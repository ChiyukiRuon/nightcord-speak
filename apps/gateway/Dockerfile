# syntax=docker/dockerfile:1
ARG RUST_VERSION=1.98.0
FROM rust:${RUST_VERSION}-bookworm AS build

RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && printf 'Acquire::Retries "3";\nAcquire::https::Timeout "30";\n' > /etc/apt/apt.conf.d/80gateway-build \
    && apt-get update \
    && apt-get install -y --no-install-recommends cmake libasound2-dev libssl-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY .cargo/config.toml .cargo/config.toml
COPY crates/ crates/
COPY apps/cli/ apps/cli/
COPY apps/gateway/ apps/gateway/
COPY apps/client/pubspec.yaml apps/client/pubspec.yaml
COPY vendor/tsclientlib/ vendor/tsclientlib/

# Cargo does not initialize the nested declarations submodule itself.
RUN test -f vendor/tsclientlib/utils/tsproto-structs/declarations/Versions.csv
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo build --locked --release -p nightcord-gateway

FROM debian:bookworm-slim AS runtime
# Bootstrap HTTPS package downloads before installing the managed certificate bundle.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && printf 'Acquire::Retries "3";\nAcquire::https::Timeout "30";\n' > /etc/apt/apt.conf.d/80gateway-build \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libasound2 libssl3 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 nightcord \
    && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /data nightcord \
    && install -d -o 10001 -g 10001 /data

COPY --from=build /workspace/target/release/nightcord-gateway /usr/local/bin/nightcord-gateway
COPY --chmod=755 apps/gateway/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY LICENSE-MIT LICENSE-APACHE /usr/share/doc/nightcord-gateway/
COPY apps/client/assets/licenses/third_party.json /usr/share/doc/nightcord-gateway/third_party.json

ENV XDG_CONFIG_HOME=/data/config
USER 10001:10001
WORKDIR /data
EXPOSE 8787/tcp
VOLUME ["/data"]
# The gateway already drains device workers on ctrl_c; Docker must send SIGINT.
STOPSIGNAL SIGINT
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD curl --fail --silent --output /dev/null http://127.0.0.1:8787/ || exit 1
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
