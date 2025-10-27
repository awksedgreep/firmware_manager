# syntax=docker/dockerfile:1

########## Build stage (Debian) ##########
ARG ELIXIR_VERSION=1.17.3
FROM elixir:${ELIXIR_VERSION}-slim AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    ERL_COMPILER_OPTIONS="[deterministic,no_debug_info]"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates \
    libssl-dev libsqlite3-dev zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Hex/Rebar and fetch deps with caching
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy the app
COPY lib ./lib
COPY priv ./priv
COPY assets ./assets

# Build assets and compile app
RUN mix assets.deploy
RUN mix compile

# Prepare entrypoint and build release
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint
RUN mix release

########## Runtime stage (Debian slim) ##########
FROM debian:bookworm-slim AS runtime

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/firmware_manager.db

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl libsqlite3-0 zlib1g libstdc++6 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --create-home --home-dir /app --uid 10001 app \
  && mkdir -p /data && chown -R 10001:10001 /data

WORKDIR /app

COPY --from=build --chown=10001:10001 /app/_build/prod/rel/firmware_manager /app
COPY --from=build --chown=10001:10001 /usr/local/bin/entrypoint /usr/local/bin/entrypoint

EXPOSE 4000
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD []
