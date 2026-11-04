-- ============================================================================
-- PROYECTO DB: INTENSA JEANS (E-COMMERCE / TIENDA DE ROPA)
-- ETAPA 04: CONSULTA DE NEGOCIO AVANZADA 
-- ARCHIVO: consulta_avanzada.sql
-- TABLAS UTILIZADAS: Cliente, Venta, Detalle_Venta, Metodo_pago, Producto
-- ============================================================================

USE IntensaJeansDB;
GO

-- ----------------------------------------------------------------------------
-- CASO DE USO 03 (CU-03): Identificación y Análisis de Clientes VIP
-- 
-- OBJETIVO DE NEGOCIO:
-- Generar un reporte consolidado de los clientes de mayor valor (VIP) que hayan
-- realizado al menos 2 ventas en el período evaluado y cuyo gasto acumulado
-- supere el promedio global de facturación por cliente.
-- Además, se desglosa la preferencia en el método de pago utilizado.
-- ----------------------------------------------------------------------------

WITH ResumenCliente AS (
    -- 1. CTE: Agregación de métricas de ventas y unidades por cliente
    SELECT 
        v.id_cliente,
        COUNT(DISTINCT v.id_venta) AS cantidad_ventas,
        SUM(dv.cantidad) AS total_prendas,
        SUM(v.monto_total) AS gasto_total,
        AVG(v.monto_total) AS ticket_promedio
    FROM Venta v
    INNER JOIN Detalle_Venta dv ON v.id_venta = dv.id_venta
    WHERE v.fecha_venta >= '2026-01-01T00:00:00' 
      AND v.fecha_venta <  '2027-01-01T00:00:00' -- Filtro de fecha SARGable
    GROUP BY v.id_cliente
    HAVING COUNT(DISTINCT v.id_venta) >= 2
),
PromedioGlobal AS (
    -- 2. CTE: Cálculo del gasto promedio por cliente en el sistema
    SELECT AVG(gasto_total) AS promedio_gasto
    FROM ResumenCliente
)
-- 3. Consulta final: Proyección de clientes VIP y distribución de medios de pago
SELECT 
    c.id_cliente,
    c.nombre,
    c.apellido,
    c.email,
    rc.cantidad_ventas,
    rc.total_prendas,
    rc.gasto_total,
    ROUND(rc.ticket_promedio, 2) AS ticket_promedio,
    -- Agregación condicional para identificar métodos de pago utilizados
    SUM(CASE WHEN mp.tipo_pago LIKE '%Efectivo%' THEN 1 ELSE 0 END) AS uso_efectivo,
    SUM(CASE WHEN mp.tipo_pago LIKE '%Tarjeta%' THEN 1 ELSE 0 END) AS uso_tarjeta,
    SUM(CASE WHEN mp.tipo_pago LIKE '%Transferencia%' THEN 1 ELSE 0 END) AS uso_transferencia
FROM Cliente c
INNER JOIN ResumenCliente rc ON c.id_cliente = rc.id_cliente
CROSS JOIN PromedioGlobal pg
INNER JOIN Venta v ON c.id_cliente = v.id_cliente
INNER JOIN Metodo_pago mp ON v.id_metodo_pago = mp.id_metodo_pago
WHERE rc.gasto_total >= pg.promedio_gasto
GROUP BY 
    c.id_cliente,
    c.nombre,
    c.apellido,
    c.email,
    rc.cantidad_ventas,
    rc.total_prendas,
    rc.gasto_total,
    rc.ticket_promedio
ORDER BY rc.gasto_total DESC;
GO