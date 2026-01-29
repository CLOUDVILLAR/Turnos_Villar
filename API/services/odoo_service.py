# Archivo sugerido: API/services/odoo_service.py

import os
import xmlrpc.client
from typing import Any, Dict, List, Optional
from pydantic import BaseModel




class TimeoutSafeTransport(xmlrpc.client.SafeTransport):
    def __init__(self, timeout: int = 20, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.timeout = timeout

    def make_connection(self, host):
        conn = super().make_connection(host)
        conn.timeout = self.timeout
        return conn


class OdooClient:
    def __init__(self):
        # ✅ Normaliza URL (si viene sin http/https, agrega https://)
        raw_url = (os.getenv("ODOO_URL", "") or "").strip()
        if raw_url and not raw_url.startswith(("http://", "https://")):
            raw_url = "https://" + raw_url
        self.url = raw_url.rstrip("/")

        self.db = (os.getenv("ODOO_DB", "") or "").strip()
        self.user = (os.getenv("ODOO_USER", "") or "").strip()
        self.password = (os.getenv("ODOO_PASSWORD", "") or "").strip()
        self.enabled = (os.getenv("ODOO_ENABLED", "true").lower() in ("1", "true", "yes", "y", "on"))

        timeout = int(os.getenv("ODOO_TIMEOUT", "20"))
        transport = TimeoutSafeTransport(timeout=timeout)

        # Proxies XML-RPC
        self.common = xmlrpc.client.ServerProxy(
            f"{self.url}/xmlrpc/2/common", allow_none=True, transport=transport
        )
        self.models = xmlrpc.client.ServerProxy(
            f"{self.url}/xmlrpc/2/object", allow_none=True, transport=transport
        )
        self.db_proxy = xmlrpc.client.ServerProxy(
            f"{self.url}/xmlrpc/2/db", allow_none=True, transport=transport
        )



    def _check_config(self):
        if not self.enabled:
            raise RuntimeError("ODOO está deshabilitado (ODOO_ENABLED=false)")
        if not self.url:
            raise RuntimeError("Falta ODOO_URL")
        if not self.db:
            raise RuntimeError("Falta ODOO_DB")
        if not self.user:
            raise RuntimeError("Falta ODOO_USER")
        if not self.password:
            raise RuntimeError("Falta ODOO_PASSWORD")

    @staticmethod
    def _normalize_partner(p: Dict[str, Any]) -> Dict[str, Any]:
        """
        Odoo devuelve False en campos vacíos (phone/mobile).
        Para FastAPI/Pydantic: convertir False -> None.
        """
        if p.get("phone") is False:
            p["phone"] = None
        if p.get("mobile") is False:
            p["mobile"] = None
        return p

    def version(self) -> Dict[str, Any]:
        self._check_config()
        try:
            return self.common.version()
        except Exception as e:
            raise RuntimeError(f"No pude obtener version() de Odoo: {repr(e)}")

    def authenticate(self) -> int:
        self._check_config()
        try:
            uid = self.common.authenticate(self.db, self.user, self.password, {})
        except Exception as e:
            raise RuntimeError(f"Error llamando authenticate(): {repr(e)}")

        if not uid:
            raise RuntimeError("authenticate() devolvió False. Revisa DB/USER/PASS.")
        return int(uid)

    def list_dbs(self) -> List[str]:
        """
        No siempre está permitido en Odoo (depende config), pero sirve para debug.
        """
        self._check_config()
        try:
            return self.db_proxy.list()
        except Exception as e:
            raise RuntimeError(f"No pude listar bases (db.list): {repr(e)}")

    def search_partners(self, q: str, limit: int = 10) -> List[Dict[str, Any]]:
        uid = self.authenticate()

        q = (q or "").strip()
        if len(q) < 2:
            return []

        # ✅ Domain correcto para 3 condiciones OR
        domain = [
            "|",
              ["name", "ilike", q],
              "|",
                ["phone", "ilike", q],
                ["mobile", "ilike", q],
        ]

        fields = ["id", "name", "phone", "mobile"]

        try:
            partners = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "search_read",
                [domain],
                {"fields": fields, "limit": int(limit), "order": "name asc"}
            )

            partners = partners or []
            return [self._normalize_partner(p) for p in partners]

        except xmlrpc.client.Fault as f:
            raise RuntimeError(f"Odoo Fault en search_read: {f.faultString}")
        except Exception as e:
            raise RuntimeError(f"Error en search_read: {repr(e)}")

    def read_partner(self, partner_id: int) -> Optional[Dict[str, Any]]:
        uid = self.authenticate()
        fields = ["id", "name", "phone", "mobile"]
        try:
            res = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "read",
                [[int(partner_id)]],
                {"fields": fields}
            )
            if not res:
                return None
            return self._normalize_partner(res[0])
        except xmlrpc.client.Fault as f:
            raise RuntimeError(f"Odoo Fault leyendo partner {partner_id}: {f.faultString}")
        except Exception as e:
            raise RuntimeError(f"Error leyendo partner {partner_id}: {repr(e)}")

    def find_partner_exact(
        self,
        nombre: str,
        apellido: Optional[str],
        telefono: Optional[str]
    ) -> Optional[Dict[str, Any]]:
        uid = self.authenticate()

        nombre = (nombre or "").strip()
        apellido = (apellido or "").strip() if apellido else ""
        full_name = f"{nombre} {apellido}".strip()

        fields = ["id", "name", "phone", "mobile"]

        tel = (telefono or "").strip()
        if tel:
            domain_tel = ["|", ["phone", "=", tel], ["mobile", "=", tel]]
            found = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "search_read",
                [domain_tel],
                {"fields": fields, "limit": 1}
            )
            if found:
                return self._normalize_partner(found[0])

        if full_name:
            domain_name = [["name", "=ilike", full_name]]
            found = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "search_read",
                [domain_name],
                {"fields": fields, "limit": 1}
            )
            if found:
                return self._normalize_partner(found[0])

        return None

    def create_partner(
        self,
        nombre: str,
        apellido: Optional[str],
        edad: Optional[int],
        telefono: Optional[str]
    ) -> Dict[str, Any]:
        uid = self.authenticate()

        nombre = (nombre or "").strip()
        apellido = (apellido or "").strip() if apellido else ""
        full_name = f"{nombre} {apellido}".strip()

        vals: Dict[str, Any] = {"name": full_name or "Cliente sin nombre"}

        tel = (telefono or "").strip()
        if tel:
            vals["phone"] = tel
            vals["mobile"] = tel

        if edad is not None:
            # Odoo estándar no trae edad: se guarda en notas
            vals["comment"] = f"Edad: {edad}"

        try:
            partner_id = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "create",
                [vals]
            )
        except xmlrpc.client.Fault as f:
            raise RuntimeError(f"Odoo Fault creando partner: {f.faultString}")
        except Exception as e:
            raise RuntimeError(f"Error creando partner: {repr(e)}")

        created = self.read_partner(int(partner_id))
        if created:
            return created

        # fallback seguro
        out = {"id": int(partner_id), "name": vals["name"], "phone": vals.get("phone"), "mobile": vals.get("mobile")}
        return self._normalize_partner(out)


    def update_partner_phone(self, partner_id: int, telefono: Optional[str]) -> Dict[str, Any]:
        uid = self.authenticate()

        tel = (telefono or "").strip()

        # Odoo usa False para limpiar campos
        vals: Dict[str, Any] = {
            "phone": tel if tel else False,
            "mobile": tel if tel else False,
        }

        try:
            ok = self.models.execute_kw(
                self.db, uid, self.password,
                "res.partner", "write",
                [[int(partner_id)], vals]
            )
            if not ok:
                raise RuntimeError("Odoo write() devolvió False")
        except xmlrpc.client.Fault as f:
            raise RuntimeError(f"Odoo Fault actualizando teléfono: {f.faultString}")
        except Exception as e:
            raise RuntimeError(f"Error actualizando teléfono: {repr(e)}")

        updated = self.read_partner(int(partner_id)) or {"id": int(partner_id), "name": None, "phone": None, "mobile": None}

        # Normaliza False -> None
        if updated.get("phone") is False:
            updated["phone"] = None
        if updated.get("mobile") is False:
            updated["mobile"] = None

        return updated
