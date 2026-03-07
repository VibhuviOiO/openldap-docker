# OpenLDAP Docker

[![GitHub Stars](https://img.shields.io/github/stars/VibhuviOiO/openldap-docker?style=flat&logo=github)](https://github.com/VibhuviOiO/openldap-docker)
[![License](https://img.shields.io/github/license/VibhuviOiO/openldap-docker?style=flat)](https://github.com/VibhuviOiO/openldap-docker/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/VibhuviOiO/openldap-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/VibhuviOiO/openldap-docker)
[![Build](https://img.shields.io/github/actions/workflow/status/VibhuviOiO/openldap-docker/docker-publish.yml?label=build&logo=githubactions&logoColor=white)](https://github.com/VibhuviOiO/openldap-docker/actions/workflows/docker-publish.yml)
[![Security Scan](https://img.shields.io/github/workflow/status/vibhuvioio/openldap-docker/Docker%20Publish?label=Trivy&logo=aquasecurity&color=blue)](./SECURITY.md)
[![Vulnerabilities](https://img.shields.io/badge/Vulns-View%20Report-orange?logo=aquasecurity)](../../security/code-scanning)

Production-ready OpenLDAP container with enterprise features.

**📖 [Documentation](https://vibhuvioio.com/openldap-docker/)** | **📦 [Container Registry](https://github.com/VibhuviOiO/openldap-docker/pkgs/container/openldap)**

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
- **Vulnerability scanning** - Trivy scans on every build ([View Report](../../security/code-scanning))

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
| `LDAP_CONN_MAX_PENDING` | `100` | Max pending unauthenticated connections (DoS protection) |
| `LDAP_CONN_MAX_PENDING_AUTH` | `1000` | Max pending authenticated connections |

#### Connection Rate Limiting

To protect against connection flooding attacks, OpenLDAP limits the number of pending connections:

- **`LDAP_CONN_MAX_PENDING`** (default: 100): Maximum number of unauthenticated connections waiting to be processed. Additional connections are refused.
- **`LDAP_CONN_MAX_PENDING_AUTH`** (default: 1000): Maximum number of authenticated connections waiting for operations.

**What happens without these limits?**

If these limits are not configured (left at OpenLDAP defaults), the server uses **unlimited** pending connections. This means:
- A malicious actor could open thousands of connections without authenticating
- Memory and file descriptor exhaustion can crash the server
- Legitimate clients cannot connect during an attack

The configured defaults (100/1000) provide reasonable protection while allowing normal operation. Adjust based on your expected load.

**Increase these values for high-traffic environments:**

```yaml
environment:
  - LDAP_CONN_MAX_PENDING=500
  - LDAP_CONN_MAX_PENDING_AUTH=5000
```

**Disable limits (not recommended):**

```yaml
environment:
  - LDAP_CONN_MAX_PENDING=unlimited
  - LDAP_CONN_MAX_PENDING_AUTH=unlimited
```

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

**Important:** The MDB database size is fixed at creation time and cannot be changed without reconfiguring the database.

**To use a different size**, create a custom LDIF file and mount it to apply after the container starts:

```bash
# Create a custom LDIF file
cat > custom-db-size.ldif << 'EOF'
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcDbMaxSize
olcDbMaxSize: 2147483648
EOF

# Apply it after the container is running
ldapmodify -Y EXTERNAL -H ldapi:/// -f custom-db-size.ldif
```

Or use an initialization script in `/docker-entrypoint-initdb.d/` to set it at first startup.

**Note:** If you need a larger database, you must configure this **before** the database is populated with data. Changing the size on an existing database requires dumping and reloading the data.

## Docker Compose

```yaml
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

See [LDAP Manager Documentation](https://vibhuvioio.com/products/ldap-manager) for:
- Helm charts
- Kubernetes deployment guides
- Production best practices
- Monitoring and alerting

## CI/CD and Testing

This repository includes comprehensive GitHub Actions workflows for continuous integration:

### Workflows

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `validate.yml` | PR to `main` | Linting, basic connectivity, security scan |
| `integration-test.yml` | PR to `main` or `develop` | Full integration test suite |
| `docker-publish.yml` | Manual | Build and publish to GHCR |

### Integration Tests

The integration test suite validates:

1. **Basic + ACL** — LDAP connectivity and anonymous access restrictions
2. **Overlay Features** — memberOf, password policy, audit log functionality
3. **TLS/SSL** — StartTLS and LDAPS connectivity
4. **Idempotency** — Restart without errors, data persistence
5. **Docker Secrets** — Password loading from secret files

### Running Tests Locally

```bash
# Run overlay tests
cd use-cases/overlay-features
docker-compose up -d
docker logs -f openldap-overlays

# Run TLS tests
cd use-cases/tls-enabled
docker-compose up -d
LDAPTLS_REQCERT=never ldapsearch -H ldaps://localhost:636 -D "cn=Manager,dc=example,dc=com" -w AdminPass123! -b dc=example,dc=com

# Run idempotency tests
cd use-cases/idempotency-test
docker-compose up -d
docker-compose restart  # Should not error
docker exec openldap-idempotency ldapsearch -x -D "cn=Manager,dc=example,dc=com" -w AdminPass123! -b dc=example,dc=com
```

## Documentation

Full documentation available at **[vibhuvioio.com/products/openldap-docker](https://vibhuvioio.com/products/openldap-docker)**:

| Guide | Description |
|-------|-------------|
| [Getting Started](https://vibhuvioio.com/products/openldap-docker/docs/getting-started) | Quick start, first user creation |
| [Configuration](https://vibhuvioio.com/products/openldap-docker/docs/configuration) | Full environment variable reference |
| [Replication](https://vibhuvioio.com/products/openldap-docker/docs/replication) | Multi-master HA cluster setup |
| [Overlays](https://vibhuvioio.com/products/openldap-docker/docs/overlays) | memberOf, password policy, audit log |
| [Security](https://vibhuvioio.com/products/openldap-docker/docs/security) | TLS, ACLs, production hardening |
| [Monitoring](https://vibhuvioio.com/products/openldap-docker/docs/monitoring) | cn=Monitor, health checks, backups |

### Integration Guides

| Integration | Description |
|-------------|-------------|
| [Keycloak (SSO)](https://vibhuvioio.com/products/openldap-docker/docs/integrations/keycloak) | User federation with Keycloak |
| [Keycloak (Auth Only)](https://vibhuvioio.com/products/openldap-docker/docs/integrations/keycloak-auth-only) | LDAP-only authentication, no user import |
| [Jenkins](https://vibhuvioio.com/products/openldap-docker/docs/integrations/jenkins) | CI/CD authentication with group-based access |
| [SonarQube](https://vibhuvioio.com/products/openldap-docker/docs/integrations/sonarqube) | Code quality platform LDAP auth |
| [HashiCorp Vault](https://vibhuvioio.com/products/openldap-docker/docs/integrations/vault) | Secret management with LDAP auth |
| [Splunk](https://vibhuvioio.com/products/openldap-docker/docs/integrations/splunk) | Log analytics LDAP auth |
| [Apache Guacamole](https://vibhuvioio.com/products/openldap-docker/docs/integrations/guacamole) | Remote access gateway LDAP auth |
| [Portainer](https://vibhuvioio.com/products/openldap-docker/docs/integrations/portainer) | Container management LDAP auth |
| [Redmine](https://vibhuvioio.com/products/openldap-docker/docs/integrations/redmine) | Project management LDAP auth |

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
| [`overlay-features`](use-cases/overlay-features/) | **Integration test** for memberOf, password policy, and audit log overlays |
| [`tls-enabled`](use-cases/tls-enabled/) | **Integration test** for TLS/SSL with StartTLS and LDAPS |
| [`idempotency-test`](use-cases/idempotency-test/) | **Integration test** for restart idempotency and data persistence |
| [`vibhuvi-com-singlenode`](use-cases/vibhuvi-com-singlenode/) | Single-node deployment example |
| [`vibhuvioio-com-singlenode`](use-cases/vibhuvioio-com-singlenode/) | Alternative single-node configuration |
| [`oiocloud-com-multinode`](use-cases/oiocloud-com-multinode/) | 3-node multi-master replication cluster |
| [`password-policy-test`](use-cases/password-policy-test/) | Password policy testing environment |

### Docker Secrets Example

The recommended way to manage passwords in production:

```yaml
services:
  openldap:
    image: ghcr.io/vibhuvioio/openldap:latest
    environment:
      - LDAP_ADMIN_PASSWORD_FILE=/run/secrets/ldap_admin_password
    secrets:
      - ldap_admin_password

secrets:
  ldap_admin_password:
    file: ./secrets/admin_password.txt
```

See [`use-cases/docker-secrets/`](use-cases/docker-secrets/) for a complete example.

## Known Limitations

### Replication Credentials in Cleartext

Multi-master replication uses simple bind authentication with the admin password stored in cleartext within the OpenLDAP configuration database (`cn=config`). Anyone with read access to `cn=config` can view these credentials.

**Mitigation:**
- Limit access to the config database through strict ACLs
- Use a dedicated replication user with minimal privileges
- Monitor access to the OpenLDAP container

**Future Improvement:** Support for SASL/EXTERNAL or TLS client certificate authentication is planned to eliminate cleartext credential storage.

## License

MIT License

## Security

[![Security Scan](https://img.shields.io/github/workflow/status/vibhuvioio/openldap-docker/Docker%20Publish?label=security%20scan)](https://github.com/vibhuvioio/openldap-docker/security)

### Vulnerability Reports

- **Trivy Scan Results**: View in [GitHub Security tab](../../security)
- **Container Image**: `ghcr.io/vibhuvioio/openldap:latest`


## 🔒 Security

This project uses automated security scanning:

| Tool | Purpose | Report |
|------|---------|--------|
| **Trivy** | Container vulnerability scanning | [View Report](../../security/code-scanning) |
| **cosign** | Image signing with Sigstore | [Verify Image](./SECURITY.md) |
| **Syft** | SBOM generation | [Security Policy](./SECURITY.md) |

### Security Badges

- ![Signed](https://img.shields.io/badge/Signed-cosign-blue?logo=sigstore) Container images are signed
- ![Scanned](https://img.shields.io/badge/Scanned-Trivy-success?logo=aquasecurity) Vulnerabilities scanned on every build
- ![SBOM](https://img.shields.io/badge/SBOM-SPDX-green) Software Bill of Materials attached

### Viewing Vulnerability Reports

1. Navigate to [GitHub Security tab](../../security)
2. Click "Code scanning alerts"
3. Filter by tool: "Trivy"

Or view the detailed [Security Policy](./SECURITY.md).

