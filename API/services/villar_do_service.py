import os

import requests


class VillarDoError(Exception):
    pass


def _config():
    return {
        "url": (os.getenv("VILLAR_DO_API_URL", "") or "").strip().rstrip("/"),
        "client_id": (os.getenv("VILLAR_DO_CLIENT_ID", "") or "").strip(),
        "app_key": (os.getenv("VILLAR_DO_APP_KEY", "") or "").strip(),
        "timeout": int(os.getenv("VILLAR_DO_TIMEOUT", "12") or "12"),
    }


def resolver_cliente_villar_do(nombre: str, apellido: str, telefono: str):
    """
    Crea o recupera un villar_id para un cliente sin app (sin correo/password),
    igual que hace KBeauty (servicios/servicio_villar_do.py). Requiere el scope
    clientes.resolver en la API key de turnos.villar en Villar ID.

    forzar_creacion=True porque el telefono ya es unico en turnos.villar (no
    se puede duplicar aqui) -- si el nombre se parece al de otro cliente pero
    el telefono es distinto, son personas distintas, no hay riesgo real en
    crear el villar_id igual.

    Puede lanzar VillarDoError; el llamador debe tratarlo como best-effort
    (no bloquear el alta del turno si Villar ID esta caido o mal configurado).
    """
    config = _config()
    if not (config["url"] and config["client_id"] and config["app_key"]):
        raise VillarDoError("Falta configuracion de Villar ID (VILLAR_DO_API_URL/CLIENT_ID/APP_KEY)")

    try:
        respuesta = requests.post(
            f"{config['url']}/api/clientes/resolver",
            json={
                "nombre": nombre,
                "apellido": apellido,
                "telefono": telefono,
                "forzar_creacion": True,
            },
            headers={
                "Accept": "application/json",
                "X-Villar-Client-Id": config["client_id"],
                "X-Villar-App-Key": config["app_key"],
            },
            timeout=config["timeout"],
        )
    except requests.RequestException as error:
        raise VillarDoError(f"No se pudo conectar con Villar ID: {error!r}")

    try:
        datos = respuesta.json()
    except ValueError:
        raise VillarDoError(f"Villar ID respondio con un formato invalido (status {respuesta.status_code})")

    if respuesta.status_code >= 400 or datos.get("ok") is False:
        mensaje = datos.get("error") or datos.get("mensaje") or "Villar ID rechazo la solicitud"
        raise VillarDoError(mensaje)

    return datos
