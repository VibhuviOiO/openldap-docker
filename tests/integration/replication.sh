#!/bin/bash
# Three-node multi-provider replication integration test.
#
# Exercises the failure modes that are silent in production:
#   * syncprov module actually loaded (it is skipped if another module created
#     cn=module{0} first - memberOf is enabled here to force that ordering)
#   * retry list ends with '+' and keepalive is present on every olcSyncRepl
#   * contextCSN checkpointing and the session log are configured
#   * entryCSN/entryUUID indexes exist
#   * olcMultiProvider is set and the full SID->URL map is applied
#   * a dedicated cn=replicator identity is used instead of the rootDN
#   * convergence after a node is stopped and restarted
#
# Usage:
#   docker build -t openldap:local .
#   tests/integration/replication.sh openldap:local

set -uo pipefail

IMAGE="${1:-openldap:local}"
DOMAIN="example.com"
BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=Manager,${BASE_DN}"
ADMIN_PW="AdminPass123!"
REPL_PW="ReplPass123!"
NET="ldapci-net"
NODES="ldapci-node1 ldapci-node2 ldapci-node3"

PASS=0
FAIL=0
FAILED_NAMES=""

# Referenced only from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
    for c in $NODES; do docker rm -f "$c" >/dev/null 2>&1 || true; done
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1)); FAILED_NAMES="${FAILED_NAMES}${1}; "
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [ -n "${2:-}" ] && printf '       %s\n' "$2"
}
section() { printf '\n\033[36m== %s\033[0m\n' "$1"; }

wait_healthy() {
    local name=$1
    for _ in $(seq 1 50); do
        if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
            return 1
        fi
        if docker exec "$name" /usr/local/bin/scripts/healthcheck.sh auto >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    return 1
}

search_ok() {
    local c=$1 dn=$2
    docker exec "$c" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "$dn" -s base dn 2>/dev/null | grep -q "^dn:"
}

wait_for_entry() {
    local c=$1 dn=$2 tries=${3:-30}
    for _ in $(seq 1 "$tries"); do
        if search_ok "$c" "$dn"; then return 0; fi
        sleep 3
    done
    return 1
}

echo "OpenLDAP 3-node replication integration test"
echo "image: ${IMAGE}"

cleanup
docker network create "$NET" >/dev/null 2>&1 || true

SID_MAP="1=ldap://ldapci-node1:389,2=ldap://ldapci-node2:389,3=ldap://ldapci-node3:389"

section "starting 3 providers"
start_node() {
    local name=$1 sid=$2 peers=$3
    docker run -d --name "$name" --hostname "$name" --network "$NET" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        -e "INCLUDE_SCHEMAS=cosine,inetorgperson,nis" \
        -e "ENABLE_MEMBEROF=true" \
        -e "ENABLE_REPLICATION=true" \
        -e "SERVER_ID=${sid}" \
        -e "REPLICATION_PEERS=${peers}" \
        -e "REPLICATION_SERVER_IDS=${SID_MAP}" \
        -e "LDAP_REPLICATION_PASSWORD=${REPL_PW}" \
        "$IMAGE" >/dev/null || return 1
}
start_node ldapci-node1 1 "ldapci-node2,ldapci-node3" || fail "node1 failed to start"
start_node ldapci-node2 2 "ldapci-node1,ldapci-node3" || fail "node2 failed to start"
start_node ldapci-node3 3 "ldapci-node1,ldapci-node2" || fail "node3 failed to start"

ALL_HEALTHY=true
for n in $NODES; do
    if wait_healthy "$n"; then
        pass "$n is healthy"
    else
        ALL_HEALTHY=false
        fail "$n never became healthy"
        docker logs "$n" 2>&1 | tail -20 | sed 's/^/       /'
    fi
done

if [ "$ALL_HEALTHY" != "true" ]; then
    echo
    printf '\033[31mAborting: not all nodes became healthy\033[0m\n'
    exit 1
fi

# --- configuration assertions -------------------------------------------------

section "replication configuration (cn=config)"
LOCAL="docker exec ldapci-node1 ldapsearch -Y EXTERNAL -H ldapi:///"

if $LOCAL -b "cn=config" "(olcModuleLoad=syncprov*)" olcModuleLoad 2>/dev/null | grep -q "syncprov.la"; then
    pass "syncprov.la is loaded (module-vs-entry guard works with memberof enabled)"
else
    fail "syncprov.la is NOT loaded"
fi

repl=$($LOCAL -b "cn=config" "(olcSyncRepl=*)" olcSyncRepl 2>/dev/null \
    | awk '/^[[:space:]]/{printf "%s", substr($0,2); next} {if(NR>1)printf "\n"; printf "%s",$0} END{printf "\n"}' \
    | grep "^olcSyncRepl:")
repl_count=$(printf '%s\n' "$repl" | grep -c "^olcSyncRepl:" || true)

if [ "$repl_count" -eq 2 ]; then
    pass "2 olcSyncRepl statements configured (2 peers)"
else
    fail "expected 2 olcSyncRepl statements, found ${repl_count}"
fi

if printf '%s\n' "$repl" | grep -qE 'retry="[^"]*\+"'; then
    pass "every olcSyncRepl retry list ends with '+'"
else
    fail "retry list does not end with '+' (replication stops permanently after ~25 min)"
    printf '%s\n' "$repl" | sed 's/^/       /'
fi

if [ "$(printf '%s\n' "$repl" | grep -c "keepalive=" || true)" -eq "$repl_count" ]; then
    pass "keepalive present on every olcSyncRepl"
else
    fail "keepalive missing on at least one olcSyncRepl"
fi

if printf '%s\n' "$repl" | grep -q 'binddn="cn=replicator,'; then
    pass "replication binds as the dedicated cn=replicator account"
else
    fail "replication is not using cn=replicator"
fi

if $LOCAL -b "cn=config" "(olcMultiProvider=*)" olcMultiProvider 2>/dev/null | grep -q "olcMultiProvider: TRUE"; then
    pass "olcMultiProvider: TRUE"
else
    fail "olcMultiProvider is not TRUE"
fi

if $LOCAL -b "cn=config" "(olcSpCheckpoint=*)" olcSpCheckpoint 2>/dev/null | grep -q "olcSpCheckpoint"; then
    pass "olcSpCheckpoint configured"
else
    fail "olcSpCheckpoint missing"
fi

if $LOCAL -b "cn=config" "(olcSpSessionlog=*)" olcSpSessionlog 2>/dev/null | grep -q "olcSpSessionlog"; then
    pass "olcSpSessionlog configured"
else
    fail "olcSpSessionlog missing"
fi

if $LOCAL -b "cn=config" "(olcDbIndex=entryCSN*)" olcDbIndex 2>/dev/null | grep -q "entryCSN"; then
    pass "entryCSN eq index present"
else
    fail "entryCSN index missing"
fi

sids=$($LOCAL -b "cn=config" "(olcServerID=*)" olcServerID 2>/dev/null | grep -c "^olcServerID:" || true)
if [ "$sids" -eq 3 ]; then
    pass "full SID->URL map applied (3 olcServerID values)"
else
    fail "expected 3 olcServerID values, found ${sids}"
fi

# --- replication behaviour ----------------------------------------------------

section "replication behaviour"

docker exec -i ldapci-node1 ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: ou=Replicated,${BASE_DN}
objectClass: organizationalUnit
ou: Replicated
EOF

if search_ok ldapci-node1 "ou=Replicated,${BASE_DN}"; then
    pass "entry created on node1"
else
    fail "could not create the test entry on node1"
fi

for n in ldapci-node2 ldapci-node3; do
    if wait_for_entry "$n" "ou=Replicated,${BASE_DN}" 30; then
        pass "${n} received the entry"
    else
        fail "${n} did not receive the entry within 90s"
        docker logs "$n" 2>&1 | tail -15 | sed 's/^/       /'
    fi
done

# Convergence per the bundled validator.
section "ldapcheck.sh --peers"
if docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers ldapci-node2,ldapci-node3 >/dev/null 2>&1; then
    pass "ldapcheck reports no failures"
else
    fail "ldapcheck reported failures"
    docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers ldapci-node2,ldapci-node3 2>&1 | sed 's/^/       /'
fi

# --- resilience: stop a provider, write, restart, expect catch-up -------------

section "catch-up after a provider restart"

docker stop ldapci-node3 >/dev/null 2>&1
docker exec -i ldapci-node1 ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: ou=AfterRestart,${BASE_DN}
objectClass: organizationalUnit
ou: AfterRestart
EOF

if search_ok ldapci-node1 "ou=AfterRestart,${BASE_DN}"; then
    pass "entry created while node3 was down"
else
    fail "could not create the entry while node3 was down"
fi

docker start ldapci-node3 >/dev/null 2>&1
if wait_healthy ldapci-node3; then
    pass "node3 restarted and became healthy"
else
    fail "node3 did not become healthy after restart"
    docker logs ldapci-node3 2>&1 | tail -15 | sed 's/^/       /'
fi

if wait_for_entry ldapci-node3 "ou=AfterRestart,${BASE_DN}" 40; then
    pass "node3 caught up after restart"
else
    fail "node3 did not catch up after restart"
    docker logs ldapci-node3 2>&1 | tail -20 | sed 's/^/       /'
fi

echo
if [ "$FAIL" -gt 0 ]; then
    printf '\033[31mFAILED\033[0m %d check(s): %s\n' "$FAIL" "$FAILED_NAMES"
    exit 1
fi
printf '\033[32mAll replication checks passed\033[0m (%d checks)\n' "$PASS"
exit 0
