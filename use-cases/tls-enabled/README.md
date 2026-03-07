# TLS-Enabled Use-Case

Tests TLS/SSL connectivity with StartTLS and LDAPS.

## Features Tested

| Feature | Validation |
|---------|-----------|
| **StartTLS** | `ldapsearch -ZZ` upgrade from plaintext to TLS |
| **LDAPS** | Direct SSL connection on port 636 |
| **Certificate loading** | Server starts with provided certs |

## Quick Start

```bash
cd use-cases/tls-enabled

# TLS certificates are pre-generated (self-signed for testing)
# In production, use proper certificates from your CA

# Start OpenLDAP with TLS
docker-compose up -d

# Wait for initialization
docker logs -f openldap-tls
```

## Testing TLS

### Test 1: StartTLS (recommended)

```bash
# Search using StartTLS (upgrades connection to TLS)
ldapsearch -x -H ldap://localhost:389 -ZZ \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "dc=example,dc=com" \
  -s base

# -ZZ: Require TLS (fail if not available)
# -Z:  Use TLS if available (don't fail if not)
```

### Test 2: LDAPS (SSL)

```bash
# Direct SSL connection (note: ldaps:// URI and port 636)
LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://localhost:636 \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "dc=example,dc=com" \
  -s base

# LDAPTLS_REQCERT=never: Skip cert validation (for self-signed testing only!)
```

### Test 3: Verify TLS is Required

```bash
# This should FAIL if TLS is required (it is by default after configuration)
ldapwhoami -x -H ldap://localhost:389
# Expected: anonymous bind may still work, but operations may require TLS
```

## Certificate Management

### Self-Signed (Testing Only)

Pre-generated certificates are included for testing:
```
certs/
├── ldap.crt  # Certificate
└── ldap.key  # Private key
```

### Production Certificates

Replace with proper certificates:

```yaml
volumes:
  - /path/to/your/cert.pem:/certs/ldap.crt:ro
  - /path/to/your/key.pem:/certs/ldap.key:ro
```

### Generate New Self-Signed Certs

```bash
cd use-cases/tls-enabled

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/ldap.key \
  -out certs/ldap.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=openldap.example.com"
```

## Troubleshooting

### "Can't contact LDAP server"

Check if slapd started correctly:
```bash
docker logs openldap-tls | grep -i tls
```

### "Connect error"

Verify certificates are readable:
```bash
docker exec openldap-tls ls -la /certs/
```

### Certificate verification failed

For self-signed certs, use:
```bash
# Skip verification (testing only!)
LDAPTLS_REQCERT=never ldapsearch ...

# Or trust the specific cert
LDAPTLS_CACERT=./certs/ldap.crt ldapsearch ...
```

## Security Notes

- Self-signed certificates are for **testing only**
- In production, use certificates from a trusted CA
- Consider using cert-manager in Kubernetes environments
- Client certificate authentication can be added for additional security
