# syntax=docker/dockerfile:1

# pgexporter PostgreSQL metrics exporter - integration container
# https://github.com/pgexporter/pgexporter
#
# Built from pinned upstream source (not vendored, not forked) so the
# integration stack composes against the real upstream component. Mirrors
# the build pattern used for pgagroal in this repository.

ARG DEBIAN_VERSION=bookworm-20260316-slim
ARG PGEXPORTER_VERSION=0.8.0

# =============================================================================
# Stage 1: Build pgexporter from source
# =============================================================================
FROM debian:${DEBIAN_VERSION} AS builder

ARG PGEXPORTER_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        gcc \
        g++ \
        make \
        cmake \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libzstd-dev \
        liblz4-dev \
        libev-dev \
        libyaml-dev \
        libpq-dev \
        python3-docutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch ${PGEXPORTER_VERSION} --depth 1 \
        https://github.com/pgexporter/pgexporter.git

WORKDIR /src/pgexporter/build

RUN cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        .. \
    && make -j"$(nproc)" \
    && make install

# =============================================================================
# Stage 2: Minimal runtime image
# =============================================================================
FROM debian:${DEBIAN_VERSION}

ARG PGEXPORTER_VERSION

LABEL maintainer="elevarq" \
      org.opencontainers.image.title="pgexporter" \
      org.opencontainers.image.description="pgexporter PostgreSQL metrics exporter" \
      org.opencontainers.image.source="https://github.com/pgexporter/pgexporter" \
      org.opencontainers.image.version="${PGEXPORTER_VERSION}"

# Pull Debian security updates on top of the pinned base (same rationale as
# the pgagroal image: dated snapshots do not bake in bookworm-security fixes).
# hadolint ignore=DL3005
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        libssl3 \
        zlib1g \
        libbz2-1.0 \
        libzstd1 \
        liblz4-1 \
        libev4 \
        libyaml-0-2 \
        libpq5 \
        libatomic1 \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries and library
COPY --from=builder /usr/local/bin/pgexporter        /usr/local/bin/pgexporter
COPY --from=builder /usr/local/bin/pgexporter-cli    /usr/local/bin/pgexporter-cli
COPY --from=builder /usr/local/bin/pgexporter-admin  /usr/local/bin/pgexporter-admin
COPY --from=builder /usr/local/lib/libpgexporter*    /usr/local/lib/
# Metric-extension definitions; pgexporter looks for them under
# /usr/local/share/pgexporter/extensions on Debian-based systems.
COPY --from=builder /usr/local/share/pgexporter      /usr/local/share/pgexporter

RUN ldconfig

# Create non-root user and config directory
RUN groupadd --gid 1000 pgexporter \
    && useradd --uid 1000 --gid pgexporter --create-home --shell /bin/bash pgexporter \
    && mkdir -p /etc/pgexporter \
    && chown -R pgexporter:pgexporter /etc/pgexporter

# Copy config template and entrypoint
COPY pgexporter.conf.template /etc/pgexporter/pgexporter.conf.template
COPY entrypoint.sh            /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R pgexporter:pgexporter /etc/pgexporter

EXPOSE 5002

USER pgexporter
WORKDIR /home/pgexporter

ENV PG_BACKEND_HOST="postgres" \
    PG_BACKEND_PORT="5432" \
    PGEXPORTER_USER="pgexporter" \
    PGEXPORTER_METRICS_PORT="5002" \
    PGEXPORTER_LOG_LEVEL="info"

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD pgexporter-cli -c /etc/pgexporter/pgexporter.conf ping || exit 1

ENTRYPOINT ["entrypoint.sh"]
