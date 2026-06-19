FROM almalinux:9.7
ARG OPENLDAP_VERSION=""
LABEL org.opencontainers.image.title="OpenLDAP"
LABEL org.opencontainers.image.description="Production-ready OpenLDAP container with multi-master replication, TLS support, and enterprise features"
LABEL org.opencontainers.image.source="https://github.com/vibhuvioio/openldap-docker"
LABEL org.opencontainers.image.vendor="VibhuviOiO"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="${OPENLDAP_VERSION}"

RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --nodocs \
        openldap \
        openldap-clients \
        openldap-servers \
        logrotate \
    && dnf clean all \
    && rm -rf /var/cache/dnf/*
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
        /tmp/ldap-init/ldif \
    && chown -R ldap:ldap \
        /var/lib/ldap \
        /etc/openldap/slapd.d \
        /var/run/openldap \
        /usr/local/bin/ldif/generated \
        /tmp/ldap-init/ldif \
    && chmod 750 /var/lib/ldap \
    && chmod 755 /etc/openldap/slapd.d \
    && chmod 755 /usr/local/bin/ldif/templates /usr/local/bin/ldif/generated /tmp/ldap-init /tmp/ldap-init/ldif
COPY --chown=root:root --chmod=644 ldif/templates/*.ldif /usr/local/bin/ldif/templates/
COPY --chown=root:root --chmod=755 scripts/*.sh /usr/local/bin/scripts/
COPY --chown=root:root --chmod=755 startup.sh /usr/local/bin/
EXPOSE 389 636
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=30s \
            --retries=3 \
    CMD /usr/local/bin/scripts/healthcheck.sh basic || exit 1
STOPSIGNAL SIGTERM
CMD ["/usr/local/bin/startup.sh"]
