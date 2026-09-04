"""
app.py — Aplicación Flask: Cotización de Moneda
Descripción: Frontend web que muestra las monedas disponibles y sus
             cotizaciones históricas consultadas al BCRA.
Entorno:     Python 3.11 / Flask / MariaDB (RHEL 9.6)
"""

import os
from datetime import date
from flask import Flask, render_template, abort
import mysql.connector
from mysql.connector import Error as DBError

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


# ---------------------------------------------------------------------------
# Rutas
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    """
    Página principal: lista de monedas y, si se pasa ?moneda=<id>,
    los valores históricos de esa moneda en el panel derecho.
    """
    monedas = fetch_all(
        "SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda"
    )
    return render_template("index.html", monedas=monedas, selected=None, valores=[])


@app.route("/moneda/<int:id_moneda>")
def detalle_moneda(id_moneda: int):
    """
    Detalle de una moneda: muestra nombre, clave BCRA y sus
    últimas cotizaciones ordenadas por fecha descendente.
    """
    # Traer la moneda seleccionada
    rows = fetch_all(
        "SELECT IDMoneda, Moneda, Clave FROM Moneda WHERE IDMoneda = %s",
        (id_moneda,),
    )
    if not rows:
        abort(404)

    selected = rows[0]

    # Traer todos los valores históricos disponibles para esa moneda
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

    # Todas las monedas para el panel izquierdo
    monedas = fetch_all(
        "SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda"
    )

    return render_template(
        "index.html",
        monedas=monedas,
        selected=selected,
        valores=valores,
    )


# ---------------------------------------------------------------------------
# Punto de entrada (desarrollo / wsgi)
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
