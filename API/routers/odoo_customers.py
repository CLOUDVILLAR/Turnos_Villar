import logging
import re
from typing import Iterable, List, Optional

import anyio
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from services.odoo_service import OdooClient

router = APIRouter(prefix="/odoo", tags=["odoo"])
log = logging.getLogger("uvicorn.error")


# =======================
# Helpers (PHONE / NAME)
# =======================

def phone_digits(raw: Optional[str]) -> Optional[str]:
    """Devuelve SOLO dígitos. Ignora +, espacios, guiones, paréntesis, etc."""
    if not raw:
        return None
    d = re.sub(r"\D+", "", raw)
    return d or None


def phone_store_pretty_plus1(raw: Optional[str]) -> Optional[str]:
    """
    Guarda SIEMPRE en Odoo como: +1 XXX-XXX-XXXX
    Reglas:
      - Si vienen 11 dígitos y empieza con 1: usa los últimos 10.
      - Si vienen 10 dígitos: les agrega +1.
      - Si viene otra longitud: fallback (+digits si venía con +, si no dígitos).
    """
    d = phone_digits(raw)
    if not d:
        return None

    # 11 dígitos con prefijo 1 -> +1 NXX-NXX-XXXX (usando los últimos 10)
    if len(d) == 11 and d.startswith("1"):
        d10 = d[1:]
        a, b, c = d10[0:3], d10[3:6], d10[6:10]
        return f"+1 {a}-{b}-{c}"

    # 10 dígitos -> forzar +1
    if len(d) == 10:
        a, b, c = d[0:3], d[3:6], d[6:10]
        return f"+1 {a}-{b}-{c}"

    # fallback (no debería pasar en tu flujo)
    return f"+{d}" if (raw or "").strip().startswith("+") else d


def norm_name(raw: Optional[str]) -> str:
    return (raw or "").strip().lower()


def unique_terms(seq: Iterable[Optional[str]]) -> List[str]:
    out: List[str] = []
    seen = set()
    for s in seq:
        if not s:
            continue
        s2 = str(s).strip()
        if not s2 or s2 in seen:
            continue
        seen.add(s2)
        out.append(s2)
    return out


def looks_formatted_phone(raw: Optional[str]) -> bool:
    """
    True si el string tiene algo más que dígitos (ej: +, espacios, guiones, paréntesis).
    """
    if not raw:
        return False
    s = raw.strip()
    if not s:
        return False
    return bool(re.search(r"[^\d]", s))


def phone_pretty_for_ui(raw_or_digits: Optional[str]) -> Optional[str]:
    """
    Devuelve un formato bonito para UI, sin alterar DB.
    - Si ya viene con formato (tiene +, espacios, guiones), lo deja igual.
    - Si viene solo dígitos:
        11 dígitos empezando con 1 => +1 XXX-XXX-XXXX
        10 dígitos => +1 XXX-XXX-XXXX  (forzamos +1 para tu caso)
        otros => lo devuelve tal cual
    """
    if not raw_or_digits:
        return None

    s = str(raw_or_digits).strip()
    if not s:
        return None

    if looks_formatted_phone(s):
        return s

    d = phone_digits(s)
    if not d:
        return None

    if len(d) == 11 and d.startswith("1"):
        d10 = d[1:]
        a, b, c = d10[0:3], d10[3:6], d10[6:10]
        return f"+1 {a}-{b}-{c}"

    if len(d) == 10:
        a, b, c = d[0:3], d[3:6], d[6:10]
        return f"+1 {a}-{b}-{c}"

    return d


# =======================
# Models
# =======================

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
    forzar_creacion: bool = False


class SelectOrCreateOut(BaseModel):
    created: bool
    partner: PartnerOut


# =======================
# Routes
# =======================

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
    """
    Actualiza el teléfono guardándolo SIEMPRE como: +1 XXX-XXX-XXXX
    y mantiene compatibilidad de comparación por dígitos en otras rutas.
    """
    try:
        client = OdooClient()
        tel_store = phone_store_pretty_plus1(data.telefono)

        updated = await anyio.to_thread.run_sync(
            client.update_partner_phone, partner_id, tel_store
        )

        # Devuelve bonito hacia la UI (sin tocar DB extra)
        updated = dict(updated)
        if updated.get("phone"):
            updated["phone"] = phone_pretty_for_ui(updated["phone"])
        if updated.get("mobile"):
            updated["mobile"] = phone_pretty_for_ui(updated["mobile"])

        return updated
    except Exception as e:
        log.exception("Odoo actualizar_telefono failed")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/clientes/seleccionar-o-crear")
async def seleccionar_o_crear(data: PartnerCreateIn):
    """
    Flujo nuevo:
    1) Si hay teléfono, busca por teléfono ignorando formato.
       - Si encuentra match exacto por dígitos: devuelve ese cliente.
    2) Si no encuentra por teléfono, busca por nombre exacto normalizado.
       - Si encuentra coincidencias por nombre: NO crea todavía.
         Devuelve possible_duplicate=True y la lista de duplicados.
    3) Si no encuentra nada: crea el cliente en Odoo.
    """
    try:
        client = OdooClient()

        nombre = data.nombre.strip()
        apellido = (data.apellido or "").strip()
        full_name = f"{nombre} {apellido}".strip()

        raw_tel = (data.telefono or "").strip()
        d = phone_digits(raw_tel)

        # Así lo guardaremos en Odoo si toca crear/actualizar
        tel_store = phone_store_pretty_plus1(raw_tel)

        def partner_for_ui(p: dict) -> dict:
            """Formatea phone/mobile bonito para devolver a Flutter."""
            p = dict(p)
            if p.get("phone"):
                p["phone"] = phone_pretty_for_ui(p["phone"])
            if p.get("mobile"):
                p["mobile"] = phone_pretty_for_ui(p["mobile"])
            return p

        # ==========================================================
        # 1) Buscar por teléfono ignorando formato
        # ==========================================================
        if d:
            last4 = d[-4:] if len(d) >= 4 else None
            last7 = d[-7:] if len(d) >= 7 else None
            last10 = d[-10:] if len(d) >= 10 else None

            search_terms = unique_terms([
                raw_tel,     # "+1 829-993-4714"
                d,           # "18299934714"
                f"+{d}",     # "+18299934714"
                last10,      # "8299934714"
                last7,       # "9934714"
                last4,       # "4714"
            ])

            by_id = {}
            for term in search_terms:
                candidates = await anyio.to_thread.run_sync(client.search_partners, term, 25)
                for p in candidates:
                    pid = p.get("id")
                    if pid is not None:
                        by_id[pid] = p

            exact_phone_matches = []
            for p in by_id.values():
                p_phone = p.get("phone")
                p_mobile = p.get("mobile")

                p_phone_d = phone_digits(p_phone)
                p_mobile_d = phone_digits(p_mobile)

                if p_phone_d == d or p_mobile_d == d:
                    raw_match = p_phone if p_phone_d == d else p_mobile
                    exact_phone_matches.append((p, raw_match))

            if exact_phone_matches:
                # Prioriza el que ya tenga formato "bonito" en Odoo
                def score(item):
                    partner, raw_match = item
                    has_formatted = 1 if looks_formatted_phone(raw_match) else 0
                    has_phone = 1 if ((partner.get("phone") or partner.get("mobile"))) else 0
                    return (has_formatted, has_phone)

                exact_phone_matches.sort(key=score, reverse=True)

                best_partner, raw_match = exact_phone_matches[0]
                best_partner = partner_for_ui(best_partner)

                # Si phone está vacío pero mobile matcheó, completa phone para la UI
                if not best_partner.get("phone") and raw_match:
                    best_partner["phone"] = phone_pretty_for_ui(raw_match)

                return {
                    "status": "existing_phone",
                    "created": False,
                    "possible_duplicate": False,
                    "partner": best_partner,
                    "duplicates": [],
                    "message": "Ya existe un cliente con este teléfono.",
                }

        # ==========================================================
        # 2) Si NO apareció por teléfono, buscar por nombre exacto
        # ==========================================================
        target_name = norm_name(full_name)

        if target_name:
            # Buscamos por nombre completo y también por nombre base para recuperar más candidatos
            name_terms = unique_terms([
                full_name,
                nombre,
            ])

            by_id = {}
            for term in name_terms:
                candidates = await anyio.to_thread.run_sync(client.search_partners, term, 50)
                for p in candidates:
                    pid = p.get("id")
                    if pid is not None:
                        by_id[pid] = p

            same_name_matches = []
            for p in by_id.values():
                partner_name = norm_name(p.get("name"))
                if partner_name == target_name:
                    same_name_matches.append(partner_for_ui(p))

            if same_name_matches and not data.forzar_creacion:
                # Prioriza mostrar primero los que sí tienen teléfono
                same_name_matches.sort(
                    key=lambda p: 1 if ((p.get("phone") or p.get("mobile"))) else 0,
                    reverse=True,
                )

                primary = same_name_matches[0]
                telefono_actual = (primary.get("phone") or primary.get("mobile"))

                return {
                    "status": "possible_duplicate_by_name",
                    "created": False,
                    "possible_duplicate": True,
                    "partner": primary,
                    "duplicates": same_name_matches,
                    "message": "Ya existe un cliente con este nombre. Confirma si es la misma persona antes de crear otro registro.",
                    "suggested_phone": telefono_actual,
                }

        # ==========================================================
        # 3) Si no hubo match ni por teléfono ni por nombre, crear
        # ==========================================================
        created = await anyio.to_thread.run_sync(
            client.create_partner,
            nombre,
            (apellido or None),
            data.edad,
            tel_store,
        )

        created = partner_for_ui(created)

        return {
            "status": "created",
            "created": True,
            "possible_duplicate": False,
            "partner": created,
            "duplicates": [],
            "message": "Cliente creado correctamente.",
        }

    except Exception as e:
        log.exception("Odoo seleccionar_o_crear failed")
        raise HTTPException(status_code=500, detail=str(e))
