# Vibhuvi.com - Single Node LDAP Cluster

## Overview
Global employee directory for Vibhuvi Corporation with 28 employees from 25+ countries across 8 departments.

## Features
- **Custom Schema**: vibhuviEmployee objectClass with corporate attributes
- **28 Employees**: Worldwide team from Japan, Spain, India, France, China, USA, UAE, Sweden, Brazil, UK, Mexico, Nigeria, South Korea, Ireland, Germany, Australia, Egypt, Russia, Portugal, Ghana, Singapore, Argentina, Pakistan, Denmark
- **8 Departments**: Engineering, Sales, Marketing, HR, Finance, IT Operations, Product Management, Customer Success
- **Attributes**: employeeID, uid, department, jobTitle, hireDate, salary, manager, telephoneNumber
- **Port**: 390 (LDAP), 637 (LDAPS)
- **Auto-initialization**: Data loads automatically on first start

## Quick Start

```bash
# Start the cluster
docker-compose up -d

# Wait for initialization (data loads automatically)
sleep 50

# Verify 28 employees loaded
docker exec openldap-vibhuvi ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" -w changeme \
  "(objectClass=vibhuviEmployee)" dn | grep "^dn:" | wc -l
```

## Employee Data

| Department | Count | Examples |
|------------|-------|----------|
| Engineering | 5 | Akira Tanaka (Japan), Maria Garcia (Spain), Raj Patel (India) |
| Sales | 5 | James O'Connor (USA), Fatima Al-Rashid (UAE), Lars Andersson (Sweden) |
| Marketing | 3 | Emma Thompson (UK), Diego Rodriguez (Mexico), Aisha Mohammed (Nigeria) |
| HR | 3 | Sarah Kim (South Korea), Michael O'Brien (Ireland), Priya Sharma (India) |
| Finance | 3 | Hans Mueller (Germany), Olivia Martin (Australia), Ahmed Hassan (Egypt) |
| IT Operations | 3 | Nikolai Petrov (Russia), Ana Costa (Portugal), Kwame Osei (Ghana) |
| Product | 3 | Liam Wilson (USA), Mei Lin (Singapore), Carlos Mendez (Argentina) |
| Customer Success | 3 | Zara Khan (Pakistan), Thomas Andersen (Denmark), Amara Nwosu (Nigeria) |

## LDAP Manager Configuration

Already configured in `oio/openldap-docker/use-cases/ldap-manager/config.yml`:

```yaml
- name: "vibhuvi.com"
  host: "openldap-vibhuvi"
  port: 389
  bind_dn: "cn=Manager,dc=vibhuvi,dc=com"
  base_dn: "dc=vibhuvi,dc=com"
  description: "Vibhuvi Corporation Employee Directory - 28 Global Employees"
```

Access UI: http://localhost:5173

## Testing

```bash
# Search all employees
docker exec openldap-vibhuvi ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" -w changeme \
  "(objectClass=vibhuviEmployee)"

# Search by department
docker exec openldap-vibhuvi ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" -w changeme \
  "(department=Engineering)"

# Search by employee ID
docker exec openldap-vibhuvi ldapsearch -x -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" -w changeme \
  "(employeeID=E001)"
```

## Data Persistence

- Data persists in Docker volumes
- Survives container restarts (`docker-compose down` without `-v`)
- Init script checks for existing data and skips reload
- Only deleted with `docker-compose down -v`

## Cleanup

```bash
# Stop but keep data
docker-compose down

# Stop and remove all data
docker-compose down -v
```

## Files

- `custom-schema/vibhuviEmployee.ldif` - Custom LDAP schema
- `sample/employee_data_global.ldif` - 28 employee records
- `init/init-data.sh` - Auto-initialization script
- `.env` - LDAP configuration
- `docker-compose.yml` - Container setup
