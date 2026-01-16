#!/bin/bash
set -e

# Default values
: "${LDAP_LOG_LEVEL:=256}"
: "${LDAP_DOMAIN:=example.com}"
: "${LDAP_ORGANIZATION:=Example Organization}"
: "${LDAP_ADMIN_PASSWORD:=admin}"
: "${LDAP_CONFIG_PASSWORD:=config}"
: "${ENABLE_REPLICATION:=false}"
: "${ENABLE_MONITORING:=true}"
: "${SERVER_ID:=1}"
: "${INCLUDE_SCHEMAS:=}"

# Derived values
IFS='.' read -ra DC_PARTS <<< "$LDAP_DOMAIN"
LDAP_BASE_DN=$(printf "dc=%s," "${DC_PARTS[@]}" | sed 's/,$//')
LDAP_ADMIN_DN="cn=Manager,${LDAP_BASE_DN}"

echo "🚀 Starting OpenLDAP initialization..."
echo "   Domain: $LDAP_DOMAIN"
echo "   Base DN: $LDAP_BASE_DN"
echo "   Replication: $ENABLE_REPLICATION"
echo "   Monitoring: $ENABLE_MONITORING"
echo "   Server ID: $SERVER_ID"

# Generate password hashes
ADMIN_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
CONFIG_HASH=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")

# Start slapd in background for configuration
mkdir -p /logs
chown ldap:ldap /logs
/usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d 1 >/dev/null 2>&1 &
SLAPD_PID=$!

# Wait for slapd to be ready
echo "⏳ Waiting for slapd to initialize..."
for i in {1..30}; do
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(objectClass=*)" >/dev/null 2>&1; then
        echo "✅ slapd is ready"
        break
    fi
    sleep 1
done
if [ $i -eq 30 ]; then
    echo "❌ slapd failed to start"
    exit 1
fi

# Check if already configured
if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcDatabase={2}mdb)" 2>/dev/null | grep -q "olcSuffix: $LDAP_BASE_DN"; then
    echo "ℹ️  Database already configured"
else
    echo "🔧 Configuring OpenLDAP..."

    # Set config password
    echo "🔹 Setting config password..."
    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $CONFIG_HASH
EOF

    # Configure database
    echo "🔹 Configuring database..."
    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE_DN
-
replace: olcRootDN
olcRootDN: $LDAP_ADMIN_DN
-
add: olcRootPW
olcRootPW: $ADMIN_HASH
EOF

    # Set database access
    echo "🔹 Setting database access..."
    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="$LDAP_ADMIN_DN" write by anonymous auth by self write by * none
-
add: olcAccess
olcAccess: {1}to dn.base="" by * read
-
add: olcAccess
olcAccess: {2}to * by dn="$LDAP_ADMIN_DN" write by * read
EOF

    # Set monitor access
    if [ "$ENABLE_MONITORING" = "true" ]; then
        echo "🔹 Enabling cn=Monitor access for Manager DN..."
        cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="$LDAP_ADMIN_DN" read by * none
EOF
    else
        echo "🔹 Monitoring disabled - cn=Monitor not accessible"
    fi

    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats stats2
EOF

    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcMonitoring
olcMonitoring: TRUE
EOF

    echo "✅ Database configured"
fi

# Create base domain if it doesn't exist
if ! ldapsearch -x -H ldap://localhost:389 -b "$LDAP_BASE_DN" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -s base "(objectClass=*)" >/dev/null 2>&1; then
    echo "🔹 Creating base domain..."
    cat <<EOF | ldapadd -x -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" 2>&1 | grep -v "adding new entry"
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: $LDAP_ORGANIZATION
dc: ${DC_PARTS[0]}

dn: $LDAP_ADMIN_DN
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: People

dn: ou=Group,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: Group
EOF
    echo "✅ Base domain created"
else
    echo "ℹ️  Base domain already exists"
fi

# Load schemas
if [ -n "$INCLUDE_SCHEMAS" ]; then
    echo "📦 Loading schemas: $INCLUDE_SCHEMAS"
    IFS=',' read -ra SCHEMAS <<< "$INCLUDE_SCHEMAS"
    for schema in "${SCHEMAS[@]}"; do
        SCHEMA_FILE="/etc/openldap/schema/${schema}.ldif"
        if [ -f "$SCHEMA_FILE" ]; then
            if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(cn={*}$schema)" 2>/dev/null | grep -q "dn:"; then
                echo "  Loading $schema..."
                ldapadd -Y EXTERNAL -H ldapi:/// -f "$SCHEMA_FILE" 2>/dev/null && echo "  ✅ $schema loaded" || echo "  ⚠️  $schema failed"
            fi
        fi
    done
fi

# Load custom schemas
if [ -d "/custom-schema" ] && [ "$(ls -A /custom-schema/*.ldif 2>/dev/null)" ]; then
    echo "📦 Loading custom schemas..."
    for schema_file in /custom-schema/*.ldif; do
        schema_name=$(basename "$schema_file" .ldif)
        if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(cn={*}$schema_name)" 2>/dev/null | grep -q "dn:"; then
            echo "  Loading $schema_name..."
            ldapadd -Y EXTERNAL -H ldapi:/// -f "$schema_file" 2>/dev/null && echo "  ✅ $schema_name loaded" || echo "  ⚠️  $schema_name failed"
        fi
    done
fi

# Configure replication
if [ "$ENABLE_REPLICATION" = "true" ]; then
    echo "🔄 Configuring multi-master replication..."
    
    # Set server ID
    echo "🔹 Setting server ID: $SERVER_ID"
    cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: $SERVER_ID
EOF

    # Load syncprov module
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcModuleLoad=*syncprov*)" 2>/dev/null | grep -q "dn:"; then
        echo "🔹 Loading syncprov module..."
        cat <<EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModuleLoad: syncprov.la
EOF
    fi

    # Add syncprov overlay
    if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay={*}syncprov)" 2>/dev/null | grep -q "dn:"; then
        echo "🔹 Adding syncprov overlay..."
        cat <<EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: olcOverlay=syncprov,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
EOF
    fi

    # Configure replication to peers
    if [ -n "$REPLICATION_PEERS" ]; then
        echo "🔹 Configuring replication peers..."
        
        # Parse RIDs if provided, otherwise auto-generate
        if [ -n "$REPLICATION_RIDS" ]; then
            IFS=',' read -ra RIDS <<< "$REPLICATION_RIDS"
        else
            RIDS=()
        fi
        
        RID_INDEX=0
        RID=100
        for peer in ${REPLICATION_PEERS//,/ }; do
            # Use provided RID or auto-generate
            if [ ${#RIDS[@]} -gt 0 ] && [ $RID_INDEX -lt ${#RIDS[@]} ]; then
                CURRENT_RID=${RIDS[$RID_INDEX]}
            else
                RID=$((RID + 1))
                CURRENT_RID=$RID
            fi
            
            echo "  Adding peer: $peer (RID: $CURRENT_RID)"
            cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:/// 2>&1 | grep -v "modifying entry"
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl: rid=$CURRENT_RID provider=ldap://$peer:389 binddn="$LDAP_ADMIN_DN" bindmethod=simple credentials=$LDAP_ADMIN_PASSWORD searchbase="$LDAP_BASE_DN" type=refreshAndPersist retry="5 5 300 5" timeout=1
EOF
            RID_INDEX=$((RID_INDEX + 1))
        done

        # Enable mirror mode
        echo "🔹 Enabling mirror mode..."
        cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcMirrorMode
olcMirrorMode: TRUE
EOF
    fi

    echo "✅ Replication configured"
fi

echo "🎉 OpenLDAP initialization completed"
echo "📊 LDAP listening on ldap://0.0.0.0:389 ldaps://0.0.0.0:636"
echo "📝 Activity logs: /logs/slapd.log"

# Stop the background slapd quietly
kill $SLAPD_PID 2>/dev/null
wait $SLAPD_PID 2>/dev/null || true

# Start slapd in foreground
exec /usr/sbin/slapd -u ldap -g ldap -h "ldap:/// ldaps:/// ldapi:///" -d stats >> /logs/slapd.log 2>&1
