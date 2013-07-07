require './bencode'
require 'net/http'
require 'socket'

FILE_NAME = 'Continuum.torrent'

ben = Bencode.new(FILE_NAME)
data = ben.decode

params = { 	peer_id: '-RB0001-000000000001', event: 'started', info_hash: ben.info_hash.scan(/../).map(&:hex).pack('c*'),
			port: 6881, uploaded: 0, downloaded: 0, left: data[:info][:length]
		}
uri = URI data[:announce]

uri.query = URI.encode_www_form params

res = Net::HTTP.get_response(uri).body
tracker_ben = Bencode.new StringIO.new(res)
tracker_data = tracker_ben.decode
puts tracker_data[:peers].size

sockets = []


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
			sockets << socket
		end
	rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED
		puts "#{i}) #{host}:#{port} - failed"
	end
end
puts 'total connections: ' + sockets.size.to_s
while sockets.size > 0
	ready = select(sockets)
	readable = ready[0]
	readable.each do |socket|
		len = socket.recv(4).unpack('C*')
		puts len.inspect
		len = len.pack('C*').unpack('L>')[0]
		if !len
			puts "#{socket.peeraddr[2]} disconnected"
			sockets.delete socket
			socket.close
			next
		end
		puts "#{socket.peeraddr[2]} sends " + len.inspect
		if len > 0
			message_id = socket.recv 1
			puts "#{socket.peeraddr[2]} sends len: #{len.to_i}, id: #{message_id.to_i}, payload " + socket.recv(len).unpack('C*').inspect
		end
	end
end
