# coding: utf-8
require 'stringio'

FILE_TITLE = 'HMM3.torrent'

def parse c
	if c == 'd'
		parse_dict
	elsif c == 'l'
		parse_arr
	elsif c == 'i'
		parse_int
	else
		parse_str c
	end
end

def parse_int
	var = $file.readline("e").to_i
	var
end

def parse_str str
	len = (str + $file.readline(":").gsub(":", "")).to_i
	s = $file.read(len)
end

def parse_dict
	data = {}
	until (c = $file.getc) == 'e'
		data[parse_str(c).to_sym] = parse($file.getc)
	end
	data
end

def parse_arr
	data = []
	until (c = $file.getc) == 'e'
		data << parse(c)
	end
	data
end

$data = nil

$file = File.open(FILE_TITLE, "rb")
until $file.eof?
	c = $file.getc
	$data = parse(c)
end

puts $data.inspect
