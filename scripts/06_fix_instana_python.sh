#!/bin/bash
# =============================================================================
# Script: 06_fix_instana_python.sh
# Descripción: Agrega INSTANA_IGNORE=true a los servicios del sistema RHEL
#              que usan /usr/bin/python3 para que el agente Instana no intente
#              instrumentarlos y deje de generar python_sensor_not_installed.
#
# El agente Instana (modo DEFAULT) ignora procesos que tienen:
#   INSTANA_IGNORE=<cualquier valor>  OR  INSTANA_MONITORING=false
# (confirmado en agent.log: "will monitor all Processes except with env var
#  INSTANA_IGNORE=(any value) OR INSTANA_MONITORING=false")
#
# Ejecutar como: sudo bash 06_fix_instana_python.sh
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Ejecutar como root"
    exit 1
fi

echo "============================================================"
echo " Fix: INSTANA_IGNORE para servicios Python del sistema RHEL"
echo "============================================================"

# Lista de servicios del sistema que usan /usr/bin/python3
SERVICES=(
    "firewalld"
    "tuned"
    "tuned-ppd"
    "fail2ban"
    "rhsm"
)

for SVC in "${SERVICES[@]}"; do
    UNIT_FILE=$(systemctl show -p FragmentPath "${SVC}.service" 2>/dev/null | cut -d= -f2)

    if [[ -z "${UNIT_FILE}" ]] || ! systemctl is-active --quiet "${SVC}.service" 2>/dev/null; then
        echo "  ⚠ ${SVC}: no activo o no encontrado, omitiendo."
        continue
    fi

    DROP_IN_DIR="/etc/systemd/system/${SVC}.service.d"
    DROP_IN_FILE="${DROP_IN_DIR}/instana-ignore.conf"

    mkdir -p "${DROP_IN_DIR}"
    cat > "${DROP_IN_FILE}" <<EOF
# Indica al agente Instana que no instrumente este servicio.
# El agente respeta: INSTANA_IGNORE=(any value) OR INSTANA_MONITORING=false
[Service]
Environment="INSTANA_IGNORE=true"
EOF
    echo "  ✔ ${SVC}: drop-in creado en ${DROP_IN_FILE}"
done

systemctl daemon-reload

# Reiniciar los servicios para que tomen la variable
# (solo los que están activos)
echo ""
echo "Reiniciando servicios afectados..."
for SVC in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "${SVC}.service" 2>/dev/null; then
        systemctl restart "${SVC}.service" && echo "  ✔ ${SVC} reiniciado" || \
            echo "  ⚠ ${SVC}: error al reiniciar"
    fi
done

echo ""
echo "============================================================"
echo " ✔ Drop-ins creados. Verificar en 2 min en Instana UI."
echo " Los errores python_sensor_not_installed de /usr/bin/python3"
echo " deben desaparecer del agente itzvsi0-vmn4bn1k."
echo "============================================================"
