# OpenLDAP Docker - Documentation Index

Welcome to the OpenLDAP Docker deployment documentation. This index will help you find the right documentation for your needs.

## 📚 Documentation Files

### Getting Started
- **[00-MASTER-PLAN.md](dockerization-plan/00-MASTER-PLAN.md)** - Original project plan (COMPLETED)
- **[IMPLEMENTATION_COMPLETE.md](dockerization-plan/IMPLEMENTATION_COMPLETE.md)** - Implementation summary
- **[README.md](README.md)** - Main documentation with features, quick start, and configuration
- **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** - High-level overview, architecture, and use cases

### Operational Guides
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Command reference for daily operations
- **[MIGRATION_FROM_RR.md](MIGRATION_FROM_RR.md)** - Migrate from RR manual configuration to Docker
- **[LOGGING.md](LOGGING.md)** - Logging configuration and log management

### Configuration Files
- **[.env.single-node](.env.single-node)** - Environment template for single node
- **[.env.multi-master-node1](.env.multi-master-node1)** - Environment template for node 1
- **[.env.multi-master-node2](.env.multi-master-node2)** - Environment template for node 2
- **[.env.multi-master-node3](.env.multi-master-node3)** - Environment template for node 3

### Deployment Files
- **[docker-compose.single-node.yml](docker-compose.single-node.yml)** - Single node deployment
- **[docker-compose.multi-master.yml](docker-compose.multi-master.yml)** - Multi-master deployment
- **[docker-compose.override.yml.example](docker-compose.override.yml.example)** - Production customization example

### Scripts
- **[startup.sh](startup.sh)** - Container initialization script
- **[test.sh](test.sh)** - Automated test suite
- **[Makefile](Makefile)** - Management commands

## 🎯 Quick Navigation by Task

### I want to...

#### Deploy a Single Node
1. Read: [README.md](README.md) - Quick Start → Single Node
2. Configure: [.env.single-node](.env.single-node)
3. Deploy: `docker-compose -f docker-compose.single-node.yml up -d`
4. Test: `./test.sh single`

#### Deploy Multi-Master Cluster
1. Read: [README.md](README.md) - Quick Start → Multi-Master
2. Configure: [.env.multi-master-node*](.env.multi-master-node1)
3. Deploy: `docker-compose -f docker-compose.multi-master.yml up -d`
4. Test: `./test.sh multi`

#### Migrate from RR Configuration
1. Read: [MIGRATION_FROM_RR.md](MIGRATION_FROM_RR.md)
2. Follow step-by-step migration guide
3. Test and verify

#### Find a Specific Command
1. Check: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
2. Search for your operation (search, add, modify, delete, backup, etc.)

#### Understand the Architecture
1. Read: [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - Architecture section
2. Review: [README.md](README.md) - Features and Configuration

#### Troubleshoot Issues
1. Check: [README.md](README.md) - Troubleshooting section
2. Check: [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Troubleshooting commands
3. Review logs: `docker logs <container-name>`

#### Add Custom Schema
1. Place `.ldif` file in: [custom-schema/](custom-schema/)
2. Restart container
3. Verify: See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Check Loaded Schemas

#### Backup and Restore
1. Commands: [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Backup & Restore section
2. Strategy: [README.md](README.md) - Backup and Restore section

#### Configure for Production
1. Review: [docker-compose.override.yml.example](docker-compose.override.yml.example)
2. Security: [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - Security Considerations
3. Tuning: [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Performance Tuning

## 📋 Cheat Sheet

### Essential Commands
```bash
# Start single node
make up-single

# Start multi-master
make up-multi

# View logs
make logs-single
make logs-multi

# Test deployment
./test.sh single
./test.sh multi

# Stop and clean
make clean
```

### Essential LDAP Commands
```bash
# Search
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" \
  -D "cn=Manager,dc=example,dc=com" -w admin

# Add entry
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=example,dc=com" -w admin < entry.ldif

# Backup
docker exec openldap-single slapcat -n 2 > backup.ldif
```

## 🔧 Configuration Reference

### Environment Variables
| Variable | Purpose | File |
|----------|---------|------|
| `LDAP_DOMAIN` | Your domain | All `.env.*` files |
| `LDAP_ADMIN_PASSWORD` | Admin password | All `.env.*` files |
| `ENABLE_REPLICATION` | Enable multi-master | `.env.multi-master-*` |
| `SERVER_ID` | Unique node ID | `.env.multi-master-*` |
| `REPLICATION_PEERS` | Other nodes | `.env.multi-master-*` |

### Ports
| Deployment | Node | LDAP | LDAPS |
|------------|------|------|-------|
| Single | - | 389 | 636 |
| Multi | Node 1 | 389 | 636 |
| Multi | Node 2 | 390 | 637 |
| Multi | Node 3 | 391 | 638 |

## 🆘 Getting Help

1. **Check Documentation**: Start with [README.md](README.md)
2. **Search Commands**: Use [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
3. **Review Logs**: `docker logs <container-name>`
4. **Run Tests**: `./test.sh single` or `./test.sh multi`
5. **Check Issues**: Review troubleshooting sections

## 📝 File Descriptions

| File | Purpose |
|------|---------|
| `Dockerfile` | Container image definition |
| `startup.sh` | Initialization and configuration script |
| `docker-compose.*.yml` | Deployment configurations |
| `.env.*` | Environment variable templates |
| `custom-schema/` | Custom LDIF schemas directory |
| `config-templates/` | Future configuration templates |
| `test.sh` | Automated testing script |
| `Makefile` | Management command shortcuts |
| `.gitignore` | Git ignore rules |

## 🚀 Quick Start Paths

### Path 1: Development (Single Node)
```
README.md → .env.single-node → docker-compose.single-node.yml → test.sh
```

### Path 2: Production (Multi-Master)
```
DEPLOYMENT_SUMMARY.md → MIGRATION_FROM_RR.md → .env.multi-master-* → 
docker-compose.multi-master.yml → test.sh → QUICK_REFERENCE.md
```

### Path 3: Migration from RR
```
MIGRATION_FROM_RR.md → custom-schema/RR.ldif → .env.* → 
docker-compose.*.yml → test.sh
```

## 📊 Documentation Hierarchy

```
INDEX.md (You are here)
├── README.md (Start here for new users)
│   ├── Features
│   ├── Quick Start
│   ├── Configuration
│   └── Troubleshooting
├── DEPLOYMENT_SUMMARY.md (Architecture & Overview)
│   ├── Architecture
│   ├── Use Cases
│   └── Security
├── QUICK_REFERENCE.md (Daily Operations)
│   ├── Commands
│   ├── LDAP Operations
│   └── Monitoring
└── MIGRATION_FROM_RR.md (Migration Guide)
    ├── Mapping
    ├── Steps
    └── Verification
```

---

**Last Updated**: 2024  
**Version**: 1.0  
**Maintained By**: Infrastructure Team
