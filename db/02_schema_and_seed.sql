-- =============================================================================
-- Script: 02_schema_and_seed.sql
-- Descripción: Creación del schema, tablas e inserción de datos iniciales
--              para la aplicación Cotización de Moneda
-- Base de datos: MariaDB 10.5 (RHEL 9.6 AppStream oficial)
-- Ejecutar con: mariadb -u root -p < 02_schema_and_seed.sql
-- =============================================================================

-- Crear y usar la base de datos
CREATE DATABASE IF NOT EXISTS cotizacion_moneda
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE cotizacion_moneda;

-- Crear usuario de aplicación (separado de root)
CREATE USER IF NOT EXISTS 'app_cotizacion'@'localhost'
    IDENTIFIED BY 'AppCotiz#2025!';

GRANT SELECT, INSERT, UPDATE, DELETE ON cotizacion_moneda.*
    TO 'app_cotizacion'@'localhost';

FLUSH PRIVILEGES;

-- =============================================================================
-- TABLA: Moneda
-- =============================================================================
CREATE TABLE IF NOT EXISTS Moneda (
    IDMoneda  INT           NOT NULL AUTO_INCREMENT,
    Moneda    VARCHAR(100)  NOT NULL COMMENT 'Descripción/nombre de la moneda',
    Clave     VARCHAR(50)   NOT NULL UNIQUE COMMENT 'Código variable BCRA para la API (ej: "dolar")',
    PRIMARY KEY (IDMoneda)
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Catálogo de monedas consultables a la API del BCRA';

-- =============================================================================
-- TABLA: Valor
-- =============================================================================
CREATE TABLE IF NOT EXISTS Valor (
    IDValor   INT           NOT NULL AUTO_INCREMENT,
    IDMoneda  INT           NOT NULL,
    Fecha     DATE          NOT NULL COMMENT 'Fecha de la consulta al BCRA',
    Valor     DECIMAL(15,4) NOT NULL COMMENT 'Cotización de la moneda en el día',
    PRIMARY KEY (IDValor),
    UNIQUE KEY uq_moneda_fecha (IDMoneda, Fecha),
    CONSTRAINT fk_valor_moneda
        FOREIGN KEY (IDMoneda)
        REFERENCES Moneda (IDMoneda)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci
  COMMENT='Histórico de cotizaciones por moneda y fecha';

-- Índice adicional para acelerar búsquedas por fecha descendente
CREATE INDEX idx_valor_fecha ON Valor (Fecha DESC);

-- =============================================================================
-- DATOS INICIALES: Tabla Moneda
-- Variables BCRA obtenidas de la API pública del BCRA:
--   https://api.bcra.gob.ar/estadisticas/v3.0/monetarias
-- El campo "Clave" corresponde al idVariable de la API BCRA v3
-- =============================================================================
INSERT INTO Moneda (IDMoneda, Moneda, Clave) VALUES
-- Orden: 1 - Dólar de los Estados Unidos de América
(1,  'Dólar de los Estados Unidos de América',  '1'),
-- Orden: 2 - Peso Argentino (tipo de cambio de referencia BNA comprador)
(2,  'Peso Argentino (referencia BNA)',          '315'),
-- Orden: 3 - Real Brasileño de Brasil
(3,  'Real Brasileño de Brasil',                 '39'),
-- Orden: 4 - Euro (Zona Euro)
(4,  'Euro (Zona Euro)',                         '32'),
-- Orden: 5 - Libra Esterlina (Reino Unido)
(5,  'Libra Esterlina (Reino Unido)',             '33'),
-- Orden: 6 - Yen Japonés (Japón)
(6,  'Yen Japonés (Japón)',                       '34'),
-- Orden: 7 - Franco Suizo (Suiza)
(7,  'Franco Suizo (Suiza)',                      '35'),
-- Orden: 8 - Dólar Canadiense (Canadá)
(8,  'Dólar Canadiense (Canadá)',                 '40'),
-- Orden: 9 - Corona Sueca (Suecia)
(9,  'Corona Sueca (Suecia)',                     '36'),
-- Orden: 10 - Dólar Australiano (Australia)
(10, 'Dólar Australiano (Australia)',             '41');

-- =============================================================================
-- DATOS INICIALES: Tabla Valor (últimos 10 días hábiles por moneda)
-- Nota: Los valores que siguen son de ejemplo/referencia histórica aproximada.
--       El servicio automático daily_updater.py reemplazará/completará estos
--       registros con datos reales desde la API del BCRA en su primera ejecución.
-- =============================================================================
INSERT INTO Valor (IDMoneda, Fecha, Valor) VALUES
-- Dólar USA (IDMoneda=1)
(1, CURDATE() - INTERVAL 9 DAY, 1165.00),
(1, CURDATE() - INTERVAL 8 DAY, 1167.50),
(1, CURDATE() - INTERVAL 7 DAY, 1170.00),
(1, CURDATE() - INTERVAL 6 DAY, 1172.25),
(1, CURDATE() - INTERVAL 5 DAY, 1175.00),
(1, CURDATE() - INTERVAL 4 DAY, 1173.75),
(1, CURDATE() - INTERVAL 3 DAY, 1176.50),
(1, CURDATE() - INTERVAL 2 DAY, 1178.00),
(1, CURDATE() - INTERVAL 1 DAY, 1180.00),
(1, CURDATE(),                   1182.50),
-- Peso Argentino (IDMoneda=2) — referencia cruzada
(2, CURDATE() - INTERVAL 9 DAY,  1.0000),
(2, CURDATE() - INTERVAL 8 DAY,  1.0000),
(2, CURDATE() - INTERVAL 7 DAY,  1.0000),
(2, CURDATE() - INTERVAL 6 DAY,  1.0000),
(2, CURDATE() - INTERVAL 5 DAY,  1.0000),
(2, CURDATE() - INTERVAL 4 DAY,  1.0000),
(2, CURDATE() - INTERVAL 3 DAY,  1.0000),
(2, CURDATE() - INTERVAL 2 DAY,  1.0000),
(2, CURDATE() - INTERVAL 1 DAY,  1.0000),
(2, CURDATE(),                    1.0000),
-- Real Brasileño (IDMoneda=3)
(3, CURDATE() - INTERVAL 9 DAY,  210.00),
(3, CURDATE() - INTERVAL 8 DAY,  211.50),
(3, CURDATE() - INTERVAL 7 DAY,  212.00),
(3, CURDATE() - INTERVAL 6 DAY,  213.25),
(3, CURDATE() - INTERVAL 5 DAY,  214.00),
(3, CURDATE() - INTERVAL 4 DAY,  213.75),
(3, CURDATE() - INTERVAL 3 DAY,  215.00),
(3, CURDATE() - INTERVAL 2 DAY,  216.50),
(3, CURDATE() - INTERVAL 1 DAY,  217.00),
(3, CURDATE(),                    218.00),
-- Euro (IDMoneda=4)
(4, CURDATE() - INTERVAL 9 DAY,  1290.00),
(4, CURDATE() - INTERVAL 8 DAY,  1292.50),
(4, CURDATE() - INTERVAL 7 DAY,  1295.00),
(4, CURDATE() - INTERVAL 6 DAY,  1297.00),
(4, CURDATE() - INTERVAL 5 DAY,  1300.00),
(4, CURDATE() - INTERVAL 4 DAY,  1298.50),
(4, CURDATE() - INTERVAL 3 DAY,  1302.00),
(4, CURDATE() - INTERVAL 2 DAY,  1305.00),
(4, CURDATE() - INTERVAL 1 DAY,  1307.50),
(4, CURDATE(),                    1310.00),
-- Libra Esterlina (IDMoneda=5)
(5, CURDATE() - INTERVAL 9 DAY,  1500.00),
(5, CURDATE() - INTERVAL 8 DAY,  1503.50),
(5, CURDATE() - INTERVAL 7 DAY,  1506.00),
(5, CURDATE() - INTERVAL 6 DAY,  1508.00),
(5, CURDATE() - INTERVAL 5 DAY,  1510.00),
(5, CURDATE() - INTERVAL 4 DAY,  1509.00),
(5, CURDATE() - INTERVAL 3 DAY,  1512.00),
(5, CURDATE() - INTERVAL 2 DAY,  1515.50),
(5, CURDATE() - INTERVAL 1 DAY,  1518.00),
(5, CURDATE(),                    1520.00),
-- Yen Japonés (IDMoneda=6)
(6, CURDATE() - INTERVAL 9 DAY,    7.80),
(6, CURDATE() - INTERVAL 8 DAY,    7.82),
(6, CURDATE() - INTERVAL 7 DAY,    7.85),
(6, CURDATE() - INTERVAL 6 DAY,    7.83),
(6, CURDATE() - INTERVAL 5 DAY,    7.86),
(6, CURDATE() - INTERVAL 4 DAY,    7.87),
(6, CURDATE() - INTERVAL 3 DAY,    7.89),
(6, CURDATE() - INTERVAL 2 DAY,    7.88),
(6, CURDATE() - INTERVAL 1 DAY,    7.90),
(6, CURDATE(),                      7.92),
-- Franco Suizo (IDMoneda=7)
(7, CURDATE() - INTERVAL 9 DAY,  1320.00),
(7, CURDATE() - INTERVAL 8 DAY,  1322.50),
(7, CURDATE() - INTERVAL 7 DAY,  1325.00),
(7, CURDATE() - INTERVAL 6 DAY,  1327.00),
(7, CURDATE() - INTERVAL 5 DAY,  1330.00),
(7, CURDATE() - INTERVAL 4 DAY,  1328.00),
(7, CURDATE() - INTERVAL 3 DAY,  1332.00),
(7, CURDATE() - INTERVAL 2 DAY,  1335.00),
(7, CURDATE() - INTERVAL 1 DAY,  1337.50),
(7, CURDATE(),                    1340.00),
-- Dólar Canadiense (IDMoneda=8)
(8, CURDATE() - INTERVAL 9 DAY,   855.00),
(8, CURDATE() - INTERVAL 8 DAY,   857.50),
(8, CURDATE() - INTERVAL 7 DAY,   860.00),
(8, CURDATE() - INTERVAL 6 DAY,   858.00),
(8, CURDATE() - INTERVAL 5 DAY,   862.00),
(8, CURDATE() - INTERVAL 4 DAY,   861.00),
(8, CURDATE() - INTERVAL 3 DAY,   863.50),
(8, CURDATE() - INTERVAL 2 DAY,   865.00),
(8, CURDATE() - INTERVAL 1 DAY,   867.00),
(8, CURDATE(),                     869.00),
-- Corona Sueca (IDMoneda=9)
(9, CURDATE() - INTERVAL 9 DAY,   108.00),
(9, CURDATE() - INTERVAL 8 DAY,   108.50),
(9, CURDATE() - INTERVAL 7 DAY,   109.00),
(9, CURDATE() - INTERVAL 6 DAY,   108.75),
(9, CURDATE() - INTERVAL 5 DAY,   109.25),
(9, CURDATE() - INTERVAL 4 DAY,   109.50),
(9, CURDATE() - INTERVAL 3 DAY,   110.00),
(9, CURDATE() - INTERVAL 2 DAY,   109.75),
(9, CURDATE() - INTERVAL 1 DAY,   110.25),
(9, CURDATE(),                     110.50),
-- Dólar Australiano (IDMoneda=10)
(10, CURDATE() - INTERVAL 9 DAY,  745.00),
(10, CURDATE() - INTERVAL 8 DAY,  747.00),
(10, CURDATE() - INTERVAL 7 DAY,  749.50),
(10, CURDATE() - INTERVAL 6 DAY,  748.00),
(10, CURDATE() - INTERVAL 5 DAY,  751.00),
(10, CURDATE() - INTERVAL 4 DAY,  750.00),
(10, CURDATE() - INTERVAL 3 DAY,  752.50),
(10, CURDATE() - INTERVAL 2 DAY,  754.00),
(10, CURDATE() - INTERVAL 1 DAY,  756.00),
(10, CURDATE(),                    758.00);

-- Verificación
SELECT 'Monedas cargadas:' AS Info, COUNT(*) AS Total FROM Moneda;
SELECT 'Valores cargados:' AS Info, COUNT(*) AS Total FROM Valor;
