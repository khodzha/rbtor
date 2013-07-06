# coding: utf-8
require 'stringio'
require 'digest/sha1'

class Bencode
  attr_reader :info_hash
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

  def initialize streamlike
    @file = if streamlike.is_a?(StringIO)
      streamlike
    else
      File.open(streamlike, 'rb')
    end
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
      key = parse_str(c).to_sym
      if key == :info
        i_start = @file.pos
      end
      data[key] = parse(@file.getc)
      if key == :info
        i_end = @file.pos
        @file.seek(i_start)
        @info_hash = Digest::SHA1.hexdigest @file.read(i_end - i_start)
      end
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