class Piece
  attr_accessor :state
  attr_reader :index

  def initialize hashsum, index, piece_length
    @hashsum = hashsum
    @peers = []
    @peers_have = 0
    @index = index
    @state = :pending
    @piece_length = piece_length
    @blocks_downloaded = [:not_downloaded] * ( @piece_length.to_f / PeerActor::BLOCK_SIZE ).ceil
  end

  def add_peer peer
    return if has_peer? peer
    @peers << peer
    @peers_have += 1
  end

  def downloaded?
    !@blocks_downloaded.any?{|x| x == :not_downloaded}
  end

  def available_block
    index = @blocks_downloaded.find_index(:not_downloaded)
    @blocks_downloaded[index] = :in_progress
    index
  end

  private
  def has_peer? peer
    @peers.include? peer
  end
end
