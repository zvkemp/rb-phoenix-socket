require 'socket'
require 'websocket'
require 'uri'
require 'json'
require 'phoenix/inbox'
require 'securerandom'

module Phoenix
  class SocketHandler
    attr_reader :uri, :socket, :url, :loop, :open

    attr_accessor :verbose

    def initialize(url = 'ws://localhost:4000/socket/websocket')
      @url = url
      @uri = URI.parse(url)
      @socket = TCPSocket.new(uri.host, uri.port)
      @handshaken = do_handshake
      @loop = Thread.new do
        Thread.current[:id] = "loop_#{SecureRandom.hex(3)}"
        receive_data
      end

      @verbose = true
    end

    def send_data(data)
      # socket.flush # for some reason it takes longer to get to a broken pipe error unless we flush
                   # here first.
      fr = WebSocket::Frame::Outgoing::Client.new(data: data, type: :text, version: handshake.version)
      socket.write(fr.to_s)
      socket.flush
    rescue Errno::EPIPE => e
      close
      raise
    end

    def handle_message
      @message_handler = Proc.new
    end

    def handle_close
      @close_handler = Proc.new
    end

    def r
      load 'lib/phoenix/socket_handler.rb'
    end

    def j
      { topic: "stat:default", event: "phx_join", payload: {}, ref: SecureRandom.uuid, join_ref: SecureRandom.uuid }.to_json
    end

    def close(skip_handler = false)
      log "CLOSING..."
      @open = false
      @socket&.close
      @socket = nil
      @handshaken = false
      @close_handler.call unless skip_handler
    end

    def log(msg)
      return unless verbose
      puts "\e[36m[#{Thread.current[:id] || Thread.current}][#{Time.now.to_f}] #{msg}\e[0m"
    end

    # private

    def do_handshake
      @socket.write(handshake.to_s)
      @socket.flush
      while char = @socket.getc
        @handshake << char
        break (@open = true) if @handshake.finished?
      end
    end

    def receive_data
      l = 1
      log "RECEIVE START"
      while @open && (char = socket.recv(1))
        # log char
        incoming << char

        if msg = incoming.next
          log("MSG")
          do_handle_message(msg)
        end
      end
      log "RECEIVE CLOSED"
      close
      raise 'closed'
    rescue Errno::EPIPE => e
      log "RECEIVE CLOSED in rescue:"
      close
    # rescue IO::EAGAINWaitReadable, IO::WaitReadable, Errno::EWOULDBLOCK
    #   IO.select([socket], [], [], timeou)
    #   retry
    end

    def do_handle_message(msg)
      return close if msg.type == :close
      @message_handler.call(msg)
    end

    def handshake
      @handshake ||= WebSocket::Handshake::Client.new(url: url)
    end

    def incoming
      @incoming ||= WebSocket::Frame::Incoming::Client.new
    end
  end
end
