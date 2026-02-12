#!/bin/bash
# Health check script for OpenLDAP
# Usage: healthcheck.sh [check_type]
# check_type: basic (default), tls, or replication

CHECK_TYPE=${1:-basic}
LDAP_PORT=${LDAP_PORT:-389}
LDAP_HOST=${LDAP_HOST:-localhost}

check_basic() {
    # Check if slapd is listening
    if ! ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        echo "FAILED: Cannot connect to LDAP"
        exit 1
    fi
    
    # Check if we can read cn=config
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(objectClass=*)" >/dev/null 2>&1; then
        echo "FAILED: Cannot read cn=config"
        exit 1
    fi
    
    echo "OK"
    exit 0
}

# TLS check
check_tls() {
    if [ -z "$LDAP_TLS_CERT" ]; then
        echo "SKIPPED: TLS not configured"
        exit 0
    fi
    
    if ! ldapsearch -x -H "ldaps://${LDAP_HOST}:636" -b "" -s base "(objectClass=*)" >/dev/null 2>&1; then
        echo "FAILED: TLS connection failed"
        exit 1
    fi
    
    echo "OK"
    exit 0
}

# Replication check
check_replication() {
    if [ "$ENABLE_REPLICATION" != "true" ]; then
        echo "SKIPPED: Replication not enabled"
        exit 0
    fi
    
    # Check if syncprov overlay is loaded
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(objectClass=olcSyncProvConfig)" 2>/dev/null | grep -q "olcOverlay"; then
        echo "FAILED: Syncprov overlay not found"
        exit 1
    fi
    
    # Check contextCSN (indicates replication state)
    if [ -n "$LDAP_BASE_DN" ]; then
        if ! ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" -b "$LDAP_BASE_DN" -s base "(contextCSN=*)" contextCSN >/dev/null 2>&1; then
            echo "WARNING: contextCSN not found (replication may not be initialized)"
            # Don't fail, this might be initial startup
            exit 0
        fi
    fi
    
    echo "OK"
    exit 0
}

# Main
case "$CHECK_TYPE" in
    basic)
        check_basic
        ;;
    tls)
        check_tls
        ;;
    replication)
        check_replication
        ;;
    *)
        echo "Unknown check type: $CHECK_TYPE"
        exit 1
        ;;
esac
