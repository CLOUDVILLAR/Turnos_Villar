import asyncio
import json
from collections import defaultdict
from typing import Dict, Optional, Set, List
from datetime import date
import anyio
import psycopg2
from psycopg2.extras import RealDictCursor
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
    "dbname": "turnos_db",
    "user": "postgres",
    "password": "123",
    "host": "localhost",
    "port": "5432",
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

def db_crear_turno(sucursal_id: int, nombre: str, edad: int, telefono: Optional[str]) -> int:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO turnos (sucursal_id, nombre, edad, telefono, estado)
            VALUES (%s, %s, %s, %s, 'espera')
            RETURNING id
            """,
            (sucursal_id, nombre, edad, telefono),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        return new_id
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

# --------- Endpoints HTTP ---------

@app.post("/login")
def login(data: LoginRequest):
    conn = get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            "SELECT id, nombre, doctor_nombre FROM sucursales WHERE username=%s AND password_hash=%s",
            (data.username, data.password),
        )
        user = cur.fetchone()
        if not user:
            raise HTTPException(status_code=400, detail="Credenciales incorrectas")
        return dict(user)
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

@app.post("/crear-turno")
async def crear_turno(turno: TurnoCreate):
    try:
        new_id = await anyio.to_thread.run_sync(
            db_crear_turno,
            turno.sucursal_id,
            turno.nombre,
            turno.edad,
            turno.telefono,
        )

        # 🔥 clave: broadcast del estado ACTUAL ya calculado
        payload = await build_turno_actual_event(turno.sucursal_id)
        await manager.broadcast(turno.sucursal_id, payload)

        return {"id": new_id, "status": "creado"}
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
