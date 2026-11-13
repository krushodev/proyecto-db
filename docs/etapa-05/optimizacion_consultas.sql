-- =============================================================================
-- PROYECTO DB - ETAPA 05: OPTIMIZACIÓN DE CONSULTAS A NIVEL DE CÓDIGO
-- Descripción: Refactorización de consultas aplicando buenas prácticas de sintaxis,
-- tablas temporales y agregación condicional.
-- Tablas: Venta, Detalle_Venta, Cliente, Metodo_pago (base tienda_ropa)
-- =============================================================================

USE tienda_ropa;
GO

-- =============================================================================
-- CASO 1: FILTRADO POR RANGOS DE FECHA Y DÍAS HÁBILES (SARGability)
-- =============================================================================
-- Problema: aplicar funciones sobre columnas en el WHERE obliga a SQL Server a
-- evaluar la función fila por fila en toda la tabla.

-- INEFICIENTE:
/*
SELECT v.Id_Venta, v.fecha_hora, v.total
FROM Venta v
WHERE MONTH(v.fecha_hora) IN (8, 9)
  AND DATENAME(weekday, v.fecha_hora) NOT IN ('Saturday', 'Sunday')
  AND v.total > 50000;
*/

-- OPTIMIZADO:
-- Rango explícito de fechas y día de la semana evaluado con DATEPART numérico.
SET DATEFIRST 7;  -- 1 = domingo ... 7 = sábado (independiente del idioma del servidor)

SELECT
    v.Id_Venta,
    v.fecha_hora,
    v.total
FROM Venta v
WHERE v.fecha_hora >= '2026-08-01T00:00:00'
  AND v.fecha_hora <  '2026-10-01T00:00:00'
  AND DATEPART(dw, v.fecha_hora) BETWEEN 2 AND 6   -- lunes a viernes
  AND v.total > 50000.00;
GO
-- Resultado esperado con los datos de prueba: ventas 1, 4, 6, 8 y 9
-- (la venta 5 se excluye porque cae un sábado).

-- =============================================================================
-- CASO 2: BÚSQUEDA EFICIENTE DE TEXTO (PATRONES EN APELLIDOS)
-- =============================================================================
-- Problema: usar funciones de cadena (LEFT, SUBSTRING) en el WHERE impide
-- aprovechar un índice sobre la columna.

-- INEFICIENTE:
/*
SELECT Id_Cliente, nombre, apellido
FROM Cliente
WHERE LEFT(apellido, 1) = 'G';
*/

-- OPTIMIZADO:
-- Patrón LIKE con prefijo fijo: el motor puede buscar por rango en un índice.
SELECT
    Id_Cliente,
    nombre,
    apellido
FROM Cliente
WHERE apellido LIKE 'G%';
GO
-- Resultado esperado: Martín Gómez (Id_Cliente 2).

-- =============================================================================
-- CASO 3: TABLAS TEMPORALES (#) PARA PROCESAMIENTO INTERMEDIO
-- =============================================================================
-- Problema: repetir subconsultas correlacionadas obliga a recalcular lo mismo
-- por cada fila de la tabla principal.

-- INEFICIENTE:
/*
SELECT
    v.Id_Venta,
    v.total,
    (SELECT SUM(d.subtotal) FROM Detalle_Venta d WHERE d.Id_Venta = v.Id_Venta) AS total_detalle,
    (SELECT COUNT(*)        FROM Detalle_Venta d WHERE d.Id_Venta = v.Id_Venta) AS cant_items
FROM Venta v
WHERE (SELECT SUM(d.subtotal) FROM Detalle_Venta d WHERE d.Id_Venta = v.Id_Venta) > 50000;
*/

-- OPTIMIZADO:
-- 1. Se calculan los totales del detalle una sola vez en una tabla temporal.
SELECT
    Id_Venta,
    SUM(subtotal) AS total_detalle,
    COUNT(*)      AS cant_items
INTO #ResumenDetalle
FROM Detalle_Venta
GROUP BY Id_Venta;

-- 2. La consulta final une la tabla principal con la temporal.
SELECT
    v.Id_Venta,
    v.total,
    r.total_detalle,
    r.cant_items
FROM Venta v
INNER JOIN #ResumenDetalle r ON r.Id_Venta = v.Id_Venta
WHERE r.total_detalle > 50000;

-- 3. Limpieza de la tabla temporal.
DROP TABLE #ResumenDetalle;
GO
-- Resultado esperado: ventas 1, 4, 5, 6, 8 y 9.

-- =============================================================================
-- CASO 4: CTE PARA AGREGAR EL DETALLE ANTES DE UNIR (CABECERA-DETALLE)
-- =============================================================================
-- Problema: unir la cabecera con el detalle y agrupar después multiplica las
-- filas de la cabecera (una por renglón) antes de aplicar SUM/COUNT.

-- OPTIMIZADO:
-- La CTE resume el detalle a una fila por venta y recién entonces se hace el JOIN.
WITH DetalleAgrupado AS (
    SELECT
        Id_Venta,
        SUM(subtotal) AS total_calculado,
        SUM(cantidad) AS total_prendas
    FROM Detalle_Venta
    GROUP BY Id_Venta
)
SELECT
    v.Id_Venta,
    v.fecha_hora,
    mp.nombre AS metodo_pago,
    d.total_calculado,
    d.total_prendas
FROM Venta v
INNER JOIN DetalleAgrupado d ON d.Id_Venta = v.Id_Venta
INNER JOIN Metodo_pago mp    ON mp.Id_metodo_pago = v.Id_metodo_pago
WHERE v.fecha_hora >= '2026-01-01T00:00:00';
GO
-- Resultado esperado: 10 filas, una por venta.

-- =============================================================================
-- CASO 5: AGREGACIÓN CONDICIONAL EN UNA SOLA PASADA (SUM + CASE)
-- =============================================================================
-- Problema: hacer una consulta por cada medio de pago recorre la tabla varias veces.

-- OPTIMIZADO:
-- Una sola consulta clasifica los montos por medio de pago con CASE.
-- Ids de Metodo_pago: 1 Efectivo, 2 Transferencia, 3/4/5/7 Tarjetas,
-- 6 Mercado Pago, 8 Gift card.
SELECT
    YEAR(fecha_hora)  AS anio,
    MONTH(fecha_hora) AS mes,
    COUNT(*)          AS total_ventas,
    SUM(CASE WHEN Id_metodo_pago = 1                THEN total ELSE 0 END) AS total_efectivo,
    SUM(CASE WHEN Id_metodo_pago = 2                THEN total ELSE 0 END) AS total_transferencia,
    SUM(CASE WHEN Id_metodo_pago IN (3, 4, 5, 7)    THEN total ELSE 0 END) AS total_tarjeta,
    SUM(CASE WHEN Id_metodo_pago IN (6, 8)          THEN total ELSE 0 END) AS total_otros
FROM Venta
GROUP BY YEAR(fecha_hora), MONTH(fecha_hora)
ORDER BY anio DESC, mes ASC;
GO
-- Resultado esperado:
--   2026 / 8 : 7 ventas | efectivo 102000 | transferencia 42390 | tarjeta 175220 | otros 64600
--   2026 / 9 : 3 ventas | efectivo 0      | transferencia 81000 | tarjeta 82200  | otros 40850

-- =============================================================================
-- CASO 6: CONTROL PRECISO DE LÍMITES Y EMPATES (TOP WITH TIES)
-- =============================================================================
-- Problema: TOP simple puede omitir filas relevantes si hay empates en el límite.

-- OPTIMIZADO:
-- Devuelve las 5 ventas de mayor valor, incluyendo a todas las que empaten en el 5.º puesto.
SELECT TOP 5 WITH TIES
    Id_Venta,
    fecha_hora,
    total
FROM Venta
ORDER BY total DESC;
GO
-- Resultado esperado con los datos de prueba: 5 filas (ventas 8, 9, 4, 5 y 1);
-- no hay empate en el límite.
