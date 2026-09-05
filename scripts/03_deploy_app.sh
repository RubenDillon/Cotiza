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
# Directorio raíz del repositorio clonado (donde está este script)
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================================"
echo " Cotización de Moneda — Despliegue de aplicación"
echo "============================================================"

# --- Verificar que se ejecuta como root ---
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
cp "${SRC_DIR}/app/app.py"                    "${APP_DIR}/app/app.py"
cp "${SRC_DIR}/app/wsgi.py"                   "${APP_DIR}/app/wsgi.py"
cp "${SRC_DIR}/app/cotizacion.conf"           "${APP_DIR}/app/cotizacion.conf"
cp "${SRC_DIR}/app/templates/index.html"      "${APP_DIR}/app/templates/index.html"
cp "${SRC_DIR}/app/static/css/styles.css"     "${APP_DIR}/app/static/css/styles.css"
cp "${SRC_DIR}/services/daily_updater.py"     "${APP_DIR}/services/daily_updater.py"
cp "${SRC_DIR}/services/cotizacion-updater.service" "${APP_DIR}/services/cotizacion-updater.service"
cp "${SRC_DIR}/services/cotizacion-updater.timer"   "${APP_DIR}/services/cotizacion-updater.timer"
cp "${SRC_DIR}/services/cotizacion-gunicorn.service" "${APP_DIR}/services/cotizacion-gunicorn.service"
cp "${SRC_DIR}/db/02_schema_and_seed.sql"     "${APP_DIR}/db/02_schema_and_seed.sql"

# --- 4. Instalar dependencias Python en el venv ---
echo "[4/9] Instalando dependencias Python (flask, gunicorn, mysql-connector, requests)..."
"${APP_DIR}/venv/bin/pip" install --upgrade pip --quiet
"${APP_DIR}/venv/bin/pip" install flask mysql-connector-python requests gunicorn --quiet

# --- 5. Aplicar permisos correctos ---
echo "[5/9] Configurando permisos..."
# Dueño general
chown -R cotizacion:cotizacion "${APP_DIR}"
chown -R cotizacion:cotizacion "${LOG_DIR}"

# Directorios: rwxr-xr-x (755) — Apache necesita poder atravesarlos
find "${APP_DIR}" -type d -exec chmod 755 {} \;

# Archivos Python y templates: rw-r--r-- (644)
find "${APP_DIR}/app"      -type f -exec chmod 644 {} \;
find "${APP_DIR}/services" -type f -exec chmod 644 {} \;
find "${APP_DIR}/db"       -type f -exec chmod 644 {} \;

# Venv: binarios ejecutables
find "${APP_DIR}/venv/bin" -type f ! -name "*.py" ! -name "*.cfg" -exec chmod 755 {} \;
chmod 755 "${APP_DIR}/venv/bin/python" "${APP_DIR}/venv/bin/python3" || true

# Limpiar __pycache__ previos que pudieran ser de root
find "${APP_DIR}" -name "__pycache__" -exec chown -R cotizacion:cotizacion {} \; 2>/dev/null || true
find "${APP_DIR}" -name "__pycache__" -exec chmod 755 {} \; 2>/dev/null || true

# --- 6. Configurar SELinux ---
echo "[6/9] Configurando SELinux..."
# Contexto de contenido web para que Apache lea los estáticos
semanage fcontext -a -t httpd_sys_content_t "${APP_DIR}(/.*)?" 2>/dev/null || \
    semanage fcontext -m -t httpd_sys_content_t "${APP_DIR}(/.*)?" 2>/dev/null || true
restorecon -Rv "${APP_DIR}" 2>/dev/null || true
# Permitir que Apache haga proxy al socket de gunicorn
setsebool -P httpd_can_network_connect 1
# Permitir que Apache acceda a sockets UNIX en /run
setsebool -P httpd_read_user_content 1

# --- 7. Configurar Apache como proxy reverso ---
echo "[7/9] Configurando Apache (proxy reverso a Gunicorn)..."
# mod_proxy y mod_headers vienen incluidos en httpd de RHEL 9.
# NO se instala mod_ssl: si el ssl.conf de una instalación previa existe sin
# certificado, rompe Apache. TLS se configura por separado cuando sea necesario.

# Si ssl.conf existe pero no tiene certificado, deshabilitarlo para evitar errores
if [ -f /etc/httpd/conf.d/ssl.conf ]; then
    if ! [ -f /etc/pki/tls/certs/localhost.crt ]; then
        mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.disabled
        echo "     → ssl.conf deshabilitado (sin certificado TLS disponible)."
    fi
fi

# Copiar VirtualHost
cp "${APP_DIR}/app/cotizacion.conf" /etc/httpd/conf.d/cotizacion.conf

systemctl restart httpd

# --- 8. Instalar y habilitar los servicios systemd ---
echo "[8/9] Instalando servicios systemd..."

# Servicio Gunicorn (servidor de aplicación — siempre corriendo)
cp "${APP_DIR}/services/cotizacion-gunicorn.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cotizacion-gunicorn.service
echo "     → cotizacion-gunicorn.service habilitado y corriendo."

# Timer actualizador de cotizaciones (dispara a las 18:00 hs)
cp "${APP_DIR}/services/cotizacion-updater.service" /etc/systemd/system/
cp "${APP_DIR}/services/cotizacion-updater.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cotizacion-updater.timer
echo "     → cotizacion-updater.timer habilitado (18:00 hs diario)."

# --- 9. Cargar schema y datos en MariaDB ---
echo "[9/9] Cargando schema y datos en MariaDB..."
mariadb -u root -p'RootPassword#2025' < "${APP_DIR}/db/02_schema_and_seed.sql"

# Ejecutar primera actualización de cotizaciones reales
echo ""
echo "     → Ejecutando primera actualización de cotizaciones desde BCRA..."
systemctl start cotizacion-updater.service && \
    echo "     ✔ Primera actualización completada." || \
    echo "     ⚠ Primera actualización con errores. Ver: journalctl -u cotizacion-updater.service"

# Verificar que gunicorn responde
sleep 2
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
echo "============================================================"
