# OpenLDAP Docker

[![GitHub Stars](https://img.shields.io/github/stars/VibhuviOiO/openldap-docker?style=flat&logo=github)](https://github.com/VibhuviOiO/openldap-docker)
[![License](https://img.shields.io/github/license/VibhuviOiO/openldap-docker?style=flat)](https://github.com/VibhuviOiO/openldap-docker/blob/main/LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/vibhuvioio/openldap?style=flat&logo=docker)](https://hub.docker.com/r/vibhuvioio/openldap)
[![Build](https://img.shields.io/github/actions/workflow/status/VibhuviOiO/openldap-docker/docker-publish.yml?label=build&logo=githubactions&logoColor=white)](https://github.com/VibhuviOiO/openldap-docker/actions/workflows/docker-publish.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/VibhuviOiO/openldap-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/VibhuviOiO/openldap-docker)

Production-ready OpenLDAP container with enterprise features.

**📖 [Documentation](https://vibhuvioio.com/openldap-docker/)** | **🐳 [Docker Hub](https://hub.docker.com/r/vibhuvioio/openldap)**

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
- **Vulnerability scanning** - Trivy scans on every build

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
  vibhuvioio/openldap:latest

# Test connection
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=Manager,dc=example,dc=com" \
  -w changeme \
  -b "dc=example,dc=com"
```

> **Registry note:** The primary image is hosted on Docker Hub at `vibhuvioio/openldap`. The same image is also available on GHCR at `ghcr.io/vibhuvioio/openldap` if you prefer GitHub's registry.

### Multi-Node Cluster

Run a 3-node multi-master replication cluster:

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
  vibhuvioio/openldap:latest
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
  vibhuvioio/openldap:latest
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
  vibhuvioio/openldap:latest
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
| `LDAP_CONN_MAX_PENDING` | `100` | Max pending unauthenticated connections (DoS protection) |
| `LDAP_CONN_MAX_PENDING_AUTH` | `1000` | Max pending authenticated connections |

See the [Configuration Guide](https://vibhuvioio.com/openldap-docker/configuration) for the complete reference.

### Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/ldap` | Database files |
| `/etc/openldap/slapd.d` | Configuration |
| `/logs` | Log output (slapd.log, audit.log) |
| `/custom-schema` | Custom LDIF schemas |
| `/docker-entrypoint-initdb.d` | Initialization scripts |

### Database Size Limit

The MDB (LMDB) backend is configured with a default maximum database size of **1 GB** (`olcDbMaxSize: 1073741824`). This is the maximum size the database file can grow to.

**Important:** The MDB database size is fixed at creation time and cannot be changed without reconfiguring the database. Plan your size before loading production data.

## Docker Compose

```yaml
services:
  openldap:
    image: vibhuvioio/openldap:latest
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

See the [OpenLDAP Docker documentation](https://vibhuvioio.com/openldap-docker/) for Kubernetes deployment guides, Helm charts, and production best practices.

## CI/CD and Testing

This repository includes GitHub Actions workflows for continuous integration and publishing:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `validate.yml` | PR to `main` | Linting, basic connectivity, security scan |
| `integration-test.yml` | PR to `main` or `develop` | Full integration test suite |
| `docker-publish.yml` | Tag push | Build and publish to Docker Hub and GHCR |

### Integration Tests

The integration test suite validates:

1. **Basic + ACL** — LDAP connectivity and anonymous access restrictions
2. **Overlay Features** — memberOf, password policy, audit log functionality
3. **TLS/SSL** — StartTLS and LDAPS connectivity
4. **Idempotency** — Restart without errors, data persistence
5. **Docker Secrets** — Password loading from secret files

Run them locally from the `use-cases/` directory.

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

## Use Cases

Example deployments for different scenarios:

| Use Case | Description |
|----------|-------------|
| [`docker-secrets`](use-cases/docker-secrets/) | Secure password management using Docker secrets instead of plaintext environment variables |
| [`overlay-features`](use-cases/overlay-features/) | Integration test for memberOf, password policy, and audit log overlays |
| [`tls-enabled`](use-cases/tls-enabled/) | Integration test for TLS/SSL with StartTLS and LDAPS |
| [`idempotency-test`](use-cases/idempotency-test/) | Integration test for restart idempotency and data persistence |
| [`vibhuvi-com-singlenode`](use-cases/vibhuvi-com-singlenode/) | Single-node deployment example |
| [`vibhuvioio-com-singlenode`](use-cases/vibhuvioio-com-singlenode/) | Alternative single-node configuration |
| [`oiocloud-com-multinode`](use-cases/oiocloud-com-multinode/) | 3-node multi-master replication cluster |
| [`password-policy-test`](use-cases/password-policy-test/) | Password policy testing environment |

## Documentation

Full documentation is available at **[vibhuvioio.com/openldap-docker](https://vibhuvioio.com/openldap-docker/)**:

| Guide | Description |
|-------|-------------|
| [Getting Started](https://vibhuvioio.com/openldap-docker/getting-started) | Quick start, first user creation |
| [Configuration](https://vibhuvioio.com/openldap-docker/configuration) | Full environment variable reference |
| [Replication](https://vibhuvioio.com/openldap-docker/deployment/multi-master) | Multi-master HA cluster setup |
| [Overlays](https://vibhuvioio.com/openldap-docker/overlays) | memberOf, password policy, audit log |
| [Security](https://vibhuvioio.com/openldap-docker/security) | TLS, ACLs, production hardening |
| [Monitoring](https://vibhuvioio.com/openldap-docker/monitoring) | cn=Monitor, health checks, backups |

## Known Limitations

### Replication Credentials in Cleartext

Multi-master replication uses simple bind authentication with the admin password stored in cleartext within the OpenLDAP configuration database (`cn=config`). Anyone with read access to `cn=config` can view these credentials.

**Mitigation:**
- Limit access to the config database through strict ACLs
- Use a dedicated replication user with minimal privileges
- Monitor access to the OpenLDAP container

## License

MIT License

## Security

This project uses automated security scanning:

| Tool | Purpose |
|------|---------|
| **Trivy** | Container vulnerability scanning |
| **cosign** | Image signing with Sigstore |
| **Syft** | SBOM generation |

Please report security vulnerabilities by opening a [GitHub Issue](../../issues) or emailing **contact@vibhuvioio.com**.

---

**Developed by [Vibhuvi OiO](https://vibhuvioio.com)**
