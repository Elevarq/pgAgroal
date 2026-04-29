# syntax=docker/dockerfile:1

# pgagroal connection pooler - production container
# https://github.com/pgagroal/pgagroal

ARG DEBIAN_VERSION=bookworm-20260316-slim
ARG PGAGROAL_VERSION=2.1.0

# =============================================================================
# Stage 1: Build pgagroal from source
# =============================================================================
FROM debian:${DEBIAN_VERSION} AS builder

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
FROM debian:${DEBIAN_VERSION}

ARG PGAGROAL_VERSION

LABEL maintainer="elevarq" \
      org.opencontainers.image.title="pgagroal" \
      org.opencontainers.image.description="pgagroal PostgreSQL connection pooler" \
      org.opencontainers.image.source="https://github.com/pgagroal/pgagroal" \
      org.opencontainers.image.version="${PGAGROAL_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
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

EXPOSE 6432

USER pgagroal
WORKDIR /home/pgagroal

ENV PGAGROAL_HOST="*" \
    PGAGROAL_PORT="6432" \
    PG_BACKEND_HOST="postgres" \
    PG_BACKEND_PORT="5432" \
    POOL_SIZE="100" \
    MAX_CONNECTIONS="100" \
    PGAGROAL_LOG_LEVEL="info"

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD pgagroal-cli -c /etc/pgagroal/pgagroal.conf ping || exit 1

ENTRYPOINT ["entrypoint.sh"]
