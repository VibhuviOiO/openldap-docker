# Complex LDAP Use-Case Coverage

This deployment covers all complex LDAP patterns from sample_ldap_data.ldif.

## Organizational Units (5 total)
- ✅ `ou=People` - User accounts
- ✅ `ou=Group` - Group memberships
- ✅ `ou=Netgroup` - Network groups
- ✅ `ou=Protocols` - Protocol definitions
- ✅ `ou=Aliases` - Email/system aliases

## User Types (14 users total)

### MahabharataUser (Custom Schema) - 11 users
- Arjuna, Bhima, Yudhishthira, Nakula, Sahadeva (Pandavas)
- Duryodhana, Dushasana, Karna (Kauravas)
- Krishna, Bhishma, Drona (Advisors/Elders)
- **ObjectClasses**: inetOrgPerson + posixAccount + shadowAccount + MahabharataUser
- **Custom Attributes**: kingdom, weapon, role, allegiance, isWarrior, isAdmin

### Legacy Unix Account - 2 users
- Gandhari, Kunti (Queen Mothers)
- **ObjectClasses**: account + posixAccount + shadowAccount (NO inetOrgPerson)
- **Pattern**: Old-style Unix accounts without modern LDAP person attributes

### Standard inetOrgPerson - 1 user
- Vidura (Advisor)
- **ObjectClasses**: inetOrgPerson + posixAccount + shadowAccount (NO custom schema)
- **Pattern**: Standard LDAP user without custom extensions

## Group Types (6 groups total)

### Standard Groups - 5 groups
- Pandavas, Kauravas, Warriors, Administrators, Advisors
- **ObjectClass**: groupOfUniqueNames
- **Pattern**: Normal group memberships with uniqueMember attribute

### Group with Empty Member - 1 group
- Elders
- **ObjectClass**: groupOfUniqueNames
- **Pattern**: Has `uniqueMember:` (empty) + actual members
- **Purpose**: Tests LDAP clients handling of empty attribute values

## Special Objects

### NIS Map - 1 object
- `nisMapName=netgroup.byhost`
- **ObjectClass**: nisMap
- **Purpose**: Network Information Service mapping for host-based netgroups

## Total Entries: 28
- 1 base DN (dc=vibhuvioio,dc=com)
- 5 organizational units
- 14 users (11 custom + 2 legacy + 1 standard)
- 6 groups
- 1 nisMap
- 1 cn=Monitor (if enabled)

## Web UI Support
- ✅ Displays MahabharataUser with role/kingdom/allegiance/admin badges
- ✅ Shows "Legacy Unix" badge for account objectClass users
- ✅ Shows "Standard" badge for plain inetOrgPerson users
- ✅ Filters users by all objectClass types (account, inetOrgPerson, posixAccount, MahabharataUser)
- ✅ Displays groups with member counts
- ✅ Shows all organizational units
- ✅ Lists all entry types in "All Entries" view

## Verification Commands

```bash
# Count all entries
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(objectClass=*)" dn | grep "^dn:" | wc -l

# List all OUs
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(objectClass=organizationalUnit)" dn

# List legacy Unix accounts
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(objectClass=account)" dn cn

# List standard inetOrgPerson (without custom schema)
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(&(objectClass=inetOrgPerson)(!(objectClass=MahabharataUser)))" dn cn

# List MahabharataUser entries
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(objectClass=MahabharataUser)" dn cn role kingdom

# Check nisMap
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "dc=vibhuvioio,dc=com" "(objectClass=nisMap)" dn nisMapName

# Check group with empty member
docker exec openldap-vibhuvioio ldapsearch -x -D "cn=Manager,dc=vibhuvioio,dc=com" -w admin123 -b "ou=Group,dc=vibhuvioio,dc=com" "(cn=Elders)" uniqueMember
```
