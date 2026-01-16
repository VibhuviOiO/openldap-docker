# OpenLDAP Docker with Web UI

Production-ready OpenLDAP deployment with Docker and modern web management interface.

## Features

### OpenLDAP Server
- **AlmaLinux 9** base image
- **Single-node** and **Multi-master** (3-node) replication support
- **Custom schema** support with hot-loading
- **Activity logging** with automatic rotation
- **Monitoring** via cn=Monitor backend
- **Environment-driven** configuration (idempotent startup)
- **TLS/SSL** ready

### Web Management UI
- **React + TypeScript** frontend with shadcn/ui components
- **FastAPI** Python backend
- **Multi-cluster** management from single interface
- **Server-side pagination** (LDAP Simple Paged Results)
- **Server-side search** with LDAP filters
- **Password caching** for shared cluster access
- **Auto-discovery** of base DN
- **Real-time monitoring** and health checks
- **Activity log** viewing with search examples

## Quick Start

### Single Node Deployment

```bash
cd oio/docker-openldap
docker-compose -f docker-compose.single-node.yml up -d
```

Access LDAP at `ldap://localhost:389`

### Multi-Master Deployment

```bash
cd oio/docker-openldap
docker-compose -f docker-compose.multi-master.yml up -d
```

Three nodes: `ldap://localhost:389`, `ldap://localhost:390`, `ldap://localhost:391`

### Web UI

```bash
cd oio/docker-openldap/web
docker-compose up -d
```

Access UI at `http://localhost:5173`

## Configuration

### Environment Variables

```bash
LDAP_DOMAIN=example.com
LDAP_ORGANIZATION=Example Organization
LDAP_ADMIN_PASSWORD=admin123
LDAP_CONFIG_PASSWORD=config123
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

### Web UI Configuration

Edit `web/config.yml`:

```yaml
clusters:
  - name: "Production LDAP"
    host: "ldap.example.com"
    port: 389
    bind_dn: "cn=Manager,dc=example,dc=com"
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

## Architecture

### Directory Structure
```
oio/docker-openldap/
├── Dockerfile              # AlmaLinux 9 + OpenLDAP
├── startup.sh              # Idempotent configuration script
├── docker-compose.*.yml    # Deployment configurations
├── custom-schema/          # Custom LDAP schemas
├── logs/                   # Activity logs (bind-mounted)
├── web/                    # Management UI
│   ├── frontend/          # React + TypeScript
│   ├── backend/           # FastAPI Python
│   └── config.yml         # Cluster configurations
├── docs/                   # Documentation
└── use-cases/             # Complete deployment examples
```

### Data Flow
1. **Frontend** → Axios → **Backend API**
2. **Backend** → python-ldap → **OpenLDAP Server**
3. **LDAP** → Server-side filtering/pagination → **Results**

## Features Deep Dive

### Server-Side Pagination
- Uses LDAP Simple Paged Results Control (RFC 2696)
- Configurable page size (default: 10 entries)
- Reduces memory usage for large directories
- No client-side filtering overhead

### Server-Side Search
- LDAP filter: `(|(uid=*query*)(cn=*query*)(mail=*query*)(sn=*query*))`
- Searches across username, name, email, surname
- Combined with type filters (users/groups/OUs)
- Efficient LDAP-native search

### Activity Logging
- Logs redirected to `/logs/slapd.log`
- Date-based rotation with logrotate
- Bind-mounted to host for direct access
- Compressed archives: `slapd.log-YYYY-MM-DD.gz`

### Monitoring
- cn=Monitor backend (EXTERNAL auth only)
- Health status checks via API
- Connection and operation metrics
- Response time tracking

## API Endpoints

### Entries
- `GET /api/entries/search?cluster=<name>&page=1&page_size=10&search=<query>&filter_type=users`

### Monitoring
- `GET /api/monitoring/health?cluster=<name>`

### Connection
- `POST /api/connection/test` - Test LDAP connection
- `POST /api/connection/connect` - Connect and cache password

### Password Cache
- `GET /api/password/check?cluster=<name>&bind_dn=<dn>`

## Documentation

- [Activity Logs](docs/ACTIVITY_LOGS.md) - Log management and rotation
- [Activity Log Reference](docs/ACTIVITY_LOG_REFERENCE.md) - Log format and commands
- [Monitoring](docs/MONITORING.md) - cn=Monitor configuration

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
- Password cache uses SHA256 hashing
- Bind DN passwords stored in memory only

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
