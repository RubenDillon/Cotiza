# Cotización de Moneda — Guía de instalación y uso
## Sistema operativo: Red Hat Enterprise Linux 9.6 (RHEL) — Stack LAMP oficial

---

## Arquitectura general

```
┌─────────────────────────────────────────────────────────────┐
│              VM RHEL 9.6 (LAMP oficial Red Hat)             │
│                                                             │
│  ┌────────────┐  WSGI   ┌──────────────────────────────┐  │
│  │  Apache    │────────▶│  Python 3.11 / Flask          │  │
│  │  httpd     │         │  app/app.py  (frontend web)   │  │
│  └────────────┘         └──────────────┬───────────────┘  │
│                                         │  mysql-connector  │
│  ┌──────────────────────┐               ▼                  │
│  │  systemd Timer       │    ┌─────────────────────────┐  │
│  │  18:00 hs diario     │───▶│  MariaDB 10.5           │  │
│  │  daily_updater.py    │    │  cotizacion_moneda       │  │
│  └──────────────────────┘    │  ├── Moneda (catálogo)   │  │
│           │                  │  └── Valor  (histórico)  │  │
│           │ requests (HTTPS) └─────────────────────────┘  │
│           ▼                                                 │
│    API BCRA v3 (externa)                                    │
│    api.bcra.gob.ar                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Requisitos previos

| Requisito                  | Detalle                                                  |
|----------------------------|----------------------------------------------------------|
| RHEL 9.6 instalado         | Suscripción RHSM activa                                  |
| Acceso a internet          | Para API BCRA y repos Red Hat                            |
| Usuario root / sudo        | Para instalación de paquetes y servicios                 |
| Repositorios habilitados   | `rhel-9-for-x86_64-baseos-rpms` + `appstream-rpms`      |
| **Sin EPEL ni CentOS**     | Sólo paquetes oficiales Red Hat                          |

---

## Paso a paso de instalación

### 1 — Instalar stack LAMP

```bash
sudo bash scripts/01_install_lamp.sh
```

Instala y habilita:
- **Apache httpd** (canal AppStream oficial)
- **MariaDB 10.5** (módulo `mariadb:10.5` del AppStream oficial)
- **PHP 8.2** (módulo `php:8.2` del AppStream oficial)
- **Python 3.11** (AppStream oficial)
- Entorno virtual Python en `/opt/cotizacion/venv`

### 2 — Desplegar la aplicación

```bash
sudo bash scripts/03_deploy_app.sh
```

Este script:
1. Crea el usuario de sistema `cotizacion` (sin login)
2. Copia los archivos a `/opt/cotizacion/`
3. Crea e instala el virtualenv con Flask, mysql-connector, requests
4. Configura SELinux y permisos
5. Instala el VirtualHost de Apache (`mod_wsgi`)
6. Instala y habilita el **timer systemd** `cotizacion-updater.timer`
7. Carga el schema SQL y datos iniciales en MariaDB

---

## Estructura del proyecto

```
cotizacion-moneda/
├── scripts/
│   ├── 01_install_lamp.sh          ← Instalación LAMP (RHEL 9.6 oficial)
│   └── 03_deploy_app.sh            ← Despliegue completo
├── db/
│   └── 02_schema_and_seed.sql      ← Schema + 10 monedas + 10 días de valores
├── app/
│   ├── app.py                      ← Aplicación Flask (frontend)
│   ├── wsgi.py                     ← Punto de entrada para Apache/mod_wsgi
│   ├── cotizacion.conf             ← VirtualHost Apache
│   ├── templates/
│   │   └── index.html              ← Template Jinja2 (layout 2 paneles)
│   └── static/css/
│       └── styles.css              ← Estilos (paleta BCRA azul)
└── services/
    ├── daily_updater.py            ← Script Python: consulta BCRA y guarda valores
    ├── cotizacion-updater.service  ← Unidad systemd (oneshot)
    └── cotizacion-updater.timer    ← Timer systemd (18:00 hs diario)
```

---

## Base de datos

### Tabla `Moneda`

| Campo    | Tipo         | Descripción                                      |
|----------|--------------|--------------------------------------------------|
| IDMoneda | INT AI PK    | Identificador autonumérico                       |
| Moneda   | VARCHAR(100) | Nombre descriptivo de la moneda                  |
| Clave    | VARCHAR(50)  | `idVariable` para la API BCRA v3 (único)         |

### Tabla `Valor`

| Campo    | Tipo          | Descripción                                     |
|----------|---------------|-------------------------------------------------|
| IDValor  | INT AI PK     | Identificador autonumérico                      |
| IDMoneda | INT FK        | Referencia a `Moneda.IDMoneda`                  |
| Fecha    | DATE          | Fecha de la cotización (UNIQUE con IDMoneda)    |
| Valor    | DECIMAL(15,4) | Cotización en pesos argentinos (ARS)            |

### Monedas precargadas

| # | Moneda                                    | Clave BCRA |
|---|-------------------------------------------|------------|
| 1 | Dólar de los Estados Unidos de América    | 1          |
| 2 | Peso Argentino (referencia BNA)           | 315        |
| 3 | Real Brasileño de Brasil                  | 39         |
| 4 | Euro (Zona Euro)                          | 32         |
| 5 | Libra Esterlina (Reino Unido)             | 33         |
| 6 | Yen Japonés (Japón)                       | 34         |
| 7 | Franco Suizo (Suiza)                      | 35         |
| 8 | Dólar Canadiense (Canadá)                 | 40         |
| 9 | Corona Sueca (Suecia)                     | 36         |
|10 | Dólar Australiano (Australia)             | 41         |

---

## API BCRA v3

Endpoint utilizado:
```
GET https://api.bcra.gob.ar/estadisticas/v3.0/monetarias/{idVariable}?desde=YYYY-MM-DD&hasta=YYYY-MM-DD
```

Respuesta:
```json
{
  "results": [
    { "fecha": "2025-07-10", "valor": 1182.50 },
    { "fecha": "2025-07-09", "valor": 1180.00 }
  ]
}
```

---

## Servicio de actualización automática

El timer systemd dispara `daily_updater.py` **todos los días a las 18:00 hs** (hora local de la VM).

```bash
# Ver estado del timer
systemctl status cotizacion-updater.timer

# Ver próximas ejecuciones
systemctl list-timers cotizacion-updater.timer

# Ejecutar manualmente
systemctl start cotizacion-updater.service

# Ver logs en tiempo real
journalctl -u cotizacion-updater.service -f

# Ver log de archivo
tail -f /var/log/cotizacion/updater.log
```

Si la VM estaba apagada a las 18:00, el timer ejecutará el servicio en el
próximo arranque (opción `Persistent=true`).

---

## Comandos útiles de operación

```bash
# Reiniciar la aplicación web
sudo systemctl reload httpd

# Verificar MariaDB
sudo systemctl status mariadb

# Consultar cotizaciones en la BD
mariadb -u app_cotizacion -p cotizacion_moneda \
  -e "SELECT m.Moneda, v.Fecha, v.Valor FROM Valor v JOIN Moneda m USING(IDMoneda) ORDER BY v.Fecha DESC LIMIT 20;"

# Verificar logs de Apache
sudo tail -f /var/log/httpd/cotizacion_error.log
```

---

## Notas de seguridad

- El usuario `cotizacion` no tiene shell interactiva ni directorio home de login.
- SELinux está activo en modo **enforcing** (por defecto en RHEL 9).
- Las credenciales de la BD pueden externalizarse en un archivo `.env` o en
  **systemd EnvironmentFile** para producción.
- Se recomienda habilitar TLS en el VirtualHost de Apache con un certificado
  emitido por la CA interna de la organización.
