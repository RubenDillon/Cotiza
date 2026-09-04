#!/usr/bin/env python3
"""
daily_updater.py — Servicio de actualización automática de cotizaciones
Descripción: Consulta la API pública del BCRA (estadisticascambiarias v1.0)
             para cada moneda registrada en la tabla Moneda y guarda (o
             actualiza) el valor del día en la tabla Valor.

API BCRA utilizada:
  GET https://api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones/{codigo_iso}
      ?fechadesde=YYYY-MM-DD&fechahasta=YYYY-MM-DD

  Respuesta JSON:
  {
    "status": 200,
    "results": [
      {
        "fecha": "2026-09-04",
        "detalle": [
          { "codigoMoneda": "USD", "descripcion": "...",
            "tipoPase": 0.0, "tipoCotizacion": 1508.0 }
        ]
      }
    ]
  }

  El campo usado como cotización es "tipoCotizacion" (pesos por unidad de moneda).
  ARS tiene tipoCotizacion=0, se registra como 1.0 (base de referencia).

Ejecución:
  • Manual     : /opt/cotizacion/venv/bin/python daily_updater.py
  • Automática : systemd timer (cotizacion-updater.timer) a las 18:00 hs
"""

import os
import sys
import logging
import requests
import mysql.connector
from mysql.connector import Error as DBError
from datetime import date, timedelta

# ---------------------------------------------------------------------------
# Configuración de logging
# ---------------------------------------------------------------------------
os.makedirs("/var/log/cotizacion", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("/var/log/cotizacion/updater.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuración de base de datos
# ---------------------------------------------------------------------------
DB_CONFIG = {
    "host":     os.getenv("DB_HOST",   "localhost"),
    "user":     os.getenv("DB_USER",   "app_cotizacion"),
    "password": os.getenv("DB_PASS",   "AppCotiz#2025!"),
    "database": os.getenv("DB_NAME",   "cotizacion_moneda"),
    "charset":  "utf8mb4",
}

# ---------------------------------------------------------------------------
# Constantes BCRA
# ---------------------------------------------------------------------------
BCRA_BASE_URL   = "https://api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones"
DIAS_HISTORICO  = 10   # cuántos días hacia atrás pedir en cada consulta
REQUEST_TIMEOUT = 15   # segundos


# ---------------------------------------------------------------------------
# Funciones de base de datos
# ---------------------------------------------------------------------------
def get_monedas(conn: mysql.connector.MySQLConnection) -> list[dict]:
    """Devuelve todas las monedas con su código ISO (campo Clave)."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda")
    monedas = cursor.fetchall()
    cursor.close()
    return monedas


def upsert_valor(
    conn: mysql.connector.MySQLConnection,
    id_moneda: int,
    fecha: str,
    valor: float,
) -> None:
    """
    Inserta o actualiza el valor de una moneda en la fecha indicada.
    La clave única (IDMoneda, Fecha) garantiza que no haya duplicados.
    """
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO Valor (IDMoneda, Fecha, Valor)
        VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE Valor = VALUES(Valor)
        """,
        (id_moneda, fecha, valor),
    )
    conn.commit()
    cursor.close()


# ---------------------------------------------------------------------------
# Consulta a la API del BCRA
# ---------------------------------------------------------------------------
def fetch_bcra(codigo_iso: str, fecha_desde: str, fecha_hasta: str) -> list[dict]:
    """
    Consulta la API de cotizaciones cambiarias del BCRA para un código ISO.

    Retorna lista de dicts: [{"fecha": "YYYY-MM-DD", "valor": float}, ...]
    Retorna lista vacía en caso de error o sin datos.

    Caso especial ARS: el BCRA no publica cotización del peso vs sí mismo;
    se retorna valor 1.0 para cada día del rango solicitado.
    """
    # El ARS no tiene cotización contra sí mismo — valor fijo 1.0
    if codigo_iso.upper() == "ARS":
        resultados = []
        fecha = date.fromisoformat(fecha_desde)
        hasta = date.fromisoformat(fecha_hasta)
        while fecha <= hasta:
            resultados.append({"fecha": fecha.isoformat(), "valor": 1.0})
            fecha += timedelta(days=1)
        return resultados

    url = f"{BCRA_BASE_URL}/{codigo_iso.upper()}"
    params = {
        "fechadesde": fecha_desde,
        "fechahasta": fecha_hasta,
    }

    try:
        response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT,
                                verify=True)
        response.raise_for_status()
        data = response.json()

        resultados = []
        for item in data.get("results", []):
            fecha = item.get("fecha")
            detalle = item.get("detalle", [])
            if not fecha or not detalle:
                continue
            # tipoCotizacion = pesos argentinos por unidad de moneda extranjera
            cotizacion = detalle[0].get("tipoCotizacion", 0)
            if cotizacion and float(cotizacion) > 0:
                resultados.append({"fecha": fecha, "valor": float(cotizacion)})

        return resultados

    except requests.exceptions.HTTPError as e:
        log.warning("HTTP error al consultar %s: %s", codigo_iso, e)
    except requests.exceptions.ConnectionError:
        log.error("Sin conexión con la API del BCRA.")
    except requests.exceptions.Timeout:
        log.error("Timeout al consultar la API del BCRA (%s).", codigo_iso)
    except (ValueError, KeyError) as e:
        log.error("Error al parsear respuesta BCRA (%s): %s", codigo_iso, e)
    return []


# ---------------------------------------------------------------------------
# Proceso principal
# ---------------------------------------------------------------------------
def run():
    log.info("=== Inicio de actualización de cotizaciones ===")

    fecha_hasta  = date.today().isoformat()
    fecha_desde  = (date.today() - timedelta(days=DIAS_HISTORICO)).isoformat()
    log.info("Rango de fechas: %s → %s", fecha_desde, fecha_hasta)

    # Conectar a la base de datos
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
    except DBError as e:
        log.critical("No se pudo conectar a la base de datos: %s", e)
        sys.exit(1)

    monedas = get_monedas(conn)
    log.info("Monedas a actualizar: %d", len(monedas))

    total_ok  = 0
    total_err = 0

    for moneda in monedas:
        id_moneda   = moneda["IDMoneda"]
        nombre      = moneda["Moneda"]
        codigo_iso  = moneda["Clave"]   # USD, EUR, BRL, etc.

        log.info("  Consultando: %s (ISO: %s)", nombre, codigo_iso)
        registros = fetch_bcra(codigo_iso, fecha_desde, fecha_hasta)

        if not registros:
            log.warning("  → Sin datos del BCRA para %s (%s)", nombre, codigo_iso)
            total_err += 1
            continue

        for reg in registros:
            try:
                upsert_valor(conn, id_moneda, reg["fecha"], reg["valor"])
                log.info("    ✔ %s | %.4f ARS", reg["fecha"], reg["valor"])
                total_ok += 1
            except DBError as e:
                log.error("    ✘ Error al guardar %s/%s: %s", codigo_iso, reg["fecha"], e)
                total_err += 1

    conn.close()
    log.info("=== Actualización finalizada: %d OK / %d errores ===",
             total_ok, total_err)

    sys.exit(0 if total_err == 0 else 1)


if __name__ == "__main__":
    run()
