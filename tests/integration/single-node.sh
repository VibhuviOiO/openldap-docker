#!/bin/bash
# Single-node integration scenarios for the OpenLDAP image.
#
# Runs against an already-built image. Generates TLS certificates at test time -
# no key material is committed to the repository.
#
# Usage:
#   docker build -t openldap:local .
#   tests/integration/single-node.sh openldap:local
#
# Exits non-zero if any scenario fails.

set -uo pipefail

IMAGE="${1:-openldap:local}"
DOMAIN="example.com"
BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=Manager,${BASE_DN}"
ADMIN_PW="AdminPass123!"
PREFIX="ldapci"
WORKDIR="$(mktemp -d)"

PASS=0
FAIL=0
FAILED_NAMES=""

# Referenced only from the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
    for c in $(docker ps -aq --filter "name=${PREFIX}" 2>/dev/null); do
        docker rm -f "$c" >/dev/null 2>&1 || true
    done
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILED_NAMES="${FAILED_NAMES}${1}; "
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [ -n "${2:-}" ] && printf '       %s\n' "$2"
}
section() { printf '\n\033[36m== %s\033[0m\n' "$1"; }
info() { printf '       %s\n' "$1"; }

# A single ldapsearch launched via `docker exec` can fail transiently while the
# host is busy (the exec itself can fail, or the connection can be refused
# during a restart). A transient miss is not evidence of a server defect, so
# every assertion that depends on one is retried before being reported.
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

# Predicate: an admin-authenticated search returns at least one entry.
# Passed to eventually() by name, which shellcheck cannot follow.
# shellcheck disable=SC2329
has_entry() {
    local c=$1 base=$2 scope=${3:-base}
    docker exec "$c" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "$base" -s "$scope" "(objectClass=*)" dn 2>/dev/null | grep -q "^dn:"
}

# Predicate: the user carries the expected memberOf value.
# shellcheck disable=SC2329
user_has_memberof() {
    local c=$1
    docker exec "$c" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" \
        -b "uid=alice,ou=People,${BASE_DN}" -s base memberOf 2>/dev/null \
        | grep -q "memberOf: cn=admins,ou=Group,${BASE_DN}"
}

# Predicate: cn=config contains a matching attribute value.
# shellcheck disable=SC2329
cn_config_has() {
    local c=$1 filter=$2 needle=$3
    docker exec "$c" ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "$filter" 2>/dev/null \
        | grep -q "$needle"
}

# Wait until the container reports healthy, or fail after ~120s.
wait_healthy() {
    local name=$1
    for _ in $(seq 1 40); do
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

dump_logs() { docker logs "$1" 2>&1 | tail -25 | sed 's/^/       /'; }

# --- scenario: defaults + ACL enforcement -------------------------------------

scenario_defaults_acl() {
    section "defaults + ACL enforcement"
    local c="${PREFIX}-default"

    docker run -d --name "$c" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        "$IMAGE" >/dev/null || { fail "container failed to start"; return; }

    if wait_healthy "$c"; then
        pass "container becomes healthy with default settings"
    else
        fail "container never became healthy"
        dump_logs "$c"
        return
    fi

    # Runtime env file must exist - this is what makes docker exec'd helpers able
    # to see the derived suffix.
    if docker exec "$c" test -s /var/run/openldap/ldap-runtime.env; then
        pass "runtime env file written"
    else
        fail "runtime env file missing or empty"
    fi

    # Authenticated read must work. This runs BEFORE the anonymous check so the
    # anonymous check cannot pass merely because nothing is there.
    if eventually 5 has_entry "$c" "$BASE_DN"; then
        pass "authenticated base search works"
    else
        fail "authenticated base search failed"
    fi

    # Anonymous read of the suffix must be denied. Assert on an explicit access
    # error rather than on absence of output, which is also true when the entry
    # simply does not exist.
    anon=$(docker exec "$c" ldapsearch -x -H ldap://localhost -b "$BASE_DN" -s base "(objectClass=*)" dn 2>&1 || true)
    if printf '%s' "$anon" | grep -q "^dn:"; then
        fail "anonymous read of ${BASE_DN} returned entries (ACL too permissive)"
    elif printf '%s' "$anon" | grep -qiE "insufficient|denied|no such object"; then
        pass "anonymous read of the suffix is denied"
    else
        fail "anonymous read result was ambiguous" "$(printf '%s' "$anon" | head -3 | tr '\n' ' ')"
    fi

    # Base OUs, including ou=Services.
    for ou in People Group Services; do
        if eventually 5 has_entry "$c" "ou=${ou},${BASE_DN}"; then
            pass "ou=${ou} exists"
        else
            fail "ou=${ou} is missing"
        fi
    done

    # Non-root users are truncated at the size limit; the config must say so.
    if eventually 5 cn_config_has "$c" "(olcLimits=*)" "olcLimits:"; then
        pass "query limits are configured"
    else
        fail "query limits not found in cn=config"
    fi

    # ldapcheck must pass on a non-replicated node.
    if docker exec "$c" /usr/local/bin/scripts/ldapcheck.sh >/dev/null 2>&1; then
        pass "ldapcheck passes on a non-replicated node"
    else
        fail "ldapcheck failed on a non-replicated node"
        docker exec "$c" /usr/local/bin/scripts/ldapcheck.sh 2>&1 | sed 's/^/       /'
    fi
}

# --- scenario: overlays -------------------------------------------------------

scenario_overlays() {
    section "overlays (memberof, ppolicy, auditlog)"
    local c="${PREFIX}-overlays"
    mkdir -p "$WORKDIR/logs"

    docker run -d --name "$c" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        -e "INCLUDE_SCHEMAS=cosine,inetorgperson,nis" \
        -e "ENABLE_MEMBEROF=true" \
        -e "ENABLE_PASSWORD_POLICY=true" \
        -e "ENABLE_AUDIT_LOG=true" \
        -v "$WORKDIR/logs:/logs" \
        "$IMAGE" >/dev/null || { fail "container failed to start"; return; }

    if wait_healthy "$c"; then
        pass "container with all overlays becomes healthy"
    else
        fail "overlay container never became healthy"
        dump_logs "$c"; return
    fi

    # --- memberOf ---
    docker exec -i "$c" ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: uid=alice,ou=People,${BASE_DN}
objectClass: inetOrgPerson
uid: alice
cn: Alice
sn: Example
userPassword: GoodPass123!
EOF
    docker exec -i "$c" ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: cn=admins,ou=Group,${BASE_DN}
objectClass: groupOfNames
cn: admins
member: uid=alice,ou=People,${BASE_DN}
EOF

    if eventually 5 user_has_memberof "$c"; then
        pass "memberOf overlay maintains memberOf on the user"
    else
        fail "memberOf attribute was not added to the user"
    fi

    # --- ppolicy: enforced for non-root identities ---
    # The rootDN bypasses password policy, so the check must bind as the user.
    if docker exec "$c" ldappasswd -x -H ldap://localhost \
            -D "uid=alice,ou=People,${BASE_DN}" -w "GoodPass123!" -s "abc" >/dev/null 2>&1; then
        fail "weak password was ACCEPTED (password policy not enforced)"
    else
        pass "weak password rejected by password policy"
    fi

    # --- auditlog ---
    if docker exec "$c" test -s /logs/audit.log; then
        pass "audit.log is populated"
    else
        fail "audit.log is empty"
    fi
}

# --- scenario: TLS ------------------------------------------------------------

scenario_tls() {
    section "TLS (self-signed, generated at test time)"
    local c="${PREFIX}-tls"
    local certs="$WORKDIR/certs"
    mkdir -p "$certs"

    if ! command -v openssl >/dev/null 2>&1; then
        info "openssl not available, skipping TLS scenario"
        return
    fi

    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$certs/ldap.key" -out "$certs/ldap.crt" -days 2 \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1 \
        || { fail "could not generate test certificate"; return; }
    cp "$certs/ldap.crt" "$certs/ca.crt"
    chmod 644 "$certs/ldap.key"

    docker run -d --name "$c" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        -e "LDAP_TLS_CERT=/certs/ldap.crt" \
        -e "LDAP_TLS_KEY=/certs/ldap.key" \
        -e "LDAP_TLS_CA=/certs/ca.crt" \
        -e "LDAP_TLS_VERIFY_CLIENT=never" \
        -v "$certs:/certs:ro" \
        "$IMAGE" >/dev/null || { fail "TLS container failed to start"; return; }

    if wait_healthy "$c"; then
        pass "TLS container becomes healthy"
    else
        fail "TLS container never became healthy"
        dump_logs "$c"; return
    fi

    # The certificate AND the CA must both be configured. Before the LDIF fix,
    # setting LDAP_TLS_CA produced a malformed record and TLS was silently never
    # applied while still logging success.
    if eventually 5 cn_config_has "$c" "olcTLSCertificateFile" "olcTLSCertificateFile:"; then
        pass "olcTLSCertificateFile applied"
    else
        fail "olcTLSCertificateFile was NOT applied (the TLS LDIF failure mode)"
    fi
    if eventually 5 cn_config_has "$c" "olcTLSCACertificateFile" "olcTLSCACertificateFile:"; then
        pass "olcTLSCACertificateFile applied (CA path works)"
    else
        fail "olcTLSCACertificateFile was NOT applied"
    fi
    if eventually 5 cn_config_has "$c" "olcTLSProtocolMin" "olcTLSProtocolMin: 3.3"; then
        pass "olcTLSProtocolMin is 3.3 (TLS 1.2 floor)"
    else
        fail "olcTLSProtocolMin is not set to 3.3"
    fi

    # Both TLS transports must actually answer.
    if eventually 5 docker exec "$c" env LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://localhost:636 -b "" -s base "(objectClass=*)"; then
        pass "LDAPS on 636 answers"
    else
        fail "LDAPS on 636 did not answer"
    fi
    if eventually 5 docker exec "$c" env LDAPTLS_REQCERT=never ldapsearch -x -ZZ -H ldap://localhost:389 -b "" -s base "(objectClass=*)"; then
        pass "StartTLS on 389 works"
    else
        fail "StartTLS on 389 failed"
    fi
}

# --- scenario: docker secrets -------------------------------------------------

scenario_secrets() {
    section "docker secrets (_FILE convention)"
    local c="${PREFIX}-secrets"
    mkdir -p "$WORKDIR/secrets"
    printf '%s' "SecretAdminPass123!" > "$WORKDIR/secrets/admin"

    docker run -d --name "$c" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD_FILE=/run/secrets/admin" \
        -v "$WORKDIR/secrets/admin:/run/secrets/admin:ro" \
        "$IMAGE" >/dev/null || { fail "secrets container failed to start"; return; }

    if wait_healthy "$c"; then
        pass "container starts from an admin password file"
    else
        fail "secrets container never became healthy"
        dump_logs "$c"; return
    fi

    if docker exec "$c" ldapsearch -x -H ldap://localhost -D "$ADMIN_DN" -w "SecretAdminPass123!" \
            -b "$BASE_DN" -s base dn >/dev/null 2>&1; then
        pass "password from the secret file is the active admin password"
    else
        fail "could not bind with the password from the secret file"
    fi
}

# --- scenario: idempotency ----------------------------------------------------

scenario_idempotency() {
    section "idempotency + persistence across restart"
    local c="${PREFIX}-idem"

    docker run -d --name "$c" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        "$IMAGE" >/dev/null || { fail "container failed to start"; return; }

    if ! wait_healthy "$c"; then
        fail "container never became healthy"
        dump_logs "$c"; return
    fi

    docker exec -i "$c" ldapadd -x -H ldap://localhost -D "$ADMIN_DN" -w "$ADMIN_PW" >/dev/null 2>&1 <<EOF
dn: ou=Persisted,${BASE_DN}
objectClass: organizationalUnit
ou: Persisted
EOF

    docker restart "$c" >/dev/null 2>&1
    if wait_healthy "$c"; then
        pass "restart reaches healthy"
    else
        fail "container unhealthy after restart"
        dump_logs "$c"; return
    fi

    if eventually 10 has_entry "$c" "ou=Persisted,${BASE_DN}"; then
        pass "entry survives a restart"
    else
        fail "entry did not survive the restart"
    fi

    # A second initialisation must not report errors. Failures are fatal now, so
    # a clean restart is meaningful evidence that reconfiguration is idempotent.
    if docker logs "$c" 2>&1 | grep -qE "\[ERROR\]|LDAP operation failed"; then
        fail "restart logs contain errors"
        docker logs "$c" 2>&1 | grep -E "\[ERROR\]|LDAP operation failed" | tail -10 | sed 's/^/       /'
    else
        pass "restart logs are free of errors"
    fi

    # And no generated LDIF with password hashes may be left behind.
    if docker exec "$c" sh -c 'ls /tmp/ldap-init/ldif/*.ldif 2>/dev/null' | grep -q .; then
        fail "generated LDIF files were left behind after startup"
    else
        pass "generated LDIF files cleaned up"
    fi
}

# --- scenario: fail-fast guardrails ------------------------------------------

scenario_guardrails() {
    section "fail-fast guardrails"

    # assert_exits_nonzero <name> <expected substring> <docker run args...>
    assert_exits_nonzero() {
        local name=$1
        local expect=$2
        shift 2
        local c="${PREFIX}-${name}"
        docker rm -f "$c" >/dev/null 2>&1 || true
        docker run -d --name "$c" "$@" "$IMAGE" >/dev/null 2>&1
        for _ in $(seq 1 20); do
            if ! docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
                break
            fi
            sleep 2
        done
        local code
        code=$(docker inspect -f '{{.State.ExitCode}}' "$c" 2>/dev/null || echo "unknown")
        local logs
        logs=$(docker logs "$c" 2>&1 || true)
        if [ "$code" != "0" ] && [ "$code" != "unknown" ] && printf '%s' "$logs" | grep -qi "$expect"; then
            pass "$name: refused to start with a clear error"
        else
            fail "$name: did NOT fail fast" "exit=${code}; look for '${expect}'"
            printf '%s' "$logs" | tail -8 | sed 's/^/       /'
        fi
        docker rm -f "$c" >/dev/null 2>&1 || true
    }

    assert_exits_nonzero "repl-no-server-id" "SERVER_ID" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        -e "ENABLE_REPLICATION=true" \
        -e "REPLICATION_PEERS=other-node"

    assert_exits_nonzero "missing-secret-file" "does not exist" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD_FILE=/run/secrets/nope"

    assert_exits_nonzero "self-in-peers" "replicate from itself" \
        -e "LDAP_DOMAIN=${DOMAIN}" \
        -e "LDAP_ADMIN_PASSWORD=${ADMIN_PW}" \
        -e "ENABLE_REPLICATION=true" \
        -e "SERVER_ID=1" \
        -e "REPLICATION_PEERS=localhost"
}

# --- run ----------------------------------------------------------------------

echo "OpenLDAP single-node integration tests"
echo "image: ${IMAGE}"

scenario_defaults_acl
scenario_overlays
scenario_tls
scenario_secrets
scenario_idempotency
scenario_guardrails

echo
if [ "$FAIL" -gt 0 ]; then
    printf '\033[31mFAILED\033[0m %d scenario(s): %s\n' "$FAIL" "$FAILED_NAMES"
    exit 1
fi
printf '\033[32mAll single-node scenarios passed\033[0m (%d checks)\n' "$PASS"
exit 0
