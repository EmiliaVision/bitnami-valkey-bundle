# CLAUDE.md - AI Development Guide

This file documents project context for AI assistants (Claude, Copilot, etc).

## Project Purpose

This is a **POC (Proof of Concept)** that serves as a learning base to:
1. Understand how to extend Bitnami images
2. Integrate Valkey modules from valkey-bundle
3. Configure high availability with Sentinel
4. Eventually create an open source project

## Technical Context

### Stack
- **Valkey 9.0.0** - Redis fork by Linux Foundation
- **Bitnami Valkey** - Base image (Photon OS)
- **valkey-bundle** - Precompiled modules (JSON, Bloom, Search, LDAP)
- **Sentinel** - High availability

### Architecture Decisions

1. **Binaries from valkey-bundle**: Instead of compiling, we copy precompiled modules
2. **valkey-bundle:8-bookworm**: Specific tag for glibc compatibility with Photon OS
3. **Separate Sentinel**: Using official bitnami/valkey-sentinel image
4. **VALKEY_PRIMARY_* variables**: Updated nomenclature (not MASTER)

### Why valkey-bundle instead of compiling?

| Aspect | Compile | valkey-bundle |
|--------|---------|---------------|
| Build time | ~2 min | ~5 sec |
| Compatibility | glibc risk | Guaranteed |
| Maintenance | Manual | Official |
| Extra modules | Compile each | Included |

## Project Structure

```
.
├── CLAUDE.md                 # This file (AI context)
├── README.md                 # Public documentation
├── docker/
│   ├── Dockerfile            # Multi-stage: bundle source + bitnami runtime
│   └── .dockerignore
├── docker-compose.yml        # Local stack: primary + 2 replicas + 3 sentinels
├── helm/
│   ├── values.yaml           # Production config (Kubernetes)
│   └── values-local.yaml     # Development config (minikube/kind)
└── tests/
    ├── test-json.sh          # JSON module tests
    ├── test-modules.sh       # All modules tests
    └── test-sentinel.sh      # Sentinel tests
```

## Development Commands

```bash
# Start complete environment
docker compose up -d

# Rebuild after Dockerfile changes
docker compose down && docker compose build --no-cache && docker compose up -d

# View logs
docker compose logs -f valkey-master
docker compose logs -f valkey-sentinel-1

# Connect to master
docker exec -it valkey-master valkey-cli -a secretpassword

# Run tests
./tests/test-json.sh
./tests/test-modules.sh
./tests/test-sentinel.sh

# Clean everything
docker compose down -v
```

## Gotchas and Known Issues

### 1. glibc Compatibility (MOST IMPORTANT)
valkey-bundle has Alpine (musl) and Debian (glibc) variants. Bitnami uses Photon OS with glibc 2.36.

```
8-alpine     -> musl       -> DOES NOT WORK (libc.musl not found)
8-trixie     -> glibc 2.38 -> DOES NOT WORK (GLIBC_2.38 not found)
8-bookworm   -> glibc 2.36 -> WORKS
```

**Solution**: Always use `valkey-bundle:8-bookworm`.

### 2. Module Permissions
Modules need execute permissions (755), not just read.
```dockerfile
RUN chmod 755 /opt/bitnami/valkey/modules/libjson.so  # CORRECT
RUN chmod 644 /opt/bitnami/valkey/modules/libjson.so  # INCORRECT
```

### 3. Nomenclature master -> primary
Bitnami changed terminology in Oct 2024.
```yaml
# INCORRECT
VALKEY_REPLICATION_MODE=master
VALKEY_MASTER_HOST=...

# CORRECT
VALKEY_REPLICATION_MODE=primary
VALKEY_PRIMARY_HOST=...
```

### 4. Port 6379 busy
If you already have Redis/Valkey running, change the port in docker-compose.yml.
Currently uses 6380.

### 5. Master name in Sentinel
Bitnami uses `myprimary`, not `mymaster`.
```bash
SENTINEL get-master-addr-by-name myprimary  # CORRECT
SENTINEL get-master-addr-by-name mymaster   # INCORRECT
```

### 6. Module location in valkey-bundle
Modules are in `/usr/lib/valkey/`:
- `libjson.so` - JSON
- `libvalkey_bloom.so` - Bloom filters
- `libsearch.so` - Full-text search (89MB)
- `libvalkey_ldap.so` - LDAP auth

## Important Environment Variables

### Primary (Master)
```yaml
VALKEY_REPLICATION_MODE: primary
VALKEY_PASSWORD: secretpassword
VALKEY_EXTRA_FLAGS: --loadmodule /opt/bitnami/valkey/modules/libjson.so --loadmodule /opt/bitnami/valkey/modules/libvalkey_bloom.so
```

### Replica
```yaml
VALKEY_REPLICATION_MODE: replica
VALKEY_PRIMARY_HOST: valkey-master
VALKEY_PRIMARY_PORT_NUMBER: 6379
VALKEY_PRIMARY_PASSWORD: secretpassword
VALKEY_PASSWORD: secretpassword
VALKEY_EXTRA_FLAGS: --loadmodule /opt/bitnami/valkey/modules/libjson.so --loadmodule /opt/bitnami/valkey/modules/libvalkey_bloom.so
```

### Sentinel
```yaml
VALKEY_PRIMARY_HOST: valkey-master
VALKEY_PRIMARY_PORT_NUMBER: 6379
VALKEY_PRIMARY_PASSWORD: secretpassword
VALKEY_SENTINEL_DOWN_AFTER_MILLISECONDS: 10000
VALKEY_SENTINEL_FAILOVER_TIMEOUT: 60000
VALKEY_SENTINEL_QUORUM: 2
```

## Workflow for Changes

1. **Dockerfile changes**:
   ```bash
   docker compose build --no-cache
   docker compose up -d
   ```

2. **docker-compose.yml changes**:
   ```bash
   docker compose down
   docker compose up -d
   ```

3. **helm/values.yaml changes**:
   ```bash
   helm upgrade valkey oci://registry-1.docker.io/bitnamicharts/valkey -f helm/values.yaml
   ```

## Quick Tests

```bash
# Verify module loaded
docker exec valkey-master valkey-cli -a secretpassword MODULE LIST

# Test JSON
docker exec valkey-master valkey-cli -a secretpassword JSON.SET test '$' '{"ok":true}'
docker exec valkey-master valkey-cli -a secretpassword JSON.GET test '$'

# Test Bloom
docker exec valkey-master valkey-cli -a secretpassword BF.ADD myfilter item1
docker exec valkey-master valkey-cli -a secretpassword BF.EXISTS myfilter item1

# Verify replication
docker exec valkey-replica-1 valkey-cli -a secretpassword JSON.GET test '$'

# Verify Sentinel
docker exec valkey-sentinel-1 valkey-cli -p 26379 SENTINEL masters
docker exec valkey-sentinel-1 valkey-cli -p 26379 SENTINEL get-master-addr-by-name myprimary
```

## Kubernetes Failover Testing (GKE Autopilot)

### Results Summary

Tested on 2025-12-06 on GKE Autopilot. **Everything works without manual intervention.**

| Test | Result | Time |
|------|--------|------|
| Delete REPLICA | Pod recreated, reconnects automatically | ~30 sec |
| Delete PRIMARY | Sentinel failover, replica promoted | ~10 sec |
| Data post-failover | Intact and replicated correctly | - |
| Modules post-failover | JSON and Bloom work | - |
| Ex-master | Becomes replica automatically | - |

### Helm Configuration for Kubernetes

The `helm/values.yaml` file must include:

```yaml
# IMPORTANT: Required for custom images
global:
  security:
    allowInsecureImages: true

image:
  registry: us-east1-docker.pkg.dev  # or your registry
  repository: PROJECT/REPO/valkey-modules
  tag: "latest"
```

### Commands to test failover

```bash
# Get password
VALKEY_PASSWORD=$(kubectl get secret -n NAMESPACE RELEASE-NAME \
  -o jsonpath="{.data.valkey-password}" | base64 -d)

# Check current roles
kubectl exec -n NAMESPACE POD-0 -c valkey -- \
  valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning ROLE

# Insert test data
kubectl exec -n NAMESPACE POD-0 -c valkey -- \
  valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning \
  JSON.SET failover:test '$' '{"test":"before"}'

# SIMULATE FAILURE: Delete primary
kubectl delete pod -n NAMESPACE POD-0

# Monitor failover (Sentinel promotes replica in ~10 sec)
kubectl exec -n NAMESPACE POD-1 -c sentinel -- \
  valkey-cli -p 26379 -a "$VALKEY_PASSWORD" --no-auth-warning \
  SENTINEL get-master-addr-by-name myprimary

# Verify new master
kubectl exec -n NAMESPACE POD-1 -c valkey -- \
  valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning ROLE
# Should show: master

# Verify data intact
kubectl exec -n NAMESPACE POD-1 -c valkey -- \
  valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning \
  JSON.GET failover:test '$'

# When POD-0 returns, it becomes replica
kubectl exec -n NAMESPACE POD-0 -c valkey -- \
  valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning ROLE
# Should show: slave
```

### Failover Lessons

1. **Sentinel works correctly** with Bitnami chart
2. **No manual intervention required** - everything is automatic
3. **Modules persist** after failover
4. **Replication reconfigures** automatically
5. **downAfterMilliseconds: 10000** is a good value for fast failure detection

## Next Steps (TODO)

- [ ] Add automated tests with pytest
- [ ] CI/CD with GitHub Actions
- [ ] Publish image to Docker Hub / GHCR
- [ ] Document integration with applications (Python, Node.js)
- [ ] Add monitoring with Prometheus/Grafana
- [x] Test Sentinel automatic failover (COMPLETED)
- [ ] Custom Helm chart (not depend on Bitnami)

## Useful References

- [Valkey JSON Commands](https://valkey.io/commands/?group=json)
- [Bitnami Valkey ENV vars](https://github.com/bitnami/containers/tree/main/bitnami/valkey#configuration)
- [Sentinel Documentation](https://valkey.io/topics/sentinel/)

## Notes for Contributors

This project is intended as an educational base. When it becomes open source:

1. Separate Dockerfile into its own repo
2. Create GitHub Actions for automatic build
3. Publish to Docker Hub with tags per Valkey version
4. Create independent Helm chart
5. Add production usage documentation
