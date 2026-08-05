import base64
import logging
from typing import List, Optional

import anyio
from fastapi import APIRouter, HTTPException, Query, UploadFile, File, Form
from pydantic import BaseModel

from services.odoo_service import OdooClient

router = APIRouter(prefix="/odoo", tags=["odoo-recetas"])
log = logging.getLogger("uvicorn.error")


class OrdenOut(BaseModel):
    id: int
    name: str
    partner_nombre: Optional[str] = None
    state: Optional[str] = None
    date_order: Optional[str] = None


@router.get("/ordenes/buscar", response_model=List[OrdenOut])
async def buscar_ordenes(
    q: str = Query(..., min_length=2, description="Numero de orden (ej. S-52628 o 52628)"),
    limit: int = Query(15, ge=1, le=25),
):
    try:
        client = OdooClient()
        orders = await anyio.to_thread.run_sync(client.search_orders, q, limit)

        out: List[OrdenOut] = []
        for o in orders:
            partner = o.get("partner_id")
            partner_nombre = partner[1] if isinstance(partner, (list, tuple)) and len(partner) > 1 else None
            out.append(OrdenOut(
                id=o["id"],
                name=o.get("name") or "",
                partner_nombre=partner_nombre,
                state=o.get("state"),
                date_order=o.get("date_order") or None,
            ))
        return out
    except Exception as e:
        log.exception("Odoo buscar_ordenes failed")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ordenes/{order_id}/anexar-receta")
async def anexar_receta(
    order_id: int,
    sucursal_nombre: str = Form(...),
    foto: UploadFile = File(...),
):
    try:
        contenido = await foto.read()
        if not contenido:
            raise HTTPException(status_code=400, detail="La foto llegó vacía")

        datas_b64 = base64.b64encode(contenido).decode("ascii")
        nombre_archivo = foto.filename or "receta.jpg"
        mimetype = foto.content_type or "image/jpeg"
        nota = f"Receta anexada desde recepción ({sucursal_nombre})."

        client = OdooClient()
        attachment_id = await anyio.to_thread.run_sync(
            client.attach_prescription,
            order_id,
            nombre_archivo,
            datas_b64,
            mimetype,
            nota,
        )

        return {"status": "ok", "attachment_id": attachment_id}
    except HTTPException:
        raise
    except Exception as e:
        log.exception("Odoo anexar_receta failed")
        raise HTTPException(status_code=500, detail=str(e))
