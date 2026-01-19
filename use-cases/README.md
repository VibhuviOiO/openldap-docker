# OpenLDAP Use Cases

This directory contains real-world OpenLDAP deployment scenarios managed through a unified LDAP Manager UI.

## LDAP Manager

**LDAP Manager** is a web-based UI that provides centralized management for multiple LDAP clusters from a single interface.

### Features
- **Multi-Cluster Management**: Switch between different LDAP directories seamlessly
- **User Management**: Create, edit, delete users with custom forms per cluster
- **Group Management**: Manage groups and memberships
- **Search & Filter**: Advanced search across users, groups, and OUs
- **Custom Schemas**: Support for domain-specific attributes and object classes
- **Multi-Master Support**: Manage replicated clusters with automatic failover
- **Responsive UI**: Modern React-based interface

### Access
- **URL**: http://localhost:5173
- **Configuration**: `ldap-manager/config.yml`
- **Start**: `cd ldap-manager && docker-compose up -d`

## Available Use Cases

### 1. vibhuvioio.com - Mahabharata Warriors (Single Node)
**Port**: 389, 636  
**Schema**: Custom warrior/kingdom schema  
**Use Case**: Mythological character management system  
**Status**: ✅ Production Ready

- Custom objectClasses: warrior, kingdom
- Attributes: role, kingdom, weapon, allegiance, isWarrior, isAdmin
- Sample data: Pandavas, Kauravas, and other Mahabharata characters
- [Documentation](./vibhuvioio-com-singlenode/README.md)

```bash 
cd oio/openldap-docker/use-cases/vibhuvioio-com-singlenode
docker-compose down -v  &&
docker-compose up -d 
```

### 2. vibhuvi.com - Corporate Employees (Single Node)
**Port**: 390, 637  
**Schema**: Employee management schema  
**Use Case**: Corporate employee directory  
**Status**: ✅ Ready to Deploy

- Custom objectClass: vibhuviEmployee
- Attributes: employeeID, department, jobTitle, hireDate, salary, manager
- Departments: Engineering, Sales, HR
- Sample data: 5 employees across 3 departments
- [Documentation](./vibhuvi-com-singlenode/README.md)

### 3. oiocloud.com - Cloud Services (3-Node Multi-Master)
**Ports**: 392-394, 639-641  
**Schema**: Cloud employee schema  
**Use Case**: Enterprise cloud services directory with high availability  
**Status**: ✅ Production Ready

- Custom objectClass: oioCloudEmployee
- Attributes: employeeID, department, jobTitle, location, telephoneNumber
- Multi-master replication across 3 nodes
- Departments: Cloud Infrastructure, Cloud Security, Cloud Operations
- Sample data: 30 employees across global locations
- [Documentation](./oiocloud-com-multinode/README.md)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    LDAP Manager UI                          │
│                   (Single Interface)                        │
└────────────┬──────────────┬──────────────┬─────────────────┘
             │              │              │
             ▼              ▼              ▼
    ┌────────────┐  ┌────────────┐  ┌────────────────────┐
    │ vibhuvioio │  │  vibhuvi   │  │    oiocloud.com    │
    │    .com    │  │    .com    │  │   (3-node cluster) │
    │            │  │            │  │                    │
    │  Port 389  │  │  Port 390  │  │ Ports 392-394      │
    │ Single Node│  │ Single Node│  │ Multi-Master       │
    └────────────┘  └────────────┘  └────────────────────┘
```

## Quick Start All Clusters

```bash
# Start vibhuvioio.com (existing)
cd vibhuvioio-com-singlenode
docker-compose up -d
cd ..

# Start vibhuvi.com
cd vibhuvi-com-singlenode
docker-compose up -d
sleep 10
docker exec openldap-vibhuvi ldapadd -x -D "cn=admin,dc=vibhuvi,dc=com" -w changeme -f /custom-schema/employee_data.ldif
cd ..

# Start oiocloud.com (3 nodes - data loads automatically)
cd oiocloud-com-multinode
docker-compose up -d
cd ..
```

## LDAP Manager Configuration

Update `oio/ldap-manager/config.yml`:

```yaml
clusters:
  # Existing cluster
  - name: vibhuvioio.com
    description: Mahabharata Warriors Directory
    host: localhost
    port: 389
    bind_dn: cn=admin,dc=vibhuvioio,dc=com
    base_dn: dc=vibhuvioio,dc=com
    readonly: false

  # New single-node cluster
  - name: vibhuvi.com
    description: Vibhuvi Corporation Employee Directory
    host: localhost
    port: 390
    bind_dn: cn=Manager,dc=vibhuvi,dc=com
    base_dn: dc=vibhuvi,dc=com
    readonly: false

  # New multi-node cluster
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

## Port Allocation

| Cluster | LDAP Port | LDAPS Port | Type |
|---------|-----------|------------|------|
| vibhuvioio.com | 389 | 636 | Single Node |
| vibhuvi.com | 390 | 637 | Single Node |
| oiocloud.com (node1) | 392 | 639 | Multi-Master |
| oiocloud.com (node2) | 393 | 640 | Multi-Master |
| oiocloud.com (node3) | 394 | 641 | Multi-Master |

## Use Case Comparison

| Feature | vibhuvioio.com | vibhuvi.com | oiocloud.com |
|---------|----------------|-------------|--------------|
| **Nodes** | 1 | 1 | 3 |
| **Replication** | No | No | Multi-Master |
| **Schema Type** | Custom (Mythological) | Corporate | Business |
| **Sample Users** | 20 warriors | 28 employees | 30 employees |
| **Departments** | Kingdoms | 8 | 3 |
| **Hierarchy** | Flat | Manager-Employee | Multi-level |
| **Use Case** | Demo/Testing | Small Company | Enterprise |

## Testing All Clusters

```bash
# Test vibhuvioio.com
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=admin,dc=vibhuvioio,dc=com" -w changeme "(objectClass=warrior)" cn

# Test vibhuvi.com
ldapsearch -x -H ldap://localhost:390 -b "dc=vibhuvi,dc=com" -D "cn=Manager,dc=vibhuvi,dc=com" -w changeme "(objectClass=vibhuviEmployee)" cn department

# Test oiocloud.com (all nodes)
ldapsearch -x -H ldap://localhost:392 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn department
ldapsearch -x -H ldap://localhost:393 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn department
ldapsearch -x -H ldap://localhost:394 -b "dc=oiocloud,dc=com" -D "cn=Manager,dc=oiocloud,dc=com" -w changeme "(objectClass=oioCloudEmployee)" cn department
```

## Cleanup All Clusters

```bash
cd vibhuvioio-com-singlenode && docker-compose down -v && cd ..
cd vibhuvi-com-singlenode && docker-compose down -v && cd ..
cd oiocloud-com-multinode && docker-compose down -v && cd ..
```

## Benefits of Multi-Cluster Management

1. **Single UI**: Manage all clusters from one interface
2. **Consistent Experience**: Same operations across different schemas
3. **Easy Switching**: Toggle between clusters instantly
4. **Centralized Monitoring**: View health of all clusters
5. **Unified Search**: Search across different directories
6. **Role-Based Access**: Different permissions per cluster

## Next Steps

1. Start the clusters you need
2. Update LDAP Manager configuration
3. Restart LDAP Manager backend
4. Access UI and switch between clusters
5. Explore different schemas and data models
