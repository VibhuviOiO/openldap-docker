# OpenLDAP Docker

Production-ready OpenLDAP container with enterprise features.

## Features

### Core Features
- **Multi-master replication** - High availability with 3+ node clusters
- **TLS/SSL support** - Secure LDAP connections
- **Custom schema support** - Hot-load your own object classes
- **Database indices** - Optimized for performance (cn, uid, mail, sn, givenname, member, memberOf)
- **Query limits** - DoS protection (500 soft / 1000 hard limit)
- **Connection timeouts** - Auto-close idle connections (600s)

### Security Features
- **Non-root execution** - Runs as `ldap` user (UID 55)
- **Secure ACLs** - Password protection, authenticated access required
- **Health checks** - Built-in Docker health monitoring
- **Signal handling** - Graceful shutdown on SIGTERM/SIGINT

### Optional Overlays
- **memberOf** - Track group membership on user entries
- **ppolicy** - Password policies (min length, history, lockout)
- **auditlog** - Audit trail of all modifications

## Quick Start

### Single Container

```bash
# Run OpenLDAP with default settings
docker run -d \
  --name openldap \
  -e LDAP_DOMAIN=example.com \
  -e LDAP_ADMIN_PASSWORD=changeme \
  -p 389:389 \
  -v ldap-data:/var/lib/ldap \
  -v ldap-config:/etc/openldap/slapd.d \
  ghcr.io/vibhuvioio/openldap:latest

# Test connection
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w changeme \
  -b "dc=example,dc=com"
```

### Multi-Node Cluster

Run 3-node multi-master replication:

**Node 1:**
```bash
docker run -d \
  --name openldap-node1 \
  --hostname openldap-node1 \
  -e LDAP_DOMAIN=example.com \
  -e LDAP_ADMIN_PASSWORD=changeme \
  -e ENABLE_REPLICATION=true \
  -e SERVER_ID=1 \
  -e REPLICATION_PEERS=openldap-node2,openldap-node3 \
  -p 389:389 \
  -v ldap-data-node1:/var/lib/ldap \
  -v ldap-config-node1:/etc/openldap/slapd.d \
  --network ldap-network \
  ghcr.io/vibhuvioio/openldap:latest
```

**Node 2:**
```bash
docker run -d \
  --name openldap-node2 \
  --hostname openldap-node2 \
  -e LDAP_DOMAIN=example.com \
  -e LDAP_ADMIN_PASSWORD=changeme \
  -e ENABLE_REPLICATION=true \
  -e SERVER_ID=2 \
  -e REPLICATION_PEERS=openldap-node1,openldap-node3 \
  -p 390:389 \
  -v ldap-data-node2:/var/lib/ldap \
  -v ldap-config-node2:/etc/openldap/slapd.d \
  --network ldap-network \
  ghcr.io/vibhuvioio/openldap:latest
```

**Node 3:**
```bash
docker run -d \
  --name openldap-node3 \
  --hostname openldap-node3 \
  -e LDAP_DOMAIN=example.com \
  -e LDAP_ADMIN_PASSWORD=changeme \
  -e ENABLE_REPLICATION=true \
  -e SERVER_ID=3 \
  -e REPLICATION_PEERS=openldap-node1,openldap-node2 \
  -p 391:389 \
  -v ldap-data-node3:/var/lib/ldap \
  -v ldap-config-node3:/etc/openldap/slapd.d \
  --network ldap-network \
  ghcr.io/vibhuvioio/openldap:latest
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LDAP_DOMAIN` | `example.com` | LDAP domain |
| `LDAP_ADMIN_PASSWORD` | `admin` | Admin password |
| `LDAP_CONFIG_PASSWORD` | `config` | Config DB password |
| `ENABLE_REPLICATION` | `false` | Enable multi-master replication |
| `SERVER_ID` | `1` | Server ID (for replication) |
| `REPLICATION_PEERS` | - | Comma-separated peer hostnames |
| `ENABLE_MEMBEROF` | `false` | Enable memberOf overlay |
| `ENABLE_PASSWORD_POLICY` | `false` | Enable password policy |
| `ENABLE_AUDIT_LOG` | `false` | Enable audit logging |
| `LDAP_TLS_CERT` | - | Path to TLS certificate |
| `LDAP_TLS_KEY` | - | Path to TLS key |

### Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/ldap` | Database files |
| `/etc/openldap/slapd.d` | Configuration |
| `/logs` | Log output (slapd.log, audit.log) |
| `/custom-schema` | Custom LDIF schemas |
| `/docker-entrypoint-initdb.d` | Initialization scripts |

## Docker Compose

```yaml
version: '3.8'

services:
  openldap:
    image: ghcr.io/vibhuvioio/openldap:latest
    environment:
      - LDAP_DOMAIN=example.com
      - LDAP_ADMIN_PASSWORD=changeme
      - ENABLE_MEMBEROF=true
    ports:
      - "389:389"
    volumes:
      - ldap-data:/var/lib/ldap
      - ldap-config:/etc/openldap/slapd.d
      - ./logs:/logs

volumes:
  ldap-data:
  ldap-config:
```

## Kubernetes

See [LDAP Manager Documentation](https://vibhuvioio.com/ldap-manager/) for:
- Helm charts
- Kubernetes deployment guides
- Production best practices
- Monitoring and alerting

## Documentation

Full documentation available at:
- **LDAP Manager Docs**: https://vibhuvioio.com/ldap-manager/
- **Use Cases**: Available in [ldap-manager/use-cases/](https://github.com/your-org/ldap-manager/tree/main/use-cases)

## Overlays Guide

### Enable memberOf
```yaml
environment:
  - ENABLE_MEMBEROF=true
```
Allows queries like: `(memberOf=cn=admins,ou=Groups,dc=example,dc=com)`

### Enable Audit Logging
```yaml
environment:
  - ENABLE_AUDIT_LOG=true
volumes:
  - ./logs:/logs
```
View audit trail: `docker exec openldap cat /logs/audit.log`

### Enable Password Policy
```yaml
environment:
  - ENABLE_PASSWORD_POLICY=true
```
Enforces: min 8 chars, 5 history, lockout after 5 failures

## License

MIT License
