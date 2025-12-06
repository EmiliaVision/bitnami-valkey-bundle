# Bitnami Valkey + Valkey Bundle Modules
# Combines Bitnami ecosystem with official Valkey modules

# Stage 1: Get modules from Valkey Bundle
# Using bookworm (Debian 12, glibc 2.36) for Photon OS compatibility
FROM valkey/valkey-bundle:8-bookworm AS bundle

# Stage 2: Final image based on Bitnami Valkey
FROM bitnami/valkey:latest

USER root

# Create directory for modules
RUN mkdir -p /opt/bitnami/valkey/modules

# Copy modules from Valkey Bundle
# JSON - Native JSON data type
COPY --from=bundle /usr/lib/valkey/libjson.so /opt/bitnami/valkey/modules/

# Bloom - Probabilistic filters
COPY --from=bundle /usr/lib/valkey/libvalkey_bloom.so /opt/bitnami/valkey/modules/

# Search - Full-text search (optional, 89MB - uncomment if needed)
# COPY --from=bundle /usr/lib/valkey/libsearch.so /opt/bitnami/valkey/modules/

# LDAP - LDAP authentication (optional)
# COPY --from=bundle /usr/lib/valkey/libvalkey_ldap.so /opt/bitnami/valkey/modules/

# Set permissions (already 755 but we ensure it)
RUN chmod 755 /opt/bitnami/valkey/modules/*.so && \
    chown -R 1001:1001 /opt/bitnami/valkey/modules

USER 1001

# Modules are loaded via VALKEY_EXTRA_FLAGS or configuration:
# --loadmodule /opt/bitnami/valkey/modules/libjson.so
# --loadmodule /opt/bitnami/valkey/modules/libvalkey_bloom.so
