# Bitnami Valkey Bundle

Extend Bitnami's Valkey image with modules (JSON, Bloom) from **valkey-bundle** + Sentinel for High Availability.

## Lessons Learned

### 1. Compile vs Precompiled Binaries

**Compile from source** (initial approach):
- Slow (~2 min build time)
- Risk of binary incompatibility between systems
- More control but more maintenance

**Use valkey-bundle** (final approach - recommended):
- Fast (~5 sec build time)
- Tested and compatible modules
- Includes JSON, Bloom, Search, LDAP

```dockerfile
# RECOMMENDED: Copy from valkey-bundle
FROM valkey/valkey-bundle:8-bookworm AS bundle
FROM bitnami/valkey:latest
COPY --from=bundle /usr/lib/valkey/libjson.so /opt/bitnami/valkey/modules/
```

### 2. glibc Compatibility (IMPORTANT)

Bitnami Valkey uses **Photon OS with glibc 2.36**. Modules must be compatible:

| Bundle Tag | Base | glibc | Compatible with Bitnami? |
|------------|------|-------|--------------------------|
| `8-alpine` | Alpine | musl | NO - Error: `libc.musl-x86_64.so.1 not found` |
| `8-trixie` | Debian 13 | 2.38 | NO - Error: `GLIBC_2.38 not found` |
| `8-bookworm` | Debian 12 | 2.36 | YES |

**Rule**: Use `bookworm` for Bitnami compatibility.

### 3. Bitnami Valkey Base Image

Bitnami Valkey image changed from Debian (minideb) to **Photon OS** (VMware):

- Cannot use `apt-get` or `install_packages`
- Uses glibc 2.36
- Non-root user: 1001

### 4. Nomenclature: Master -> Primary

Bitnami updated the nomenclature in October 2024:

| Old | New |
|-----|-----|
| `VALKEY_REPLICATION_MODE=master` | `VALKEY_REPLICATION_MODE=primary` |
| `VALKEY_MASTER_HOST` | `VALKEY_PRIMARY_HOST` |
| `VALKEY_MASTER_PASSWORD` | `VALKEY_PRIMARY_PASSWORD` |

Using old variables will cause errors like:
```
ERROR ==> Invalid replication mode. Available options are 'primary/replica'
```

### 5. Module Permissions

Valkey modules require **execute permissions** (755), not just read (644):

```dockerfile
# INCORRECT - will cause "does not have execute permissions" error
RUN chmod 644 /opt/bitnami/valkey/modules/libjson.so

# CORRECT
RUN chmod 755 /opt/bitnami/valkey/modules/libjson.so
```

### 6. Loading Modules

There are 3 ways to load modules:

```bash
# 1. Environment variable (recommended for Docker)
VALKEY_EXTRA_FLAGS=--loadmodule /opt/bitnami/valkey/modules/libjson.so

# 2. In valkey.conf
loadmodule /opt/bitnami/valkey/modules/libjson.so

# 3. At runtime (not persistent)
MODULE LOAD /opt/bitnami/valkey/modules/libjson.so
```

### 7. Bitnami Sentinel

The master name in Bitnami Sentinel is `myprimary` (not `mymaster`):

```bash
# Query master
SENTINEL masters
SENTINEL get-master-addr-by-name myprimary

# DO NOT use "mymaster" as in traditional Redis
```

### 8. Healthchecks

Healthchecks are critical for startup order:

```yaml
healthcheck:
  test: ["CMD", "valkey-cli", "-a", "password", "ping"]
  interval: 5s
  timeout: 3s
  retries: 5
```

Replicas and sentinels must wait for master to be healthy:

```yaml
depends_on:
  valkey-master:
    condition: service_healthy
```

## Quick Start

```bash
# Start complete stack
docker compose up -d

# Check status
docker compose ps

# Test JSON
docker exec valkey-master valkey-cli -a secretpassword JSON.SET doc '$' '{"test":true}'
docker exec valkey-master valkey-cli -a secretpassword JSON.GET doc '$'

# Verify replication
docker exec valkey-replica-1 valkey-cli -a secretpassword JSON.GET doc '$'

# Verify Sentinel
docker exec valkey-sentinel-1 valkey-cli -p 26379 SENTINEL masters
```

## Structure

```
.
├── README.md                 # This file
├── CLAUDE.md                 # AI development guide
├── docker/
│   ├── Dockerfile            # Multi-stage build with modules
│   └── .dockerignore
├── docker-compose.yml        # Stack: 1 primary + 2 replicas + 3 sentinels
├── helm/
│   ├── values.yaml           # Production
│   └── values-local.yaml     # Development
└── tests/
    ├── test-json.sh          # JSON module tests
    ├── test-modules.sh       # All modules tests
    └── test-sentinel.sh      # Sentinel tests
```

## Architecture

```
                         ┌─────────────┐
                         │ Application │
                         └──────┬──────┘
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
    ┌──────▼──────┐      ┌──────▼──────┐      ┌──────▼──────┐
    │ Sentinel 1  │      │ Sentinel 2  │      │ Sentinel 3  │
    │   :26379    │      │   :26380    │      │   :26381    │
    └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
           │                    │                    │
           └────────────────────┼────────────────────┘
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
    ┌──────▼──────┐      ┌──────▼──────┐      ┌──────▼──────┐
    │   Primary   │      │  Replica 1  │      │  Replica 2  │
    │   :6380     │◄─────│             │◄─────│             │
    │  (modules)  │      │  (modules)  │      │  (modules)  │
    └─────────────┘      └─────────────┘      └─────────────┘
```

## Available JSON Commands

```bash
# Create document
JSON.SET user:1 '$' '{"name":"John","age":30}'

# Read full document
JSON.GET user:1 '$'

# Read specific field
JSON.GET user:1 '$.name'

# Update field
JSON.SET user:1 '$.age' '31'

# Increment number
JSON.NUMINCRBY user:1 '$.age' 1

# Work with arrays
JSON.SET user:1 '$.tags' '["dev"]'
JSON.ARRAPPEND user:1 '$.tags' '"python"' '"go"'

# Get type
JSON.TYPE user:1 '$'

# Delete field
JSON.DEL user:1 '$.tags'
```

## Kubernetes Deployment

```bash
# Build and push image (GCR example)
docker build -t us-east1-docker.pkg.dev/PROJECT/REPO/valkey-modules:latest ./docker
docker push us-east1-docker.pkg.dev/PROJECT/REPO/valkey-modules:latest

# Edit helm/values.yaml with your registry
# image.registry: us-east1-docker.pkg.dev
# image.repository: PROJECT/REPO/valkey-modules

# Install
helm install valkey oci://registry-1.docker.io/bitnamicharts/valkey \
  -f helm/values.yaml \
  -n valkey --create-namespace
```

### Custom Images Note

Bitnami requires `global.security.allowInsecureImages: true` for non-Bitnami images:

```yaml
global:
  security:
    allowInsecureImages: true
```

## High Availability Testing (Failover)

Tested on GKE Autopilot with successful results:

| Test | Result | Recovery Time |
|------|--------|---------------|
| Delete REPLICA | Kubernetes recreates pod, reconnects to master | ~30 sec |
| Delete PRIMARY | Sentinel promotes replica to master automatically | ~10 sec |
| Data integrity | Data intact after failover | - |
| Modules post-failover | JSON and Bloom work correctly | - |
| Reverse replication | Ex-master becomes replica automatically | - |

### Simulate Primary Failure (Failover)

```bash
# Check initial state
kubectl exec -n valkey valkey-node-0 -c valkey -- valkey-cli -a PASSWORD ROLE

# Delete primary to force failover
kubectl delete pod -n valkey valkey-node-0

# Sentinel detects failure and promotes replica (~10 sec)
kubectl exec -n valkey valkey-node-1 -c sentinel -- \
  valkey-cli -p 26379 -a PASSWORD SENTINEL get-master-addr-by-name myprimary

# Verify new master
kubectl exec -n valkey valkey-node-1 -c valkey -- valkey-cli -a PASSWORD ROLE
```

### Verify Modules Work Post-Failover

```bash
# On the new master
kubectl exec -n valkey valkey-node-1 -c valkey -- \
  valkey-cli -a PASSWORD MODULE LIST

kubectl exec -n valkey valkey-node-1 -c valkey -- \
  valkey-cli -a PASSWORD JSON.SET test '$' '{"failover":"ok"}'
```

## References

- [Valkey](https://valkey.io/) - Redis fork by Linux Foundation
- [Valkey JSON Module](https://github.com/valkey-io/valkey-json)
- [Bitnami Valkey](https://github.com/bitnami/containers/tree/main/bitnami/valkey)
- [Bitnami Valkey Chart](https://github.com/bitnami/charts/tree/main/bitnami/valkey)

## License

Apache 2.0 - See [LICENSE](LICENSE) file for details.
