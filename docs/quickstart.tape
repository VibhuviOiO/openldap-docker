Output docs/openldap-quickstart.gif

Set Shell "zsh"
Set FontFamily "JetBrains Mono, Menlo, monospace"
Set FontSize 15
Set TypingSpeed 20ms
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

# Prepare the container without recording setup
Hide
Type "docker rm -f openldap-demo >/dev/null 2>&1"
Enter
Type "docker run -d --name openldap-demo -e LDAP_DOMAIN=example.com -e LDAP_ORGANIZATION='Example Org' -e LDAP_ADMIN_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -e LDAP_CONFIG_PASSWORD='ChangeMe_StrongP@ssw0rd123!' -p 127.0.0.1:16389:389 vibhuvioio/openldap:2.6.10"
Enter
Sleep 40s
Type "clear"
Enter
Show

# Step 1: heading only; no echo command shown
Type "clear"
Enter
Type "printf '\\033[1;36mOpenLDAP — Container Status\\033[0m\\n'"
Enter
Type "docker ps --filter name=openldap-demo --format 'Status: {{.Status}}'"
Enter
Sleep 3s

# Step 2: hide the command, show its output
Hide
Type "docker logs openldap-demo 2>&1 | tail -n 8"
Enter
Sleep 2s
Show
Sleep 3s