#!/bin/bash
# Idempotency and data persistence test
# Verifies that restarting the container doesn't corrupt data or cause errors
set -eo pipefail

LDAP_HOST="openldap-idempotency"
LDAP_ADMIN_DN="cn=Manager,dc=example,dc=com"
LDAP_ADMIN_PASSWORD="AdminPass123!"
BASE_DN="dc=example,dc=com"

echo "=========================================="
echo "Idempotency and Data Persistence Test"
echo "=========================================="

# Wait for first initialization
sleep 5

echo ""
echo "=== Phase 1: Initial Data Creation ==="

# Create test data
ldapadd -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" << EOF
dn: ou=TestUsers,$BASE_DN
objectClass: organizationalUnit
ou: TestUsers

dn: uid=testuser,ou=TestUsers,$BASE_DN
objectClass: inetOrgPerson
uid: testuser
cn: Test User
sn: User
userPassword: InitialPass123!
EOF

# Verify data exists
echo "Verifying initial data..."
if ldapsearch -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
    -b "uid=testuser,ou=TestUsers,$BASE_DN" "(objectClass=*)" cn | grep -q "cn: Test User"; then
    echo "✓ Initial data created successfully"
else
    echo "✗ Failed to create initial data"
    exit 1
fi

# Store entry count
INITIAL_COUNT=$(ldapsearch -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
    -b "$BASE_DN" "(objectClass=*)" | grep -c "^dn:" || true)
echo "Initial entry count: $INITIAL_COUNT"

echo ""
echo "=== Phase 2: Simulating Container Restart ==="
echo "Container will restart when this init script completes."
echo "Check container logs to verify idempotent initialization."

# Create a marker file to track restart
if [ -f /tmp/ldap-init/.restart_marker ]; then
    RESTART_COUNT=$(cat /tmp/ldap-init/.restart_marker)
    RESTART_COUNT=$((RESTART_COUNT + 1))
else
    RESTART_COUNT=1
fi
echo "$RESTART_COUNT" > /tmp/ldap-init/.restart_marker

echo "Restart marker: $RESTART_COUNT"

# On first run, we stop here (init scripts only run once)
# The test requires manual restart or CI orchestration
if [ "$RESTART_COUNT" -eq 1 ]; then
    echo ""
    echo "First initialization complete. Data created."
    echo "To test idempotency, restart the container:"
    echo "  docker-compose restart"
    echo ""
    echo "Then verify:"
    echo "  1. No errors in logs during second initialization"
    echo "  2. Data still exists (entry count: $INITIAL_COUNT)"
    echo "  3. No duplicate entries created"
fi

echo ""
echo "=========================================="
echo "Phase 1 initialization complete"
echo "=========================================="
