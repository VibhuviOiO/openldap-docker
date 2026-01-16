from fastapi import APIRouter, Query, HTTPException
from app.core.config import load_config
from app.core.ldap_client import LDAPClient, LDAPConfig
from app.core.password_cache import get_password
from datetime import datetime

router = APIRouter()

@router.get("/activity")
async def get_activity_logs(cluster: str = Query(...)):
    try:
        clusters = load_config()
        cluster_config = next((c for c in clusters if c.name == cluster), None)
        if not cluster_config:
            raise HTTPException(status_code=404, detail="Cluster not found")
        
        password = get_password(cluster, cluster_config.bind_dn)
        if not password:
            raise HTTPException(status_code=401, detail="Password not configured")
        
        host = cluster_config.host or cluster_config.nodes[0]['host']
        port = cluster_config.port or cluster_config.nodes[0]['port']
        
        config = LDAPConfig(
            host=host,
            port=port,
            bind_dn=cluster_config.bind_dn,
            bind_password=password,
            base_dn="cn=Monitor"
        )
        
        client = LDAPClient(config)
        client.connect()
        
        logs = []
        try:
            # Get operations statistics
            ops_base = "cn=Operations,cn=Monitor"
            operations = ["Bind", "Unbind", "Search", "Compare", "Modify", "Add", "Delete"]
            
            for op in operations:
                try:
                    op_results = client.search(f"cn={op},{ops_base}", "(objectClass=*)", attrs=["monitorOpCompleted"])
                    if op_results:
                        count = op_results[0]["attributes"].get("monitorOpCompleted", [b"0"])[0].decode()
                        logs.append({
                            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                            "client": "Statistics",
                            "operation": op.upper(),
                            "dn": f"Completed: {count}",
                            "filter": ""
                        })
                except:
                    pass
            
            if not logs:
                logs.append({
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "client": "System",
                    "operation": "INFO",
                    "dn": "cn=Monitor backend not enabled on this LDAP server",
                    "filter": "Enable monitoring in slapd.conf or cn=config to view activity logs"
                })
            
        except Exception as e:
            logs.append({
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "client": "System",
                "operation": "INFO",
                "dn": "cn=Monitor backend not available",
                "filter": "This LDAP server does not have monitoring enabled"
            })
        
        client.disconnect()
        return {"logs": logs}
    except Exception as e:
        return {
            "logs": [{
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "client": "System",
                "operation": "INFO",
                "dn": "Activity logging unavailable",
                "filter": "cn=Monitor backend must be enabled in LDAP configuration"
            }]
        }

@router.get("/")
async def get_logs():
    return {"logs": [], "message": "Log streaming to be implemented"}
