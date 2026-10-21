# AGENT.md — Cotización de Moneda

## Descripción del proyecto
Aplicación web y servicio de monitoreo en **Python 3.11 + Flask** desplegado sobre **RHEL 9.6** utilizando el stack LAMP oficial de Red Hat (Apache httpd como proxy inverso, Gunicorn con 3 workers, MariaDB 10.5). Consume diariamente las cotizaciones oficiales de moneda extranjera desde la API del Banco Central de la República Argentina (BCRA), almacena el histórico y expone un simulador de tráfico 24x7 y métricas completas integradas con **IBM Instana**.

## Aplicaciones y Servicios en el repositorio

| Archivo / Servicio | Tipo | Descripción |
|---|---|---|
| [`app/app.py`](app/app.py) | Flask App | Aplicación web principal con Jinja2, manejo de fallas de BD e instrumentación Instana |
| [`app/wsgi.py`](app/wsgi.py) | WSGI Entrypoint | Punto de entrada WSGI para Gunicorn |
| [`app/gunicorn.conf.py`](app/gunicorn.conf.py) | Config | Configuración de Gunicorn (3 workers, socket UNIX, sin `--preload`) |
| [`services/daily_updater.py`](services/daily_updater.py) | Batch Job | Script que consume API BCRA y actualiza las cotizaciones en MariaDB |
| [`services/traffic_simulator.py`](services/traffic_simulator.py) | Daemon | Generador de tráfico sintético realista continuo (~10 req/min) |
| `cotizacion-gunicorn.service` | Systemd | Servicio de ejecución de Flask en background |
| `cotizacion-updater.timer` / `.service` | Systemd | Timer diario (18:00 hs) para sincronización con BCRA |
| `cotizacion-traffic.service` | Systemd | Servicio de simulación de tráfico permanente |

## Estructura del proyecto

```
cotizacion-moneda/
├── app/
│   ├── app.py                         # Flask core (rutas, endpoints, DB error handlers, instana)
│   ├── wsgi.py                        # Entrypoint WSGI
│   ├── gunicorn.conf.py               # Configuración Gunicorn
│   ├── cotizacion.conf                # VirtualHost Apache (ProxyPass a socket UNIX)
│   ├── instana-status.conf            # VirtualHost Apache mod_status para Instana
│   ├── templates/
│   │   ├── index.html                 # Vista principal (layout split de cotizaciones)
│   │   └── error_db.html              # Vista amigable cuando MariaDB no está disponible (HTTP 503)
│   └── static/css/styles.css          # Estilos CSS
├── db/
│   ├── 02_schema_and_seed.sql         # Schema SQL: tablas Moneda y Valor + 10 monedas iniciales
│   └── 04_fix_claves_iso.sql          # Migración de códigos ISO
├── services/
│   ├── daily_updater.py               # Actualizador de cotizaciones vía API BCRA
│   ├── traffic_simulator.py           # Simulador de tráfico sintético 24x7
│   ├── cotizacion-gunicorn.service    # Unit systemd para Gunicorn
│   ├── cotizacion-updater.service     # Unit systemd oneshot para daily_updater
│   ├── cotizacion-updater.timer       # Timer systemd diario (18:00 hs, Persistent=true)
│   └── cotizacion-traffic.service     # Unit systemd para el simulador de tráfico
├── scripts/
│   ├── 01_install_lamp.sh             # Instalación de LAMP oficial RHEL 9 + Python 3.11 + venv
│   ├── 03_deploy_app.sh               # Despliegue de app, Apache, SELinux y systemd drop-ins
│   ├── 05_setup_instana.sh            # Instalación de agente Instana y configuración de sensores
│   ├── 08_fix_mariadb_resilience.sh   # Hardening, tuning de memoria y reinicio resiliente de MariaDB
│   └── mariadb-resilience.conf        # Plantilla drop-in systemd para MariaDB
├── instana/
│   └── configuration.yaml             # Configuración del agente Instana (MariaDB, Apache, tags)
├── README.md                          # Guía de instalación y operación paso a paso
└── AGENT.md                           # Contexto para agentes de IA
```

## Cómo correr y desplegar

```bash
# 1. En servidor RHEL 9.6: Clonar y configurar stack LAMP
sudo bash scripts/01_install_lamp.sh

# 2. Desplegar aplicación y configurar servicios systemd
sudo bash scripts/03_deploy_app.sh

# 3. Configurar agente de observabilidad Instana
sudo bash scripts/05_setup_instana.sh

# 4. Aplicar tuning y resiliencia de MariaDB
sudo bash scripts/08_fix_mariadb_resilience.sh
```

### Gestión de servicios systemd

```bash
# Ver estado general
systemctl status cotizacion-gunicorn.service cotizacion-updater.timer cotizacion-traffic.service httpd mariadb

# Logs en tiempo real de la app
journalctl -u cotizacion-gunicorn.service -f

# Logs del simulador de tráfico
journalctl -u cotizacion-traffic.service -f
```

## Stack Técnico

| Componente | Versión | Uso |
|---|---|---|
| OS | RHEL 9.6 (Plow) | Sistema operativo empresarial |
| Python | 3.11 (`/opt/cotizacion/venv`) | Runtime de la aplicación y servicios |
| Flask | ≥ 3.0 | Framework web |
| Gunicorn | ≥ 21.0 | WSGI HTTP Server |
| Apache httpd | 2.4.x (Red Hat) | Reverse proxy (UNIX socket) y estáticos |
| MariaDB | 10.5.x | Base de datos relacional (InnoDB) |
| mysql-connector-python | ≥ 8.0 | Driver JDBC/Python de base de datos |
| instana | ≥ 2.5 | SDK de observabilidad y trazabilidad distribuida |
| requests | ≥ 2.31 | Cliente HTTP para consumo de API BCRA |

## Arquitectura de Monitoreo e Instana

- **Gunicorn sin `--preload`**: Crítico para que el SDK de Instana cree sus hilos de fondo dentro de cada worker individual tras el arranque (`instana.init()`).
- **Drop-ins con `INSTANA_IGNORE=true`**: Servicios del sistema RHEL (firewalld, tuned, fail2ban, rhsm) usan `/usr/bin/python3` (Python 3.9 del OS). Tienen configurado `INSTANA_IGNORE=true` para evitar warnings `python_sensor_not_installed`.
- **Manejo de resiliencia MariaDB**: `app.py` atrapa códigos de error de conexión (`errno 2002, 2003, 2006, 2013`) y retorna HTTP 503 controlado (`error_db.html`), permitiendo a Instana tipificar fallos de infraestructura sin marcar errores 500 no controlados.

## Base de Datos
- **Moneda** (`IDMoneda`, `Moneda`, `Clave`): 10 divisas principales (USD, EUR, BRL, GBP, JPY, CHF, CAD, SEK, AUD, ARS).
- **Valor** (`IDValor`, `IDMoneda`, `Fecha`, `Valor`): Histórico diario en pesos argentinos (ARS).

## Patrones de desarrollo
- Todo el código de producción corre bajo el usuario del sistema `cotizacion` y el entorno `/opt/cotizacion/venv`.
- El socket UNIX `/run/cotizacion/gunicorn.sock` es gestionado dinámicamente por systemd con `RuntimeDirectory=cotizacion`.
- El endpoint `/health` expone el estado de conectividad a la BD con detalles de diagnóstico.
