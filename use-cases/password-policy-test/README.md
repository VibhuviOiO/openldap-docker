# Password Policy Test Use-Case

This use-case validates the OpenLDAP password policy overlay functionality, ensuring that password policies are correctly applied and enforced.

## Overview

- **Domain**: `test.com`
- **Base DN**: `dc=test,dc=com`
- **Admin DN**: `cn=Manager,dc=test,dc=com`
- **Ports**: 391 (LDAP), 638 (LDAPS)
- **Feature**: Password Policy Overlay (`ENABLE_PASSWORD_POLICY=true`)

## Default Password Policy

The following password policy is automatically configured on startup:

| Attribute | Value | Description |
|-----------|-------|-------------|
| `pwdMinLength` | 8 | Minimum password length |
| `pwdMaxFailure` | 5 | Maximum failed login attempts |
| `pwdLockout` | TRUE | Account lockout enabled |
| `pwdLockoutDuration` | 1800 | Lockout duration in seconds (30 min) |
| `pwdMaxAge` | 7776000 | Password expiration in seconds (90 days) |
| `pwdInHistory` | 5 | Number of passwords in history |
| `pwdMustChange` | TRUE | User must change password on first login |

## Quick Start

```bash
# Ensure the shared network exists
docker network create ldap-shared-network 2>/dev/null || true

# Start the OpenLDAP container with password policy enabled
docker-compose up -d

# View logs to see test results
docker logs -f openldap-password-policy
```

## Automated Tests

The `test-password-policy.sh` script automatically runs on container startup and validates:

1. **Overlay Configuration** - Verifies ppolicy overlay is loaded in cn=config
2. **Policy OU Exists** - Confirms `ou=Policies,dc=test,dc=com` exists
3. **Default Policy Exists** - Confirms `cn=default,ou=Policies,dc=test,dc=com` exists
4. **Policy Attributes** - Validates pwdMinLength, pwdMaxFailure, pwdLockout settings
5. **Password Enforcement** - Tests that weak passwords are rejected and strong passwords are accepted

## Manual Testing

```bash
# Search for password policy
ldapsearch -x -H ldap://localhost:391 \
  -D "cn=Manager,dc=test,dc=com" -w admin123 \
  -b "cn=default,ou=Policies,dc=test,dc=com" -s base

# Try to create a user with weak password (should fail)
ldapadd -x -H ldap://localhost:391 \
  -D "cn=Manager,dc=test,dc=com" -w admin123 <<EOF
dn: uid=weakuser,ou=People,dc=test,dc=com
objectClass: inetOrgPerson
uid: weakuser
cn: Weak User
sn: User
userPassword: 123
EOF

# Create a user with strong password (should succeed)
ldapadd -x -H ldap://localhost:391 \
  -D "cn=Manager,dc=test,dc=com" -w admin123 <<EOF
dn: uid=stronguser,ou=People,dc=test,dc=com
objectClass: inetOrgPerson
uid: stronguser
cn: Strong User
sn: User
userPassword: MySecurePass123!
EOF
```

## Files

- `.env.password-policy` - LDAP configuration with `ENABLE_PASSWORD_POLICY=true`
- `docker-compose.yml` - Container configuration
- `test-password-policy.sh` - Automated validation tests

## Cleanup

```bash
# Stop but keep data
docker-compose down

# Stop and remove all data
docker-compose down -v
```

## Troubleshooting

If password policy is not being enforced:

1. Check logs: `docker logs openldap-password-policy`
2. Verify overlay is loaded:
   ```bash
   ldapsearch -x -H ldap://localhost:391 \
     -D "cn=Manager,dc=test,dc=com" -w admin123 \
     -b "cn=config" "(objectClass=olcPPolicyConfig)"
   ```
3. Check policy entry exists:
   ```bash
   ldapsearch -x -H ldap://localhost:391 \
     -D "cn=Manager,dc=test,dc=com" -w admin123 \
     -b "ou=Policies,dc=test,dc=com"
   ```
