import time
import ldap
from prometheus_client import start_http_server, Gauge

# LDAP configuration
LDAP_SERVERS = [
    {"uri": "ldap://localhost:389", "bind_user": "cn=admin,dc=containertalks,dc=com", "bind_password": "binduser"}
]

# Prometheus metrics
ldap_up = Gauge('openldap_up', 'LDAP server health', ['server'])
ldap_entries_count = Gauge('openldap_entries_count', 'Count of directory entries', ['server'])
ldap_bind_failures_total = Gauge('openldap_bind_failures_total', 'Total bind failures', ['server'])
ldap_binds_total = Gauge('openldap_binds_total', 'Total successful binds', ['server'])
ldap_bind_failures_bad_credentials_total = Gauge('openldap_bind_failures_bad_credentials_total', 'Total bad credentials or unknown credentials', ['server'])
ldap_syncrepl_last_sync = Gauge('openldap_syncrepl_last_sync', 'Last sync time', ['server'])
ldap_node_health = Gauge('openldap_node_health', 'Node health', ['server'])

def check_ldap_server(server):
    try:
        conn = ldap.initialize(server['uri'])
        conn.simple_bind_s(server['bind_user'], server['bind_password'])

        # Check the health of the LDAP server
        ldap_up.labels(server=server['uri']).set(1)

        # Count directory entries
        search_base = 'dc=containertalks,dc=com'
        search_filter = '(objectClass=*)'
        result = conn.search_s(search_base, ldap.SCOPE_SUBTREE, search_filter, ['dn'])
        ldap_entries_count.labels(server=server['uri']).set(len(result))

        # Mock values for other metrics (should be replaced with actual log parsing or relevant queries)
        ldap_bind_failures_total.labels(server=server['uri']).set(0)  # Replace with actual bind failures count
        ldap_binds_total.labels(server=server['uri']).set(10)         # Replace with actual successful binds count
        ldap_bind_failures_bad_credentials_total.labels(server=server['uri']).set(0)  # Replace with actual bad credentials count

        # Mock values for sync metrics (should be replaced with actual sync status queries)
        ldap_syncrepl_last_sync.labels(server=server['uri']).set(time.time() - 60)  # Replace with actual last sync time
        ldap_node_health.labels(server=server['uri']).set(1)  # Replace with actual node health status

    except ldap.LDAPError as e:
        print(f"LDAP connection error for {server['uri']}: {e}")
        ldap_up.labels(server=server['uri']).set(0)
    finally:
        conn.unbind_s()

if __name__ == "__main__":
    # Start up the server to expose the metrics.
    start_http_server(9331)
    print("Starting OpenLDAP exporter on port 9330")

    # Generate some requests.
    while True:
        for server in LDAP_SERVERS:
            check_ldap_server(server)
        time.sleep(60)
