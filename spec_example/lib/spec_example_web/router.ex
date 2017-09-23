defmodule SpecExampleWeb.Router do
  use SpecExampleWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SpecExampleWeb do
    pipe_through :api
  end
end
