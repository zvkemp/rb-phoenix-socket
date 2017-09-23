defmodule SpecExampleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :spec_example

  socket "/socket", SpecExampleWeb.UserSocket
end
