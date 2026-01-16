# OpenLDAP Docker Deployment - Summary

## Overview

This is a production-ready OpenLDAP dockerization solution built on AlmaLinux 9, supporting both single-node and multi-master (mirror mode) deployments with environment-variable driven configuration.

## Key Features

✅ **AlmaLinux 9 Base** - Enterprise-grade Linux distribution  
✅ **Environment-Driven** - No manual LDIF editing required  
✅ **Single Node Support** - Simple standalone deployment  
✅ **Multi-Master Support** - 3-node mirror mode replication  
✅ **Custom Schemas** - Automatic loading from directory  
✅ **Auto-Initialization** - Database setup on first run  
✅ **Persistent Storage** - Docker volumes for data/config  
✅ **Monitoring Ready** - Stats and monitoring enabled  
✅ **Generic & Reusable** - Works for any organization  

## Architecture

### Single Node
```
┌─────────────────────────┐
│   OpenLDAP Container    │
│   - AlmaLinux 9         │
│   - OpenLDAP Server     │
│   - Port 389/636        │
└─────────────────────────┘
         │
         ├─ Volume: ldap-data
         ├─ Volume: ldap-config
         └─ Volume: ldap-logs
```

### Multi-Master (3 Nodes)
```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Node 1     │────▶│   Node 2     │────▶│   Node 3     │
│  Server ID:1 │◀────│  Server ID:2 │◀────│  Server ID:3 │
│  Port: 389   │     │  Port: 390   │     │  Port: 391   │
└──────────────┘     └──────────────┘     └──────────────┘
       ▲                    ▲                    ▲
       └────────────────────┴────────────────────┘
              Bidirectional Replication
```

## File Structure

```
oio/docker-openldap/
├── Dockerfile                          # AlmaLinux 9 + OpenLDAP
├── startup.sh                          # Initialization script
├── docker-compose.single-node.yml      # Single node deployment
├── docker-compose.multi-master.yml     # Multi-master deployment
├── .env.single-node                    # Single node config template
├── .env.multi-master-node1             # Node 1 config template
├── .env.multi-master-node2             # Node 2 config template
├── .env.multi-master-node3             # Node 3 config template
├── custom-schema/                      # Custom LDIF schemas
│   └── RR.ldif                        # Example: RR custom schema
├── config-templates/                   # Future: config templates
├── Makefile                           # Management commands
├── test.sh                            # Test suite
├── README.md                          # Main documentation
├── MIGRATION_FROM_RR.md               # RR migration guide
├── QUICK_REFERENCE.md                 # Command reference
└── .gitignore                         # Git ignore rules
```

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `LDAP_DOMAIN` | LDAP domain | `example.com` |
| `LDAP_ORGANIZATION` | Organization name | `Example Org` |
| `LDAP_ADMIN_PASSWORD` | Admin password | `secret123` |
| `LDAP_CONFIG_PASSWORD` | Config DB password | `config123` |
| `LDAP_LOG_LEVEL` | Logging level | `256` |
| `INCLUDE_SCHEMAS` | Default schemas (comma-separated) | `cosine,inetorgperson,nis` |
| `ENABLE_REPLICATION` | Enable multi-master | `true` or `false` |
| `SERVER_ID` | Unique server ID | `1`, `2`, `3` |
| `REPLICATION_PEERS` | Peer hostnames (comma-separated) | `node2,node3` |

### How It Works

1. **Domain to Base DN**: `example.com` → `dc=example,dc=com`
2. **Admin DN**: Auto-generated as `cn=Manager,dc=example,dc=com`
3. **Password Hashing**: Automatic SSHA hashing
4. **Base Structure**: Auto-creates `ou=People` and `ou=Group`
5. **Schemas**: Loads from `/custom-schema/*.ldif`
6. **Replication**: Configures syncrepl based on `REPLICATION_PEERS`

## Quick Start

### Single Node
```bash
cd oio/docker-openldap
cp .env.single-node .env
# Edit .env with your settings
docker-compose -f docker-compose.single-node.yml up -d
```

### Multi-Master
```bash
cd oio/docker-openldap
# Edit .env.multi-master-node* files
docker-compose -f docker-compose.multi-master.yml up -d
```

### Test
```bash
./test.sh single    # Test single node
./test.sh multi     # Test multi-master
```

## Migration from RR Configuration

The solution is designed to replace manual LDIF configuration:

| Old Approach | New Approach |
|--------------|--------------|
| Manual LDIF files in `rr/config/` | Environment variables |
| Hard-coded domain/passwords | Configurable via `.env` |
| Manual replication setup | Automatic via `ENABLE_REPLICATION` |
| Manual schema loading | Auto-load from `custom-schema/` |

See `MIGRATION_FROM_RR.md` for detailed migration steps.

## Use Cases

### 1. Development Environment
```bash
LDAP_DOMAIN=dev.example.com
LDAP_ADMIN_PASSWORD=devpass
ENABLE_REPLICATION=false
```

### 2. Production Single Node
```bash
LDAP_DOMAIN=prod.example.com
LDAP_ADMIN_PASSWORD=<strong-password>
ENABLE_REPLICATION=false
INCLUDE_SCHEMAS=cosine,inetorgperson,nis
```

### 3. Production Multi-Master
```bash
# Node 1
LDAP_DOMAIN=prod.example.com
ENABLE_REPLICATION=true
SERVER_ID=1
REPLICATION_PEERS=ldap-node2,ldap-node3

# Node 2
SERVER_ID=2
REPLICATION_PEERS=ldap-node1,ldap-node3

# Node 3
SERVER_ID=3
REPLICATION_PEERS=ldap-node1,ldap-node2
```

## Advantages

### Over Manual Setup
- ✅ No LDIF editing
- ✅ Consistent configuration
- ✅ Easy to replicate
- ✅ Version controlled
- ✅ Environment-specific configs

### Over Other Docker Solutions
- ✅ AlmaLinux 9 (enterprise-grade)
- ✅ Generic and customizable
- ✅ Multi-master support
- ✅ Custom schema support
- ✅ Production-ready

## Testing

### Automated Tests
```bash
./test.sh single    # Tests connection, schema, structure
./test.sh multi     # Tests replication across nodes
```

### Manual Tests
```bash
# Connection test
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" \
  -D "cn=Manager,dc=example,dc=com" -w admin

# Add test user
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=example,dc=com" -w admin <<EOF
dn: uid=test,ou=People,dc=example,dc=com
objectClass: inetOrgPerson
uid: test
cn: Test User
sn: User
EOF

# Verify replication (multi-master)
ldapsearch -x -H ldap://localhost:390 -b "dc=example,dc=com" "(uid=test)"
```

## Monitoring

### Logs
```bash
docker logs -f openldap-single
docker logs -f ldap-node1
```

### Replication Status
```bash
docker exec ldap-node1 ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b "cn=config" "(olcSyncRepl=*)"
```

### Database Stats
```bash
ldapsearch -x -H ldap://localhost:389 -b "cn=Monitor" \
  -D "cn=Manager,dc=example,dc=com" -w admin
```

## Backup & Restore

### Backup
```bash
docker exec openldap-single slapcat -n 2 > backup.ldif
```

### Restore
```bash
docker-compose down
docker run --rm -v ldap-data:/var/lib/ldap -v $(pwd):/backup \
  almalinux:9 slapadd -n 2 -l /backup/backup.ldif
docker-compose up -d
```

## Security Considerations

1. **Change Default Passwords** - Never use default passwords in production
2. **Use Strong Passwords** - Minimum 12 characters, mixed case, numbers, symbols
3. **Enable TLS/SSL** - For production deployments
4. **Network Isolation** - Use Docker networks
5. **Regular Backups** - Automated backup schedule
6. **Access Control** - Restrict who can access LDAP ports
7. **Monitor Logs** - Regular log review for suspicious activity

## Troubleshooting

### Container Won't Start
```bash
docker logs <container-name>
docker exec -it <container-name> bash
```

### Replication Issues
- Check network connectivity between nodes
- Verify `REPLICATION_PEERS` hostnames
- Ensure passwords match across nodes
- Review logs for sync errors

### Schema Not Loading
- Verify `.ldif` file syntax
- Check file is in `custom-schema/`
- Ensure unique schema name
- Review startup logs

## Performance Tuning

- Adjust `LDAP_LOG_LEVEL` (lower = less logging)
- Increase database cache size
- Use indexes for frequently searched attributes
- Monitor resource usage

## Future Enhancements

- [ ] TLS/SSL support
- [ ] Health check endpoints
- [ ] Prometheus metrics exporter
- [ ] Automated backup scripts
- [ ] Kubernetes deployment manifests
- [ ] Additional replication modes

## Support

- **Documentation**: See `README.md`, `QUICK_REFERENCE.md`
- **Migration**: See `MIGRATION_FROM_RR.md`
- **Testing**: Run `./test.sh`
- **Issues**: Check logs and troubleshooting section

## License

Internal use only.

---

**Created**: 2024  
**Version**: 1.0  
**Base Image**: AlmaLinux 9  
**OpenLDAP Version**: System default from AlmaLinux repos
