require 'io/wait'

class PeerActor
  include Celluloid
  include Celluloid::Logger

  attr_reader :peer_choking, :peer_interested, :am_interested, :am_choking
  attr_reader :last_send, :last_receive, :torrent

  BLOCK_SIZE = 2**14
  MAX_REQUESTS = 5

  extend Forwardable
  def_delegators :torrent, :piece_length, :pieces

  def initialize host, port, torrent
    @host = host
    @port = port
    @socket = nil
    @am_interested = false
    @am_choking = true

    @peer_interested = false
    @peer_choking = true

    @torrent = torrent
    @last_send = Time.now
    @last_receive = Time.now
    @downloading_piece = nil
    @current_requests = 0
    @shutdown_flag = false
  end

  def to_s
    "#{@host.to_s}\tchoke: #{@peer_choking} int: #{@peer_interested}\t"
  end
  def inspect; to_s; end

  def start
    unless send_handshake
      terminate
    end

    send_bitfield
    send_interested
    send_unchoking

    @keepalive_actor = PeerKeepaliveActor.new self
    @download_actor = PeerDownloadactor.new self

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
          @torrent.add_peer_to_piece self, piece_index
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
  end

  def send_have index
    data = [5, 4, index].pack('L>CL>')
    send data
  end

  def touch_last_send
    @last_send = Time.now
  end

  def touch_last_receive
    @last_receive = Time.now
  end

  def increase_requests
    @current_requests += 1
  end

  private

  def send_bitfield
    touch_last_send
    bitfield_size = (pieces.size/8.0).ceil

    bitfield = pieces.each_slice(8).map do |slice|
      slice.each_with_index.inject(0) do |sum, (el, index)|
        sum | ((el.state == :downloaded ? 1 : 0)<<(7 - index))
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
          @torrent.add_peer_to_piece self, index
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
