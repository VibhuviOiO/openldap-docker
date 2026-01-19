# Multi-Cluster LDAP Setup - Complete

## One-Time Setup

```bash
cd oio/openldap-docker/use-cases

# Create network
docker network create ldap-shared-network

# Build the base image (only needed once or after Dockerfile changes)
cd ..
docker build -t openldap-custom .
cd use-cases
```

## Start Everything

```bash
# Start all clusters
cd vibhuvioio-com-singlenode && docker-compose up -d && cd ..
cd vibhuvi-com-singlenode && docker-compose up -d && cd ..
cd oiocloud-com-multinode && docker-compose up -d && cd ..

# Start LDAP Manager
docker-compose -f docker-compose.ldap-manager.yml up -d

# Wait for initialization (data loads automatically)
sleep 40
```

## Access

- **LDAP Manager UI**: http://localhost:5173
- **Backend API**: http://localhost:8000/docs

## Clusters

| Cluster | Port | Users | Type |
|---------|------|-------|------|
| vibhuvioio.com | 389 | 11 warriors | Single Node |
| vibhuvi.com | 390 | 5 employees | Single Node |
| oiocloud.com | 391-393 | 10 employees | 3-Node Multi-Master |

## Data Persistence

- Data is stored in Docker volumes
- Survives container restarts
- Only deleted with `docker-compose down -v`

## Stop Everything

```bash
docker-compose -f docker-compose.ldap-manager.yml down
cd oiocloud-com-multinode && docker-compose down && cd ..
cd vibhuvi-com-singlenode && docker-compose down && cd ..
cd vibhuvioio-com-singlenode && docker-compose down && cd ..
```

## Clean Everything (Remove Data)

```bash
docker-compose -f docker-compose.ldap-manager.yml down -v
cd oiocloud-com-multinode && docker-compose down -v && cd ..
cd vibhuvi-com-singlenode && docker-compose down -v && cd ..
cd vibhuvioio-com-singlenode && docker-compose down -v && cd ..
docker network rm ldap-shared-network
```

## Features

✅ Automatic data loading on first start  
✅ Data persists across restarts  
✅ Single shared network for all containers  
✅ Multi-master replication (oiocloud.com)  
✅ Single UI to manage all clusters  
✅ No manual commands needed  

## How It Works

1. **startup.sh** initializes LDAP server
2. **init-data.sh** loads sample data automatically
3. Data only loads once (checks if already exists)
4. Volumes persist data between restarts
