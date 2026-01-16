# Multi-Node Cluster Deployment

## Use Case

Production 3-node multi-master cluster with automatic replication configuration.

---

## Docker Compose Cluster

```yaml
version: '3.8'

services:
  ldap-node1:
    build: .
    container_name: ldap-node1
    hostname: ldap-node1
    environment:
      - LDAP_DOMAIN=vibhuvioio.com
      - LDAP_BASE_DN=dc=vibhuvioio,dc=com
      - LDAP_ADMIN_PASSWORD=secret123
      - LDAP_CONFIG_PASSWORD=config123
      - SERVER_ID=1
      - ENABLE_REPLICATION=true
      - REPLICATION_PEERS=ldap-node2:389,ldap-node3:389
      - IMPORT_LDIF_PATH=/data-import/initial-data.ldif
    ports:
      - "389:389"
    volumes:
      - ldap-data1:/var/lib/ldap
      - ldap-config1:/etc/openldap/slapd.d
      - ./import:/data-import:ro
    networks:
      - ldap-cluster
    restart: unless-stopped

  ldap-node2:
    build: .
    container_name: ldap-node2
    hostname: ldap-node2
    environment:
      - LDAP_DOMAIN=vibhuvioio.com
      - LDAP_BASE_DN=dc=vibhuvioio,dc=com
      - LDAP_ADMIN_PASSWORD=secret123
      - LDAP_CONFIG_PASSWORD=config123
      - SERVER_ID=2
      - ENABLE_REPLICATION=true
      - REPLICATION_PEERS=ldap-node1:389,ldap-node3:389
      - IMPORT_LDIF_PATH=/data-import/initial-data.ldif
    ports:
      - "390:389"
    volumes:
      - ldap-data2:/var/lib/ldap
      - ldap-config2:/etc/openldap/slapd.d
      - ./import:/data-import:ro
    networks:
      - ldap-cluster
    restart: unless-stopped
    depends_on:
      - ldap-node1

  ldap-node3:
    build: .
    container_name: ldap-node3
    hostname: ldap-node3
    environment:
      - LDAP_DOMAIN=vibhuvioio.com
      - LDAP_BASE_DN=dc=vibhuvioio,dc=com
      - LDAP_ADMIN_PASSWORD=secret123
      - LDAP_CONFIG_PASSWORD=config123
      - SERVER_ID=3
      - ENABLE_REPLICATION=true
      - REPLICATION_PEERS=ldap-node1:389,ldap-node2:389
      - IMPORT_LDIF_PATH=/data-import/initial-data.ldif
    ports:
      - "391:389"
    volumes:
      - ldap-data3:/var/lib/ldap
      - ldap-config3:/etc/openldap/slapd.d
      - ./import:/data-import:ro
    networks:
      - ldap-cluster
    restart: unless-stopped
    depends_on:
      - ldap-node1
      - ldap-node2

volumes:
  ldap-data1:
  ldap-data2:
  ldap-data3:
  ldap-config1:
  ldap-config2:
  ldap-config3:

networks:
  ldap-cluster:
    driver: bridge
```

---

## Usage

**Start cluster:**
```bash
docker-compose -f docker-compose-cluster.yml up -d
```

**Check cluster health:**
```bash
docker exec ldap-node1 /usr/local/bin/health-check.sh
docker exec ldap-node2 /usr/local/bin/health-check.sh
docker exec ldap-node3 /usr/local/bin/health-check.sh
```

**Verify replication:**
```bash
# Add entry on node1
docker exec ldap-node1 ldapadd -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w secret123 <<EOF
dn: cn=test,dc=vibhuvioio,dc=com
objectClass: organizationalRole
cn: test
EOF

# Check on node2
docker exec ldap-node2 ldapsearch -x -b "cn=test,dc=vibhuvioio,dc=com"

# Check on node3
docker exec ldap-node3 ldapsearch -x -b "cn=test,dc=vibhuvioio,dc=com"
```

**Scale down/up:**
```bash
docker-compose -f docker-compose-cluster.yml stop ldap-node3
docker-compose -f docker-compose-cluster.yml start ldap-node3
```

**Logs:**
```bash
docker-compose -f docker-compose-cluster.yml logs -f
```

---

## Auto-Configuration Logic

**On container startup:**

1. Check if `/var/lib/ldap` is empty (first boot)
2. If first boot:
   - Load schemas
   - Create base domain
   - Import LDIF if `IMPORT_LDIF_PATH` set
   - Set Server ID from `SERVER_ID` env
3. If `ENABLE_REPLICATION=true`:
   - Parse `REPLICATION_PEERS`
   - Generate replication config with unique RIDs
   - Apply replication config
4. Start slapd

---

## Key Features

- ✅ **One command deployment:** `docker-compose up -d`
- ✅ **Auto-replication:** No manual configuration
- ✅ **Unique Server IDs:** From environment variables
- ✅ **Data persistence:** Volumes for each node
- ✅ **Service discovery:** DNS-based (ldap-node1, ldap-node2, ldap-node3)
- ✅ **Health monitoring:** Built-in health checks
- ✅ **Easy scaling:** Add/remove nodes via compose file

---

## Next: Implement Scripts

- `docker-entrypoint.sh` - Orchestrates initialization
- `configure-replication.sh` - Generates and applies replication config
- `health-check.sh` - Validates cluster health
