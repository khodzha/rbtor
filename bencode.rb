# coding: utf-8
require 'stringio'

class Bencode
  def new filename
    if filename.is_a? StringIO
      initialize filename
    else
      initialize File.open(filename, 'rb')
    end
  end

  def self.from_string str
    Bencode.new StringIO.new(str)
  end

  def decode
    until @file.eof?
      c = @file.getc
      @data = parse(c)
    end
    @data
  end

  private

  def initialize stream
    @file = stream
    @data = nil
  end

  def parse c
    case c
    when 'd' then parse_dict
    when 'l' then parse_arr
    when 'i' then parse_int
    else parse_str c
    end
  end

  def parse_int
    var = @file.readline("e").to_i
    var
  end

  def parse_str str
    len = (str + @file.readline(":").gsub(":", "")).to_i
    s = @file.read(len)
  end

  def parse_dict
    data = {}
    until (c = @file.getc) == 'e'
      data[parse_str(c).to_sym] = parse(@file.getc)
    end
    data
  end

  def parse_arr
    data = []
    until (c = @file.getc) == 'e'
      data << parse(c)
    end
    data
  end

end