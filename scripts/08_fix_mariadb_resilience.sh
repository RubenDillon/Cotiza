#!/bin/bash
# =============================================================================
# Script: 08_fix_mariadb_resilience.sh
# Descripción: Mejora la resiliencia de MariaDB ante caídas:
#   1. Aplica drop-in systemd para reinicio más rápido y más reintentos
#   2. Diagnostica la causa de las caídas recientes (OOM, disco, logs)
#   3. Configura innodb_buffer_pool_size acorde a la RAM disponible
#
# Ejecutar como: sudo bash 08_fix_mariadb_resilience.sh
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutar como root"
    exit 1
fi

echo "============================================================"
echo " MariaDB — Diagnóstico y mejora de resiliencia"
echo "============================================================"

# --- 1. Diagnóstico de caídas recientes ---
echo ""
echo "[1/4] Historial de reinicios de MariaDB (últimas 24 horas):"
journalctl -u mariadb --since "24 hours ago" \
    | grep -E "Started|Stopped|Failed|Restarting|OOM|killed" \
    | tail -20 || echo "     (sin eventos recientes)"

echo ""
echo "[1/4] OOM killer (últimas 24 horas):"
journalctl -k --since "24 hours ago" \
    | grep -iE "oom|killed process|mariadb" \
    | tail -10 || echo "     (sin eventos OOM)"

echo ""
echo "[1/4] Espacio en disco:"
df -h / /var/lib/mysql 2>/dev/null || df -h /

echo ""
echo "[1/4] Memoria disponible:"
free -h

# --- 2. Calcular innodb_buffer_pool_size óptimo ---
echo ""
echo "[2/4] Calculando innodb_buffer_pool_size óptimo..."
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
# Regla: 50-70% de la RAM para innodb_buffer_pool en servidor dedicado
# En una VM compartida usamos 40% para no presionar al OOM killer
BUFFER_MB=$((TOTAL_RAM_MB * 40 / 100))
# Redondear a múltiplo de 128MB
BUFFER_MB=$(( (BUFFER_MB / 128) * 128 ))
[[ $BUFFER_MB -lt 128 ]] && BUFFER_MB=128
echo "     RAM total: ${TOTAL_RAM_MB} MB"
echo "     innodb_buffer_pool_size recomendado: ${BUFFER_MB} MB (40% de RAM)"

# Aplicar configuración si no existe o es diferente
MARIADB_CONF="/etc/my.cnf.d/cotizacion-tuning.cnf"
if [[ ! -f "${MARIADB_CONF}" ]]; then
    cat > "${MARIADB_CONF}" << EOF
# Tuning de MariaDB para la VM de Cotización de Moneda
# Generado por 08_fix_mariadb_resilience.sh — $(date)
[mysqld]
# Limitar buffer pool al 40% de RAM para evitar presión de memoria
innodb_buffer_pool_size = ${BUFFER_MB}M

# Reducir timeout de conexiones inactivas (default: 28800s = 8h)
wait_timeout    = 600
interactive_timeout = 600

# Log de errores explícito
log_error = /var/log/mariadb/mariadb.log

# Reintentar transacciones que fallan por deadlock
innodb_deadlock_detect = ON
EOF
    echo "     ✔ Configuración de tuning creada en ${MARIADB_CONF}"
else
    echo "     → ${MARIADB_CONF} ya existe, no se modifica."
fi

# --- 3. Aplicar drop-in systemd para reinicio más rápido ---
echo ""
echo "[3/4] Aplicando drop-in systemd para resiliencia de MariaDB..."
DROP_IN_DIR="/etc/systemd/system/mariadb.service.d"
mkdir -p "${DROP_IN_DIR}"
cat > "${DROP_IN_DIR}/cotizacion-resilience.conf" << 'DROPIN'
[Service]
Restart=always
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=10
DROPIN

systemctl daemon-reload
echo "     ✔ Drop-in aplicado: reinicio en 5s, hasta 10 reintentos en 5 min."

# --- 4. Reiniciar MariaDB para aplicar la configuración ---
echo ""
echo "[4/4] Reiniciando MariaDB para aplicar configuración..."
systemctl restart mariadb
sleep 3

if systemctl is-active --quiet mariadb; then
    echo "     ✔ MariaDB activo."
    echo ""
    echo "     Variables activas:"
    mariadb -u root -p'RootPassword#2025' -e \
        "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; \
         SHOW VARIABLES LIKE 'wait_timeout';" 2>/dev/null || true
else
    echo "     ✗ MariaDB no arrancó. Ver: journalctl -u mariadb -n 30"
fi

echo ""
echo "============================================================"
echo " ✔ Resiliencia de MariaDB mejorada."
echo ""
echo " Para monitorear reinicios futuros:"
echo "   journalctl -u mariadb -f"
echo "   journalctl -k -f | grep -i oom"
echo "============================================================"
