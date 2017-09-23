require 'pry-byebug'
require "spec_helper"

RSpec.describe Phoenix::Socket do
  it "has a version number" do
    expect(Rb::Phoenix::Socket::VERSION).not_to be nil
  end

  let(:socket_handler) do
    Phoenix::Socket.new("rspec:default", path: "ws://#{`docker-machine ip`.strip}:4000/socket/websocket")
  end

  it 'echoes back the requested payload' do
    response = socket_handler.request_reply(event: :echo, payload: { foo: :bar })
    expect(response['event']).to eq('phx_reply')
    expect(response['topic']).to eq('rspec:default')
    expect(response['payload']).to eq({ 'status' => 'ok', 'response' => { 'foo' => 'bar' }})
  end

  it 'handles concurrent threads' do
    # NOTE: This is a proof of concept, and is WAY more than anyone would ever want/need
    # to spawn in a runtime process. I.e. don't do this. If one at a time isn't enough,
    # do it in Elixir.
    responses = (0..500).map do |n|
      Thread.new do
        Thread.current[:id] = n
        socket_handler.request_reply(event: :echo, payload: { n: n })
      end
    end.map(&:value)

    responses.each_with_index do |response, index|
      expect(response['payload']).to eq({ 'status' => 'ok', 'response' => { 'n' => index }})
    end
  end

  describe 're-spawn' do
    20.times do |n|
      # NOTE: Running this multiple times because there was some unexpected thread scheduling
      # behavior that came up during development. Generally came up at least 1 / 5 times;
      # running 20 for safety.
      it "handles termination but respawns the connection handler" do
        expect { socket_handler.request_reply(event: :unsupported) }.to raise_error(RuntimeError)
        expect(socket_handler.request_reply(event: :echo)['payload']['status']).to eq('ok')
      end
    end
  end
end
