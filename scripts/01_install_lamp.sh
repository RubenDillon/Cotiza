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

# --- Verificar que se ejecuta como root ---
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
mariadb --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY 'RootPassword#2025';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# --- Instalar PHP (para completar el stack LAMP; la app usa Python/Flask) ---
echo "[6/7] Instalando PHP 8.2..."
# RHEL 9.6 AppStream incluye PHP 8.2 mediante el módulo php:8.2
dnf module reset php -y
dnf module enable php:8.2 -y
dnf install -y php php-mysqlnd php-json php-mbstring php-xml php-curl

systemctl restart httpd

# --- Instalar Python 3.11 (incluido en RHEL 9 AppStream oficial) ---
echo "[7/7] Instalando Python 3.11 y herramientas..."
dnf install -y python3 python3-pip python3-devel gcc

# Crear directorio base de la aplicación
mkdir -p /opt/cotizacion

# Instalar entorno virtual Python para la app
python3 -m venv /opt/cotizacion/venv
/opt/cotizacion/venv/bin/pip install --upgrade pip --quiet
/opt/cotizacion/venv/bin/pip install flask mysql-connector-python requests gunicorn --quiet

echo ""
echo "============================================================"
echo " Instalación LAMP completada exitosamente."
echo ""
echo " Apache : $(httpd -v | head -1)"
echo " MariaDB: $(mariadb --version)"
echo " PHP    : $(php --version | head -1)"
echo " Python : $(/opt/cotizacion/venv/bin/python --version)"
echo " Gunicorn: $(/opt/cotizacion/venv/bin/gunicorn --version)"
echo ""
echo " Siguiente paso: sudo bash 03_deploy_app.sh"
echo "============================================================"
