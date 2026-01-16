# LDAP Activity Logs

## Overview

All LDAP operations (BIND, SEARCH, ADD, MODIFY, DELETE) are logged to track user activity and detect security issues.

## Log Files

Activity logs are stored in `./logs/slapd.log`

Logrotate automatically creates dated archives:
- `slapd.log` - Current log
- `slapd.log-2026-01-16.gz` - Yesterday's log (compressed)
- `slapd.log-2026-01-15.gz` - 2 days ago
- etc.

## Setup

### 1. Update logrotate.conf Path
Edit `logrotate.conf` and replace `/path/to/docker-openldap` with your actual path:
```bash
/absolute/path/to/oio/docker-openldap/logs/slapd.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    dateext
    dateformat -%Y-%m-%d
}
```

### 2. Setup Automatic Rotation
Add to system crontab (run `crontab -e`):
```bash
0 0 * * * cd /absolute/path/to/oio/docker-openldap && ./cleanup-logs.sh
```

This rotates logs daily at midnight UTC.

## Configuration Options

Edit `logrotate.conf` to customize:

| Option | Description | Example |
|--------|-------------|----------|
| `daily` | Rotation frequency | `daily`, `weekly`, `monthly` |
| `rotate 7` | Keep N old logs | `rotate 30` (keep 30 days) |
| `compress` | Compress old logs | Remove to disable |
| `delaycompress` | Don't compress most recent | Remove to compress immediately |
| `copytruncate` | Copy then truncate (no restart) | Required for running services |
| `dateext` | Add date to filename | Creates `slapd.log-2026-01-16` |

## What Gets Logged

### Connection Events
```
conn=1000 fd=14 ACCEPT from IP=127.0.0.1:36404
conn=1000 fd=14 closed
```

### Authentication (BIND)
```
conn=1000 op=0 BIND dn="cn=Manager,dc=example,dc=com" method=128
conn=1000 op=0 RESULT tag=97 err=0
```
- `err=0` = success
- `err=49` = invalid credentials

### Search Operations
```
conn=1000 op=1 SRCH base="dc=example,dc=com" scope=2 filter="(uid=jdoe)"
conn=1000 op=1 SEARCH RESULT tag=101 err=0 nentries=4
```

### Add/Modify/Delete
```
conn=1002 op=1 ADD dn="uid=jdoe,ou=People,dc=example,dc=com"
conn=1003 op=1 MOD dn="uid=jdoe,ou=People,dc=example,dc=com"
conn=1004 op=1 DEL dn="uid=jdoe,ou=People,dc=example,dc=com"
```

## Viewing Logs

### Today's logs (live)
```bash
tail -f logs/slapd.log
```

### Yesterday's logs
```bash
zcat logs/slapd.log-2026-01-16.gz | less
```

### Search across all logs
```bash
zgrep "uid=jdoe" logs/slapd.log*
```

### Find failed logins
```bash
zgrep "err=49" logs/slapd.log*
```

### Count operations
```bash
grep -c "BIND" logs/slapd.log
grep -c "SEARCH" logs/slapd.log
grep -c "ADD" logs/slapd.log
```

## Manual Rotation

Rotate logs immediately:
```bash
./cleanup-logs.sh
```

## Troubleshooting

### Logs not rotating
1. Check crontab is set: `crontab -l`
2. Check path in `logrotate.conf` is absolute
3. Test manually: `./cleanup-logs.sh`
4. Check permissions: `ls -la logs/`

### Disk space issues
Reduce retention in `logrotate.conf`:
```bash
rotate 3  # Keep only 3 days
```

### Need more history
Increase retention:
```bash
rotate 30  # Keep 30 days
```

## No Environment Variables Required

Logging is enabled by default. No additional configuration needed in `.env` files.
