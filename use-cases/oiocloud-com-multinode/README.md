# OIOCloud.com - 3-Node Multi-Master LDAP Cluster

## Overview
This use case demonstrates a 3-node multi-master OpenLDAP deployment for OIO Cloud Services, featuring a business employee schema with organizational hierarchy and replication across all nodes.

## Features
- **Multi-Master Replication**: 3 nodes with full synchronization
- **Custom Schema**: oioCloudEmployee objectClass with business attributes
- **Departments**: Executive, Technology, Product, Sales, Marketing, HR
- **Attributes**: businessUnit, costCenter, employeeLevel, location, workSchedule
- **Ports**: 
  - Node 1: 391 (LDAP), 638 (LDAPS)
  - Node 2: 392 (LDAP), 639 (LDAPS)
  - Node 3: 393 (LDAP), 640 (LDAPS)

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Node 1    │────▶│   Node 2    │────▶│   Node 3    │
│  Port 391   │◀────│  Port 392   │◀────│  Port 393   │
└─────────────┘     └─────────────┘     └─────────────┘
       ▲                                        │
       └────────────────────────────────────────┘
              Multi-Master Replication
```

## Quick Start

```bash
# Start all 3 nodes
docker-compose up -d

# Wait for initialization and replication setup
sleep 30

# Load sample data on node 1 (will replicate to all nodes)
docker exec openldap-oiocloud-node1 ldapadd -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme -f /custom-schema/business_data.ldif

# Verify on all nodes
docker exec openldap-oiocloud-node1 ldapsearch -x -b "dc=oiocloud,dc=com" -LLL | grep "dn:"
docker exec openldap-oiocloud-node2 ldapsearch -x -b "dc=oiocloud,dc=com" -LLL | grep "dn:"
docker exec openldap-oiocloud-node3 ldapsearch -x -b "dc=oiocloud,dc=com" -LLL | grep "dn:"
```

## Sample Organization

| Name | Title | Business Unit | Level | Location |
|------|-------|---------------|-------|----------|
| John Anderson | CEO | Executive | C-Level | San Francisco |
| Sarah Martinez | CTO | Technology | C-Level | San Francisco |
| Mike Thompson | Engineering Director | Technology | Director | San Francisco |
| Lisa Chen | Senior Software Engineer | Technology | Senior | Austin (Remote) |
| Tom Wilson | Software Engineer | Technology | Mid | New York |
| Anna Rodriguez | Product Manager | Product | Manager | San Francisco |
| Robert Lee | VP of Sales | Sales | VP | New York |
| Jennifer Taylor | Account Executive | Sales | Mid | Chicago |
| David Kim | Marketing Director | Marketing | Director | Los Angeles |
| Emily White | HR Manager | Human Resources | Manager | San Francisco |

## LDAP Manager Configuration

Add to `oio/ldap-manager/config.yml`:

```yaml
clusters:
  - name: oiocloud.com
    description: OIO Cloud Services - Multi-Master Cluster
    nodes:
      - host: localhost
        port: 391
        name: node1
      - host: localhost
        port: 392
        name: node2
      - host: localhost
        port: 393
        name: node3
    bind_dn: cn=admin,dc=oiocloud,dc=com
    base_dn: dc=oiocloud,dc=com
    readonly: false
```

## Testing Replication

```bash
# Add user on node 1
echo "dn: uid=test.user,ou=People,dc=oiocloud,dc=com
objectClass: oioCloudEmployee
uid: test.user
cn: Test User
sn: User
mail: test.user@oiocloud.com
businessUnit: Technology
employeeLevel: Junior
userPassword: test123" | docker exec -i openldap-oiocloud-node1 ldapadd -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme

# Verify on node 2
docker exec openldap-oiocloud-node2 ldapsearch -x -b "uid=test.user,ou=People,dc=oiocloud,dc=com" -LLL

# Verify on node 3
docker exec openldap-oiocloud-node3 ldapsearch -x -b "uid=test.user,ou=People,dc=oiocloud,dc=com" -LLL

# Modify on node 2
echo "dn: uid=test.user,ou=People,dc=oiocloud,dc=com
changetype: modify
replace: employeeLevel
employeeLevel: Mid" | docker exec -i openldap-oiocloud-node2 ldapmodify -x -D "cn=admin,dc=oiocloud,dc=com" -w changeme

# Verify change replicated to node 1
docker exec openldap-oiocloud-node1 ldapsearch -x -b "uid=test.user,ou=People,dc=oiocloud,dc=com" -LLL employeeLevel
```

## Monitoring

```bash
# Check replication status on each node
docker exec openldap-oiocloud-node1 ldapsearch -x -b "cn=config" -D "cn=admin,cn=config" -w changeme "(olcSyncrepl=*)" olcSyncrepl
docker exec openldap-oiocloud-node2 ldapsearch -x -b "cn=config" -D "cn=admin,cn=config" -w changeme "(olcSyncrepl=*)" olcSyncrepl
docker exec openldap-oiocloud-node3 ldapsearch -x -b "cn=config" -D "cn=admin,cn=config" -w changeme "(olcSyncrepl=*)" olcSyncrepl
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
