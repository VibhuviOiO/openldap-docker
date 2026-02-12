#!/bin/bash
# Common utility functions for OpenLDAP startup

set -e

# Logging functions
log_info() { echo "ℹ️  $1"; }
log_success() { echo "✅ $1"; }
log_warn() { echo "⚠️  $1"; }
log_error() { echo "❌ $1"; }
log_step() { echo "🔹 $1"; }
log_header() { echo "🚀 $1"; }

# Retry logic for LDAP operations
# Usage: ldap_retry <max_attempts> <delay_seconds> <ldap_command> [args...]
ldap_retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1
    
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@" 2>/dev/null; then
            return 0
        fi
        
        if [ "$attempt" -lt "$max_attempts" ]; then
            log_warn "LDAP operation failed, retrying ($attempt/$max_attempts) in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done
    
    log_error "LDAP operation failed after $max_attempts attempts"
    return 1
}

# Wait for slapd to be ready
wait_for_slapd() {
    local max_wait=${1:-30}
    local wait_interval=${2:-1}
    local _i
    
    log_info "Waiting for slapd to initialize (max ${max_wait}s)..."
    
    for _i in $(seq 1 "$max_wait"); do
        if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(objectClass=*)" >/dev/null 2>&1; then
            log_success "slapd is ready"
            return 0
        fi
        sleep "$wait_interval"
    done
    
    log_error "slapd failed to start within ${max_wait} seconds"
    return 1
}

# Check if slapd is running
is_slapd_running() {
    local pid=$1
    kill -0 "$pid" 2>/dev/null
}

# Validate required environment variables
validate_required_env() {
    local required=("LDAP_DOMAIN")
    local missing=()
    
    for var in "${required[@]}"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Required environment variables not set: ${missing[*]}"
        exit 1
    fi
}

# Password strength check
warn_weak_password() {
    local password=$1
    local name=$2
    
    if [ "${#password}" -lt 8 ]; then
        log_warn "$name is less than 8 characters - consider using a stronger password"
    fi
}

# Create temporary credentials file for secure password handling
# Usage: create_creds_file <password>
# Returns: path to temp file
create_creds_file() {
    local password=$1
    local tmpfile
    tmpfile=$(mktemp /tmp/ldap_creds.XXXXXX)
    chmod 600 "$tmpfile"
    echo "$password" > "$tmpfile"
    echo "$tmpfile"
}

# Cleanup credentials file
remove_creds_file() {
    local file=$1
    if [ -f "$file" ]; then
        rm -f "$file"
    fi
}

# Cleanup function for signal handling
cleanup_slapd() {
    local pid=$1
    log_info "Received shutdown signal, stopping slapd..."
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}
