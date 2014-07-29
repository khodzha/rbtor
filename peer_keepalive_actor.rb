class PeerKeepaliveActor
  include Celluloid

  extend Forwardable
  def_delegators :@peer, :last_send, :last_receive

  def initialize peer
    @peer = peer

    every 30 do
      if Time.now.to_i - last_send.to_i > 90
        @peer.async.touch_last_send
        @peer.async.send [0, 0, 0, 0].pack('C4')
      end

      if Time.now.to_i - last_receive.to_i > 180
        peer.async.exit
      end
    end
  end
end
