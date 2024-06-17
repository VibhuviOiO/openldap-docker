 # Install OpenLDAP on a Raspberry Pi:
 
**Update and upgrade your system**

```bash
sudo apt-get update
sudo apt-get upgrade
```

**Install OpenLDAP server and client**

```bash
sudo apt-get install slapd ldap-utils

# OUTPUT:
sudo apt-get install slapd ldap-utils
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following packages were automatically installed and are no longer required:
  libraspberrypi0 libwpe-1.0-1 libwpebackend-fdo-1.0-1
Use 'sudo apt autoremove' to remove them.
The following additional packages will be installed:
  libodbc2
Suggested packages:
  libsasl2-modules-gssapi-mit | libsasl2-modules-gssapi-heimdal odbc-postgresql tdsodbc
The following NEW packages will be installed:
  ldap-utils libodbc2 slapd
0 upgraded, 3 newly installed, 0 to remove and 1 not upgraded.
Need to get 1,599 kB of archives.
After this operation, 7,834 kB of additional disk space will be used.
Do you want to continue? [Y/n] y
Get:1 http://deb.debian.org/debian bookworm/main arm64 libodbc2 arm64 2.3.11-2+deb12u1 [132 kB]
Get:2 http://deb.debian.org/debian bookworm/main arm64 slapd arm64 2.5.13+dfsg-5 [1,329 kB]
Get:3 http://deb.debian.org/debian bookworm/main arm64 ldap-utils arm64 2.5.13+dfsg-5 [138 kB]
Fetched 1,599 kB in 1s (1,263 kB/s) 
Preconfiguring packages ...
Selecting previously unselected package libodbc2:arm64.
(Reading database ... 148800 files and directories currently installed.)
Preparing to unpack .../libodbc2_2.3.11-2+deb12u1_arm64.deb ...
Unpacking libodbc2:arm64 (2.3.11-2+deb12u1) ...
Selecting previously unselected package slapd.
Preparing to unpack .../slapd_2.5.13+dfsg-5_arm64.deb ...
Unpacking slapd (2.5.13+dfsg-5) ...
Selecting previously unselected package ldap-utils.
Preparing to unpack .../ldap-utils_2.5.13+dfsg-5_arm64.deb ...
Unpacking ldap-utils (2.5.13+dfsg-5) ...
Setting up ldap-utils (2.5.13+dfsg-5) ...
Setting up libodbc2:arm64 (2.3.11-2+deb12u1) ...
Setting up slapd (2.5.13+dfsg-5) ...
  Creating new user openldap... done.
  Creating initial configuration... done.
  Creating LDAP directory... done.
Processing triggers for man-db (2.11.2-2) ...
Processing triggers for libc-bin (2.36-9+rpt2+deb12u7) ...
```
During installation, you will be prompted to set the admin password. Enter your desired password.
![admin-password](https://github.com/jinnabaalu/openldap-tutorial/blob/main/screenshots/admin-password.png)
![confirm password](https://github.com/jinnabaalu/openldap-tutorial/blob/main/screenshots/confirm-password.png)



If the configuration prompt doesn't appear, reconfigure using:
```bash
sudo dpkg-reconfigure slapd
```

#### Start and check the status

```bash
sudo systemctl start slapd
sudo systemctl status slapd
```
#### Initialise the LDAP directory

Generate the password hash then use in init `ldif`

```bash
 slappasswd -s changeme 
{SSHA}JZh7YlO68Y2zhTGHPj7vgE8sGEYmDpCx
```

Create an LDIF file `init.ldif` with your directory structure. 

```ldif
dn: dc=jinnabalu,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: JinnaBalu Inc
dc: jinnabalu

dn: cn=admin,dc=jinnabalu,dc=com
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: Directory Manager
userPassword: {SSHA}JZh7YlO68Y2zhTGHPj7vgE8sGEYmDpCx
```

**Add**

```bash
sudo ldapadd -x -D cn=admin,dc=jinnabalu,dc=com -W -f init.ldif
```

**Search** : Verify the above records updated
```bash
ldapsearch -x -LLL -b dc=jinnabalu,dc=com

# OUTPUT:
dn: dc=jinnabalu,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: JinnaBalu Inc
dc: jinnabalu
```

**Enable**
Set up LDAP to start on boot:
```bash
sudo systemctl enable slapd
```
This concludes the OpenLDAP server is now runing on your host
