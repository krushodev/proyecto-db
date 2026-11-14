-- =============================================================================
-- PROYECTO DB - ETAPA 05: OPTIMIZACIÓN DE CONSULTAS A TRAVÉS DE ÍNDICES
-- Base: tienda_ropa (Intensa Jeans)
--
-- Experimento:
--   0. Tabla de pruebas VentaHistorica con 1.200.000 filas (sin índices: heap).
--   1. Escenario A: consulta por rango de fechas SIN índice.
--   2. Escenario B: índice AGRUPADO (CLUSTERED) sobre fecha_hora.
--   3. Escenario C: se borra el agrupado y se crea uno NO AGRUPADO de
--      cobertura (NONCLUSTERED ... INCLUDE).
--   4. Limpieza.
--
-- Cómo medir en SSMS:
--   * Activar "Incluir plan de ejecución real" (Ctrl+M) antes de cada escenario.
--   * Los tiempos y lecturas salen en la pestaña "Mensajes" (STATISTICS TIME/IO).
--   * Anotar: tiempo de CPU, tiempo transcurrido, lecturas lógicas y la
--     operación principal del plan (Table Scan / Clustered Index Seek / Index Seek).
-- =============================================================================

USE tienda_ropa;
GO

-- =============================================================================
-- PASO 0: TABLA DE PRUEBAS CON CARGA MASIVA
-- =============================================================================
-- VentaHistorica replica el encabezado de Venta (fecha, canal, cliente, método
-- de pago y total) para simular varios años de ventas. Es una tabla de pruebas:
-- no tiene clave primaria ni claves foráneas a propósito, para que arranque como
-- HEAP (sin índice agrupado) y la primera medición sea con Table Scan.

IF OBJECT_ID('dbo.VentaHistorica', 'U') IS NOT NULL
    DROP TABLE dbo.VentaHistorica;
GO

CREATE TABLE dbo.VentaHistorica (
    Id_VentaHistorica INT           NOT NULL,
    fecha_hora        DATETIME2(0)  NOT NULL,
    canal             VARCHAR(50)   NOT NULL,
    Id_Cliente        INT           NOT NULL,
    Id_metodo_pago    INT           NOT NULL,
    total             DECIMAL(10,2) NOT NULL
);
GO

-- Carga masiva: ROW_NUMBER() sobre el producto cartesiano de sys.objects
-- (159 objetos ^ 3 = ~4 millones de combinaciones; se toman 1.200.000).
--   * fecha_hora: una venta cada 3 minutos desde 2020-01-01 (~6,8 años).
--   * Id_Cliente (1..10) e Id_metodo_pago (1..8): rotan sobre los datos reales.
--   * canal: alterna 'Local' / 'Online'.
--   * total: entre 5.000 y 204.999 (pseudoaleatorio).
INSERT INTO dbo.VentaHistorica WITH (TABLOCK)
    (Id_VentaHistorica, fecha_hora, canal, Id_Cliente, Id_metodo_pago, total)
SELECT
    n,
    DATEADD(MINUTE, n * 3, CAST('2020-01-01T00:00:00' AS DATETIME2(0))),
    CASE WHEN n % 2 = 0 THEN 'Local' ELSE 'Online' END,
    1 + n % 10,
    1 + n % 8,
    CAST(5000 + ABS(CHECKSUM(NEWID())) % 200000 AS DECIMAL(10,2))
FROM (
    SELECT TOP (1200000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a
    CROSS JOIN sys.objects b
    CROSS JOIN sys.objects c
) AS numeros;
GO

-- Verificación de la carga
SELECT
    COUNT(*)        AS filas,
    MIN(fecha_hora) AS desde,
    MAX(fecha_hora) AS hasta
FROM dbo.VentaHistorica;
GO

-- Estado inicial: la tabla no tiene ningún índice (index_id 0 = HEAP)
SELECT i.index_id, i.name, i.type_desc
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.VentaHistorica');
GO

-- =============================================================================
-- CONSULTA DE PRUEBA (la misma en los tres escenarios)
-- =============================================================================
-- Necesidad de negocio: listar las ventas de enero de 2025 con su cliente y total
-- (por ejemplo, para un reporte mensual). Filtra por un rango de fechas SARGable.
--
--   SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
--   FROM dbo.VentaHistorica
--   WHERE fecha_hora >= '2025-01-01' AND fecha_hora < '2025-02-01';

-- Opcional, para medir siempre "en frío" (requiere permisos de sysadmin):
--   CHECKPOINT; DBCC DROPCLEANBUFFERS;
-- Las lecturas lógicas no dependen de la caché; los tiempos sí.

-- =============================================================================
-- ESCENARIO A: SIN ÍNDICE (HEAP)
-- =============================================================================
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
FROM dbo.VentaHistorica
WHERE fecha_hora >= '2025-01-01T00:00:00'
  AND fecha_hora <  '2025-02-01T00:00:00';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- Esperado: plan con Table Scan sobre toda la tabla (lee todas las páginas).

-- =============================================================================
-- ESCENARIO B: ÍNDICE AGRUPADO SOBRE LA FECHA
-- =============================================================================
-- El índice agrupado ordena físicamente la tabla por fecha_hora: las filas de
-- enero de 2025 quedan contiguas y el motor va directo a ellas.
CREATE CLUSTERED INDEX IX_VentaHistorica_fecha
    ON dbo.VentaHistorica (fecha_hora);
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
FROM dbo.VentaHistorica
WHERE fecha_hora >= '2025-01-01T00:00:00'
  AND fecha_hora <  '2025-02-01T00:00:00';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- Esperado: Clustered Index Seek, solo lee las páginas del rango.

-- =============================================================================
-- ESCENARIO C: ÍNDICE NO AGRUPADO DE COBERTURA (INCLUDE)
-- =============================================================================
-- Se borra el agrupado: la tabla vuelve a ser un heap.
DROP INDEX IX_VentaHistorica_fecha ON dbo.VentaHistorica;
GO

-- Índice no agrupado por fecha que además guarda en sus hojas las columnas que
-- pide la consulta. Así el motor resuelve todo desde el índice, sin ir a la
-- tabla (sin RID Lookup).
CREATE NONCLUSTERED INDEX IX_VentaHistorica_fecha_cobertura
    ON dbo.VentaHistorica (fecha_hora)
    INCLUDE (Id_VentaHistorica, Id_Cliente, total);
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
FROM dbo.VentaHistorica
WHERE fecha_hora >= '2025-01-01T00:00:00'
  AND fecha_hora <  '2025-02-01T00:00:00';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- Esperado: Index Seek (NonClustered) sobre IX_VentaHistorica_fecha_cobertura,
-- sin RID Lookup, con menos lecturas que el agrupado (las hojas son más chicas).

-- =============================================================================
-- COMPARACIÓN EXTRA: NO AGRUPADO SIN COBERTURA
-- =============================================================================
-- Muestra para qué sirve el INCLUDE: si el índice tiene solo la fecha, por cada
-- fila encontrada hay que ir a la tabla a buscar el resto (RID Lookup). Con
-- tantas filas, el optimizador suele preferir volver al Table Scan.
CREATE NONCLUSTERED INDEX IX_VentaHistorica_fecha_simple
    ON dbo.VentaHistorica (fecha_hora);
GO

SET STATISTICS TIME ON;
SET STATISTICS IO ON;

SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
FROM dbo.VentaHistorica WITH (INDEX (IX_VentaHistorica_fecha_simple))
WHERE fecha_hora >= '2025-01-01T00:00:00'
  AND fecha_hora <  '2025-02-01T00:00:00';

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
-- Se fuerza el índice con una sugerencia (hint) solo para ver el costo del
-- RID Lookup. Esperado: Index Seek + RID Lookup, con muchas más lecturas.

-- Índices presentes al final del experimento
SELECT i.name, i.type_desc
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.VentaHistorica');
GO

-- =============================================================================
-- APLICACIÓN AL MODELO REAL: ÍNDICE SOBRE Venta.fecha_hora
-- =============================================================================
-- En Venta el índice agrupado ya es la PK (Id_Venta, IDENTITY): conviene dejarlo
-- así porque es angosto, creciente (las ventas nuevas se agregan al final) y es
-- el que usan el JOIN con Detalle_Venta y las FK. Para las consultas por rango
-- de fechas (CU-02, reportes mensuales) se agrega un índice NO agrupado de
-- cobertura, igual al del escenario C. Id_Venta no hace falta en el INCLUDE:
-- todo índice no agrupado ya guarda la clave del índice agrupado.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Venta_fecha_hora' AND object_id = OBJECT_ID('dbo.Venta'))
    CREATE NONCLUSTERED INDEX IX_Venta_fecha_hora
        ON dbo.Venta (fecha_hora)
        INCLUDE (Id_Cliente, Id_metodo_pago, total);
GO

-- Con las 10 ventas de prueba el optimizador puede seguir eligiendo un scan
-- (la tabla entra en una sola página); el beneficio aparece con volumen, como
-- muestra el experimento con VentaHistorica.
SELECT i.name, i.type_desc, i.is_primary_key
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('dbo.Venta');
GO

-- =============================================================================
-- LIMPIEZA
-- =============================================================================
-- La tabla de pruebas no forma parte del modelo. Descomentar para eliminarla.
-- DROP TABLE dbo.VentaHistorica;
-- GO
