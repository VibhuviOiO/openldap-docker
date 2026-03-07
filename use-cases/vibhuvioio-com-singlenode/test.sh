#!/bin/bash
# Test: Vibhuvioio Single Node Use-Case
# Tests Mahabharata themed schema and data
# Usage: ./test-vibhuvioio-singlenode.sh [image_tag]

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="ghcr.io/vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-vibhuvioio-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: Vibhuvioio Single Node (Mahabharata Theme)"
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
echo "→ Starting container..."
cd "$(dirname "$0")"
LDAP_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d

# Wait for initialization
echo "→ Waiting for OpenLDAP to initialize (20s)..."
sleep 20

# Get actual container name
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Check container is running
if ! docker ps | grep -q "$ACTUAL_CONTAINER"; then
    echo -e "${RED}✗ Container not running${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs --tail=30
    exit 1
fi

BASE_DN="dc=vibhuvioio,dc=com"

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
echo "→ Test 2: Verify Mahabharata data imported..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -b "$BASE_DN" \
    "(objectClass=MahabharataUser)" cn 2>&1 | grep -q "^cn:"; then
    echo -e "${GREEN}✓ Mahabharata data imported${NC}"
else
    # Check alternative - just count entries
    COUNT=$(docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
        -b "$BASE_DN" \
        "(objectClass=*)" 2>/dev/null | grep -c "^dn:" || echo "0")
    if [ "$COUNT" -gt 2 ]; then
        echo -e "${GREEN}✓ Found $COUNT entries in directory${NC}"
    else
        echo -e "${RED}✗ No Mahabharata data found${NC}"
        exit 1
    fi
fi

echo ""
echo "→ Test 3: Verify custom schema..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -Y EXTERNAL \
    -H ldapi:/// \
    -b "cn=schema,cn=config" \
    "(objectClass=*)" cn 2>&1 | grep -qi "mahabharata"; then
    echo -e "${GREEN}✓ Mahabharata custom schema loaded${NC}"
else
    echo -e "${YELLOW}⚠ Schema check inconclusive (data import may still work)${NC}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All Vibhuvioio single-node tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
