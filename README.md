# Cotización de Moneda — Guía de instalación y uso
## Sistema operativo: Red Hat Enterprise Linux 9.6 — Stack LAMP oficial Red Hat

---

## Arquitectura general

```
┌──────────────────────────────────────────────────────────────┐
│              VM RHEL 9.6 (LAMP oficial Red Hat)              │
│                                                              │
│  ┌────────────┐  Proxy    ┌───────────────────────────────┐  │
│  │  Apache    │──────────▶│  Gunicorn (3 workers)         │  │
│  │  httpd :80 │  UNIX     │  /run/cotizacion/gunicorn.sock│  │
│  └─────┬──────┘  socket   └──────────────┬────────────────┘  │
│        │ /static                          │  Flask + instana  │
│        ▼                                  ▼                   │
│  /opt/cotizacion/          ┌─────────────────────────────┐   │
│  app/static/               │  MariaDB 10.5               │   │
│                            │  cotizacion_moneda          │   │
│  ┌───────────────────┐     │  ├── Moneda (10 monedas)    │   │
│  │  systemd Timer    │     │  └── Valor (histórico)      │   │
│  │  18:00 hs diario  │     └─────────────────────────────┘   │
│  │  daily_updater.py │──── HTTPS ──▶ API BCRA               │
│  └───────────────────┘                                        │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Instana Agent ←→ ingress-orange-saas.instana.io:443   │  │
│  │  Host · MariaDB · Apache · PHP · Python (3 workers)    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## Instalación completa desde cero — 3 comandos

```bash
# 1. Clonar el repositorio
git clone https://github.com/RubenDillon/Cotiza.git
cd Cotiza/cotizacion-moneda

# 2. Instalar stack LAMP + Python 3.11 + venv con todas las dependencias
sudo bash scripts/01_install_lamp.sh

# 3. Desplegar la aplicación + servicios systemd + Instana drops-ins + simulador de tráfico
sudo bash scripts/03_deploy_app.sh

# 4. Instalar y configurar el agente Instana (opcional)
sudo bash scripts/05_setup_instana.sh
```

---

## Requisitos previos

| Requisito                | Detalle                                                      |
|--------------------------|--------------------------------------------------------------|
| RHEL 9.6 instalado       | Suscripción RHSM activa                                      |
| Acceso a internet        | Para API BCRA, repos Red Hat e instalador Instana            |
| Usuario root / sudo      | Para instalación de paquetes y servicios                     |
| Repos habilitados        | `rhel-9-for-x86_64-baseos-rpms` + `appstream-rpms`          |
| **Sin EPEL ni CentOS**   | Solo paquetes oficiales Red Hat                              |

---

## Qué hace cada script

### `01_install_lamp.sh` — Stack LAMP + Python 3.11

1. Verifica suscripción RHSM
2. Habilita repos oficiales Red Hat
3. Instala Apache httpd + habilita firewall
4. Instala MariaDB 10.5 + securiza la instalación
5. Instala PHP 8.2 (módulo AppStream)
6. Instala **`python3.11`** (no `python3` — en RHEL 9 apunta a 3.9)
7. Crea usuario `cotizacion` + venv `/opt/cotizacion/venv` con:
   - `flask`, `mysql-connector-python`, `requests`, `gunicorn`, **`instana`**

> **Nota crítica:** El sensor Python de Instana requiere Python 3.10+. En RHEL 9,
> `python3` apunta a Python 3.9 (sistema base). Por eso se usa `python3.11`
> explícitamente para el venv.

### `03_deploy_app.sh` — Despliegue completo

1. Crea usuario `cotizacion` (si no existe)
2. Crea estructura de directorios
3. Copia archivos de la aplicación
4. Verifica/completa dependencias Python (incluye `instana`)
5. Configura permisos y SELinux
6. Configura Apache: VirtualHost proxy reverso + `mod_status` para Instana
7. Crea **drop-ins systemd** con `INSTANA_IGNORE=true` para los servicios del
   sistema RHEL que usan `/usr/bin/python3` (firewalld, tuned, tuned-ppd,
   fail2ban, rhsm) — evita errores `python_sensor_not_installed` en Instana
8. Instala y habilita:
   - `cotizacion-gunicorn.service` — servidor Flask (3 workers)
   - `cotizacion-updater.timer` — actualización BCRA a las 18:00 hs
   - `cotizacion-traffic.service` — simulador de tráfico 24x7 (~10 req/min)
9. Carga schema SQL + ejecuta primera actualización desde la API BCRA

### `05_setup_instana.sh` — Agente Instana

1. Instala el agente Instana si no está presente (one-liner oficial IBM)
2. Aplica `instana/configuration.yaml` (plugins MariaDB + Apache + host tags)
3. Verifica SDK `instana` en el venv
4. Verifica/crea drop-ins `INSTANA_IGNORE` para servicios del sistema
5. Reinicia todos los servicios
6. Verifica el estado final

---

## Estructura del proyecto

```
cotizacion-moneda/
├── scripts/
│   ├── 01_install_lamp.sh       ← LAMP + Python 3.11 + venv con instana
│   ├── 03_deploy_app.sh         ← App + Apache + systemd + drop-ins Instana
│   └── 05_setup_instana.sh      ← Agente Instana + configuration.yaml
├── db/
│   ├── 02_schema_and_seed.sql   ← Schema + 10 monedas + 10 días de valores
│   └── 04_fix_claves_iso.sql    ← Migración (referencia histórica)
├── app/
│   ├── app.py                   ← Flask app (manejo de errores BD + import instana)
│   ├── wsgi.py                  ← Punto de entrada WSGI
│   ├── gunicorn.conf.py         ← Config Gunicorn (sin --preload)
│   ├── cotizacion.conf          ← VirtualHost Apache proxy reverso
│   ├── templates/
│   │   ├── index.html           ← Template Jinja2 (layout 2 paneles)
│   │   └── error_db.html        ← Página de error amigable (MariaDB no disponible)
│   └── static/css/styles.css   ← Estilos (paleta azul BCRA)
├── services/
│   ├── daily_updater.py             ← Actualiza cotizaciones desde API BCRA
│   ├── traffic_simulator.py         ← Simulador de tráfico (~10 req/min, 24x7)
│   ├── cotizacion-gunicorn.service  ← Gunicorn (HOME=/tmp, 3 workers, sin --preload)
│   ├── cotizacion-updater.service   ← oneshot: ejecuta daily_updater.py
│   ├── cotizacion-updater.timer     ← Timer: 18:00 hs, Persistent=true
│   └── cotizacion-traffic.service   ← Simulador de tráfico como daemon systemd
└── instana/
    └── configuration.yaml       ← Plugin MariaDB + Apache status_url + tags
```

---

## Arquitectura del servidor web

```
Browser → Apache :80 → (UNIX socket) → Gunicorn (3 workers) → Flask
                   └──→ /static → archivos estáticos directos
```

- **Apache** actúa como proxy reverso via `mod_proxy` (incluido en RHEL 9)
- **Gunicorn** corre **sin `--preload`** — cada worker importa `instana`
  independientemente al arrancar, garantizando que el background thread del
  SDK se inicializa correctamente y puede anunciarse al agente Instana
- El socket UNIX `/run/cotizacion/gunicorn.sock` es creado por systemd
  (`RuntimeDirectory=cotizacion`)

---

## Base de datos

### Tabla `Moneda`

| Campo    | Tipo         | Descripción                                |
|----------|--------------|--------------------------------------------|
| IDMoneda | INT AI PK    | Identificador autonumérico                 |
| Moneda   | VARCHAR(100) | Nombre descriptivo de la moneda            |
| Clave    | VARCHAR(50)  | Código ISO 4217 para la API BCRA (único)   |

### Tabla `Valor`

| Campo    | Tipo          | Descripción                               |
|----------|---------------|-------------------------------------------|
| IDValor  | INT AI PK     | Identificador autonumérico                |
| IDMoneda | INT FK        | Referencia a `Moneda.IDMoneda`            |
| Fecha    | DATE          | Fecha de la cotización (UNIQUE+IDMoneda)  |
| Valor    | DECIMAL(15,4) | Cotización en pesos argentinos (ARS)      |

### Monedas precargadas

| # | Moneda                                 | ISO   |
|---|----------------------------------------|-------|
| 1 | Dólar de los Estados Unidos de América | USD   |
| 2 | Peso Argentino (referencia BCRA)       | ARS   |
| 3 | Real Brasileño de Brasil               | BRL   |
| 4 | Euro (Zona Euro)                       | EUR   |
| 5 | Libra Esterlina (Reino Unido)          | GBP   |
| 6 | Yen Japonés (Japón)                    | JPY   |
| 7 | Franco Suizo (Suiza)                   | CHF   |
| 8 | Dólar Canadiense (Canadá)              | CAD   |
| 9 | Corona Sueca (Suecia)                  | SEK   |
|10 | Dólar Australiano (Australia)          | AUD   |

---

## API BCRA

```
GET https://api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones/{ISO}
    ?fechadesde=YYYY-MM-DD&fechahasta=YYYY-MM-DD
```

Campo utilizado de la respuesta: `tipoCotizacion` (ARS por unidad de moneda).

---

## Servicio de actualización automática

El timer systemd dispara `daily_updater.py` **todos los días a las 18:00 hs**.

```bash
systemctl status cotizacion-updater.timer       # estado del timer
systemctl list-timers cotizacion-updater.timer  # próxima ejecución
systemctl start cotizacion-updater.service      # ejecutar manualmente
journalctl -u cotizacion-updater.service -f     # logs en tiempo real
```

Si la VM estaba apagada a las 18:00, el timer ejecuta en el próximo arranque
(`Persistent=true`).

---

## Simulador de tráfico

`cotizacion-traffic.service` corre **las 24 horas** generando tráfico realista
contra la aplicación. Simula usuarios que navegan la lista de monedas y
consultan cotizaciones históricas.

### Comportamiento de cada sesión simulada

```
GET /            ← usuario abre la app
[pausa 2-8s]     ← "lee" la lista de monedas
GET /moneda/3    ← elige una moneda aleatoria (ej: BRL)
[pausa 2-8s]     ← "lee" las cotizaciones
GET /moneda/1    ← cambia a otra moneda (ej: USD)
[pausa 2-8s]
...
```

### Parámetros de carga

| Parámetro | Valor |
|---|---|
| Rate objetivo | ~10 requests/minuto |
| Monedas por sesión | 1–4 (40 % visita 1, 35 % visita 2, 15 % visita 3, 10 % visita 4) |
| Pausa entre páginas | 2–8 segundos (simula lectura humana) |
| User-Agents | 6 variados (Chrome, Safari, Firefox, iOS, Android) |
| Log | `/var/log/cotizacion/traffic_simulator.log` |
| Reinicio automático | `Restart=always`, backoff 10 s |
| Instana | `INSTANA_IGNORE=true` — excluido del sensor Python (es carga sintética) |

### Comandos de gestión

```bash
systemctl status cotizacion-traffic.service          # estado del simulador
journalctl -u cotizacion-traffic.service -f          # logs en tiempo real (recomendado)
tail -f /var/log/cotizacion/traffic_simulator.log    # log de sesiones en archivo
systemctl stop cotizacion-traffic.service            # detener temporalmente
systemctl start cotizacion-traffic.service           # reiniciar
```

### Seguimiento en tiempo real

El comando más útil para ver qué está haciendo el simulador en este momento:

```bash
journalctl -u cotizacion-traffic.service -f
```

Ejemplo de salida:

```
Sep 07 18:42:01 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:01 [INFO] Sesión 0047 | GET / → 200 (0.03s) [Mozilla/5.0 (Windows NT 10.0...]
Sep 07 18:42:04 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:04 [INFO] Sesión 0047 | GET /moneda/3 → 200 (0.07s)
Sep 07 18:42:09 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:09 [INFO] Sesión 0047 | GET /moneda/8 → 200 (0.06s)
Sep 07 18:42:14 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:14 [INFO] Sesión 0047 completada — 147 req totales — rate 9.8 req/min — próxima en 5.3s
Sep 07 18:42:19 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:19 [INFO] Sesión 0048 | GET / → 200 (0.03s) [Mozilla/5.0 (iPhone; CPU iPhone...]
Sep 07 18:42:24 itzvsi0-vmn4bn1k cotizacion-traffic[18955]: 2026-09-07 18:42:24 [INFO] Sesión 0048 | GET /moneda/1 → 200 (0.06s)
```

Cada línea muestra:
- **Número de sesión** — sesión correlativa desde que arrancó el servicio
- **Endpoint visitado** — `GET /` (lista) o `GET /moneda/<id>` (detalle)
- **Código HTTP** — `200` normal, `503` si MariaDB no está disponible
- **Tiempo de respuesta** — en segundos; valores normales: `0.03s` para `/`, `0.06s` para `/moneda/<id>`
- **User-Agent parcial** — el navegador simulado en esa sesión
- **Resumen de sesión** — requests totales acumulados, rate actual (req/min) y pausa hasta la próxima sesión

### Detectar problemas con el simulador

Si MariaDB se cae, el simulador lo refleja inmediatamente:

```bash
# Ver solo los errores del simulador
journalctl -u cotizacion-traffic.service -f | grep -v "200"

# Contar errores en los últimos 10 minutos
journalctl -u cotizacion-traffic.service --since "10 minutes ago" | grep -c "→ [^2]"
```

---

## Manejo de errores — Base de datos no disponible

### Contexto

Durante la operación normal, si MariaDB se cae o se reinicia, Flask intentaba
conectar a `localhost:3306`, recibía `ECONNREFUSED` en ~1 ms y lanzaba una
excepción no manejada que resultaba en un **HTTP 500 genérico**. En Instana
esto aparecía como una falla de la aplicación, sin indicar que la causa real
era la base de datos.

### Solución implementada

`app.py` ahora intercepta los errores de conexión de MariaDB
(`errno 2002, 2003, 2006, 2013`) y los convierte en respuestas **HTTP 503**
controladas, mostrando la página `error_db.html`.

```
MariaDB caído
     ↓
Flask recibe DBError (errno 2003 — Can't connect to localhost:3306)
     ↓
_db_unavailable(e) == True
     ↓
abort(503) → @app.errorhandler(503) → render_template("error_db.html")
     ↓
HTTP 503 con página amigable al usuario
```

### Página de error (`error_db.html`)

Cuando MariaDB no está disponible el usuario ve una página con:
- Explicación clara de qué ocurrió
- Indicación de que el servicio se restaurará automáticamente
- Botón **"Reintentar"** para recargar cuando MariaDB vuelva

### Diferencia en Instana antes y después

| Situación | Antes | Después |
|---|---|---|
| MariaDB caído | HTTP **500** — falla de app | HTTP **503** — servicio no disponible |
| Duración de la traza | ~1 ms (excepción inmediata) | ~1 ms (misma velocidad de fallo) |
| Mensaje en Instana | Error genérico sin contexto | 503 — indica claramente que es BD |
| `/health` endpoint | `{"status":"error","db":"disconnected"}` | Igual + campo `"detail"` con el error exacto |

### Códigos de error de MariaDB manejados

| errno | Descripción |
|---|---|
| `2002` | Can't connect to local server through socket |
| `2003` | Can't connect to MySQL server on 'host:port' |
| `2006` | MySQL server has gone away |
| `2013` | Lost connection to MySQL server during query |

---

## Observabilidad — Instana

### Sensores activos confirmados

| Sensor               | Componente                    |
|----------------------|-------------------------------|
| `sensor-host`        | Servidor RHEL 9.6             |
| `sensor-httpd`       | Apache httpd                  |
| `sensor-mariadb`     | MariaDB 10.5                  |
| `sensor-php-fpm`     | PHP-FPM                       |
| `sensor-python`      | Gunicorn workers (Python 3.11)|
| `sensor-python-trace`| Trazas distribuidas Flask     |
| `sensor-process`     | Procesos del sistema          |

### Por qué `INSTANA_IGNORE=true` en servicios del sistema

RHEL 9 usa `/usr/bin/python3` (Python 3.9) en varios servicios del sistema
(firewalld, tuned, tuned-ppd, fail2ban, rhsm). El agente Instana intenta
instrumentar todos los procesos Python que encuentra. Sin el SDK instalado
en esos procesos → error `python_sensor_not_installed`.

Solución: drop-in systemd con `Environment="INSTANA_IGNORE=true"` en cada
uno de esos servicios. El agente respeta esta variable y los excluye.

### Por qué Gunicorn corre sin `--preload`

Con `--preload`, el SDK de Instana se inicializa en el proceso master antes
del `fork()`. Los background threads del SDK **no sobreviven `fork()`** en
Python → los 3 workers quedan sin poder anunciarse al agente → error
`python_sensor_not_installed` para cada worker.

Sin `--preload`, cada worker importa `instana` de forma independiente al
arrancar → el SDK se inicializa correctamente en cada worker → los 3 aparecen
como **Python apps instrumentadas** en la UI de Instana.

---

## Comandos útiles de operación

```bash
# Estado de todos los servicios
systemctl status cotizacion-gunicorn.service cotizacion-updater.timer \
                 cotizacion-traffic.service httpd mariadb

# Reiniciar la aplicación
systemctl restart cotizacion-gunicorn.service

# Logs en tiempo real
tail -f /var/log/cotizacion/gunicorn_error.log
tail -f /var/log/cotizacion/updater.log
tail -f /var/log/httpd/cotizacion_error.log

# Consultar cotizaciones en la BD
mariadb -u app_cotizacion -p'AppCotiz#2025!' cotizacion_moneda \
  -e "SELECT m.Moneda, v.Fecha, v.Valor FROM Valor v
      JOIN Moneda m USING(IDMoneda)
      ORDER BY v.Fecha DESC LIMIT 20;"

# Verificar Instana — sensores activos
grep "Activated" /opt/instana/agent/data/log/agent.log | tail -20

# Verificar Instana — sin errores python_sensor
grep "python_sensor" /opt/instana/agent/data/log/agent.log | tail -5
```
