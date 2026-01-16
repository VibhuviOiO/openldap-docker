# Setup Guide

## Prerequisites

1. **Docker** (20.10+)
   ```bash
   docker --version
   ```

2. **Docker Compose** (2.0+)
   ```bash
   docker-compose --version
   ```

## Installation Steps

### 1. Clone Repository

```bash
git clone https://github.com/[your-org]/openldap.git
cd openldap
```

### 2. Choose Deployment Type

#### Option A: Single Node (Recommended for Development)

```bash
# Copy environment template
cp .env.single-node .env

# Edit configuration
nano .env

# Start OpenLDAP
docker-compose -f docker-compose.single-node.yml up -d

# Check logs
docker-compose -f docker-compose.single-node.yml logs -f
```

#### Option B: Multi-Master (Production)

```bash
# Copy environment templates
cp .env.multi-master-node1 .env.node1
cp .env.multi-master-node2 .env.node2
cp .env.multi-master-node3 .env.node3

# Edit configurations
nano .env.node1
nano .env.node2
nano .env.node3

# Start cluster
docker-compose -f docker-compose.multi-master.yml up -d

# Verify replication
docker exec ldap-node1 ldapsearch -x -b "dc=example,dc=com" -LLL dn
docker exec ldap-node2 ldapsearch -x -b "dc=example,dc=com" -LLL dn
docker exec ldap-node3 ldapsearch -x -b "dc=example,dc=com" -LLL dn
```

### 3. Load Sample Data (Optional)

```bash
# Using ldapadd
docker exec openldap-single ldapadd -x -D "cn=Manager,dc=example,dc=com" -w admin123 -f /data/sample.ldif

# Or copy from host
cat sample_data.ldif | docker exec -i openldap-single ldapadd -x -D "cn=Manager,dc=example,dc=com" -w admin123
```

### 4. Setup Web UI

```bash
cd web

# Configure clusters
nano config.yml

# Start web services
docker-compose up -d

# Access UI
open http://localhost:5173
```

### 5. Configure Web UI Access

1. Open `http://localhost:5173`
2. Click on cluster name
3. Enter admin password when prompted
4. Password is cached for all users

## Verification

### Test LDAP Connection

```bash
# From host
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" -D "cn=Manager,dc=example,dc=com" -w admin123

# From container
docker exec openldap-single ldapsearch -x -b "dc=example,dc=com" -D "cn=Manager,dc=example,dc=com" -w admin123
```

### Test Web UI API

```bash
# Health check
curl http://localhost:8000/api/monitoring/health?cluster=Local%20Single%20Node

# Search entries
curl "http://localhost:8000/api/entries/search?cluster=Local%20Single%20Node&page=1&page_size=10"
```

## Custom Schema Setup

### 1. Create Schema File

```bash
mkdir -p custom-schema
nano custom-schema/MySchema.ldif
```

Example schema:
```ldif
dn: cn=MySchema,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: MySchema
olcAttributeTypes: ( 1.3.6.1.4.1.99999.1.1 NAME 'employeeNumber' 
  EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 SINGLE-VALUE )
olcObjectClasses: ( 1.3.6.1.4.1.99999.2.1 NAME 'Employee' 
  SUP inetOrgPerson STRUCTURAL MAY ( employeeNumber ) )
```

### 2. Mount Schema Directory

Already configured in docker-compose files:
```yaml
volumes:
  - ./custom-schema:/custom-schema:ro
```

### 3. Restart Container

```bash
docker-compose -f docker-compose.single-node.yml restart
```

Schema is automatically loaded on startup.

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker-compose logs openldap-single

# Check permissions
ls -la logs/
chmod 755 logs/

# Remove volumes and restart
docker-compose down -v
docker-compose up -d
```

### Can't Connect to LDAP

```bash
# Check if port is open
netstat -an | grep 389

# Check container network
docker network inspect openldap_ldap-network

# Test from container
docker exec openldap-single ldapwhoami -x -D "cn=Manager,dc=example,dc=com" -w admin123
```

### Web UI Can't Connect

```bash
# Check backend logs
docker-compose -f web/docker-compose.yml logs ldap-manager

# Verify config.yml
cat web/config.yml

# Test backend directly
curl http://localhost:8000/api/monitoring/health?cluster=Local%20Single%20Node
```

### Password Cache Issues

```bash
# Clear cache
rm -rf web/backend/.cache/

# Restart web service
docker-compose -f web/docker-compose.yml restart
```

## Production Deployment

### 1. Security Hardening

```bash
# Change default passwords
nano .env
# Set strong LDAP_ADMIN_PASSWORD and LDAP_CONFIG_PASSWORD

# Enable TLS (add to .env)
echo "LDAP_TLS_ENABLED=true" >> .env
echo "LDAP_TLS_CERT_FILE=/certs/server.crt" >> .env
echo "LDAP_TLS_KEY_FILE=/certs/server.key" >> .env
```

### 2. Backup Configuration

```bash
# Backup LDAP data
docker exec openldap-single slapcat -n 2 > backup-$(date +%Y%m%d).ldif

# Backup config
docker exec openldap-single slapcat -n 0 > config-backup-$(date +%Y%m%d).ldif
```

### 3. Monitoring Setup

```bash
# Enable monitoring in .env
echo "ENABLE_MONITORING=true" >> .env

# Access cn=Monitor
docker exec openldap-single ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=Monitor"
```

### 4. Log Rotation

```bash
# Setup logrotate on host
sudo cp logrotate.conf /etc/logrotate.d/openldap

# Test rotation
sudo logrotate -f /etc/logrotate.d/openldap
```

## Next Steps

- Read [Activity Logs Documentation](docs/ACTIVITY_LOGS.md)
- Review [Monitoring Guide](docs/MONITORING.md)
- Explore [Use Cases](use-cases/)
- Configure [Multi-Master Replication](docs/REPLICATION.md)
