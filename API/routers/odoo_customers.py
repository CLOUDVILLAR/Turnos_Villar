import logging
import anyio
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Optional

from services.odoo_service import OdooClient

router = APIRouter(prefix="/odoo", tags=["odoo"])
log = logging.getLogger("uvicorn.error")


import re
from typing import Optional

def normalize_phone_for_odoo(raw: Optional[str]) -> Optional[str]:
    """
    Permite entradas tipo:
      +1 300-123-4567, (300) 123-4567, 300 123 4567
    Guarda en Odoo como:
      +13001234567   (si venía con +)
      3001234567     (si no venía con +)
    """
    if not raw:
        return None

    s = raw.strip()
    if s == "":
        return None

    has_plus = s.lstrip().startswith("+")
    digits = re.sub(r"\D+", "", s)  # solo números

    if digits == "":
        return None

    return f"+{digits}" if has_plus else digits


class UpdateTelefonoReq(BaseModel):
    telefono: Optional[str] = None


class UpdateTelefonoIn(BaseModel):
    telefono: Optional[str] = None

class PartnerOut(BaseModel):
    id: int
    name: str
    phone: Optional[str] = None
    mobile: Optional[str] = None


class PartnerCreateIn(BaseModel):
    nombre: str = Field(..., min_length=1)
    apellido: Optional[str] = None
    edad: Optional[int] = None
    telefono: Optional[str] = None


class SelectOrCreateOut(BaseModel):
    created: bool
    partner: PartnerOut


@router.get("/health")
async def odoo_health():
    """
    Te dice:
      - version de Odoo
      - si autentica (uid)
      - (si permite) lista de DBs
    """
    try:
        client = OdooClient()
        version = await anyio.to_thread.run_sync(client.version)
        uid = await anyio.to_thread.run_sync(client.authenticate)

        dbs = None
        try:
            dbs = await anyio.to_thread.run_sync(client.list_dbs)
        except Exception:
            dbs = None

        return {"ok": True, "version": version, "uid": uid, "dbs": dbs}
    except Exception as e:
        log.exception("Odoo health failed")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/clientes/buscar", response_model=List[PartnerOut])
async def buscar_clientes(
    q: str = Query(..., min_length=2),
    limit: int = Query(10, ge=1, le=25),
):
    try:
        client = OdooClient()
        partners = await anyio.to_thread.run_sync(client.search_partners, q, limit)
        return partners
    except Exception as e:
        log.exception("Odoo buscar_clientes failed")
        raise HTTPException(status_code=500, detail=str(e))




@router.post("/clientes/{partner_id}/telefono", response_model=PartnerOut)
async def actualizar_telefono(partner_id: int, data: UpdateTelefonoIn):
    try:
        client = OdooClient()
        updated = await anyio.to_thread.run_sync(client.update_partner_phone, partner_id, data.telefono)
        return updated
    except Exception as e:
        log.exception("Odoo actualizar_telefono failed")
        raise HTTPException(status_code=500, detail=str(e))
    

import re
from typing import Optional

def _norm_phone(raw: Optional[str]) -> Optional[str]:
    """
    Normaliza teléfonos permitiendo entradas como:
      +1 300-123-4567, (300) 123-4567, 300 123 4567
    y las convierte en:
      +13001234567  (si traía +)
      3001234567    (si no traía +)
    """
    if not raw:
        return None

    s = raw.strip()
    if s == "":
        return None

    has_plus = s.startswith("+")
    digits = re.sub(r"\D+", "", s)  # deja solo dígitos

    if digits == "":
        return None

    return f"+{digits}" if has_plus else digits


def _norm_name(s: Optional[str]) -> str:
    return (s or "").strip().lower()


@router.post("/clientes/seleccionar-o-crear", response_model=SelectOrCreateOut)
async def seleccionar_o_crear(data: PartnerCreateIn):
    try:
        client = OdooClient()

        nombre = data.nombre.strip()
        apellido = (data.apellido or "").strip()

        # ✅ normalizado para comparar y evitar duplicados aunque escriban con guiones/+ etc
        tel_norm = _norm_phone(data.telefono)

        # 1) Si hay teléfono, SOLO lo consideramos "existente" si el match es EXACTO (normalizado)
        if tel_norm:
            candidates = await anyio.to_thread.run_sync(client.search_partners, tel_norm, 25)

            for p in candidates:
                p_phone = _norm_phone(p.get("phone"))
                p_mobile = _norm_phone(p.get("mobile"))

                if p_phone == tel_norm or p_mobile == tel_norm:
                    return {"created": False, "partner": p}

        # 2) Si NO hay teléfono, intenta por nombre exacto (conservador)
        else:
            target = _norm_name(f"{nombre} {apellido}".strip())
            candidates = await anyio.to_thread.run_sync(client.search_partners, target, 25)

            for p in candidates:
                if _norm_name(p.get("name")) == target:
                    return {"created": False, "partner": p}

        # 3) Si no hubo match real, ahora SÍ crea
        # ✅ IMPORTANTE: crea con el teléfono normalizado (para que Odoo compare bien y no se duplique por formato)
        created = await anyio.to_thread.run_sync(
            client.create_partner,
            nombre,
            (apellido or None),
            data.edad,
            tel_norm,  # <-- aquí va normalizado
        )
        return {"created": True, "partner": created}

    except Exception as e:
        log.exception("Odoo seleccionar_o_crear failed")
        raise HTTPException(status_code=500, detail=str(e))