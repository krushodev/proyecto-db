USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - TRIGGERS DE AUDITORIA
-- Registra en la tabla Auditoria quien modifico precios, liquidaciones
-- y stock, con el valor anterior y el nuevo.
--
-- Contenido (pendiente):
--   1. Tabla Auditoria
--   2. Trigger sobre Producto        (precio_lista, en_liquidacion, porcentaje_liquidacion)
--   3. Trigger sobre Producto_Talle  (stock)
--   4. Pruebas: exito, sin cambios, varias filas, DELETE, NULL
-- =====================================================================
