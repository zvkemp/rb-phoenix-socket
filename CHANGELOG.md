### 0.2.0

- Added specs, backed by Phoenix app via docker-compose
- Support timeout on requests

### 0.1.1

Provide better threadsafety. This now works correctly:

```ruby
require 'phoenix/socket'
ps = Phoenix::Socket.new('stat:default')
(1..100).map do |x| 
  Thread.new do
    ps.request_reply(event: 'word_count', payload: { user_id: x })
  end
end.map(&:value)
```

- EventMachine thread spawning is now limited to a single concurrent instance
- Requests wait until the channel has received join confirmation (no more 'Unknown Topic' errors)
- Certain conditions are now broadcasts instead of signals (prevent threads from sleeping forever when their replies come out-of-order)
