#!/usr/bin/env python3
"""
traffic_simulator.py — Simulador de tráfico para Cotización de Moneda
=======================================================================
Simula ~10 conexiones por minuto de usuarios navegando la aplicación.
Cada "sesión" de usuario:
  1. Visita la página principal (/)
  2. Elige una moneda aleatoriamente y visita /moneda/<id>
  3. Con 60% de probabilidad, visita 1-3 monedas adicionales
  4. Pausa entre requests (simula lectura humana)

Corre como servicio systemd las 24 horas.
"""

import random
import time
import logging
import sys
import urllib.request
import urllib.error
from datetime import datetime

# ─── Configuración ────────────────────────────────────────────────────────────
BASE_URL       = "http://127.0.0.1"       # Apache escucha en :80
NUM_MONEDAS    = 10                        # IDs de moneda del 1 al 10
TARGET_RPS     = 10 / 60                   # ~10 requests por minuto = 1 cada 6s
MIN_PAUSE      = 2.0                       # pausa mínima entre páginas (seg)
MAX_PAUSE      = 8.0                       # pausa máxima entre páginas (seg)
SESSION_PAUSE  = 4.0                       # pausa extra entre sesiones (seg)
LOG_FILE       = "/var/log/cotizacion/traffic_simulator.log"
# ──────────────────────────────────────────────────────────────────────────────

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("traffic_simulator")
# ──────────────────────────────────────────────────────────────────────────────

# User-Agents variados para simular distintos navegadores
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.5 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.6422.165 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0",
]


def fetch(path: str, ua: str) -> tuple[int, float]:
    """
    Realiza un GET a BASE_URL+path.
    Retorna (status_code, tiempo_en_segundos).
    """
    url = BASE_URL + path
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()  # consumir el body completo
            elapsed = time.monotonic() - t0
            return resp.status, elapsed
    except urllib.error.HTTPError as e:
        elapsed = time.monotonic() - t0
        return e.code, elapsed
    except Exception as e:
        elapsed = time.monotonic() - t0
        log.warning("Error en GET %s: %s (%.2fs)", url, e, elapsed)
        return 0, elapsed


def simulate_session(session_id: int) -> int:
    """
    Simula una sesión de usuario completa.
    Retorna el número de requests realizados.
    """
    ua = random.choice(USER_AGENTS)
    requests_count = 0

    # 1. Visita la página principal
    status, elapsed = fetch("/", ua)
    requests_count += 1
    log.info(
        "Sesión %04d | GET / → %s (%.2fs) [%s...]",
        session_id, status, elapsed, ua[:40]
    )

    # Pausa de lectura (el usuario "lee" la lista de monedas)
    time.sleep(random.uniform(MIN_PAUSE, MAX_PAUSE))

    # 2. Elige entre 1 y 4 monedas para visitar
    num_visitas = random.choices(
        population=[1, 2, 3, 4],
        weights   =[40, 35, 15, 10],
        k=1
    )[0]

    monedas_a_visitar = random.sample(range(1, NUM_MONEDAS + 1), k=min(num_visitas, NUM_MONEDAS))

    for id_moneda in monedas_a_visitar:
        path = f"/moneda/{id_moneda}"
        status, elapsed = fetch(path, ua)
        requests_count += 1
        log.info(
            "Sesión %04d | GET %s → %s (%.2fs)",
            session_id, path, status, elapsed
        )
        # Pausa entre monedas (el usuario "lee" las cotizaciones)
        time.sleep(random.uniform(MIN_PAUSE, MAX_PAUSE))

    return requests_count


def main():
    log.info("=" * 60)
    log.info("Simulador de tráfico iniciado")
    log.info("  Objetivo  : ~10 conexiones/minuto")
    log.info("  Base URL  : %s", BASE_URL)
    log.info("  Monedas   : 1 a %d", NUM_MONEDAS)
    log.info("=" * 60)

    session_id   = 0
    total_reqs   = 0
    start_global = time.monotonic()

    while True:
        session_id += 1
        t_session_start = time.monotonic()

        try:
            reqs = simulate_session(session_id)
            total_reqs += reqs
        except Exception as e:
            log.error("Error inesperado en sesión %d: %s", session_id, e)

        # Calcular pausa para mantener ~TARGET_RPS requests/segundo global
        session_duration = time.monotonic() - t_session_start
        elapsed_global   = time.monotonic() - start_global

        # Rate actual
        actual_rps = total_reqs / elapsed_global if elapsed_global > 0 else 0

        # Si vamos más rápido que el objetivo, esperamos más
        # Si vamos más lento, reducimos la pausa entre sesiones
        if actual_rps > TARGET_RPS * 1.2:
            extra_wait = SESSION_PAUSE + random.uniform(2.0, 6.0)
        elif actual_rps < TARGET_RPS * 0.8:
            extra_wait = max(1.0, SESSION_PAUSE - 2.0)
        else:
            extra_wait = SESSION_PAUSE + random.uniform(0.0, 3.0)

        log.info(
            "Sesión %04d completada — %d req totales — rate %.2f req/min — "
            "próxima en %.1fs",
            session_id, total_reqs, actual_rps * 60, extra_wait
        )

        time.sleep(extra_wait)


if __name__ == "__main__":
    main()
