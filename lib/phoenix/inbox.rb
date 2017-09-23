require 'mutex_m'
module Phoenix
  class Inbox
    # Read it or forget it

    include Mutex_m
    attr_reader :ttl, :data
    def initialize(ttl:)
      @ttl = ttl
      @bucket = Time.now.to_i / ttl
      @data = Hash.new { |h, k| h[k] = {} }
      super()
    end

    def push(key, val)
      synchronize do
        ts = current_timestamp
        (data[ts][key] = val).tap do
          if data.keys.size >= 3
            data.delete_if { |key, _| key < (ts - 1) }
          end
        end
      end
    end

    alias_method :[]=, :push

    def pop(key)
      synchronize do
        ts = current_timestamp
        data[ts - 1].delete(key) { data[ts].delete(key) { yield }}
      end
    end

    alias_method :delete, :pop

    def key?(key)
      data.values.any? { |v| v.key?(key) }
    end

    def current_timestamp
      Time.now.to_i / ttl
    end
  end
end
