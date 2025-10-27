# syntax=docker/dockerfile:1

# Build and tag locally (example):
#   export IMAGE_REF=firmware_manager:latest
#   podman build -t "$IMAGE_REF" .
# Target size budget: <80MB compressed (linux/arm64)

########## Build stage (Alpine) ##########
ARG ELIXIR_VERSION=1.17.3
FROM elixir:${ELIXIR_VERSION}-alpine AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    ERL_COMPILER_OPTIONS="[deterministic,no_debug_info]"

# Needed for compiling deps and asset installers
RUN apk add --no-cache build-base git curl

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
RUN mix assets.setup
RUN mix assets.deploy
RUN mix compile

# Build release
RUN mix release

# Prune unused OTP libs and strip binaries inside the assembled release
# Do this in the builder so the runtime stays minimal
RUN set -eux; \
    rel="/app/_build/prod/rel/firmware_manager"; \
    # Remove rarely-used OTP apps to shrink ERTS
    rm -rf "$rel"/erts-*/lib/{wx-*,observer-*,megaco-*,odbc-*,jinterface-*,reltool-*,debugger-*} || true; \
    # Strip native shared libs and beam.smp where possible
    find "$rel" -type f -name "*.so" -exec strip --strip-unneeded {} + || true; \
    strip --strip-unneeded "$rel"/erts-*/bin/beam.smp || true

# Prepare entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

########## Runtime stage (Alpine) ##########
FROM alpine:3.20 AS runtime

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/firmware_manager.db \
    SKIP_MIGRATIONS=0 \
    ERL_CRASH_DUMP_SECONDS=0

# Only required runtime libs
RUN apk add --no-cache ca-certificates openssl ncurses-libs zlib libstdc++ && \
    addgroup -S app && adduser -S -H -G app -u 10001 app && \
    mkdir -p /data && chown -R app:app /data

WORKDIR /app

# Copy the release from the builder (already pruned/stripped) and the entrypoint
COPY --from=build --chown=app:app /app/_build/prod/rel/firmware_manager /app
COPY --from=build --chown=app:app /usr/local/bin/entrypoint /usr/local/bin/entrypoint

# Ensure OpenSSL runtime matches what Erlang/crypto was built against
# Copy libssl/libcrypto from the builder image to avoid ABI mismatch
# Paths for Alpine-based images (in official elixir:alpine they are under /usr/lib)
COPY --from=build /usr/lib/libssl.so.* /usr/lib/
COPY --from=build /usr/lib/libcrypto.so.* /usr/lib/

EXPOSE 4000
USER app:app
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD []
