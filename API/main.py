import asyncio
import json
import os
from collections import defaultdict
from typing import Dict, Optional, Set, List
from datetime import date
import anyio
import psycopg2
from psycopg2.extras import RealDictCursor
import re
from services.odoo_service import OdooClient
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.encoders import jsonable_encoder
from fastapi import Query
from pydantic import BaseModel
from typing import Optional as Opt
from routers.odoo_customers import router as odoo_router
from dotenv import load_dotenv
from routers.odoo_customers import router as odoo_customers_router
load_dotenv()

app = FastAPI()

# RUTAS AÑADIDAS
app.include_router(odoo_router)
app.include_router(odoo_customers_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # en prod pon tu dominio
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

db_params = {
    "dbname": os.getenv("DB_NAME", "turnos_db"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "123"),
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
}

def get_db_connection():
    return psycopg2.connect(**db_params)

# --------- DB helpers (SYNC) ---------
def db_get_turnos_espera(sucursal_id: int) -> list[dict]:
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT * FROM turnos
            WHERE sucursal_id = %s AND estado = 'espera'
            ORDER BY created_at ASC
            """,
            (sucursal_id,),
        )
        rows = cur.fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()

def db_get_turno_actual(sucursal_id: int) -> Optional[dict]:
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT * FROM turnos
            WHERE sucursal_id = %s AND estado = 'espera'
            ORDER BY created_at ASC
            LIMIT 1
            """,
            (sucursal_id,),
        )
        return cur.fetchone()
    finally:
        conn.close()

def db_crear_turno_seguro(
    sucursal_id: int,
    nombre: str,
    edad: int,
    telefono: Optional[str],
) -> Optional[int]:
    """
    Crea un turno SOLO si no existe otro activo.
    Devuelve el id si se creó, o None si ya existía.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO turnos (sucursal_id, nombre, edad, telefono, estado)
            SELECT %s, %s, %s, %s, 'espera'
            WHERE NOT EXISTS (
                SELECT 1
                FROM turnos
                WHERE sucursal_id = %s
                  AND estado IN ('espera', 'atendiendo')
                  AND (
                        (%s IS NOT NULL AND telefono = %s)
                     OR (%s IS NULL AND nombre = %s)
                  )
            )
            RETURNING id
            """,
            (
                sucursal_id, nombre, edad, telefono,
                sucursal_id,
                telefono, telefono,
                telefono, nombre,
            ),
        )

        row = cur.fetchone()
        conn.commit()
        return row[0] if row else None
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def db_finalizar_turno(turno_id: int) -> int:
    """
    Finaliza un turno y retorna sucursal_id del turno finalizado.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            UPDATE turnos
            SET estado='finalizado', updated_at=NOW()
            WHERE id=%s
            RETURNING sucursal_id
            """,
            (turno_id,),
        )
        row = cur.fetchone()
        if not row:
            raise ValueError("Turno no encontrado")
        conn.commit()
        return row[0]
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

# --------- Evento estándar (SIEMPRE JSON-safe) ---------

async def build_turno_actual_event(sucursal_id: int) -> dict:
    turno_actual = await anyio.to_thread.run_sync(db_get_turno_actual, sucursal_id)
    payload = {
        "type": "turno_actual",
        "sucursal_id": sucursal_id,
        "turno": dict(turno_actual) if turno_actual else None,  # RealDictRow -> dict
    }
    return jsonable_encoder(payload)  # datetime -> string ISO

# --------- WebSocket Manager ---------

class ConnectionManager:
    def __init__(self):
        self._by_sucursal: Dict[int, Set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()

    async def connect(self, sucursal_id: int, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self._by_sucursal[sucursal_id].add(websocket)

    async def disconnect(self, sucursal_id: int, websocket: WebSocket):
        async with self._lock:
            conns = self._by_sucursal.get(sucursal_id)
            if not conns:
                return
            conns.discard(websocket)
            if not conns:
                self._by_sucursal.pop(sucursal_id, None)

    async def broadcast(self, sucursal_id: int, event: dict):
        # event debe ser dict (NO string)
        msg = json.dumps(event, ensure_ascii=False)

        async with self._lock:
            targets = list(self._by_sucursal.get(sucursal_id, set()))

        dead: List[WebSocket] = []
        for ws in targets:
            try:
                await ws.send_text(msg)
            except Exception:
                dead.append(ws)

        if dead:
            async with self._lock:
                conns = self._by_sucursal.get(sucursal_id, set())
                for ws in dead:
                    conns.discard(ws)
                if not conns:
                    self._by_sucursal.pop(sucursal_id, None)

manager = ConnectionManager()

# --------- Models ---------

class LoginRequest(BaseModel):
    username: str
    password: str

class TurnoCreate(BaseModel):
    sucursal_id: int
    nombre: str
    edad: int
    telefono: Opt[str] = None

class FinalizarTurno(BaseModel):
    turno_id: int


class AdminUserCreate(BaseModel):
    nombre: str
    username: str
    password: str
    doctor_nombre: Optional[str] = None
    rol: str = "sucursal"

class AdminUserUpdate(BaseModel):
    nombre: str
    username: str
    password: Optional[str] = None
    doctor_nombre: Optional[str] = None
    rol: str = "sucursal"


def _validar_rol(rol: str):
    if rol not in ("admin", "sucursal"):
        raise HTTPException(status_code=400, detail="Rol inválido")



def _phone_digits(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    d = re.sub(r"\D+", "", raw)
    return d or None


async def _get_odoo_name_by_phone(telefono: Optional[str]) -> Optional[str]:
    """
    Busca en Odoo por teléfono (ignorando formato) y devuelve el partner.name.
    Si no encuentra, devuelve None.
    """
    d = _phone_digits(telefono)
    if not d:
        return None

    client = OdooClient()

    last4 = d[-4:] if len(d) >= 4 else None
    last7 = d[-7:] if len(d) >= 7 else None
    last10 = d[-10:] if len(d) >= 10 else None

    terms = [
        (telefono or "").strip(),  # tal cual (por si Odoo lo tiene igual)
        d,                         # pegado
        f"+{d}",                   # pegado con +
        last10,                    # últimos 10
        last7,                     # últimos 7
        last4,                     # últimos 4
    ]

    seen = set()
    for t in terms:
        if not t:
            continue
        if t in seen:
            continue
        seen.add(t)

        candidates = await anyio.to_thread.run_sync(client.search_partners, t, 25)
        for p in candidates:
            if _phone_digits(p.get("phone")) == d or _phone_digits(p.get("mobile")) == d:
                name = (p.get("name") or "").strip()
                if name:
                    return name

    return None


# --------- Endpoints HTTP ---------

@app.post("/login")
def login(data: LoginRequest):
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT id, nombre, doctor_nombre, rol
            FROM sucursales
            WHERE username = %s
              AND password_hash = %s
            """,
            (data.username, data.password),
        )
        user = cur.fetchone()

        if not user:
            raise HTTPException(status_code=400, detail="Credenciales incorrectas")

        user_dict = dict(user)

        # Compatibilidad hacia atrás:
        # Flutter viejo seguirá usando id, nombre y doctor_nombre.
        # Flutter nuevo usará rol / is_admin.
        user_dict["is_admin"] = user_dict.get("rol") == "admin"

        return user_dict

    finally:
        conn.close()

@app.get("/turno-actual/{sucursal_id}")
def get_turno_actual(sucursal_id: int):
    row = db_get_turno_actual(sucursal_id)
    return dict(row) if row else None

@app.get("/turnos-espera/{sucursal_id}")
def get_turnos_espera(sucursal_id: int):
    # FastAPI convertirá datetimes bien en HTTP
    return db_get_turnos_espera(sucursal_id)



def db_turno_activo_existente(
    sucursal_id: int,
    telefono: Optional[str],
    nombre: str,
) -> bool:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        if telefono:
            cur.execute(
                """
                SELECT 1
                FROM turnos
                WHERE sucursal_id = %s
                  AND telefono = %s
                  AND estado IN ('espera', 'atendiendo')
                LIMIT 1
                """,
                (sucursal_id, telefono),
            )
        else:
            cur.execute(
                """
                SELECT 1
                FROM turnos
                WHERE sucursal_id = %s
                  AND nombre = %s
                  AND estado IN ('espera', 'atendiendo')
                LIMIT 1
                """,
                (sucursal_id, nombre),
            )

        return cur.fetchone() is not None
    finally:
        conn.close()



@app.post("/crear-turno")
async def crear_turno(turno: TurnoCreate):
    try:
        # 1) Normalizar nombre usando Odoo si existe
        odoo_name = await _get_odoo_name_by_phone(turno.telefono)
        nombre_final = (odoo_name or turno.nombre).strip()

        # 2) Crear turno de forma ATÓMICA (sin race conditions)
        new_id = await anyio.to_thread.run_sync(
            db_crear_turno_seguro,   # 👈 función segura
            turno.sucursal_id,
            nombre_final,
            turno.edad,
            turno.telefono,
        )

        # 3) Si no se creó, ya existía un turno activo
        if not new_id:
            return {
                "status": "ok",
                "mensaje": "El cliente ya tiene un turno activo",
            }

        # 4) Broadcast del estado actual
        payload = await build_turno_actual_event(turno.sucursal_id)
        await manager.broadcast(turno.sucursal_id, payload)

        return {
            "id": new_id,
            "status": "creado",
            "nombre": nombre_final,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))



@app.post("/finalizar-turno")
async def finalizar_turno(data: FinalizarTurno):
    try:
        sucursal_id = await anyio.to_thread.run_sync(db_finalizar_turno, data.turno_id)

        # 🔥 clave: broadcast del estado ACTUAL ya calculado (pasa al siguiente)
        payload = await build_turno_actual_event(sucursal_id)
        await manager.broadcast(sucursal_id, payload)

        return {"status": "ok"}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    






# Estisticas 


def db_iniciar_turno(turno_id: int) -> Optional[int]:
    """
    Marca inicio_atencion y estado=atendiendo si estaba en espera.
    Retorna sucursal_id si se actualizó, o None si no se pudo.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            UPDATE turnos
            SET estado='atendiendo', inicio_atencion=NOW(), updated_at=NOW()
            WHERE id=%s AND estado='espera'
            RETURNING sucursal_id
            """,
            (turno_id,),
        )
        row = cur.fetchone()
        conn.commit()
        return row[0] if row else None
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def db_get_turnos_en_curso(sucursal_id: int) -> list[dict]:
    """
    Devuelve la lista de turnos no finalizados (atendiendo primero, luego espera)
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT * FROM turnos
            WHERE sucursal_id=%s AND estado IN ('atendiendo','espera')
            ORDER BY (estado='atendiendo') DESC, created_at ASC
            """,
            (sucursal_id,),
        )
        rows = cur.fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()

def db_get_estadisticas_por_fecha(sucursal_id: int, fecha: str) -> dict:
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            WITH base AS (
              SELECT
                id, nombre, edad, telefono,
                created_at,
                inicio_atencion,
                updated_at AS finalizado_at,
                LAG(updated_at) OVER (ORDER BY created_at ASC) AS prev_finalizado
              FROM turnos
              WHERE sucursal_id = %s
                AND estado = 'finalizado'
                AND DATE(created_at) = %s::date
            ),
            calc AS (
              SELECT
                *,
                COALESCE(
                  inicio_atencion,
                  GREATEST(created_at, COALESCE(prev_finalizado, created_at))
                ) AS inicio_calculado
              FROM base
            )
            SELECT
              id, nombre, edad, telefono,
              created_at,
              inicio_atencion,
              inicio_calculado,
              finalizado_at,

              EXTRACT(EPOCH FROM GREATEST(inicio_calculado - created_at, interval '0')) AS espera_seg,
              EXTRACT(EPOCH FROM GREATEST(finalizado_at - inicio_calculado, interval '0')) AS atencion_seg,
              EXTRACT(EPOCH FROM GREATEST(finalizado_at - created_at, interval '0')) AS total_seg
            FROM calc
            ORDER BY created_at DESC
            """,
            (sucursal_id, fecha),
        )

        clientes = cur.fetchall()
        total = len(clientes)

        sum_total = sum((c.get("total_seg") or 0) for c in clientes)
        sum_espera = sum((c.get("espera_seg") or 0) for c in clientes)
        sum_atencion = sum((c.get("atencion_seg") or 0) for c in clientes)

        avg_total = (sum_total / total) if total else 0
        avg_espera = (sum_espera / total) if total else 0
        avg_atencion = (sum_atencion / total) if total else 0

        return {
            "fecha": fecha,
            "total_atendidos": total,
            "promedio_total_seg": avg_total,
            "promedio_espera_seg": avg_espera,
            "promedio_atencion_seg": avg_atencion,
            "clientes": clientes,
        }
    finally:
        conn.close()



class IniciarTurno(BaseModel):
    turno_id: int

@app.post("/iniciar-turno")
async def iniciar_turno(data: IniciarTurno):
    try:
        sucursal_id = await anyio.to_thread.run_sync(db_iniciar_turno, data.turno_id)
        # si no se pudo iniciar (ya estaba atendiendo/finalizado), igual devolvemos ok
        if sucursal_id:
            payload = await build_turno_actual_event(sucursal_id)
            await manager.broadcast(sucursal_id, payload)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# IMPORTANTE: para recepción (cola completa con "actual" arriba)
@app.get("/turnos-espera/{sucursal_id}")
def get_turnos_espera(sucursal_id: int):
    return db_get_turnos_en_curso(sucursal_id)

# Endpoint de estadísticas por fecha
@app.get("/estadisticas/{sucursal_id}")
def estadisticas(sucursal_id: int, fecha: str = Query(..., description="YYYY-MM-DD")):
    data = db_get_estadisticas_por_fecha(sucursal_id, fecha)
    return jsonable_encoder(data)

# --------- WebSocket por sucursal ---------

@app.websocket("/ws/{sucursal_id}")
async def websocket_endpoint(websocket: WebSocket, sucursal_id: int):
    await manager.connect(sucursal_id, websocket)

    # estado inicial
    payload = await build_turno_actual_event(sucursal_id)
    await websocket.send_text(json.dumps(payload, ensure_ascii=False))

    try:
        while True:
            await websocket.receive_text()  # pings
    except WebSocketDisconnect:
        await manager.disconnect(sucursal_id, websocket)
    except Exception:
        await manager.disconnect(sucursal_id, websocket)




@app.get("/admin/usuarios")
def admin_listar_usuarios():
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            SELECT id, nombre, username, doctor_nombre, rol, created_at
            FROM sucursales
            ORDER BY id ASC
            """
        )
        return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


@app.post("/admin/usuarios", status_code=201)
def admin_crear_usuario(data: AdminUserCreate):
    _validar_rol(data.rol)
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            INSERT INTO sucursales (nombre, username, password_hash, doctor_nombre, rol)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id, nombre, username, doctor_nombre, rol, created_at
            """,
            (data.nombre, data.username, data.password, data.doctor_nombre, data.rol),
        )
        row = cur.fetchone()
        conn.commit()
        return dict(row)
    except psycopg2.errors.UniqueViolation:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Ese usuario ya existe")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@app.put("/admin/usuarios/{usuario_id}")
def admin_actualizar_usuario(usuario_id: int, data: AdminUserUpdate):
    _validar_rol(data.rol)
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)

        if data.password:
            cur.execute(
                """
                UPDATE sucursales
                SET nombre = %s,
                    username = %s,
                    password_hash = %s,
                    doctor_nombre = %s,
                    rol = %s
                WHERE id = %s
                RETURNING id, nombre, username, doctor_nombre, rol, created_at
                """,
                (data.nombre, data.username, data.password, data.doctor_nombre, data.rol, usuario_id),
            )
        else:
            cur.execute(
                """
                UPDATE sucursales
                SET nombre = %s,
                    username = %s,
                    doctor_nombre = %s,
                    rol = %s
                WHERE id = %s
                RETURNING id, nombre, username, doctor_nombre, rol, created_at
                """,
                (data.nombre, data.username, data.doctor_nombre, data.rol, usuario_id),
            )

        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        conn.commit()
        return dict(row)
    except psycopg2.errors.UniqueViolation:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Ese usuario ya existe")
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@app.delete("/admin/usuarios/{usuario_id}")
def admin_eliminar_usuario(usuario_id: int):
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute("SELECT id, rol FROM sucursales WHERE id = %s", (usuario_id,))
        user = cur.fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="Usuario no encontrado")

        cur.execute("SELECT COUNT(*) AS total FROM turnos WHERE sucursal_id = %s", (usuario_id,))
        total_turnos = cur.fetchone()["total"]
        if total_turnos > 0:
            raise HTTPException(
                status_code=400,
                detail="No se puede eliminar porque esta sucursal tiene turnos. Mejor cambia usuario/contraseña o rol.",
            )

        cur.execute("DELETE FROM sucursales WHERE id = %s", (usuario_id,))
        conn.commit()
        return {"ok": True}
    except HTTPException:
        conn.rollback()
        raise
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@app.get("/admin/estadisticas-globales")
def admin_estadisticas_globales(
    fecha: Optional[date] = Query(None),
    fecha_inicio: Optional[date] = Query(None),
    fecha_fin: Optional[date] = Query(None),
):
    """
    Estadísticas globales para admin.

    Compatibilidad:
    - Si Flutter viejo manda ?fecha=YYYY-MM-DD, funciona igual.
    - Si Flutter nuevo manda ?fecha_inicio=YYYY-MM-DD&fecha_fin=YYYY-MM-DD,
      devuelve el rango completo.
    """

    if fecha_inicio is None and fecha_fin is None:
        if fecha is None:
            fecha_inicio = date.today()
            fecha_fin = date.today()
        else:
            fecha_inicio = fecha
            fecha_fin = fecha

    if fecha_inicio is None:
        fecha_inicio = fecha_fin

    if fecha_fin is None:
        fecha_fin = fecha_inicio

    if fecha_inicio > fecha_fin:
        raise HTTPException(status_code=400, detail="Rango de fechas inválido")

    conn = get_db_connection()

    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute(
            """
            WITH base AS (
                SELECT
                    t.id,
                    t.sucursal_id,
                    s.nombre AS sucursal_nombre,
                    t.nombre,
                    t.telefono,
                    t.edad,
                    t.estado,
                    t.created_at,
                    t.updated_at,
                    t.inicio_atencion,
                    CASE
                        WHEN t.inicio_atencion IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.inicio_atencion - t.created_at))
                        ELSE 0
                    END AS espera_segundos,
                    CASE
                        WHEN t.inicio_atencion IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.updated_at - t.inicio_atencion))
                        ELSE 0
                    END AS atencion_segundos,
                    CASE
                        WHEN t.updated_at IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.updated_at - t.created_at))
                        ELSE 0
                    END AS total_segundos
                FROM turnos t
                INNER JOIN sucursales s ON s.id = t.sucursal_id
                WHERE DATE(t.created_at) BETWEEN %s AND %s
            )
            SELECT
                COUNT(*) AS total_turnos,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN espera_segundos
                    END
                ), 0) AS promedio_espera_segundos,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN atencion_segundos
                    END
                ), 0) AS promedio_atencion_segundos,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN total_segundos
                    END
                ), 0) AS promedio_total_segundos,

                COUNT(*) FILTER (WHERE edad BETWEEN 1 AND 4) AS edad_1_4,
                COUNT(*) FILTER (WHERE edad BETWEEN 5 AND 14) AS edad_5_14,
                COUNT(*) FILTER (WHERE edad BETWEEN 15 AND 64) AS edad_15_64,
                COUNT(*) FILTER (WHERE edad > 64) AS edad_65_plus
            FROM base;
            """,
            (fecha_inicio, fecha_fin),
        )
        global_stats = dict(cur.fetchone() or {})

        cur.execute(
            """
            WITH base AS (
                SELECT
                    t.id,
                    t.sucursal_id,
                    s.nombre AS sucursal_nombre,
                    t.edad,
                    t.estado,
                    t.created_at,
                    t.updated_at,
                    t.inicio_atencion,
                    CASE
                        WHEN t.inicio_atencion IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.inicio_atencion - t.created_at))
                        ELSE 0
                    END AS espera_segundos,
                    CASE
                        WHEN t.inicio_atencion IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.updated_at - t.inicio_atencion))
                        ELSE 0
                    END AS atencion_segundos,
                    CASE
                        WHEN t.updated_at IS NOT NULL
                            THEN EXTRACT(EPOCH FROM (t.updated_at - t.created_at))
                        ELSE 0
                    END AS total_segundos
                FROM turnos t
                INNER JOIN sucursales s ON s.id = t.sucursal_id
                WHERE DATE(t.created_at) BETWEEN %s AND %s
            )
            SELECT
                sucursal_id,
                sucursal_nombre,
                COUNT(*) AS total_turnos,
                COUNT(*) FILTER (WHERE estado = 'espera') AS en_espera,
                COUNT(*) FILTER (WHERE estado IN ('finalizado', 'atendido')) AS finalizados,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN espera_segundos
                    END
                ), 0) AS promedio_espera_segundos,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN atencion_segundos
                    END
                ), 0) AS promedio_atencion_segundos,

                COALESCE(AVG(
                    CASE
                        WHEN estado IN ('finalizado', 'atendido')
                        THEN total_segundos
                    END
                ), 0) AS promedio_total_segundos,

                COUNT(*) FILTER (WHERE edad BETWEEN 1 AND 4) AS edad_1_4,
                COUNT(*) FILTER (WHERE edad BETWEEN 5 AND 14) AS edad_5_14,
                COUNT(*) FILTER (WHERE edad BETWEEN 15 AND 64) AS edad_15_64,
                COUNT(*) FILTER (WHERE edad > 64) AS edad_65_plus
            FROM base
            GROUP BY sucursal_id, sucursal_nombre
            ORDER BY sucursal_nombre ASC;
            """,
            (fecha_inicio, fecha_fin),
        )
        por_sucursal = [dict(r) for r in cur.fetchall()]

        cur.execute(
            """
            SELECT
                edad,
                COUNT(*) AS cantidad
            FROM turnos
            WHERE DATE(created_at) BETWEEN %s AND %s
            GROUP BY edad
            ORDER BY edad ASC;
            """,
            (fecha_inicio, fecha_fin),
        )
        por_edad = [dict(r) for r in cur.fetchall()]

        return jsonable_encoder({
            "fecha_inicio": fecha_inicio,
            "fecha_fin": fecha_fin,
            "global": global_stats,
            "por_sucursal": por_sucursal,
            "por_edad": por_edad,
        })

    finally:
        conn.close()