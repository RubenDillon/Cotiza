#!/usr/bin/env python3
"""
daily_updater.py — Servicio de actualización automática de cotizaciones
Descripción: Consulta la API pública del BCRA v3 para cada moneda registrada
             en la tabla Moneda y guarda (o actualiza) el valor del día en
             la tabla Valor.

API BCRA v3 utilizada:
  GET https://api.bcra.gob.ar/estadisticas/v3.0/monetarias/{idVariable}
  Respuesta JSON: { "results": [ { "fecha": "YYYY-MM-DD", "valor": float } ] }

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
BCRA_BASE_URL = "https://api.bcra.gob.ar/estadisticas/v3.0/monetarias"
# Ventana de días a solicitar (hoy -1 para capturar el último publicado)
BCRA_LIMIT     = 2
REQUEST_TIMEOUT = 10  # segundos


# ---------------------------------------------------------------------------
# Funciones de base de datos
# ---------------------------------------------------------------------------
def get_monedas(conn: mysql.connector.MySQLConnection) -> list[dict]:
    """Devuelve todas las monedas con su clave BCRA."""
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
    Usa INSERT ... ON DUPLICATE KEY UPDATE (la clave única es IDMoneda+Fecha).
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
def fetch_bcra(id_variable: str) -> list[dict]:
    """
    Consulta la API del BCRA para una variable monetaria.
    Retorna lista de dicts con claves 'fecha' (str YYYY-MM-DD) y 'valor' (float).
    Retorna lista vacía en caso de error.
    """
    # Solicitar datos de los últimos BCRA_LIMIT días
    fecha_desde = (date.today() - timedelta(days=BCRA_LIMIT)).strftime("%Y-%m-%d")
    url = f"{BCRA_BASE_URL}/{id_variable}"
    params = {
        "desde": fecha_desde,
        "hasta": date.today().strftime("%Y-%m-%d"),
        "limit": BCRA_LIMIT,
    }

    try:
        response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT,
                                verify=True)
        response.raise_for_status()
        data = response.json()
        return data.get("results", [])
    except requests.exceptions.HTTPError as e:
        log.warning("HTTP error al consultar variable %s: %s", id_variable, e)
    except requests.exceptions.ConnectionError:
        log.error("Sin conexión con la API del BCRA.")
    except requests.exceptions.Timeout:
        log.error("Timeout al consultar la API del BCRA (variable %s).", id_variable)
    except (ValueError, KeyError) as e:
        log.error("Error al parsear respuesta BCRA (variable %s): %s", id_variable, e)
    return []


# ---------------------------------------------------------------------------
# Proceso principal
# ---------------------------------------------------------------------------
def run():
    log.info("=== Inicio de actualización de cotizaciones ===")

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
        id_moneda  = moneda["IDMoneda"]
        nombre     = moneda["Moneda"]
        clave_bcra = moneda["Clave"]

        log.info("  Consultando: %s (clave BCRA: %s)", nombre, clave_bcra)
        registros = fetch_bcra(clave_bcra)

        if not registros:
            log.warning("  → Sin datos del BCRA para %s", nombre)
            total_err += 1
            continue

        for reg in registros:
            try:
                fecha = reg["fecha"]        # "YYYY-MM-DD"
                valor = float(reg["valor"])
                upsert_valor(conn, id_moneda, fecha, valor)
                log.info("    ✔ Fecha: %s | Valor: %.4f ARS", fecha, valor)
                total_ok += 1
            except (KeyError, ValueError, DBError) as e:
                log.error("    ✘ Error procesando registro %s: %s", reg, e)
                total_err += 1

    conn.close()

    log.info("=== Actualización finalizada: %d OK / %d errores ===", total_ok, total_err)

    # Retornar código de salida para que systemd registre el resultado
    sys.exit(0 if total_err == 0 else 1)


if __name__ == "__main__":
    run()
