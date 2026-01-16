import ldap
import ldap.controls
from ldap.controls import SimplePagedResultsControl
from typing import List, Dict, Optional, Tuple
from pydantic import BaseModel

class LDAPConfig(BaseModel):
    host: str
    port: int = 389
    bind_dn: str
    bind_password: str
    base_dn: str = ""

class LDAPClient:
    def __init__(self, config: LDAPConfig):
        self.config = config
        self.conn = None
    
    def connect(self) -> bool:
        try:
            ldap_url = f"ldap://{self.config.host}:{self.config.port}"
            self.conn = ldap.initialize(ldap_url)
            self.conn.simple_bind_s(self.config.bind_dn, self.config.bind_password)
            
            # Auto-discover base_dn if empty
            if not self.config.base_dn:
                self.config.base_dn = self._discover_base_dn()
            
            return True
        except ldap.LDAPError as e:
            raise Exception(f"LDAP connection failed: {str(e)}")
    
    def _discover_base_dn(self) -> str:
        """Auto-discover base DN from rootDSE"""
        try:
            result = self.conn.search_s("", ldap.SCOPE_BASE, "(objectClass=*)", ["namingContexts"])
            if result and result[0][1].get("namingContexts"):
                return result[0][1]["namingContexts"][0].decode()
            return ""
        except:
            return ""
    
    def disconnect(self):
        if self.conn:
            self.conn.unbind_s()
    
    def search(self, base_dn: str, filter_str: str = "(objectClass=*)", 
               scope: int = ldap.SCOPE_SUBTREE, attrs: Optional[List[str]] = None,
               page_size: int = 0, cookie: bytes = b'') -> Tuple[List[Dict], bytes, int]:
        """Search with optional pagination support.
        Returns: (entries, cookie, total_count)
        If page_size=0, returns all results without pagination.
        """
        try:
            if page_size > 0:
                # Paginated search
                page_ctrl = SimplePagedResultsControl(True, size=page_size, cookie=cookie)
                msgid = self.conn.search_ext(
                    base_dn, scope, filter_str, attrs, serverctrls=[page_ctrl]
                )
                rtype, rdata, rmsgid, serverctrls = self.conn.result3(msgid)
                
                # Extract cookie for next page
                pctrls = [c for c in serverctrls if c.controlType == SimplePagedResultsControl.controlType]
                next_cookie = pctrls[0].cookie if pctrls else b''
                
                # Get total count (only on first page)
                total_count = 0
                if not cookie:
                    count_results = self.conn.search_s(base_dn, scope, filter_str, ['dn'])
                    total_count = len(count_results)
                
                entries = self._process_results(rdata)
                return entries, next_cookie, total_count
            else:
                # Non-paginated search (original behavior)
                results = self.conn.search_s(base_dn, scope, filter_str, attrs)
                entries = self._process_results(results)
                return entries, b'', len(entries)
        except ldap.LDAPError as e:
            raise Exception(f"Search failed: {str(e)}")
    
    def _process_results(self, results: List) -> List[Dict]:
        """Process LDAP search results into dict format"""
        entries = []
        for dn, attrs in results:
            if not dn:
                continue
            entry = {"dn": dn}
            for key, values in attrs.items():
                decoded_values = []
                for v in values:
                    try:
                        decoded_values.append(v.decode('utf-8'))
                    except:
                        decoded_values.append(str(v))
                entry[key] = decoded_values if len(decoded_values) > 1 else decoded_values[0]
            entries.append(entry)
        return entries
    
    def add(self, dn: str, attributes: Dict) -> bool:
        try:
            ldif = [(k, v if isinstance(v, list) else [v]) for k, v in attributes.items()]
            self.conn.add_s(dn, ldif)
            return True
        except ldap.LDAPError as e:
            raise Exception(f"Add failed: {str(e)}")
    
    def modify(self, dn: str, changes: Dict) -> bool:
        try:
            mod_list = [(ldap.MOD_REPLACE, k, v if isinstance(v, list) else [v]) 
                       for k, v in changes.items()]
            self.conn.modify_s(dn, mod_list)
            return True
        except ldap.LDAPError as e:
            raise Exception(f"Modify failed: {str(e)}")
    
    def delete(self, dn: str) -> bool:
        try:
            self.conn.delete_s(dn)
            return True
        except ldap.LDAPError as e:
            raise Exception(f"Delete failed: {str(e)}")
    
    def get_entry_count(self, base_dn: str) -> int:
        try:
            results = self.conn.search_s(base_dn, ldap.SCOPE_SUBTREE, "(objectClass=*)", ["dn"])
            return len(results)
        except ldap.LDAPError:
            return 0
