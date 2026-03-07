#!/bin/bash
# ACL enforcement test - verifies anonymous users cannot read sensitive data
set -eo pipefail

# Default values
LDAP_HOST="${LDAP_HOST:-localhost}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=Manager,dc=example,dc=com}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-admin}"
BASE_DN="${BASE_DN:-dc=example,dc=com}"

echo "=========================================="
echo "ACL Enforcement Test"
echo "=========================================="
echo "Testing that anonymous users cannot read user entries"
echo ""

# Test 1: Anonymous bind to rootDSE should work
echo "=== Test 1: Anonymous bind to rootDSE ==="
if ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT -b "" -s base "(objectClass=*)" 2>&1 | grep -q "namingContexts"; then
    echo "✓ PASS: Anonymous bind to rootDSE works (expected)"
else
    echo "✗ FAIL: Cannot read rootDSE anonymously"
    exit 1
fi

# Test 2: Anonymous read of base domain should fail
echo ""
echo "=== Test 2: Anonymous read of user entries ==="
ANON_RESULT=$(ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT -b "$BASE_DN" "(objectClass=inetOrgPerson)" cn 2>&1 || true)

if echo "$ANON_RESULT" | grep -q "No such object\|Insufficient access\|size limit exceeded"; then
    echo "✓ PASS: Anonymous read correctly denied"
elif echo "$ANON_RESULT" | grep -q "^dn:"; then
    echo "✗ FAIL: Anonymous read returned entries (ACL too permissive)!"
    echo "Output: $ANON_RESULT"
    exit 1
else
    echo "? UNCLEAR: Anonymous read result ambiguous"
    echo "Output: $ANON_RESULT"
fi

# Test 3: Authenticated read should work
echo ""
echo "=== Test 3: Authenticated read of user entries ==="
if ldapsearch -x -H ldap://$LDAP_HOST:$LDAP_PORT \
    -D "$LDAP_ADMIN_DN" \
    -w "$LDAP_ADMIN_PASSWORD" \
    -b "$BASE_DN" \
    "(objectClass=*)" 2>&1 | grep -q "^dn:"; then
    echo "✓ PASS: Authenticated read works"
else
    echo "✗ FAIL: Authenticated read failed"
    exit 1
fi

echo ""
echo "=========================================="
echo "ACL tests complete"
echo "=========================================="
