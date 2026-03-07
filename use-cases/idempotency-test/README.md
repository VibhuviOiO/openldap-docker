# Idempotency and Data Persistence Test

Verifies that restarting the OpenLDAP container:
1. **Doesn't error** on second initialization (idempotent config)
2. **Preserves data** across restarts (data persistence)
3. **Doesn't create duplicates** (proper existence checks)

## What This Tests

| Test | Description |
|------|-------------|
| **Idempotency** | Configuration scripts check for existing entries before creating |
| **Data Persistence** | Database files survive container restart |
| **No Duplicates** | Re-running init doesn't create duplicate entries |

## Quick Start

```bash
cd use-cases/idempotency-test

# First start - creates test data
docker-compose up -d

# Wait for initialization
docker logs -f openldap-idempotency
# Look for: "Phase 1 initialization complete"

# Note the entry count from logs, then restart
docker-compose restart

# Check logs - should show "Database already configured" (no errors)
docker logs openldap-idempotency | grep -E "(already|configured|error|Error)"

# Verify data persistence
docker exec openldap-idempotency ldapsearch -x \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "dc=example,dc=com" \
  "(objectClass=*)" | grep -c "^dn:"
# Should match the initial count
```

## Manual Verification

```bash
# 1. Create data and note entry count
docker exec openldap-idempotency ldapsearch -x \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "dc=example,dc=com" \
  "(objectClass=*)" | grep "^dn:"

# 2. Restart container
docker-compose restart

# 3. Check for errors in logs
docker logs openldap-idempotency 2>&1 | grep -i error
# Should show no errors

# 4. Verify data still exists
docker exec openldap-idempotency ldapsearch -x \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "uid=testuser,ou=TestUsers,dc=example,dc=com" \
  "(objectClass=*)"

# 5. Verify no duplicates (same count as before)
docker exec openldap-idempotency ldapsearch -x \
  -D "cn=Manager,dc=example,dc=com" \
  -w "AdminPass123!" \
  -b "dc=example,dc=com" \
  "(objectClass=*)" | grep -c "^dn:"
```

## Expected Behavior

### First Start
```
Configuring OpenLDAP
Setting config password...
Configuring database...
Database ACL configured
...
Phase 1 initialization complete
```

### Second Start (Restart)
```
Database already configured
Base domain already exists
...
OpenLDAP initialization completed
```

**No errors should appear!**

## How Idempotency Works

The `startup.sh` script checks before each configuration step:

```bash
# Check if database is already configured
if is_database_configured "$LDAP_BASE_DN"; then
    log_info "Database already configured"
else
    # ... configure database
fi

# Check if base domain exists
if is_base_domain_exists "$LDAP_BASE_DN" "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD"; then
    log_info "Base domain already exists"
else
    # ... create base domain
fi
```

This ensures the container can be restarted safely.

## Troubleshooting

### "Entry already exists" errors

If you see errors like:
```
ldap_add: Already exists (68)
```

This indicates an idempotency bug. The init script should check for existence first.

### Data lost after restart

Check that volumes are properly mounted:
```bash
docker volume ls | grep idempotency
```

Verify the volume contains data:
```bash
docker run --rm -v idempotency-test_ldap-data:/data alpine ls -la /data
```
