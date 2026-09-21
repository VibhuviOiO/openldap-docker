#!/bin/bash
set -eo pipefail
#
# ldapcheck - validate OpenLDAP replication configuration and convergence.
#
# Usage:
#   ldapcheck.sh                 # local configuration checks only
#   ldapcheck.sh --peers node2,node3
#                                # also compare contextCSN against each peer
#   ldapcheck.sh --peers         # derive the peer list from REPLICATION_PEERS
#   ldapcheck.sh --peers n2,n3 --deep
#                                # also compare entry counts (reads every entry)
#
# Exits non-zero if any check FAILS. Intended for CI and for incident triage.
#
# Why this exists: every defect it detects is a *silent* one. A finite syncrepl
# retry list, a missing keepalive, a duplicate serverID, a missing entryCSN
# index or a node that never converged all present as "replication is fine"
# until someone notices that data is stale.

RUNTIME_ENV="${RUNTIME_ENV:-/var/run/openldap/ldap-runtime.env}"
LDAP_HOST="${LDAP_HOST:-localhost}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAPI="ldapi:///"

PEERS=""
PEERS_FROM_RUNTIME=false
DEEP=false

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FAILED_CHECKS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --peers)
            # A bare --peers means "use the peers this node already replicates
            # from", which is the only sane thing to ask for inside the
            # container. The old form was `PEERS="$2"; shift 2`, and with
            # --peers as the last argument `shift 2` failed under `set -e`,
            # exiting 1 with no output at all.
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                PEERS="$2"
                shift 2
            else
                PEERS_FROM_RUNTIME=true
                shift
            fi
            ;;
        --peers=*) PEERS="${1#*=}"; shift ;;
        --deep) DEEP=true; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -f "$RUNTIME_ENV" ]; then
    # shellcheck disable=SC1090
    . "$RUNTIME_ENV"
fi

# Resolve a bare --peers now that the runtime env has been read. Empty is not an
# error: a node without peers (a standalone provider, or one that has not been
# configured yet) is a legitimate thing to run this against, and a diagnostic
# tool that refuses to report anything at all is worse than one that says why it
# skipped a section.
PEERS_FROM_RUNTIME_EMPTY=false
if [ "$PEERS_FROM_RUNTIME" = true ]; then
    PEERS="${REPLICATION_PEERS:-}"
    if [ -z "$PEERS" ]; then
        PEERS_FROM_RUNTIME_EMPTY=true
    fi
fi

# Honour a password file exactly as startup.sh does.
#
# A `docker exec` or `kubectl exec` process does not inherit the container's
# loaded secrets: PID 1 reads LDAP_ADMIN_PASSWORD_FILE into LDAP_ADMIN_PASSWORD
# and never exports it back to the container environment. Without this the peer
# checks are unusable in every secrets-file deployment, which is the recommended
# way to run this image under Docker secrets or Kubernetes.
if [ -z "${LDAP_ADMIN_PASSWORD:-}" ] && [ -n "${LDAP_ADMIN_PASSWORD_FILE:-}" ]; then
    if [ -r "$LDAP_ADMIN_PASSWORD_FILE" ]; then
        # tr, matching startup.sh: strip CR/LF rather than trusting the file to
        # end without a newline. `kubectl create secret --from-file` and
        # `echo pw > f` both leave one behind.
        LDAP_ADMIN_PASSWORD=$(tr -d '\n\r' < "$LDAP_ADMIN_PASSWORD_FILE")
        export LDAP_ADMIN_PASSWORD
    else
        echo "warning: LDAP_ADMIN_PASSWORD_FILE=${LDAP_ADMIN_PASSWORD_FILE} is not readable" >&2
    fi
fi

BASE_DN="${LDAP_BASE_DN:-}"
ADMIN_DN="${LDAP_ADMIN_DN:-}"
SERVER_ID="${SERVER_ID:-1}"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  [PASS] %s\n' "$1"; }
fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_CHECKS="${FAILED_CHECKS}${1}; "
    printf '  [FAIL] %s\n' "$1"
    [ -n "${2:-}" ] && printf '         %s\n' "$2"
}
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf '  [WARN] %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }
skip() { printf '  [SKIP] %s\n' "$1"; }

# Join RFC 2849 folded continuation lines (leading space) into single lines.
unfold() {
    awk '
        /^[[:space:]]/ { printf "%s", substr($0, 2); next }
        { if (NR > 1) printf "\n"; printf "%s", $0 }
        END { printf "\n" }
    '
}

# Credentials never go on the command line.
CREDS_FILE=""
make_creds() {
    CREDS_FILE=$(mktemp /tmp/ldapcheck.XXXXXX)
    chmod 600 "$CREDS_FILE"
    printf '%s' "${LDAP_ADMIN_PASSWORD:-}" > "$CREDS_FILE"
}
trap '[ -n "$CREDS_FILE" ] && rm -f "$CREDS_FILE" || true' EXIT

local_search() { ldapsearch -Y EXTERNAL -H "$LDAPI" "$@"; }

# A node with replication disabled has no olcSyncRepl or olcMultiProvider, so
# every replication check below would fail. Report basic health and stop.
if [ "${ENABLE_REPLICATION:-false}" != "true" ]; then
    echo "OpenLDAP validation (replication disabled)"
    echo "========================================="
    if local_search -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        pass "slapd reachable over ${LDAPI}"
    else
        fail "cannot reach slapd over ${LDAPI}"
    fi
    if [ -n "$BASE_DN" ] && local_search -b "" -s base namingContexts 2>/dev/null | grep -qF "namingContexts: ${BASE_DN}"; then
        pass "suffix ${BASE_DN} is served"
    else
        fail "suffix ${BASE_DN:-<unknown>} is not served"
    fi
    echo
    echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    echo "Replication checks skipped: ENABLE_REPLICATION is not true."
    if [ "$FAIL_COUNT" -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

echo "OpenLDAP replication validation"
echo "==============================="
echo "Base DN:   ${BASE_DN:-<unknown>}"
echo "Server ID: ${SERVER_ID}"
echo "Peers:     ${PEERS:-<none specified>}"
echo

# --- local configuration ------------------------------------------------------

echo "LOCAL CONFIGURATION"
echo "-------------------"

if ! local_search -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
    echo "  [FAIL] cannot reach slapd over ${LDAPI}"
    exit 1
fi

# syncprov module
if local_search -b "cn=config" "(olcModuleLoad=syncprov*)" olcModuleLoad 2>/dev/null | grep -q "syncprov"; then
    pass "syncprov module loaded"
else
    fail "syncprov module is NOT loaded" "replication cannot work without it; see load_syncprov_module()"
fi

# exactly one syncprov overlay
# Count matching DNs. slapd stores the olcOverlay value with its ordering
# prefix ("olcOverlay: {0}syncprov"), so matching the value string never worked.
syncprov_overlays=$(local_search -b "cn=config" "(olcOverlay=syncprov)" dn 2>/dev/null | grep -c "^dn:" || true)
if [ "$syncprov_overlays" -eq 1 ]; then
    pass "exactly one syncprov overlay (${syncprov_overlays})"
elif [ "$syncprov_overlays" -eq 0 ]; then
    fail "no syncprov overlay configured"
else
    fail "${syncprov_overlays} syncprov overlays configured" "expected exactly one"
fi

# multi-provider
mp=$(local_search -b "cn=config" "(olcMultiProvider=*)" olcMultiProvider 2>/dev/null | grep -c "^olcMultiProvider: TRUE" || true)
if [ "$mp" -ge 1 ]; then
    pass "olcMultiProvider: TRUE"
else
    fail "olcMultiProvider is not TRUE" "multi-master/multi-provider is not actually enabled (2.6 name; olcMirrorMode is the deprecated 2.4 name)"
fi

# olcReadOnly
if local_search -b "cn=config" "(olcReadOnly=*)" olcReadOnly 2>/dev/null | grep -q "^olcReadOnly: TRUE"; then
    fail "olcReadOnly is TRUE on at least one database" "a read-only node accepts no writes"
else
    pass "olcReadOnly unset"
fi

# olcSyncRepl statements
REPLS=$(local_search -b "cn=config" "(olcSyncrepl=*)" olcSyncRepl 2>/dev/null | unfold | grep -i "^olcSyncrepl:" || true)
repl_total=$(printf '%s\n' "$REPLS" | grep -ci "^olcSyncrepl:" || true)

if [ "$repl_total" -eq 0 ]; then
    warn "no olcSyncRepl statements found" "this node is a provider only"
else
    retry_ok=0
    retry_bad=0
    ka_ok=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if printf '%s' "$line" | grep -qE 'retry="[^"]*\+"'; then
            retry_ok=$((retry_ok + 1))
        else
            retry_bad=$((retry_bad + 1))
            warn "olcSyncRepl retry list does not end with '+'" "$(printf '%s' "$line" | grep -oE 'retry="[^"]*"')"
        fi
        if printf '%s' "$line" | grep -q "keepalive="; then
            ka_ok=$((ka_ok + 1))
        else
            warn "olcSyncRepl is missing keepalive=" "an idle refreshAndPersist link can be blackholed by a middlebox with no RST"
        fi
    done <<< "$REPLS"

    if [ "$retry_bad" -eq 0 ]; then
        pass "retry ends with '+': ${retry_ok}/${repl_total} olcSyncRepl"
    else
        fail "retry ends with '+': ${retry_ok}/${repl_total}" "a finite retry list stops replicating permanently once exhausted"
    fi
    if [ "$ka_ok" -eq "$repl_total" ]; then
        pass "keepalive present: ${ka_ok}/${repl_total} olcSyncRepl"
    else
        fail "keepalive present: ${ka_ok}/${repl_total}"
    fi
fi

# indexes
if local_search -b "cn=config" "(olcDbIndex=entryCSN*)" olcDbIndex 2>/dev/null | grep -q "entryCSN"; then
    pass "entryCSN eq index"
else
    fail "entryCSN eq index missing" "syncrepl searches on entryCSN; without it the provider scans"
fi
if local_search -b "cn=config" "(olcDbIndex=entryUUID*)" olcDbIndex 2>/dev/null | grep -q "entryUUID"; then
    pass "entryUUID eq index"
else
    warn "entryUUID eq index missing" "recommended when using the syncprov session log"
fi

# checkpoint
if local_search -b "cn=config" "(olcSpCheckpoint=*)" olcSpCheckpoint 2>/dev/null | grep -q "olcSpCheckpoint"; then
    pass "olcSpCheckpoint configured"
else
    warn "olcSpCheckpoint is not configured" "after an unclean shutdown startup must scan the whole database to find contextCSN"
fi

# sessionlog
if local_search -b "cn=config" "(olcSpSessionlog=*)" olcSpSessionlog 2>/dev/null | grep -q "olcSpSessionlog"; then
    pass "olcSpSessionlog configured"
else
    warn "olcSpSessionlog is not configured" "a stale consumer will do a full refresh instead of a delta"
fi

# serverID set and includes this node
SERVER_IDS=$(local_search -b "cn=config" "(olcServerID=*)" olcServerID 2>/dev/null | unfold | grep "^olcServerID:" || true)
if printf '%s\n' "$SERVER_IDS" | grep -qE "^olcServerID: ${SERVER_ID}( |$)"; then
    pass "olcServerID includes this node's SID (${SERVER_ID})"
else
    fail "olcServerID does not include this node's SERVER_ID (${SERVER_ID})"
fi
sid_count=$(printf '%s\n' "$SERVER_IDS" | grep -c "^olcServerID:" || true)
if [ "$sid_count" -le 1 ]; then
    warn "only ${sid_count} olcServerID value(s)" "an N-way mesh should list the full SID->URL map on every node (REPLICATION_SERVER_IDS)"
fi

echo

# --- peer convergence ---------------------------------------------------------

if [ -z "$PEERS" ]; then
    echo "PEER CONVERGENCE"
    echo "----------------"
    if [ "$PEERS_FROM_RUNTIME_EMPTY" = true ]; then
        skip "--peers given but REPLICATION_PEERS is empty; local checks only"
    else
        skip "no --peers given; local checks only"
    fi
else
    echo "PEER CONVERGENCE"
    echo "----------------"
    if [ -z "$BASE_DN" ] || [ -z "${LDAP_ADMIN_PASSWORD:-}" ]; then
        fail "cannot check peers" "LDAP_BASE_DN or LDAP_ADMIN_PASSWORD unavailable"
    else
        make_creds
        local_csn=$(local_search -b "$BASE_DN" -s base contextCSN 2>/dev/null | grep "^contextCSN:" | sed 's/^contextCSN: //' | sort || true)
        local_n=$(printf '%s\n' "$local_csn" | grep -c . || true)

        printf '  %-22s %-10s %-12s %s\n' "PEER" "REACHABLE" "CSN COUNT" "CONVERGED"
        for peer in ${PEERS//,/ }; do
            peer=$(printf '%s' "$peer" | tr -d '[:space:]')
            [ -z "$peer" ] && continue

            if ! ldapsearch -x -H "ldap://${peer}:${LDAP_PORT}" -D "$ADMIN_DN" -y "$CREDS_FILE" \
                    -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
                printf '  %-22s %-10s %-12s %s\n' "$peer" "NO" "-" "-"
                fail "peer ${peer} is not reachable" "check DNS/hostname, network and that the peer is running"
                continue
            fi

            peer_csn=$(ldapsearch -x -H "ldap://${peer}:${LDAP_PORT}" -D "$ADMIN_DN" -y "$CREDS_FILE" \
                -b "$BASE_DN" -s base contextCSN 2>/dev/null | grep "^contextCSN:" | sed 's/^contextCSN: //' | sort || true)
            peer_n=$(printf '%s\n' "$peer_csn" | grep -c . || true)

            converged="no"
            if [ "$local_n" -gt 0 ] && [ "$peer_csn" = "$local_csn" ]; then
                converged="yes"
            fi
            printf '  %-22s %-10s %-12s %s\n' "$peer" "yes" "$peer_n" "$converged"

            if [ "$converged" = "yes" ]; then
                pass "peer ${peer} contextCSN matches (${peer_n} sid(s))"
            else
                fail "peer ${peer} has NOT converged" "local ${local_n} CSN(s) vs peer ${peer_n}; compare contextCSN per sid"
            fi

            if [ "$DEEP" = "true" ]; then
                local_e=$(ldapsearch -Y EXTERNAL -H "$LDAPI" -b "$BASE_DN" -s sub "(objectClass=*)" dn 2>/dev/null | grep -c "^dn:" || true)
                peer_e=$(ldapsearch -x -H "ldap://${peer}:${LDAP_PORT}" -D "$ADMIN_DN" -y "$CREDS_FILE" \
                    -b "$BASE_DN" -s sub "(objectClass=*)" dn 2>/dev/null | grep -c "^dn:" || true)
                if [ "$local_e" = "$peer_e" ]; then
                    pass "peer ${peer} entry count matches (${peer_e})"
                else
                    fail "peer ${peer} entry count differs" "local ${local_e} vs peer ${peer_e}"
                fi
            fi
        done
    fi
fi

echo
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Failed: ${FAILED_CHECKS}"
    exit 1
fi

exit 0
