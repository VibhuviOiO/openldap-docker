# Logging and Log Management

## Overview

OpenLDAP Docker deployment includes comprehensive logging with multiple output destinations and configurable log levels.

## Log Locations

### Container Logs
- **Docker stdout/stderr**: `docker logs <container-name>`
- **Internal log file**: `/logs/slapd.log` (mounted volume)
- **Host volume**: `ldap-logs` or `ldap-logs-node*`

### Access Logs

```bash
# View live logs
docker logs -f openldap-single

# View last 100 lines
docker logs --tail 100 openldap-single

# View logs with timestamps
docker logs -t openldap-single

# View logs from specific time
docker logs --since 2024-01-01T00:00:00 openldap-single
```

## Log Levels

Configure via `LDAP_LOG_LEVEL` environment variable:

| Level | Value | Description |
|-------|-------|-------------|
| None | 0 | No logging |
| Trace | 1 | Trace function calls |
| Packets | 2 | Debug packet handling |
| Args | 4 | Heavy trace debugging |
| Conns | 8 | Connection management |
| BER | 16 | Print packets sent/received |
| Filter | 32 | Search filter processing |
| Config | 64 | Configuration processing |
| ACL | 128 | Access control list processing |
| Stats | 256 | **Default - Stats logging** |
| Stats2 | 512 | Stats log connections/operations/results |
| Shell | 1024 | Print communication with shell backends |
| Parse | 2048 | Print entry parsing debug |
| Sync | 16384 | Syncrepl consumer processing |
| None | 32768 | Only messages that get logged whatever log level is set |

### Common Combinations

```bash
# Production (recommended)
LDAP_LOG_LEVEL=256          # Stats only

# Debug replication
LDAP_LOG_LEVEL=16640        # Stats (256) + Sync (16384)

# Full debugging
LDAP_LOG_LEVEL=32767        # All levels

# Minimal
LDAP_LOG_LEVEL=0            # No logging
```

## Log Management Strategies

### 1. Docker Logging Driver

**JSON File (Default)**
```yaml
services:
  openldap:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

**Syslog**
```yaml
services:
  openldap:
    logging:
      driver: "syslog"
      options:
        syslog-address: "tcp://192.168.0.42:514"
        tag: "openldap"
```

**Fluentd**
```yaml
services:
  openldap:
    logging:
      driver: "fluentd"
      options:
        fluentd-address: "localhost:24224"
        tag: "openldap.{{.Name}}"
```

### 2. Log Rotation (Host Volume)

**Using logrotate:**

Create `/etc/logrotate.d/openldap-docker`:
```bash
/var/lib/docker/volumes/docker-openldap_ldap-logs/_data/slapd.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 ldap ldap
    postrotate
        docker exec openldap-single kill -USR1 $(docker exec openldap-single pgrep slapd)
    endscript
}
```

### 3. Centralized Logging

**ELK Stack Integration:**

```yaml
services:
  openldap:
    logging:
      driver: "gelf"
      options:
        gelf-address: "udp://logstash:12201"
        tag: "openldap"
```

**Promtail + Loki:**

```yaml
services:
  openldap:
    labels:
      logging: "promtail"
      logging_jobname: "openldap"
```

## Monitoring Logs

### Real-time Monitoring

```bash
# Follow all nodes
docker-compose -f docker-compose.multi-master.yml logs -f

# Follow specific node
docker logs -f ldap-node1

# Filter by pattern
docker logs ldap-node1 2>&1 | grep -i error

# Watch for replication issues
docker logs -f ldap-node1 2>&1 | grep -i "sync\|repl"
```

### Log Analysis

```bash
# Count operations
docker logs openldap-single 2>&1 | grep "RESULT" | wc -l

# Find failed operations
docker logs openldap-single 2>&1 | grep "err=[^0]"

# Check connection count
docker logs openldap-single 2>&1 | grep "ACCEPT" | wc -l

# Analyze slow queries
docker logs openldap-single 2>&1 | grep "etime=" | awk '{print $NF}' | sort -n
```

### Export Logs

```bash
# Export to file
docker logs openldap-single > openldap-$(date +%Y%m%d).log

# Export with timestamps
docker logs -t openldap-single > openldap-$(date +%Y%m%d).log

# Export specific time range
docker logs --since "2024-01-01T00:00:00" --until "2024-01-02T00:00:00" openldap-single > logs.txt
```

## Log Parsing Examples

### Parse Connection Info
```bash
docker logs openldap-single 2>&1 | \
  grep "ACCEPT" | \
  awk '{print $10}' | \
  sort | uniq -c | sort -rn
```

### Parse Operation Types
```bash
docker logs openldap-single 2>&1 | \
  grep "op=" | \
  awk '{for(i=1;i<=NF;i++) if($i~/^op=/) print $i}' | \
  cut -d'=' -f2 | \
  sort | uniq -c
```

### Parse Error Codes
```bash
docker logs openldap-single 2>&1 | \
  grep "err=" | \
  awk '{for(i=1;i<=NF;i++) if($i~/^err=/) print $i}' | \
  sort | uniq -c
```

## Troubleshooting with Logs

### Replication Issues
```bash
# Check sync status
docker logs ldap-node1 2>&1 | grep -i "syncrepl"

# Check for replication errors
docker logs ldap-node1 2>&1 | grep -E "rid=[0-9]+" | grep "err="
```

### Performance Issues
```bash
# Find slow operations (>1 second)
docker logs openldap-single 2>&1 | \
  grep "etime=" | \
  awk '{for(i=1;i<=NF;i++) if($i~/etime=/) print $0}' | \
  awk '{for(i=1;i<=NF;i++) if($i~/etime=/) if(substr($i,7)+0>1) print $0}'
```

### Authentication Issues
```bash
# Check bind failures
docker logs openldap-single 2>&1 | grep "BIND" | grep "err=[^0]"

# Check invalid credentials
docker logs openldap-single 2>&1 | grep "err=49"
```

## Production Logging Setup

### Recommended Configuration

```yaml
services:
  openldap:
    environment:
      - LDAP_LOG_LEVEL=256  # Stats only
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
        compress: "true"
    volumes:
      - ldap-logs:/logs
```

### Log Aggregation Script

```bash
#!/bin/bash
# aggregate-logs.sh

DATE=$(date +%Y%m%d)
OUTPUT_DIR="./logs-archive"

mkdir -p "$OUTPUT_DIR"

for node in ldap-node1 ldap-node2 ldap-node3; do
    docker logs "$node" > "$OUTPUT_DIR/${node}-${DATE}.log" 2>&1
    gzip "$OUTPUT_DIR/${node}-${DATE}.log"
done

echo "Logs archived to $OUTPUT_DIR"
```

### Automated Log Cleanup

```bash
#!/bin/bash
# cleanup-old-logs.sh

# Remove logs older than 30 days
find /var/lib/docker/volumes/docker-openldap_ldap-logs-*/_data/ \
  -name "*.log" -mtime +30 -delete

# Remove compressed logs older than 90 days
find ./logs-archive/ -name "*.log.gz" -mtime +90 -delete
```

## Monitoring Integration

### Prometheus Metrics from Logs

Use `mtail` or similar to extract metrics:

```bash
# Example: Count operations per minute
docker logs -f openldap-single 2>&1 | \
  grep "RESULT" | \
  awk '{print strftime("%Y-%m-%d %H:%M")}' | \
  uniq -c
```

### Alerting Rules

```yaml
# Example: Alert on high error rate
- alert: HighLDAPErrorRate
  expr: rate(ldap_errors_total[5m]) > 10
  annotations:
    summary: "High LDAP error rate detected"
```

## Best Practices

1. **Set appropriate log level** - Use 256 (stats) for production
2. **Implement log rotation** - Prevent disk space issues
3. **Centralize logs** - Use ELK, Loki, or similar
4. **Monitor log volume** - Alert on unusual patterns
5. **Archive old logs** - Compress and store for compliance
6. **Parse logs regularly** - Identify issues proactively
7. **Secure log access** - Restrict who can view logs
8. **Test log pipeline** - Ensure logs reach destination

## Common Log Messages

| Message | Meaning | Action |
|---------|---------|--------|
| `err=0` | Success | Normal |
| `err=32` | No such object | Check DN |
| `err=49` | Invalid credentials | Check password |
| `err=50` | Insufficient access | Check ACLs |
| `err=68` | Entry already exists | Check uniqueness |
| `ACCEPT` | New connection | Normal |
| `BIND` | Authentication attempt | Monitor failures |
| `SEARCH` | Search operation | Monitor performance |
| `ADD/MOD/DEL` | Modify operations | Audit trail |

## Log Retention Policy

**Recommended:**
- **Hot logs** (live): 7 days
- **Warm logs** (compressed): 30 days
- **Cold logs** (archived): 90-365 days
- **Compliance logs**: As required by policy

## Resources

- OpenLDAP Admin Guide: https://www.openldap.org/doc/admin24/
- Docker Logging: https://docs.docker.com/config/containers/logging/
- Log levels reference: `man slapd.conf`
