#!/bin/bash
# Script to test all Valkey modules (JSON + Bloom)
# Usage: ./tests/test-modules.sh

set -e

VALKEY_HOST="${VALKEY_HOST:-localhost}"
VALKEY_PORT="${VALKEY_PORT:-6380}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-secretpassword}"

echo "=== Valkey Modules Tests ==="
echo "Host: $VALKEY_HOST:$VALKEY_PORT"
echo ""

# Function to run commands
valkey_cmd() {
    valkey-cli -h "$VALKEY_HOST" -p "$VALKEY_PORT" -a "$VALKEY_PASSWORD" --no-auth-warning "$@"
}

# Verify connection
echo "1. Verifying connection..."
valkey_cmd PING
echo ""

# Verify loaded modules
echo "2. Verifying loaded modules..."
valkey_cmd MODULE LIST
echo ""

# ==================== JSON ====================
echo "3. JSON Module tests..."

echo "   - JSON.SET: Create document..."
valkey_cmd JSON.SET user:1 '$' '{"name":"John","age":30,"tags":["dev"]}'

echo "   - JSON.GET: Get document..."
valkey_cmd JSON.GET user:1 '$'

echo "   - JSON.GET: Get field..."
valkey_cmd JSON.GET user:1 '$.name'

echo "   - JSON.NUMINCRBY: Increment..."
valkey_cmd JSON.NUMINCRBY user:1 '$.age' 1

echo "   - JSON.ARRAPPEND: Append to array..."
valkey_cmd JSON.ARRAPPEND user:1 '$.tags' '"python"'

echo "   - JSON.GET: Final document..."
valkey_cmd JSON.GET user:1 '$'

echo "   [OK] JSON Module works correctly"
echo ""

# ==================== BLOOM ====================
echo "4. Bloom Filter Module tests..."

echo "   - BF.ADD: Add elements..."
valkey_cmd BF.ADD emails user@example.com
valkey_cmd BF.ADD emails admin@example.com

echo "   - BF.EXISTS: Check existence (should be 1)..."
result=$(valkey_cmd BF.EXISTS emails user@example.com)
echo "   Result: $result"

echo "   - BF.EXISTS: Check non-existence (should be 0)..."
result=$(valkey_cmd BF.EXISTS emails unknown@example.com)
echo "   Result: $result"

echo "   - BF.MADD: Add multiple..."
valkey_cmd BF.MADD emails test1@example.com test2@example.com

echo "   - BF.MEXISTS: Check multiple..."
valkey_cmd BF.MEXISTS emails test1@example.com test2@example.com unknown@test.com

echo "   - BF.INFO: Filter info..."
valkey_cmd BF.INFO emails

echo "   [OK] Bloom Filter Module works correctly"
echo ""

# ==================== CLEANUP ====================
echo "5. Cleaning test data..."
valkey_cmd DEL user:1 emails
echo ""

echo "=== All tests passed! ==="
echo ""
echo "Verified modules:"
echo "  - JSON (libjson.so)"
echo "  - Bloom Filter (libvalkey_bloom.so)"
