# gunicorn.conf.py — Configuración de Gunicorn con hook para Instana
# Instana necesita inicializarse en cada worker DESPUÉS del fork de Gunicorn.
# El hook post_fork garantiza que el sensor se registra correctamente
# en cada worker con el agente.

import os

# Worker post-fork: inicializar Instana en cada worker
def post_fork(server, worker):
    # En instana >= 2.x el simple import activa la instrumentación automática.
    # No existe instana.initialize() — el módulo se auto-inicializa al importarse.
    try:
        import instana  # noqa: F401 — el import activa el sensor
    except ImportError as e:
        server.log.warning("Instana no disponible en este worker: %s", e)


def on_starting(server):
    server.log.info("Cotizacion de Moneda — Gunicorn iniciando con soporte Instana")
