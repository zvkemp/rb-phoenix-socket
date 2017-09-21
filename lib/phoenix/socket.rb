require "phoenix/socket/version"
require 'faye/websocket'
require 'eventmachine'
require 'json'

module Phoenix
  class Socket
    include MonitorMixin
    attr_reader :path, :socket, :inbox, :topic, :join_options

    def initialize(topic, join_options: {}, path: 'ws://localhost:4000/socket/websocket')
      @path = path
      @topic = topic
      @join_options = join_options
      @inbox = {}
      super() # MonitorMixin
      @inbox_cond = new_cond
      @thread_ready = new_cond
    end

    # Simulate a synchronous call over the websocket
    def request_reply(event:, payload: {})
      ref = SecureRandom.uuid
      ensure_thread
      EM.next_tick { socket.send({ topic: topic, event: event, payload: payload, ref: ref }.to_json) }
      synchronize do
        inbox_cond.wait_until { inbox.key?(ref) || @dead }
        inbox.delete(ref) or raise "reply #{ref} not found"
      end
    end

    private

    attr_reader :inbox_cond, :thread_ready

    def ensure_thread
      @ws_thread&.alive? or synchronize do
        spawn_thread
        thread_ready.wait(3)
        raise 'dead connection timeout' if @dead
      end
    end

    def spawn_thread
      @dead = false
      @ws_thread = Thread.new do
        EM.run do
          synchronize do
            @socket = Faye::WebSocket::Client.new(path)
            socket.on :open do |event|
              p [:open]
              socket.send({ topic: topic, event: "phx_join", payload: join_options, ref: 1 }.to_json)
              synchronize { thread_ready.signal }
            end

            socket.on :message do |event|
              data = JSON.parse(event.data)
              synchronize do
                inbox[data['ref']] = data
                inbox_cond.signal
              end
            end

            socket.on :close do |event|
              p [:close, event.code, event.reason]
              @socket = nil
              @dead = true
              synchronize do
                inbox_cond.signal
                thread_ready.signal
              end
              EM::stop
            end
          end
        end
      end
    end
  end
end
