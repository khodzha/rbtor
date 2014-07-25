class ServerActor
  include Celluloid

  def announce announce_url, info_hash, downloaded, left
    # TODO: implement :event key
    params = {  peer_id: '-RB0001-000000000001', event: :started, info_hash: info_hash,
              port: 6881, uploaded: 0, downloaded: downloaded, left: left
            }
    uri = URI announce_url
    uri.query = URI.encode_www_form params

    res = Net::HTTP.get_response(uri).body

    tracker_ben = Bencode.new StringIO.new(res)
    tracker_data = tracker_ben.decode
    tracker_data[:peers][0, 120].unpack('C*').each_slice(6).to_a
  end
end
