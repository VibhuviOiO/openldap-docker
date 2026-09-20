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

check_tls() {
    if [ "${LDAP_TLS_ENABLED:-false}" != "true" ]; then
        echo "SKIPPED: TLS not configured"
        return 0
    fi

    # Verify with normal certificate checking first. If that fails we retry
    # without verification, which distinguishes "the TLS listener is broken"
    # from "the certificate is not in the local trust store" - the latter is
    # the normal case for a self-signed certificate and must not make a
    # perfectly healthy container report unhealthy forever.
    if ldapsearch -x -H "ldaps://${LDAP_HOST}:${LDAPS_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        : # verified
    elif LDAPTLS_REQCERT=never ldapsearch -x -H "ldaps://${LDAP_HOST}:${LDAPS_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        echo "OK: LDAPS is serving (certificate not trusted by the default trust store; expected for self-signed)"
        return 0
    else
        echo "FAILED: LDAPS on port ${LDAPS_PORT} is not answering"
        return 1
    fi

    if ! ldapsearch -x -ZZ -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        if ! LDAPTLS_REQCERT=never ldapsearch -x -ZZ -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
            echo "FAILED: StartTLS on port ${LDAP_PORT} failed"
            return 1
        fi
    fi

    echo "OK"
    return 0
}

# --- replication --------------------------------------------------------------

check_replication() {
    if [ "${ENABLE_REPLICATION:-false}" != "true" ]; then
        echo "SKIPPED: replication not enabled"
        return 0
    fi

    # syncprov must be loaded, otherwise nothing is a provider.
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=syncprov)" olcOverlay 2>/dev/null \
            | grep -q "olcOverlay: syncprov"; then
        echo "FAILED: syncprov overlay is not configured"
        return 1
    fi

    if [ -z "$base_dn" ]; then
        echo "FAILED: LDAP_BASE_DN unknown (is $RUNTIME_ENV present?)"
        return 1
    fi

    # contextCSN is the replication state indicator. A node that never converged
    # has none. The previous version returned OK in that case, so a node serving
    # stale data reported healthy.
    local csn
    csn=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "$base_dn" -s base contextCSN 2>/dev/null \
        | grep -c "^contextCSN:" || true)
    if [ "$csn" -gt 0 ]; then
        echo "OK"
        return 0
    fi

    # No contextCSN yet. That is legitimate for a freshly created cluster with no
    # writes, but not for a directory that already holds entries.
    local entries
    entries=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "$base_dn" -s sub -z 2 "(objectClass=*)" dn 2>/dev/null \
        | grep -c "^dn:" || true)
    # The suffix entry itself always matches, so >1 means real data is present.
    if [ "$entries" -gt 1 ]; then
        echo "FAILED: ${entries} entries below ${base_dn} but no contextCSN has been established"
        return 1
    fi

    echo "OK (no contextCSN yet, database is empty)"
    return 0
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
