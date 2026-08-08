# Vibhuvi.com — Single-Node OpenLDAP

## Overview

This use case demonstrates a single-node OpenLDAP deployment for the Vibhuvi Corporation employee directory.

The example contains **28 employee records** representing a global team across **25+ countries** and **8 departments**.

The deployment demonstrates:

* Custom LDAP schema
* Global employee directory
* Department and employee attributes
* LDIF-based data seeding
* Automatic initialization
* Persistent LDAP storage
* LDAP and LDAPS endpoints
* LDAP search and filtering

> This is a single-node deployment. LDAP replication is disabled.

## Features

* **Custom Schema:** `vibhuviEmployee` object class with corporate employee attributes
* **Employees:** 28 sample employee records
* **Countries:** 25+ countries
* **Departments:** 8
* **Auto-initialization:** Employee data is loaded automatically during initial startup
* **Persistence:** LDAP data and configuration are stored in Docker volumes
* **LDAP:** Port `390` on the host
* **LDAPS:** Port `637` on the host

### Employee Attributes

The custom employee schema includes attributes such as:

```text
employeeID
uid
department
jobTitle
hireDate
salary
manager
telephoneNumber
```

## Directory Structure

The LDAP directory uses:

```text
dc=vibhuvi,dc=com
└── ou=People
    ├── Employee records
    └── ...
```

## Employee Data

| Department         | Count | Example Employees                                |
| ------------------ | ----: | ------------------------------------------------ |
| Engineering        |     5 | Akira Tanaka, Maria Garcia, Raj Patel            |
| Sales              |     5 | James O'Connor, Fatima Al-Rashid, Lars Andersson |
| Marketing          |     3 | Emma Thompson, Diego Rodriguez, Aisha Mohammed   |
| HR                 |     3 | Sarah Kim, Michael O'Brien, Priya Sharma         |
| Finance            |     3 | Hans Mueller, Olivia Martin, Ahmed Hassan        |
| IT Operations      |     3 | Nikolai Petrov, Ana Costa, Kwame Osei            |
| Product Management |     3 | Liam Wilson, Mei Lin, Carlos Mendez              |
| Customer Success   |     3 | Zara Khan, Thomas Andersen, Amara Nwosu          |

The sample records represent employees from countries including Japan, Spain, India, France, China, the USA, UAE, Sweden, Brazil, UK, Mexico, Nigeria, South Korea, Ireland, Germany, Australia, Egypt, Russia, Portugal, Ghana, Singapore, Argentina, Pakistan, and Denmark.

## Quick Start

Create the environment file or review

```bash
.env.vibhuvi
```

Review the configuration and change the default credentials before starting the container.

Start OpenLDAP:

```bash
docker compose up -d
```

Follow the initialization logs:

```bash
docker logs -f openldap-vibhuvi
```

The initialization script automatically:

1. Waits for LDAP to become available.
2. Checks whether the employee data already exists.
3. Loads the sample LDIF data when required.
4. Skips loading when the data already exists.

## Verify Employees

After initialization, verify that all 28 employees were loaded:

```bash
docker exec openldap-vibhuvi ldapsearch \
  -x \
  -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" \
  -w changeme \
  "(objectClass=vibhuviEmployee)" \
  dn | grep "^dn:" | wc -l
```

Expected:

```text
28
```

## LDAP Manager

This use case can be accessed through the LDAP Manager application included in the repository.

The corresponding configuration uses:

```yaml
- name: "vibhuvi.com"
  host: "openldap-vibhuvi"
  port: 389
  bind_dn: "cn=Manager,dc=vibhuvi,dc=com"
  base_dn: "dc=vibhuvi,dc=com"
  description: "Vibhuvi Corporation Employee Directory - 28 Global Employees"
```

When the LDAP Manager application is running, it can be accessed at:

```text
http://localhost:5173
```

## Testing

### Search All Employees

```bash
docker exec openldap-vibhuvi ldapsearch \
  -x \
  -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" \
  -w changeme \
  "(objectClass=vibhuviEmployee)"
```

### Search by Department

For example, search for Engineering employees:

```bash
docker exec openldap-vibhuvi ldapsearch \
  -x \
  -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" \
  -w changeme \
  "(department=Engineering)"
```

### Search by Employee ID

```bash
docker exec openldap-vibhuvi ldapsearch \
  -x \
  -H ldap://localhost:389 \
  -b "ou=People,dc=vibhuvi,dc=com" \
  -D "cn=Manager,dc=vibhuvi,dc=com" \
  -w changeme \
  "(employeeID=E001)"
```

## LDAP Authentication

Verify that the LDAP Manager account can authenticate:

```bash
docker exec openldap-vibhuvi ldapwhoami \
  -x \
  -H ldap://localhost:389 \
  -D "cn=Manager,dc=vibhuvi,dc=com" \
  -w changeme
```

Expected:

```text
dn:cn=Manager,dc=vibhuvi,dc=com
```

## Custom Schema

The custom employee schema is located at:

```text
custom-schema/vibhuviEmployee.ldif
```

It defines the `vibhuviEmployee` object class and the corporate employee attributes used by the sample directory.

The schema is mounted into the container during startup:

```yaml
- ./custom-schema:/custom-schema:ro
```

## Data Initialization

The initialization script is:

```text
init/init-data.sh
```

The sample employee data is:

```text
sample/employee_data_global.ldif
```

The LDIF file is mounted into the container as:

```text
/data/employee_data_global.ldif
```

The initialization process is designed to avoid loading the sample data again when the directory already contains the employee records.

## Data Persistence

OpenLDAP uses two Docker volumes:

```text
ldap-data
ldap-config
```

The data survives a normal container restart and:

```bash
docker compose down
```

does not remove these volumes.

To remove the LDAP data and recreate the directory:

```bash
docker compose down -v
```

> **Warning:** `docker compose down -v` permanently removes the LDAP Docker volumes and the directory data stored in them.

## Ports

The example maps the container ports as follows:

| Service | Container Port | Host Port |
| ------- | -------------: | --------: |
| LDAP    |            389 |       390 |
| LDAPS   |            636 |       637 |

Therefore, clients connecting from the host use:

```text
ldap://localhost:390
ldaps://localhost:637
```

Containers connected to the same Docker network should use:

```text
ldap://openldap-vibhuvi:389
```

## Files

```text
vibhuvi-com-singlenode/
├── README.md
├── docker-compose.yml
├── .env.vibhuvi.example
├── custom-schema/
│   └── vibhuviEmployee.ldif
├── sample/
│   └── employee_data_global.ldif
└── init/
    └── init-data.sh
```

### File Description

| File                                 | Purpose                                     |
| ------------------------------------ | ------------------------------------------- |
| `docker-compose.yml`                 | OpenLDAP container and volume configuration |
| `.env.vibhuvi.example`               | Example environment configuration           |
| `custom-schema/vibhuviEmployee.ldif` | Custom employee LDAP schema                 |
| `sample/employee_data_global.ldif`   | Sample employee directory data              |
| `init/init-data.sh`                  | Automatic LDAP initialization               |
| `README.md`                          | Use-case documentation                      |

## Cleanup

Stop the container while keeping LDAP data:

```bash
docker compose down
```

Stop the container and remove LDAP volumes:

```bash
docker compose down -v
```

Start again:

```bash
docker compose up -d
```

## Important

This use case is intended as a **demonstration and development example**.

The sample credentials and employee data should not be used in a production LDAP deployment.

For production deployments:

* Use strong, unique passwords.
* Do not commit `.env.vibhuvi`.
* Enable and properly configure TLS.
* Protect LDAP/LDAPS network access.
* Review LDAP access controls.
* Use appropriate backup and recovery procedures.
* Avoid storing sensitive employee information unless required.
