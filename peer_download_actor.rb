class PeerDownloadActor
  include Celluloid

  extend Forwardable
  def_delegators :@peer, :peer_choking, :current_requests, :torrent

  def initialize peer
    @peer = peer
    @downloading_piece = nil

    every 1 do
      unless peer_choking
        @downloading_piece = torrent.get_piece_for_downloading self if @downloading_piece.nil? || !@downloading_piece.downloaded?
        if @downloading_piece && @current_requests < MAX_REQUESTS
          send_requests
        end
      end
    end
  end

  private
  def send_requests
    (MAX_REQUESTS - @current_requests).times do |i|
      index = @downloading_piece.available_block
      data = [13, 6, @downloading_piece.index, index*BLOCK_SIZE, BLOCK_SIZE]
      @peer.async.send data.pack('L>CL>3')
      @peer.async.increate_requests
    end

    @peer.async.touch_last_send
  end

end
