require "phoenix/socket/version"
require 'faye/websocket'
require 'eventmachine'
require 'phoenix/inbox'
require 'json'
require 'cgi'
require 'uri'

module Phoenix
  class Socket
    include MonitorMixin
    attr_reader :path, :socket, :inbox, :topic
    attr_accessor :verbose, :join_options_proc, :connect_options_proc

    def initialize(topic, join_options: {}, connect_options: {}, path: 'ws://localhost:4000/socket/websocket')
      @path = path
      @topic = topic
      @join_options = join_options
      @connect_options = connect_options
      @inbox = Phoenix::Inbox.new(ttl: 15)
      super() # MonitorMixin
      @inbox_cond = new_cond
      @thread_ready = new_cond
      @topic_cond = new_cond
      reset_state_conditions
    end

    # Simulate a synchronous call over the websocket
    # TODO: use a queue/inbox/outbox here instead
    def request_reply(event:, payload: {}, timeout: 5) # timeout in seconds
      ref = SecureRandom.uuid
      synchronize do
        ensure_connection
        @topic_cond.wait_until { @topic_joined }
        EM.next_tick { socket.send({ topic: topic, event: event, payload: payload, ref: ref }.to_json) }
        log [event, ref]

        # Ruby's condition variables only support timeout on the basic 'wait' method;
        # This should behave roughly as if wait_until also support a timeout:
        # `inbox_cond.wait_until(timeout) { inbox.key?(ref) || @dead }
        #
        # Note that this serves only to unblock the main thread, and should not halt execution of the
        # socket connection. Therefore, there is a possibility that the inbox may pile up with
        # unread messages if a lot of timeouts are encountered. A self-sweeping inbox will
        # be implemented to prevent this.
        ts = Time.now
        loop do
          inbox_cond.wait(timeout) # waits until time expires or signaled
          break if inbox.key?(ref) || @dead
          raise 'timeout' if timeout && Time.now > (ts + timeout)
        end
        inbox.delete(ref) { raise "reply #{ref} not found" }
      end
    end

    def join_options
      return @join_options unless join_options_proc
      join_options_proc.call(@join_options)
    end

    def connect_options
      return @connect_options unless connect_options_proc
      connect_options_proc.call(@connect_options)
    end

    private

    attr_reader :inbox_cond, :thread_ready

    def log(msg)
      return unless @verbose
      puts "[#{Thread.current[:id]}] #{msg} (#@topic_joined)"
    end

    def ensure_connection
      connection_alive? or synchronize do
        spawn_thread
        thread_ready.wait(3)
        if @dead
          @spawned = false
          raise 'dead connection timeout'
        end
      end
    end

    def connection_alive?
      @ws_thread&.alive? && !@dead
    end

    def handle_close(event)
      synchronize do
        reset_state_conditions
        inbox_cond.signal
        thread_ready.signal
      end
    end

    def reset_state_conditions
      @dead = true # no EM thread active, or the connection has been closed
      @socket = nil # the Faye::Websocket::Client instance
      @spawned = false # The thread running (or about to run) EventMachine has been launched
      @join_ref = SecureRandom.uuid # unique id that Phoenix uses to identify the socket <-> channel connection
      @topic_joined = false # The initial join request has been acked by the remote server
    end

    def handle_message(event)
      data = JSON.parse(event.data)
      log event.data
      synchronize do
        if data['event'] == 'phx_close'
          log('handling close from message')
          handle_close(event)
        elsif data['ref'] == @join_ref && data['event'] == 'phx_error'
          # NOTE: For some reason, on errors phx will send the join ref instead of the message ref
          inbox_cond.broadcast
        elsif data['ref'] == @join_ref
          log ['join_ref', @join_ref]
          @topic_joined = true
          @topic_cond.broadcast
        else
          inbox[data['ref']] = data
          inbox_cond.broadcast
        end
      end
    end

    def handle_open(event)
      log 'open'
      socket.send({ topic: topic, event: "phx_join", payload: join_options, ref: @join_ref, join_ref: @join_ref }.to_json)
      synchronize do
        @dead     = false
        thread_ready.broadcast
      end
    end

    def build_path
      uri = URI.parse(path)
      existing_query = CGI.parse(uri.query || '')
      uri.query = URI.encode_www_form(existing_query.merge(connect_options))
      uri.to_s
    end

    def spawn_thread
      return if @spawned || connection_alive?
      log 'spawning...'
      @spawned = true
      @ws_thread = Thread.new do
        Thread.current[:id] = "WSTHREAD_#{SecureRandom.hex(3)}"
        EM.run do
          synchronize do
            log 'em.run.sync'
            @socket = Faye::WebSocket::Client.new(build_path)
            socket.on :open do |event|
              handle_open(event)
            end

            socket.on :message do |event|
              handle_message(event)
            end

            socket.on :close do |event|
              log [:close, event.code, event.reason]
              handle_close(event)
              EM::stop
            end
          end
        end
      end
    end
  end
end
