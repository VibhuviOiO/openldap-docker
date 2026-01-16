# OpenLDAP Docker Deployment

Generic OpenLDAP dockerization with AlmaLinux 9 supporting both Single Node and Multi-Master configurations.

## Features

- ✅ AlmaLinux 9 base image with OpenLDAP
- ✅ Environment variable-driven configuration
- ✅ Single Node deployment
- ✅ Multi-Master (Mirror Mode) replication
- ✅ Custom schema support
- ✅ Automatic initialization
- ✅ Persistent data volumes
- ✅ Monitoring enabled

## Quick Start

### Single Node Deployment

1. **Configure environment variables:**
   ```bash
   cp .env.single-node .env
   # Edit .env with your settings
   ```

2. **Add custom schemas (optional):**
   ```bash
   cp /path/to/your/schema.ldif custom-schema/
   ```

3. **Start the container:**
   ```bash
   docker-compose -f docker-compose.single-node.yml up -d
   ```

4. **Verify:**
   ```bash
   ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" -D "cn=Manager,dc=example,dc=com" -w admin
   ```

### Multi-Master Deployment

1. **Configure environment for each node:**
   ```bash
   # Review and update each node's configuration
   vim .env.multi-master-node1
   vim .env.multi-master-node2
   vim .env.multi-master-node3
   ```

2. **Add custom schemas (optional):**
   ```bash
   cp /path/to/your/schema.ldif custom-schema/
   ```

3. **Start the cluster:**
   ```bash
   docker-compose -f docker-compose.multi-master.yml up -d
   ```

4. **Verify replication:**
   ```bash
   # Add entry to node1
   ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=example,dc=com" -w admin <<EOF
   dn: uid=testuser,ou=People,dc=example,dc=com
   objectClass: inetOrgPerson
   uid: testuser
   cn: Test User
   sn: User
   EOF

   # Check on node2 (port 390)
   ldapsearch -x -H ldap://localhost:390 -b "dc=example,dc=com" "(uid=testuser)"
   ```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `LDAP_DOMAIN` | LDAP domain (e.g., example.com) | example.com | Yes |
| `LDAP_ORGANIZATION` | Organization name | Example Organization | Yes |
| `LDAP_ADMIN_PASSWORD` | Admin password | admin | Yes |
| `LDAP_CONFIG_PASSWORD` | Config database password | config | Yes |
| `LDAP_LOG_LEVEL` | Logging level | 256 | No |
| `INCLUDE_SCHEMAS` | Comma-separated default schemas | cosine,inetorgperson,nis | No |
| `ENABLE_REPLICATION` | Enable multi-master replication | false | No |
| `SERVER_ID` | Unique server ID (1-999) | 1 | Yes (if replication) |
| `REPLICATION_PEERS` | Comma-separated peer hostnames | - | Yes (if replication) |
| `REPLICATION_RIDS` | Comma-separated RIDs for peers | Auto (101+) | No |

### Custom Schemas

Place your custom LDIF schema files in the `custom-schema/` directory. They will be automatically loaded during initialization.

Example:
```bash
custom-schema/
├── RR.ldif
├── MyCustom.ldif
└── AnotherSchema.ldif
```

### Ports

**Single Node:**
- 389: LDAP
- 636: LDAPS (if configured)

**Multi-Master:**
- Node 1: 389, 636
- Node 2: 390, 637
- Node 3: 391, 638

## Directory Structure

```
oio/docker-openldap/
├── Dockerfile                          # Main Dockerfile
├── startup.sh                          # Initialization script
├── docker-compose.single-node.yml      # Single node compose
├── docker-compose.multi-master.yml     # Multi-master compose
├── .env.single-node                    # Single node env template
├── .env.multi-master-node1             # Node 1 env template
├── .env.multi-master-node2             # Node 2 env template
├── .env.multi-master-node3             # Node 3 env template
├── custom-schema/                      # Custom LDIF schemas
│   └── RR.ldif                        # Example custom schema
├── config-templates/                   # Config templates (future use)
└── README.md                          # This file
```

## Usage Examples

### Example 1: Company-Specific Configuration (vibhuvioio)

```bash
# .env
LDAP_DOMAIN=vibhuvioio.com
LDAP_ORGANIZATION=vibhuvioio
LDAP_ADMIN_PASSWORD=3bigeggs
LDAP_CONFIG_PASSWORD=configpass
INCLUDE_SCHEMAS=cosine,inetorgperson,nis

# Copy RR schema
cp ../../rr/custom-schema/RR.ldif custom-schema/

# Start
docker-compose -f docker-compose.single-node.yml up -d
```

### Example 2: Multi-Master with Custom Domain

```bash
# Update all three .env.multi-master-node* files:
LDAP_DOMAIN=mycompany.com
LDAP_ORGANIZATION=My Company
LDAP_ADMIN_PASSWORD=securepass123
REPLICATION_PEERS=ldap-node1,ldap-node2,ldap-node3

# Start cluster
docker-compose -f docker-compose.multi-master.yml up -d
```

### Example 3: Adding Data

```bash
# Create user
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=example,dc=com" -w admin <<EOF
dn: uid=john,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
uid: john
cn: John Doe
sn: Doe
mail: john@example.com
userPassword: password123
EOF

# Search
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" "(uid=john)"
```

## Monitoring

Check logs:
```bash
# Single node
docker logs openldap-single

# Multi-master
docker logs ldap-node1
docker logs ldap-node2
docker logs ldap-node3
```

Monitor replication status:
```bash
ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcSyncRepl=*)"
```

## Troubleshooting

### Container won't start
```bash
docker logs <container-name>
docker exec -it <container-name> bash
```

### Replication not working
1. Check network connectivity between nodes
2. Verify REPLICATION_PEERS hostnames are correct
3. Check credentials match across all nodes
4. Review logs for sync errors

### Schema not loading
1. Verify LDIF syntax
2. Check file permissions
3. Ensure schema name is unique
4. Review startup logs

## Migration from Existing Setup

To migrate from the `rr/config/` setup:

1. Copy custom schema:
   ```bash
   cp ../../rr/custom-schema/RR.ldif custom-schema/
   ```

2. Update environment variables to match your domain:
   ```bash
   LDAP_DOMAIN=vibhuvioio.com
   LDAP_ORGANIZATION=vibhuvioio
   LDAP_ADMIN_PASSWORD=<your-password>
   ```

3. For multi-master, set appropriate SERVER_ID and REPLICATION_PEERS

4. Start and verify

## Building Custom Image

```bash
docker build -t my-openldap:latest .
```

## Backup and Restore

### Backup
```bash
docker exec openldap-single slapcat -n 2 > backup.ldif
```

### Restore
```bash
docker exec -i openldap-single slapadd -n 2 < backup.ldif
```

## Security Recommendations

1. Change default passwords
2. Use strong passwords
3. Enable TLS/SSL for production
4. Restrict network access
5. Regular backups
6. Monitor access logs

## License

Internal use only.
