# Valkey 9.0.0 with Bitnami-style scripts and modules
# All components are version 9.x for consistency
#
# This image combines:
# - valkey/valkey:9.0.0 as base (Debian Trixie, glibc 2.41)
# - Bitnami scripts for env var configuration
# - valkey-bundle:9.0.0 modules (JSON, Bloom)

ARG VALKEY_VERSION=9.0.0
ARG BUNDLE_VERSION=9.0.0

# Stage 1: Get modules from Valkey Bundle 9.x
FROM valkey/valkey-bundle:${BUNDLE_VERSION} AS bundle

# Stage 2: Get Bitnami scripts
FROM bitnami/valkey:latest AS bitnami

# Stage 3: Final image
FROM valkey/valkey:${VALKEY_VERSION}

ARG VALKEY_VERSION
ARG BUNDLE_VERSION

LABEL org.opencontainers.image.title="Valkey with Modules"
LABEL org.opencontainers.image.description="Valkey ${VALKEY_VERSION} with Bitnami-style configuration and modules from valkey-bundle"
LABEL org.opencontainers.image.source="https://github.com/EmiliaVision/bitnami-valkey-bundle"
LABEL org.opencontainers.image.version="${VALKEY_VERSION}"
LABEL valkey.version="${VALKEY_VERSION}"
LABEL valkey.bundle.version="${BUNDLE_VERSION}"

USER root

# Create Bitnami-compatible directory structure
RUN mkdir -p /opt/bitnami/valkey/bin \
             /opt/bitnami/valkey/etc \
             /opt/bitnami/valkey/modules \
             /opt/bitnami/scripts/valkey \
             /opt/bitnami/common/bin \
             /bitnami/valkey/data

# Copy ALL Bitnami scripts and config (includes libvalkey.sh, valkey-env.sh, etc)
COPY --from=bitnami /opt/bitnami/scripts/ /opt/bitnami/scripts/
COPY --from=bitnami /opt/bitnami/common/ /opt/bitnami/common/
COPY --from=bitnami /opt/bitnami/valkey/etc.default/ /opt/bitnami/valkey/etc.default/
COPY --from=bitnami /opt/bitnami/valkey/etc/ /opt/bitnami/valkey/etc/

# Link valkey binaries to Bitnami expected location
RUN ln -sf /usr/local/bin/valkey-server /opt/bitnami/valkey/bin/valkey-server && \
    ln -sf /usr/local/bin/valkey-cli /opt/bitnami/valkey/bin/valkey-cli && \
    ln -sf /usr/local/bin/valkey-sentinel /opt/bitnami/valkey/bin/valkey-sentinel && \
    ln -sf /usr/local/bin/valkey-benchmark /opt/bitnami/valkey/bin/valkey-benchmark

# Copy modules from Valkey Bundle
COPY --from=bundle /usr/lib/valkey/libjson.so /opt/bitnami/valkey/modules/
COPY --from=bundle /usr/lib/valkey/libvalkey_bloom.so /opt/bitnami/valkey/modules/

# Optional: Search module (89MB - uncomment if needed)
# COPY --from=bundle /usr/lib/valkey/libsearch.so /opt/bitnami/valkey/modules/

# Set permissions
RUN chmod 755 /opt/bitnami/valkey/modules/*.so && \
    chmod -R g+rwX /opt/bitnami /bitnami && \
    chown -R 1001:1001 /opt/bitnami /bitnami

# Create symlinks for entrypoint
RUN ln -sf /opt/bitnami/scripts/valkey/entrypoint.sh /entrypoint.sh && \
    ln -sf /opt/bitnami/scripts/valkey/run.sh /run.sh

# Environment variables (Bitnami-compatible)
ENV HOME="/" \
    OS_ARCH="amd64" \
    OS_FLAVOUR="debian-13" \
    OS_NAME="linux" \
    APP_VERSION="${VALKEY_VERSION}" \
    BITNAMI_APP_NAME="valkey" \
    PATH="/opt/bitnami/common/bin:/opt/bitnami/valkey/bin:$PATH"

EXPOSE 6379

USER 1001

ENTRYPOINT [ "/opt/bitnami/scripts/valkey/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/valkey/run.sh" ]
