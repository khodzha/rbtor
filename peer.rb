require 'io/wait'
require 'forwardable'

$logging = false

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
		@last_send = Time.now
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
				sleep 30
				if Time.now.to_i - @last_send.to_i > 90
					mutex.synchronize do
						@last_send = Time.now
					end
					data = [0, 0, 0, 0].pack('C4')
					puts "KEEP ALIVE message: #{data.inspect}"
					@socket.print data
				end
			end
		end

		@threads << Thread.new do
			while true
				sleep 2
				puts "#{time} #{self} #{@socket.closed?}" if $logging
				puts "#{time} #{self} THREADS_STATUS: #{@threads.map(&:status).inspect}" if $logging
			end
		end

		@threads << Thread.new do
			while true
				if @peer_choking == false && @downloading == false
					piece = @torrent.get_piece_for_downloading self
					if piece
						puts "#{time} #{self} PIECE DL index: #{piece[:index].inspect}"
						send_piece_request piece
					end
				end
				sleep 1
			end
		end

		@threads << Thread.new do
			while true do
				@socket.wait_readable
				puts "#{time} #{self} bytes: #{@socket.nread.inspect}"
				while @socket.nread < 4
					sleep 1
				end
				message_len = @socket.recv(4).unpack('L>')[0]
				next if message_len.nil?
				puts "MESSAGE_LEN: #{message_len}"
				message = receive_message message_len
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
					index, start, length = payload.unpack('L>L>L>')
					data = @torrent.get_piece(index, start, length)
					puts "REQUEST response: " + data.inspect
					@socket.print data
				when 7
					# piece
					index, start, data = payload.unpack('L>L>a*')
					mutex.synchronize do
						@torrent.save_piece self, index, start, data
						@downloading = false
					end
				when 8
					# cancel
				else
				end
			end
		end
		puts "THREADS_SIZE= #{@threads.size.inspect}"
		@threads
	end

	def send_have index
		data = [5, 4, index].pack('L>CL>')
		@socket.print data
	end

	private

	def send_bitfield
		mutex.synchronize do
			@last_send = Time.now
		end
		bitfield_size = (@pieces.size/8.0).ceil
		data = [ bitfield_size + 1, 5, [0]*bitfield_size].flatten
		puts "BITFIELD message: #{data}"
		@socket.print data.pack('L>C*')
	end

	def send_piece_request piece
		mutex.synchronize do
			@downloading = true
		end
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
			@last_send = Time.now
		end
		data = [1, 1].pack('L>C')
		puts "UNCHOKE message: " + data.inspect
		@socket.print data
	end

	def send_interested
		mutex.synchronize do
			@last_send = Time.now
		end
		data = [1, 2].pack('L>C')
		puts "INTERESTED message: " + data.inspect
		@socket.print data
	end

	def send_request piece
		3.times do |i|
			data = [13, 6, piece[:index], i*(2**14), 2**14]
			puts "REQUEST message: #{data.inspect}"
			@socket.print data.pack('L>CL>3')
		end
		mutex.synchronize do
			@last_send = Time.now
		end
	end

	def time
		Time.now.strftime('%T')+"\t"
	end

	def receive_message message_len
		message = ''
		while message_len > 0
			@socket.wait_readable
			buf = @socket.recv message_len
			message_len -= buf.size
			message << buf
		end
		message
	end
end
