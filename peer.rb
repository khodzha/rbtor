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
		@pieces_queue = []
		@downloading = false
	end

	def to_s
		"#{@socket.peeraddr[2]}\t#{@peer_choking}\t#{@peer_interested}"
	end

	def inspect
		"<#{self.to_s}>"
	end

	def start 
		thread = Thread.new do
			send_unchoking
			send_interested
			Thread.new do
				# keep alive
				@socket.send [0].pack('L')
				sleep 120
			end

			Thread.new do
				while true
					while @pieces_queue.empty?
						mutex.synchronize do
							@pieces_queue << @torrent.get_piece_for_downloading(self) if @peer_choking == false && @downloading == false
						end
						sleep 0.1
					end
					mutex.synchronize do
						send_piece_request @pieces_queue.shift
					end
				end
			end

			while true do
				sleep 0.1 while @socket.nread < 4
				message_len = @socket.recv(4).unpack('L>')[0]
				next if message_len.nil?
				sleep 0.1 while @socket.nread < message_len
				message = @socket.recv(message_len)
				message_id, payload = message.unpack('Ca*')
				puts "peer: #{self}\t#{message_len} #{message_id} #{payload.unpack('C*')}"
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
					mutex.synchronize do
						index, start, length = payload.unpack('L>L>L>')
						@socket.print @torrent.get_piece(index, start, length)
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
		puts thread.inspect
		thread
	end

	def send_bitfield
		mutex.synchronize do
			bitfield_size = (@pieces.size/8.0).ceil
			data = [ bitfield_size + 1, 5, [0]*bitfield_size].flatten
			puts "sent bitfield #{data} to #{self}"
			@socket.print data.pack('CL>C*')
		end
	end

	private

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
		data = [1, 1].pack('L>C')
		puts data.inspect
		@socket.print data
	end

	def send_interested
		data = [1, 2].pack('L>C')
		puts data.inspect
		@socket.print data
	end

	def send_request piece
		Thread.new do
			(@torrent.piece_length/(2**15.to_f)).ceil.times do |i|
				mutex.synchronize do
					data = [13, 6, piece[:index], i, 2**15]
					puts data
					@socket.print data.pack('L>CL>3')
				end
			end
		end
	end
end
