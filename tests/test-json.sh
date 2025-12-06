#!/bin/bash
# Script to test JSON module in Valkey
# Usage: ./tests/test-json.sh

set -e

VALKEY_HOST="${VALKEY_HOST:-localhost}"
VALKEY_PORT="${VALKEY_PORT:-6380}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-secretpassword}"

echo "=== Valkey JSON Module Tests ==="
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

# Verify module loaded
echo "2. Verifying loaded modules..."
valkey_cmd MODULE LIST
echo ""

# JSON tests
echo "3. JSON tests..."

echo "   - JSON.SET: Create document..."
valkey_cmd JSON.SET user:1 '$' '{"name":"John","age":30,"city":"Madrid"}'

echo "   - JSON.GET: Get full document..."
valkey_cmd JSON.GET user:1 '$'

echo "   - JSON.GET: Get specific field..."
valkey_cmd JSON.GET user:1 '$.name'

echo "   - JSON.SET: Update field..."
valkey_cmd JSON.SET user:1 '$.age' '31'

echo "   - JSON.GET: Verify update..."
valkey_cmd JSON.GET user:1 '$.age'

echo "   - JSON.ARRAPPEND: Add array..."
valkey_cmd JSON.SET user:1 '$.hobbies' '["reading"]'
valkey_cmd JSON.ARRAPPEND user:1 '$.hobbies' '"coding"' '"traveling"'

echo "   - JSON.GET: Verify array..."
valkey_cmd JSON.GET user:1 '$.hobbies'

echo "   - JSON.NUMINCRBY: Increment number..."
valkey_cmd JSON.NUMINCRBY user:1 '$.age' 1

echo "   - JSON.GET: Final document..."
valkey_cmd JSON.GET user:1 '$'

# Cleanup
echo ""
echo "4. Cleaning test data..."
valkey_cmd DEL user:1

echo ""
echo "=== All tests passed! ==="
