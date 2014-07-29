require 'net/http'
require 'socket'
require 'thread'
require 'timeout'
require 'fileutils'
require 'byebug'
require 'forwardable'

require 'celluloid/autostart'

require './bencode'
require './peer_actor'
require './server_actor'
require './pieces_actor'

class TorrentActor
  attr_reader :data, :server_actor, :pieces_actor
  include Celluloid

  extend Forwardable
  def_delegators :pieces_actor, :downloaded_pieces, :pieces, :add_peer_to_piece
  def_delegators :data, :piece_length

  def initialize filename
    @data = Bencode.new(filename).decode
    @server_actor = ServerActor.new
    set_torrent_data
  end

  def to_s
    "#{@peers.size}"
  end
  def inspect; to_s; end

  def start
    now_and_every 300 do
      if downloaded_pieces.size < pieces.size

        peers_response = server_actor.announce data.announce, data.info_hash, downloaded_size, left_size
        puts "peers_response, #{peers_response.inspect}"
        peers_response.each_with_index do |x, i|
          host, port = x[0..3].join('.'), ((x[4]<<8)+x[5]).to_s
          unless Actor[host]
            Actor[host] = PeerActor.new host, port, self
            Actor[host].async.start
          end
        end
      else
        shutdown
      end
    end
    Kernel.sleep()
  end

  def save_piece peer, index, start, data
    puts "SAVE PIECE #{index} #{start}"
    piece = @pieces[index]
    block_index = start / PeerActor::BLOCK_SIZE

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
      piece[:blocks_downloaded] = [:not_downloaded] * ( piece_length.to_f / PeerActor::BLOCK_SIZE ).ceil
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

  def set_torrent_data
    unpack_format = 'a20'*(data[:info][:pieces].size/20)
    @pieces_actor = PiecesActor.new data[:info][:pieces].unpack(unpack_format), piece_length

    @peers = []
    @hosts = []
  end

  def downloaded_size
    downloaded_pieces.size * piece_length
  end

  def left_size
    data.length - downloaded_size
  end

  def join_pieces
    File.open('./' + @data[:info][:name]) do |f|
      @pieces.each do |piece|
        file_name = './tmp/' + piece[:index].to_s + '_' + piece[:hashsum].each_byte.map{|b| "%02x"%b}.join + '.tmp'
        f.print File.read(file_name)
      end
    end
  end

  def shutdown
    # TODO: finish this method
    join_pieces
    terminate
  end

  def now_and_every time, &block
    block.call
    every time, &block
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
