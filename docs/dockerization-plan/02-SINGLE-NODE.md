# Single Node Deployment

## Use Case

Development, testing, or standalone LDAP server without replication.

---

## Docker Compose

```yaml
version: '3.8'

services:
  ldap:
    build: .
    container_name: openldap-single
    hostname: ldap.example.com
    environment:
      - LDAP_DOMAIN=vibhuvioio.com
      - LDAP_BASE_DN=dc=vibhuvioio,dc=com
      - LDAP_ADMIN_PASSWORD=secret123
      - LDAP_CONFIG_PASSWORD=config123
      - SERVER_ID=1
      - ENABLE_REPLICATION=false
    ports:
      - "389:389"
      - "636:636"
    volumes:
      - ldap-data:/var/lib/ldap
      - ldap-config:/etc/openldap/slapd.d
      - ./schemas:/custom-schemas:ro
      - ./import:/data-import:ro
    networks:
      - ldap-net
    restart: unless-stopped

volumes:
  ldap-data:
  ldap-config:

networks:
  ldap-net:
    driver: bridge
```

---

## Usage

**Start:**
```bash
docker-compose up -d
```

**Import data:**
```bash
docker exec openldap-single slapadd -n 2 -l /data-import/data.ldif
docker restart openldap-single
```

**Check status:**
```bash
docker exec openldap-single ldapsearch -x -b "dc=vibhuvioio,dc=com" | grep -c "^dn:"
```

**Logs:**
```bash
docker logs -f openldap-single
```

**Stop:**
```bash
docker-compose down
```

---

## Features

- ✅ Persistent data (volumes)
- ✅ Custom schemas support
- ✅ Data import on startup
- ✅ Health checks
- ✅ Easy backup/restore
