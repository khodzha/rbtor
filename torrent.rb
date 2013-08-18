require 'net/http'
require 'socket'
require 'thread'
require 'timeout'
require 'fileutils'

require './bencode'
require './peer'

class Torrent
  attr_reader :mutex, :piece_length

  def initialize filename
    @ben = Bencode.new(filename)
    @data = @ben.decode

    unpack_format = 'a20'*(@data[:info][:pieces].size/20)
    @pieces = @data[:info][:pieces].unpack(unpack_format)
    @piece_length = @data[:info][:"piece length"]

    @peers = []
    @mutex = Mutex.new
    @downloaded_pieces = []
    @tracker_data = nil
    @hosts = []
  end

  def to_s
    "#{@peers.size} #{@pieces.size} #{@downloaded_pieces.size}"
  end

  def inspect
    "<#{self.to_s}>"
  end

  def start
    Thread.new do
      loop do
        puts eval(gets.chomp).inspect
        sleep 1
      end
    end

    new_peers = []
    threads = []

    @pieces = @pieces.each_with_index.inject([]) {|r, (v, index)| r[index] = {hashsum: v, peers: [], peers_have: 0, index: index, state: :pending}; r}
    @pieces.each do |piece|
      piece[:blocks_downloaded] = [:not_downloaded] * ( @piece_length.to_f / Peer::BLOCK_SIZE ).ceil
    end

    Dir['./tmp/*'].select{|x| File::size?(x) == @piece_length}.each do |filename|
      filename = File.basename(filename)
      @pieces[filename.split('_').first.to_i][:state] = :downloaded
      @pieces[filename.split('_').first.to_i][:blocks_downloaded].map!{|x| :downloaded}
      @downloaded_pieces << @pieces[filename.split('_').first.to_i]
    end

    while @downloaded_pieces.size < @pieces.size

      params = {  peer_id: '-RB0001-000000000001', event: 'started', info_hash: @ben.info_hash.scan(/../).map(&:hex).pack('c*'),
            port: 6881, uploaded: 0, downloaded: @downloaded_pieces.size * @piece_length, left: @data[:info][:length] - @downloaded_pieces.size * @piece_length
          }
      @uri = URI @data[:announce]
      @uri.query = URI.encode_www_form params

      puts "Connecting to #{@uri.host}"
      begin
        res = Net::HTTP.get_response(@uri).body
      rescue Errno::ETIMEDOUT
        redo
      end
      tracker_ben = Bencode.new StringIO.new(res)
      @tracker_data = tracker_ben.decode

      @tracker_data[:peers][0, 120].unpack('C*').each_slice(6).each_with_index do |x, i|
        threads << Thread.new do
          host, port = x[0..3].join('.'), ((x[4]<<8)+x[5]).to_s
          unless @hosts.include?(host)
            begin
              Timeout::timeout(5) do
                socket = TCPSocket.new(host, port)
                handshake = [19].pack('C') + 'BitTorrent protocol' + [0].pack('Q') + @ben.info_hash.scan(/../).map(&:hex).pack('c*') + '-RB0001-000000000001'
                socket.print handshake
                data = socket.recv 49+19
                response = data.unpack 'CA19Q>C20C20'
                if response[0] == 19
                  @mutex.synchronize do
                    new_peers << Peer.new(socket, @pieces, @piece_length, self)
                    @hosts << host
                  end
                end
              end
            rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, 
                    Errno::EADDRNOTAVAIL, Timeout::Error
              puts "#{host}:#{port} - failed"
            end
          else
            puts "#{host}:#{port} - was there"
          end
        end
      end

      threads.map(&:join)
      threads.clear

      new_peers.map(&:start)
      @peers.concat new_peers
      new_peers.clear

      sleep 60*( @hosts.size < 5 ? @hosts.size : 5 )
    end

    join_pieces
  end

  def update_pieces peer, piece_index
    piece = @pieces[piece_index]
    @mutex.synchronize do
      if piece && !piece[:peers].include?(peer)
        piece[:peers] << peer
        piece[:peers_have] += 1
      end
    end
  end

  def save_piece peer, index, start, data
    puts "SAVE PIECE #{index} #{start}"
    piece = @pieces[index]
    block_index = start / Peer::BLOCK_SIZE

    piece[:blocks_downloaded][block_index] = :downloaded
    piece_downloaded = piece[:blocks_downloaded].all?{|x| x == :downloaded}

    filename = './tmp/' + index.to_s + '_' + @pieces[index][:hashsum].each_byte.map{|b| "%02x"%b}.join + '.tmp'
    File.open(filename, File::CREAT|File::BINARY|File::WRONLY) do |f|
      f.seek(start)
      f.write(data)
    end

    if piece_downloaded && validate_sha(filename)
      @downloaded_pieces << @pieces[index]
    elsif piece_downloaded
      piece[:blocks_downloaded] = [:not_downloaded] * ( @piece_length.to_f / Peer::BLOCK_SIZE ).ceil
      piece[:state] = :downloaded
    end
  end

  def announce_have except_peer, index
    (@peers-[except_peer]).each{|x| x.send_have(index)}
  end

  def get_piece index, start, length
    @mutex.synchronize do
      file_name = './tmp/' + index.to_s + '_'  + @pieces[index][:hashsum].each_byte.map{|b| "%02x"%b}.join + '.tmp'
      File.read(file_name, length, start)
    end
  end

  def get_piece_for_downloading peer
    piece = nil
    @mutex.synchronize do
      piece = (@pieces - @downloaded_pieces).select{|x| x[:peers].include?(peer) && x[:state] == :pending}.sort_by{|x| x[:peers_have]}.first
      piece[:state] = :downloading if piece
    end
    puts "PIECE INSPECT: #{piece.inspect}" if false
    piece
  end

  def remove_peer peer, host
    puts "HOST REMOVAL: #{host.inspect}, #{@hosts.index(host).inspect}"
    @pieces.select{|x| x[:peers].include?(peer)}.each do |piece|
      piece[:peers].delete(peer)
      piece[:peers_have] -= 1
      piece[:blocks_downloaded].map!{|x| (x == :in_progress ? :not_downloaded : x)}
    end
    @peers.delete(peer)
    @hosts.delete(host)
  end

  private

  def join_pieces
    File.open('./' + @data[:info][:name]) do |f|
      @pieces.each do |piece|
        file_name = './tmp/' + piece[:index].to_s + '_' + piece[:hashsum].each_byte.map{|b| "%02x"%b}.join + '.tmp'
        f.print File.read(file_name)
      end
    end
  end

  def validate_sha filename
    if Digest::SHA1.file(filename).hexdigest != File.basename(filename, '.tmp').split('_').last
      FileUtils.rm_f filename
      false
    else
      true
    end
  end
end
