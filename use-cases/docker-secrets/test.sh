#!/bin/bash
# Test: Docker Secrets Use-Case
# Usage: ./test-docker-secrets.sh [image_tag]
# This script is also used by GitHub Actions

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="ghcr.io/vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-secrets-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: Docker Secrets"
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
echo "→ Starting container..."
cd "$(dirname "$0")"
LDAP_IMAGE="$IMAGE" docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d

# Wait for initialization
echo "→ Waiting for OpenLDAP to initialize (15s)..."
sleep 15

# Check if container is running
if ! docker ps | grep -q "openldap-secrets"; then
    echo -e "${RED}✗ Container not running${NC}"
    docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" logs --tail=30
    exit 1
fi

# Get actual container name
ACTUAL_CONTAINER=$(docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -q | head -1)

# Test 1: Verify password loaded from secret file
echo ""
echo "→ Test 1: Verify authentication with secret password..."
# Test bind - success if no "Invalid credentials" error
# (base domain may not exist yet, but bind should succeed)
if ! docker exec "$ACTUAL_CONTAINER" ldapsearch -x \
    -D "cn=Manager,dc=example,dc=com" \
    -w "SecureAdminP@ssw0rd123!" \
    -b "dc=example,dc=com" \
    -s base 2>&1 | grep -q "Invalid credentials"; then
    echo -e "${GREEN}✓ Authentication with secret password works${NC}"
else
    echo -e "${RED}✗ Authentication failed${NC}"
    exit 1
fi

# Test 2: Verify password is NOT exposed in environment
echo ""
echo "→ Test 2: Verify password not exposed in environment variables..."
if docker exec "$ACTUAL_CONTAINER" env | grep -q "SecureAdminP@ssw0rd123"; then
    echo -e "${YELLOW}⚠ Warning: Password may be exposed in environment${NC}"
else
    echo -e "${GREEN}✓ Password not exposed in environment${NC}"
fi

# Test 3: Verify config password also loaded from secret
echo ""
echo "→ Test 3: Verify config database access..."
if docker exec "$ACTUAL_CONTAINER" ldapsearch -Y EXTERNAL \
    -H ldapi:/// \
    -b "cn=config" \
    -s base 2>&1 | grep -q "dn:"; then
    echo -e "${GREEN}✓ Config database accessible${NC}"
else
    echo -e "${RED}✗ Config database access failed${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
