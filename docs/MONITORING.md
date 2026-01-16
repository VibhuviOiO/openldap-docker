# Enabling LDAP Monitoring (cn=Monitor)

## Overview
OpenLDAP's `cn=Monitor` backend provides real-time statistics about server operations, connections, and performance. This is required for the Activity Log feature in the LDAP Manager UI.

## Enabling Monitoring in Docker Deployment

### Option 1: Environment Variable (Recommended)
Set `ENABLE_MONITORING=true` in your environment file:

**Single Node** (`.env.single-node`):
```bash
LDAP_DOMAIN=example.com
LDAP_ORGANIZATION=Example Organization
LDAP_ADMIN_PASSWORD=admin
ENABLE_MONITORING=true
```

**Multi-Master** (`.env.multi-master-node1`, `.env.multi-master-node2`, `.env.multi-master-node3`):
```bash
LDAP_DOMAIN=example.com
LDAP_ORGANIZATION=Example Organization
LDAP_ADMIN_PASSWORD=admin
ENABLE_REPLICATION=true
ENABLE_MONITORING=true
SERVER_ID=1
REPLICATION_PEERS=ldap-node2,ldap-node3
```

### Option 2: Docker Compose Override
Add to `docker-compose.single-node.yml` or `docker-compose.multi-master.yml`:

```yaml
services:
  openldap-single:
    environment:
      - ENABLE_MONITORING=true
```

## Manual Configuration (Existing LDAP Server)

If you have an existing LDAP server without monitoring enabled:

### Step 1: Enable cn=Monitor Access for Manager DN

```bash
ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=example,dc=com" read by * none
EOF
```

**Note**: Replace `dc=example,dc=com` with your actual base DN.

### Step 2: Verify Access

Test that the Manager DN can access cn=Monitor:

```bash
ldapsearch -x -D "cn=Manager,dc=example,dc=com" -w admin \
  -b "cn=Monitor" "(objectClass=*)" dn
```

You should see output like:
```
dn: cn=Monitor
dn: cn=Backends,cn=Monitor
dn: cn=Connections,cn=Monitor
dn: cn=Operations,cn=Monitor
...
```

### Step 3: Query Operation Statistics

```bash
# Get total operations
ldapsearch -x -D "cn=Manager,dc=example,dc=com" -w admin \
  -b "cn=Operations,cn=Monitor" "(objectClass=*)" monitorOpCompleted

# Get connection count
ldapsearch -x -D "cn=Manager,dc=example,dc=com" -w admin \
  -b "cn=Connections,cn=Monitor" "(objectClass=*)" monitorCounter
```

## What cn=Monitor Provides

The Activity Log in LDAP Manager UI shows:
- **BIND operations**: Authentication attempts
- **SEARCH operations**: Directory queries
- **MODIFY operations**: Entry modifications
- **ADD operations**: New entry additions
- **DELETE operations**: Entry deletions
- **Connection statistics**: Total connections

## Troubleshooting

### "No such object (32)" Error
This means cn=Monitor is not accessible. Check:
1. `ENABLE_MONITORING=true` is set in environment
2. Container was restarted after changing the setting
3. ACL allows Manager DN to read cn=Monitor

### "Insufficient access" Error
The Manager DN doesn't have permission. Run the manual configuration Step 1.

### No Statistics Showing
cn=Monitor shows cumulative statistics since server start. If the server just started, counts will be low.

## Security Considerations

- cn=Monitor exposes server internals and should only be accessible to administrators
- The default ACL allows only the Manager DN and root (via EXTERNAL auth) to read cn=Monitor
- For production, consider using a dedicated monitoring user with read-only access

## Disabling Monitoring

To disable monitoring:
```bash
ENABLE_MONITORING=false
```

Or remove the environment variable (defaults to `true`).

## References

- [OpenLDAP Admin Guide - Monitoring](https://www.openldap.org/doc/admin24/monitoringslapd.html)
- [cn=Monitor Schema](https://www.openldap.org/software/man.cgi?query=slapd-monitor)
