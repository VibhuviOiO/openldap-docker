# Renders docs/openldap-quickstart.gif
#
#   vhs docs/quickstart.tape
#
# One Type per command, one Enter. Do NOT split a command across several
# Type/Enter pairs with a trailing backslash: each Enter submits the line,
# so the shell runs a fragment at a time. The terminal wraps long lines on
# its own, the same way it does for a real user.

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

Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1; clear"
Enter
Sleep 1s
Show

Type "docker run -d --name openldap-demo -e LDAP_DOMAIN=example.com -e LDAP_ORGANIZATION='Example Org' -e LDAP_ADMIN_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -e LDAP_CONFIG_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -e INCLUDE_SCHEMAS=cosine,inetorgperson,nis -p 127.0.0.1:16389:389 vibhuvioio/openldap:2.6.10"
Enter
Sleep 25s

Type "docker exec openldap-demo ldapsearch -LLL -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config dn | grep '^dn:'"
Enter
Sleep 7s

# A heredoc is the one case where several Enters are correct: each one is a
# line of the LDIF, not a separate command.
Type "docker exec -i openldap-demo ldapadd -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' <<'LDIF'"
Enter
Sleep 400ms
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

Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' -b 'dc=example,dc=com' '(uid=asmith)' dn cn mail"
Enter
Sleep 7s

Type "docker exec openldap-demo ldapdelete -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' 'uid=asmith,dc=example,dc=com'"
Enter
Sleep 4s

Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' -b 'dc=example,dc=com' '(uid=asmith)' dn | grep -c '^dn:'"
Enter
Sleep 5s

Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1"
Enter
Sleep 1s
Show
