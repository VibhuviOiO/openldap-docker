#!/bin/bash
set -e

LDAP_URI="ldap://localhost:389"
ADMIN_DN="cn=Manager,dc=vibhuvioio,dc=com"
ADMIN_PW="changeme"
BASE_DN="dc=vibhuvioio,dc=com"

# Wait for LDAP to be ready with proper credentials
echo "⏳ Waiting for LDAP to be ready..."
for i in {1..10}; do
    if ldapsearch -x -H "$LDAP_URI" -b "$BASE_DN" -D "$ADMIN_DN" -w "$ADMIN_PW" -s base dn >/dev/null 2>&1; then
        echo "✅ LDAP is ready"
        break
    fi
    echo "  Attempt $i/10 failed, waiting..."
    sleep 3
done

echo "🔍 Checking if data already exists..."
COUNT=$(ldapsearch -x -H "$LDAP_URI" -b "ou=People,$BASE_DN" -D "$ADMIN_DN" -w "$ADMIN_PW" "(objectClass=inetOrgPerson)" dn 2>/dev/null | grep "^dn:" | wc -l || echo "0")
COUNT=$(echo $COUNT | tr -d '\n\r ')

if [ "$COUNT" -gt "0" ]; then
    echo "✅ Data already exists ($COUNT users), skipping initialization"
    exit 0
fi

echo "📥 Loading Mahabharata warriors data..."
ldapadd -x -H "$LDAP_URI" -D "$ADMIN_DN" -w "$ADMIN_PW" -f /data/mahabharata_data.ldif

echo "✅ Successfully loaded Mahabharata warriors data"
