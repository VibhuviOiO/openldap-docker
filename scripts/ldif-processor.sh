#!/bin/bash
# LDIF template processor
# Replaces placeholders in template files with actual values

# Template directory
LDIF_TEMPLATE_DIR="${LDIF_TEMPLATE_DIR:-/usr/local/bin/ldif/templates}"
# Use /tmp for generated files (supports read-only rootfs)
LDIF_GENERATED_DIR="${LDIF_GENERATED_DIR:-/tmp/ldap-init/ldif}"

# Create generated directory if not exists
mkdir -p "$LDIF_GENERATED_DIR"

# Process a template file and replace placeholders
# Usage: process_ldif_template <template_name> [var1=value1] [var2=value2] ...
process_ldif_template() {
    local template_name=$1
    shift
    local template_file="$LDIF_TEMPLATE_DIR/${template_name}.ldif"
    local output_file="$LDIF_GENERATED_DIR/${template_name}.ldif"
    local content
    local var_name
    local var_value
    
    if [ ! -f "$template_file" ]; then
        echo "Error: Template file not found: $template_file" >&2
        return 1
    fi
    
    # Start with template content
    content=$(cat "$template_file")
    
    # Process each variable replacement
    for var_assignment in "$@"; do
        var_name=$(echo "$var_assignment" | cut -d'=' -f1)
        var_value=$(echo "$var_assignment" | cut -d'=' -f2-)
        
        # Escape special characters for sed
        var_value=$(echo "$var_value" | sed 's/[&/\]/\\&/g')
        
        # Replace placeholder using bash string replacement
        content="${content//\{\{$var_name\}\}/$var_value}"
    done
    
    # Write to output file
    echo "$content" > "$output_file"
    echo "$output_file"
}

# Process LDIF with multi-line or conditional content
# Usage: process_ldif_advanced <template_name> -v VAR1=value1 -v VAR2=value2 ...
process_ldif_advanced() {
    local template_name=$1
    shift
    local template_file="$LDIF_TEMPLATE_DIR/${template_name}.ldif"
    local output_file="$LDIF_GENERATED_DIR/${template_name}.ldif"
    local var_assignment
    local var_name
    local var_value
    
    if [ ! -f "$template_file" ]; then
        echo "Error: Template file not found: $template_file" >&2
        return 1
    fi
    
    # Copy template to output
    cp "$template_file" "$output_file"
    
    # Process each variable
    while [ $# -gt 0 ]; do
        case "$1" in
            -v)
                shift
                var_assignment=$1
                var_name=$(echo "$var_assignment" | cut -d'=' -f1)
                var_value=$(echo "$var_assignment" | cut -d'=' -f2-)
                
                # Escape special characters for sed
                var_value=$(printf '%s' "$var_value" | sed 's/[&/\]/\\&/g')
                
                # Replace placeholder
                sed -i "s/{{${var_name}}}/${var_value}/g" "$output_file"
                shift
                ;;
            -r)
                # Raw replacement (for multi-line content)
                shift
                local var_name=$1
                local var_file=$2
                shift 2
                
                if [ -f "$var_file" ]; then
                    # Use awk for multi-line replacement
                    awk -v placeholder="{{${var_name}}}" -v content="$(cat "$var_file")" '{
                        gsub(placeholder, content)
                        print
                    }' "$output_file" > "${output_file}.tmp"
                    mv "${output_file}.tmp" "$output_file"
                fi
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo "$output_file"
}

# Apply LDIF file using ldapmodify with retry
# Usage: apply_ldif <ldif_file> [ldapmodify_options]
apply_ldif_modify() {
    local ldif_file=$1
    shift
    
    if [ ! -f "$ldif_file" ]; then
        echo "Error: LDIF file not found: $ldif_file" >&2
        return 1
    fi
    
    ldap_retry 5 2 ldapmodify "$@" -f "$ldif_file"
}

# Apply LDIF file using ldapadd with retry
# Usage: apply_ldif_add <ldif_file> [ldapadd_options]
apply_ldif_add() {
    local ldif_file=$1
    shift
    
    if [ ! -f "$ldif_file" ]; then
        echo "Error: LDIF file not found: $ldif_file" >&2
        return 1
    fi
    
    ldap_retry 5 2 ldapadd "$@" -f "$ldif_file"
}

# Clean up generated LDIF files
cleanup_generated_ldif() {
    rm -rf "$LDIF_GENERATED_DIR"/*.ldif
}

# Get path to generated LDIF file
# Usage: get_ldif_path <template_name>
get_ldif_path() {
    local template_name=$1
    echo "$LDIF_GENERATED_DIR/${template_name}.ldif"
}
