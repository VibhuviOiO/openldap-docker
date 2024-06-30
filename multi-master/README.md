ldapmodify -Y EXTERNAL -H ldapi:/// -f /ldifs/syncprov.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f /ldifs/syncrepl-master.ldif

docker exec -it openldap2 ldapmodify -Y EXTERNAL -H ldapi:/// -f /ldifs/syncprov.ldif
docker exec -it openldap2 ldapmodify -Y EXTERNAL -H ldapi:/// -f /ldifs/syncrepl-master.ldif
