#!/bin/bash
# =============================================================================
# Script: 03_deploy_app.sh
# Descripción: Despliega la aplicación Cotización de Moneda en RHEL 9.6.
#              Debe ejecutarse DESPUÉS de 01_install_lamp.sh y
#              02_schema_and_seed.sql.
# Ejecutar como: sudo bash 03_deploy_app.sh
# =============================================================================
set -euo pipefail

APP_DIR="/opt/cotizacion"
LOG_DIR="/var/log/cotizacion"
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # raíz del repositorio clonado

echo "============================================================"
echo " Cotización de Moneda — Despliegue de aplicación"
echo "============================================================"

# --- 1. Crear usuario del sistema dedicado (sin shell, sin home de login) ---
echo "[1/8] Creando usuario del sistema 'cotizacion'..."
if ! id cotizacion &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin cotizacion
fi

# --- 2. Crear estructura de directorios ---
echo "[2/8] Creando directorios..."
mkdir -p "${APP_DIR}/app/templates"
mkdir -p "${APP_DIR}/app/static/css"
mkdir -p "${APP_DIR}/services"
mkdir -p "${APP_DIR}/db"
mkdir -p "${LOG_DIR}"

# --- 3. Copiar archivos de la aplicación ---
echo "[3/8] Copiando archivos de la aplicación..."
cp -r "${SRC_DIR}/app/"*           "${APP_DIR}/app/"
cp -r "${SRC_DIR}/services/"*      "${APP_DIR}/services/"
cp    "${SRC_DIR}/db/"*.sql        "${APP_DIR}/db/"

# --- 4. Instalar dependencias Python en el venv ---
echo "[4/8] Instalando dependencias Python..."
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --upgrade pip --quiet
"${APP_DIR}/venv/bin/pip" install flask mysql-connector-python requests --quiet

# --- 5. Aplicar permisos ---
echo "[5/8] Configurando permisos..."
chown -R cotizacion:cotizacion "${APP_DIR}"
chown -R cotizacion:cotizacion "${LOG_DIR}"
chmod -R 750 "${APP_DIR}"
chmod 640 "${APP_DIR}/app/app.py"

# Permisos de SELinux para que Apache lea los archivos de la app
# (RHEL 9 usa SELinux enforcing por defecto)
semanage fcontext -a -t httpd_sys_content_t "${APP_DIR}(/.*)?" 2>/dev/null || true
restorecon -Rv "${APP_DIR}" 2>/dev/null || true
# Permitir que httpd conecte a la red (para API BCRA desde el updater)
setsebool -P httpd_can_network_connect 1

# --- 6. Configurar Apache VirtualHost ---
echo "[6/8] Configurando Apache..."
dnf install -y python3-mod_wsgi --quiet
cp "${APP_DIR}/app/cotizacion.conf" /etc/httpd/conf.d/cotizacion.conf
# Habilitar headers para cabeceras de seguridad
sed -i '/^#LoadModule headers_module/s/^#//' /etc/httpd/conf/httpd.conf 2>/dev/null || \
    echo "LoadModule headers_module modules/mod_headers.so" >> /etc/httpd/conf/httpd.conf
systemctl reload httpd

# --- 7. Configurar el timer systemd ---
echo "[7/8] Instalando timer systemd..."
cp "${APP_DIR}/services/cotizacion-updater.service" /etc/systemd/system/
cp "${APP_DIR}/services/cotizacion-updater.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cotizacion-updater.timer

# Ejecutar primera carga de datos reales ahora
echo "     → Ejecutando primera actualización de cotizaciones..."
systemctl start cotizacion-updater.service || \
    echo "     ⚠ Primera actualización fallida (verificar conectividad/API). Reintentará a las 18:00."

# --- 8. Cargar el schema y datos iniciales de la BD ---
echo "[8/8] Cargando schema y datos en MariaDB..."
mariadb -u root -p"RootPassword#2025" < "${APP_DIR}/db/02_schema_and_seed.sql"

echo ""
echo "============================================================"
echo " ✔ Despliegue completado."
echo ""
echo "   Aplicación : http://$(hostname -I | awk '{print $1}')"
echo "   Timer      : systemctl status cotizacion-updater.timer"
echo "   Logs app   : ${LOG_DIR}/updater.log"
echo "   Logs Apache: /var/log/httpd/cotizacion_error.log"
echo "============================================================"
