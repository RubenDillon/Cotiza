# gunicorn.conf.py — Configuración de Gunicorn con soporte Instana
# Con --preload Gunicorn carga la app UNA VEZ en el master antes de forkear
# los workers. Instana se inicializa en el master y cada worker hereda el
# estado instrumentado — forma oficial recomendada para Gunicorn + Instana.

def on_starting(server):
    server.log.info("Cotizacion de Moneda — Gunicorn iniciando con soporte Instana")

def post_fork(server, worker):
    server.log.info("Worker %s listo (Instana activo via preload)", worker.pid)
