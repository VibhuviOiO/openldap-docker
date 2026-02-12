FROM almalinux:9

# Install OpenLDAP packages (requires CRB repo)
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --nodocs \
        openldap \
        openldap-clients \
        openldap-servers \
        logrotate \
    && dnf clean all \
    && rm -rf /var/cache/dnf/*

# Create directories with proper permissions
RUN mkdir -p \
        /var/lib/ldap \
        /etc/openldap/slapd.d \
        /var/run/openldap \
        /logs \
        /custom-schema \
        /docker-entrypoint-initdb.d \
        /usr/local/bin/scripts \
        /usr/local/bin/ldif/templates \
        /usr/local/bin/ldif/generated \
        /tmp/ldap-init \
    && chown -R ldap:ldap \
        /var/lib/ldap \
        /etc/openldap/slapd.d \
        /var/run/openldap \
        /usr/local/bin/ldif/generated \
        /tmp/ldap-init \
    && chmod 750 /var/lib/ldap /etc/openldap/slapd.d \
    && chmod 755 /usr/local/bin/ldif/templates /usr/local/bin/ldif/generated /tmp/ldap-init

# Copy LDIF templates (read-only, owned by root)
COPY --chown=root:root --chmod=644 ldif/templates/*.ldif /usr/local/bin/ldif/templates/

# Copy scripts (owned by root, executable)
COPY --chown=root:root --chmod=755 scripts/*.sh /usr/local/bin/scripts/
COPY --chown=root:root --chmod=755 startup.sh /usr/local/bin/

# Expose LDAP ports
EXPOSE 389 636

# Health check (runs as root, but script switches to ldap)
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=30s \
            --retries=3 \
    CMD /usr/local/bin/scripts/healthcheck.sh basic || exit 1

# Run as root (startup script will drop to ldap user)
CMD ["/usr/local/bin/startup.sh"]
