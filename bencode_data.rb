class BencodeData
  attr_reader :info_hash, :data

  def initialize data, info_hash=nil
    @data = data.freeze
    @info_hash = [info_hash].pack('H*').freeze if info_hash
  end

  def length
    data[:info][:length]
  end

  def announce
    data[:announce]
  end

  def [] param
    data[param]
  end
end
