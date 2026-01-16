# Activity Log Quick Reference

## Log Location
- **File**: `./logs/slapd-YYYY-MM-DD.log`
- **Today's log**: `./logs/slapd-$(date +%Y-%m-%d).log`

## What Gets Logged

### Connection Events
```
conn=1000 fd=14 ACCEPT from IP=127.0.0.1:36404
conn=1000 fd=14 closed
```
- Shows who connected and from which IP

### Authentication (BIND)
```
conn=1000 op=0 BIND dn="cn=Manager,dc=example,dc=com" method=128
conn=1000 op=0 RESULT tag=97 err=0
```
- `err=0` = success
- `err=49` = invalid credentials (failed login)

### Search Operations
```
conn=1000 op=1 SRCH base="dc=example,dc=com" scope=2 filter="(uid=jdoe)"
conn=1000 op=1 SEARCH RESULT tag=101 err=0 nentries=4
```
- Shows what was searched and how many results returned

### Add Operations
```
conn=1002 op=1 ADD dn="uid=jdoe,ou=People,dc=example,dc=com"
conn=1002 op=1 RESULT tag=105 err=0
```
- Logs new entry creation

### Modify Operations
```
conn=1003 op=1 MOD dn="uid=jdoe,ou=People,dc=example,dc=com"
conn=1003 op=1 RESULT tag=103 err=0
```
- Logs entry updates

### Delete Operations
```
conn=1004 op=1 DEL dn="uid=jdoe,ou=People,dc=example,dc=com"
conn=1004 op=1 RESULT tag=107 err=0
```
- Logs entry deletions

## Useful Commands

### View live activity
```bash
tail -f logs/slapd-$(date +%Y-%m-%d).log
```

### Find failed logins
```bash
grep "err=49" logs/slapd-*.log
```

### Find who searched for specific user
```bash
grep "uid=jdoe" logs/slapd-*.log
```

### Count operations by type
```bash
grep -c "BIND" logs/slapd-2026-01-16.log
grep -c "SEARCH" logs/slapd-2026-01-16.log
grep -c "ADD" logs/slapd-2026-01-16.log
grep -c "MOD" logs/slapd-2026-01-16.log
grep -c "DEL" logs/slapd-2026-01-16.log
```

### Find activity from specific IP
```bash
grep "IP=192.168.1.100" logs/slapd-*.log
```

### See all operations by a specific user
```bash
grep "BIND dn=\"uid=jdoe" logs/slapd-*.log
```

## Log Rotation

Logs are automatically rotated daily by filename. Clean up old logs:
```bash
./cleanup-logs.sh  # Removes logs older than 7 days
```

## Performance Metrics

Each operation shows timing:
- `qtime` = queue time
- `etime` = execution time (in seconds)
- `nentries` = number of results returned

Example:
```
SEARCH RESULT tag=101 err=0 qtime=0.000048 etime=0.000869 nentries=1
```
This search took 0.869ms and returned 1 entry.
