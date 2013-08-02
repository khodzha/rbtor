require './torrent'

FILE_NAME = 'Defiance.torrent'

Thread.abort_on_exception = true
Torrent.new(FILE_NAME).start
