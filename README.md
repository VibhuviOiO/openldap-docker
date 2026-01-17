# OpenLDAP Docker

Production-ready OpenLDAP deployment with Docker supporting single-node and multi-master replication.

## Features

- **AlmaLinux 9** base image
- **Single-node** and **Multi-master** (3-node) replication support
- **Custom schema** support with hot-loading
- **Activity logging** with automatic rotation
- **Monitoring** via cn=Monitor backend
- **Environment-driven** configuration (idempotent startup)
- **TLS/SSL** ready

## Quick Start

### Single Node Deployment

```bash
cp .env.example .env
# Edit .env with your configuration
docker-compose -f docker-compose.single-node.yml up -d
```

Access LDAP at `ldap://localhost:389`

### Multi-Master Deployment

```bash
docker-compose -f docker-compose.multi-master.yml up -d
```

Three nodes: `ldap://localhost:389`, `ldap://localhost:390`, `ldap://localhost:391`

## Configuration

### Environment Variables

```bash
LDAP_DOMAIN=example.com
LDAP_ORGANIZATION=Example Organization
LDAP_ADMIN_PASSWORD=changeme
LDAP_CONFIG_PASSWORD=changeme
ENABLE_REPLICATION=false
ENABLE_MONITORING=true
SERVER_ID=1
INCLUDE_SCHEMAS=cosine,inetorgperson,nis
```

### Custom Schemas

Place `.ldif` schema files in `./custom-schema/` directory:

```bash
./custom-schema/
  └── MyCustomSchema.ldif
```

Schemas are automatically loaded on container startup.

## Management Options

### Command Line Tools
Use standard LDAP utilities:
```bash
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" -D "cn=Manager,dc=example,dc=com" -w changeme
ldapadd -x -D "cn=Manager,dc=example,dc=com" -w changeme -f data.ldif
ldapmodify -x -D "cn=Manager,dc=example,dc=com" -w changeme -f changes.ldif
```

### GUI Clients
- **Apache Directory Studio** - Eclipse-based LDAP browser
- **phpLDAPadmin** - Web-based PHP interface
- **JXplorer** - Java LDAP browser

### Modern Web UI (Recommended)
For a modern React-based management interface:

**[LDAP Manager](https://github.com/your-org/ldap-manager)** - Standalone web UI with:
- Multi-cluster management
- Server-side pagination and search
- Custom schema support
- Real-time monitoring
- Password caching

```bash
# Quick start with LDAP Manager
git clone https://github.com/your-org/ldap-manager.git
cd ldap-manager
cp config.example.yml config.yml
# Edit config.yml to point to your OpenLDAP server
docker-compose up -d
# Access at http://localhost:5173
```

## Use Cases

Complete standalone deployments in `use-cases/` directory:

### Vibhuvioio.com Example
```bash
cd use-cases/vibhuvioio-com-singlenode
docker-compose up -d
```

Includes:
- Custom MahabharataCharacter schema
- 14 sample users (11 custom + 2 legacy + 1 standard)
- 6 groups with various patterns
- 5 organizational units
- NIS map objects

## Activity Logging

- Logs redirected to `/logs/slapd.log`
- Date-based rotation with logrotate
- Bind-mounted to host for direct access
- Compressed archives: `slapd.log-YYYY-MM-DD.gz`

See [Activity Logs Documentation](docs/ACTIVITY_LOGS.md)

## Monitoring

- cn=Monitor backend (EXTERNAL auth only)
- Health status checks
- Connection and operation metrics

See [Monitoring Documentation](docs/MONITORING.md)

## Complex LDAP Patterns Supported

- ✅ Multiple organizational units
- ✅ Custom objectClass schemas
- ✅ Legacy Unix accounts (account without inetOrgPerson)
- ✅ Standard inetOrgPerson entries
- ✅ groupOfNames, groupOfUniqueNames, posixGroup
- ✅ Groups with empty member attributes
- ✅ nisMap objects
- ✅ Multi-value attributes
- ✅ Custom schema inheritance

## Requirements

- Docker 20.10+
- Docker Compose 2.0+
- 2GB RAM minimum
- 10GB disk space

## Security Notes

- Change default passwords in production
- Use TLS/SSL for production deployments
- Restrict network access to LDAP ports
- Regular password rotation

## Documentation

- [Setup Guide](SETUP.md)
- [Activity Logs](docs/ACTIVITY_LOGS.md)
- [Activity Log Reference](docs/ACTIVITY_LOG_REFERENCE.md)
- [Monitoring](docs/MONITORING.md)

## License

MIT License - See LICENSE file

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## Support

For issues and questions, please open a GitHub issue.
