-- =============================================================================
-- Script: 04_fix_claves_iso.sql
-- Descripción: Actualiza el campo Clave de la tabla Moneda de IDs numéricos
--              (API BCRA v3 deprecada) a códigos ISO 4217 (API cambiaria v1.0)
-- Ejecutar con: mariadb -u root -p cotizacion_moneda < 04_fix_claves_iso.sql
-- =============================================================================

USE cotizacion_moneda;

UPDATE Moneda SET Clave = 'USD' WHERE IDMoneda = 1;
UPDATE Moneda SET Clave = 'ARS' WHERE IDMoneda = 2;
UPDATE Moneda SET Clave = 'BRL' WHERE IDMoneda = 3;
UPDATE Moneda SET Clave = 'EUR' WHERE IDMoneda = 4;
UPDATE Moneda SET Clave = 'GBP' WHERE IDMoneda = 5;
UPDATE Moneda SET Clave = 'JPY' WHERE IDMoneda = 6;
UPDATE Moneda SET Clave = 'CHF' WHERE IDMoneda = 7;
UPDATE Moneda SET Clave = 'CAD' WHERE IDMoneda = 8;
UPDATE Moneda SET Clave = 'SEK' WHERE IDMoneda = 9;
UPDATE Moneda SET Clave = 'AUD' WHERE IDMoneda = 10;

-- Verificación
SELECT IDMoneda, Moneda, Clave FROM Moneda ORDER BY IDMoneda;
