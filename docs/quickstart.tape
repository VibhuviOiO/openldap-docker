# Renders docs/openldap-quickstart.gif
#
#   vhs docs/quickstart.tape
#
# Commands only - no echo, no banners. A real session does not type headings,
# and the output identifies each step well enough on its own.

Output docs/openldap-quickstart.gif

Set Shell "zsh"
Set FontFamily "JetBrains Mono, Menlo, monospace"
Set FontSize 15
Set LineHeight 1.45
Set LetterSpacing 0
Set TypingSpeed 30ms
Set CursorBlink true

Set Width 1200
Set Height 680
Set Padding 24
Set Margin 40
Set MarginFill "#21222c"
Set WindowBar "Colorful"
Set WindowBarSize 40

Set Theme "Dracula"
Set PlaybackSpeed 1.0

Require docker

# Clear any previous container off camera.
Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1; clear"
Enter
Sleep 1s
Show

Type "docker run -d --name openldap-demo \\"
Enter
Sleep 250ms
Type "  -e LDAP_DOMAIN=example.com \\"
Enter
Sleep 250ms
Type "  -e LDAP_ORGANIZATION='Example Org' \\"
Enter
Sleep 250ms
Type "  -e LDAP_ADMIN_PASSWORD='ChangeMe_StrongP@ssw0rd123!' \\"
Enter
Sleep 250ms
Type "  -e LDAP_CONFIG_PASSWORD='ChangeMe_StrongP@ssw0rd123!' \\"
Enter
Sleep 250ms
Type "  -e INCLUDE_SCHEMAS=cosine,inetorgperson,nis \\"
Enter
Sleep 250ms
Type "  -p 127.0.0.1:16389:389 \\"
Enter
Sleep 250ms
Type "  vibhuvioio/openldap:2.6.10"
Enter
Sleep 25s

Type "docker exec openldap-demo ldapsearch -LLL -Y EXTERNAL -H ldapi:/// \\"
Enter
Sleep 250ms
Type "  -b cn=schema,cn=config dn | grep '^dn:'"
Enter
Sleep 7s

Type "docker exec -i openldap-demo ldapadd -x -H ldap://localhost \\"
Enter
Sleep 250ms
Type "  -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' <<'LDIF'"
Enter
Sleep 500ms
Type "dn: uid=asmith,dc=example,dc=com"
Enter
Sleep 200ms
Type "objectClass: inetOrgPerson"
Enter
Sleep 200ms
Type "uid: asmith"
Enter
Sleep 200ms
Type "cn: Alice Smith"
Enter
Sleep 200ms
Type "sn: Smith"
Enter
Sleep 200ms
Type "mail: alice@example.com"
Enter
Sleep 200ms
Type "LDIF"
Enter
Sleep 6s

Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost \\"
Enter
Sleep 250ms
Type "  -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' \\"
Enter
Sleep 250ms
Type "  -b 'dc=example,dc=com' '(uid=asmith)' dn cn mail"
Enter
Sleep 7s

Type "docker exec openldap-demo ldapdelete -x -H ldap://localhost \\"
Enter
Sleep 250ms
Type "  -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' \\"
Enter
Sleep 250ms
Type "  'uid=asmith,dc=example,dc=com'"
Enter
Sleep 4s

Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost \\"
Enter
Sleep 250ms
Type "  -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' \\"
Enter
Sleep 250ms
Type "  -b 'dc=example,dc=com' '(uid=asmith)' dn | grep -c '^dn:'"
Enter
Sleep 5s

Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1"
Enter
Sleep 1s
Show
