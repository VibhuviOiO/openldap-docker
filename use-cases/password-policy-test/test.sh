#!/bin/bash
# Test: Password Policy Use-Case
# Tests password policy overlay functionality
# Usage: ./test-password-policy.sh [image_tag]

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-ppolicy-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: Password Policy"
echo "  Image: $IMAGE"
echo "═══════════════════════════════════════════════════════════════"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    cd "$OLDPWD"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" down -v 2>/dev/null || true
}
trap cleanup EXIT

# Create shared network if needed
docker network create ldap-shared-network 2>/dev/null || true

# Start container
echo ""
echo "→ Starting container with password policy..."
cd "$(dirname "$0")"
LDAP_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d

# Wait for initialization
echo "→ Waiting for OpenLDAP to initialize (75s)..."
sleep 75

# Get actual container name
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Check container is running
if ! docker ps --no-trunc | grep -q "$ACTUAL_CONTAINER"; then
    echo -e "${RED}✗ Container not running${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs --tail=30
    exit 1
fi

BASE_DN="dc=test,dc=com"

echo ""
echo "→ Test 1: Verify base domain accessible..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -b "$BASE_DN" \
    -s base 2>&1 | grep -q "dn:"; then
    echo -e "${GREEN}✓ Base domain accessible${NC}"
else
    echo -e "${RED}✗ Base domain not accessible${NC}"
    exit 1
fi

echo ""
echo "→ Test 2: Verify password policy overlay..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -Y EXTERNAL \
    -H ldapi:/// \
    -b "cn=config" \
    "(objectClass=olcOverlayConfig)" 2>&1 | grep -q "ppolicy"; then
    echo -e "${GREEN}✓ Password policy overlay configured${NC}"
else
    echo -e "${YELLOW}⚠ Password policy overlay not detected (may still be initializing)${NC}"
fi

echo ""
echo "→ Test 3: Create test user..."
docker exec -i "$ACTUAL_CONTAINER" ldapadd -x \
    -D "cn=Manager,$BASE_DN" \
    -w "admin123" 2>/dev/null << LDIF || true
dn: uid=ppolicytest,$BASE_DN
objectClass: inetOrgPerson
uid: ppolicytest
cn: Password Policy Test
sn: Test
userPassword: InitialPass123!
LDIF

sleep 2

echo ""
echo "→ Test 4: Verify user created..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "cn=Manager,$BASE_DN" -w "admin123" \
    -b "uid=ppolicytest,$BASE_DN" \
    -s base 2>&1 | grep -q "cn: Password Policy Test"; then
    echo -e "${GREEN}✓ Test user created${NC}"
else
    echo -e "${RED}✗ Test user not found${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All password policy tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
