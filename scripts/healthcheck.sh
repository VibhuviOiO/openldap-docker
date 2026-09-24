#!/bin/bash
set -eo pipefail

# Health check for OpenLDAP.
#
# Usage: healthcheck.sh [auto|basic|tls|replication]
#
#   auto        (default) basic checks, plus TLS/replication when enabled
#   basic       slapd reachable, cn=config readable, expected suffix present
#   tls         LDAPS/StartTLS reachable (needs TLS configured)
#   replication syncprov loaded, peers configured, contextCSN converged
#
# All checks run over ldapi:/// with EXTERNAL (peercred) authentication, which
# the ACLs in set-database-acl.ldif and configure-monitor.ldif permit for the
# container's root identity. No password is needed and the checks keep working
# when anonymous binds are disabled.
#
# The previous implementation checked only the rootDSE and cn=config over an
# anonymous ldap:// bind. It never touched the suffix, so a container whose data
# database was empty or unmounted reported healthy; its replication mode was
# also unreachable, because LDAP_BASE_DN is derived at runtime and is not a
# container environment variable.

RUNTIME_ENV="${RUNTIME_ENV:-/var/run/openldap/ldap-runtime.env}"
READY_FILE="${READY_FILE:-/var/run/openldap/initialized}"
LDAP_HOST="${LDAP_HOST:-localhost}"
CHECK_TYPE="${1:-auto}"

# Load values derived by startup.sh (suffix, ports, enabled features). These are
# not container environment variables, so they must be read from the runtime file.
if [ -f "$RUNTIME_ENV" ]; then
    # shellcheck disable=SC1090
    . "$RUNTIME_ENV"
fi

LDAP_PORT="${LDAP_PORT:-389}"
LDAPS_PORT="${LDAPS_PORT:-636}"

base_dn="${LDAP_BASE_DN:-}"

# --- basic --------------------------------------------------------------------

check_basic() {
    # 0. Initialisation must have completed. This is what stops the healthcheck
    #    from reporting healthy while startup is still running - or after it has
    #    failed and the container is on its way down.
    if [ ! -f "$READY_FILE" ]; then
        echo "FAILED: initialisation has not completed (${READY_FILE} is absent)"
        return 1
    fi

    # 1. slapd must answer on the local socket.
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        echo "FAILED: cannot reach slapd over ldapi:///"
        return 1
    fi

    # 2. cn=config must be readable, i.e. the configuration database loaded.
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(objectClass=*)" >/dev/null 2>&1; then
        echo "FAILED: cannot read cn=config"
        return 1
    fi

    # 3. The expected suffix must actually be served. namingContexts is in the
    #    rootDSE, which ACL rule {1} makes readable by everyone, so this needs no
    #    credentials and is independent of anonymous-bind policy.
    #
    #    Limitation: an intact config volume with a wiped data volume still
    #    advertises its naming context, so this cannot distinguish "empty
    #    database" from "fresh install". Use ldapcheck.sh (which counts entries)
    #    for that.
    if [ -z "$base_dn" ]; then
        echo "FAILED: LDAP_BASE_DN unknown (is $RUNTIME_ENV present?)"
        return 1
    fi
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "" -s base namingContexts 2>/dev/null \
            | grep -qF "namingContexts: ${base_dn}"; then
        echo "FAILED: expected suffix ${base_dn} is not a configured naming context"
        return 1
    fi

    # 4. Finally, confirm the TCP listener answers (this is what clients use).
    if ! ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        # Anonymous binds may legitimately be disabled; fall back to the socket.
        if [ "${LDAP_DISABLE_ANONYMOUS_BIND:-false}" != "true" ]; then
            echo "FAILED: ldap://${LDAP_HOST}:${LDAP_PORT} is not answering"
            return 1
        fi
    fi

    echo "OK"
    return 0
}

# --- tls ----------------------------------------------------------------------

# True when something answered at the LDAP protocol layer over TLS.
#
# Certificate verification is disabled on purpose: the certificate is normally
# self-signed, and "not in the local trust store" must not make a healthy
# container report unhealthy forever.
#
# What this asks is "is the TLS listener serving?", NOT "did an anonymous bind
# succeed". The two are not the same: with bind_anon disabled the server
# answers an anonymous search with result 48, which still proves the handshake
# completed. Requiring an anonymous bind here made every TLS install with
# features.disableAnonymousBind=true fail its startup probe forever.
#
# ldapsearch exits 0 when the search succeeded, and with the LDAP result code
# when the server replied but refused. It exits 255 (LDAP_SERVER_DOWN) or 1
# when it cannot reach the listener at all. So these codes mean "the server
# answered us over TLS"; anything else means it did not.
tls_answered() {
    local url="$1"; shift
    local rc=0
    LDAPTLS_REQCERT=never ldapsearch -x -H "$url" "$@" \
        -b "" -s base "(objectClass=*)" >/dev/null 2>&1 || rc=$?

    case "$rc" in
        0)                return 0 ;;   # search succeeded
        8|32|48|49|50|53) return 0 ;;   # server replied: strongAuth/absent/anon-denied/bad-creds/no-access/unwilling
        *)                return 1 ;;   # no listener, or the handshake failed
    esac
}

check_tls() {
    if [ "${LDAP_TLS_ENABLED:-false}" != "true" ]; then
        echo "SKIPPED: TLS not configured"
        return 0
    fi

    if ! tls_answered "ldaps://${LDAP_HOST}:${LDAPS_PORT}"; then
        echo "FAILED: LDAPS on port ${LDAPS_PORT} is not answering"
        return 1
    fi

    if ! tls_answered "ldap://${LDAP_HOST}:${LDAP_PORT}" -ZZ; then
        echo "FAILED: StartTLS on port ${LDAP_PORT} failed"
        return 1
    fi

    echo "OK: LDAPS and StartTLS are serving"
    return 0
}

# --- replication --------------------------------------------------------------

check_replication() {
    if [ "${ENABLE_REPLICATION:-false}" != "true" ]; then
        echo "SKIPPED: replication not enabled"
        return 0
    fi

    # syncprov must be loaded, otherwise nothing is a provider.
    # Assert on the returned DN, not on the olcOverlay value: slapd stores that
    # value with its ordering prefix, i.e. "olcOverlay: {0}syncprov". Grepping
    # for "olcOverlay: syncprov" never matched, so this reported a healthy
    # provider as unconfigured.
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=syncprov)" dn 2>/dev/null \
            | grep -q "^dn:"; then
        echo "FAILED: syncprov overlay is not configured"
        return 1
    fi

    if [ -z "$base_dn" ]; then
        echo "FAILED: LDAP_BASE_DN unknown (is $RUNTIME_ENV present?)"
        return 1
    fi

    # Peers must actually be configured.
    local peers
    # Count returned DNs rather than matching the attribute name. slapd reports
    # this attribute as "olcSyncrepl" (lowercase r) with an ordering prefix on
    # the value, i.e. "olcSyncrepl: {0}rid=101 ...". Matching the value string
    # case-sensitively never worked. Filter attribute names are case-insensitive,
    # so the filter itself is fine.
    peers=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcSyncrepl=*)" dn 2>/dev/null \
        | grep -c "^dn:" || true)
    if [ "$peers" -eq 0 ]; then
        echo "FAILED: ENABLE_REPLICATION=true but no olcSyncRepl statements are configured"
        return 1
    fi

    # contextCSN is the replication state indicator.
    local csn
    csn=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "$base_dn" -s base contextCSN 2>/dev/null \
        | grep -c "^contextCSN:" || true)
    if [ "$csn" -gt 0 ]; then
        echo "OK (${csn} contextCSN value(s), ${peers} peer(s))"
        return 0
    fi

    # No contextCSN yet. That is legitimate on a freshly initialised node: the
    # base domain is written before the syncprov overlay is loaded, so nothing
    # has produced a CSN yet. It is NOT legitimate on a node that has been
    # running well past startup - that is the "never converged, serves stale
    # data, reports healthy" case.
    #
    # So apply a grace window measured from the readiness marker rather than
    # failing immediately, which previously made every fresh replication node
    # report unhealthy forever.
    local grace="${REPLICATION_CSN_GRACE:-300}"
    local age=0
    if [ -f "$READY_FILE" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$READY_FILE" 2>/dev/null || echo 0) ))
    fi
    if [ "$age" -lt "$grace" ]; then
        echo "OK (no contextCSN yet; ${age}s of uptime, within the ${grace}s grace window)"
        return 0
    fi

    echo "FAILED: no contextCSN after ${age}s of uptime - this node has not converged"
    return 1
}

# --- main ---------------------------------------------------------------------

case "$CHECK_TYPE" in
    auto)
        check_basic || exit 1
        check_tls || exit 1
        check_replication || exit 1
        ;;
    basic)
        check_basic || exit 1
        ;;
    tls)
        check_tls || exit 1
        ;;
    replication)
        check_replication || exit 1
        ;;
    *)
        echo "Unknown check type: $CHECK_TYPE (expected auto|basic|tls|replication)"
        exit 1
        ;;
esac

exit 0
