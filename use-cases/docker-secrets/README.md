# Docker Secrets Use Case

This use-case demonstrates how to use Docker secrets to securely manage OpenLDAP passwords instead of passing them as plaintext environment variables.

## Overview

Docker secrets provide a secure way to manage sensitive data like passwords. With Docker secrets:
- Passwords are stored in encrypted files on the host
- Secrets are mounted as files in `/run/secrets/` inside the container
- The `startup.sh` script supports `_FILE` variants for password variables
- Passwords never appear in environment variables or process lists

## Files

```
.
├── docker-compose.yml      # Compose file with secrets configuration
├── secrets/
│   ├── admin_password.txt     # Admin password (add to .gitignore!)
│   └── config_password.txt    # Config DB password (add to .gitignore!)
├── logs/                   # Log output directory
└── README.md              # This file
```

## Quick Start

### 1. Create Secret Files

Create the password files (these are gitignored in production):

```bash
mkdir -p secrets
echo "YourSecureAdminPassword" > secrets/admin_password.txt
echo "YourSecureConfigPassword" > secrets/config_password.txt
```

**Important:** Add `secrets/*.txt` to `.gitignore` to avoid committing passwords!

### 2. Start OpenLDAP

```bash
docker-compose up -d
```

### 3. Verify Secrets Are Used

```bash
# Check that passwords are NOT in environment variables
docker exec openldap-secrets env | grep -i password
# Should show: LDAP_ADMIN_PASSWORD_FILE=/run/secrets/ldap_admin_password
# But NOT the actual password value

# Verify the secret file is mounted
docker exec openldap-secrets cat /run/secrets/ldap_admin_password
```

### 4. Test Authentication

```bash
# Get the admin password from the secret file
ADMIN_PASS=$(cat secrets/admin_password.txt)

# Test LDAP connection
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w "$ADMIN_PASS" \
  -b "dc=example,dc=com" \
  -s base
```

## How It Works

### Docker Compose Configuration

```yaml
services:
  openldap:
    environment:
      # Use _FILE to point to the secret file path
      - LDAP_ADMIN_PASSWORD_FILE=/run/secrets/ldap_admin_password
      - LDAP_CONFIG_PASSWORD_FILE=/run/secrets/ldap_config_password
    secrets:
      - ldap_admin_password
      - ldap_config_password

secrets:
  ldap_admin_password:
    file: ./secrets/admin_password.txt
  ldap_config_password:
    file: ./secrets/config_password.txt
```

### startup.sh Logic

The `startup.sh` script checks for `_FILE` variants:

```bash
if [ -n "$LDAP_ADMIN_PASSWORD_FILE" ] && [ -f "$LDAP_ADMIN_PASSWORD_FILE" ]; then
    LDAP_ADMIN_PASSWORD=$(cat "$LDAP_ADMIN_PASSWORD_FILE")
fi
```

This means:
1. If `LDAP_ADMIN_PASSWORD_FILE` is set and the file exists
2. Read the password from the file
3. Use it for OpenLDAP configuration

## Security Benefits

| Plaintext Env Var | Docker Secrets |
|-------------------|----------------|
| Visible in `docker inspect` | Hidden from container metadata |
| In process list (`ps e`) | Only in file readable by container |
| May be logged | Not logged by default |
| Committed to git risk | Can be gitignored |

## Production Recommendations

1. **Never commit secrets to git:**
   ```bash
   echo "secrets/*.txt" >> .gitignore
   ```

2. **Use proper secret management in production:**
   - Docker Swarm: `docker secret create`
   - Kubernetes: Sealed Secrets or External Secrets Operator
   - CI/CD: Inject secrets from vault at deploy time

3. **Rotate secrets regularly:**
   ```bash
   # Update secret file
   echo "NewSecurePassword" > secrets/admin_password.txt
   # Restart container to pick up new secret
   docker-compose restart
   ```

4. **Monitor secret access:**
   ```bash
   # Check who can read the secret files
   ls -la secrets/
   ```

## Troubleshooting

### Container fails to start

Check if secret files exist:
```bash
ls -la secrets/
```

### Permission denied on secrets

Ensure the secret files are readable:
```bash
chmod 600 secrets/*.txt
```

### Wrong password errors

Verify the password file has no trailing newlines (if your password shouldn't have them):
```bash
# Check for newlines
od -c secrets/admin_password.txt

# Write without newline
echo -n "password" > secrets/admin_password.txt
```
