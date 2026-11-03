USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA IV - 2. REPORTE AGREGADO
-- Total de ventas por categoria de producto en un rango de fechas.
-- (El modelo no tiene entidad Vendedor, por eso se agrupa por categoria.)
--
-- Metricas por categoria:
--   cant_ventas      -> COUNT(DISTINCT Id_Venta): ventas donde aparece la categoria
--   cant_items       -> COUNT(*): renglones de detalle vendidos
--   unidades         -> SUM(cantidad)
--   total_vendido    -> SUM(subtotal): importe de los renglones (precio ya con
--                       liquidacion, antes del descuento por metodo de pago)
--   ticket_promedio  -> total_vendido / cant_ventas
-- =====================================================================

DECLARE @fecha_desde DATETIME2(0) = '2026-08-01';
DECLARE @fecha_hasta DATETIME2(0) = '2026-09-30';   -- inclusive (se compara < dia siguiente)

-- ---------------------------------------------------------------------
-- 2.a Reporte por categoria (incluye categorias sin ventas en el rango)
-- ---------------------------------------------------------------------
SELECT
    c.Id_Categoria,
    c.nombre                                   AS categoria,
    COUNT(DISTINCT dv.Id_Venta)                AS cant_ventas,
    COUNT(dv.nro_item)                         AS cant_items,
    COALESCE(SUM(dv.cantidad), 0)              AS unidades,
    COALESCE(SUM(dv.subtotal), 0)              AS total_vendido,
    COALESCE(SUM(dv.subtotal) / NULLIF(COUNT(DISTINCT dv.Id_Venta), 0), 0) AS ticket_promedio
FROM Categoria c
LEFT JOIN Producto p        ON p.Id_Categoria = c.Id_Categoria
-- El rango de fechas se aplica dentro del LEFT JOIN (renglones de ventas del rango),
-- asi las categorias sin ventas en el rango siguen apareciendo con valores en 0.
LEFT JOIN (
    SELECT d.Id_Producto, d.Id_Venta, d.nro_item, d.cantidad, d.subtotal
    FROM Detalle_Venta d
    JOIN Venta v ON v.Id_Venta = d.Id_Venta
    WHERE v.fecha_hora >= @fecha_desde
      AND v.fecha_hora <  DATEADD(DAY, 1, @fecha_hasta)
) dv                        ON dv.Id_Producto = p.Id_Producto
GROUP BY c.Id_Categoria, c.nombre
ORDER BY total_vendido DESC;
GO

-- ---------------------------------------------------------------------
-- 2.b Mismo reporte con fila de total general (ROLLUP) -- solo categorias con ventas
-- ---------------------------------------------------------------------
DECLARE @fecha_desde DATETIME2(0) = '2026-08-01';
DECLARE @fecha_hasta DATETIME2(0) = '2026-09-30';

SELECT
    CASE WHEN GROUPING(c.nombre) = 1 THEN 'TOTAL GENERAL' ELSE c.nombre END AS categoria,
    COUNT(DISTINCT v.Id_Venta) AS cant_ventas,
    SUM(dv.cantidad)           AS unidades,
    SUM(dv.subtotal)           AS total_vendido
FROM Venta v
JOIN Detalle_Venta dv ON dv.Id_Venta    = v.Id_Venta
JOIN Producto p       ON p.Id_Producto  = dv.Id_Producto
JOIN Categoria c      ON c.Id_Categoria = p.Id_Categoria
WHERE v.fecha_hora >= @fecha_desde
  AND v.fecha_hora <  DATEADD(DAY, 1, @fecha_hasta)
GROUP BY ROLLUP (c.nombre)
ORDER BY GROUPING(c.nombre), total_vendido DESC;
GO
