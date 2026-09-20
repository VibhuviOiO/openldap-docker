#!/bin/bash
set -eo pipefail

# OpenLDAP configuration functions

source /usr/local/bin/scripts/utils.sh
source /usr/local/bin/scripts/ldif-processor.sh

# Set derived values from LDAP_DOMAIN
setup_derived_values() {
    IFS='.' read -ra DC_PARTS <<< "$LDAP_DOMAIN"
    LDAP_BASE_DN=$(printf "dc=%s," "${DC_PARTS[@]}" | sed 's/,$//')
    LDAP_ADMIN_DN="cn=Manager,${LDAP_BASE_DN}"
    
    export LDAP_BASE_DN LDAP_ADMIN_DN DC_PARTS
}

# Validate configuration using slaptest
validate_config() {
    log_step "Validating OpenLDAP configuration..."
    
    if slaptest -u -F /etc/openldap/slapd.d >/dev/null 2>&1; then
        log_success "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed"
        return 1
    fi
}

# Set config database password
set_config_password() {
    local config_hash=$1
    
    log_step "Setting config password..."
    
    local ldif_file=$(process_ldif_template "set-config-password" \
        "CONFIG_HASH=${config_hash}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Config password set"
}

# Configure main database
configure_database() {
    local admin_hash=$1
    
    log_step "Configuring database..."
    
    local ldif_file=$(process_ldif_template "configure-database" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}" \
        "ADMIN_HASH=${admin_hash}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Database configured"
}

# Set database access controls
set_database_acl() {
    log_step "Setting database access controls..."
    
    local ldif_file=$(process_ldif_template "set-database-acl" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}" \
        "READ_SUBJECT=${LDAP_READ_ACCESS_SUBJECT:-users}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Database ACL configured"
}

# Configure monitor access
configure_monitor() {
    local enabled=$1
    
    if [ "$enabled" != "true" ]; then
        log_info "Monitoring disabled - cn=Monitor not accessible"
        return 0
    fi
    
    log_step "Enabling cn=Monitor access for Manager DN..."
    
    local ldif_file=$(process_ldif_template "configure-monitor" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Monitor access configured"
}

# Set log level
set_log_level() {
    local level=${1:-stats stats2}
    
    log_step "Setting log level to: $level"
    
    local ldif_file=$(process_ldif_template "set-log-level" \
        "LOG_LEVEL=${level}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
}

# Enable database monitoring
#
# Gated on ENABLE_MONITORING. Previously this ran unconditionally, so setting
# ENABLE_MONITORING=false still turned DB statistics collection on and only
# revoked the ACL that would have let anyone read the statistics.
enable_db_monitoring() {
    local enabled=${1:-true}

    if [ "$enabled" != "true" ]; then
        log_info "Database monitoring disabled"
        return 0
    fi

    log_step "Enabling database monitoring..."
    
    local ldif_file=$(get_ldif_path "enable-db-monitoring")
    cp "$LDIF_TEMPLATE_DIR/enable-db-monitoring.ldif" "$ldif_file"
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
}

# Configure memberOf overlay
configure_memberof() {
    local enabled=$1
    
    if [ "$enabled" != "true" ]; then
        return 0
    fi
    
    log_header "Configuring memberOf overlay..."
    
    # Check if memberOf overlay already exists
    # Filter on olcOverlay and assert on the returned DN. slapd stores the value
    # with an ordering prefix whose number depends on the order overlays were
    # added ("olcOverlay={1}memberof"), so matching a bare name or a hardcoded
    # "{0}" never works and the overlay was re-added on every restart.
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=memberof)" dn 2>/dev/null | grep -q "^dn:"; then
        log_info "memberOf overlay already configured"
        return 0
    fi
    
    # Load memberof and refint modules first
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" 2>/dev/null | grep -q "memberof.la"; then
        log_step "Loading memberof module..."
        if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base 2>/dev/null | grep -q "dn: cn=module{0},cn=config"; then
            # Entry exists, add memberof module
            local memberof_module_ldif=$(get_ldif_path "add-memberof-module")
            cp "$LDIF_TEMPLATE_DIR/add-memberof-module.ldif" "$memberof_module_ldif"
            apply_ldif_modify "$memberof_module_ldif" -Y EXTERNAL -H ldapi:///
        else
            # Create module entry
            local memberof_module_ldif=$(get_ldif_path "load-memberof-module")
            cp "$LDIF_TEMPLATE_DIR/load-memberof-module.ldif" "$memberof_module_ldif"
            apply_ldif_add "$memberof_module_ldif" -Y EXTERNAL -H ldapi:///
        fi
    fi
    
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" 2>/dev/null | grep -q "refint.la"; then
        log_step "Loading refint module..."
        local refint_module_ldif=$(get_ldif_path "add-refint-module")
        cp "$LDIF_TEMPLATE_DIR/add-refint-module.ldif" "$refint_module_ldif"
        apply_ldif_modify "$refint_module_ldif" -Y EXTERNAL -H ldapi:///
    fi
    
    # Add refint overlay first (required for memberOf)
    log_step "Adding refint overlay..."
    local refint_ldif=$(get_ldif_path "add-refint-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-refint-overlay.ldif" "$refint_ldif"
    
    apply_ldif_add "$refint_ldif" -Y EXTERNAL -H ldapi:///
    
    # Add memberOf overlay
    log_step "Adding memberOf overlay..."
    local memberof_ldif=$(get_ldif_path "add-memberof-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-memberof-overlay.ldif" "$memberof_ldif"
    
    apply_ldif_add "$memberof_ldif" -Y EXTERNAL -H ldapi:///
    
    log_success "memberOf overlay configured"
}

# Configure database indices for performance
configure_indices() {
    log_step "Configuring database indices..."
    
    local ldif_file=$(get_ldif_path "add-indices")
    cp "$LDIF_TEMPLATE_DIR/add-indices.ldif" "$ldif_file"
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Database indices configured"
}

# Set query limits (DoS protection)
#
# Any bind that is not the rootDN or a service account is silently truncated at
# QUERY_SIZE_HARD. Clients must use RFC 2696 paged results (LDAP Manager does).
set_query_limits() {
    log_step "Setting query limits..."
    
    local ldif_file=$(process_ldif_template "set-limits" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}" \
        "QUERY_SIZE_SOFT=${LDAP_QUERY_SIZE_SOFT:-500}" \
        "QUERY_SIZE_HARD=${LDAP_QUERY_SIZE_HARD:-1000}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Query limits configured"
}

# Set connection timeouts
set_timeouts() {
    log_step "Setting connection timeouts..."
    
    local ldif_file=$(get_ldif_path "set-timeouts")
    cp "$LDIF_TEMPLATE_DIR/set-timeouts.ldif" "$ldif_file"
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Connection timeouts configured"
}

# Set connection rate limits (DoS protection)
set_connection_limits() {
    local max_pending=${1:-100}
    local max_pending_auth=${2:-1000}
    
    log_step "Setting connection limits (max_pending=${max_pending}, max_pending_auth=${max_pending_auth})..."
    
    local ldif_file=$(process_ldif_template "set-connection-limits" \
        "CONN_MAX_PENDING=${max_pending}" \
        "CONN_MAX_PENDING_AUTH=${max_pending_auth}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Connection limits configured"
}

# Set the slapd worker thread count
set_threads() {
    local threads=${1:-16}
    
    log_step "Setting slapd threads to: ${threads}"
    
    local ldif_file=$(process_ldif_template "set-threads" \
        "THREADS=${threads}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "slapd thread count set to ${threads}"
}

# Set the password hashing scheme
set_password_hash() {
    local scheme="${1:-}"
    if [ -z "$scheme" ]; then
        scheme='{SSHA}'
    fi
    
    log_step "Setting password hash scheme to: ${scheme}"
    
    local ldif_file=$(process_ldif_template "set-password-hash" \
        "PASSWORD_HASH=${scheme}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Password hash scheme set to ${scheme}"
}

# Optionally disallow anonymous binds
configure_anonymous_bind() {
    local disable=$1
    
    if [ "$disable" != "true" ]; then
        return 0
    fi
    
    log_step "Disabling anonymous binds..."
    
    local ldif_file=$(get_ldif_path "disable-anonymous-bind")
    cp "$LDIF_TEMPLATE_DIR/disable-anonymous-bind.ldif" "$ldif_file"
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Anonymous binds disabled (rootDSE now requires a bind)"
}

# Configure audit logging (auditlog overlay)
configure_audit_log() {
    local enabled=$1
    
    if [ "$enabled" != "true" ]; then
        log_info "Audit logging disabled"
        return 0
    fi
    
    log_header "Configuring audit logging..."
    
    # Ensure audit log file exists and has correct permissions
    touch /logs/audit.log
    chown ldap:ldap /logs/audit.log
    chmod 640 /logs/audit.log
    
    # Load auditlog module if not already loaded
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" 2>/dev/null | grep -q "auditlog.la"; then
        log_step "Loading auditlog module..."
        local module_ldif=$(get_ldif_path "add-auditlog-overlay")
        cp "$LDIF_TEMPLATE_DIR/add-auditlog-overlay.ldif" "$module_ldif"
        apply_ldif_modify "$module_ldif" -Y EXTERNAL -H ldapi:///
    fi
    
    # Add auditlog overlay
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=auditlog)" dn 2>/dev/null | grep -q "^dn:"; then
        log_step "Adding auditlog overlay..."
        local overlay_ldif=$(get_ldif_path "configure-auditlog")
        cp "$LDIF_TEMPLATE_DIR/configure-auditlog.ldif" "$overlay_ldif"
        apply_ldif_add "$overlay_ldif" -Y EXTERNAL -H ldapi:///
    fi
    
    log_success "Audit logging configured - logs to /logs/audit.log"
}

# Configure password policy (ppolicy overlay)
configure_password_policy() {
    local enabled=$1
    
    if [ "$enabled" != "true" ]; then
        log_info "Password policy disabled"
        return 0
    fi
    
    log_header "Configuring password policy..."
    
    # Load ppolicy module if not already loaded
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" 2>/dev/null | grep -q "ppolicy.la"; then
        log_step "Loading ppolicy module..."
        local module_ldif=$(get_ldif_path "add-password-policy")
        cp "$LDIF_TEMPLATE_DIR/add-password-policy.ldif" "$module_ldif"
        
        # Check if module{0} entry exists (created by another module loader)
        if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base 2>/dev/null | grep -q "dn: cn=module{0},cn=config"; then
            # Entry exists: append ppolicy.la to it with a modify.
            # This used to be done by rewriting add-password-policy.ldif with
            # sed and piping it into ldapmodify, which cannot be retried (stdin
            # is consumed on the first attempt) and broke whenever the template
            # text changed. A dedicated template mirrors memberof/refint.
            local ppolicy_module_ldif=$(get_ldif_path "add-ppolicy-module")
            cp "$LDIF_TEMPLATE_DIR/add-ppolicy-module.ldif" "$ppolicy_module_ldif"
            apply_ldif_modify "$ppolicy_module_ldif" -Y EXTERNAL -H ldapi:///
        else
            # Entry doesn't exist, create it
            apply_ldif_add "$module_ldif" -Y EXTERNAL -H ldapi:///
        fi
    fi
    
    # Add ppolicy overlay
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=ppolicy)" dn 2>/dev/null | grep -q "^dn:"; then
        log_step "Adding ppolicy overlay..."
        local overlay_ldif=$(process_ldif_template "configure-ppolicy" \
            "LDAP_BASE_DN=${LDAP_BASE_DN}")
        apply_ldif_add "$overlay_ldif" -Y EXTERNAL -H ldapi:///
    fi
    
    # Create the ou=Policies container, then the default policy. They are
    # separate records on purpose: ldapadd stops at the first failing record, so
    # a directory that already had ou=Policies but not cn=default previously
    # failed the whole add and ended up with no password policy at all.
    local creds_file
    creds_file=$(create_creds_file "$LDAP_ADMIN_PASSWORD")

    if ! ldapsearch -x -H ldap://localhost:389 -b "ou=Policies,${LDAP_BASE_DN}" \
            -D "$LDAP_ADMIN_DN" -y "$creds_file" -s base "(objectClass=*)" dn 2>/dev/null \
            | grep -q "dn:"; then
        log_step "Creating ou=Policies container..."
        local policies_ldif
        policies_ldif=$(process_ldif_template "create-policies-ou" \
            "LDAP_BASE_DN=${LDAP_BASE_DN}")
        apply_ldif_add "$policies_ldif" -x -D "$LDAP_ADMIN_DN" -y "$creds_file"
    fi

    if ! ldapsearch -x -H ldap://localhost:389 -b "cn=default,ou=Policies,${LDAP_BASE_DN}" \
            -D "$LDAP_ADMIN_DN" -y "$creds_file" -s base "(objectClass=*)" dn 2>/dev/null \
            | grep -q "dn:"; then
        log_step "Creating default password policy..."
        local policy_ldif
        policy_ldif=$(process_ldif_template "create-default-policy" \
            "LDAP_BASE_DN=${LDAP_BASE_DN}")
        apply_ldif_add "$policy_ldif" -x -D "$LDAP_ADMIN_DN" -y "$creds_file"
    fi

    remove_creds_file "$creds_file"
    
    log_success "Password policy configured"
}

# Configure TLS/SSL
configure_tls() {
    local cert_file=${LDAP_TLS_CERT:-}
    local key_file=${LDAP_TLS_KEY:-}
    local ca_file=${LDAP_TLS_CA:-}
    
    # Skip if TLS not configured
    if [ -z "$cert_file" ] || [ -z "$key_file" ]; then
        log_info "TLS not configured (set LDAP_TLS_CERT and LDAP_TLS_KEY)"
        return 0
    fi
    
    # Validate files exist
    if [ ! -f "$cert_file" ]; then
        log_error "TLS certificate file not found: $cert_file"
        return 1
    fi
    
    if [ ! -f "$key_file" ]; then
        log_error "TLS key file not found: $key_file"
        return 1
    fi
    
    log_step "Configuring TLS..."
    
    # Set proper permissions (ignore errors for read-only mounts)
    chown ldap:ldap "$cert_file" "$key_file" 2>/dev/null || true
    chmod 644 "$cert_file" 2>/dev/null || true
    chmod 600 "$key_file" 2>/dev/null || true
    
    # Build the trailing multi-line block of the modify operation: optional CA
    # file, then the hardening attributes.
    #
    # printf (or $'\n' joining) is required: "-\nreplace: ..." written inside a
    # plain double-quoted string keeps the backslash-n literal, which produced a
    # malformed LDIF line and made the whole modify fail.
    #
    # This block must never render empty - a blank line inside an LDIF modify
    # terminates the record, and the remainder would be parsed as a second,
    # invalid record. Hence protocol-min and verify-client are always emitted.
    local tls_extra=""
    if [ -n "$ca_file" ]; then
        if [ ! -f "$ca_file" ]; then
            log_error "TLS CA file not found: $ca_file"
            return 1
        fi
        chown ldap:ldap "$ca_file" 2>/dev/null || true
        chmod 644 "$ca_file" 2>/dev/null || true
        tls_extra=$(printf -- '-\nreplace: olcTLSCACertificateFile\nolcTLSCACertificateFile: %s' "$ca_file")
    fi

    local hardening
    hardening=$(printf -- '-\nreplace: olcTLSProtocolMin\nolcTLSProtocolMin: %s\n-\nreplace: olcTLSVerifyClient\nolcTLSVerifyClient: %s' \
        "${LDAP_TLS_PROTOCOL_MIN:-3.3}" "${LDAP_TLS_VERIFY_CLIENT:-never}")

    if [ -n "$tls_extra" ]; then
        tls_extra="${tls_extra}"$'\n'"${hardening}"
    else
        tls_extra="${hardening}"
    fi

    # The cipher suite is emitted only when explicitly requested, so we never
    # pin a suite list that is wrong for the OpenSSL build in use.
    if [ -n "${LDAP_TLS_CIPHER_SUITE:-}" ]; then
        tls_extra="${tls_extra}"$'\n'"$(printf -- '-\nreplace: olcTLSCipherSuite\nolcTLSCipherSuite: %s' "$LDAP_TLS_CIPHER_SUITE")"
    fi
    
    local ldif_file=$(process_ldif_template "configure-tls" \
        "LDAP_TLS_CERT=${cert_file}" \
        "LDAP_TLS_KEY=${key_file}" \
        "TLS_EXTRA=${tls_extra}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "TLS configured"
}

# Create base domain entries
create_base_domain() {
    local admin_password=$1
    
    log_step "Creating base domain..."
    
    local ldif_file=$(process_ldif_template "create-base-domain" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}" \
        "LDAP_ORGANIZATION=${LDAP_ORGANIZATION}" \
        "DC_PARTS_0=${DC_PARTS[0]}" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}")
    
    local creds_file
    creds_file=$(create_creds_file "$admin_password")
    apply_ldif_add "$ldif_file" -x -D "$LDAP_ADMIN_DN" -y "$creds_file"
    remove_creds_file "$creds_file"
    
    log_success "Base domain created"
}

# Create one dedicated bind account if it does not already exist.
# Usage: ensure_service_account <cn> <description> <password>
ensure_service_account() {
    local account_cn=$1
    local description=$2
    local password=$3

    if [ -z "$password" ]; then
        return 0
    fi

    local account_dn="cn=${account_cn},${LDAP_BASE_DN}"
    local creds_file
    creds_file=$(create_creds_file "$LDAP_ADMIN_PASSWORD")

    if ldapsearch -x -H ldap://localhost:389 -b "$account_dn" \
            -D "$LDAP_ADMIN_DN" -y "$creds_file" -s base "(objectClass=*)" dn 2>/dev/null \
            | grep -q "dn:"; then
        log_info "Service account already exists: ${account_dn}"
        remove_creds_file "$creds_file"
        return 0
    fi

    local account_hash
    account_hash=$(slappasswd -s "$password")

    local ldif_file
    ldif_file=$(process_ldif_template "create-service-account" \
        "ACCOUNT_CN=${account_cn}" \
        "ACCOUNT_DESCRIPTION=${description}" \
        "ACCOUNT_HASH=${account_hash}" \
        "LDAP_BASE_DN=${LDAP_BASE_DN}")

    apply_ldif_add "$ldif_file" -x -D "$LDAP_ADMIN_DN" -y "$creds_file"
    remove_creds_file "$creds_file"

    log_success "Created service account: ${account_dn}"
}

# Create the dedicated replication and monitoring accounts.
#
# Rationale: binding replication (and monitoring) as the directory rootDN means
# the administrator credential is stored in cleartext in cn=config on every
# node and handed to any monitoring stack. These accounts are least-privilege
# and are exempted from olcLimits so replication cannot silently truncate.
#
# This runs on every start, not only on first initialisation, so that a volume
# created by an older image also gets the accounts.
configure_service_accounts() {
    if [ "$ENABLE_REPLICATION" = "true" ] && [ -z "${LDAP_REPLICATION_PASSWORD:-}" ]; then
        log_warn "LDAP_REPLICATION_PASSWORD is not set: replication will bind as the"
        log_warn "directory rootDN (${LDAP_ADMIN_DN}). Set LDAP_REPLICATION_PASSWORD to use"
        log_warn "the least-privilege cn=replicator account instead."
    fi

    ensure_service_account "replicator" \
        "Replication bind account used by syncrepl on every node" \
        "${LDAP_REPLICATION_PASSWORD:-}"

    ensure_service_account "monitor" \
        "Read-only monitoring and exporter bind account" \
        "${LDAP_MONITOR_PASSWORD:-}"
}

# Check if database is already configured
is_database_configured() {
    local base_dn=$1
    
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcDatabase={2}mdb)" 2>/dev/null | grep -q "olcSuffix: $base_dn"; then
        return 0
    fi
    return 1
}

# Check if base domain exists
is_base_domain_exists() {
    local base_dn=$1
    local admin_dn=$2
    local admin_password=$3
    
    local creds_file
    creds_file=$(create_creds_file "$admin_password")
    local rc=1
    if ldapsearch -x -H ldap://localhost:389 -b "$base_dn" -D "$admin_dn" -y "$creds_file" -s base "(objectClass=*)" >/dev/null 2>&1; then
        rc=0
    fi
    remove_creds_file "$creds_file"
    return $rc
}
