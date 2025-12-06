# Bitnami Valkey Bundle

Valkey 9.0.0 with Bitnami-style configuration, JSON/Bloom modules, and Sentinel for High Availability.

## Quick Start

```bash
# Use pre-built image from GitHub Container Registry
docker pull ghcr.io/emiliavision/bitnami-valkey-bundle:9.0.0

# Or start complete local stack (1 primary + 2 replicas + 3 sentinels)
docker compose up -d
```

## Image

| Registry | Image | Tags |
|----------|-------|------|
| ghcr.io | `ghcr.io/emiliavision/bitnami-valkey-bundle` | `latest`, `9.0.0`, `9.0.0-bundle-9.0` |

### What's Included

- **Valkey 9.0.0** - Redis-compatible in-memory data store
- **JSON Module** - Native JSON data type support
- **Bloom Module** - Probabilistic data structures
- **Bitnami Scripts** - Environment variable configuration (VALKEY_PASSWORD, etc.)
- **Multi-arch** - linux/amd64 and linux/arm64

## Kubernetes Deployment

```bash
# Deploy with Bitnami Helm chart
helm install valkey oci://registry-1.docker.io/bitnamicharts/valkey \
  -f helm/values.yaml \
  -n valkey --create-namespace
```

See [helm/values.yaml](helm/values.yaml) for production configuration or [helm/values-test.yaml](helm/values-test.yaml) for testing.

## Sentinel Failover (Tested on GKE Autopilot)

Comprehensive failover testing completed with the following results:

| Test | Result | Recovery Time |
|------|--------|---------------|
| Kill primary (node-0) | Sentinel promotes replica | ~5 sec |
| Kill new primary (node-1) | Sentinel promotes back | ~8 sec |
| Data integrity | Preserved through double failover | - |
| Ex-master rejoins | Automatically becomes replica | ~30 sec |
| Modules post-failover | JSON and Bloom work correctly | - |

This configuration is suitable for GCP Autopilot node evacuations.

---

## Lessons Learned

### 1. glibc Compatibility (Critical)

We use a **hybrid Dockerfile** approach because:
- `valkey-bundle:9.0.0` requires glibc 2.38+ (Debian Trixie)
- `bitnami/valkey:latest` uses Photon OS with glibc 2.36

**Solution**: Use `valkey/valkey:9.0.0` (Debian Trixie, glibc 2.41) as base, copy Bitnami scripts and bundle modules.

```dockerfile
FROM valkey/valkey-bundle:9.0.0 AS bundle
FROM bitnami/valkey:latest AS bitnami
FROM valkey/valkey:9.0.0

# Copy Bitnami scripts for env var support
COPY --from=bitnami /opt/bitnami/scripts/ /opt/bitnami/scripts/

# Copy modules from bundle
COPY --from=bundle /usr/lib/valkey/libjson.so /opt/bitnami/valkey/modules/
COPY --from=bundle /usr/lib/valkey/libvalkey_bloom.so /opt/bitnami/valkey/modules/
```

### 2. Nomenclature: Master -> Primary

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

## CI/CD

GitHub Actions automatically builds and publishes to ghcr.io on:
- Push to `main` branch
- Tags matching `v*`
- Manual trigger (workflow_dispatch)

See [.github/workflows/build-publish.yml](.github/workflows/build-publish.yml).

## Testing Failover in Kubernetes

```bash
# Deploy to test namespace
helm install valkey-test oci://registry-1.docker.io/bitnamicharts/valkey \
  -f helm/values-test.yaml -n valkey-test --create-namespace

# Check current master
kubectl exec -n valkey-test valkey-test-node-0 -c sentinel -- \
  valkey-cli -p 26379 -a PASSWORD --no-auth-warning SENTINEL get-master-addr-by-name myprimary

# Write test data
kubectl exec -n valkey-test valkey-test-node-0 -c valkey -- \
  valkey-cli -a PASSWORD --no-auth-warning JSON.SET test '$' '{"failover":"test"}'

# Kill master to trigger failover
kubectl delete pod -n valkey-test valkey-test-node-0 --force --grace-period=0

# Wait ~10 seconds, then verify new master
kubectl exec -n valkey-test valkey-test-node-1 -c valkey -- \
  valkey-cli -a PASSWORD --no-auth-warning ROLE

# Verify data integrity
kubectl exec -n valkey-test valkey-test-node-1 -c valkey -- \
  valkey-cli -a PASSWORD --no-auth-warning JSON.GET test '$'

# Cleanup
kubectl delete namespace valkey-test
```

## References

- [Valkey](https://valkey.io/) - Redis fork by Linux Foundation
- [Valkey JSON Module](https://github.com/valkey-io/valkey-json)
- [Bitnami Valkey](https://github.com/bitnami/containers/tree/main/bitnami/valkey)
- [Bitnami Valkey Chart](https://github.com/bitnami/charts/tree/main/bitnami/valkey)

## License

Apache 2.0 - See [LICENSE](LICENSE) file for details.
