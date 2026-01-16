# Quick Reference Guide

## Common Commands

### Start/Stop

```bash
# Single Node
docker-compose -f docker-compose.single-node.yml up -d
docker-compose -f docker-compose.single-node.yml down

# Multi-Master
docker-compose -f docker-compose.multi-master.yml up -d
docker-compose -f docker-compose.multi-master.yml down

# Using Makefile
make up-single
make down-single
make up-multi
make down-multi
```

### View Logs

```bash
# Single Node
docker logs -f openldap-single

# Multi-Master
docker logs -f ldap-node1
docker logs -f ldap-node2
docker logs -f ldap-node3

# All nodes
docker-compose -f docker-compose.multi-master.yml logs -f
```

### LDAP Operations

#### Search
```bash
# Basic search
ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin

# Search specific user
ldapsearch -x -H ldap://localhost:389 \
  -b "dc=example,dc=com" \
  "(uid=john)"

# Search with filter
ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=example,dc=com" \
  "(objectClass=inetOrgPerson)"
```

#### Add Entry
```bash
ldapadd -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin <<EOF
dn: uid=john,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
uid: john
cn: John Doe
sn: Doe
mail: john@example.com
userPassword: password123
EOF
```

#### Modify Entry
```bash
ldapmodify -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin <<EOF
dn: uid=john,ou=People,dc=example,dc=com
changetype: modify
replace: mail
mail: newemail@example.com
EOF
```

#### Delete Entry
```bash
ldapdelete -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin \
  "uid=john,ou=People,dc=example,dc=com"
```

### Monitoring

#### Check Replication Status
```bash
docker exec ldap-node1 ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "cn=config" \
  "(olcSyncRepl=*)" | grep olcSyncRepl
```

#### Check Server ID
```bash
docker exec ldap-node1 ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "cn=config" \
  "(olcServerID=*)" | grep olcServerID
```

#### Check Loaded Schemas
```bash
docker exec openldap-single ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "cn=schema,cn=config" \
  "(objectClass=olcSchemaConfig)" | grep "^dn:"
```

#### Monitor Database Stats
```bash
ldapsearch -x -H ldap://localhost:389 \
  -b "cn=Monitor" \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin
```

### Backup & Restore

#### Backup
```bash
# Export data
docker exec openldap-single slapcat -n 2 > backup-$(date +%Y%m%d).ldif

# Backup volumes
docker run --rm -v ldap-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/ldap-data-backup.tar.gz /data
```

#### Restore
```bash
# Stop container
docker-compose -f docker-compose.single-node.yml down

# Restore data
docker run --rm -v ldap-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/ldap-data-backup.tar.gz -C /

# Start container
docker-compose -f docker-compose.single-node.yml up -d
```

### Troubleshooting

#### Access Container Shell
```bash
docker exec -it openldap-single bash
docker exec -it ldap-node1 bash
```

#### Check Configuration
```bash
docker exec openldap-single ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "cn=config" \
  "(objectClass=*)"
```

#### Test Connection
```bash
# Test LDAP connection
ldapsearch -x -H ldap://localhost:389 -b "" -s base

# Test authentication
ldapwhoami -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin
```

#### Reset Everything
```bash
# Remove all containers and volumes
docker-compose -f docker-compose.single-node.yml down -v
docker-compose -f docker-compose.multi-master.yml down -v

# Remove images
docker rmi $(docker images | grep openldap | awk '{print $3}')
```

### Environment Variables Quick Reference

```bash
# Required
LDAP_DOMAIN=example.com
LDAP_ORGANIZATION=Example Org
LDAP_ADMIN_PASSWORD=secret

# Optional
LDAP_CONFIG_PASSWORD=config
LDAP_LOG_LEVEL=256
INCLUDE_SCHEMAS=cosine,inetorgperson,nis

# Replication
ENABLE_REPLICATION=true
SERVER_ID=1
REPLICATION_PEERS=node2,node3
```

### Port Mapping

| Service | LDAP Port | LDAPS Port |
|---------|-----------|------------|
| Single Node | 389 | 636 |
| Multi Node 1 | 389 | 636 |
| Multi Node 2 | 390 | 637 |
| Multi Node 3 | 391 | 638 |

### File Locations

| Purpose | Container Path | Host Mount |
|---------|---------------|------------|
| Data | /var/lib/ldap | ldap-data volume |
| Config | /etc/openldap/slapd.d | ldap-config volume |
| Logs | /logs | ldap-logs volume |
| Custom Schema | /custom-schema | ./custom-schema |

### Testing

```bash
# Run test suite
./test.sh single    # Test single node
./test.sh multi     # Test multi-master

# Manual replication test
# 1. Add entry to node 1
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=example,dc=com" -w admin <<EOF
dn: uid=test,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
uid: test
cn: Test
sn: User
EOF

# 2. Check on node 2
ldapsearch -x -H ldap://localhost:390 -b "dc=example,dc=com" "(uid=test)"

# 3. Check on node 3
ldapsearch -x -H ldap://localhost:391 -b "dc=example,dc=com" "(uid=test)"
```

### Performance Tuning

```bash
# Increase log level for debugging
LDAP_LOG_LEVEL=stats  # or 256, 512, etc.

# Check database cache
docker exec openldap-single ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "olcDatabase={2}mdb,cn=config" \
  "(objectClass=*)" | grep olcDbMaxSize
```

### Security

```bash
# Change admin password
ldappasswd -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w oldpassword \
  -s newpassword \
  "cn=Manager,dc=example,dc=com"

# Add user with password
ldapadd -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w admin <<EOF
dn: uid=user1,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
uid: user1
cn: User One
sn: One
userPassword: $(slappasswd -s userpass)
EOF
```
