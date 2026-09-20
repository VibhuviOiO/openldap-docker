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

# A single ldapsearch launched via docker exec can fail transiently under host
# load. A transient miss is not evidence of a server defect, so every
# configuration assertion is retried before it is reported.
eventually() {
    local tries=${1:-5}
    shift
    local _i
    for _i in $(seq 1 "$tries"); do
        if "$@"; then return 0; fi
        sleep 1
    done
    return 1
}

# Predicates (passed to eventually by name; shellcheck cannot follow them).
# shellcheck disable=SC2329
cfg_has() {  # <filter> <needle>
    # Anchor the match to the start of a line: an unanchored grep also matches
    # ldapsearch's own "# requesting: <attr>" header, so the assertion passed
    # even when the attribute was absent, and could only fail when ldapsearch
    # produced no output at all (a transient exec failure).
    docker exec ldapci-node1 ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "$1" 2>/dev/null \
        | grep -qiE "^${2}"
}
# shellcheck disable=SC2329
node_has() {  # <container> <basedn>
    docker exec "$1" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "$2" -s base "(objectClass=*)" dn 2>/dev/null | grep -q "^dn:"
}
# shellcheck disable=SC2329
add_ou() {  # <container> <dn> <ou>
    docker exec -i "$1" ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" 2>/dev/null <<EOF
dn: $2
objectClass: organizationalUnit
ou: $3
EOF
}

# Return a node's contextCSN set, one per line, sorted.
# shellcheck disable=SC2329
csn_set() {  # <container>
    docker exec "$1" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "$BASE_DN" -s base contextCSN 2>/dev/null \
        | grep "^contextCSN:" | sed 's/^contextCSN: //' | sort
}

# Wait until all three nodes report the SAME contextCSN set.
#
# In a multi-provider mesh every node mints its own SID during local
# initialisation, so convergence is bidirectional and takes time. Asserting
# immediately after the first write raced on a fast runner: node2 and node3 had
# all three SIDs while node1 still had only its own, and ldapcheck correctly
# reported no convergence.
wait_converged() {
    local tries=${1:-30}
    local _i node1
    for _i in $(seq 1 "$tries"); do
        node1=$(csn_set ldapci-node1)
        if [ -n "$node1" ] \
           && [ "$node1" = "$(csn_set ldapci-node2)" ] \
           && [ "$node1" = "$(csn_set ldapci-node3)" ]; then
            return 0
        fi
        sleep 5
    done
    return 1
}

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

if eventually 10 cfg_has "(olcModuleLoad=*)" "olcModuleLoad:.*syncprov"; then
    pass "syncprov.la is loaded (module-vs-entry guard works with memberof enabled)"
else
    fail "syncprov.la is NOT loaded"
fi

repl=$($LOCAL -b "cn=config" "(olcSyncrepl=*)" olcSyncrepl 2>/dev/null \
    | awk '/^[[:space:]]/{printf "%s", substr($0,2); next} {if(NR>1)printf "\n"; printf "%s",$0} END{printf "\n"}' \
    | grep -i "^olcSyncrepl:")
repl_count=$(printf '%s\n' "$repl" | grep -ci "^olcSyncrepl:" || true)

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

if eventually 10 cfg_has "(olcMultiProvider=*)" "olcMultiProvider: TRUE"; then
    pass "olcMultiProvider: TRUE"
else
    fail "olcMultiProvider is not TRUE"
fi

if eventually 10 cfg_has "(olcSpCheckpoint=*)" "olcSpCheckpoint"; then
    pass "olcSpCheckpoint configured"
else
    fail "olcSpCheckpoint missing"
fi

if eventually 10 cfg_has "(olcSpSessionlog=*)" "olcSpSessionlog"; then
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

if eventually 5 node_has ldapci-node1 "ou=Replicated,${BASE_DN}"; then
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
if wait_converged 30; then
    pass "all three nodes report the same contextCSN set"
else
    fail "nodes had not converged after 150s"
    for n in ldapci-node1 ldapci-node2 ldapci-node3; do
        printf '       %s: %s CSN(s)\n' "$n" "$(csn_set "$n" | grep -c . || true)"
    done
fi
if docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers ldapci-node2,ldapci-node3 >/dev/null 2>&1; then
    pass "ldapcheck reports no failures"
else
    fail "ldapcheck reported failures"
    docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers ldapci-node2,ldapci-node3 2>&1 | sed 's/^/       /'
fi

# Regression: a bare `--peers` used to be parsed as `PEERS="$2"; shift 2`. With
# --peers as the last argument `shift 2` failed under `set -e`, so the script
# exited 1 having printed nothing - the worst possible failure mode for a
# diagnostic tool.
if docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers >/dev/null 2>&1; then
    pass "bare --peers derives the peer list from REPLICATION_PEERS"
else
    fail "bare --peers did not work"
    docker exec ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers 2>&1 | sed 's/^/       /'
fi

# Regression: these containers are started with -e LDAP_ADMIN_PASSWORD, so the
# peer checks passed in CI while being unusable in any secrets-file deployment
# (Docker secrets, Kubernetes Secrets). PID 1 loads LDAP_ADMIN_PASSWORD_FILE
# into its own environment and never exports it to a later `docker exec`, so
# ldapcheck has to read the file itself. The file deliberately ends in a newline
# because that is what `--from-file` and `echo pw > f` produce.
docker exec ldapci-node1 sh -c "printf '%s\n' '${ADMIN_PW}' > /tmp/admin-pw && chmod 600 /tmp/admin-pw"
if docker exec \
        -e LDAP_ADMIN_PASSWORD= \
        -e LDAP_ADMIN_PASSWORD_FILE=/tmp/admin-pw \
        ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers >/dev/null 2>&1; then
    pass "peer checks work from LDAP_ADMIN_PASSWORD_FILE alone"
else
    fail "peer checks need LDAP_ADMIN_PASSWORD in the environment"
    docker exec -e LDAP_ADMIN_PASSWORD= -e LDAP_ADMIN_PASSWORD_FILE=/tmp/admin-pw \
        ldapci-node1 /usr/local/bin/scripts/ldapcheck.sh --peers 2>&1 | sed 's/^/       /'
fi
docker exec ldapci-node1 rm -f /tmp/admin-pw >/dev/null 2>&1 || true

# --- resilience: stop a provider, write, restart, expect catch-up -------------

section "catch-up after a provider restart"

docker stop ldapci-node3 >/dev/null 2>&1
docker exec -i ldapci-node1 ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: ou=AfterRestart,${BASE_DN}
objectClass: organizationalUnit
ou: AfterRestart
EOF

if eventually 5 node_has ldapci-node1 "ou=AfterRestart,${BASE_DN}"; then
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
