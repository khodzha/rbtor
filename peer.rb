require 'io/wait'
require 'forwardable'

class Peer
  include Celluloid
  include Celluloid::Logger

  attr_reader :peer_choking, :peer_choking, :am_interested, :am_choking

  BLOCK_SIZE = 2**14
  MAX_REQUESTS = 5

  def initialize host, port, pieces, piece_length, torrent
    @host = host
    @port = port
    @socket = nil
    @am_interested = false
    @am_choking = true

    @peer_interested = false
    @peer_choking = true
    @pieces = pieces
    @piece_length = piece_length
    @torrent = torrent
    @threads = []
    @last_send = Time.now
    @last_receive = Time.now
    @downloading_piece = nil
    @current_requests = 0
    @shutdown_flag = false
  end

  def to_s
    peer_str = @peeraddr.to_s
    peer_str << "\t" if peer_str.size < 12
    "#{peer_str}\t#{@peer_choking}\t#{@peer_interested}\t"
  end

  def inspect
    "<#{self.to_s}>"
  end

  def start
    unless send_handshake
      terminate
    end

    send_bitfield
    send_interested
    send_unchoking

    @threads << Thread.new do
      until @shutdown_flag
        # keep alive
        sleep 30
        if Time.now.to_i - @last_send.to_i > 90
          mutex.synchronize do
            @last_send = Time.now
          end
          data = [0, 0, 0, 0].pack('C4')
          send data
        end
        if Time.now.to_i - @last_receive.to_i > 180
          exit
        end
      end
    end

    @threads << Thread.new do
      until @shutdown_flag
        if @peer_choking == false
          if @downloading_piece.nil? || ( @current_requests < MAX_REQUESTS && @downloading_piece[:blocks_downloaded].any?{|x| x == :not_downloaded} )
            @downloading_piece = @torrent.get_piece_for_downloading self unless @downloading_piece
            if @downloading_piece
              send_requests unless @shutdown_flag
            end
          end
        end
        sleep 1
      end
    end

    @threads << Thread.new do
      until @shutdown_flag
        begin
          @socket.wait_readable
          while @socket.nread < 4
            sleep 1
          end
          message_len = @socket.recv(4).unpack('L>')[0]
          next if message_len.nil?
          message = receive_message message_len
        rescue
          exit
          break
        end
        message_id, payload = message.unpack('Ca*')
        case message_id
        when 0
          @peer_choking = true
        when 1
          @peer_choking = false
        when 2
          @peer_interested = true
        when 3
          @peer_interested = false
        when 4
          # have
          piece_index = payload.unpack('L>')[0]
          @torrent.update_pieces self, piece_index
        when 5
          # bitfield
          bitfield_to_array payload
        when 6
          # request
          index, start, length = payload.unpack('L>L>L>')
          data = @torrent.get_piece(index, start, length)
          send data
        when 7
          # piece
          index, start, data = payload.unpack('L>L>a*')
          mutex.synchronize do
            @torrent.save_piece self, index, start, data
            @current_requests -= 1
            @downloading_piece = nil if @current_requests == 0 && @downloading_piece[:blocks_downloaded].all?{|x| x == :downloaded}
          end
          @torrent.announce_have self, index
        when 8
          # cancel
        else
        end
      end
    end
    @threads
  end

  def send_have index
    data = [5, 4, index].pack('L>CL>')
    send data
  end

  private

  def send_bitfield
    mutex.synchronize do
      @last_send = Time.now
    end
    bitfield_size = (@pieces.size/8.0).ceil

    bitfield = @pieces.each_slice(8).map do |slice|
      slice.each_with_index.inject(0) do |sum, (el, index)|
        sum | ((el[:state] == :downloaded ? 1 : 0)<<(7 - index))
      end
    end
    data = [ bitfield_size + 1, 5, bitfield].flatten
    send data.pack('L>C*')
  end

  def bitfield_to_array bitfield
    # OPTIMIZE need to rewrite with something like merge ?
    index = 0
    bitfield.unpack('C*').each do |byte|
      7.downto(0).each do |offset|
        if (byte & (1<<offset) != 0)
          @torrent.update_pieces self, index
        end
        index+=1
      end
    end
  end

  def send_unchoking
    mutex.synchronize do
      @last_send = Time.now
    end
    data = [1, 1].pack('L>C')
    send data
  end

  def send_interested
    mutex.synchronize do
      @last_send = Time.now
    end
    data = [1, 2].pack('L>C')
    send data
  end

  def send_requests
    (MAX_REQUESTS - @current_requests).times do |i|
      index = @downloading_piece[:blocks_downloaded].find_index(:not_downloaded)
      break if index.nil?
      mutex.synchronize do
        @downloading_piece[:blocks_downloaded][index] = :in_progress
      end
      data = [13, 6, @downloading_piece[:index], index*BLOCK_SIZE, BLOCK_SIZE]
      send data.pack('L>CL>3')
      mutex.synchronize do
        @current_requests += 1
      end
    end

    mutex.synchronize do
      @last_send = Time.now
    end
  end

  def time
    Time.now.strftime('%T')+"\t"
  end

  def receive_message message_len
    message = ''
    while message_len > 0
      @socket.wait_readable
      buf = @socket.recv message_len
      message_len -= buf.size
      message << buf
    end
    @last_receive = Time.now
    message
  end

  def exit
    mutex.synchronize do
      @downloading_piece[:state] = :pending if @downloading_piece
      @torrent.remove_peer self, @peeraddr
      @shutdown_flag = true
      begin
        @socket.close
      rescue IOError => e
        error e.message
      end
    end
  end

  def send data
    begin
      @socket.print data unless @shutdown_flag
    rescue
      exit
    end
  end

  def send_handshake
    begin
      @socket = TCPSocket.new(@host, @port)
      @peeraddr = @socket.peeraddr[2]

      handshake = [19].pack('C') + 'BitTorrent protocol' + [0].pack('Q') + @torrent.data.info_hash.scan(/../).map(&:hex).pack('c*') + '-RB0001-000000000001'
      @socket.print handshake
      response = @socket.recv(49+19).unpack 'CA19Q>C20C20'
      if response[0] == 19
        debug "#{@host}:#{@port} - success"
        return true
      end

    rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, 
            Errno::EADDRNOTAVAIL, Timeout::Error
      debug "#{@host}:#{@port} - failed"
    end
    debug "#{@host}:#{@port} - not success"
    false
  end
end
