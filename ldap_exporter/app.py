from prometheus_client import start_http_server, Gauge
import ldap
import time
import logging

logging.basicConfig(level=logging.INFO)

ldap_healthy = Gauge('ldap_healthy', 'LDAP server health', ['server'])
ldap_entries_count = Gauge('ldap_entries_count', 'Count of directory entries', ['server'])
ldap_login_failures = Gauge('ldap_login_failures', 'Login failures', ['server'])
ldap_total_logins = Gauge('ldap_total_logins', 'Total logins', ['server'])
ldap_bad_credentials = Gauge('ldap_bad_credentials', 'Total bad credentials / unknown credentials', ['server'])
ldap_syncs_from = Gauge('ldap_syncs_from', 'Syncs from', ['server'])
ldap_last_sync = Gauge('ldap_last_sync', 'Last sync time', ['server'])

LDAP_SERVERS = [
    {"uri": "ldap://localhost:389", "bind_user": "cn=admin,dc=containertalks,dc=com", "bind_password": "adminpassword"}
]
BASE_DN = 'dc=containertalks,dc=com'
USER_FILTER = '(objectClass=person)'
BIND_LOG = './bind_log'

def check_ldap_health(conn, server):
    try:
        conn.search_s(BASE_DN, ldap.SCOPE_BASE)
        ldap_healthy.labels(server=server['uri']).set(1)
        logging.info(f"LDAP health check passed for {server['uri']}")
    except ldap.LDAPError as e:
        ldap_healthy.labels(server=server['uri']).set(0)
        logging.error(f"LDAP health check failed for {server['uri']}: {e}")

def count_directory_entries(conn, server):
    try:
        results = conn.search_s(BASE_DN, ldap.SCOPE_SUBTREE, USER_FILTER)
        ldap_entries_count.labels(server=server['uri']).set(len(results))
        logging.info(f"Directory entries count for {server['uri']}: {len(results)}")
    except ldap.LDAPError as e:
        ldap_entries_count.labels(server=server['uri']).set(0)
        logging.error(f"Failed to count directory entries for {server['uri']}: {e}")

def monitor_login_failures(server):
    try:
        with open(BIND_LOG, 'r') as log_file:
            failures = sum(1 for line in log_file if 'LOGIN_FAILURE' in line and server['uri'] in line)
        ldap_login_failures.labels(server=server['uri']).set(failures)
        logging.info(f"Login failures for {server['uri']}: {failures}")
    except Exception as e:
        ldap_login_failures.labels(server=server['uri']).set(0)
        logging.error(f"Failed to monitor login failures for {server['uri']}: {e}")

def monitor_total_logins(server):
    try:
        # Parse the log file to count total logins
        with open(BIND_LOG, 'r') as log_file:
            logins = sum(1 for line in log_file if 'LOGIN_SUCCESS' in line and server['uri'] in line)
        ldap_total_logins.labels(server=server['uri']).set(logins)
        logging.info(f"Total logins for {server['uri']}: {logins}")
    except Exception as e:
        ldap_total_logins.labels(server=server['uri']).set(0)
        logging.error(f"Failed to monitor total logins for {server['uri']}: {e}")

def monitor_bad_credentials(server):
    try:
        # Parse the log file to count bad credentials
        with open(BIND_LOG, 'r') as log_file:
            bad_credentials = sum(1 for line in log_file if 'BAD_CREDENTIALS' in line and server['uri'] in line)
        ldap_bad_credentials.labels(server=server['uri']).set(bad_credentials)
        logging.info(f"Bad credentials for {server['uri']}: {bad_credentials}")
    except Exception as e:
        ldap_bad_credentials.labels(server=server['uri']).set(0)
        logging.error(f"Failed to monitor bad credentials for {server['uri']}: {e}")

def monitor_syncs_from(conn, server):
    try:
        # Monitor the sync status and last sync time
        results = conn.search_s(BASE_DN, ldap.SCOPE_SUBTREE, '(objectClass=sync)')
        syncs_from = len(results)
        ldap_syncs_from.labels(server=server['uri']).set(syncs_from)
        ldap_last_sync.labels(server=server['uri']).set(time.time())  # Set the current time as the last sync time
        logging.info(f"Syncs from for {server['uri']}: {syncs_from}")
        logging.info(f"Last sync time for {server['uri']}: {time.time()}")
    except ldap.LDAPError as e:
        ldap_syncs_from.labels(server=server['uri']).set(0)
        ldap_last_sync.labels(server=server['uri']).set(0)
        logging.error(f"Failed to monitor syncs for {server['uri']}: {e}")

def create_ldap_connection(server):
    try:
        conn = ldap.initialize(server['uri'])
        conn.simple_bind_s(server['bind_user'], server['bind_password'])
        logging.info(f"LDAP connection established for {server['uri']}")
        return conn
    except ldap.LDAPError as e:
        logging.error(f"LDAP connection failed for {server['uri']}: {e}")
        return None

def main():
    start_http_server(9330)
    connections = {server['uri']: create_ldap_connection(server) for server in LDAP_SERVERS}

    while True:
        for server in LDAP_SERVERS:
            conn = connections.get(server['uri'])
            if conn is None:
                conn = create_ldap_connection(server)
                connections[server['uri']] = conn

            if conn is not None:
                check_ldap_health(conn, server)
                count_directory_entries(conn, server)
                monitor_login_failures(server)
                monitor_total_logins(server)
                monitor_bad_credentials(server)
                monitor_syncs_from(conn, server)
            else:
                ldap_healthy.labels(server=server['uri']).set(0)
        
        time.sleep(60)

if __name__ == '__main__':
    main()
