# gunicorn.conf.py — Configuración de Gunicorn
# Instana se inicializa en el proceso master via 'import instana' en app.py
# (cargado con --preload antes del fork). Los workers heredan el estado.

def on_starting(server):
    server.log.info("Cotizacion de Moneda — Gunicorn iniciando")

def post_fork(server, worker):
    server.log.info("Worker %s listo", worker.pid)
