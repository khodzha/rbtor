class Peer
	def initialize(socket)
		@socket = socket
		@am_interested = false
		@am_choking = true

		@peer_interested = false
		@peer_choking = true
	end

	def start pieces, piece_length
		Thread.new do
			puts "starting data transmission for #{@socket.peeraddr[2]}"
			Thread.new do
				@socket.send [0].pack('L')
				sleep 120
			end

			while true do
				message_len = @socket.recv(4, MSG_WAITALL).unpack('L>')
				message = @socket.recv(message_len, MSG_WAITALL)
				case message[0]
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
				when 5
					# bitfield
				when 6
					#request
				when 7
					# piece
				when 8
					# cancel
				end
			end
		end
	end
end