from fastapi import APIRouter
from app.core.config import load_config

router = APIRouter()

@router.get("/list")
async def list_clusters():
    clusters = load_config()
    return {
        "clusters": [
            {
                "name": c.name,
                "host": c.host,
                "port": c.port,
                "nodes": c.nodes,
                "base_dn": c.base_dn,
                "bind_dn": c.bind_dn,
                "readonly": c.readonly,
                "description": c.description
            }
            for c in clusters
        ]
    }
