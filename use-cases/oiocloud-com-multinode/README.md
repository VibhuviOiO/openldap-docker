# OIOCloud.com - 3-Node Multi-Master LDAP Cluster

## Overview
This use case demonstrates a 3-node multi-master OpenLDAP deployment for OIO Cloud Services, featuring a business employee schema with organizational hierarchy and replication across all nodes.

## Features
- **Multi-Master Replication**: 3 nodes with full synchronization
- **Custom Schema**: oioCloudEmployee objectClass
- **Departments**: Cloud Infrastructure, Cloud Security, Cloud Operations
- **30 Employees**: 10 per department across global locations
- **Ports**: 
  - Node 1: 392 (LDAP), 639 (LDAPS)
  - Node 2: 393 (LDAP), 640 (LDAPS)
  - Node 3: 394 (LDAP), 641 (LDAPS)

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Node 1    │────▶│   Node 2    │────▶│   Node 3    │
│  Port 392   │◀────│  Port 393   │◀────│  Port 394   │
└─────────────┘     └─────────────┘     └─────────────┘
       ▲                                        │
       └────────────────────────────────────────┘
              Multi-Master Replication
```

## Quick Start

```bash
# Start all 3 nodes
docker-compose up -d

# Data loads automatically on node1 and replicates to node2 & node3

# Verify employee count on all nodes
echo "=== Node 1 (port 392) ===" && ldapsearch -x -H ldap://localhost:392 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" dn | grep -c "^dn:"

echo "=== Node 2 (port 393) ===" && ldapsearch -x -H ldap://localhost:393 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" dn | grep -c "^dn:"

echo "=== Node 3 (port 394) ===" && ldapsearch -x -H ldap://localhost:394 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" dn | grep -c "^dn:"
```

## Sample Data

- **30 Employees** across 3 departments
- **Cloud Infrastructure Team**: 10 employees (VP, Architects, Engineers)
- **Cloud Security Team**: 10 employees (CISO, Security Engineers, Analysts)
- **Cloud Operations Team**: 10 employees (VP, Operations Engineers, Managers)
- **Global Locations**: San Francisco, Bangalore, Tokyo, London, Singapore, etc.
- **3 Groups**: CloudInfrastructure, CloudSecurity, CloudOperations

## LDAP Manager Configuration

Add to `oio/ldap-manager/config.yml`:

```yaml
clusters:
  - name: oiocloud.com
    description: OIO Cloud Services - Multi-Master Cluster
    nodes:
      - host: localhost
        port: 392
        name: node1
      - host: localhost
        port: 393
        name: node2
      - host: localhost
        port: 394
        name: node3
    bind_dn: cn=Manager,dc=oiocloud,dc=com
    base_dn: dc=oiocloud,dc=com
    readonly: false
```

## Testing Replication

```bash
# Add employee on node 2
echo "dn: employeeID=TEST001,ou=People,dc=oiocloud,dc=com
objectClass: oioCloudEmployee
objectClass: posixAccount
employeeID: TEST001
uid: testuser
cn: Test User
sn: User
mail: test.user@oiocloud.com
department: Engineering
jobTitle: Test Engineer
location: Test City
telephoneNumber: +1-555-9999
uidNumber: 9001
gidNumber: 200
homeDirectory: /home/testuser
userPassword: test123" | docker exec -i openldap-oiocloud-node2 ldapadd -x -D "cn=Manager,dc=oiocloud,dc=com" -w changeme

# Verify on node 1
ldapsearch -x -H ldap://localhost:392 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(employeeID=TEST001)" dn

# Verify on node 3
ldapsearch -x -H ldap://localhost:394 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(employeeID=TEST001)" dn

# Modify on node 3
echo "dn: employeeID=TEST001,ou=People,dc=oiocloud,dc=com
changetype: modify
replace: jobTitle
jobTitle: Senior Test Engineer" | docker exec -i openldap-oiocloud-node3 ldapmodify -x -D "cn=Manager,dc=oiocloud,dc=com" -w changeme

# Verify change replicated to node 1
ldapsearch -x -H ldap://localhost:392 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(employeeID=TEST001)" jobTitle
```

## Monitoring

```bash
# Check logs
docker logs openldap-oiocloud-node1
docker logs openldap-oiocloud-node2
docker logs openldap-oiocloud-node3

# Check replication status
docker exec openldap-oiocloud-node1 cat /logs/slapd.log
```

## Cleanup

```bash
docker-compose down -v
```

## High Availability

This setup provides:
- **Read/Write on all nodes**: Any node can handle modifications
- **Automatic synchronization**: Changes propagate to all nodes
- **Fault tolerance**: Cluster continues operating if 1-2 nodes fail
- **Load balancing**: Distribute read operations across nodes
