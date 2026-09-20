#!/bin/bash
set -eo pipefail

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
#
# Substitution is done with bash parameter expansion rather than sed, so
# values containing "/", "&" or "\" (DNs, hashes, paths) are inserted
# literally and need no escaping. A multi-line value is valid and is
# substituted as-is.
process_ldif_template() {
    local template_name=$1
    shift
    local template_file="$LDIF_TEMPLATE_DIR/${template_name}.ldif"
    local output_file="$LDIF_GENERATED_DIR/${template_name}.ldif"
    local content
    local var_name
    local var_value

    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Start with template content
    content=$(cat "$template_file")

    # Process each variable replacement
    for var_assignment in "$@"; do
        # Split on the FIRST "=" only, using parameter expansion rather than
        # cut. cut works line-by-line, so a multi-line value (such as the
        # optional TLS CA entry) produced a multi-line "variable name" and the
        # placeholder was never matched - the placeholder was emitted verbatim
        # into the LDIF and ldapmodify rejected the record.
        var_name="${var_assignment%%=*}"
        var_value="${var_assignment#*=}"

        # Replace placeholder using bash string replacement
        content="${content//\{\{$var_name\}\}/$var_value}"
    done

    # Write to output file
    printf '%s\n' "$content" > "$output_file"
    echo "$output_file"
}

# Apply an LDIF file with ldapmodify, retrying transient failures.
# Usage: apply_ldif_modify <ldif_file> [ldapmodify_options]
#
# The file is passed with -f so that every retry attempt re-reads it. Do NOT
# pipe the LDIF into ldapmodify: stdin is consumed by the first attempt, so
# retries would run against EOF (see ldap_retry in utils.sh).
#
# Returns non-zero when the operation ultimately fails. Callers must NOT
# swallow that with "|| true" - a failed configuration step has to abort the
# startup rather than be reported as success.
apply_ldif_modify() {
    local ldif_file=$1
    shift

    if [ ! -f "$ldif_file" ]; then
        log_error "LDIF file not found: $ldif_file"
        return 1
    fi

    ldap_retry 5 2 ldapmodify "$@" -f "$ldif_file"
}

# Apply an LDIF file with ldapadd, retrying transient failures.
# Usage: apply_ldif_add <ldif_file> [ldapadd_options]
#
# See apply_ldif_modify for why -f is required rather than a pipe.
apply_ldif_add() {
    local ldif_file=$1
    shift

    if [ ! -f "$ldif_file" ]; then
        log_error "LDIF file not found: $ldif_file"
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
