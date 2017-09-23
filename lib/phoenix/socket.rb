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
      @topic_cond = new_cond
      @join_ref = SecureRandom.uuid
    end

    # Simulate a synchronous call over the websocket
    def request_reply(event:, payload: {})
      ref = SecureRandom.uuid
      ensure_thread
      synchronize do
        @topic_cond.wait_until { @topic_joined }
        EM.next_tick { socket.send({ topic: topic, event: event, payload: payload, ref: ref }.to_json) }
        inbox_cond.wait_until { inbox.key?(ref) || @dead }
        inbox.delete(ref) { raise "reply #{ref} not found" }
      end
    end

    private

    attr_reader :inbox_cond, :thread_ready

    def ensure_thread
      connection_alive? or synchronize do
        spawn_thread
        thread_ready.wait(3)
        if @dead
          @spawning = false
          raise 'dead connection timeout'
        end
      end
    end

    def connection_alive?
      @ws_thread&.alive? && !@dead
    end

    def spawn_thread
      return if @spawning
      puts 'spawn_thread'
      @spawning = true
      @ws_thread = Thread.new do
        EM.run do
          synchronize do
            @socket = Faye::WebSocket::Client.new(path)
            socket.on :open do |event|
              p [:open]
              socket.send({ topic: topic, event: "phx_join", payload: join_options, ref: @join_ref }.to_json)
              synchronize do
                @dead     = false
                @spawning = false
                thread_ready.broadcast
              end
            end

            socket.on :message do |event|
              data = JSON.parse(event.data)
              synchronize do
                if data['ref'] == @join_ref
                  @topic_joined = true
                  @topic_cond.broadcast
                else
                  inbox[data['ref']] = data
                  inbox_cond.broadcast
                end
              end
            end

            socket.on :close do |event|
              p [:close, event.code, event.reason]
              synchronize do
                @socket = nil
                @dead = true
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
