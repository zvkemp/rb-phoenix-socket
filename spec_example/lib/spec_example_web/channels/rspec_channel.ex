defmodule SpecExampleWeb.RSpecChannel do
  use Phoenix.Channel

  def join("rspec:default", _message, socket) do
    {:ok, socket}
  end

  def handle_in("echo", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end
