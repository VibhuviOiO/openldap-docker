from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import List, Dict, Optional
from app.core.ldap_client import LDAPClient, LDAPConfig
from app.core.config import load_config
from app.core.password_cache import get_password
import ldap

router = APIRouter()

class SearchRequest(BaseModel):
    host: str
    port: int
    bind_dn: str
    bind_password: str
    base_dn: str
    filter: str = "(objectClass=*)"
    attributes: Optional[List[str]] = None

class EntryCreate(BaseModel):
    host: str
    port: int
    bind_dn: str
    bind_password: str
    dn: str
    attributes: Dict

class EntryUpdate(BaseModel):
    host: str
    port: int
    bind_dn: str
    bind_password: str
    dn: str
    changes: Dict

@router.get("/search")
async def search_by_cluster(
    cluster: str = Query(...),
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=10000),
    search: str = Query(None),
    filter_type: str = Query(None)
):
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
        
        # Build LDAP filter
        ldap_filter = "(objectClass=*)"
        if filter_type == "users":
            ldap_filter = "(|(objectClass=inetOrgPerson)(objectClass=posixAccount)(objectClass=account))"
        elif filter_type == "groups":
            ldap_filter = "(|(objectClass=groupOfNames)(objectClass=groupOfUniqueNames)(objectClass=posixGroup))"
        elif filter_type == "ous":
            ldap_filter = "(objectClass=organizationalUnit)"
        
        # Add search filter
        if search:
            search_filter = f"(|(uid=*{search}*)(cn=*{search}*)(mail=*{search}*)(sn=*{search}*))"
            if ldap_filter != "(objectClass=*)":
                ldap_filter = f"(&{ldap_filter}{search_filter})"
            else:
                ldap_filter = search_filter
        
        client = LDAPClient(config)
        client.connect()
        
        # Calculate pagination
        cookie = b''
        skip = (page - 1) * page_size
        
        # For first page, get paginated results
        if page == 1:
            entries, next_cookie, total = client.search(
                client.config.base_dn, ldap_filter, attrs=None,
                page_size=page_size, cookie=cookie
            )
        else:
            # For subsequent pages, need to iterate through pages
            # This is a limitation - LDAP pagination doesn't support random access
            entries, next_cookie, total = client.search(
                client.config.base_dn, ldap_filter, attrs=None,
                page_size=0, cookie=b''
            )
            # Client-side pagination for pages > 1
            start = skip
            end = skip + page_size
            entries = entries[start:end]
            next_cookie = b'' if end >= total else b'more'
        
        client.disconnect()
        
        return {
            "entries": entries,
            "total": total if page == 1 else len(entries),
            "page": page,
            "page_size": page_size,
            "has_more": bool(next_cookie)
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/search")
async def search_entries(req: SearchRequest):
    try:
        config = LDAPConfig(
            host=req.host,
            port=req.port,
            bind_dn=req.bind_dn,
            bind_password=req.bind_password,
            base_dn=req.base_dn
        )
        client = LDAPClient(config)
        client.connect()
        results = client.search(req.base_dn, req.filter, attrs=req.attributes)
        client.disconnect()
        return {"entries": results, "count": len(results)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/create")
async def create_entry(req: EntryCreate):
    try:
        config = LDAPConfig(
            host=req.host,
            port=req.port,
            bind_dn=req.bind_dn,
            bind_password=req.bind_password,
            base_dn=req.dn
        )
        client = LDAPClient(config)
        client.connect()
        client.add(req.dn, req.attributes)
        client.disconnect()
        return {"status": "success", "dn": req.dn}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.put("/update")
async def update_entry(req: EntryUpdate):
    try:
        config = LDAPConfig(
            host=req.host,
            port=req.port,
            bind_dn=req.bind_dn,
            bind_password=req.bind_password,
            base_dn=req.dn
        )
        client = LDAPClient(config)
        client.connect()
        client.modify(req.dn, req.changes)
        client.disconnect()
        return {"status": "success", "dn": req.dn}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.delete("/delete")
async def delete_entry(
    host: str = Query(...),
    port: int = Query(389),
    bind_dn: str = Query(...),
    bind_password: str = Query(...),
    dn: str = Query(...)
):
    try:
        config = LDAPConfig(
            host=host,
            port=port,
            bind_dn=bind_dn,
            bind_password=bind_password,
            base_dn=dn
        )
        client = LDAPClient(config)
        client.connect()
        client.delete(dn)
        client.disconnect()
        return {"status": "success", "dn": dn}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
