#!/bin/bash
set -eo pipefail

# OpenLDAP replication configuration functions

source /usr/local/bin/scripts/utils.sh
source /usr/local/bin/scripts/ldif-processor.sh

# Configure replication
configure_replication() {
    local server_id=$1
    local base_dn=$2
    local bind_dn=$3
    local bind_password=$4
    local peers=$5
    local rids=$6
    
    log_header "Configuring multi-master replication..."
    
    # Refuse to start on settings that would silently corrupt replication
    validate_replication_settings "$server_id" "$peers"
    
    # Set server ID
    set_server_id "$server_id"
    
    # Load syncprov module
    load_syncprov_module
    
    # Add syncprov overlay
    add_syncprov_overlay
    
    # Configure replication peers
    if [ -n "$peers" ]; then
        configure_replication_peers "$base_dn" "$bind_dn" "$bind_password" "$peers" "$rids"
    fi
    
    log_success "Replication configured"
}

# Fail fast on replication settings that lead to silent, hard-to-diagnose
# corruption rather than to a clear error.
validate_replication_settings() {
    local server_id=$1
    local peers=$2

    # 1. SERVER_ID must be explicit. Two nodes that both fall back to the
    #    default serverID 1 write CSNs carrying the same sid; CSN ordering is
    #    then corrupted in a way that is very hard to diagnose.
    if [ "${SERVER_ID_WAS_SET:-false}" != "true" ]; then
        log_error "ENABLE_REPLICATION=true but SERVER_ID was not set explicitly."
        log_error "Every node must have a unique SERVER_ID; the default (1) would be"
        log_error "shared by every node whose operator forgot to set it."
        return 1
    fi

    # 2. The node must not list itself as a peer. Administrator's Guide: provider
    #    URLs "must exactly match the URLs slapd listens on. Otherwise slapd may
    #    attempt to replicate from itself, causing a loop."
    local self_names
    self_names="$(hostname 2>/dev/null || true) $(hostname -s 2>/dev/null || true) $(hostname -f 2>/dev/null || true) localhost 127.0.0.1"

    local peer
    local peer_host
    local self_name
    for peer in ${peers//,/ }; do
        peer_host=$(printf '%s' "$peer" \
            | sed -e 's|^ldaps\?://||' -e 's|:.*$||' \
            | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        if [ -z "$peer_host" ]; then
            continue
        fi
        for self_name in $self_names; do
            self_name=$(printf '%s' "$self_name" | tr '[:upper:]' '[:lower:]')
            if [ -n "$self_name" ] && [ "$peer_host" = "$self_name" ]; then
                log_error "REPLICATION_PEERS lists this node (${peer}); slapd would"
                log_error "replicate from itself, causing a replication loop."
                return 1
            fi
        done
    done

    # 3. A full SID->URL map must include this node's SID.
    if [ -n "${REPLICATION_SERVER_IDS:-}" ]; then
        # NOTE: do NOT strip whitespace with `tr -d '[:space:]'` here. That
        # deletes the newlines produced by `tr ',' '\n'`, collapsing every
        # entry into one line so `cut -f1` returns only the first SID - which
        # rejected a map that genuinely contained the node's SID.
        # awk strips whitespace per field and leaves the records intact.
        if ! printf '%s' "$REPLICATION_SERVER_IDS" | tr ',' '\n' \
                | awk -F= -v sid="$server_id" \
                    '{ gsub(/[[:space:]]/, "", $1); if ($1 == sid) found = 1 } END { exit !found }'; then
            log_error "REPLICATION_SERVER_IDS does not contain this node's SERVER_ID (${server_id})."
            log_error "Value: ${REPLICATION_SERVER_IDS}"
            return 1
        fi
    fi

    return 0
}

# Set the server ID(s).
#
# With REPLICATION_SERVER_IDS set, every node learns the full (SID, URL) map,
# which is what the 2.6 Administrator's Guide's N-Way example does. Otherwise
# fall back to a single bare olcServerID value.
set_server_id() {
    local server_id=$1
    local lines=""

    if [ -n "${REPLICATION_SERVER_IDS:-}" ]; then
        local entry
        local -a entries
        IFS=',' read -ra entries <<< "$REPLICATION_SERVER_IDS"
        for entry in "${entries[@]}"; do
            entry=$(printf '%s' "$entry" | tr -d '[:space:]')
            if [ -z "$entry" ]; then
                continue
            fi

            local sid="${entry%%=*}"
            local url="${entry#*=}"
            if [ -z "$sid" ] || [ -z "$url" ] || [ "$sid" = "$entry" ]; then
                log_error "Malformed REPLICATION_SERVER_IDS entry '${entry}' (expected SID=URL)"
                return 1
            fi
            lines="${lines}olcServerID: ${sid} ${url}"$'\n'
        done
        lines="${lines%$'\n'}"
    fi

    if [ -z "$lines" ]; then
        lines="olcServerID: ${server_id}"
    fi

    log_step "Setting server ID: $server_id"
    
    local ldif_file=$(process_ldif_template "set-server-id" \
        "SERVER_ID_LINES=${lines}")
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
}

# Load syncprov module
load_syncprov_module() {
    # Already loaded? Test for the module itself, not for the module entry.
    # The presence of cn=module{0},cn=config only proves that *some* module was
    # loaded - the memberof, refint, ppolicy and auditlog loaders each create
    # it. The previous guard tested for the entry, so syncprov.la was never
    # loaded once any other module had been loaded first, and the subsequent
    # syncprov overlay add failed (silently, because failures were swallowed).
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" 2>/dev/null | grep -q "syncprov.la"; then
        log_info "Syncprov module already loaded"
        return 0
    fi
    
    log_step "Loading syncprov module..."
    
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base 2>/dev/null | grep -q "dn: cn=module{0},cn=config"; then
        # Entry exists: append syncprov.la to it with a modify
        local ldif_file=$(get_ldif_path "add-syncprov-module")
        cp "$LDIF_TEMPLATE_DIR/add-syncprov-module.ldif" "$ldif_file"
        apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
        log_success "Syncprov module loaded"
        return 0
    fi

    local ldif_file=$(get_ldif_path "load-syncprov-module")
    cp "$LDIF_TEMPLATE_DIR/load-syncprov-module.ldif" "$ldif_file"
    
    apply_ldif_add "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Syncprov module loaded"
}

# Add syncprov overlay
add_syncprov_overlay() {
    # Check if already added
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=syncprov)" dn 2>/dev/null | grep -q "^dn:"; then
        log_info "Syncprov overlay already configured"
        return 0
    fi
    
    log_step "Adding syncprov overlay..."
    
    local ldif_file=$(get_ldif_path "add-syncprov-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-syncprov-overlay.ldif" "$ldif_file"
    
    apply_ldif_add "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Syncprov overlay added"
}

# Configure replication peers
configure_replication_peers() {
    local base_dn=$1
    local bind_dn=$2
    local bind_password=$3
    local peers=$4
    local rids=$5
    
    # Check if already configured
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={2}mdb,cn=config" 2>/dev/null | grep -q "olcSyncrepl:"; then
        log_info "Replication peers already configured, skipping"
        return 0
    fi
    
    log_step "Configuring replication peers..."
    
    # Parse RIDs if provided
    local -a RID_ARRAY
    if [ -n "$rids" ]; then
        IFS=',' read -ra RID_ARRAY <<< "$rids"
    fi
    
    local rid_index=0
    local auto_rid=100

    # StartTLS / certificate verification options appended to every olcSyncRepl.
    # syncrepl uses bindmethod=simple, so without TLS the bind password crosses
    # the network in cleartext even when TLS is configured for clients.
    local tls_opts=""
    case "${LDAP_REPLICATION_STARTTLS:-}" in
        ""|false|no|0)
            tls_opts=""
            ;;
        *)
            tls_opts=" starttls=critical tls_reqcert=${LDAP_REPLICATION_TLS_REQCERT:-demand}"
            ;;
    esac
    if [ -z "$tls_opts" ]; then
        log_warn "Replication is not using TLS: bind credentials cross the network in cleartext."
        log_warn "Set LDAP_REPLICATION_STARTTLS=critical and configure TLS on every node."
    fi

    for peer in ${peers//,/ }; do
        # Determine RID
        local current_rid
        if [ ${#RID_ARRAY[@]} -gt 0 ] && [ $rid_index -lt ${#RID_ARRAY[@]} ]; then
            current_rid=${RID_ARRAY[$rid_index]}
        else
            auto_rid=$((auto_rid + 1))
            current_rid=$auto_rid
        fi
        
        log_step "Adding peer: $peer (RID: $current_rid)"
        
        local ldif_file=$(process_ldif_template "add-syncrepl-peer" \
            "RID=${current_rid}" \
            "PEER=${peer}" \
            "BIND_DN=${bind_dn}" \
            "BIND_PASSWORD=${bind_password}" \
            "LDAP_BASE_DN=${base_dn}" \
            "TLS_OPTS=${tls_opts}")
        
        apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
        
        rid_index=$((rid_index + 1))
    done
    
    # Enable multi-provider mode
    enable_mirror_mode
}

# Enable multi-provider mode
enable_mirror_mode() {
    log_step "Enabling mirror mode..."
    
    local ldif_file=$(get_ldif_path "enable-mirror-mode")
    cp "$LDIF_TEMPLATE_DIR/enable-mirror-mode.ldif" "$ldif_file"
    
    apply_ldif_modify "$ldif_file" -Y EXTERNAL -H ldapi:///
    
    log_success "Multi-provider mode enabled"
}

# Check if replication is configured
is_replication_configured() {
    local server_id=$1
    
    if [ "$ENABLE_REPLICATION" != "true" ]; then
        return 1
    fi
    
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcServerID=$server_id)" 2>/dev/null | grep -q "olcServerID: $server_id"; then
        return 0
    fi
    
    return 1
}
