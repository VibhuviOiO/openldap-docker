from fastapi import APIRouter
from app.core.password_cache import get_password
from app.core.config import load_config

router = APIRouter()

@router.get("/check/{cluster_name}")
async def check_password(cluster_name: str):
    clusters = load_config()
    cluster = next((c for c in clusters if c.name == cluster_name), None)
    
    if not cluster:
        return {"cached": False}
    
    cached = get_password(cluster_name, cluster.bind_dn) is not None
    return {"cached": cached}
