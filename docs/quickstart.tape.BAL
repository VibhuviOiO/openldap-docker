Output docs/openldap-quickstart.gif

# --- Type ---
Set Shell "zsh"
Set FontFamily "JetBrains Mono, Menlo, monospace"
Set FontSize 15
Set LineHeight 1.45
Set LetterSpacing 0
Set TypingSpeed 20ms
Set CursorBlink true

# --- Frame ---
# A window bar over a margin reads as an application window rather than a
# raw terminal dump. BorderRadius is not a vhs 0.12 setting - don't add it.
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

Type "docker rm -f openldap-demo >/dev/null 2>&1; docker run -d --name openldap-demo -e LDAP_DOMAIN=example.com -e LDAP_ORGANIZATION='Example Org' -e LDAP_ADMIN_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -e INCLUDE_SCHEMAS=cosine,inetorgperson,nis -e LDAP_CONFIG_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -p 127.0.0.1:16389:389 vibhuvioio/openldap:2.6.10"
Enter
Sleep 55s
# Coloured rule between tasks, so each step reads as a section.
Type "banner() { printf '\\n\\033[1;36m━━━  %s\\033[0m\\n\\n' $*; }"
Enter
Type "PROMPT='%F{cyan}❯%f '"
Enter
Type "clear"
Enter
Sleep 2s
Show

Type "banner '1 · OpenLDAP started'"
Enter
Sleep 800ms
Type "docker logs openldap-demo 2>&1 | tail -n 12"
Enter
Sleep 4s

Type "banner '2 · Schemas loaded at boot'"
Enter
Sleep 800ms
Type "docker exec openldap-demo ldapsearch -LLL -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config dn | grep '^dn:'"
Enter
Sleep 5s

Type "banner '3 · Create a record'"
Enter
Sleep 800ms
Type "docker exec -i openldap-demo sh -c 'cat > /tmp/alice.ldif' <<'EOF'"
Enter
Type "dn: uid=asmith,dc=example,dc=com"
Enter
Type "objectClass: inetOrgPerson"
Enter
Type "uid: asmith"
Enter
Type "cn: Alice Smith"
Enter
Type "sn: Smith"
Enter
Type "mail: alice@example.com"
Enter
Type "EOF"
Enter
Sleep 2s
Type "docker exec openldap-demo ldapadd -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' -f /tmp/alice.ldif"
Enter
Sleep 4s

Type "banner '4 · Find her'"
Enter
Sleep 800ms
Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' -b 'dc=example,dc=com' '(uid=asmith)' dn cn mail"
Enter
Sleep 5s

Type "banner '5 · Delete, then prove it is gone'"
Enter
Sleep 800ms
Type "docker exec openldap-demo ldapdelete -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' 'uid=asmith,dc=example,dc=com'"
Enter
Sleep 3s
Type "docker exec openldap-demo ldapsearch -LLL -x -H ldap://localhost -D 'cn=Manager,dc=example,dc=com' -w 'ChangeMe_StrongP@ssw0rd123!' -b 'dc=example,dc=com' '(uid=asmith)' dn | grep -c '^dn:'"
Enter
Sleep 4s

Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1"
Enter
Sleep 1s
Show
