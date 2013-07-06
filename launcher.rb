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

#[truncated] Expert Info (Chat/Sequence): GET /tracker.php/6f7bef12d2f5f7bdfe1c2dc9967bc48d/announce?info_hash=%d9%a8g%f1%15%d9%07%a6U%18%0e%8f%c4%0f%9fQ%dd%00%27H&peer_id=-UT3300-%b9s%bb%811%af%a2%95%20%c6%e4P&port=13251&uploaded=0&downloa