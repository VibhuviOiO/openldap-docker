from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.ldap_client import LDAPClient, LDAPConfig
from app.core.password_cache import save_password, get_password
from app.core.config import load_config

router = APIRouter()

class ConnectionRequest(BaseModel):
    cluster_name: str
    bind_password: str

class ConnectionResponse(BaseModel):
    status: str
    message: str
    base_dn: str

@router.post("/connect", response_model=ConnectionResponse)
async def connect(req: ConnectionRequest):
    try:
        clusters = load_config()
        cluster = next((c for c in clusters if c.name == req.cluster_name), None)
        if not cluster:
            raise HTTPException(status_code=404, detail="Cluster not found")
        
        # Use cached password if available, otherwise use provided
        cached_pwd = get_password(req.cluster_name, cluster.bind_dn)
        password = cached_pwd or req.bind_password
        
        if not password:
            raise HTTPException(status_code=400, detail="Password required")
        
        # Connect to first node or single host
        host = cluster.host or cluster.nodes[0]['host']
        port = cluster.port or cluster.nodes[0]['port']
        
        config = LDAPConfig(
            host=host,
            port=port,
            bind_dn=cluster.bind_dn,
            bind_password=password,
            base_dn=cluster.base_dn or ''
        )
        
        client = LDAPClient(config)
        client.connect()
        base_dn = client.config.base_dn
        client.disconnect()
        
        # Save password to cache on successful connection
        if not cached_pwd:
            save_password(req.cluster_name, cluster.bind_dn, password)
        
        return ConnectionResponse(
            status="success",
            message="Connected successfully",
            base_dn=base_dn
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/status")
async def status():
    return {"status": "ready"}
