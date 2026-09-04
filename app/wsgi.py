"""
wsgi.py — Punto de entrada WSGI para Apache + mod_wsgi
El servidor Apache invoca este módulo para servir la aplicación Flask.
"""
import sys
import os

# Agregar el directorio de la app al path de Python
sys.path.insert(0, '/opt/cotizacion/app')

# Activar el entorno virtual
activate_this = '/opt/cotizacion/venv/bin/activate_this.py'
with open(activate_this) as f:
    exec(f.read(), {'__file__': activate_this})

from app import app as application  # noqa: E402
