require 'io/wait'
require 'forwardable'

class Peer
	extend Forwardable
	def_delegators :@torrent, :mutex

	def initialize(socket, pieces, piece_length, torrent)
		@socket = socket
		@am_interested = false
		@am_choking = true

		@peer_interested = false
		@peer_choking = true
		@pieces = pieces
		@piece_length = piece_length
		@torrent = torrent
		@downloading = false
		@peeraddr = @socket.peeraddr[2]
		@threads = []
	end

	def to_s
		peer_str = @peeraddr.to_s
		peer_str << "\t" if peer_str.size < 12
		"#{peer_str}\t#{@peer_choking}\t#{@peer_interested}\t"
	end

	def inspect
		"<#{self.to_s}>"
	end

	def start
		send_bitfield
		send_interested
		send_unchoking

		@threads << Thread.new do
			while true
				# keep alive
				sleep 5
				mutex.synchronize do
					data = [0].pack('L>')
					puts "KEEP ALIVE message: #{data.inspect}"
					@socket.print data
				end
			end
		end

		@threads << Thread.new do
			while true
				sleep 2
				puts "#{time} #{self} #{@socket.closed?}"
				puts "#{time} #{self} THREADS_STATUS: #{@threads.map(&:status).inspect}"
			end
		end

		@threads << Thread.new do
			while true
				mutex.synchronize do
					piece = @torrent.get_piece_for_downloading(self) if @peer_choking == false && @downloading == false
					puts "#{time}: PIECE for downloading: #{piece[:index].inspect}" if piece
					send_piece_request(piece) if piece
				end
				sleep 1
			end
		end

		@threads << Thread.new do
			while true do
				while @socket.nread < 4
					puts "#{time} #{self} bytes: #{@socket.nread.inspect}"
					sleep 1
				end
				message_len = @socket.recv(4).unpack('L>')[0]
				next if message_len.nil?
				sleep 1 while @socket.nread < message_len
				message = @socket.recv(message_len)
				message_id, payload = message.unpack('Ca*')
				puts "#{time} #{self} #{message_len} #{message_id} #{payload.unpack('C*')}"
				case message_id
				when 0
					@peer_choking = true
				when 1
					@peer_choking = false
				when 2
					@peer_interested = trueresponse
				when 3
					@peer_interested = false
				when 4
					# have
					piece_index = payload.unpack('L>')[0]
					@torrent.update_pieces self, piece_index
				when 5
					# bitfield
					bitfield_to_array payload
				when 6
					# request
					mutex.synchronize do
						index, start, length = payload.unpack('L>L>L>')
						data = @torrent.get_piece(index, start, length)
						puts "REQUEST response: " + data.inspect
						@socket.print data
					end
				when 7
					# piece
					mutex.synchronize do
						index, start, data = payload.unpack('L>L>a*')
						@torrent.save_piece index, start, data
						@downloading = false
					end
				when 8
					# cancel
				else
				end
				sleep 0.1
			end
		end
		puts "THREADS_SIZE= #{@threads.size.inspect}"
		@threads
	end

	private

	def send_bitfield
		mutex.synchronize do
			bitfield_size = (@pieces.size/8.0).ceil
			data = [ bitfield_size + 1, 5, [0]*bitfield_size].flatten
			puts "BITFIELD message: #{data}"
			@socket.print data.pack('L>C*')
		end
	end

	def send_piece_request piece
		@downloading = true
		send_request piece
	end

	def bitfield_to_array bitfield
		# OPTIMIZE need to rewrite with something like merge ?
		index = 0
		bitfield.unpack('C*').each do |byte|
			0.upto(7).each do |offset|
				if (byte & (1<<offset) == 1)
					@torrent.update_pieces self, index
				end
				index+=1
			end
		end
	end

	def send_unchoking
		mutex.synchronize do
			data = [1, 1].pack('L>C')
			puts "UNCHOKE message: " + data.inspect
			@socket.print data
		end
	end

	def send_interested
		mutex.synchronize do
			data = [1, 2].pack('L>C')
			puts "INTERESTED message: " + data.inspect
			@socket.print data
		end
	end

	def send_request piece
		3.times do |i|
			data = [13, 6, piece[:index], i*(2**15), 2**15]
			puts "REQUEST message: #{data.inspect}"
			@socket.print data.pack('L>CL>3')
		end
	end

	def time
		Time.now.strftime('%T')+"\t"
	end
end
