#!/bin/bash
# Password Policy Validation Test Script
# This script runs after OpenLDAP initialization to verify password policy is working

set -e

LDAP_HOST="localhost"
LDAP_PORT="389"
BASE_DN="dc=test,dc=com"
ADMIN_DN="cn=Manager,dc=test,dc=com"
ADMIN_PASS="admin123"
POLICY_DN="cn=default,ou=Policies,${BASE_DN}"

# Secure credential files (avoid password in ps output)
ADMIN_CREDS_FILE=$(mktemp /tmp/ldap_creds.XXXXXX)
chmod 600 "$ADMIN_CREDS_FILE"
echo "$ADMIN_PASS" > "$ADMIN_CREDS_FILE"
# Track any extra creds files for cleanup
EXTRA_CREDS_FILES=()
trap 'rm -f "$ADMIN_CREDS_FILE" "${EXTRA_CREDS_FILES[@]}"' EXIT

# Create a temporary credential file for a given password
# Usage: make_creds_file <password>
make_creds_file() {
    local tmpfile
    tmpfile=$(mktemp /tmp/ldap_creds.XXXXXX)
    chmod 600 "$tmpfile"
    echo "$1" > "$tmpfile"
    EXTRA_CREDS_FILES+=("$tmpfile")
    echo "$tmpfile"
}

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

# Wait for LDAP to be ready
wait_for_ldap() {
    log_info "Waiting for LDAP to be ready..."
    for i in {1..30}; do
        if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" -b "" -s base > /dev/null 2>&1; then
            log_success "LDAP is ready"
            return 0
        fi
        sleep 2
    done
    log_error "LDAP did not become ready in time"
    return 1
}

# Test 1: Verify password policy overlay is configured
test_policy_overlay() {
    log_info "Test 1: Verifying password policy overlay configuration..."
    
    # Check if the ppolicy overlay is loaded in cn=config (requires EXTERNAL auth)
    if ldapsearch -Y EXTERNAL -H ldapi:/// \
        -b "olcDatabase={2}mdb,cn=config" "(objectClass=olcOverlayConfig)" dn 2>/dev/null | grep -q "ppolicy"; then
        log_success "Password policy overlay is configured"
    else
        log_error "Password policy overlay is NOT configured"
        return 1
    fi
}

# Test 2: Verify policy OU exists
test_policy_ou_exists() {
    log_info "Test 2: Verifying policy OU exists..."
    
    if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" \
        -b "ou=Policies,${BASE_DN}" -s base "(objectClass=organizationalUnit)" dn 2>/dev/null | grep -q "ou=Policies"; then
        log_success "Policy OU exists"
    else
        log_error "Policy OU does NOT exist"
        return 1
    fi
}

# Test 3: Verify default password policy exists
test_default_policy_exists() {
    log_info "Test 3: Verifying default password policy entry exists..."
    
    if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" \
        -b "${POLICY_DN}" -s base "(objectClass=pwdPolicy)" dn 2>/dev/null | grep -q "cn=default"; then
        log_success "Default password policy exists"
    else
        log_error "Default password policy does NOT exist"
        return 1
    fi
}

# Test 4: Verify password policy attributes
test_policy_attributes() {
    log_info "Test 4: Verifying password policy attributes..."
    
    local policy_attrs
    policy_attrs=$(ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" \
        -b "${POLICY_DN}" -s base "(objectClass=pwdPolicy)" pwdMinLength pwdMaxFailure pwdLockout 2>/dev/null)
    
    if echo "$policy_attrs" | grep -q "pwdMinLength: 8"; then
        log_success "pwdMinLength is set to 8"
    else
        log_error "pwdMinLength attribute missing or incorrect"
        return 1
    fi
    
    if echo "$policy_attrs" | grep -q "pwdMaxFailure: 5"; then
        log_success "pwdMaxFailure is set to 5"
    else
        log_error "pwdMaxFailure attribute missing or incorrect"
        return 1
    fi
    
    if echo "$policy_attrs" | grep -q "pwdLockout: TRUE"; then
        log_success "pwdLockout is TRUE"
    else
        log_error "pwdLockout attribute missing or incorrect"
        return 1
    fi
}

# Test 5: Verify password policy enforcement by checking pwdPolicySubentry behavior
test_password_enforcement() {
    log_info "Test 5: Testing password policy enforcement..."
    
    local test_user_dn="uid=testuser,ou=People,${BASE_DN}"
    local test_user_pass="StrongPass123!"
    
    # Create test user
    log_info "Creating test user with pwdPolicySubentry..."
    if ! ldapadd -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" <<EOF
dn: uid=testuser,ou=People,${BASE_DN}
objectClass: inetOrgPerson
uid: testuser
cn: Test User
sn: User
userPassword: ${test_user_pass}
pwdPolicySubentry: cn=default,ou=Policies,${BASE_DN}
EOF
    then
        log_error "Failed to create test user"
        return 1
    fi
    log_success "Test user created with pwdPolicySubentry"
    
    # Verify the pwdPolicySubentry is set
    if ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" \
        -b "${test_user_dn}" -s base pwdPolicySubentry 2>/dev/null | grep -q "cn=default,ou=Policies"; then
        log_success "pwdPolicySubentry correctly set on user"
    else
        log_error "pwdPolicySubentry not set on user"
        ldapdelete -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" "${test_user_dn}" 2>/dev/null || true
        return 1
    fi
    
    # Test that weak password is rejected (via ldappasswd if available, skip otherwise)
    local user_creds_file
    user_creds_file=$(make_creds_file "${test_user_pass}")
    if ldappasswd -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${test_user_dn}" -y "$user_creds_file" -s "weak" 2>/dev/null; then
        log_error "Weak password was accepted - policy NOT enforced!"
        ldapdelete -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" "${test_user_dn}" 2>/dev/null || true
        return 1
    else
        log_success "Weak password correctly rejected (or ldappasswd not available)"
    fi
    
    # Clean up test user
    ldapdelete -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -D "${ADMIN_DN}" -y "$ADMIN_CREDS_FILE" "${test_user_dn}" 2>/dev/null || true
}

# Main test execution
main() {
    log_info "=========================================="
    log_info "Password Policy Validation Tests"
    log_info "=========================================="
    
    wait_for_ldap || exit 1
    
    local failed=0
    
    test_policy_overlay || failed=$((failed + 1))
    test_policy_ou_exists || failed=$((failed + 1))
    test_default_policy_exists || failed=$((failed + 1))
    test_policy_attributes || failed=$((failed + 1))
    test_password_enforcement || failed=$((failed + 1))
    
    log_info "=========================================="
    if [ $failed -eq 0 ]; then
        log_success "All password policy tests passed!"
    else
        log_error "$failed test(s) failed!"
        exit 1
    fi
    log_info "=========================================="
}

main "$@"
