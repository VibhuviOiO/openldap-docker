# Multi-Cluster LDAP Setup with Single UI

## Quick Start - All Clusters

```bash
# 0. Create shared network
docker network create ldap-shared-network

# 1. Start vibhuvioio.com (port 389)
cd vibhuvioio-com-singlenode
docker-compose up -d
cd ..

# 2. Start vibhuvi.com (port 390)
cd vibhuvi-com-singlenode
docker-compose up -d
sleep 10
docker exec openldap-vibhuvi ldapadd -x -D "cn=admin,dc=vibhuvi,dc=com" -w changeme -f /custom-schema/employee_data.ldif
cd ..

# 3. Start oiocloud.com 3-node cluster (ports 391-393)
cd oiocloud-com-multinode
docker-compose up -d
sleep 30
docker exec openldap-oiocloud-node1 ldapadd -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme -f /custom-schema/business_data.ldif
cd ..

# 4. Start LDAP Manager UI
docker-compose -f docker-compose.ldap-manager.yml up -d
```

## Access

- **LDAP Manager UI**: http://localhost:5173
- **Backend API**: http://localhost:8000

## Clusters Available

| Cluster | Port | Type | Description |
|---------|------|------|-------------|
| vibhuvioio.com | 389 | Single Node | Mahabharata Warriors |
| vibhuvi.com | 390 | Single Node | Corporate Employees |
| oiocloud.com | 391-393 | 3-Node Multi-Master | Business Organization |

## Stop All

```bash
docker-compose -f docker-compose.ldap-manager.yml down
cd oiocloud-com-multinode && docker-compose down && cd ..
cd vibhuvi-com-singlenode && docker-compose down && cd ..
cd vibhuvioio-com-singlenode && docker-compose down && cd ..
```

## Clean All (including data)

```bash
docker-compose -f docker-compose.ldap-manager.yml down -v
cd oiocloud-com-multinode && docker-compose down -v && cd ..
cd vibhuvi-com-singlenode && docker-compose down -v && cd ..
cd vibhuvioio-com-singlenode && docker-compose down -v && cd ..
```
