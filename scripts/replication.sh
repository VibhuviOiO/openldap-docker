#!/bin/bash
# OpenLDAP replication configuration functions

source /usr/local/bin/scripts/utils.sh
source /usr/local/bin/scripts/ldif-processor.sh

# Configure replication
configure_replication() {
    local server_id=$1
    local base_dn=$2
    local admin_dn=$3
    local admin_password=$4
    local peers=$5
    local rids=$6
    
    log_header "Configuring multi-master replication..."
    
    # Set server ID
    set_server_id "$server_id"
    
    # Load syncprov module
    load_syncprov_module
    
    # Add syncprov overlay
    add_syncprov_overlay
    
    # Configure replication peers
    if [ -n "$peers" ]; then
        configure_replication_peers "$base_dn" "$admin_dn" "$admin_password" "$peers" "$rids"
    fi
    
    log_success "Replication configured"
}

# Set server ID
set_server_id() {
    local server_id=$1
    
    log_step "Setting server ID: $server_id"
    
    local ldif_file=$(process_ldif_template "set-server-id" \
        "SERVER_ID=${server_id}")
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
}

# Load syncprov module
load_syncprov_module() {
    # Check if already loaded
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base 2>/dev/null | grep -q "dn: cn=module{0},cn=config"; then
        log_info "Syncprov module already loaded"
        return 0
    fi
    
    log_step "Loading syncprov module..."
    
    local ldif_file=$(get_ldif_path "load-syncprov-module")
    cp "$LDIF_TEMPLATE_DIR/load-syncprov-module.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
    
    log_success "Syncprov module loaded"
}

# Add syncprov overlay
add_syncprov_overlay() {
    # Check if already added
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={2}mdb,cn=config" 2>/dev/null | grep -q "olcOverlay={0}syncprov"; then
        log_info "Syncprov overlay already configured"
        return 0
    fi
    
    log_step "Adding syncprov overlay..."
    
    local ldif_file=$(get_ldif_path "add-syncprov-overlay")
    cp "$LDIF_TEMPLATE_DIR/add-syncprov-overlay.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapadd -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "adding new entry" || true
    
    log_success "Syncprov overlay added"
}

# Configure replication peers
configure_replication_peers() {
    local base_dn=$1
    local admin_dn=$2
    local admin_password=$3
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
            "LDAP_ADMIN_DN=${admin_dn}" \
            "LDAP_ADMIN_PASSWORD=${admin_password}" \
            "LDAP_BASE_DN=${base_dn}")
        
        cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
        
        rid_index=$((rid_index + 1))
    done
    
    # Enable mirror mode
    enable_mirror_mode
}

# Enable mirror mode
enable_mirror_mode() {
    log_step "Enabling mirror mode..."
    
    local ldif_file=$(get_ldif_path "enable-mirror-mode")
    cp "$LDIF_TEMPLATE_DIR/enable-mirror-mode.ldif" "$ldif_file"
    
    cat "$ldif_file" | ldap_retry 5 2 ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry" || true
    
    log_success "Mirror mode enabled"
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
