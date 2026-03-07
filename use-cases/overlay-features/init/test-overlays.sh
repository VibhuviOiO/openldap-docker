#!/bin/bash
# Integration test for overlay features (memberOf, ppolicy, auditlog)
set -eo pipefail

LDAP_HOST="openldap-overlays"
LDAP_ADMIN_DN="cn=Manager,dc=example,dc=com"
LDAP_ADMIN_PASSWORD="AdminPass123!"
BASE_DN="dc=example,dc=com"

echo "=========================================="
echo "Testing Overlay Features"
echo "=========================================="

# Wait for OpenLDAP to be fully ready
sleep 3

echo ""
echo "=== Test 1: memberOf overlay ==="
echo "Creating test users and groups..."

# Create OU for users and groups
ldapadd -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" << EOF
ou: Groups
dn: ou=Groups,$BASE_DN
objectClass: organizationalUnit
ou: Groups

ou: Users
dn: ou=Users,$BASE_DN
objectClass: organizationalUnit
ou: Users

# Create test user 1
dn: uid=user1,ou=Users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
uid: user1
cn: Test User 1
sn: User1
uidNumber: 10001
gidNumber: 10000
homeDirectory: /home/user1
userPassword: TestPass123!

# Create test user 2
dn: uid=user2,ou=Users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
uid: user2
cn: Test User 2
sn: User2
uidNumber: 10002
gidNumber: 10000
homeDirectory: /home/user2
userPassword: TestPass456!

# Create test group
dn: cn=developers,ou=Groups,$BASE_DN
objectClass: groupOfNames
cn: developers
member: uid=user1,ou=Users,$BASE_DN
member: uid=user2,ou=Users,$BASE_DN
EOF

echo "Verifying memberOf attribute on user1..."
if ldapsearch -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
    -b "uid=user1,ou=Users,$BASE_DN" "(objectClass=*)" memberOf | grep -q "memberOf: cn=developers,ou=Groups,$BASE_DN"; then
    echo "✓ PASS: memberOf attribute correctly set on user1"
else
    echo "✗ FAIL: memberOf attribute not found on user1"
    exit 1
fi

echo ""
echo "=== Test 2: Password Policy overlay ==="
echo "Testing password rejection (too short)..."

# Try to set a weak password (should fail)
if ldapmodify -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" << EOF 2>&1 | grep -q "Password fails quality checking"; then
    dn: uid=user1,ou=Users,$BASE_DN
    changetype: modify
    replace: userPassword
    userPassword: 123
EOF
    echo "✓ PASS: Weak password correctly rejected"
else
    echo "✗ FAIL: Weak password was accepted (policy not working)"
    exit 1
fi

echo "Testing password acceptance (strong)..."
if ldapmodify -x -H ldap://$LDAP_HOST:389 -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" << EOF 2>&1 | grep -q "modifying entry"; then
    dn: uid=user1,ou=Users,$BASE_DN
    changetype: modify
    replace: userPassword
    userPassword: StrongPass789!
EOF
    echo "✓ PASS: Strong password accepted"
else
    echo "✗ FAIL: Strong password was rejected"
    exit 1
fi

echo ""
echo "=== Test 3: Audit Log ==="
echo "Checking audit log file..."
sleep 2  # Give auditlog time to write

if [ -f /logs/audit.log ]; then
    echo "✓ PASS: Audit log file exists"
    echo "Audit log entries:"
    wc -l /logs/audit.log
    echo ""
    echo "Sample audit entries:"
    tail -10 /logs/audit.log
else
    echo "✗ FAIL: Audit log file not found"
    exit 1
fi

echo ""
echo "=========================================="
echo "All overlay tests PASSED!"
echo "=========================================="
