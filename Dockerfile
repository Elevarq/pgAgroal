# syntax=docker/dockerfile:1

# pgagroal connection pooler - production container
# https://github.com/pgagroal/pgagroal

ARG DEBIAN_VERSION=bookworm-20260623-slim
# Pin the base by its multi-arch index digest for reproducibility (Gate D).
# The human-readable tag above is retained for clarity; the digest is
# authoritative. Keep both in sync — Dependabot/Renovate update them together.
# This digest is the bookworm-20260623-slim snapshot, which already carries
# the libssl3 3.0.20-1~deb12u2 fix for CVE-2026-45447 (#60); the runtime
# apt-get upgrade still runs as defence in depth for any newer advisory.
ARG DEBIAN_DIGEST=sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df
ARG PGAGROAL_VERSION=2.1.0

# =============================================================================
# Stage 1: Build pgagroal from source
# =============================================================================
FROM debian:${DEBIAN_VERSION}@${DEBIAN_DIGEST} AS builder

ARG PGAGROAL_VERSION

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
        liburing-dev \
        python3-docutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch ${PGAGROAL_VERSION} --depth 1 \
        https://github.com/pgagroal/pgagroal.git

WORKDIR /src/pgagroal/build

RUN cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        .. \
    && make -j"$(nproc)" \
    && make install

# =============================================================================
# Stage 2: Minimal runtime image
# =============================================================================
FROM debian:${DEBIAN_VERSION}@${DEBIAN_DIGEST}

ARG PGAGROAL_VERSION

LABEL maintainer="elevarq" \
      org.opencontainers.image.title="pgagroal" \
      org.opencontainers.image.description="pgagroal PostgreSQL connection pooler" \
      org.opencontainers.image.source="https://github.com/pgagroal/pgagroal" \
      org.opencontainers.image.version="${PGAGROAL_VERSION}"

# Pull Debian security updates on top of the pinned base. Debian publishes
# CVE fixes (e.g. libgnutls30 deb12u7, libcap2 deb12u3) to bookworm-security,
# which the dated base-image snapshots do not bake in — so a security
# upgrade is required to ship a CVE-clean runtime. DL3005 is intentionally
# ignored here for exactly that reason.
# hadolint ignore=DL3005
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        libssl3 \
        zlib1g \
        libbz2-1.0 \
        libzstd1 \
        liblz4-1 \
        liburing2 \
        libatomic1 \
        gettext-base \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries and library
COPY --from=builder /usr/local/bin/pgagroal     /usr/local/bin/pgagroal
COPY --from=builder /usr/local/bin/pgagroal-cli /usr/local/bin/pgagroal-cli
COPY --from=builder /usr/local/bin/pgagroal-admin /usr/local/bin/pgagroal-admin
COPY --from=builder /usr/local/lib/libpgagroal* /usr/local/lib/

RUN ldconfig

# Create non-root user and directories
RUN groupadd --gid 1000 pgagroal \
    && useradd --uid 1000 --gid pgagroal --create-home --shell /bin/bash pgagroal \
    && mkdir -p /etc/pgagroal /var/log/pgagroal /var/run/pgagroal \
    && chown -R pgagroal:pgagroal /etc/pgagroal /var/log/pgagroal /var/run/pgagroal

# Copy templates and entrypoint
COPY pgagroal.conf.template    /etc/pgagroal/pgagroal.conf.template
COPY pgagroal_hba.conf.template /etc/pgagroal/pgagroal_hba.conf.template
COPY entrypoint.sh             /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R pgagroal:pgagroal /etc/pgagroal

EXPOSE 6432 2346

USER pgagroal
WORKDIR /home/pgagroal

ENV PGAGROAL_HOST="*" \
    PGAGROAL_PORT="6432" \
    PGAGROAL_METRICS_PORT="2346" \
    PG_BACKEND_HOST="postgres" \
    PG_BACKEND_PORT="5432" \
    POOL_SIZE="100" \
    MAX_CONNECTIONS="100" \
    PGAGROAL_LOG_LEVEL="info" \
    PGAGROAL_HBA_SOURCE="10.0.0.0/8,172.16.0.0/16,172.17.0.0/16,172.18.0.0/16,172.19.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16,172.23.0.0/16,172.24.0.0/16,172.25.0.0/16,172.26.0.0/16,172.27.0.0/16,172.28.0.0/16,172.29.0.0/16,172.30.0.0/16,172.31.0.0/16,192.168.0.0/16" \
    PGAGROAL_ALLOW_UNKNOWN_USERS="false"

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD pgagroal-cli -c /etc/pgagroal/pgagroal.conf ping || exit 1

ENTRYPOINT ["entrypoint.sh"]
