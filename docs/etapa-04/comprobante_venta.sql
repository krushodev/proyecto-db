USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA IV - 1. FACTURA / COMPROBANTE DE VENTA  (CU-01, incluye CU-04)
-- Consolida el encabezado y el detalle de una venta, calculando el
-- subtotal de cada renglon y el total acumulado.
--
-- Los importes se calculan con precio_unitario del DETALLE (precio
-- historico, RN.08), nunca con Producto.precio_lista.
--
-- Parametro: @id_venta (numero de venta a emitir)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.a Comprobante renglon por renglon
--     Cada fila trae el encabezado (repetido) + un renglon del detalle.
--     subtotal_renglon  = cantidad * precio_unitario
--     total_acumulado   = suma corrida de los subtotales hasta ese renglon
-- ---------------------------------------------------------------------
DECLARE @id_venta INT = 1;

SELECT
    v.Id_Venta                                             AS nro_comprobante,
    v.fecha_hora,
    v.canal,
    c.apellido + ', ' + c.nombre                           AS cliente,
    c.dni,
    mp.nombre                                              AS metodo_pago,
    dv.nro_item,
    p.nombre                                               AS producto,
    t.descripcion                                          AS talle,
    dv.cantidad,
    dv.precio_unitario,
    dv.cantidad * dv.precio_unitario                       AS subtotal_renglon,
    SUM(dv.cantidad * dv.precio_unitario)
        OVER (PARTITION BY dv.Id_Venta
              ORDER BY dv.nro_item
              ROWS UNBOUNDED PRECEDING)                    AS total_acumulado
FROM Venta v
JOIN Cliente       c  ON c.Id_Cliente      = v.Id_Cliente
JOIN Metodo_pago   mp ON mp.Id_metodo_pago = v.Id_metodo_pago
JOIN Detalle_Venta dv ON dv.Id_Venta       = v.Id_Venta
JOIN Producto      p  ON p.Id_Producto     = dv.Id_Producto
JOIN Talle         t  ON t.Id_Talle        = dv.Id_Talle
WHERE v.Id_Venta = @id_venta
ORDER BY dv.nro_item;
GO

-- ---------------------------------------------------------------------
-- 1.b Pie del comprobante: subtotal de renglones, descuento por metodo
--     de pago (RN.07) y total final, comparado con Venta.total.
--     control_ok = 1 si el total guardado coincide con el recalculado.
-- ---------------------------------------------------------------------
DECLARE @id_venta INT = 1;

SELECT
    v.Id_Venta                                    AS nro_comprobante,
    mp.nombre                                     AS metodo_pago,
    mp.porcentaje_descuento                       AS pct_descuento,
    SUM(dv.cantidad * dv.precio_unitario)         AS subtotal_renglones,
    v.descuento_aplicado                          AS descuento,
    SUM(dv.cantidad * dv.precio_unitario)
        - v.descuento_aplicado                    AS total_calculado,
    v.total                                       AS total_registrado,
    CASE WHEN SUM(dv.cantidad * dv.precio_unitario) - v.descuento_aplicado = v.total
         THEN 1 ELSE 0 END                        AS control_ok
FROM Venta v
JOIN Metodo_pago   mp ON mp.Id_metodo_pago = v.Id_metodo_pago
JOIN Detalle_Venta dv ON dv.Id_Venta       = v.Id_Venta
WHERE v.Id_Venta = @id_venta
GROUP BY v.Id_Venta, mp.nombre, mp.porcentaje_descuento, v.descuento_aplicado, v.total;
GO

-- ---------------------------------------------------------------------
-- 1.c Control global: ventas cuyo total registrado no coincide con el
--     detalle (deberia devolver 0 filas con los datos de prueba).
-- ---------------------------------------------------------------------
SELECT v.Id_Venta, v.total AS total_registrado,
       SUM(dv.cantidad * dv.precio_unitario) - v.descuento_aplicado AS total_calculado
FROM Venta v
JOIN Detalle_Venta dv ON dv.Id_Venta = v.Id_Venta
GROUP BY v.Id_Venta, v.total, v.descuento_aplicado
HAVING SUM(dv.cantidad * dv.precio_unitario) - v.descuento_aplicado <> v.total;
GO
