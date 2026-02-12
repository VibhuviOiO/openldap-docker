#!/bin/bash
# OpenLDAP schema loading functions

source /usr/local/bin/scripts/utils.sh

# Load built-in schemas
load_builtin_schemas() {
    local schemas=$1
    
    if [ -z "$schemas" ]; then
        return 0
    fi
    
    log_info "Loading built-in schemas: $schemas"
    
    IFS=',' read -ra SCHEMAS <<< "$schemas"
    for schema in "${SCHEMAS[@]}"; do
        schema=$(echo "$schema" | xargs)  # trim whitespace
        local schema_file="/etc/openldap/schema/${schema}.ldif"
        
        if [ ! -f "$schema_file" ]; then
            log_warn "Schema file not found: $schema_file"
            continue
        fi
        
        # Check if already loaded
        if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(cn={*}$schema)" 2>/dev/null | grep -q "dn:"; then
            log_info "Schema '$schema' already loaded, skipping"
            continue
        fi
        
        log_step "Loading schema: $schema"
        if ldapadd -Y EXTERNAL -H ldapi:/// -f "$schema_file" 2>/dev/null; then
            log_success "Schema '$schema' loaded"
        else
            log_warn "Failed to load schema '$schema'"
        fi
    done
}

# Load custom schemas from directory
load_custom_schemas() {
    local custom_dir="/custom-schema"
    
    if [ ! -d "$custom_dir" ]; then
        return 0
    fi
    
    local schema_files=("$custom_dir"/*.ldif)
    if [ ! -f "${schema_files[0]}" ]; then
        log_info "No custom schemas found in $custom_dir"
        return 0
    fi
    
    log_info "Loading custom schemas..."
    
    for schema_file in "$custom_dir"/*.ldif; do
        if [ ! -f "$schema_file" ]; then
            continue
        fi
        
        local schema_name=$(basename "$schema_file" .ldif)
        
        # Check if already loaded
        if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(cn={*}$schema_name)" 2>/dev/null | grep -q "dn:"; then
            log_info "Custom schema '$schema_name' already loaded, skipping"
            continue
        fi
        
        log_step "Loading custom schema: $schema_name"
        if ldapadd -Y EXTERNAL -H ldapi:/// -f "$schema_file" 2>/dev/null; then
            log_success "Custom schema '$schema_name' loaded"
        else
            log_warn "Failed to load custom schema '$schema_name'"
        fi
    done
}
