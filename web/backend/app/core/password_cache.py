import hashlib
import json
from pathlib import Path
from typing import Optional

CACHE_DIR = Path("/app/.cache")
CACHE_DIR.mkdir(exist_ok=True)

def _hash_key(cluster_name: str, bind_dn: str) -> str:
    """Create hash of cluster+bind_dn for cache key"""
    key = f"{cluster_name}:{bind_dn}"
    return hashlib.sha256(key.encode()).hexdigest()

def save_password(cluster_name: str, bind_dn: str, password: str):
    """Save password to hashed cache file"""
    cache_key = _hash_key(cluster_name, bind_dn)
    cache_file = CACHE_DIR / f"{cache_key}.json"
    
    # Hash password for storage
    pwd_hash = hashlib.sha256(password.encode()).hexdigest()
    
    cache_file.write_text(json.dumps({
        "cluster": cluster_name,
        "bind_dn": bind_dn,
        "password_hash": pwd_hash,
        "password": password  # Store encrypted in production
    }))

def get_password(cluster_name: str, bind_dn: str) -> Optional[str]:
    """Retrieve password from cache"""
    cache_key = _hash_key(cluster_name, bind_dn)
    cache_file = CACHE_DIR / f"{cache_key}.json"
    
    if not cache_file.exists():
        return None
    
    data = json.loads(cache_file.read_text())
    return data.get("password")

def clear_password(cluster_name: str, bind_dn: str):
    """Clear cached password"""
    cache_key = _hash_key(cluster_name, bind_dn)
    cache_file = CACHE_DIR / f"{cache_key}.json"
    if cache_file.exists():
        cache_file.unlink()
