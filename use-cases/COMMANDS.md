# LDAP Multi-Cluster Setup - Commands Only

## Prerequisites
```bash
cd oio/openldap-docker/use-cases
docker network create ldap-shared-network
```

## Start All Clusters

### 1. vibhuvioio.com (Port 389)
```bash
cd vibhuvioio-com-singlenode
docker-compose up -d
cd ..
```

### 2. vibhuvi.com (Port 390)
```bash
cd vibhuvi-com-singlenode
docker-compose up -d
sleep 10
docker exec openldap-vibhuvi ldapadd -x -D "cn=admin,dc=vibhuvi,dc=com" -w changeme -f /data/employee_data.ldif
cd ..
```

### 3. oiocloud.com (Ports 391-393)
```bash
cd oiocloud-com-multinode
docker-compose up -d
sleep 30
docker exec openldap-oiocloud-node1 ldapadd -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme -f /data/business_data.ldif
cd ..
```

### 4. LDAP Manager UI
```bash
docker-compose -f docker-compose.ldap-manager.yml up -d
```

## Access
```bash
# UI
open http://localhost:5173

# API
curl http://localhost:8000/api/clusters/list
```

## Verify Clusters
```bash
# vibhuvioio.com
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w changeme "(objectClass=warrior)" cn | grep "^cn:"

# vibhuvi.com
ldapsearch -x -H ldap://localhost:390 -b "dc=vibhuvi,dc=com" -D "cn=admin,dc=vibhuvi,dc=com" -w changeme "(objectClass=vibhuviEmployee)" cn | grep "^cn:"

# oiocloud.com node1
ldapsearch -x -H ldap://localhost:391 -b "dc=oiocloud,dc=com" -D "cn=admin,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn | grep "^cn:"

# oiocloud.com node2
ldapsearch -x -H ldap://localhost:392 -b "dc=oiocloud,dc=com" -D "cn=admin,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn | grep "^cn:"

# oiocloud.com node3
ldapsearch -x -H ldap://localhost:393 -b "dc=oiocloud,dc=com" -D "cn=admin,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn | grep "^cn:"
```

## Check Status
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## View Logs
```bash
# LDAP Manager
docker logs -f ldap-manager

# vibhuvioio.com
docker logs -f openldap-vibhuvioio

# vibhuvi.com
docker logs -f openldap-vibhuvi

# oiocloud.com
docker logs -f openldap-oiocloud-node1
docker logs -f openldap-oiocloud-node2
docker logs -f openldap-oiocloud-node3
```

## Stop All
```bash
docker-compose -f docker-compose.ldap-manager.yml down
cd oiocloud-com-multinode && docker-compose down && cd ..
cd vibhuvi-com-singlenode && docker-compose down && cd ..
cd vibhuvioio-com-singlenode && docker-compose down && cd ..
```

## Clean All (Remove Data)
```bash
docker-compose -f docker-compose.ldap-manager.yml down -v
cd oiocloud-com-multinode && docker-compose down -v && cd ..
cd vibhuvi-com-singlenode && docker-compose down -v && cd ..
cd vibhuvioio-com-singlenode && docker-compose down -v && cd ..
docker network rm ldap-shared-network
```

## Restart Single Cluster
```bash
# vibhuvioio.com
cd vibhuvioio-com-singlenode && docker-compose restart && cd ..

# vibhuvi.com
cd vibhuvi-com-singlenode && docker-compose restart && cd ..

# oiocloud.com
cd oiocloud-com-multinode && docker-compose restart && cd ..

# LDAP Manager
docker-compose -f docker-compose.ldap-manager.yml restart
```

## Test Replication (oiocloud.com)
```bash
# Add user on node1
echo "dn: uid=test.repl,ou=People,dc=oiocloud,dc=com
objectClass: oioCloudEmployee
uid: test.repl
cn: Test Replication
sn: Replication
mail: test.repl@oiocloud.com
businessUnit: Technology
employeeLevel: Junior
userPassword: test123" | docker exec -i openldap-oiocloud-node1 ldapadd -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme

# Verify on node2
docker exec openldap-oiocloud-node2 ldapsearch -x -b "uid=test.repl,ou=People,dc=oiocloud,dc=com" -LLL cn

# Verify on node3
docker exec openldap-oiocloud-node3 ldapsearch -x -b "uid=test.repl,ou=People,dc=oiocloud,dc=com" -LLL cn

# Delete test user
docker exec openldap-oiocloud-node1 ldapdelete -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme "uid=test.repl,ou=People,dc=oiocloud,dc=com"
```

## Troubleshooting
```bash
# Check network
docker network inspect ldap-shared-network

# Check if containers are on network
docker network inspect ldap-shared-network --format '{{range .Containers}}{{.Name}} {{end}}'

# Rebuild LDAP Manager
docker-compose -f docker-compose.ldap-manager.yml down
docker-compose -f docker-compose.ldap-manager.yml build --no-cache
docker-compose -f docker-compose.ldap-manager.yml up -d

# Rebuild specific cluster
cd vibhuvi-com-singlenode
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
cd ..
```

## Port Summary
| Cluster | LDAP | LDAPS | Container |
|---------|------|-------|-----------|
| vibhuvioio.com | 389 | 636 | openldap-vibhuvioio |
| vibhuvi.com | 390 | 637 | openldap-vibhuvi |
| oiocloud.com-node1 | 391 | 638 | openldap-oiocloud-node1 |
| oiocloud.com-node2 | 392 | 639 | openldap-oiocloud-node2 |
| oiocloud.com-node3 | 393 | 640 | openldap-oiocloud-node3 |
| LDAP Manager | 8000, 5173 | - | ldap-manager |
