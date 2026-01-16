# Vibhuvioio.com Single Node LDAP

Complete LDAP setup with Mahabharata characters for vibhuvioio.com domain.

## Quick Start

```bash
# Start LDAP
docker-compose up -d

# Wait for initialization
docker logs -f openldap-vibhuvioio
# Wait for "OpenLDAP initialization completed"

# Load custom schema
docker exec openldap-vibhuvioio ldapadd -Y EXTERNAL -H ldapi:/// -f /custom-schema/MahabharataCharacter.ldif

# Load sample data (from host)
ldapadd -x -H ldap://localhost:389 -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -f data/mahabharata_data.ldif

# Or from container
docker cp data/mahabharata_data.ldif openldap-vibhuvioio:/tmp/
docker exec openldap-vibhuvioio ldapadd -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -f /tmp/mahabharata_data.ldif
```

## Verify

```bash
# Count entries
ldapsearch -x -H ldap://localhost:389 -b "dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=*)" dn | grep -c "^dn:"

# List users
ldapsearch -x -H ldap://localhost:389 -b "ou=People,dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=MahabharataUser)" uid cn kingdom role allegiance

# List groups
ldapsearch -x -H ldap://localhost:389 -b "ou=Group,dc=vibhuvioio,dc=com" -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 "(objectClass=groupOfUniqueNames)" cn
```

## Data

### Users (11)
- **Pandavas**: arjuna, bhima, yudhishthira, nakula, sahadeva
- **Kauravas**: duryodhana, dushasana, karna
- **Advisors**: krishna, bhishma, drona

### Groups (5)
- Pandavas, Kauravas, Warriors, Administrators, Advisors

### Custom Attributes
- kingdom, weapon, role, allegiance, isWarrior, isAdmin

## Web UI

Update `../../web/config.yml`:
```yaml
clusters:
  - name: "Vibhuvioio LDAP"
    host: "localhost"
    port: 389
    bind_dn: "cn=Manager,dc=vibhuvioio,dc=com"
```

Password: `admin123`

## Cleanup

```bash
docker-compose down -v
```
