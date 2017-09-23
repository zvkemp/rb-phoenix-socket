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
    responses = (0..300).map do |n|
      Thread.new do
        Thread.current[:id] = n
        socket_handler.request_reply(event: :echo, payload: { n: n })
      end
    end.map(&:value)

    responses.each_with_index do |response, index|
      expect(response['payload']).to eq({ 'status' => 'ok', 'response' => { 'n' => index }})
    end
  end
end
