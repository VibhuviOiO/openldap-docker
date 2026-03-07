# Overlay Features Test Use-Case

Tests `memberOf`, `ppolicy` (password policy), and `auditlog` overlays in a single-node deployment.

## Features Tested

| Feature | Validation |
|---------|-----------|
| **memberOf** | User entries show `memberOf` attribute when added to groups |
| **ppolicy** | Weak passwords rejected, strong passwords accepted |
| **auditlog** | All modifications logged to `/logs/audit.log` |

## Quick Start

```bash
cd use-cases/overlay-features

# Start OpenLDAP with overlays enabled
docker-compose up -d

# Wait for initialization (the init script runs automatically)
docker logs -f openldap-overlays

# Check test results
docker logs openldap-overlays 2>&1 | grep -E "(PASS|FAIL|Testing)"

# View audit log
docker exec openldap-overlays cat /logs/audit.log
```

## Manual Testing

```bash
# Test memberOf
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "uid=user1,ou=Users,dc=example,dc=com" \
  "(objectClass=*)" memberOf

# Test password policy (should fail)
ldappasswd -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -s "123" \
  "uid=user1,ou=Users,dc=example,dc=com"

# View audit log
docker exec openldap-overlays tail -20 /logs/audit.log
```

## Expected Output

```
=== Test 1: memberOf overlay ===
✓ PASS: memberOf attribute correctly set on user1

=== Test 2: Password Policy overlay ===
✓ PASS: Weak password correctly rejected
✓ PASS: Strong password accepted

=== Test 3: Audit Log ===
✓ PASS: Audit log file exists
```
