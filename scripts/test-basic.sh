#!/bin/bash
# Basic connectivity test - doesn't require authentication
# Usage: test-basic.sh [host] [port]

set -e

HOST="${1:-localhost}"
PORT="${2:-389}"

# Test 1: Test anonymous bind
if ! ldapsearch -x -H "ldap://${HOST}:${PORT}" -b "" -s base >/dev/null 2>&1; then
    echo "FAIL: Cannot connect to LDAP"
    exit 1
fi

# Test 2: Check rootDSE
ROOT_DSE=$(ldapsearch -x -H "ldap://${HOST}:${PORT}" -b "" -s base 2>/dev/null)
if ! echo "$ROOT_DSE" | grep -q "OpenLDAProotDSE"; then
    echo "FAIL: Invalid rootDSE response"
    exit 1
fi

echo "OK: LDAP basic connectivity test passed"
exit 0
