# Phoenix::Socket

Phoenix Channels websocket client wrapper for synchronous Ruby applications.

## Usage Example

In your Phoenix channel:
```elixir
def join("words:default", _message, socket) do
  {:ok, socket}
end

def handle_in("word_list", %{"user_id" => id}, socket) do
  payload = %{user_id: id, words: WordRepo.words(id)}
  {:reply, {:ok, payload}, socket}
end
```

```ruby
socket = Phoenix::Socket.new("words:default", join_options: {}, path: 'ws://localhost:4000/socket/websocket')
socket.request_reply(event: "word_list", payload: { user_id: 1 })
# => {"topic"=>"words:default", "ref"=>"5d47b623", "payload"=>{"status"=>"ok", "response"=>{"words"=>["hummingbird", "puffleg"], "user_id"=>1}}, "join_ref"=>nil, "event"=>"phx_reply"}
```

The socket client does not currently implement a heartbeat, meaning it will eventually close the connection and cause the event thread to die; however, it will automatically re-open a new connection the next time you make a request. This should be a reasonable default for situations in which traffic over the socket is either steady or comes in short bursts followed by longer periods of dormancy.

The `join_options` keyword in the initializer can be used to declare the payload sent with the channel join request (for authorization/cookies/whatever).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/zvkemp/rb-phoenix-socket.

