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

## Image tags

Tags are derived from the OpenLDAP version **installed in the image**, not from this
repository's release schedule:

| Tag | Meaning |
|-----|---------|
| `latest` | Most recent build |
| `2.6.8` | OpenLDAP version inside the image |
| `sha-<commit>` | Exact source revision |

CI reads `/usr/local/share/openldap-version` out of the built image and fails the build if it
does not match the `VERSION` file, so a tag can never claim a version the image does not
contain.

**Prefer Docker Hub.** `vibhuvioio/openldap` is the primary registry; GHCR is published from
the same build as a mirror. Pull examples in this README use Docker Hub.

## Registries

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
| `LDAP_ADMIN_PASSWORD` | `admin` | Data rootDN (`cn=Manager,<base>`) password |
| `LDAP_CONFIG_PASSWORD` | `config` | `cn=config` password |
| `LDAP_ADMIN_PASSWORD_FILE` | - | Read the admin password from a file (Docker secrets) |
| `LDAP_CONFIG_PASSWORD_FILE` | - | Read the config password from a file |
| `ENABLE_REPLICATION` | `false` | Enable multi-provider replication |
| `SERVER_ID` | `1` | Server ID. **Must be set explicitly when replication is enabled** |
| `REPLICATION_PEERS` | - | Comma-separated peer hostnames (must not include this node) |
| `REPLICATION_RIDS` | - | Optional comma-separated RIDs |
| `REPLICATION_SERVER_IDS` | - | Full SID→URL map, e.g. `1=ldap://n1:389,2=ldap://n2:389` |
| `LDAP_REPLICATION_PASSWORD` | - | Creates `cn=replicator` and uses it for replication instead of the rootDN |
| `LDAP_REPLICATION_STARTTLS` | - | Set to `critical` to add `starttls=critical` to every `olcSyncRepl` |
| `LDAP_REPLICATION_TLS_REQCERT` | `demand` | Certificate verification for replication links |
| `LDAP_MONITOR_PASSWORD` | - | Creates `cn=monitor`, a read-only account with access to `cn=Monitor` |
| `ENABLE_MEMBEROF` | `false` | Enable memberOf overlay |
| `ENABLE_PASSWORD_POLICY` | `false` | Enable password policy |
| `ENABLE_AUDIT_LOG` | `false` | Enable audit logging |
| `ENABLE_MONITORING` | `true` | Enable `cn=Monitor` statistics |
| `LDAP_TLS_CERT` | - | Path to TLS certificate |
| `LDAP_TLS_KEY` | - | Path to TLS key |
| `LDAP_TLS_CA` | - | Optional CA certificate |
| `LDAP_TLS_PROTOCOL_MIN` | `3.3` | Minimum TLS version (`3.3` = TLS 1.2) |
| `LDAP_TLS_VERIFY_CLIENT` | `never` | `never` \| `allow` \| `try` \| `demand` |
| `LDAP_TLS_CIPHER_SUITE` | - | Optional explicit cipher suite list |
| `LDAP_CONN_MAX_PENDING` | `100` | Max pending unauthenticated connections |
| `LDAP_CONN_MAX_PENDING_AUTH` | `1000` | Max pending authenticated connections |
| `LDAP_QUERY_SIZE_SOFT` / `_HARD` | `500` / `1000` | Query size limits for non-service accounts |
| `LDAP_READ_ACCESS_SUBJECT` | `users` | ACL subject permitted to read the directory |
| `LDAP_DISABLE_ANONYMOUS_BIND` | `false` | Disallow anonymous simple binds |
| `LDAP_THREADS` | `16` | slapd worker threads |
| `LDAP_PASSWORD_HASH` | `{SSHA}` | Password hash scheme |
| `LDAP_LOG_LEVEL` | `256` (`16640` with replication) | slapd log level |

`*_PASSWORD_FILE` variables take precedence over the matching plain variable. A
`*_FILE` that is set but unreadable is a hard startup failure rather than a
silent fallback to the default password.

See the [Configuration Guide](https://vibhuvioio.com/openldap-docker/configuration) for the complete reference.

### Volumes

| Path | Purpose |
|------|---------|
| `/var/lib/ldap` | Database files |
| `/etc/openldap/slapd.d` | Configuration |
| `/logs` | Audit log (`audit.log`). slapd itself logs to stdout — use `docker logs` |
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
| `ci.yml` | PR / push to `main` | Linting, build, basic connectivity, non-root check |
| `integration-test.yml` | PR / push to `main` | ACLs, overlays, TLS, Docker secrets, idempotency, fail-fast guardrails, 3-node replication |
| `docker-publish.yml` | Tag push | Build and publish to Docker Hub and GHCR |
| `secops.yml` | After publish | Trivy scan, cosign signing, SBOM |
| `scorecard.yml` | Schedule | OpenSSF Scorecard |

### Integration Tests

The integration scenarios live in `tests/integration/` and are runnable locally:

```bash
docker build -t openldap:local .
tests/integration/single-node.sh openldap:local
tests/integration/replication.sh openldap:local
```

They validate:

1. **Defaults + ACL** — anonymous reads denied, authenticated search works, base OUs present
2. **Overlays** — memberOf maintained, weak passwords rejected, audit log populated
3. **TLS** — certificate *and* CA applied, TLS 1.2 floor, LDAPS and StartTLS answering
4. **Docker secrets** — the password file is the active credential
5. **Idempotency** — restart is error-free, data persists, no generated LDIF left behind
6. **Fail-fast guardrails** — replication without `SERVER_ID`, a missing secret file, and a self-referencing peer each refuse to start
7. **Replication** — 3-node cluster converges, survives a provider restart and catches up

Integration use-cases are maintained in the sibling [`openldap-usecases`](https://github.com/VibhuviOiO/openldap-usecases) repository.

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
Enforces: min 8 chars (`pwdMinLength`), 5-password history, lockout after 5 failures.

Two caveats worth knowing:

- The password policy **does not apply to the rootDN**. `cn=Manager` bypasses it, so
  testing policy enforcement requires binding as a normal user.
- `pwdCheckQuality` is `1` ("check quality if possible, otherwise accept"). No
  `olcPPolicyCheckModule` ships in the base package, so quality checks beyond length are
  inert. Setting `pwdCheckQuality: 2` without a check module would reject *every* password.

## Replication

Three-node multi-provider mesh, single-node settings shown:

```yaml
environment:
  - ENABLE_REPLICATION=true
  - SERVER_ID=1                      # MUST be explicit and unique per node
  - REPLICATION_PEERS=openldap-node2,openldap-node3
  - REPLICATION_SERVER_IDS=1=ldap://openldap-node1:389,2=ldap://openldap-node2:389,3=ldap://openldap-node3:389
  - LDAP_REPLICATION_PASSWORD=change-me
  - LDAP_REPLICATION_STARTTLS=critical
```

Correct-by-default replication is the point of this image, so the following are built in:

| Behaviour | Why |
|-----------|-----|
| `retry="5 5 300 +"` | The trailing `+` retries forever. A finite list (the form used by the Administrator's Guide's own N-Way example) stops replicating permanently after ~25 minutes and the node then serves stale data silently |
| `keepalive=60:3:10` | An idle `refreshAndPersist` link across a stateful firewall can be dropped with no RST; both ends report ESTABLISHED and `retry` never fires |
| `olcSpCheckpoint: 100 10` | Without it the `contextCSN` is only persisted on clean shutdown, so an unclean stop forces a full database scan at next start |
| `olcSpSessionlog: 100` | Without it a stale consumer does a full refresh instead of a delta |
| `entryCSN` / `entryUUID` eq indexes | Searched on every syncrepl operation |
| `olcMultiProvider: TRUE` | The 2.6 name; `olcMirrorMode` is the deprecated alias |
| `cn=replicator` | Least-privilege bind account, exempt from `olcLimits`. Without that exemption a replicator governed by `size.hard` builds a **partial replica silently** |
| `SERVER_ID` required | Two nodes sharing a serverID corrupt CSN ordering |
| Self-peer rejected | A provider URL naming the local node causes a replication loop |

`LDAP_REPLICATION_PASSWORD` is strongly recommended: without it replication binds as the
directory rootDN, which stores the administrator credential in cleartext in `cn=config` on
every node. `ldapcheck.sh` warns about this.

## Validation

A bundled validator checks the configuration and, optionally, cross-node convergence:

```bash
# Local configuration only
docker exec openldap /usr/local/bin/scripts/ldapcheck.sh

# Compare contextCSN against peers
docker exec openldap /usr/local/bin/scripts/ldapcheck.sh --peers node2,node3

# Also compare entry counts (reads every entry)
docker exec openldap /usr/local/bin/scripts/ldapcheck.sh --peers node2,node3 --deep
```

It fails (non-zero) on a finite `retry` list, a missing `keepalive`, a missing
`entryCSN` index, `olcMultiProvider` not TRUE, `olcReadOnly` set, a missing `olcServerID`
for the local SID, a `syncprov` overlay that is absent or duplicated, or a peer whose
`contextCSN` set has not converged. Suitable for CI and for incident triage.

`make ldapcheck` wraps it, and `make backup` / `make restore` cover data plus `cn=config`.
Note that `make restore` is destructive and requires `FORCE=1`.

## Use-Cases

Hands-on use-cases and integration scenarios are maintained separately in the sibling [`openldap-usecases`](https://github.com/VibhuviOiO/openldap-usecases) repository. They cover single-node deployments, multi-master replication, overlays, TLS, Docker secrets, idempotency, and password policy testing.

Clone it alongside this repository and run tests from `../openldap-usecases/<use-case>/`.

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

Replication uses simple bind authentication, so the bind password is stored in cleartext
within the OpenLDAP configuration database (`cn=config`) on every node. Anyone with read
access to `cn=config` can read it. This is inherent to `bindmethod=simple`.

**Mitigation (partly built in):**

- Set `LDAP_REPLICATION_PASSWORD` so the credential is a dedicated, least-privilege
  `cn=replicator` account rather than the directory rootDN
- Set `LDAP_REPLICATION_STARTTLS=critical` so the credential is not also sent in cleartext
  over the network
- Limit access to the config database through strict ACLs
- Monitor access to the OpenLDAP container

The long-term fix is SASL/EXTERNAL or TLS client-certificate authentication for
replication, which this image does not yet support.

### startup.sh configures the database only once

`set_database_acl`, `configure_indices`, `set_query_limits` and the overlay configuration
run only on first initialisation, when the suffix is not yet configured. An existing data
volume therefore does **not** pick up changes to ACLs, indices or limits from a newer image
version. Changing those requires a fresh database, or applying the equivalent `ldapmodify`
by hand. Service accounts (`cn=replicator`, `cn=monitor`) are the exception: they are
reconciled on every start.

### Audit log rotation

`/logs/audit.log` is a file that slapd holds open, so the container log driver cannot
manage it. It grows without bound unless you rotate it externally (sidecar, or host-side
rotation of the mounted volume). slapd's own output goes to stdout and *is* covered by the
`logging:` block in the compose file.

### Database Size Limit

The MDB (LMDB) backend is configured with a default maximum database size of **1 GB**
(`olcDbMaxSize: 1073741824`), which is not currently configurable by environment variable.
Hitting the LMDB map makes writes **fail**, not slow down, so size it deliberately for large
directories.

### Health check cannot distinguish an empty database from a fresh install

`healthcheck.sh` verifies that the expected suffix is a configured naming context, but an
intact config volume with a wiped data volume still advertises that context. Use
`ldapcheck.sh --deep` to compare entry counts across nodes.

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
