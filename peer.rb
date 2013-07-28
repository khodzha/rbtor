class Peer
	def initialize(socket, pieces, piece_length, torrent)
		@socket = socket
		@am_interested = false
		@am_choking = true

		@peer_interested = false
		@peer_choking = true
		@pieces = pieces
		@piece_length = piece_length
		@torrent = torrent
	end

	def start 
		thread = Thread.new do
			puts "starting data transmission for #{@socket.peeraddr[2]}"
			Thread.new do
				# keep alive
				@socket.send [0].pack('L')
				sleep 120
			end

			while true do
				message_len = @socket.recv(4, Socket::MSG_WAITALL).unpack('L>')[0]
				next if message_len.nil?
				message = @socket.recv(message_len, Socket::MSG_WAITALL)
				puts "peer = #{self.to_s}"
				puts "message_len = #{message_len}"
				puts "message= #{message.unpack('C*')}"
				case message.bytes[0]
				when 0
					@peer_choking = true
				when 1
					@peer_choking = false
				when 2
					@peer_interested = true
				when 3
					@peer_interested = false
				when 4
					# have
					piece_index = message.unpack('C')[0]
					@torrent.update_pieces self, piece_index
				when 5
					# bitfield
					bitfield_to_array message
				when 6
					# request
					index, start, length = message.unpack('L>L>L>')
					@socket.puts @torrent.get_piece(index, start, length)
				when 7
					# piece
					index, start, data = message.unpack('L>L>a*')
					@torrent.save_piece index, start, data
				when 8
					# cancel
				else
				end
				sleep 5
			end
		end
		puts thread.inspect
		thread
	end

	private

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
end
