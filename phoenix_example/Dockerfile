FROM elixir:1.5.1-alpine

ENV LANG=C.UTF-8
WORKDIR /usr/src/app

ENV MIX_ENV=dev
RUN mix local.hex --force && mix local.rebar --force

COPY mix* ./
RUN mix deps.get && mix compile

COPY . ./
RUN mix deps.get && mix compile

CMD ["mix", "phx.server"]
