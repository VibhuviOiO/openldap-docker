#!/bin/bash
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
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
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
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Database configured"
}

# Set database access controls
set_database_acl() {
    log_step "Setting database access controls..."
    
    local ldif_file=$(process_ldif_template "set-database-acl" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}")
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
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
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}")
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Monitor access configured"
}

# Set log level
set_log_level() {
    local level=${1:-stats stats2}
    
    log_step "Setting log level to: $level"
    
    local ldif_file=$(process_ldif_template "set-log-level" \
        "LOG_LEVEL=${level}")
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
}

# Enable database monitoring
enable_db_monitoring() {
    log_step "Enabling database monitoring..."
    
    local ldif_file=$(get_ldif_path "enable-db-monitoring")
    cp "$LDIF_TEMPLATE_DIR/enable-db-monitoring.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
}

# Configure memberOf overlay
configure_memberof() {
    local enabled=$1
    
    if [ "$enabled" != "true" ]; then
        return 0
    fi
    
    log_header "Configuring memberOf overlay..."
    
    # Check if memberOf overlay already exists
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=memberof)" 2>/dev/null | grep -q "dn: olcOverlay=memberof"; then
        log_info "memberOf overlay already configured"
        return 0
    fi
    
    # Add refint overlay first (required for memberOf)
    log_step "Adding refint overlay..."
    local refint_ldif=$(get_ldif_path "add-refint-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-refint-overlay.ldif" "$refint_ldif"
    
    cat "$refint_ldif" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
    
    # Add memberOf overlay
    log_step "Adding memberOf overlay..."
    local memberof_ldif=$(get_ldif_path "add-memberof-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-memberof-overlay.ldif" "$memberof_ldif"
    
    cat "$memberof_ldif" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
    
    log_success "memberOf overlay configured"
}

# Configure database indices for performance
configure_indices() {
    log_step "Configuring database indices..."
    
    local ldif_file=$(get_ldif_path "add-indices")
    cp "$LDIF_TEMPLATE_DIR/add-indices.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Database indices configured"
}

# Set query limits (DoS protection)
set_query_limits() {
    log_step "Setting query limits..."
    
    local ldif_file=$(process_ldif_template "set-limits" \
        "LDAP_ADMIN_DN=${LDAP_ADMIN_DN}")
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Query limits configured"
}

# Set connection timeouts
set_timeouts() {
    log_step "Setting connection timeouts..."
    
    local ldif_file=$(get_ldif_path "set-timeouts")
    cp "$LDIF_TEMPLATE_DIR/set-timeouts.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Connection timeouts configured"
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
        cat "$module_ldif" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    fi
    
    # Add auditlog overlay
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={2}mdb,cn=config" 2>/dev/null | grep -q "olcOverlay=auditlog"; then
        log_step "Adding auditlog overlay..."
        local overlay_ldif=$(get_ldif_path "configure-auditlog")
        cp "$LDIF_TEMPLATE_DIR/configure-auditlog.ldif" "$overlay_ldif"
        cat "$overlay_ldif" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
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
        cat "$module_ldif" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    fi
    
    # Add ppolicy overlay
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={2}mdb,cn=config" 2>/dev/null | grep -q "olcOverlay=ppolicy"; then
        log_step "Adding ppolicy overlay..."
        local overlay_ldif=$(process_ldif_template "configure-ppolicy" \
            "LDAP_BASE_DN=${LDAP_BASE_DN}")
        cat "$overlay_ldif" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
    fi
    
    # Create default policy
    if ! ldapsearch -x -H ldap://localhost:389 -b "cn=default,ou=Policies,${LDAP_BASE_DN}" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" 2>/dev/null | grep -q "dn:"; then
        log_step "Creating default password policy..."
        local policy_ldif=$(process_ldif_template "create-default-policy" \
            "LDAP_BASE_DN=${LDAP_BASE_DN}")
        cat "$policy_ldif" | ldap_retry 5 2 ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" 2>&1 | grep -v "adding new entry" || true
    fi
    
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
    
    # Set proper permissions
    chown ldap:ldap "$cert_file" "$key_file"
    chmod 644 "$cert_file"
    chmod 600 "$key_file"
    
    # Prepare CA entry if provided
    local ca_entry=""
    if [ -n "$ca_file" ] && [ -f "$ca_file" ]; then
        chown ldap:ldap "$ca_file"
        chmod 644 "$ca_file"
        ca_entry="-\nadd: olcTLSCACertificateFile\nolcTLSCACertificateFile: ${ca_file}"
    fi
    
    local ldif_file=$(process_ldif_template "configure-tls" \
        "LDAP_TLS_CERT=${cert_file}" \
        "LDAP_TLS_KEY=${key_file}" \
        "TLS_CA_ENTRY=${ca_entry}")
    
    # Handle the CA entry as a special case - it may contain newlines
    if [ -n "$ca_file" ]; then
        # Add CA entry to the LDIF file
        echo -e "-\nadd: olcTLSCACertificateFile\nolcTLSCACertificateFile: ${ca_file}" >> "$ldif_file"
    fi
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
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
    
    cat "$ldif_file" | ldap_retry 5 2 ldapadd -x -D "$LDAP_ADMIN_DN" -w "$admin_password" 2>&1 | grep -v "adding new entry" || true
    
    log_success "Base domain created"
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
    
    if ldapsearch -x -H ldap://localhost:389 -b "$base_dn" -D "$admin_dn" -w "$admin_password" -s base "(objectClass=*)" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}
