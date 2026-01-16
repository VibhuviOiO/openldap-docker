# Vibhuvioio LDAP Setup with Mahabharata Characters

## Overview
This setup creates an LDAP server for vibhuvioio.com domain with Mahabharata characters as sample users.

## Quick Start

### 1. Start LDAP Server
```bash
cd oio/docker-openldap
docker-compose -f docker-compose.vibhuvioio.yml up -d
```

### 2. Wait for Initialization
```bash
docker logs -f openldap-vibhuvioio
# Wait for "OpenLDAP initialization completed"
```

### 3. Load Custom Schema
```bash
docker exec openldap-vibhuvioio ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-schema/MahabharataCharacter.ldif
```

### 4. Load Sample Data
```bash
docker exec openldap-vibhuvioio ldapadd -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -f /custom-schema/mahabharata_data.ldif
```

Or from host:
```bash
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -f mahabharata_data.ldif
```

### 5. Verify Data
```bash
# Count entries
docker exec openldap-vibhuvioio ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=*)" dn | grep -c "^dn:"

# List users
docker exec openldap-vibhuvioio ldapsearch -x -H ldap://localhost:389 -b "ou=People,dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=MahabharataUser)" uid cn kingdom role

# List groups
docker exec openldap-vibhuvioio ldapsearch -x -H ldap://localhost:389 -b "ou=Group,dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=groupOfUniqueNames)" cn description
```

## Sample Data

### Users (11 total)
**Pandavas (5):**
- arjuna - Warrior Prince, Admin, Weapon: Gandiva
- bhima - Warrior, Weapon: Mace
- yudhishthira - King, Admin, Weapon: Spear
- nakula - Warrior, Weapon: Sword
- sahadeva - Warrior, Weapon: Sword

**Kauravas (3):**
- duryodhana - Prince, Admin, Weapon: Mace
- dushasana - Warrior, Weapon: Sword
- karna - King of Anga, Admin, Weapon: Vijaya

**Advisors (3):**
- krishna - Advisor, Admin, Weapon: Sudarshana Chakra
- bhishma - Grand Elder, Admin, Weapon: Bow
- drona - Teacher, Weapon: Brahmastra

### Groups (5 total)
- **Pandavas** - 6 members (5 Pandavas + Krishna)
- **Kauravas** - 5 members (Duryodhana, Dushasana, Karna, Bhishma, Drona)
- **Warriors** - 10 members (all warriors)
- **Administrators** - 6 members (users with isAdmin=TRUE)
- **Advisors** - 3 members (Krishna, Bhishma, Drona)

### Custom Attributes
Each MahabharataUser has:
- **kingdom** - Their kingdom (Hastinapura, Anga, Dwaraka)
- **weapon** - Their primary weapon
- **role** - Their role (Warrior, King, Advisor, etc.)
- **allegiance** - Pandavas or Kauravas
- **isWarrior** - TRUE/FALSE
- **isAdmin** - TRUE/FALSE

## Web UI Configuration

Update `web/config.yml`:
```yaml
clusters:
  - name: "Vibhuvioio LDAP"
    host: "localhost"
    port: 389
    bind_dn: "cn=Manager,dc=vibhuvioio,dc=com"
    base_dn: "dc=vibhuvioio,dc=com"
```

Then access the web UI and enter password: `admin123`

## Cleanup

```bash
docker-compose -f docker-compose.vibhuvioio.yml down -v
```

## Testing Queries

### Find all admins
```bash
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(isAdmin=TRUE)" uid cn role
```

### Find all Pandavas
```bash
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(allegiance=Pandavas)" uid cn kingdom
```

### Find warriors with specific weapons
```bash
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(weapon=Bow)" uid cn weapon
```
