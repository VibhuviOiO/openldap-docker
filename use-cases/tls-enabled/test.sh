#!/bin/bash
# Test: TLS/SSL Use-Case
# Tests StartTLS and LDAPS connections
# Usage: ./test-tls.sh [image_tag]

set -e

IMAGE_TAG="${1:-latest}"
IMAGE="ghcr.io/vibhuvioio/openldap:${IMAGE_TAG}"
CONTAINER_NAME="openldap-tls-test"
COMPOSE_FILE="docker-compose.yml"

echo "═══════════════════════════════════════════════════════════════"
echo "  Test: TLS/SSL (StartTLS and LDAPS)"
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

# Start container
echo ""
echo "→ Starting container with TLS..."
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

ADMIN_DN="cn=Manager,dc=example,dc=com"
ADMIN_PASS="AdminPass123!"
BASE_DN="dc=example,dc=com"

echo ""
echo "→ Test 1: StartTLS (LDAP with TLS upgrade)"
# Use LDAPTLS_REQCERT=never to allow self-signed certificates in test
if docker exec "$ACTUAL_CONTAINER" bash -c "LDAPTLS_REQCERT=never ldapsearch -x -H ldap://localhost:389 -ZZ -D '$ADMIN_DN' -w '$ADMIN_PASS' -b '$BASE_DN' -s base" 2>&1 | grep -q "dn:"; then
    echo -e "${GREEN}✓ StartTLS connection successful${NC}"
else
    echo -e "${RED}✗ StartTLS connection failed${NC}"
    exit 1
fi

echo ""
echo "→ Test 2: LDAPS (Direct SSL on port 636)"
if docker exec "$ACTUAL_CONTAINER" bash -c "LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://localhost:636 -D '$ADMIN_DN' -w '$ADMIN_PASS' -b '$BASE_DN' -s base" 2>&1 | grep -q "dn:"; then
    echo -e "${GREEN}✓ LDAPS connection successful${NC}"
else
    echo -e "${RED}✗ LDAPS connection failed${NC}"
    exit 1
fi

echo ""
echo "→ Test 3: TLS Certificate Files"
if docker exec "$ACTUAL_CONTAINER" test -f /certs/ldap.crt && \
   docker exec "$ACTUAL_CONTAINER" test -f /certs/ldap.key; then
    echo -e "${GREEN}✓ TLS certificate files present${NC}"
else
    echo -e "${RED}✗ TLS certificate files missing${NC}"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}  ✓ All TLS tests passed!${NC}"
echo "═══════════════════════════════════════════════════════════════"
exit 0
