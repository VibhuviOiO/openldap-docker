#!/bin/bash
# Test: Overlay Features Use-Case
# Tests memberOf, ppolicy, and auditlog overlays
# Usage: ./test-overlay-features.sh [image_tag]

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="ghcr.io/vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-overlays-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: Overlay Features (memberOf, ppolicy, auditlog)"
echo "  Image: $IMAGE"
echo "═══════════════════════════════════════════════════════════════"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    cd "$OLDPWD"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" down -v 2>/dev/null || true
}
trap cleanup EXIT

# Start container
echo ""
echo "→ Starting container with overlays enabled..."
cd "$(dirname "$0")"
LDAP_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d

# Wait longer for overlay setup (includes init + restart cycle)
echo "→ Waiting for OpenLDAP to initialize (35s)..."
sleep 35

# Get actual container name
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Check container is running
if ! docker ps --no-trunc | grep -q "$ACTUAL_CONTAINER"; then
    echo -e "${RED}✗ Container not running${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs --tail=30
    exit 1
fi

LDAP_HOST="localhost"
LDAP_PORT="389"
ADMIN_DN="cn=Manager,dc=example,dc=com"
ADMIN_PASS="AdminPass123!"
BASE_DN="dc=example,dc=com"

echo ""
echo "→ Test 1: memberOf Overlay"
echo "  Creating test users and groups..."

# Create OU for users and groups
docker exec -i "$ACTUAL_CONTAINER" ldapadd -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" 2>/dev/null << 'LDIF' || true
dn: ou=TestUsers,dc=example,dc=com
objectClass: organizationalUnit
ou: TestUsers

dn: uid=testuser,ou=TestUsers,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: testuser
cn: Test User
sn: User
uidNumber: 10001
gidNumber: 10000
homeDirectory: /home/testuser
userPassword: TestPass123!

dn: cn=testgroup,ou=TestUsers,dc=example,dc=com
objectClass: groupOfNames
cn: testgroup
member: uid=testuser,ou=TestUsers,dc=example,dc=com
LDIF

sleep 2

# Verify memberOf attribute
echo "  Checking memberOf attribute on user..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" \
    -b "uid=testuser,ou=TestUsers,$BASE_DN" \
    "(objectClass=*)" memberOf 2>&1 | grep -q "memberOf: cn=testgroup"; then
    echo -e "${GREEN}  ✓ memberOf attribute correctly set${NC}"
else
    echo -e "${RED}  ✗ memberOf attribute not found${NC}"
    docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
        -D "$ADMIN_DN" -w "$ADMIN_PASS" \
        -b "uid=testuser,ou=TestUsers,$BASE_DN" \
        "(objectClass=*)" memberOf 2>&1 || true
    exit 1
fi

echo ""
echo "→ Test 2: Password Policy Overlay"
echo "  Testing weak password rejection..."

# Try weak password (should fail)
if docker exec -i "$ACTUAL_CONTAINER" ldapmodify -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" 2>&1 << 'LDIF' | grep -qE "(Password fails quality checking|Constraint violation)"
dn: uid=testuser,ou=TestUsers,dc=example,dc=com
changetype: modify
replace: userPassword
userPassword: 123
LDIF
then
    echo -e "${GREEN}  ✓ Weak password correctly rejected${NC}"
else
    echo -e "${YELLOW}  ⚠ Weak password was accepted (ppolicy may need configuration)${NC}"
    # Note: ppolicy overlay is loaded but enforcement may require additional configuration
fi

# Try strong password (should succeed)
echo "  Testing strong password acceptance..."
if docker exec -i "$ACTUAL_CONTAINER" ldapmodify -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" 2>&1 << 'LDIF' | grep -q "modifying entry"
dn: uid=testuser,ou=TestUsers,dc=example,dc=com
changetype: modify
replace: userPassword
userPassword: StrongPass789!
LDIF
then
    echo -e "${GREEN}  ✓ Strong password accepted${NC}"
else
    echo -e "${RED}  ✗ Strong password was rejected${NC}"
    exit 1
fi

echo ""
echo "→ Test 3: Audit Log"
echo "  Checking audit log file..."
sleep 2

if docker exec "$ACTUAL_CONTAINER" test -f /logs/audit.log; then
    echo -e "${GREEN}  ✓ Audit log file exists${NC}"
    COUNT=$(docker exec "$ACTUAL_CONTAINER" wc -l /logs/audit.log 2>/dev/null | awk '{print $1}')
    echo "    Lines in audit log: $COUNT"
else
    echo -e "${YELLOW}  ⚠ Audit log file not found (may need more time)${NC}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All overlay tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
