require 'pry-byebug'
require "spec_helper"

RSpec.describe Phoenix::Socket do
  it "has a version number" do
    expect(Rb::Phoenix::Socket::VERSION).not_to be nil
  end

  let(:socket_handler) do
    Phoenix::Socket.new("rspec:default", path: "ws://#{ENV.fetch('PHOENIX_HOST')}:4000/socket/websocket")
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
    # do it in Elixir. Although you should probably also ask yourself why you need 500 processes
    # to share a single websocket.
    responses = (0..500).map do |n|
      Thread.new do
        Thread.current[:id] = n
        socket_handler.request_reply(event: :echo, payload: { n: n }, timeout: nil)
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
        expect { socket_handler.request_reply(event: :unsupported) }.to raise_error(RuntimeError, /reply .* not found/)
        expect(socket_handler.request_reply(event: :echo)['payload']['status']).to eq('ok')

        # Ensure dead handler threads have been cleaned up; we should have at most
        # the live main thread and a live respawned handler
        expect(Thread.list.count).to be < 3
      end
    end
  end

  describe 'timeout handling' do
    specify 'small sleep' do
      response = socket_handler.request_reply(event: :sleep, payload: { ms: 50 })
      expect(response.dig('payload', 'status')).to eq('ok')
    end

    specify 'long sleep' do
      response = socket_handler.request_reply(event: :sleep, payload: { ms: 1000 })
      expect(response.dig('payload', 'status')).to eq('ok')
    end

    specify 'sleep exceeding timeout' do
      expect { socket_handler.request_reply(timeout: 0.5, event: :sleep, payload: { ms: 1000 }) }.to raise_error(RuntimeError, /timeout/)
      expect { socket_handler.request_reply(timeout: 0.5, event: :sleep, payload: { ms: 10 }) }.not_to raise_error
    end
  end
end
