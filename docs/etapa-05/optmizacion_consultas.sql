-- =============================================================================
-- PROYECTO DB - ETAPA 05: OPTIMIZACIÓN DE CONSULTAS A NIVEL DE CÓDIGO
-- Descripción: Refactorización de consultas aplicando buenas prácticas de sintaxis,
-- tablas temporales y agregación condicional.
-- =============================================================================

USE tienda_ropa;
GO

-- =============================================================================
-- CASO 1: FILTRADO POR RANGOS DE FECHA Y DÍAS HÁBILES (SARGability)
-- =============================================================================
-- Problema: Aplicar funciones sobre columnas en el WHERE obliga a SQL Server a
-- evaluar la función fila por fila en toda la tabla.

--INEFICIENTE:
/_
SELECT c.id_compra, c.fecha_y_hora, c.costo
FROM COMPRA c
WHERE MONTH(c.fecha_y_hora) IN (1, 2, 3)
AND DATENAME(weekday, c.fecha_y_hora) NOT IN ('Saturday', 'Sunday')
AND c.costo > 20000;
_/

--OPTIMIZADO:
-- Filtro con rango explícito de fechas y evaluación numérica con DATEPART.
SET DATEFIRST 7; -- 1 = Domingo, 7 = Sábado

SELECT
c.id_compra,
c.fecha_y_hora,
c.costo
FROM COMPRA c
WHERE c.fecha_y_hora >= '2026-01-01T00:00:00'
AND c.fecha_y_hora < '2026-04-01T00:00:00'
AND DATEPART(dw, c.fecha_y_hora) BETWEEN 2 AND 6
AND c.costo > 20000.00;
GO

-- =============================================================================
-- CASO 2: BÚSQUEDA EFICIENTE DE TEXTO (PATRONES EN APELLIDOS/NOMBRES)
-- =============================================================================
-- Problema: Usar funciones de cadena (como LEFT o SUBSTRING) en la cláusula WHERE
-- genera carga innecesaria en el procesador.

--INEFICIENTE:
/_
SELECT id_cliente, nombre_completo
FROM CLIENTE
WHERE LEFT(nombre_completo, 1) = 'M';
_/

--OPTIMIZADO:
-- Patrón LIKE directo desde el inicio del campo.
SELECT
id_cliente,
nombre_completo
FROM CLIENTE
WHERE nombre_completo LIKE 'M%';
GO

-- =============================================================================
-- CASO 3: USO DE TABLAS TEMPORALES (#) PARA PROCESAMIENTO INTERMEDIO
-- =============================================================================
-- Problema: Repetir subconsultas complejas o calcular varias veces lo mismo en
-- una consulta grande sobrecarga el servidor.

--INEFICIENTE:
/_
SELECT
c.id_compra,
c.costo,
(SELECT SUM(d.sub_total) FROM DETALLEDECOMPRA d WHERE d.id_compra = c.id_compra) AS total_detalle,
(SELECT COUNT(_) FROM DETALLEDECOMPRA d WHERE d.id_compra = c.id_compra) AS cant_items
FROM COMPRA c
WHERE (SELECT SUM(d.sub_total) FROM DETALLEDECOMPRA d WHERE d.id_compra = c.id_compra) > 50000;
\*/

--OPTIMIZADO:
-- 1. Se crea una tabla auxiliar/temporal (#) con los totales procesados previamente.
SELECT
id_compra,
SUM(sub_total) AS total_detalle,
COUNT(\*) AS cant_items
INTO #ResumenDetalle
FROM DETALLEDECOMPRA
GROUP BY id_compra;

-- 2. Se realiza la consulta final uniendo la tabla principal con la auxiliar.
SELECT
c.id_compra,
c.costo,
r.total_detalle,
r.cant_items
FROM COMPRA c
INNER JOIN #ResumenDetalle r ON c.id_compra = r.id_compra
WHERE r.total_detalle > 50000;

-- 3. Limpieza de la tabla temporal al finalizar
DROP TABLE #ResumenDetalle;
GO

-- =============================================================================
-- CASO 4: USO DE CTE (WITH) PARA AGREGACIONES EN MODELO CABECERA-DETALLE
-- =============================================================================
-- Problema: Agrupar la cabecera y el detalle en una sola consulta con múltiples
-- JOINs puede duplicar filas en memoria antes de aplicar el SUM/COUNT.

--OPTIMIZADO:
-- La CTE pre-calcula los totales del detalle y luego se hace el JOIN simple.
WITH DetalleAgrupado AS (
SELECT
id_compra,
SUM(sub_total) AS total_calculado,
SUM(cantidad) AS total_prendas
FROM DETALLEDECOMPRA
GROUP BY id_compra
)
SELECT
c.id_compra,
c.fecha_y_hora,
mp.tipo_de_pago,
d.total_calculado,
d.total_prendas
FROM COMPRA c
INNER JOIN DetalleAgrupado d ON c.id_compra = d.id_compra
INNER JOIN METODO_DE_PAGO mp ON c.id_metodo = mp.id_metodo
WHERE c.fecha_y_hora >= '2026-01-01';
GO

-- =============================================================================
-- CASO 5: AGREGACIÓN CONDICIONAL EN UNA SOLA PASADA (SUM + CASE)
-- =============================================================================
-- Problema: Hacer múltiples consultas para contar o sumar por categorías.

--OPTIMIZADO:
-- Utilizar una sola consulta y clasificar las columnas usando CASE.
SELECT
YEAR(fecha_y_hora) AS anio,
MONTH(fecha_y_hora) AS mes,
COUNT(\*) AS total_compras,
SUM(CASE WHEN id_metodo = 1 THEN costo ELSE 0 END) AS total_efectivo,
SUM(CASE WHEN id_metodo = 2 THEN costo ELSE 0 END) AS total_tarjeta,
SUM(CASE WHEN id_metodo = 3 THEN costo ELSE 0 END) AS total_transferencia
FROM COMPRA
GROUP BY YEAR(fecha_y_hora), MONTH(fecha_y_hora)
ORDER BY anio DESC, mes ASC;
GO

-- =============================================================================
-- CASO 6: CONTROL PRECISO DE LÍMITES Y EMPATES (TOP WITH TIES)
-- =============================================================================
-- Problema: Usar TOP simple puede omitir datos relevantes si hay empates en el límite.

--OPTIMIZADO:
-- Devuelve las 5 compras de mayor valor, incluyendo a todos los que empaten en el puesto 5.
SELECT TOP 5 WITH TIES
id_compra,
fecha_y_hora,
costo
FROM COMPRA
ORDER BY costo DESC;
GO
