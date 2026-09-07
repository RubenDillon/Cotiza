#!/bin/bash
# =============================================================================
# Script: 07_fix_venv_python311.sh
# Descripción: Recrea el entorno virtual de la aplicación usando Python 3.11
#              en lugar de Python 3.9.
#
# Problema: En RHEL 9, 'python3' apunta a Python 3.9 (sistema base).
#           El venv fue creado con python3 → usa Python 3.9.
#           El sensor Python de Instana no soporta Python 3.9, por eso
#           reporta 'python_sensor_not_installed' para los workers de Gunicorn.
#
# Solución: Recrear el venv con python3.11 y reinstalar todas las dependencias
#           incluyendo el paquete 'instana'.
#
# Ejecutar como: sudo bash 07_fix_venv_python311.sh
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutar como root"
    exit 1
fi

APP_DIR="/opt/cotizacion"

echo "============================================================"
echo " Fix: Recrear venv con Python 3.11 (Instana sensor support)"
echo "============================================================"

# --- Verificar que Python 3.11 está disponible ---
echo "[1/5] Verificando Python 3.11..."
if ! command -v python3.11 &>/dev/null; then
    echo "  Python 3.11 no encontrado. Instalando desde AppStream..."
    dnf install -y python3.11 python3.11-pip python3.11-devel gcc
fi
PYVER=$(python3.11 --version)
echo "  ✔ ${PYVER}"

# --- Detener Gunicorn antes de tocar el venv ---
echo "[2/5] Deteniendo cotizacion-gunicorn.service..."
systemctl stop cotizacion-gunicorn.service
echo "  ✔ Gunicorn detenido."

# --- Eliminar venv viejo (Python 3.9) ---
echo "[3/5] Eliminando venv antiguo (Python 3.9)..."
rm -rf "${APP_DIR}/venv"
echo "  ✔ Venv eliminado."

# --- Crear venv nuevo con Python 3.11 ---
echo "[4/5] Creando venv con Python 3.11..."
python3.11 -m venv "${APP_DIR}/venv"

# Verificar que el nuevo venv usa 3.11
VENV_VER=$("${APP_DIR}/venv/bin/python" --version)
echo "  ✔ Venv creado: ${VENV_VER}"

# Instalar dependencias
echo "  → Instalando dependencias Python..."
"${APP_DIR}/venv/bin/pip" install --upgrade pip --quiet
"${APP_DIR}/venv/bin/pip" install \
    flask \
    mysql-connector-python \
    requests \
    gunicorn \
    instana \
    --quiet
echo "  ✔ Dependencias instaladas."

# Verificar instana
INSTANA_VER=$("${APP_DIR}/venv/bin/pip" show instana | grep ^Version | cut -d' ' -f2)
echo "  ✔ instana ${INSTANA_VER} instalado en Python 3.11"

# Restaurar permisos
chown -R cotizacion:cotizacion "${APP_DIR}/venv"
find "${APP_DIR}/venv/bin" -type f ! -name "*.py" ! -name "*.cfg" -exec chmod 755 {} \;

# --- Reiniciar Gunicorn ---
echo "[5/5] Reiniciando cotizacion-gunicorn.service..."
systemctl start cotizacion-gunicorn.service
sleep 3

# Verificar estado
if systemctl is-active --quiet cotizacion-gunicorn.service; then
    echo "  ✔ Gunicorn corriendo."
else
    echo "  ✗ Gunicorn falló. Ver: journalctl -u cotizacion-gunicorn.service -n 20"
    journalctl -u cotizacion-gunicorn.service -n 20 --no-pager
    exit 1
fi

# Mostrar PIDs actuales
echo ""
echo "PIDs de Gunicorn (deben aparecer en Instana en ~2 min):"
ps aux | grep "[g]unicorn" | awk '{print "  PID " $2 ": " $11}'

echo ""
echo "Verificando que el venv usa Python 3.11:"
ls -la "${APP_DIR}/venv/bin/python"*

echo ""
echo "============================================================"
echo " ✔ Venv recreado con Python 3.11."
echo " Esperar ~2 minutos y verificar en Instana UI."
echo ""
echo " Para confirmar sin errores en el agente:"
echo "  grep 'python_sensor' /opt/instana/agent/data/log/agent.log | tail -10"
echo "  grep 'Activated.*9[0-9][0-9][0-9]' /opt/instana/agent/data/log/agent.log | tail -5"
echo "============================================================"
