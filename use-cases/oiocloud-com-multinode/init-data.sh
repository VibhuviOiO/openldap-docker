#!/bin/bash
set -e

# Wait for LDAP to be ready
sleep 5

# Check if data already loaded
if ldapsearch -x -b "uid=john.ceo,ou=People,dc=oiocloud,dc=com" -LLL 2>/dev/null | grep -q "uid: john.ceo"; then
    echo "Data already loaded"
    exit 0
fi

# Load data
ldapadd -x -D "cn=Manager,dc=oiocloud,dc=com" -w changeme << 'EOF'
dn: uid=john.ceo,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: john.ceo
cn: John Anderson
sn: Anderson
mail: john.anderson@oiocloud.com
title: CEO
uidNumber: 3001
gidNumber: 100
homeDirectory: /home/john.ceo
userPassword: password123

dn: uid=sarah.cto,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: sarah.cto
cn: Sarah Martinez
sn: Martinez
mail: sarah.martinez@oiocloud.com
title: CTO
uidNumber: 3002
gidNumber: 100
homeDirectory: /home/sarah.cto
userPassword: password123

dn: uid=mike.eng,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: mike.eng
cn: Mike Thompson
sn: Thompson
mail: mike.thompson@oiocloud.com
title: Engineering Director
uidNumber: 3003
gidNumber: 100
homeDirectory: /home/mike.eng
userPassword: password123

dn: uid=lisa.dev,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: lisa.dev
cn: Lisa Chen
sn: Chen
mail: lisa.chen@oiocloud.com
title: Senior Software Engineer
uidNumber: 3004
gidNumber: 100
homeDirectory: /home/lisa.dev
userPassword: password123

dn: uid=tom.dev,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: tom.dev
cn: Tom Wilson
sn: Wilson
mail: tom.wilson@oiocloud.com
title: Software Engineer
uidNumber: 3005
gidNumber: 100
homeDirectory: /home/tom.dev
userPassword: password123

dn: uid=anna.pm,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: anna.pm
cn: Anna Rodriguez
sn: Rodriguez
mail: anna.rodriguez@oiocloud.com
title: Product Manager
uidNumber: 3006
gidNumber: 100
homeDirectory: /home/anna.pm
userPassword: password123

dn: uid=robert.sales,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: robert.sales
cn: Robert Lee
sn: Lee
mail: robert.lee@oiocloud.com
title: VP of Sales
uidNumber: 3007
gidNumber: 100
homeDirectory: /home/robert.sales
userPassword: password123

dn: uid=jennifer.ae,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: jennifer.ae
cn: Jennifer Taylor
sn: Taylor
mail: jennifer.taylor@oiocloud.com
title: Account Executive
uidNumber: 3008
gidNumber: 100
homeDirectory: /home/jennifer.ae
userPassword: password123

dn: uid=david.mkt,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: david.mkt
cn: David Kim
sn: Kim
mail: david.kim@oiocloud.com
title: Marketing Director
uidNumber: 3009
gidNumber: 100
homeDirectory: /home/david.mkt
userPassword: password123

dn: uid=emily.hr,ou=People,dc=oiocloud,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
uid: emily.hr
cn: Emily White
sn: White
mail: emily.white@oiocloud.com
title: HR Manager
uidNumber: 3010
gidNumber: 100
homeDirectory: /home/emily.hr
userPassword: password123
EOF

echo "Data loaded successfully"
