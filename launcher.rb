require 'net/http'
require 'socket'

require './bencode'
require './peer'
FILE_NAME = 'Defiance.torrent'

ben = Bencode.new(FILE_NAME)
data = ben.decode
pieces = data[:info][:pieces].scan(/.{20}/)).size
piece_length = data[:info][:"piece length"]
params = { 	peer_id: '-RB0001-000000000001', event: 'started', info_hash: ben.info_hash.scan(/../).map(&:hex).pack('c*'),
			port: 6881, uploaded: 0, downloaded: 0, left: data[:info][:length]
		}
uri = URI data[:announce]

uri.query = URI.encode_www_form params

res = Net::HTTP.get_response(uri).body
tracker_ben = Bencode.new StringIO.new(res)
tracker_data = tracker_ben.decode
puts tracker_data[:peers].size

peers = []

puts 'hash = ' + ben.info_hash.scan(/../).map(&:hex).inspect
tracker_data[:peers].scan(/.{6}/).take(10).each_with_index do |x, i|
	t = x.unpack('CCCCS>')
	host, port = t[0..3].join('.'), t[4]
	begin
		socket = TCPSocket.new(host, port)
		handshake = [19].pack('C') + 'BitTorrent protocol' + [0].pack('Q') + ben.info_hash.scan(/../).map(&:hex).pack('c*') + '-RB0001-000000000001'
		socket.puts handshake
		data = socket.recv 49+19
		response = data.unpack 'CA19QC20C20'
		if response[0] == 19
			puts response.inspect
			puts "#{i}) #{host}:#{port} - succeeded"
			peers << Peer.new(socket)
		end
	rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED
		puts "#{i}) #{host}:#{port} - failed"
	end
end
puts 'total connections: ' + peers.size.to_s
peers.each{|x| x.start(pieces, piece_length).join}