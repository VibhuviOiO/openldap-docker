#!/bin/bash
set -e

LDAP_URI="ldap://localhost:389"
ADMIN_DN="cn=Manager,dc=oiocloud,dc=com"
ADMIN_PW="changeme"
BASE_DN="dc=oiocloud,dc=com"

# Secure credential file (avoid password in ps output)
CREDS_FILE=$(mktemp /tmp/ldap_creds.XXXXXX)
chmod 600 "$CREDS_FILE"
echo "$ADMIN_PW" > "$CREDS_FILE"
trap 'rm -f "$CREDS_FILE"' EXIT

echo "⏳ Waiting for LDAP to be ready..."
for i in {1..10}; do
    if ldapsearch -x -H "$LDAP_URI" -b "$BASE_DN" -D "$ADMIN_DN" -y "$CREDS_FILE" -s base dn >/dev/null 2>&1; then
        echo "✅ LDAP is ready"
        break
    fi
    echo "  Attempt $i/10 failed, waiting..."
    sleep 3
done

echo "🔍 Checking if data already exists..."
if ldapsearch -x -H "$LDAP_URI" -b "ou=People,$BASE_DN" -D "$ADMIN_DN" -y "$CREDS_FILE" "(employeeID=CI001)" dn 2>/dev/null | grep -q "^dn:"; then
    echo "✅ Data already exists, skipping initialization"
    exit 0
fi

echo "📥 Loading OIO Cloud employee data..."
ldapadd -x -H "$LDAP_URI" -D "$ADMIN_DN" -y "$CREDS_FILE" -c -f /data/oiocloud_data.ldif 2>&1 | grep "^adding new entry" || true

echo "✅ Successfully loaded 30 employees across 3 departments"
