# Vibhuvioio.com Single Node LDAP

Complete LDAP setup with Mahabharata characters for vibhuvioio.com domain.

## Quick Start

```bash
# Start LDAP (data loads automatically)
docker-compose up -d

# Wait 45 seconds for initialization
sleep 45
```

## Verify

```bash
# Check user count (should be 20)
docker exec openldap-vibhuvioio ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvioio,dc=com" \
  -D "cn=Manager,dc=vibhuvioio,dc=com" -w "changeme" \
  "(objectClass=inetOrgPerson)" dn 2>/dev/null | grep "^dn:" | wc -l

# List all users
docker exec openldap-vibhuvioio ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvioio,dc=com" \
  -D "cn=Manager,dc=vibhuvioio,dc=com" -w "changeme" \
  "(objectClass=inetOrgPerson)" uid cn
```

## Data

### Users (20)
- **Pandavas (5)**: arjuna, bhima, yudhishthira, nakula, sahadeva
- **Kauravas (3)**: duryodhana, dushasana, karna
- **Advisors/Elders (3)**: krishna, bhishma, drona
- **Warriors (3)**: abhimanyu, ashwatthama, kripacharya
- **Royalty (3)**: draupadi, kunti, gandhari
- **Leaders (3)**: vidura, shakuni, dhritarashtra

### Groups (5)
- **Pandavas** (10 members)
- **Kauravas** (10 members)
- **Warriors** (13 members)
- **Administrators** (9 members)
- **Advisors** (3 members)

### Custom Schema
- **MahabharataUser** objectClass with attributes:
  - kingdom, weapon, role, allegiance, isWarrior, isAdmin

## Configuration

- **Domain**: vibhuvioio.com
- **Port**: 389 (LDAP), 636 (LDAPS)
- **Admin DN**: cn=Manager,dc=vibhuvioio,dc=com
- **Admin Password**: changeme
- **Base DN**: dc=vibhuvioio,dc=com

## Cleanup

```bash
# Stop and remove all data
docker-compose down -v
```
