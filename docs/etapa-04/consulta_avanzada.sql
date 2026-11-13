-- ============================================================================
-- PROYECTO DB: INTENSA JEANS (E-COMMERCE / TIENDA DE ROPA)
-- ETAPA 04: CONSULTA DE NEGOCIO AVANZADA
-- ARCHIVO: consulta_avanzada.sql
-- TABLAS UTILIZADAS: Cliente, Venta, Detalle_Venta, Metodo_pago
-- ============================================================================

USE tienda_ropa;
GO

-- ----------------------------------------------------------------------------
-- CASO DE USO 03 (CU-03): Identificación y análisis de clientes VIP
--
-- OBJETIVO DE NEGOCIO:
-- Listar los clientes que hicieron al menos 2 ventas en el período analizado
-- y cuyo gasto acumulado es igual o superior al promedio de gasto por cliente
-- (calculado sobre TODOS los clientes que compraron en ese período).
-- Además, se desglosa el medio de pago utilizado en cada compra.
--
-- NOTA SOBRE EL DISEÑO:
-- Venta y Detalle_Venta son una relación cabecera-detalle (1:N). Si se unen
-- directamente y luego se suma Venta.total, cada venta se suma una vez por
-- renglón y el gasto queda inflado. Por eso el detalle se resume primero a
-- una fila por venta (CTE PrendasPorVenta) y recién después se une.
-- ----------------------------------------------------------------------------

WITH PrendasPorVenta AS (
    -- 1. Una fila por venta con la cantidad de prendas del detalle
    SELECT
        Id_Venta,
        SUM(cantidad) AS prendas
    FROM Detalle_Venta
    GROUP BY Id_Venta
),
GastoPorCliente AS (
    -- 2. Una fila por cliente: métricas y medio de pago (sin filtrar aún)
    SELECT
        v.Id_Cliente,
        COUNT(*)           AS cantidad_ventas,
        SUM(p.prendas)     AS total_prendas,
        SUM(v.total)       AS gasto_total,
        AVG(v.total)       AS ticket_promedio,
        SUM(CASE WHEN mp.nombre = 'Efectivo'               THEN 1 ELSE 0 END) AS uso_efectivo,
        SUM(CASE WHEN mp.nombre LIKE 'Tarjeta%'            THEN 1 ELSE 0 END) AS uso_tarjeta,
        SUM(CASE WHEN mp.nombre = 'Transferencia bancaria' THEN 1 ELSE 0 END) AS uso_transferencia,
        SUM(CASE WHEN mp.nombre IN ('Efectivo', 'Transferencia bancaria')
                   OR mp.nombre LIKE 'Tarjeta%'            THEN 0 ELSE 1 END) AS uso_otros
    FROM Venta v
    INNER JOIN PrendasPorVenta p ON p.Id_Venta = v.Id_Venta
    INNER JOIN Metodo_pago mp    ON mp.Id_metodo_pago = v.Id_metodo_pago
    WHERE v.fecha_hora >= '2026-01-01T00:00:00'
      AND v.fecha_hora <  '2027-01-01T00:00:00'   -- rango SARGable
    GROUP BY v.Id_Cliente
),
PromedioGlobal AS (
    -- 3. Promedio de gasto entre todos los clientes que compraron
    SELECT AVG(gasto_total) AS promedio_gasto
    FROM GastoPorCliente
)
-- 4. Resultado: clientes recurrentes con gasto igual o superior al promedio
SELECT
    c.Id_Cliente,
    c.nombre,
    c.apellido,
    c.email,
    g.cantidad_ventas,
    g.total_prendas,
    g.gasto_total,
    ROUND(g.ticket_promedio, 2) AS ticket_promedio,
    g.uso_efectivo,
    g.uso_tarjeta,
    g.uso_transferencia,
    g.uso_otros
FROM GastoPorCliente g
INNER JOIN Cliente c ON c.Id_Cliente = g.Id_Cliente
CROSS JOIN PromedioGlobal pg
WHERE g.cantidad_ventas >= 2
  AND g.gasto_total >= pg.promedio_gasto
ORDER BY g.gasto_total DESC;
GO
