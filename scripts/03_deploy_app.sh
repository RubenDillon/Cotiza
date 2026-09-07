#!/bin/bash
# =============================================================================
# Script: 03_deploy_app.sh
# Descripción: Despliega la aplicación Cotización de Moneda en RHEL 9.6.
#              Arquitectura: Flask + Gunicorn + Apache (proxy reverso)
#              Debe ejecutarse DESPUÉS de 01_install_lamp.sh
# Ejecutar como: sudo bash 03_deploy_app.sh
# =============================================================================
set -euo pipefail

APP_DIR="/opt/cotizacion"
LOG_DIR="/var/log/cotizacion"
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================================"
echo " Cotización de Moneda — Despliegue de aplicación"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo bash $0)"
    exit 1
fi

# --- 1. Crear usuario del sistema dedicado (sin shell, sin home de login) ---
echo "[1/9] Creando usuario del sistema 'cotizacion'..."
if ! id cotizacion &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin cotizacion
    echo "     → Usuario 'cotizacion' creado."
else
    echo "     → Usuario 'cotizacion' ya existe."
fi

# --- 2. Crear estructura de directorios ---
echo "[2/9] Creando directorios..."
mkdir -p "${APP_DIR}/app/templates"
mkdir -p "${APP_DIR}/app/static/css"
mkdir -p "${APP_DIR}/services"
mkdir -p "${APP_DIR}/db"
mkdir -p "${LOG_DIR}"

# --- 3. Copiar archivos de la aplicación ---
echo "[3/9] Copiando archivos de la aplicación..."
cp "${SRC_DIR}/app/app.py"                          "${APP_DIR}/app/app.py"
cp "${SRC_DIR}/app/wsgi.py"                         "${APP_DIR}/app/wsgi.py"
cp "${SRC_DIR}/app/gunicorn.conf.py"                "${APP_DIR}/app/gunicorn.conf.py"
cp "${SRC_DIR}/app/cotizacion.conf"                 "${APP_DIR}/app/cotizacion.conf"
cp "${SRC_DIR}/app/templates/index.html"            "${APP_DIR}/app/templates/index.html"
cp "${SRC_DIR}/app/static/css/styles.css"           "${APP_DIR}/app/static/css/styles.css"
cp "${SRC_DIR}/services/daily_updater.py"            "${APP_DIR}/services/daily_updater.py"
cp "${SRC_DIR}/services/traffic_simulator.py"        "${APP_DIR}/services/traffic_simulator.py"
cp "${SRC_DIR}/services/cotizacion-updater.service"  "${APP_DIR}/services/cotizacion-updater.service"
cp "${SRC_DIR}/services/cotizacion-updater.timer"    "${APP_DIR}/services/cotizacion-updater.timer"
cp "${SRC_DIR}/services/cotizacion-gunicorn.service" "${APP_DIR}/services/cotizacion-gunicorn.service"
cp "${SRC_DIR}/services/cotizacion-traffic.service"  "${APP_DIR}/services/cotizacion-traffic.service"
cp "${SRC_DIR}/db/02_schema_and_seed.sql"            "${APP_DIR}/db/02_schema_and_seed.sql"

# --- 4. Verificar / completar dependencias Python en el venv ---
echo "[4/9] Verificando dependencias Python en el venv..."
# El venv debe existir con Python 3.11 (creado por 01_install_lamp.sh).
# Si no existe, lo creamos ahora.
if [[ ! -f "${APP_DIR}/venv/bin/python" ]]; then
    echo "     → Venv no encontrado. Creando con Python 3.11..."
    python3.11 -m venv "${APP_DIR}/venv"
fi

PYVER=$("${APP_DIR}/venv/bin/python" --version 2>&1)
echo "     → Python en venv: ${PYVER}"

"${APP_DIR}/venv/bin/pip" install --upgrade pip --quiet
"${APP_DIR}/venv/bin/pip" install \
    flask \
    mysql-connector-python \
    requests \
    gunicorn \
    instana \
    --quiet
echo "     ✔ Dependencias instaladas (incluido instana SDK)."

# --- 5. Aplicar permisos correctos ---
echo "[5/9] Configurando permisos..."
chown -R cotizacion:cotizacion "${APP_DIR}"
chown -R cotizacion:cotizacion "${LOG_DIR}"
find "${APP_DIR}" -type d -exec chmod 755 {} \;
find "${APP_DIR}/app"      -type f -exec chmod 644 {} \;
find "${APP_DIR}/services" -type f -exec chmod 644 {} \;
find "${APP_DIR}/db"       -type f -exec chmod 644 {} \;
find "${APP_DIR}/venv/bin" -type f ! -name "*.py" ! -name "*.cfg" -exec chmod 755 {} \;
find "${APP_DIR}" -name "__pycache__" -exec chown -R cotizacion:cotizacion {} \; 2>/dev/null || true

# --- 6. Configurar SELinux ---
echo "[6/9] Configurando SELinux..."
semanage fcontext -a -t httpd_sys_content_t "${APP_DIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t httpd_sys_content_t "${APP_DIR}(/.*)?" 2>/dev/null || true
restorecon -Rv "${APP_DIR}" 2>/dev/null || true
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_read_user_content 1

# --- 7. Configurar Apache ---
echo "[7/9] Configurando Apache (proxy reverso + mod_status para Instana)..."

# Deshabilitar ssl.conf si no hay certificado TLS (evita error al arrancar)
if [[ -f /etc/httpd/conf.d/ssl.conf ]] && [[ ! -f /etc/pki/tls/certs/localhost.crt ]]; then
    mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.disabled
    echo "     → ssl.conf deshabilitado (sin certificado TLS)."
fi

# VirtualHost proxy reverso
cp "${APP_DIR}/app/cotizacion.conf" /etc/httpd/conf.d/cotizacion.conf

# mod_status para Instana (solo accesible desde localhost)
cat > /etc/httpd/conf.d/instana-status.conf << 'EOF'
# mod_status para Instana — solo accesible desde localhost
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>
<Location "/server-info">
    Require all denied
</Location>
EOF

systemctl restart httpd
echo "     ✔ Apache configurado."

# --- 8. Instalar servicios systemd ---
echo "[8/9] Instalando servicios systemd..."

# Drop-ins INSTANA_IGNORE para servicios Python del sistema RHEL.
# El agente Instana v1.x intenta instrumentar cualquier proceso Python que encuentre.
# Los servicios del sistema usan /usr/bin/python3 (3.9) sin el SDK de Instana →
# generan 'python_sensor_not_installed'. La variable INSTANA_IGNORE=true los excluye.
echo "     → Creando drop-ins INSTANA_IGNORE para servicios Python del sistema..."
for SVC in firewalld tuned tuned-ppd fail2ban rhsm; do
    if systemctl is-active --quiet "${SVC}.service" 2>/dev/null; then
        DROP_IN_DIR="/etc/systemd/system/${SVC}.service.d"
        mkdir -p "${DROP_IN_DIR}"
        cat > "${DROP_IN_DIR}/instana-ignore.conf" << DROPIN
[Service]
Environment="INSTANA_IGNORE=true"
DROPIN
        echo "       ✔ ${SVC}: drop-in creado."
    fi
done

# Servicio Gunicorn
cp "${APP_DIR}/services/cotizacion-gunicorn.service" /etc/systemd/system/
# Timer actualizador de cotizaciones
cp "${APP_DIR}/services/cotizacion-updater.service"  /etc/systemd/system/
cp "${APP_DIR}/services/cotizacion-updater.timer"    /etc/systemd/system/
# Simulador de tráfico
cp "${APP_DIR}/services/cotizacion-traffic.service"  /etc/systemd/system/

systemctl daemon-reload

# Reiniciar servicios del sistema para que tomen INSTANA_IGNORE
for SVC in firewalld tuned tuned-ppd fail2ban rhsm; do
    systemctl is-active --quiet "${SVC}.service" 2>/dev/null && \
        systemctl restart "${SVC}.service" && \
        echo "       ✔ ${SVC} reiniciado con INSTANA_IGNORE=true." || true
done

systemctl enable --now cotizacion-gunicorn.service
echo "     ✔ cotizacion-gunicorn.service habilitado y corriendo."

systemctl enable --now cotizacion-updater.timer
echo "     ✔ cotizacion-updater.timer habilitado (18:00 hs diario)."

systemctl enable --now cotizacion-traffic.service
echo "     ✔ cotizacion-traffic.service habilitado (~10 req/min 24x7)."

# --- 9. Cargar schema y datos en MariaDB ---
echo "[9/9] Cargando schema y datos en MariaDB..."
mariadb -u root -p'RootPassword#2025' < "${APP_DIR}/db/02_schema_and_seed.sql"
echo "     ✔ Schema y datos cargados."

# Ejecutar primera actualización de cotizaciones reales
echo "     → Ejecutando primera actualización desde la API del BCRA..."
systemctl start cotizacion-updater.service && \
    echo "     ✔ Primera actualización completada." || \
    echo "     ⚠ Primera actualización con errores. Ver: journalctl -u cotizacion-updater.service"

# Verificar que Gunicorn responde
sleep 3
if curl -sf --unix-socket /run/cotizacion/gunicorn.sock http://localhost/ -o /dev/null; then
    echo "     ✔ Gunicorn responde correctamente."
else
    echo "     ⚠ Gunicorn no responde aún. Ver: journalctl -u cotizacion-gunicorn.service"
fi

VM_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " ✔ Despliegue completado."
echo ""
echo "   Aplicación    : http://${VM_IP}"
echo "   Gunicorn      : systemctl status cotizacion-gunicorn.service"
echo "   Timer BCRA    : systemctl status cotizacion-updater.timer"
echo "   Log gunicorn  : ${LOG_DIR}/gunicorn_error.log"
echo "   Log updater   : ${LOG_DIR}/updater.log"
echo "   Log Apache    : /var/log/httpd/cotizacion_error.log"
echo ""
echo " Siguiente paso (opcional): sudo bash 05_setup_instana.sh"
echo "============================================================"
