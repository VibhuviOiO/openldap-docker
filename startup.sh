#!/bin/bash
set -eo pipefail

# Fix permissions for mounted volumes (run as root initially)
fix_permissions() {
    # Only run if we're root
    if [ "$(id -u)" = "0" ]; then
        echo "[INFO] Fixing permissions for mounted volumes..."
        # Fix ownership of volumes that need to be writable by ldap user
        # Note: /tmp/ldap-init must stay owned by root for no-new-privileges support
        for dir in /logs /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap /tmp/ldap-init/ldif /usr/local/bin/ldif/generated; do
            if [ -d "$dir" ]; then
                chown -R ldap:ldap "$dir" 2>/dev/null || true
                chmod 755 "$dir" 2>/dev/null || true
            fi
        done
    fi
}

# Fix permissions first (must run before sourcing scripts that use /tmp/ldap-init)
fix_permissions

# Source helper scripts
SCRIPT_DIR="/usr/local/bin/scripts"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/schema.sh"
source "$SCRIPT_DIR/replication.sh"
source "$SCRIPT_DIR/ldif-processor.sh"

# Fix permissions again after sourcing (scripts may create directories)
fix_permissions

# Default values
: "${LDAP_LOG_LEVEL:=256}"
: "${LDAP_DOMAIN:=example.com}"
: "${LDAP_ORGANIZATION:=Example Organization}"
: "${LDAP_ADMIN_PASSWORD:=admin}"
: "${LDAP_ADMIN_PASSWORD_FILE:=}"
: "${LDAP_CONFIG_PASSWORD:=config}"
: "${LDAP_CONFIG_PASSWORD_FILE:=}"
: "${ENABLE_REPLICATION:=false}"
: "${ENABLE_MONITORING:=true}"
: "${ENABLE_MEMBEROF:=false}"
: "${ENABLE_PASSWORD_POLICY:=false}"
: "${ENABLE_AUDIT_LOG:=false}"
: "${SERVER_ID:=1}"
: "${INCLUDE_SCHEMAS:=}"
: "${LDAP_PORT:=389}"
: "${LDAPS_PORT:=636}"
: "${LDAP_CONN_MAX_PENDING:=100}"
: "${LDAP_CONN_MAX_PENDING_AUTH:=1000}"

# Load passwords from files if specified (more secure than env vars)
if [ -n "$LDAP_ADMIN_PASSWORD_FILE" ] && [ -f "$LDAP_ADMIN_PASSWORD_FILE" ]; then
    LDAP_ADMIN_PASSWORD=$(cat "$LDAP_ADMIN_PASSWORD_FILE" | tr -d '\n\r')
    log_info "Loaded admin password from file (length: ${#LDAP_ADMIN_PASSWORD})"
fi

if [ -n "$LDAP_CONFIG_PASSWORD_FILE" ] && [ -f "$LDAP_CONFIG_PASSWORD_FILE" ]; then
    LDAP_CONFIG_PASSWORD=$(cat "$LDAP_CONFIG_PASSWORD_FILE" | tr -d '\n\r')
    log_info "Loaded config password from file (length: ${#LDAP_CONFIG_PASSWORD})"
fi

# Export for use in sourced scripts
export LDAP_DOMAIN LDAP_ORGANIZATION LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD
export ENABLE_REPLICATION ENABLE_MONITORING ENABLE_MEMBEROF ENABLE_PASSWORD_POLICY ENABLE_AUDIT_LOG SERVER_ID
export LDAP_CONN_MAX_PENDING LDAP_CONN_MAX_PENDING_AUTH

# Global variable to track slapd PID
SLAPD_PID=""

# Cleanup function for proper signal handling
cleanup() {
    local signal=$1
    log_info "Received signal $signal, initiating shutdown..."
    
    if [ -n "$SLAPD_PID" ] && kill -0 "$SLAPD_PID" 2>/dev/null; then
        # Send SIGTERM to slapd
        kill -TERM "$SLAPD_PID" 2>/dev/null || true
        
        # Wait for slapd to stop (with timeout)
        local count=0
        while kill -0 "$SLAPD_PID" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        # Force kill if still running
        if kill -0 "$SLAPD_PID" 2>/dev/null; then
            log_warn "slapd did not stop gracefully, forcing..."
            kill -KILL "$SLAPD_PID" 2>/dev/null || true
        fi
        
        wait "$SLAPD_PID" 2>/dev/null || true
    fi
    
    log_info "Shutdown complete"
    exit 0
}

# Setup signal handlers
trap 'cleanup SIGTERM' SIGTERM
trap 'cleanup SIGINT' SIGINT

# Main startup
main() {
    log_header "Starting OpenLDAP initialization"
    
    # Validate required environment
    validate_required_env
    
    # Password strength warnings
    warn_weak_password "$LDAP_ADMIN_PASSWORD" "LDAP_ADMIN_PASSWORD"
    warn_weak_password "$LDAP_CONFIG_PASSWORD" "LDAP_CONFIG_PASSWORD"
    
    # Setup derived values
    setup_derived_values
    
    # Log configuration
    log_info "Domain: $LDAP_DOMAIN"
    log_info "Base DN: $LDAP_BASE_DN"
    log_info "Replication: $ENABLE_REPLICATION"
    log_info "Monitoring: $ENABLE_MONITORING"
    log_info "Server ID: $SERVER_ID"
    
    # Generate password hashes
    log_info "Generating password hashes..."
    local admin_hash=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
    local config_hash=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
    log_info "Admin hash prefix: ${admin_hash:0:20}..."
    
    # Prepare directories and log file
    mkdir -p /logs
    chown ldap:ldap /logs
    touch /logs/slapd.log
    chown ldap:ldap /logs/slapd.log
    
    # Start slapd in background for configuration
    log_info "Starting slapd for initial configuration..."
    # Check if slapd can start (capture errors)
    # Note: Don't use -u/-g here because no-new-privileges prevents setuid
    if ! /usr/sbin/slapd -h "ldap:/// ldaps:/// ldapi:///" -d 1 -Tt 2>&1; then
        log_warn "slaptest indicates potential issues, but continuing..."
    fi
    /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d 256 &
    SLAPD_PID=$!
    
    # Wait for slapd to be ready
    if ! wait_for_slapd 30 1; then
        log_error "slapd failed to start for configuration"
        exit 1
    fi
    
    # Validate configuration before proceeding
    if ! validate_config; then
        log_error "Configuration validation failed"
        kill $SLAPD_PID 2>/dev/null || true
        wait $SLAPD_PID 2>/dev/null || true
        exit 1
    fi
    
    # Configure database if not already configured
    if is_database_configured "$LDAP_BASE_DN"; then
        log_info "Database already configured"
    else
        log_header "Configuring OpenLDAP"
        
        set_config_password "$config_hash"
        configure_database "$admin_hash"
        set_database_acl
        configure_indices
        set_query_limits
        set_timeouts
        set_connection_limits "$LDAP_CONN_MAX_PENDING" "$LDAP_CONN_MAX_PENDING_AUTH"
        configure_monitor "$ENABLE_MONITORING"
        set_log_level "$LDAP_LOG_LEVEL"
        enable_db_monitoring
        configure_tls
        configure_memberof "$ENABLE_MEMBEROF"
        configure_audit_log "$ENABLE_AUDIT_LOG"
        
        log_success "Database configuration complete"
    fi
    
    # Create base domain if it doesn't exist
    if is_base_domain_exists "$LDAP_BASE_DN" "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD"; then
        log_info "Base domain already exists"
    else
        create_base_domain "$LDAP_ADMIN_PASSWORD"
    fi
    
    # Load built-in schemas
    if [ -n "$INCLUDE_SCHEMAS" ]; then
        load_builtin_schemas "$INCLUDE_SCHEMAS"
    fi
    
    # Load custom schemas
    load_custom_schemas
    
    # Configure password policy (must be after base domain is created)
    configure_password_policy "$ENABLE_PASSWORD_POLICY"
    
    # Configure replication if enabled
    if [ "$ENABLE_REPLICATION" = "true" ]; then
        configure_replication "$SERVER_ID" "$LDAP_BASE_DN" "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD" "$REPLICATION_PEERS" "$REPLICATION_RIDS"
    fi
    
    log_header "OpenLDAP initialization completed"
    log_info "LDAP listening on ldap://0.0.0.0:${LDAP_PORT} ldaps://0.0.0.0:${LDAPS_PORT}"
    log_info "Activity logs: /logs/slapd.log"
    
    # Clean up generated LDIF files containing password hashes
    log_step "Cleaning up generated LDIF files..."
    cleanup_generated_ldif
    log_success "Generated LDIF files cleaned up"
    
    # Check if init scripts need to run (BEFORE stopping slapd)
    local has_init_scripts=false
    if [ -d "/docker-entrypoint-initdb.d" ]; then
        for script in /docker-entrypoint-initdb.d/*.sh; do
            if [ -f "$script" ]; then
                has_init_scripts=true
                break
            fi
        done
    fi
    
    if [ "$has_init_scripts" = "true" ]; then
        # Init scripts present - keep slapd running and execute them
        log_info "Init scripts found, keeping slapd running..."
        
        # Run init scripts against the already running slapd
        log_header "Running initialization scripts..."
        for script in /docker-entrypoint-initdb.d/*.sh; do
            if [ -f "$script" ]; then
                log_step "Executing $(basename "$script")..."
                if bash "$script"; then
                    log_success "Script completed: $(basename "$script")"
                else
                    log_warn "Script failed but continuing: $(basename "$script")"
                fi
            fi
        done
        log_success "All initialization scripts completed"
        
        # Sync database to disk
        log_step "Syncing database to disk..."
        slapcat -b "${LDAP_BASE_DN}" >/dev/null 2>&1 || true
        sync
        
        # Keep slapd running with proper signal handling
        log_info "Keeping slapd running in foreground..."
        wait $SLAPD_PID
    else
        # No init scripts - stop slapd and restart cleanly
        log_step "Syncing database to disk..."
        slapcat -b "${LDAP_BASE_DN}" >/dev/null 2>&1 || true
        sync
        
        log_info "Stopping temporary slapd..."
        if kill -0 "$SLAPD_PID" 2>/dev/null; then
            kill -TERM "$SLAPD_PID" 2>/dev/null || true
            for i in {1..10}; do
                if ! kill -0 "$SLAPD_PID" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            if kill -0 "$SLAPD_PID" 2>/dev/null; then
                kill -9 "$SLAPD_PID" 2>/dev/null || true
            fi
            wait "$SLAPD_PID" 2>/dev/null || true
        fi
        sync
        SLAPD_PID=""
        
        log_info "Waiting for port 389 to be released..."
        sleep 30
        local port_wait=0
        while [ $port_wait -lt 30 ]; do
            if ! grep -q ":0185 " /proc/net/tcp 2>/dev/null; then
                break
            fi
            sleep 1
            port_wait=$((port_wait + 1))
        done
        if [ $port_wait -ge 30 ]; then
            log_warn "Port 389 still in use after 60s..."
        fi
        sleep 10
        
        setup_logrotate
        
        log_info "Starting slapd in foreground mode..."
        /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d "$LDAP_LOG_LEVEL" >> /logs/slapd.log 2>&1 &
        SLAPD_PID=$!
        wait $SLAPD_PID
    fi
}
# Setup log rotation (skipped for read-only rootfs - handle externally)
setup_logrotate() {
    # Log rotation is handled outside the container when using read-only rootfs
    # For writable containers, you can mount a custom logrotate config
    if [ -w /etc/logrotate.d ]; then
        log_step "Setting up log rotation..."
        
        cat > /etc/logrotate.d/slapd << 'EOF'
/logs/slapd.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /var/run/openldap/slapd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF
        log_success "Log rotation configured"
    else
        log_info "Read-only rootfs detected - skipping logrotate setup (handle externally)"
    fi
}

# Run main function
main "$@"
