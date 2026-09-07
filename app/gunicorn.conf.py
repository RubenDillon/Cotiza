# gunicorn.conf.py — Configuración de Gunicorn con Instana SDK v3.x
#
# SIN --preload: cada worker importa 'instana' de forma independiente
# al arrancar. Esto garantiza que el background thread del SDK se
# inicializa correctamente en cada worker y puede anunciarse al agente
# Instana en 127.0.0.1:42699.
#
# Con --preload el SDK se inicializaba en el master antes del fork(),
# pero los background threads no sobreviven fork() en Python → los workers
# quedaban sin poder anunciarse → python_sensor_not_installed en Instana UI.

def on_starting(server):
    server.log.info("Cotizacion de Moneda — Gunicorn iniciando (3 workers, Instana por worker)")

def post_fork(server, worker):
    server.log.info("Worker %s listo", worker.pid)
