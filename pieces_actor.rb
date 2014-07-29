require './piece'

class PiecesActor
  include Celluloid
  attr_reader :downloaded_pieces, :pieces

  def initialize pieces_data, piece_length
    @pieces = pieces_data.each_with_index.map do |hashsum, ind|
      Piece.new hashsum, ind, piece_length
    end

    @downloaded_pieces = []
    check_loaded_pieces
  end

  def add_peer_to_piece peer, piece_index
    @pieces[piece_index].add_peer peer
  end

  private
  def check_loaded_pieces
    Dir['./tmp/*'].select{|x| File::size?(x) == data.piece_length}.each do |filename|
      filename = File.basename(filename)
      index = File.basename(filename).split('_').first.to_i
      @pieces[index].state = :downloaded
      @downloaded_pieces << @pieces[index]
    end
  end
end
