#!/bin/bash
# Script to test Sentinel and failover
# Usage: ./tests/test-sentinel.sh

set -e

SENTINEL_HOST="${SENTINEL_HOST:-localhost}"
SENTINEL_PORT="${SENTINEL_PORT:-26379}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-secretpassword}"

echo "=== Valkey Sentinel Tests ==="
echo "Sentinel: $SENTINEL_HOST:$SENTINEL_PORT"
echo ""

# Function to run Sentinel commands
sentinel_cmd() {
    valkey-cli -h "$SENTINEL_HOST" -p "$SENTINEL_PORT" "$@"
}

# Function to run Valkey commands
valkey_cmd() {
    local host=$1
    local port=$2
    shift 2
    valkey-cli -h "$host" -p "$port" -a "$VALKEY_PASSWORD" --no-auth-warning "$@"
}

echo "1. Verifying Sentinel connection..."
sentinel_cmd PING
echo ""

echo "2. Getting master info..."
sentinel_cmd SENTINEL master myprimary
echo ""

echo "3. Getting replica list..."
sentinel_cmd SENTINEL replicas myprimary
echo ""

echo "4. Getting sentinel list..."
sentinel_cmd SENTINEL sentinels myprimary
echo ""

echo "5. Getting current master address..."
MASTER_INFO=$(sentinel_cmd SENTINEL get-master-addr-by-name myprimary)
MASTER_HOST=$(echo "$MASTER_INFO" | head -1)
MASTER_PORT=$(echo "$MASTER_INFO" | tail -1)
echo "   Master: $MASTER_HOST:$MASTER_PORT"
echo ""

echo "6. Verifying master role..."
valkey_cmd "$MASTER_HOST" "$MASTER_PORT" ROLE
echo ""

echo "7. Writing data to master..."
valkey_cmd "$MASTER_HOST" "$MASTER_PORT" SET test:sentinel "test_value"
valkey_cmd "$MASTER_HOST" "$MASTER_PORT" GET test:sentinel
echo ""

echo "8. Verifying replication..."
valkey_cmd "$MASTER_HOST" "$MASTER_PORT" INFO replication
echo ""

echo "9. Cleaning test data..."
valkey_cmd "$MASTER_HOST" "$MASTER_PORT" DEL test:sentinel

echo ""
echo "=== Sentinel tests completed! ==="
echo ""
echo "To test manual failover:"
echo "  sentinel_cmd SENTINEL failover myprimary"
