require './bencode'
require 'net/http'

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

tracker_data[:peers].scan(/.{6}/).each do |x|
	t = x.unpack('CCCCS>')
	puts t[0..3].join('.')+':' + t[4].to_s
end
