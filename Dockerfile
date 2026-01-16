FROM almalinux:9

RUN dnf -y update && \
    dnf -y install procps-ng iproute net-tools gettext rsyslog && \
    dnf -y install dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf -y install openldap openldap-clients openldap-servers && \
    dnf clean all

RUN mkdir -p /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap /logs /custom-schema && \
    chown -R ldap:ldap /var/lib/ldap /etc/openldap/slapd.d /var/run/openldap /logs /custom-schema && \
    touch /logs/slapd.log && chown ldap:ldap /logs/slapd.log

COPY startup.sh /usr/local/bin/startup.sh

RUN chmod +x /usr/local/bin/startup.sh

EXPOSE 389 636

CMD ["/usr/local/bin/startup.sh"]
