#!/bin/bash
# =============================================================================
# Script: 05_setup_instana.sh
# Descripción: Configura la integración de la aplicación Cotización de Moneda
#              con el agente Instana ya instalado en la VM.
#              - Instala el SDK Python de Instana en el venv
#              - Configura el agente (configuration.yaml)
#              - Habilita mod_status en Apache para métricas httpd
#              - Reinicia los servicios
# Requisitos : Agente Instana ya instalado en /opt/instana/agent
#              Script 03_deploy_app.sh ya ejecutado
# Ejecutar como: sudo bash 05_setup_instana.sh
# =============================================================================
set -euo pipefail

APP_DIR="/opt/cotizacion"
AGENT_CONFIG_DIR="/opt/instana/agent/etc/instana"
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================================"
echo " Cotización de Moneda — Configuración de Instana"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutar como root (sudo bash $0)"
    exit 1
fi

# --- 1. Verificar que el agente Instana está instalado ---
echo "[1/6] Verificando agente Instana..."
if ! systemctl is-active --quiet instana-agent; then
    echo "ERROR: El agente Instana no está corriendo."
    echo "       Instalá el agente primero desde: https://www.ibm.com/docs/en/instana-observability"
    exit 1
fi
echo "     ✔ Agente Instana activo."

# --- 2. Instalar SDK Python de Instana en el venv ---
echo "[2/6] Instalando SDK Python de Instana..."
"${APP_DIR}/venv/bin/pip" install instana --quiet
echo "     ✔ instana SDK instalado: $("${APP_DIR}/venv/bin/pip" show instana | grep Version)"

# --- 3. Copiar configuración del agente ---
echo "[3/6] Configurando agente Instana..."
mkdir -p "${AGENT_CONFIG_DIR}"

# Hacer backup si existe configuración previa
if [ -f "${AGENT_CONFIG_DIR}/configuration.yaml" ]; then
    cp "${AGENT_CONFIG_DIR}/configuration.yaml" \
       "${AGENT_CONFIG_DIR}/configuration.yaml.bak.$(date +%Y%m%d%H%M%S)"
    echo "     → Backup de configuración previa creado."
fi

cp "${SRC_DIR}/instana/configuration.yaml" "${AGENT_CONFIG_DIR}/configuration.yaml"
echo "     ✔ configuration.yaml aplicado."

# --- 4. Habilitar mod_status en Apache (necesario para métricas httpd en Instana) ---
echo "[4/6] Habilitando mod_status en Apache..."
cat > /etc/httpd/conf.d/instana-status.conf << 'EOF'
# mod_status para Instana — solo accesible desde localhost
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>

# Deshabilitar acceso externo a server-info
<Location "/server-info">
    Require all denied
</Location>
EOF

echo "     ✔ mod_status habilitado en /server-status (solo localhost)."

# --- 5. Copiar app.py instrumentado y reiniciar Gunicorn ---
echo "[5/6] Aplicando app.py con instrumentación Instana..."
cp "${SRC_DIR}/app/app.py" "${APP_DIR}/app/app.py"
chown cotizacion:cotizacion "${APP_DIR}/app/app.py"
chmod 644 "${APP_DIR}/app/app.py"

# El service file ya incluye las variables INSTANA_* — no hace falta parchear

systemctl daemon-reload
systemctl restart httpd
systemctl restart cotizacion-gunicorn.service
systemctl restart instana-agent

echo "     ✔ Servicios reiniciados."

# --- 6. Verificar que todo responde ---
echo "[6/6] Verificando integración..."
sleep 5

# Verificar health check de la app
if curl -sf http://localhost/health -o /dev/null; then
    echo "     ✔ Endpoint /health responde correctamente."
else
    echo "     ⚠ Endpoint /health no responde — verificar Gunicorn."
fi

# Verificar mod_status
if curl -sf http://localhost/server-status -o /dev/null; then
    echo "     ✔ mod_status de Apache responde correctamente."
else
    echo "     ⚠ mod_status no responde — verificar Apache."
fi

echo ""
echo "============================================================"
echo " ✔ Integración con Instana configurada."
echo ""
echo "   Aplicación en Instana : 'Cotizacion de Moneda'"
echo "   Servicio Flask        : cotizacion-moneda-web"
echo "   Health check          : http://$(hostname -I | awk '{print $1}')/health"
echo "   Apache status         : http://localhost/server-status"
echo ""
echo "   Verificar trazas en   : https://ingress-orange-saas.instana.io"
echo "   Log agente Instana    : journalctl -u instana-agent -f"
echo "============================================================"
