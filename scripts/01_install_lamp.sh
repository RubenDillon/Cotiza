#!/bin/bash
# =============================================================================
# Script: 01_install_lamp.sh
# Descripción: Instalación del stack LAMP en RHEL 9.6 (paquetes oficiales Red Hat)
#              SIN repositorios comunitarios (sin EPEL, sin Remi, sin CentOS Stream)
# Requisitos : Suscripción activa a Red Hat Subscription Manager (RHSM)
#              Ejecutar como root o con sudo
# =============================================================================
set -euo pipefail

echo "============================================================"
echo " Cotización de Moneda — Instalación LAMP en RHEL 9.6"
echo "============================================================"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Este script debe ejecutarse como root (sudo bash $0)"
    exit 1
fi

# --- Verificar suscripción Red Hat activa ---
echo "[1/7] Verificando suscripción Red Hat..."
subscription-manager status || {
    echo "ERROR: Sin suscripción RHSM activa."
    echo "       Ejecute: subscription-manager register --username <user> --password <pass> --auto-attach"
    exit 1
}

# --- Habilitar únicamente los repos oficiales necesarios ---
echo "[2/7] Habilitando repositorios oficiales de Red Hat..."
subscription-manager repos \
    --enable=rhel-9-for-x86_64-baseos-rpms \
    --enable=rhel-9-for-x86_64-appstream-rpms

# --- Actualizar el sistema ---
echo "[3/7] Actualizando el sistema base..."
dnf update -y

# --- Instalar Apache HTTP Server ---
echo "[4/7] Instalando Apache HTTP Server (httpd)..."
dnf install -y httpd
systemctl enable --now httpd
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# --- Instalar MariaDB Server ---
# NOTA: En RHEL 9.6 MariaDB 10.5 está disponible como paquete directo en
#       el canal AppStream. NO existe el módulo DNF "mariadb:10.5" (eso era RHEL 8).
echo "[5/7] Instalando MariaDB Server..."
dnf install -y mariadb-server mariadb
systemctl enable --now mariadb

# Securizar instalación MariaDB de forma no interactiva
mariadb --user=root <<'EOSQL'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'RootPassword#2025';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOSQL

# --- Instalar PHP (para completar el stack LAMP) ---
echo "[6/7] Instalando PHP 8.2..."
dnf module reset php -y
dnf module enable php:8.2 -y
dnf install -y php php-mysqlnd php-json php-mbstring php-xml php-curl
systemctl restart httpd

# --- Instalar Python 3.11 ---
# IMPORTANTE: En RHEL 9, 'python3' apunta a Python 3.9 (sistema base).
# Python 3.11 está en AppStream como paquete 'python3.11'.
# Se debe usar python3.11 explícitamente para el venv de la aplicación,
# ya que el sensor Python de Instana requiere Python 3.10+.
echo "[7/7] Instalando Python 3.11 y creando entorno virtual..."
dnf install -y python3.11 python3.11-pip python3.11-devel gcc
python3.11 --version

# Crear usuario del sistema para la aplicación
if ! id cotizacion &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin cotizacion
fi

# Crear directorio base y venv con Python 3.11
mkdir -p /opt/cotizacion
python3.11 -m venv /opt/cotizacion/venv
/opt/cotizacion/venv/bin/pip install --upgrade pip --quiet
/opt/cotizacion/venv/bin/pip install \
    flask \
    mysql-connector-python \
    requests \
    gunicorn \
    instana \
    --quiet

chown -R cotizacion:cotizacion /opt/cotizacion/venv

echo ""
echo "============================================================"
echo " Instalación LAMP completada exitosamente."
echo ""
echo " Apache  : $(httpd -v | head -1)"
echo " MariaDB : $(mariadb --version)"
echo " PHP     : $(php --version | head -1)"
echo " Python  : $(/opt/cotizacion/venv/bin/python --version)"
echo " Gunicorn: $(/opt/cotizacion/venv/bin/gunicorn --version)"
echo " instana : $(/opt/cotizacion/venv/bin/pip show instana | grep Version)"
echo ""
echo " Siguiente paso: sudo bash 03_deploy_app.sh"
echo "============================================================"
