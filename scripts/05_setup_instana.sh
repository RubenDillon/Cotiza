#!/bin/bash
# =============================================================================
# Script: 05_setup_instana.sh
# Descripción: Instala y configura el agente Instana + SDK Python en RHEL 9.6.
#
#   - Instala el agente Instana (one-liner oficial de IBM)
#   - Aplica configuration.yaml (MariaDB, Apache mod_status, host tags)
#   - Verifica que el SDK Python 'instana' está en el venv (ya incluido por
#     03_deploy_app.sh, pero se verifica por si se ejecuta de forma aislada)
#   - Verifica drop-ins INSTANA_IGNORE para servicios Python del sistema
#   - Reinicia todo y verifica el estado final
#
# Prerrequisitos:
#   - Script 03_deploy_app.sh ya ejecutado
#   - Agent key válida de Instana (variable INSTANA_AGENT_KEY o editar abajo)
#
# Ejecutar como: sudo bash 05_setup_instana.sh
# =============================================================================
set -euo pipefail

# ─── CONFIGURACIÓN — editar si cambia el entorno ──────────────────────────────
INSTANA_AGENT_KEY="${INSTANA_AGENT_KEY:-uBp4GXpZQpKrHxMXNcvInQ}"
INSTANA_ENDPOINT_HOST="ingress-orange-saas.instana.io"
INSTANA_ENDPOINT_PORT="443"
APP_DIR="/opt/cotizacion"
AGENT_CONFIG_DIR="/opt/instana/agent/etc/instana"
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# ──────────────────────────────────────────────────────────────────────────────

echo "============================================================"
echo " Cotización de Moneda — Configuración de Instana"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutar como root (sudo bash $0)"
    exit 1
fi

# --- 1. Instalar el agente Instana si no está presente ---
echo "[1/6] Verificando / instalando agente Instana..."
if systemctl is-active --quiet instana-agent 2>/dev/null; then
    echo "     → Agente ya activo, omitiendo instalación."
else
    echo "     → Instalando agente Instana..."
    curl -o /tmp/instana-agent-install.sh \
        -sSL "https://setup.instana.io/agent" \
        --header "Authorization: apitoken ${INSTANA_AGENT_KEY}"

    bash /tmp/instana-agent-install.sh \
        -a "${INSTANA_AGENT_KEY}" \
        -t dynamic \
        -e "${INSTANA_ENDPOINT_HOST}:${INSTANA_ENDPOINT_PORT}" \
        -s

    systemctl enable instana-agent
    systemctl start instana-agent
    sleep 10
    echo "     ✔ Agente Instana instalado y arrancado."
fi

# --- 2. Aplicar configuration.yaml ---
echo "[2/6] Aplicando configuración del agente (configuration.yaml)..."
mkdir -p "${AGENT_CONFIG_DIR}"

if [[ -f "${AGENT_CONFIG_DIR}/configuration.yaml" ]]; then
    cp "${AGENT_CONFIG_DIR}/configuration.yaml" \
       "${AGENT_CONFIG_DIR}/configuration.yaml.bak.$(date +%Y%m%d%H%M%S)"
    echo "     → Backup de configuración previa creado."
fi

cp "${SRC_DIR}/instana/configuration.yaml" "${AGENT_CONFIG_DIR}/configuration.yaml"
echo "     ✔ configuration.yaml aplicado."

# --- 3. Verificar SDK Python instana en el venv ---
echo "[3/6] Verificando SDK Python de Instana en el venv..."
if ! "${APP_DIR}/venv/bin/pip" show instana &>/dev/null; then
    echo "     → instana no encontrado en venv, instalando..."
    "${APP_DIR}/venv/bin/pip" install instana --quiet
fi
INSTANA_VER=$("${APP_DIR}/venv/bin/pip" show instana | grep ^Version | cut -d' ' -f2)
PYTHON_VER=$("${APP_DIR}/venv/bin/python" --version)
echo "     ✔ instana ${INSTANA_VER} en ${PYTHON_VER}"

# --- 4. Verificar drop-ins INSTANA_IGNORE para servicios del sistema ---
echo "[4/6] Verificando drop-ins INSTANA_IGNORE para servicios Python del sistema..."
MISSING=0
for SVC in firewalld tuned tuned-ppd fail2ban rhsm; do
    DROP_IN="/etc/systemd/system/${SVC}.service.d/instana-ignore.conf"
    if systemctl is-active --quiet "${SVC}.service" 2>/dev/null; then
        if [[ ! -f "${DROP_IN}" ]]; then
            mkdir -p "$(dirname "${DROP_IN}")"
            cat > "${DROP_IN}" << DROPIN
[Service]
Environment="INSTANA_IGNORE=true"
DROPIN
            systemctl daemon-reload
            systemctl restart "${SVC}.service"
            echo "     ✔ ${SVC}: drop-in creado y servicio reiniciado."
            MISSING=1
        else
            echo "     ✔ ${SVC}: drop-in ya existe."
        fi
    fi
done
[[ "${MISSING}" -eq 0 ]] || systemctl daemon-reload

# --- 5. Reiniciar servicios ---
echo "[5/6] Reiniciando servicios..."
systemctl restart httpd
systemctl restart cotizacion-gunicorn.service
systemctl restart instana-agent
sleep 8
echo "     ✔ Servicios reiniciados."

# --- 6. Verificación final ---
echo "[6/6] Verificación final..."

# App web
if curl -sf --unix-socket /run/cotizacion/gunicorn.sock http://localhost/ -o /dev/null 2>/dev/null; then
    echo "     ✔ Aplicación Flask responde correctamente."
else
    echo "     ⚠ Flask/Gunicorn no responde — ver: journalctl -u cotizacion-gunicorn.service"
fi

# mod_status
if curl -sf http://127.0.0.1/server-status?auto -o /dev/null 2>/dev/null; then
    echo "     ✔ Apache mod_status responde en /server-status."
else
    echo "     ⚠ mod_status no responde — verificar Apache."
fi

# Agente Instana
if systemctl is-active --quiet instana-agent; then
    echo "     ✔ Agente Instana activo."
else
    echo "     ✗ Agente Instana no activo — ver: journalctl -u instana-agent"
fi

# Verificar variables de entorno en PIDs del sistema
echo ""
echo "     Variables INSTANA_IGNORE en servicios del sistema:"
for SVC in firewalld tuned tuned-ppd fail2ban rhsm; do
    PID=$(systemctl show -p MainPID "${SVC}.service" 2>/dev/null | cut -d= -f2)
    if [[ -n "${PID}" && "${PID}" != "0" ]]; then
        VAL=$(cat "/proc/${PID}/environ" 2>/dev/null | tr '\0' '\n' | grep "^INSTANA_IGNORE" || echo "NO ENCONTRADO")
        echo "       PID ${PID} (${SVC}): ${VAL}"
    fi
done

VM_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " ✔ Instana configurado correctamente."
echo ""
echo "   Host           : $(hostname)"
echo "   IP             : ${VM_IP}"
echo "   Aplicación     : http://${VM_IP}"
echo "   Endpoint Instana: ${INSTANA_ENDPOINT_HOST}:${INSTANA_ENDPOINT_PORT}"
echo ""
echo "   En ~2 min el agente detectará automáticamente:"
echo "     - Apache HTTPd"
echo "     - MariaDB"
echo "     - PHP runtime"
echo "     - Python apps (cotizacion-moneda-web)"
echo ""
echo "   Verificar log del agente:"
echo "     grep 'Activated' /opt/instana/agent/data/log/agent.log | tail -20"
echo "     grep 'python_sensor' /opt/instana/agent/data/log/agent.log | tail -5"
echo "============================================================"
