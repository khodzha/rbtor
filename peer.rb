require 'io/wait'

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
				sleep 0.1 while @socket.nread < 4
				message_len = @socket.recv(4).unpack('L>')[0]
				next if message_len.nil?
				sleep 0.1 while @socket.nread < message_len
				message = @socket.recv(message_len)
				message_id, payload = message.unpack('Ca*')
				puts "message #{message_id} #{payload.unpack('C*')}"
				case message_id
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
					piece_index = payload.unpack('L>')[0]
					@torrent.update_pieces self, piece_index
				when 5
					# bitfield
					bitfield_to_array payload
				when 6
					# request
					index, start, length = payload.unpack('L>L>L>')
					@socket.puts @torrent.get_piece(index, start, length)
				when 7
					# piece
					index, start, data = payload.unpack('L>L>a*')
					@torrent.save_piece index, start, data
				when 8
					# cancel
				else
				end
				sleep 0.1
			end
		end
		puts thread.inspect
		thread
	end

	def download piece
		send_interested
		send_request piece
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

	def send_interested
		@socket.print [1, 2].pack('L>C')
	end

	def send_request piece
		Thread.new do
			(@torrent.piece_length/(2**15.to_f)).ceil.times do |i|
				@torrent.mutex.synchronize do
					data = [13, 6, piece[:index], i, 2**15]
					puts data
					@socket.print data.pack('L>CL>3')
				end
			end
		end
	end
end
