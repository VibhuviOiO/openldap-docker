#!/bin/bash
# Test: Idempotency and Data Persistence
# Tests that container restart doesn't lose data or error
# Usage: ./test-idempotency.sh [image_tag]

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="ghcr.io/vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-idempotency-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: Idempotency & Data Persistence"
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

ADMIN_DN="cn=Manager,dc=example,dc=com"
ADMIN_PASS="AdminPass123!"
BASE_DN="dc=example,dc=com"

# Start container
echo ""
echo "→ Phase 1: First start and data creation..."
cd "$(dirname "$0")"
LDAP_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d

# Wait for initialization
echo "→ Waiting for OpenLDAP to initialize (15s)..."
sleep 15

# Get actual container name
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Check container is running
if ! docker ps | grep -q "$ACTUAL_CONTAINER"; then
    echo -e "${RED}✗ Container not running on first start${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs --tail=30
    exit 1
fi

# Create test data
echo "→ Creating test data..."
docker exec -i "$ACTUAL_CONTAINER" ldapadd -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" 2>/dev/null << 'LDIF' || true
dn: ou=PersistenceTest,dc=example,dc=com
objectClass: organizationalUnit
ou: PersistenceTest

dn: uid=persistuser,ou=PersistenceTest,dc=example,dc=com
objectClass: inetOrgPerson
uid: persistuser
cn: Persistence Test User
sn: User
userPassword: PersistPass123!
LDIF

# Count entries after first start
INITIAL_COUNT=$(docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" \
    -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -c "^dn:" || echo "0")

echo "  Initial entry count: $INITIAL_COUNT"

if [ "$INITIAL_COUNT" -lt 3 ]; then
    echo -e "${RED}✗ Initial data not created properly${NC}"
    exit 1
fi

echo ""
echo "→ Phase 2: Restarting container..."
docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" restart

# Wait for restart
echo "→ Waiting for OpenLDAP to restart (15s)..."
sleep 15

# Get new container name after restart
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Check for idempotency (should say "already configured" not errors)
echo "→ Checking for idempotency markers..."
if docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs 2>&1 | grep -q "already configured\|already exists"; then
    echo -e "${GREEN}✓ Idempotency detected (configuration skipped as expected)${NC}"
else
    echo -e "${YELLOW}⚠ Idempotency markers not found (checking for errors)...${NC}"
fi

# Check for errors
if docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs 2>&1 | grep -iE "error|fail" | grep -v "already configured\|already exists\|error rate\|errorlog" | head -5; then
    echo -e "${RED}✗ Errors found during restart${NC}"
    exit 1
fi

# Verify data persistence
echo "→ Verifying data persistence..."
SECOND_COUNT=$(docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" \
    -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -c "^dn:" || echo "0")

echo "  Entry count after restart: $SECOND_COUNT"

if [ "$INITIAL_COUNT" -ne "$SECOND_COUNT" ]; then
    echo -e "${RED}✗ Entry count changed: $INITIAL_COUNT → $SECOND_COUNT${NC}"
    exit 1
fi

# Verify specific entry exists
if docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "$ADMIN_DN" -w "$ADMIN_PASS" \
    -b "uid=persistuser,ou=PersistenceTest,$BASE_DN" \
    "(objectClass=*)" 2>&1 | grep -q "cn: Persistence Test User"; then
    echo -e "${GREEN}✓ Test data persisted after restart${NC}"
else
    echo -e "${RED}✗ Test data not found after restart${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All idempotency tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
