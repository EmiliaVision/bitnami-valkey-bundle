# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Valkey 9.0.0 with Bitnami-style configuration, JSON/Bloom modules, and Sentinel for high availability.

**Stack**:
- `valkey/valkey:9.0.0` (Debian Trixie, glibc 2.41)
- `valkey-bundle:9.0.0` modules (JSON, Bloom)
- Bitnami scripts for env var configuration (VALKEY_PASSWORD, VALKEY_EXTRA_FLAGS, etc)
- Sentinel for HA

## Development Commands

```bash
# Start complete environment (1 primary + 2 replicas + 3 sentinels)
docker compose up -d

# Rebuild after Dockerfile changes
docker compose down && docker compose build --no-cache && docker compose up -d

# View logs
docker compose logs -f valkey-master

# Connect to master (password: secretpassword, port: 6380)
docker exec -it valkey-master valkey-cli -a secretpassword

# Run tests
./tests/test-modules.sh      # All modules (JSON + Bloom)
./tests/test-json.sh         # JSON module only
./tests/test-sentinel.sh     # Sentinel HA

# Clean everything
docker compose down -v
```

## Critical Gotchas

### 1. Version Compatibility
We use `valkey/valkey:9.0.0` (glibc 2.41) + `valkey-bundle:9.0.0` for matching versions.
Bitnami scripts are copied from `bitnami/valkey:latest` for env var support.

### 2. Nomenclature: master -> primary
Bitnami uses updated terminology:
```yaml
VALKEY_REPLICATION_MODE: primary  # not "master"
VALKEY_PRIMARY_HOST: valkey-master
```

### 3. Sentinel master name
Bitnami uses `myprimary`, not `mymaster`:
```bash
SENTINEL get-master-addr-by-name myprimary
```

### 4. Local port
Uses port 6380 to avoid conflicts with local Redis/Valkey.

## Architecture

Multi-stage Dockerfile combining:
1. `valkey/valkey:9.0.0` - base image with Valkey server
2. `valkey-bundle:9.0.0` - modules (JSON, Bloom)
3. `bitnami/valkey:latest` - scripts for env var configuration

Modules are loaded via `VALKEY_EXTRA_FLAGS`:
```yaml
VALKEY_EXTRA_FLAGS: --loadmodule /opt/bitnami/valkey/modules/libjson.so --loadmodule /opt/bitnami/valkey/modules/libvalkey_bloom.so
```

## Environment Variables Reference

**Primary**: `VALKEY_REPLICATION_MODE=primary`, `VALKEY_PASSWORD`, `VALKEY_EXTRA_FLAGS`

**Replica**: Same as primary + `VALKEY_PRIMARY_HOST`, `VALKEY_PRIMARY_PORT_NUMBER`, `VALKEY_PRIMARY_PASSWORD`

**Sentinel**: `VALKEY_PRIMARY_HOST`, `VALKEY_PRIMARY_PASSWORD`, `VALKEY_SENTINEL_QUORUM=2`, `VALKEY_SENTINEL_DOWN_AFTER_MILLISECONDS=10000`

## Helm/Kubernetes

Requires `global.security.allowInsecureImages: true` for non-Bitnami images.

```bash
# Deploy with Bitnami chart
helm install valkey oci://registry-1.docker.io/bitnamicharts/valkey -f helm/values.yaml
```

## CI/CD (GitHub Actions)

Build y publicación automática a `ghcr.io` en `.github/workflows/build-publish.yml`.

**Triggers**: push a main, tags `v*`, PRs, manual (workflow_dispatch)

**Tags publicados automáticamente**:
- `latest` - última versión
- `9.0.0` - versión de Valkey (detectada automáticamente)
- `9.0.0-bundle-8` - versión completa (Valkey + bundle)
- `<sha>` - commit SHA

```bash
# Usar la imagen publicada
docker pull ghcr.io/emiliavision/bitnami-valkey-bundle:latest
docker pull ghcr.io/emiliavision/bitnami-valkey-bundle:9.0.0
```

**Nota sobre versiones**: Bitnami solo ofrece `latest` gratis en Docker Hub (sin tags de versión). Por eso hacemos build propio y publicamos en ghcr.io con versionado automático.

## Kubernetes Testing (GKE Autopilot)

```bash
# Deploy test environment
helm install valkey-test oci://registry-1.docker.io/bitnamicharts/valkey \
  -f helm/values-test.yaml -n valkey-test --create-namespace

# Check pods
kubectl get pods -n valkey-test

# Verify modules
kubectl exec -n valkey-test valkey-test-node-0 -c valkey -- \
  valkey-cli -a testpassword123 --no-auth-warning MODULE LIST

# Test JSON
kubectl exec -n valkey-test valkey-test-node-0 -c valkey -- \
  valkey-cli -a testpassword123 --no-auth-warning JSON.SET test '$' '{"ok":true}'

# Check Sentinel master
kubectl exec -n valkey-test valkey-test-node-0 -c sentinel -- \
  valkey-cli -p 26379 -a testpassword123 --no-auth-warning SENTINEL get-master-addr-by-name myprimary

# Simulate failover (kill master)
kubectl delete pod -n valkey-test valkey-test-node-0 --force --grace-period=0

# Wait ~10s, verify new master
kubectl exec -n valkey-test valkey-test-node-1 -c valkey -- \
  valkey-cli -a testpassword123 --no-auth-warning ROLE

# Cleanup
kubectl delete namespace valkey-test
```

**Failover tested**: Double failover (kill node-0 → node-1 promoted → kill node-1 → node-0 promoted back). Data integrity preserved.

## Quick Verification

```bash
# Verify modules loaded
docker exec valkey-master valkey-cli -a secretpassword MODULE LIST

# Test JSON
docker exec valkey-master valkey-cli -a secretpassword JSON.SET test '$' '{"ok":true}'

# Test Bloom
docker exec valkey-master valkey-cli -a secretpassword BF.ADD myfilter item1

# Verify replication
docker exec valkey-replica-1 valkey-cli -a secretpassword JSON.GET test '$'

# Verify Sentinel
docker exec valkey-sentinel-1 valkey-cli -p 26379 SENTINEL get-master-addr-by-name myprimary
```
