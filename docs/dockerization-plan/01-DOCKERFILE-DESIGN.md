# Dockerfile Design

## Enhanced Dockerfile Features

### 1. Multi-Stage Build
- **Stage 1:** Build dependencies
- **Stage 2:** Runtime image (smaller, secure)

### 2. Environment Variables

```dockerfile
ENV LDAP_DOMAIN="vibhuvioio.com"
ENV LDAP_BASE_DN="dc=vibhuvioio,dc=com"
ENV LDAP_ADMIN_PASSWORD="changeme"
ENV LDAP_CONFIG_PASSWORD="changeme"
ENV SERVER_ID="1"
ENV REPLICATION_PEERS=""
ENV IMPORT_LDIF_PATH=""
ENV ENABLE_REPLICATION="false"
```

### 3. Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD ldapsearch -x -H ldap://localhost:389 -b "" -s base || exit 1
```

### 4. Entrypoint vs CMD

- **ENTRYPOINT:** `/usr/local/bin/docker-entrypoint.sh` (always runs)
- **CMD:** `["slapd", "-d", "256", "-h", "ldap:/// ldapi:///"]` (can override)

---

## Proposed Dockerfile

```dockerfile
FROM almalinux:9 AS base

# Install OpenLDAP
RUN dnf -y update && \
    dnf -y install dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf -y install openldap openldap-clients openldap-servers \
                   procps-ng iproute net-tools gettext && \
    dnf clean all

# Environment variables
ENV LDAP_DOMAIN="example.com" \
    LDAP_BASE_DN="dc=example,dc=com" \
    LDAP_ADMIN_PASSWORD="" \
    LDAP_CONFIG_PASSWORD="" \
    SERVER_ID="1" \
    REPLICATION_PEERS="" \
    IMPORT_LDIF_PATH="" \
    ENABLE_REPLICATION="false" \
    ENABLE_MONITORING="true"

# Create directories
RUN mkdir -p /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap \
             /docker-entrypoint-initdb.d /custom-schemas /data-import && \
    chown -R ldap:ldap /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap

# Copy scripts and configs
COPY scripts/docker-entrypoint.sh /usr/local/bin/
COPY scripts/configure-replication.sh /usr/local/bin/
COPY scripts/health-check.sh /usr/local/bin/
COPY config/templates/ /config-templates/
COPY init/*.ldif /docker-entrypoint-initdb.d/

RUN chmod +x /usr/local/bin/*.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD /usr/local/bin/health-check.sh

# Volumes
VOLUME ["/var/lib/ldap", "/etc/openldap/slapd.d", "/custom-schemas", "/data-import"]

# Ports
EXPOSE 389 636

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["slapd", "-d", "256", "-h", "ldap:/// ldapi:///", "-u", "ldap", "-g", "ldap"]
```

---

## Key Improvements

1. **Environment-driven:** All config via ENV vars
2. **Health checks:** Built-in container health monitoring
3. **Volumes:** Persistent data and config
4. **Templates:** Config files generated from templates
5. **Auto-init:** Schemas and base domain loaded on first boot
6. **Replication:** Auto-configured based on REPLICATION_PEERS

---

## Next: Implement Scripts

- `docker-entrypoint.sh` - Main initialization logic
- `configure-replication.sh` - Auto-setup replication
- `health-check.sh` - Container health validation
