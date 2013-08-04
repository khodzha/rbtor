require 'net/http'
require 'socket'
require 'thread'
require 'timeout'

require './bencode'
require './peer'

class Torrent
	attr_reader :mutex, :piece_length

	def initialize filename
		@ben = Bencode.new(filename)
		@data = @ben.decode
		unpack_format = 'a20'*(@data[:info][:pieces].size/20)
		@pieces = @data[:info][:pieces].unpack(unpack_format)
		@piece_length = @data[:info][:"piece length"]
		params = { 	peer_id: '-RB0001-000000000001', event: 'started', info_hash: @ben.info_hash.scan(/../).map(&:hex).pack('c*'),
					port: 6881, uploaded: 0, downloaded: 0, left: @data[:info][:length]
				}
		@uri = URI @data[:announce]
		@uri.query = URI.encode_www_form params
		@peers = []
		@mutex = Mutex.new
		@downloaded_pieces = []
	end

	def to_s
		"#{@peers.size} #{@pieces.size} #{@downloaded_pieces.size}"
	end

	def inspect
		"<#{self.to_s}>"
	end

	def start
		puts "Connecting to #{@uri.host}"
		res = Net::HTTP.get_response(@uri).body
		tracker_ben = Bencode.new StringIO.new(res)
		@tracker_data = tracker_ben.decode
		threads = []
		@tracker_data[:peers].scan(/.{6}/).take(10).each_with_index do |x, i|
			threads << Thread.new do
				t = x.unpack('CCCCS>')
				host, port = t[0..3].join('.'), t[4]
				begin
					Timeout::timeout(5) do
						socket = TCPSocket.new(host, port)
						handshake = [19].pack('C') + 'BitTorrent protocol' + [0].pack('Q') + @ben.info_hash.scan(/../).map(&:hex).pack('c*') + '-RB0001-000000000001'
						socket.print handshake
						data = socket.recv 49+19
						response = data.unpack 'CA19Q>C20C20'
						if response[0] == 19
							puts response.inspect
							@mutex.synchronize do
								@peers << Peer.new(socket, @pieces, @piece_length, self)
							end
						end
					end
				rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
					puts "#{host}:#{port} - failed"
				end
			end
		end
		threads.map &:join
		puts 'total connections: ' + @peers.size.to_s
		exit if @peers.size == 0
		@pieces = @pieces.each_with_index.inject([]) {|r, (v, index)| r[index] = {hashsum: v, peers: [], peers_have: 0, index: index, downloading: false}; r}
		@peers.map(&:start).flatten.map &:join
	end

	def update_pieces peer, piece_index
		piece = @pieces[piece_index]
		@mutex.synchronize do
			if piece && !piece[:peers].include?(peer)
				piece[:peers] << peer
				piece[:peers_have] += 1
			end
		end
	end

	def save_piece peer, index, start, data
		puts "SAVE PIECE #{index} #{start}"
		@downloaded_pieces << @pieces[index]
		File.open('./' + @pieces[index][:hashsum].each_byte.map{|b| "%02X"%b}.join + '.tmp', File::CREAT|File::BINARY|File::WRONLY) do |f|
			f.seek(start)
			f.write(data)
		end
		(@peers-[peer]).each{|x| x.send_have(index)}
	end

	def get_piece index, start, length
		@mutex.synchronize do
			file_name = './' + @pieces[index][:hashsum].each_byte.map{|b| "%02x"%b}.join + '.tmp'
			File.read(file_name, length, start)
		end
	end

	def get_piece_for_downloading peer
		piece = @pieces.select{|x| x[:peers].include?(peer) && x[:downloading] == false}.sort_by{|x| -x[:peers_have]}.first
		piece[:downloading] = true
		piece
	end
end
