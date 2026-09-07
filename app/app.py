"""
app.py — Aplicación Flask: Cotización de Moneda
Instrumentación Instana: import instana activa el sensor en el proceso
master de Gunicorn (--preload). Los workers heredan la instrumentación.
"""

import os
import instana  # noqa: F401 — activa el sensor en el master (preload)
from datetime import date
from flask import Flask, render_template, abort
import mysql.connector
from mysql.connector import Error as DBError

# Código de error MySQL/MariaDB: "Can't connect to server"
_MYSQL_CANT_CONNECT = (2003, 2002, 2006, 2013)

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
DB_CONFIG = {
    "host":     os.getenv("DB_HOST",   "localhost"),
    "user":     os.getenv("DB_USER",   "app_cotizacion"),
    "password": os.getenv("DB_PASS",   "AppCotiz#2025!"),
    "database": os.getenv("DB_NAME",   "cotizacion_moneda"),
    "charset":  "utf8mb4",
}

app = Flask(__name__)


# ---------------------------------------------------------------------------
# Helpers de base de datos
# ---------------------------------------------------------------------------
def get_connection():
    """Abre y retorna una conexión a MariaDB."""
    return mysql.connector.connect(**DB_CONFIG)


def fetch_all(query: str, params: tuple = ()) -> list[dict]:
    """Ejecuta una SELECT y devuelve lista de dicts."""
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(query, params)
        return cursor.fetchall()
    except DBError as e:
        app.logger.error("DB error en fetch_all: %s", e)
        raise
    finally:
        conn.close()


def _db_unavailable(e: DBError) -> bool:
    """Retorna True si el error indica que la BD no está disponible."""
    return hasattr(e, 'errno') and e.errno in _MYSQL_CANT_CONNECT


# ---------------------------------------------------------------------------
# Manejador de errores global — BD no disponible
# ---------------------------------------------------------------------------
@app.errorhandler(503)
def service_unavailable(e):
    return render_template("error_db.html"), 503


# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    """Página principal: lista de monedas disponibles."""
    try:
        monedas = fetch_all(
            "SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda"
        )
    except DBError as e:
        app.logger.error("BD no disponible en /: %s", e)
        if _db_unavailable(e):
            abort(503)
        raise
    return render_template("index.html", monedas=monedas, selected=None, valores=[])


@app.route("/moneda/<int:id_moneda>")
def detalle_moneda(id_moneda: int):
    """Detalle de una moneda: cotizaciones históricas."""
    try:
        rows = fetch_all(
            "SELECT IDMoneda, Moneda, Clave FROM Moneda WHERE IDMoneda = %s",
            (id_moneda,),
        )
    except DBError as e:
        app.logger.error("BD no disponible en /moneda/%s: %s", id_moneda, e)
        if _db_unavailable(e):
            abort(503)
        raise

    if not rows:
        abort(404)

    selected = rows[0]

    try:
        valores = fetch_all(
            """
            SELECT
                DATE_FORMAT(Fecha, '%%d/%%m/%%Y') AS FechaFormateada,
                Fecha,
                ROUND(Valor, 4)                   AS Valor
            FROM  Valor
            WHERE IDMoneda = %s
            ORDER BY Fecha DESC
            """,
            (id_moneda,),
        )
        monedas = fetch_all(
            "SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda"
        )
    except DBError as e:
        app.logger.error("BD no disponible cargando detalle moneda %s: %s", id_moneda, e)
        if _db_unavailable(e):
            abort(503)
        raise

    return render_template(
        "index.html",
        monedas=monedas,
        selected=selected,
        valores=valores,
    )


# ---------------------------------------------------------------------------
# Health check endpoint (usado por Instana para liveness)
# ---------------------------------------------------------------------------
@app.route("/health")
def health():
    """Endpoint de health check para Instana y monitoreo externo."""
    try:
        conn = get_connection()
        conn.close()
        return {"status": "ok", "db": "connected"}, 200
    except DBError as e:
        app.logger.error("Health check falló — BD no disponible: %s", e)
        return {"status": "error", "db": "disconnected", "detail": str(e)}, 503


# ---------------------------------------------------------------------------
# Punto de entrada
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
