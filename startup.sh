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
: "${INCLUDE_SCHEMAS:=}"
: "${LDAP_PORT:=389}"
: "${LDAPS_PORT:=636}"
: "${LDAP_CONN_MAX_PENDING:=100}"
: "${LDAP_CONN_MAX_PENDING_AUTH:=1000}"
: "${LDAP_THREADS:=16}"
# NOTE: do NOT write this as : "${LDAP_PASSWORD_HASH:={SSHA}}". The closing
# brace inside {SSHA} terminates the parameter expansion, so the value silently
# becomes "{SSHA" (5 chars) and slapd rejects it with
#   <olcPasswordHash> no valid hashes found
: "${LDAP_PASSWORD_HASH:=}"
if [ -z "$LDAP_PASSWORD_HASH" ]; then
    LDAP_PASSWORD_HASH='{SSHA}'
fi
: "${LDAP_DISABLE_ANONYMOUS_BIND:=false}"
: "${LDAP_READ_ACCESS_SUBJECT:=users}"
: "${LDAP_QUERY_SIZE_SOFT:=500}"
: "${LDAP_QUERY_SIZE_HARD:=1000}"
: "${RUNTIME_ENV:=/var/run/openldap/ldap-runtime.env}"
: "${READY_FILE:=/var/run/openldap/initialized}"

# Record whether SERVER_ID was supplied explicitly, before applying a default.
# With replication enabled, a defaulted SERVER_ID means every node whose
# operator forgot to set it shares serverID 1; the resulting duplicate CSN
# sids corrupt replication in ways that are very hard to diagnose.
SERVER_ID_WAS_SET=false
if [ -n "${SERVER_ID:-}" ]; then
    SERVER_ID_WAS_SET=true
fi
: "${SERVER_ID:=1}"
export SERVER_ID_WAS_SET

# Dedicated replication / monitoring identities. When LDAP_REPLICATION_PASSWORD
# is set, replication binds as cn=replicator,<base> instead of the directory
# rootDN, so the directory administrator credential is not the one stored in
# cleartext in cn=config and shared across the cluster.
: "${LDAP_REPLICATION_PASSWORD:=}"
: "${LDAP_REPLICATION_PASSWORD_FILE:=}"
: "${LDAP_MONITOR_PASSWORD:=}"
: "${LDAP_MONITOR_PASSWORD_FILE:=}"
: "${REPLICATION_SERVER_IDS:=}"
: "${LDAP_REPLICATION_STARTTLS:=}"
: "${LDAP_REPLICATION_TLS_REQCERT:=demand}"

# TLS hardening, applied only when LDAP_TLS_CERT / LDAP_TLS_KEY are set.
# LDAP_TLS_PROTOCOL_MIN 3.3 = TLS 1.2 (SSL3=3.0, TLS1.0=3.1, TLS1.1=3.2, TLS1.2=3.3).
# LDAP_TLS_CIPHER_SUITE is left empty by default so that we do not pin a suite
# list that may be wrong for the OpenSSL build in use.
: "${LDAP_TLS_PROTOCOL_MIN:=3.3}"
: "${LDAP_TLS_VERIFY_CLIENT:=never}"
: "${LDAP_TLS_CIPHER_SUITE:=}"

# Log level. The "stats" level (256) does NOT include syncrepl activity, which
# makes replication failures invisible in the logs - a silent divergence that
# lasts for days is the classic outcome. When replication is enabled the
# default also enables "sync" (16384), i.e. 16640. Set LDAP_LOG_LEVEL to
# override explicitly.
if [ -z "${LDAP_LOG_LEVEL:-}" ]; then
    if [ "$ENABLE_REPLICATION" = "true" ]; then
        LDAP_LOG_LEVEL=16640
    else
        LDAP_LOG_LEVEL=256
    fi
fi

# Load passwords from files if specified (more secure than env vars).
#
# The value is read into the named variable and never echoed; its length is not
# logged either. A *_FILE that is set but unreadable is a hard failure: the old
# behaviour silently fell back to the built-in default password ("admin"),
# which is a far worse outcome than refusing to start.
load_secret_from_file() {
    local var_name=$1
    local file_var=$2
    local file_path=${!file_var:-}

    if [ -z "$file_path" ]; then
        return 0
    fi

    if [ ! -f "$file_path" ]; then
        log_error "${file_var} is set but the file does not exist: ${file_path}"
        return 1
    fi

    local secret
    secret=$(tr -d '\n\r' < "$file_path")
    if [ -z "$secret" ]; then
        log_error "${file_var} file is empty: ${file_path}"
        return 1
    fi

    printf -v "$var_name" '%s' "$secret"
    # Export the variable *named* by $var_name. ${var_name?} is used rather
    # than a bare "$var_name" only to silence shellcheck SC2163; both forms
    # export the indirect name (verified: the name lands in the environment).
    export "${var_name?}"
    log_info "Loaded ${var_name} from ${file_path}"
}

load_secret_from_file LDAP_ADMIN_PASSWORD LDAP_ADMIN_PASSWORD_FILE
load_secret_from_file LDAP_CONFIG_PASSWORD LDAP_CONFIG_PASSWORD_FILE
load_secret_from_file LDAP_REPLICATION_PASSWORD LDAP_REPLICATION_PASSWORD_FILE
load_secret_from_file LDAP_MONITOR_PASSWORD LDAP_MONITOR_PASSWORD_FILE

# Export for use in sourced scripts
export LDAP_DOMAIN LDAP_ORGANIZATION LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD
export LDAP_REPLICATION_PASSWORD LDAP_MONITOR_PASSWORD
export ENABLE_REPLICATION ENABLE_MONITORING ENABLE_MEMBEROF ENABLE_PASSWORD_POLICY ENABLE_AUDIT_LOG SERVER_ID
export LDAP_CONN_MAX_PENDING LDAP_CONN_MAX_PENDING_AUTH
export LDAP_THREADS LDAP_PASSWORD_HASH LDAP_DISABLE_ANONYMOUS_BIND LDAP_READ_ACCESS_SUBJECT
export LDAP_QUERY_SIZE_SOFT LDAP_QUERY_SIZE_HARD
export REPLICATION_SERVER_IDS LDAP_REPLICATION_STARTTLS LDAP_REPLICATION_TLS_REQCERT
export LDAP_TLS_PROTOCOL_MIN LDAP_TLS_VERIFY_CLIENT LDAP_TLS_CIPHER_SUITE
export LDAP_LOG_LEVEL LDAP_PORT LDAPS_PORT RUNTIME_ENV READY_FILE

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

# Persist runtime-derived values so helper scripts run via `docker exec`
# (healthcheck.sh, ldapcheck.sh) can see them.
#
# These are NOT container environment variables: LDAP_BASE_DN and friends are
# derived here at startup. That is precisely why the replication branch of the
# old healthcheck silently skipped itself - it tested an unset variable. A file
# is the only way to hand state from PID 1 to a later `docker exec` process.
#
# Contains NO secrets - never add passwords or hashes here.
write_runtime_env() {
    local runtime_dir
    runtime_dir=$(dirname "$RUNTIME_ENV")

    mkdir -p "$runtime_dir" 2>/dev/null || true

    {
        echo "# Generated by startup.sh. Values derived at container start."
        echo "# Contains no secrets. Sourced by healthcheck.sh and ldapcheck.sh."
        printf 'LDAP_BASE_DN=%s\n' "$LDAP_BASE_DN"
        printf 'LDAP_ADMIN_DN=%s\n' "$LDAP_ADMIN_DN"
        printf 'SERVER_ID=%s\n' "$SERVER_ID"
        printf 'REPLICATION_PEERS=%s\n' "${REPLICATION_PEERS:-}"
        printf 'REPLICATION_SERVER_IDS=%s\n' "${REPLICATION_SERVER_IDS:-}"
        printf 'ENABLE_REPLICATION=%s\n' "$ENABLE_REPLICATION"
        printf 'ENABLE_MONITORING=%s\n' "$ENABLE_MONITORING"
        printf 'ENABLE_MEMBEROF=%s\n' "$ENABLE_MEMBEROF"
        printf 'ENABLE_PASSWORD_POLICY=%s\n' "$ENABLE_PASSWORD_POLICY"
        printf 'ENABLE_AUDIT_LOG=%s\n' "$ENABLE_AUDIT_LOG"
        printf 'LDAP_DISABLE_ANONYMOUS_BIND=%s\n' "$LDAP_DISABLE_ANONYMOUS_BIND"
        printf 'LDAP_QUERY_SIZE_SOFT=%s\n' "$LDAP_QUERY_SIZE_SOFT"
        printf 'LDAP_QUERY_SIZE_HARD=%s\n' "$LDAP_QUERY_SIZE_HARD"
        printf 'LDAP_PORT=%s\n' "$LDAP_PORT"
        printf 'LDAPS_PORT=%s\n' "$LDAPS_PORT"
        if [ -n "${LDAP_TLS_CERT:-}" ] && [ -n "${LDAP_TLS_KEY:-}" ]; then
            printf 'LDAP_TLS_ENABLED=true\n'
        else
            printf 'LDAP_TLS_ENABLED=false\n'
        fi
    } > "$RUNTIME_ENV"

    chmod 644 "$RUNTIME_ENV" 2>/dev/null || true
    log_info "Runtime values written to ${RUNTIME_ENV}"
}

# Return 0 if something is LISTENing on the given TCP port (hex, e.g. :0185).
#
# /proc/net/tcp lists every socket, including connections left in TIME_WAIT
# whose LOCAL port is the one we care about. TIME_WAIT does not prevent a new
# bind (slapd sets SO_REUSEADDR), so treating it as "port still in use" made
# every cold start wait the full timeout - 60s of dead time.
has_listener() {
    local port_hex=$1
    local f
    for f in /proc/net/tcp /proc/net/tcp6; do
        [ -r "$f" ] || continue
        if awk -v p="$port_hex" '$2 ~ p && $4 == "0A" { found = 1 } END { exit !found }' "$f" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Confirm slapd is serving and publish the readiness marker.
#
# healthcheck.sh requires this marker, so a container that fails during
# initialisation can never be reported healthy. Without it the healthcheck
# passed as soon as the temporary slapd was up - while configuration was still
# running and might be about to fail, which is how a container that exits with
# an LDIF error could still look healthy for a few seconds.
mark_ready() {
    if wait_for_slapd 30 1; then
        touch "$READY_FILE"
        log_success "Container is ready"
        return 0
    fi
    log_error "slapd did not become responsive after configuration"
    return 1
}

# Main startup
main() {
    log_header "Starting OpenLDAP initialization"
    
    # Clear the readiness marker. It is only re-created once slapd is actually
    # serving, and healthcheck.sh refuses to report healthy without it.
    rm -f "$READY_FILE"
    
    # Validate required environment
    validate_required_env
    
    # Password strength warnings
    warn_weak_password "$LDAP_ADMIN_PASSWORD" "LDAP_ADMIN_PASSWORD"
    warn_weak_password "$LDAP_CONFIG_PASSWORD" "LDAP_CONFIG_PASSWORD"
    
    # Setup derived values
    setup_derived_values
    
    # Publish derived values for healthcheck.sh / ldapcheck.sh
    write_runtime_env
    
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
        set_threads "$LDAP_THREADS"
        set_password_hash "$LDAP_PASSWORD_HASH"
        set_connection_limits "$LDAP_CONN_MAX_PENDING" "$LDAP_CONN_MAX_PENDING_AUTH"
        configure_monitor "$ENABLE_MONITORING"
        set_log_level "$LDAP_LOG_LEVEL"
        enable_db_monitoring "$ENABLE_MONITORING"
        configure_anonymous_bind "$LDAP_DISABLE_ANONYMOUS_BIND"
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
    
    # Create the dedicated replication / monitoring bind accounts. Must run
    # after the base domain exists and before replication is configured.
    configure_service_accounts
    
    # Configure password policy (must be after base domain is created)
    configure_password_policy "$ENABLE_PASSWORD_POLICY"
    
    # Configure replication if enabled
    if [ "$ENABLE_REPLICATION" = "true" ]; then
        # Prefer the least-privilege cn=replicator account. Binding as the
        # rootDN stores the directory administrator password in cleartext in
        # cn=config on every node, and is deprecated.
        local repl_bind_dn="$LDAP_ADMIN_DN"
        local repl_bind_password="$LDAP_ADMIN_PASSWORD"
        if [ -n "${LDAP_REPLICATION_PASSWORD:-}" ]; then
            repl_bind_dn="cn=replicator,${LDAP_BASE_DN}"
            repl_bind_password="$LDAP_REPLICATION_PASSWORD"
        fi
        
        configure_replication "$SERVER_ID" "$LDAP_BASE_DN" "$repl_bind_dn" "$repl_bind_password" "$REPLICATION_PEERS" "$REPLICATION_RIDS"
    fi
    
    log_header "OpenLDAP initialization completed"
    log_info "LDAP listening on ldap://0.0.0.0:${LDAP_PORT} ldaps://0.0.0.0:${LDAPS_PORT}"
    log_info "Activity logs: stdout/stderr (use 'docker logs'); audit log: /logs/audit.log"
    
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
        # NOTE: a "slapcat -b <suffix> >/dev/null" used to run here as a flush.
        # It reads the entire database on every start, so startup cost scaled
        # with directory size for no benefit: olcSpCheckpoint (see
        # add-syncprov-overlay.ldif) persists the contextCSN, and a clean
        # SIGTERM shutdown flushes LMDB.
        sync
        
        # Keep slapd running with proper signal handling
        if ! mark_ready; then
            exit 1
        fi
        log_info "Keeping slapd running in foreground..."
        wait $SLAPD_PID
    else
        # No init scripts - stop slapd and restart cleanly
        log_step "Syncing database to disk..."
        # NOTE: a "slapcat -b <suffix> >/dev/null" used to run here as a flush.
        # It reads the entire database on every start, so startup cost scaled
        # with directory size for no benefit: olcSpCheckpoint (see
        # add-syncprov-overlay.ldif) persists the contextCSN, and a clean
        # SIGTERM shutdown flushes LMDB.
        sync
        
        log_info "Stopping temporary slapd..."
        if kill -0 "$SLAPD_PID" 2>/dev/null; then
            kill -TERM "$SLAPD_PID" 2>/dev/null || true
            local wait_count=0
            while [ "$wait_count" -lt 10 ]; do
                if ! kill -0 "$SLAPD_PID" 2>/dev/null; then
                    break
                fi
                sleep 1
                wait_count=$((wait_count + 1))
            done
            if kill -0 "$SLAPD_PID" 2>/dev/null; then
                kill -9 "$SLAPD_PID" 2>/dev/null || true
            fi
            wait "$SLAPD_PID" 2>/dev/null || true
        fi
        sync
        SLAPD_PID=""
        
        log_info "Waiting for port ${LDAP_PORT} to be released..."
        # Poll instead of sleeping a flat 30s and then another 10s. Only a
        # LISTEN socket blocks a rebind - see has_listener().
        local port_hex
        port_hex=$(printf ':%04X' "$LDAP_PORT")
        local port_wait=0
        while [ $port_wait -lt 30 ]; do
            if ! has_listener "$port_hex"; then
                break
            fi
            sleep 1
            port_wait=$((port_wait + 1))
        done
        if [ $port_wait -ge 30 ]; then
            log_warn "Port ${LDAP_PORT} is still LISTENing after 30s; starting anyway."
        fi
        
        log_info "Starting slapd in foreground mode..."
        # Log to stdout/stderr rather than /logs/slapd.log so the container
        # runtime actually receives slapd's output (docker logs, the compose
        # json-file driver, Loki/ELK/CloudWatch). Writing to a file inside the
        # container made the compose "logging:" block a no-op and depended on
        # logrotate, which is installed and configured but never executed -
        # there is no cron or systemd in this image.
        /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d "$LDAP_LOG_LEVEL" &
        SLAPD_PID=$!
        
        if ! mark_ready; then
            exit 1
        fi
        wait $SLAPD_PID
    fi
}
# Logging and log rotation
#
# slapd logs to stdout/stderr (see the foreground start in main), so rotation
# is the container runtime's job - docker-compose.yml sets the json-file driver
# with max-size/max-file.
#
# The previous setup_logrotate() wrote an /etc/logrotate.d/slapd config that
# was never executed: the image installs logrotate but has no cron or systemd
# to run it, and nothing invoked it directly. It was removed rather than fixed
# because logging to stdout is the correct pattern for a container.
#
# /logs/audit.log is the exception: the auditlog overlay appends to a file that
# slapd holds open, so the container log driver cannot manage it. It grows
# without bound unless rotated externally (sidecar, or host-side rotation of
# the mounted volume).

# Run main function
main "$@"
