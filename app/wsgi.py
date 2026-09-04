"""
wsgi.py — Punto de entrada WSGI para Apache + mod_wsgi
"""
import sys
sys.path.insert(0, '/opt/cotizacion/app')

from app import app as application  # noqa: E402
