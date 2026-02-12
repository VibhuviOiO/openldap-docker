#!/bin/bash
set -e

#!/bin/bash
set -e

# Fix permissions for mounted volumes (run as root initially)
fix_permissions() {
    # Only run if we're root
    if [ "$(id -u)" = "0" ]; then
        log_info "Fixing permissions for mounted volumes..."
        # Fix ownership of volumes that need to be writable by ldap user
        for dir in /logs /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap /tmp/ldap-init /usr/local/bin/ldif/generated; do
            if [ -d "$dir" ]; then
                chown -R ldap:ldap "$dir" 2>/dev/null || true
                chmod 755 "$dir" 2>/dev/null || true
            fi
        done
    fi
}

# Source helper scripts
SCRIPT_DIR="/usr/local/bin/scripts"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/schema.sh"
source "$SCRIPT_DIR/replication.sh"

# Fix permissions (must run before anything else)
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

# Load passwords from files if specified (more secure than env vars)
if [ -n "$LDAP_ADMIN_PASSWORD_FILE" ] && [ -f "$LDAP_ADMIN_PASSWORD_FILE" ]; then
    LDAP_ADMIN_PASSWORD=$(cat "$LDAP_ADMIN_PASSWORD_FILE")
    log_info "Loaded admin password from file"
fi

if [ -n "$LDAP_CONFIG_PASSWORD_FILE" ] && [ -f "$LDAP_CONFIG_PASSWORD_FILE" ]; then
    LDAP_CONFIG_PASSWORD=$(cat "$LDAP_CONFIG_PASSWORD_FILE")
    log_info "Loaded config password from file"
fi

# Export for use in sourced scripts
export LDAP_DOMAIN LDAP_ORGANIZATION LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD
export ENABLE_REPLICATION ENABLE_MONITORING ENABLE_MEMBEROF ENABLE_PASSWORD_POLICY ENABLE_AUDIT_LOG SERVER_ID

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
    local admin_hash=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
    local config_hash=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
    
    # Prepare directories and log file
    mkdir -p /logs
    chown ldap:ldap /logs
    touch /logs/slapd.log
    chown ldap:ldap /logs/slapd.log
    
    # Start slapd in background for configuration
    log_info "Starting slapd for initial configuration..."
    # Check if slapd can start (capture errors)
    if ! /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d 1 -Tt 2>&1; then
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
        configure_monitor "$ENABLE_MONITORING"
        set_log_level "$LDAP_LOG_LEVEL"
        enable_db_monitoring
        configure_tls
        configure_memberof "$ENABLE_MEMBEROF"
        configure_password_policy "$ENABLE_PASSWORD_POLICY"
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
    
    # Configure replication if enabled
    if [ "$ENABLE_REPLICATION" = "true" ]; then
        configure_replication "$SERVER_ID" "$LDAP_BASE_DN" "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD" "$REPLICATION_PEERS" "$REPLICATION_RIDS"
    fi
    
    log_header "OpenLDAP initialization completed"
    log_info "LDAP listening on ldap://0.0.0.0:${LDAP_PORT} ldaps://0.0.0.0:${LDAPS_PORT}"
    log_info "Activity logs: /logs/slapd.log"
    
    # Stop the background slapd
    log_info "Stopping temporary slapd..."
    if kill -0 "$SLAPD_PID" 2>/dev/null; then
        kill "$SLAPD_PID" 2>/dev/null || true
        wait "$SLAPD_PID" 2>/dev/null || true
    fi
    SLAPD_PID=""
    
    # Setup log rotation
    setup_logrotate
    
    # Start slapd in foreground
    log_info "Starting slapd in foreground mode..."
    
    # Check if init scripts need to run
    local has_init_scripts=false
    if [ -d "/docker-entrypoint-initdb.d" ]; then
        for script in /docker-entrypoint-initdb.d/*.sh; do
            if [ -f "$script" ]; then
                has_init_scripts=true
                break
            fi
        done
    fi
    
    if [ "$has_init_scripts" = "false" ]; then
        # No init scripts - start slapd and wait (logs go to file)
        log_info "No init scripts found, starting slapd..."
        /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d "$LDAP_LOG_LEVEL" >> /logs/slapd.log 2>&1 &
        SLAPD_PID=$!
        wait $SLAPD_PID
    else
        # Has init scripts - need background mode
        /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d "$LDAP_LOG_LEVEL" >> /logs/slapd.log 2>&1 &
        SLAPD_PID=$!
        
        # Verify slapd started successfully
        sleep 2
        if ! kill -0 "$SLAPD_PID" 2>/dev/null; then
            log_error "slapd failed to start!"
            exit 1
        fi
        
        # Wait for slapd to be ready for init scripts
        if ! wait_for_slapd 30 1; then
            log_error "slapd not ready for init scripts"
            exit 1
        fi
        
        # Run init scripts
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
        
        # Keep slapd running with proper signal handling
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
