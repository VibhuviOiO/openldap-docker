from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List
from app.core.ldap_client import LDAPClient, LDAPConfig
from app.core.config import load_config
from app.core.password_cache import get_password
import ldap
import time

router = APIRouter()

class NodeMetrics(BaseModel):
    host: str
    port: int
    bind_dn: str
    bind_password: str
    base_dn: str

@router.get("/health")
async def get_health(cluster: str = Query(...)):
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
            base_dn=cluster_config.base_dn or ''
        )
        
        client = LDAPClient(config)
        start = time.time()
        client.connect()
        response_time = int((time.time() - start) * 1000)
        
        # Get entry count
        entry_count = client.get_entry_count(client.config.base_dn)
        
        # Get contextCSN
        try:
            csn_results = client.search(client.config.base_dn, "(objectClass=*)", 
                                       scope=ldap.SCOPE_BASE, attrs=["contextCSN"])
            context_csn = csn_results[0]["attributes"].get("contextCSN", [b""])[0].decode() if csn_results else ""
        except:
            context_csn = ""
        
        client.disconnect()
        
        return {
            "status": "healthy",
            "responseTime": f"{response_time}ms",
            "connections": "N/A",
            "operations": entry_count,
            "contextCSN": context_csn
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e)
        }

@router.post("/metrics")
async def get_metrics(req: NodeMetrics):
    try:
        config = LDAPConfig(**req.dict())
        client = LDAPClient(config)
        client.connect()
        
        entry_count = client.get_entry_count(req.base_dn)
        
        # Get contextCSN for replication status
        try:
            csn_results = client.search(req.base_dn, "(objectClass=*)", 
                                       scope=ldap.SCOPE_BASE, attrs=["contextCSN"])
            context_csn = csn_results[0]["attributes"].get("contextCSN", [b""])[0].decode() if csn_results else ""
        except:
            context_csn = ""
        
        client.disconnect()
        
        return {
            "node": req.host,
            "status": "healthy",
            "entry_count": entry_count,
            "contextCSN": context_csn
        }
    except Exception as e:
        return {
            "node": req.host,
            "status": "unhealthy",
            "error": str(e)
        }

@router.post("/cluster")
async def get_cluster_metrics(nodes: List[NodeMetrics]):
    results = []
    for node in nodes:
        metrics = await get_metrics(node)
        results.append(metrics)
    
    in_sync = len(set(r.get("contextCSN") for r in results if r.get("contextCSN"))) <= 1
    
    return {
        "nodes": results,
        "cluster_status": "healthy" if all(r["status"] == "healthy" for r in results) else "degraded",
        "in_sync": in_sync
    }
