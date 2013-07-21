require 'net/http'
require 'socket'
require 'thread'

require './bencode'
require './peer'

class Launcher
	def initialize filename
		@ben = Bencode.new(filename)
		@data = @ben.decode
		@pieces = @data[:info][:pieces].scan(/.{20}/)
		@piece_length = @data[:info][:"piece length"]
		params = { 	peer_id: '-RB0001-000000000001', event: 'started', info_hash: @ben.info_hash.scan(/../).map(&:hex).pack('c*'),
					port: 6881, uploaded: 0, downloaded: 0, left: @data[:info][:length]
				}
		@uri = URI @data[:announce]
		@uri.query = URI.encode_www_form params
		@peers = []
	end

	def start
		res = Net::HTTP.get_response(@uri).body
		tracker_ben = Bencode.new StringIO.new(res)
		@tracker_data = tracker_ben.decode

		mutex = Mutex.new

		@tracker_data[:peers].scan(/.{6}/).take(10).each do |x|
			thread = Thread.new do
				t = x.unpack('CCCCS>')
				host, port = t[0..3].join('.'), t[4]
				begin
					socket = TCPSocket.new(host, port)
					handshake = [19].pack('C') + 'BitTorrent protocol' + [0].pack('Q') + @ben.info_hash.scan(/../).map(&:hex).pack('c*') + '-RB0001-000000000001'
					socket.puts handshake
					data = socket.recv 49+19
					response = data.unpack 'CA19QC20C20'
					if response[0] == 19
						mutex.synchronize do
							@peers << Peer.new(socket, @pieces, @piece_length)
						end
					end
				rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED
					puts "#{host}:#{port} - failed"
				end
			end
			thread.join
		end
		while Thread.list.count > 1
			sleep 5
		end
		puts 'total connections: ' + @peers.size.to_s
		@peers.each{|x| x.start.join}
	end
end
