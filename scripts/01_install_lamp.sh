#!/bin/bash
# =============================================================================
# Script: 01_install_lamp.sh
# Descripción: Instalación del stack LAMP en RHEL 9.6 (paquetes oficiales Red Hat)
#              SIN repositorios comunitarios (sin EPEL, sin Remi, sin CentOS Stream)
# Requisitos: Suscripción activa a Red Hat Subscription Manager (RHSM)
#             Ejecutar como root o con sudo
# =============================================================================
set -euo pipefail

echo "============================================================"
echo " Cotización de Moneda - Instalación LAMP en RHEL 9.6"
echo "============================================================"

# --- Verificar suscripción Red Hat activa ---
echo "[1/7] Verificando suscripción Red Hat..."
subscription-manager status || { echo "ERROR: Sin suscripción RHSM activa. Ejecute: subscription-manager register"; exit 1; }

# --- Habilitar únicamente los repos oficiales necesarios ---
echo "[2/7] Habilitando repositorios oficiales de Red Hat..."
subscription-manager repos \
    --enable=rhel-9-for-x86_64-baseos-rpms \
    --enable=rhel-9-for-x86_64-appstream-rpms

# Seleccionar el módulo AppStream para PHP 8.2 (incluido en RHEL 9.6 AppStream)
dnf module reset php -y
dnf module enable php:8.2 -y

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
echo "[5/7] Instalando MariaDB Server..."
# RHEL 9.6 AppStream incluye MariaDB 10.5 en el módulo mariadb
dnf module reset mariadb -y
dnf module enable mariadb:10.5 -y
dnf install -y mariadb-server mariadb

systemctl enable --now mariadb

# Securizar instalación MariaDB sin interacción manual
mariadb-secure-installation <<EOF

y
RootPassword#2025
RootPassword#2025
y
y
y
y
EOF

# --- Instalar PHP y extensiones necesarias ---
echo "[6/7] Instalando PHP 8.2 y extensiones..."
dnf install -y \
    php \
    php-mysqlnd \
    php-json \
    php-mbstring \
    php-xml \
    php-curl

systemctl restart httpd

# --- Instalar Python 3.11 y pip (incluidos en RHEL 9 AppStream oficial) ---
echo "[7/7] Instalando Python 3.11..."
dnf install -y python3 python3-pip python3-devel gcc

# Instalar dependencias Python de la aplicación en entorno virtual
python3 -m venv /opt/cotizacion/venv
/opt/cotizacion/venv/bin/pip install --upgrade pip
/opt/cotizacion/venv/bin/pip install flask mysql-connector-python requests

echo ""
echo "============================================================"
echo " Instalación LAMP completada exitosamente."
echo " Apache : $(httpd -v | head -1)"
echo " MariaDB: $(mariadb --version)"
echo " PHP    : $(php --version | head -1)"
echo " Python : $(/opt/cotizacion/venv/bin/python --version)"
echo "============================================================"
