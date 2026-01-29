import logging
import anyio
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import List, Optional

from services.odoo_service import OdooClient

router = APIRouter(prefix="/odoo", tags=["odoo"])
log = logging.getLogger("uvicorn.error")


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

@router.post("/clientes/seleccionar-o-crear", response_model=SelectOrCreateOut)
async def seleccionar_o_crear(data: PartnerCreateIn):
    try:
        client = OdooClient()
        found = await anyio.to_thread.run_sync(
            client.find_partner_exact, data.nombre, data.apellido, data.telefono
        )
        if found:
            return {"created": False, "partner": found}

        created = await anyio.to_thread.run_sync(
            client.create_partner, data.nombre, data.apellido, data.edad, data.telefono
        )
        return {"created": True, "partner": created}
    except Exception as e:
        log.exception("Odoo seleccionar_o_crear failed")
        raise HTTPException(status_code=500, detail=str(e))
