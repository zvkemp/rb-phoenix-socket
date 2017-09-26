require "phoenix/socket/version"
require 'phoenix/socket_handler'
# require 'faye/websocket'
# require 'eventmachine'
require 'phoenix/inbox'
require 'json'

module Phoenix
  class Socket
    include MonitorMixin
    attr_reader :path, :socket, :inbox, :topic, :join_options
    attr_accessor :verbose

    def initialize(topic, join_options: {}, path: 'ws://localhost:4000/socket/websocket')
      @path = path
      @topic = topic
      @join_options = join_options
      @inbox = Phoenix::Inbox.new(ttl: 15)
      super() # MonitorMixin
      @inbox_cond = new_cond
      @thread_ready = new_cond
      @topic_cond = new_cond
      reset_state_conditions
    end

    def d
      # @verbose = true
      request_reply(event: "words", payload: { user_id: 1 })
    end

    def self.verbose=(f)
      super
      @socket&.verbose = f
    end

    # Simulate a synchronous call over the websocket
    # TODO: use a queue/inbox/outbox here instead
    def request_reply(event:, payload: {}, timeout: 1) # timeout in seconds
      ref = SecureRandom.uuid
      synchronize do
        ensure_connection
        log "\e[31m WAITING #{event} #{ref}"
        @topic_cond.wait_until { @topic_joined }
        log "\e[31m#{event} #{ref}"
        socket.send_data({ topic: topic, event: event, payload: payload, ref: ref }.to_json)

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
          log("\e[36mwaiting for #{ref}")
          inbox_cond.wait(timeout) # waits until time expires or signaled
          break if inbox.key?(ref) || @dead
          log("#{ref} checking timeout NOW:#{Time.now.to_f} TS:#{ts.to_f} TO:#{timeout} #{(ts + timeout).to_f}") if timeout
          if timeout && Time.now > (ts + timeout)
            socket&.socket&.flush
            raise "#{ref} timeout"
          end
        end
        inbox.delete(ref) { raise "reply #{ref} not found" }.tap do |r|
          log(r)
        end
      end
    end

    private

    attr_reader :inbox_cond, :thread_ready

    def log(msg)
      return unless verbose
      puts "\e[32m[#{Thread.current[:id]}][#{Time.now.to_f}] #{msg} (#@topic_joined)\e[0m"
    end

    def ensure_connection
      connection_alive? or synchronize do
        log("ensure_connection")
        spawn_thread
        thread_ready.wait(3)
        if @dead
          @spawned = false
          raise 'dead connection timeout'
        end
      end
    end

    def connection_alive?
      #@ws_thread&.alive? && !@dead
      @socket&.open && !@dead
    end

    def handle_close(event = nil)
      synchronize do
        @socket&.close(:skip_handler)
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
      log "handling #{event.data}"
      synchronize do
        if data['event'] == 'phx_close'
          log('handling close from message')
          handle_close(event)
        elsif data['ref'] == @join_ref && data['event'] == 'phx_error'
          # NOTE: For some reason, on errors phx will send the join ref instead of the message ref
          log("\e[31mBROADCAST")
          inbox_cond.broadcast
        elsif data['ref'] == @join_ref
          log ['join_ref', @join_ref]
          @topic_joined = true
          log("\e[31mTOPICJOIN")
          @topic_cond.broadcast
          thread_ready.broadcast
        else
          inbox[data['ref']] = data
          log("\e[31mBROADCAST")
          inbox_cond.broadcast
        end
      end
    end

    def handle_open(event)
      log 'open'
      socket.send_data({ topic: topic, event: "phx_join", payload: join_options, ref: @join_ref, join_ref: @join_ref }.to_json)
      synchronize do
        @dead     = false
        thread_ready.broadcast
      end
    end

    def spawn_thread
      return if @spawned || connection_alive?
      log 'spawning...'
      @spawned = true
      synchronize do
        begin
          log 'new socket'
          @socket = Phoenix::SocketHandler.new(path)
          @socket.verbose = verbose
          @socket.handle_message do |msg|
            # puts msg.data
            handle_message(msg)
          end

          @socket.handle_close { handle_close(nil) }

          handle_open(nil)
        rescue
          reset_state_conditions
          raise
        end
      end
    end
  end
end
