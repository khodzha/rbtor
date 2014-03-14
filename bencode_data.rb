class BencodeData
  attr_reader :info_hash, :data

  def initialize data, info_hash=nil
    @data, @info_hash = data, info_hash
    @data.freeze
    @info_hash.freeze
  end

  def [] param
    @data[param]
  end
end
