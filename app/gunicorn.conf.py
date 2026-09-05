# gunicorn.conf.py — Configuración de Gunicorn con hook para Instana
# Instana necesita inicializarse en cada worker DESPUÉS del fork de Gunicorn.
# El hook post_fork garantiza que el sensor se registra correctamente
# en cada worker con el agente.

import os

# Worker post-fork: inicializar Instana en cada worker
def post_fork(server, worker):
    # Solo inicializar si AUTOWRAPT_BOOTSTRAP está configurado
    if os.environ.get("AUTOWRAPT_BOOTSTRAP") == "instana":
        try:
            import instana
            instana.initialize()
        except Exception as e:
            server.log.warning("Instana init warning: %s", e)


def on_starting(server):
    server.log.info("Cotizacion de Moneda — Gunicorn iniciando con soporte Instana")
