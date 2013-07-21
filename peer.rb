class Peer
	def initialize(socket, pieces, piece_length)
		@socket = socket
		@am_interested = false
		@am_choking = true

		@peer_interested = false
		@peer_choking = true
		@pieces = pieces.each_with_index.inject([]) {|r, (v, index)| r[index] = {hashsum: v, have: false}; r}
		@piece_length = piece_length
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
				message = @socket.recv(message_len, Socket::MSG_WAITALL)
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
					piece_index = message.unpack('C')[0]
					@pieces[piece_index][:have] = true if @pieces[piece_index]
				when 5
					# bitfield
					bitfield_to_array message
				when 6
					#request
				when 7
					# piece
				when 8
					# cancel
				end
			end
		end
		puts thread.inspect
		thread
	end

	private

	def bitfield_to_array bitfield
		index = 0
		bitfield.unpack('C*').each do |byte|
			0.upto(7).each do |offset|
				if @pieces[index] && (byte & (1<<offset) == 1)
					@pieces[index][:have] = true
				end
				index+=1
			end
		end

		puts "peer has #{ @pieces.inject(0){|r, v| v[:have] == true ? r + 1 : r} } pieces"
	end
end