# Cotización de Moneda — Guía de instalación y uso
## Sistema operativo: Red Hat Enterprise Linux 9.6 (RHEL) — Stack LAMP oficial

---

## Arquitectura general

```
┌─────────────────────────────────────────────────────────────┐
│              VM RHEL 9.6 (LAMP oficial Red Hat)             │
│                                                             │
│  ┌────────────┐  Proxy    ┌──────────────────────────────┐  │
│  │  Apache    │──────────▶│  Gunicorn (3 workers)        │  │
│  │  httpd     │  UNIX     │  /run/cotizacion/gunicorn.sock│  │
│  │  :80       │  socket   │                              │  │
│  └─────┬──────┘           └──────────────┬───────────────┘  │
│        │ /static directo                  │  Flask app.py    │
│        │                                  │  mysql-connector │
│  ┌─────▼──────────────┐                   ▼                 │
│  │  /opt/cotizacion/  │      ┌────────────────────────┐    │
│  │  app/static/       │      │  MariaDB 10.5           │    │
│  └────────────────────┘      │  cotizacion_moneda      │    │
│                               │  ├── Moneda (catálogo) │    │
│  ┌──────────────────────┐     │  └── Valor (histórico) │    │
│  │  systemd Timer       │     └────────────────────────┘    │
│  │  18:00 hs diario     │                                   │
│  │  daily_updater.py    │──── requests (HTTPS) ────────▶   │
│  └──────────────────────┘     API BCRA (externa)            │
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

## Instalación en una VM limpia — 2 comandos

```bash
sudo bash scripts/01_install_lamp.sh
sudo bash scripts/03_deploy_app.sh
```

---

## Paso a paso de instalación

### 1 — Instalar stack LAMP

```bash
sudo bash scripts/01_install_lamp.sh
```

Instala y habilita:
- **Apache httpd** (canal AppStream oficial)
- **MariaDB 10.5** (paquete directo AppStream — sin módulo DNF, eso era RHEL 8)
- **PHP 8.2** (módulo `php:8.2` del AppStream oficial)
- **Python 3.11** (AppStream oficial)
- **Gunicorn** instalado en entorno virtual `/opt/cotizacion/venv`

### 2 — Desplegar la aplicación

```bash
sudo bash scripts/03_deploy_app.sh
```

Este script realiza 9 pasos:
1. Crea el usuario de sistema `cotizacion` (sin login)
2. Crea la estructura de directorios en `/opt/cotizacion/`
3. Copia todos los archivos de la aplicación
4. Instala dependencias Python (Flask, Gunicorn, mysql-connector, requests)
5. Configura permisos correctos (directorios `755`, archivos `644`)
6. Configura SELinux (contextos y booleanos para Apache proxy)
7. Instala el VirtualHost de Apache como **proxy reverso a Gunicorn**
8. Instala y habilita los servicios systemd (Gunicorn + timer BCRA)
9. Carga el schema SQL y datos iniciales en MariaDB

---

## Estructura del proyecto

```
cotizacion-moneda/
├── scripts/
│   ├── 01_install_lamp.sh              ← Instalación LAMP (RHEL 9.6 oficial)
│   └── 03_deploy_app.sh                ← Despliegue completo (9 pasos)
├── db/
│   ├── 02_schema_and_seed.sql          ← Schema + 10 monedas + 10 días de valores
│   └── 04_fix_claves_iso.sql           ← Migración de claves numéricas a ISO 4217
├── app/
│   ├── app.py                          ← Aplicación Flask (frontend)
│   ├── wsgi.py                         ← Punto de entrada WSGI (reserva/referencia)
│   ├── cotizacion.conf                 ← VirtualHost Apache (proxy reverso)
│   ├── templates/
│   │   └── index.html                  ← Template Jinja2 (layout 2 paneles)
│   └── static/css/
│       └── styles.css                  ← Estilos (paleta BCRA azul)
└── services/
    ├── daily_updater.py                ← Script Python: consulta BCRA y guarda valores
    ├── cotizacion-gunicorn.service     ← Servicio systemd Gunicorn (siempre corriendo)
    ├── cotizacion-updater.service      ← Unidad systemd oneshot (actualiza cotizaciones)
    └── cotizacion-updater.timer        ← Timer systemd (18:00 hs diario)
```

---

## Arquitectura de servidores

La aplicación **no usa mod_wsgi**. El stack de producción es:

```
Browser → Apache :80 → (UNIX socket) → Gunicorn → Flask
                  └──→ /static → archivos directos
```

- **Apache** actúa como proxy reverso usando `mod_proxy` (incluido en RHEL 9)
- **Gunicorn** corre como servicio systemd con 3 workers, socket UNIX en
  `/run/cotizacion/gunicorn.sock`
- El socket UNIX es creado automáticamente por systemd (`RuntimeDirectory=cotizacion`)
- No se usa el puerto 8000 ni ningún puerto adicional

---

## Base de datos

### Tabla `Moneda`

| Campo    | Tipo         | Descripción                                      |
|----------|--------------|--------------------------------------------------|
| IDMoneda | INT AI PK    | Identificador autonumérico                       |
| Moneda   | VARCHAR(100) | Nombre descriptivo de la moneda                  |
| Clave    | VARCHAR(50)  | Código ISO 4217 para la API BCRA (único)         |

### Tabla `Valor`

| Campo    | Tipo          | Descripción                                     |
|----------|---------------|-------------------------------------------------|
| IDValor  | INT AI PK     | Identificador autonumérico                      |
| IDMoneda | INT FK        | Referencia a `Moneda.IDMoneda`                  |
| Fecha    | DATE          | Fecha de la cotización (UNIQUE con IDMoneda)    |
| Valor    | DECIMAL(15,4) | Cotización en pesos argentinos (ARS)            |

### Monedas precargadas

| # | Moneda                                    | Clave ISO |
|---|-------------------------------------------|-----------|
| 1 | Dólar de los Estados Unidos de América    | USD       |
| 2 | Peso Argentino (referencia BCRA)          | ARS       |
| 3 | Real Brasileño de Brasil                  | BRL       |
| 4 | Euro (Zona Euro)                          | EUR       |
| 5 | Libra Esterlina (Reino Unido)             | GBP       |
| 6 | Yen Japonés (Japón)                       | JPY       |
| 7 | Franco Suizo (Suiza)                      | CHF       |
| 8 | Dólar Canadiense (Canadá)                 | CAD       |
| 9 | Corona Sueca (Suecia)                     | SEK       |
|10 | Dólar Australiano (Australia)             | AUD       |

---

## API BCRA

Endpoint utilizado:
```
GET https://api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones/{codigo_iso}
    ?fechadesde=YYYY-MM-DD&fechahasta=YYYY-MM-DD
```

Respuesta:
```json
{
  "status": 200,
  "results": [
    {
      "fecha": "2026-09-04",
      "detalle": [
        { "codigoMoneda": "USD", "tipoCotizacion": 1508.0 }
      ]
    }
  ]
}
```

El campo utilizado es `tipoCotizacion` (pesos argentinos por unidad de moneda).

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
próximo arranque (`Persistent=true`).

---

## Comandos útiles de operación

```bash
# Estado de la aplicación web (Gunicorn)
systemctl status cotizacion-gunicorn.service

# Reiniciar la aplicación
systemctl restart cotizacion-gunicorn.service

# Ver logs de la app en tiempo real
tail -f /var/log/cotizacion/gunicorn_error.log

# Recargar Apache
systemctl reload httpd

# Verificar MariaDB
systemctl status mariadb

# Consultar cotizaciones en la BD
mariadb -u app_cotizacion -p cotizacion_moneda \
  -e "SELECT m.Moneda, v.Fecha, v.Valor FROM Valor v
      JOIN Moneda m USING(IDMoneda)
      ORDER BY v.Fecha DESC LIMIT 20;"

# Ver todos los logs
tail -f /var/log/httpd/cotizacion_error.log
tail -f /var/log/cotizacion/gunicorn_error.log
tail -f /var/log/cotizacion/updater.log
```

---

## Notas de seguridad

- El usuario `cotizacion` no tiene shell interactiva ni directorio home de login.
- SELinux está activo en modo **enforcing** (por defecto en RHEL 9).
- Las credenciales de la BD pueden externalizarse en un archivo `EnvironmentFile`
  de systemd para entornos de producción.
- Se recomienda habilitar TLS en el VirtualHost de Apache con un certificado
  emitido por la CA interna de la organización.
