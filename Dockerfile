# syntax=docker/dockerfile:1.6

# ---- Build stage ----
ARG ELIXIR_VERSION=1.17.3

FROM elixir:${ELIXIR_VERSION}-alpine AS build

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    ERL_COMPILER_OPTIONS="[deterministic,no_debug_info]"

SHELL ["/bin/sh", "-ec"]

# Build deps for native compilation (SQLite, OpenSSL) and basic tools
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    ca-certificates \
    openssl-dev \
    sqlite-dev \
    zlib-dev \
    ncurses-dev

WORKDIR /app

# Install Hex/Rebar and fetch deps with max caching
RUN mix local.hex --force && mix local.rebar --force

# Copy files to resolve deps and compile them first
COPY mix.exs mix.lock ./
COPY config ./config
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy the rest of the app
COPY lib ./lib
COPY priv ./priv
COPY assets ./assets

# Compile, build assets, and create release
RUN mix compile
RUN mix assets.deploy

# Add entrypoint script into build context for copying to final image
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

RUN mix release && \
    apk add --no-cache binutils && \
    find /app/_build/prod/rel/firmware_manager -type f \( -name "*.so" -o -name "beam.smp" -o -name "epmd" \) -exec strip --strip-unneeded {} + || true

# ---- Dependencies stage (runtime libs we need to copy into scratch) ----
FROM alpine:3.20 AS deps
RUN apk add --no-cache \
    ca-certificates \
    openssl \
    sqlite-libs \
    zlib \
    libstdc++ \
    libgcc \
    ncurses-libs \
    ncurses-terminfo-base \
    busybox-static \
  && ln -sf /bin/busybox.static /bin/busybox \
  && /bin/busybox --install -s /bin \
  && mkdir -p /data \
  && chown 10001:10001 /data

# ---- Scratch runtime stage ----
FROM scratch AS runtime

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    HOME=/app \
    SHELL=/bin/sh \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/firmware_manager.db

# Provide /bin with busybox applets (sh, readlink, dirname, cut, etc)
COPY --from=deps /bin /bin

# CA certificates for HTTPS
COPY --from=deps /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# musl loader and required shared libs for OTP/NIFs
COPY --from=deps /lib/ld-musl-aarch64.so.1 /lib/ld-musl-aarch64.so.1
COPY --from=build /usr/lib/libcrypto.so.3 /usr/lib/libcrypto.so.3
COPY --from=build /usr/lib/libssl.so.3 /usr/lib/libssl.so.3
COPY --from=deps /usr/lib/libsqlite3.so.0 /usr/lib/libsqlite3.so.0
COPY --from=deps /lib/libz.so.1 /lib/libz.so.1
COPY --from=deps /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
COPY --from=deps /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1
COPY --from=deps /usr/lib/libncursesw.so.6 /usr/lib/libncursesw.so.6

WORKDIR /app

# Copy the release, entrypoint, and writable data dir with correct ownership
COPY --from=build --chown=10001:10001 /app/_build/prod/rel/firmware_manager /app
COPY --from=build --chown=10001:10001 /usr/local/bin/entrypoint /usr/local/bin/entrypoint
COPY --from=deps --chown=10001:10001 /data /data

# Expose UI + telephony-related UDP ports
EXPOSE 4000/tcp
EXPOSE 5060/udp
EXPOSE 2427/udp
EXPOSE 10000-20000/udp

USER 10001

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD []
