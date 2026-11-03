USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - 2. MANEJO DE TRANSACCIONES
-- Registro de una venta como una unica unidad de trabajo (atomicidad):
--   1. INSERT en Venta          (encabezado)
--   2. INSERT en Detalle_Venta  (renglones con precio historico, RN.08)
--   3. UPDATE de Producto_Talle (descuento de stock, RN.02)
-- Si cualquier paso falla, se deshace todo: no queda venta, ni detalle,
-- ni stock modificado.
--
-- Cada prueba es un lote independiente con los mismos pasos y distintos
-- parametros. No se usan procedimientos almacenados: ese tema es de otro
-- integrante, y estos bloques se pueden envolver en uno mas adelante.
--
-- Decisiones de diseno:
--  * SET XACT_ABORT ON + TRY/CATCH: cualquier error de ejecucion deja la
--    transaccion en estado doomed y el CATCH hace ROLLBACK.
--  * El stock se descuenta con UPDATE ... WHERE stock >= cantidad y se
--    controla @@ROWCOUNT. Es una sola sentencia atomica: dos ventas
--    simultaneas no pueden dejar el stock negativo (ver
--    scripts_concurrencia.sql).
--  * El total y el descuento se calculan ANTES de insertar la venta,
--    porque rol_mostrador tiene DENY UPDATE sobre Venta (seguridad.sql).
--
-- Requisitos: ecommerce.sql y tienda_ropa_dml.sql. Si existe la tabla
-- Auditoria (triggers_auditoria/scripts.sql), tambien se muestra como
-- el ROLLBACK deshace los registros de auditoria.
--
-- La prueba 1 deja datos reales (venta 11 y stock -2): la seccion 6
-- los restablece.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PRUEBA 1 (correcta): venta de 2 unidades del producto 8 (talle 1,
-- stock 10), pagada en efectivo (15 %).
-- Esperado: COMMIT; 1 venta y 1 renglon nuevos; stock 10 -> 8.
-- ---------------------------------------------------------------------
DECLARE @id_cliente INT = 1, @id_metodo INT = 1, @canal VARCHAR(50) = 'Local';
DECLARE @items TABLE (Id_Producto INT NOT NULL, Id_Talle INT NOT NULL, cantidad INT NOT NULL,
                      PRIMARY KEY (Id_Producto, Id_Talle));
INSERT INTO @items VALUES (8, 1, 2);

DECLARE @antes TABLE (Id_Producto INT, Id_Talle INT, stock INT);
INSERT INTO @antes
SELECT pt.Id_Producto, pt.Id_Talle, pt.stock
FROM Producto_Talle pt JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle;
DECLARE @ventas_antes INT = (SELECT COUNT(*) FROM Venta);
DECLARE @detalles_antes INT = (SELECT COUNT(*) FROM Detalle_Venta);
DECLARE @aud_antes INT = CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN 0
                              ELSE (SELECT COUNT(*) FROM Auditoria) END;

DECLARE @resultado VARCHAR(300), @id_venta INT, @subtotal DECIMAL(10,2), @descuento DECIMAL(10,2);

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    -- Precio vigente = precio de lista con la liquidacion aplicada (RN.06).
    SELECT @subtotal = SUM(i.cantidad * pu.precio)
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    -- Descuento por metodo de pago (RN.07).
    SELECT @descuento = CAST(ROUND(@subtotal * mp.porcentaje_descuento / 100.0, 2) AS DECIMAL(10,2))
    FROM Metodo_pago mp WHERE mp.Id_metodo_pago = @id_metodo;

    -- Paso 1: encabezado
    INSERT INTO Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (@canal, @descuento, @subtotal - @descuento, @id_cliente, @id_metodo);
    SET @id_venta = SCOPE_IDENTITY();

    -- Paso 2: detalle con el precio historico (RN.08)
    INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
    SELECT @id_venta, ROW_NUMBER() OVER (ORDER BY i.Id_Producto, i.Id_Talle),
           i.Id_Producto, i.Id_Talle, i.cantidad, pu.precio, i.cantidad * pu.precio
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    -- Paso 3: stock. Solo descuenta si alcanza; si algun renglon no alcanza,
    -- se actualizan menos filas que renglones y se aborta la venta (RN.02).
    UPDATE pt SET stock = pt.stock - i.cantidad
    FROM Producto_Talle pt
    JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle
    WHERE pt.stock >= i.cantidad;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @items)
        THROW 50001, 'Stock insuficiente para uno o mas renglones.', 1;

    COMMIT TRANSACTION;
    SET @resultado = CONCAT('COMMIT: venta ', @id_venta, ' registrada');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET @resultado = CONCAT('ROLLBACK: ', ERROR_MESSAGE());
END CATCH;

SELECT 'P1' AS prueba, @resultado AS resultado,
       (SELECT COUNT(*) FROM Venta) - @ventas_antes AS ventas_nuevas,
       (SELECT COUNT(*) FROM Detalle_Venta) - @detalles_antes AS renglones_nuevos,
       CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN NULL
            ELSE (SELECT COUNT(*) FROM Auditoria) - @aud_antes END AS filas_auditoria_nuevas;
SELECT 'P1' AS prueba, a.Id_Producto, a.Id_Talle, a.stock AS stock_antes, pt.stock AS stock_despues
FROM @antes a JOIN Producto_Talle pt ON pt.Id_Producto = a.Id_Producto AND pt.Id_Talle = a.Id_Talle;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 2 (incorrecta): se piden 10 unidades del producto 4 (talle 3),
-- que tiene 9.
-- Esperado: ROLLBACK; 0 ventas, 0 renglones y 0 filas de auditoria
-- nuevas; stock sin cambios (9 -> 9).
-- ---------------------------------------------------------------------
DECLARE @id_cliente INT = 2, @id_metodo INT = 4, @canal VARCHAR(50) = 'Web';
DECLARE @items TABLE (Id_Producto INT NOT NULL, Id_Talle INT NOT NULL, cantidad INT NOT NULL,
                      PRIMARY KEY (Id_Producto, Id_Talle));
INSERT INTO @items VALUES (4, 3, 10);

DECLARE @antes TABLE (Id_Producto INT, Id_Talle INT, stock INT);
INSERT INTO @antes
SELECT pt.Id_Producto, pt.Id_Talle, pt.stock
FROM Producto_Talle pt JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle;
DECLARE @ventas_antes INT = (SELECT COUNT(*) FROM Venta);
DECLARE @detalles_antes INT = (SELECT COUNT(*) FROM Detalle_Venta);
DECLARE @aud_antes INT = CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN 0
                              ELSE (SELECT COUNT(*) FROM Auditoria) END;

DECLARE @resultado VARCHAR(300), @id_venta INT, @subtotal DECIMAL(10,2), @descuento DECIMAL(10,2);

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @subtotal = SUM(i.cantidad * pu.precio)
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    SELECT @descuento = CAST(ROUND(@subtotal * mp.porcentaje_descuento / 100.0, 2) AS DECIMAL(10,2))
    FROM Metodo_pago mp WHERE mp.Id_metodo_pago = @id_metodo;

    INSERT INTO Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (@canal, @descuento, @subtotal - @descuento, @id_cliente, @id_metodo);
    SET @id_venta = SCOPE_IDENTITY();

    INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
    SELECT @id_venta, ROW_NUMBER() OVER (ORDER BY i.Id_Producto, i.Id_Talle),
           i.Id_Producto, i.Id_Talle, i.cantidad, pu.precio, i.cantidad * pu.precio
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    UPDATE pt SET stock = pt.stock - i.cantidad
    FROM Producto_Talle pt
    JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle
    WHERE pt.stock >= i.cantidad;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @items)
        THROW 50001, 'Stock insuficiente para uno o mas renglones.', 1;

    COMMIT TRANSACTION;
    SET @resultado = CONCAT('COMMIT: venta ', @id_venta, ' registrada');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET @resultado = CONCAT('ROLLBACK: ', ERROR_MESSAGE());
END CATCH;

SELECT 'P2' AS prueba, @resultado AS resultado,
       (SELECT COUNT(*) FROM Venta) - @ventas_antes AS ventas_nuevas,
       (SELECT COUNT(*) FROM Detalle_Venta) - @detalles_antes AS renglones_nuevos,
       CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN NULL
            ELSE (SELECT COUNT(*) FROM Auditoria) - @aud_antes END AS filas_auditoria_nuevas;
SELECT 'P2' AS prueba, a.Id_Producto, a.Id_Talle, a.stock AS stock_antes, pt.stock AS stock_despues
FROM @antes a JOIN Producto_Talle pt ON pt.Id_Producto = a.Id_Producto AND pt.Id_Talle = a.Id_Talle;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 3 (incorrecta, varios renglones): el renglon 1 tiene stock
-- (producto 8, talle 2: 10 unidades, se piden 1) y el renglon 2 no
-- (producto 4, talle 4: 5 unidades, se piden 6).
-- Esperado: ROLLBACK; el renglon valido tampoco descuenta stock
-- (producto 8 talle 2: 10 -> 10) y no queda ninguna venta.
-- ---------------------------------------------------------------------
DECLARE @id_cliente INT = 3, @id_metodo INT = 2, @canal VARCHAR(50) = 'Instagram';
DECLARE @items TABLE (Id_Producto INT NOT NULL, Id_Talle INT NOT NULL, cantidad INT NOT NULL,
                      PRIMARY KEY (Id_Producto, Id_Talle));
INSERT INTO @items VALUES (8, 2, 1), (4, 4, 6);

DECLARE @antes TABLE (Id_Producto INT, Id_Talle INT, stock INT);
INSERT INTO @antes
SELECT pt.Id_Producto, pt.Id_Talle, pt.stock
FROM Producto_Talle pt JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle;
DECLARE @ventas_antes INT = (SELECT COUNT(*) FROM Venta);
DECLARE @detalles_antes INT = (SELECT COUNT(*) FROM Detalle_Venta);
DECLARE @aud_antes INT = CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN 0
                              ELSE (SELECT COUNT(*) FROM Auditoria) END;

DECLARE @resultado VARCHAR(300), @id_venta INT, @subtotal DECIMAL(10,2), @descuento DECIMAL(10,2);

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @subtotal = SUM(i.cantidad * pu.precio)
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    SELECT @descuento = CAST(ROUND(@subtotal * mp.porcentaje_descuento / 100.0, 2) AS DECIMAL(10,2))
    FROM Metodo_pago mp WHERE mp.Id_metodo_pago = @id_metodo;

    INSERT INTO Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (@canal, @descuento, @subtotal - @descuento, @id_cliente, @id_metodo);
    SET @id_venta = SCOPE_IDENTITY();

    INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
    SELECT @id_venta, ROW_NUMBER() OVER (ORDER BY i.Id_Producto, i.Id_Talle),
           i.Id_Producto, i.Id_Talle, i.cantidad, pu.precio, i.cantidad * pu.precio
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    UPDATE pt SET stock = pt.stock - i.cantidad
    FROM Producto_Talle pt
    JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle
    WHERE pt.stock >= i.cantidad;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @items)
        THROW 50001, 'Stock insuficiente para uno o mas renglones.', 1;

    COMMIT TRANSACTION;
    SET @resultado = CONCAT('COMMIT: venta ', @id_venta, ' registrada');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET @resultado = CONCAT('ROLLBACK: ', ERROR_MESSAGE());
END CATCH;

SELECT 'P3' AS prueba, @resultado AS resultado,
       (SELECT COUNT(*) FROM Venta) - @ventas_antes AS ventas_nuevas,
       (SELECT COUNT(*) FROM Detalle_Venta) - @detalles_antes AS renglones_nuevos,
       CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN NULL
            ELSE (SELECT COUNT(*) FROM Auditoria) - @aud_antes END AS filas_auditoria_nuevas;
SELECT 'P3' AS prueba, a.Id_Producto, a.Id_Talle, a.stock AS stock_antes, pt.stock AS stock_despues
FROM @antes a JOIN Producto_Talle pt ON pt.Id_Producto = a.Id_Producto AND pt.Id_Talle = a.Id_Talle
ORDER BY a.Id_Producto;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 4 (error inesperado): el producto 1 no tiene stock cargado
-- para el talle 10, asi que el INSERT del detalle viola la clave
-- foranea (Detalle_Venta -> Producto_Talle) cuando la venta ya fue
-- insertada. Con XACT_ABORT ON, el error no deja nada a medias.
-- Esperado: ROLLBACK con el error de FOREIGN KEY; 0 ventas nuevas.
-- ---------------------------------------------------------------------
DECLARE @id_cliente INT = 4, @id_metodo INT = 6, @canal VARCHAR(50) = 'Web';
DECLARE @items TABLE (Id_Producto INT NOT NULL, Id_Talle INT NOT NULL, cantidad INT NOT NULL,
                      PRIMARY KEY (Id_Producto, Id_Talle));
INSERT INTO @items VALUES (1, 10, 1);

DECLARE @antes TABLE (Id_Producto INT, Id_Talle INT, stock INT);
INSERT INTO @antes
SELECT pt.Id_Producto, pt.Id_Talle, pt.stock
FROM Producto_Talle pt JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle;
DECLARE @ventas_antes INT = (SELECT COUNT(*) FROM Venta);
DECLARE @detalles_antes INT = (SELECT COUNT(*) FROM Detalle_Venta);
DECLARE @aud_antes INT = CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN 0
                              ELSE (SELECT COUNT(*) FROM Auditoria) END;

DECLARE @resultado VARCHAR(300), @id_venta INT, @subtotal DECIMAL(10,2), @descuento DECIMAL(10,2);

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @subtotal = SUM(i.cantidad * pu.precio)
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    SELECT @descuento = CAST(ROUND(@subtotal * mp.porcentaje_descuento / 100.0, 2) AS DECIMAL(10,2))
    FROM Metodo_pago mp WHERE mp.Id_metodo_pago = @id_metodo;

    INSERT INTO Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (@canal, @descuento, @subtotal - @descuento, @id_cliente, @id_metodo);
    SET @id_venta = SCOPE_IDENTITY();

    INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
    SELECT @id_venta, ROW_NUMBER() OVER (ORDER BY i.Id_Producto, i.Id_Talle),
           i.Id_Producto, i.Id_Talle, i.cantidad, pu.precio, i.cantidad * pu.precio
    FROM @items i
    JOIN Producto p ON p.Id_Producto = i.Id_Producto
    CROSS APPLY (SELECT CAST(ROUND(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                       THEN p.porcentaje_liquidacion ELSE 0 END / 100.0), 2) AS DECIMAL(10,2)) AS precio) pu;

    UPDATE pt SET stock = pt.stock - i.cantidad
    FROM Producto_Talle pt
    JOIN @items i ON i.Id_Producto = pt.Id_Producto AND i.Id_Talle = pt.Id_Talle
    WHERE pt.stock >= i.cantidad;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @items)
        THROW 50001, 'Stock insuficiente para uno o mas renglones.', 1;

    COMMIT TRANSACTION;
    SET @resultado = CONCAT('COMMIT: venta ', @id_venta, ' registrada');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET @resultado = CONCAT('ROLLBACK: ', ERROR_MESSAGE());
END CATCH;

SELECT 'P4' AS prueba, @resultado AS resultado,
       (SELECT COUNT(*) FROM Venta) - @ventas_antes AS ventas_nuevas,
       (SELECT COUNT(*) FROM Detalle_Venta) - @detalles_antes AS renglones_nuevos,
       CASE WHEN OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL THEN NULL
            ELSE (SELECT COUNT(*) FROM Auditoria) - @aud_antes END AS filas_auditoria_nuevas;
GO

-- ---------------------------------------------------------------------
-- 5. VERIFICACION DE LA VENTA CONFIRMADA (prueba 1)
--    El total registrado debe coincidir con el detalle menos el descuento.
-- ---------------------------------------------------------------------
SELECT v.Id_Venta, v.canal, mp.nombre AS metodo_pago,
       SUM(dv.subtotal) AS subtotal_renglones, v.descuento_aplicado, v.total,
       CASE WHEN SUM(dv.subtotal) - v.descuento_aplicado = v.total THEN 'SI' ELSE 'NO' END AS total_consistente
FROM Venta v
JOIN Metodo_pago mp   ON mp.Id_metodo_pago = v.Id_metodo_pago
JOIN Detalle_Venta dv ON dv.Id_Venta = v.Id_Venta
WHERE v.Id_Venta > 10
GROUP BY v.Id_Venta, v.canal, mp.nombre, v.descuento_aplicado, v.total;

-- Movimientos de stock que dejaron los triggers de auditoria (si existen).
IF OBJECT_ID(N'dbo.Auditoria', N'U') IS NOT NULL
    SELECT tabla, operacion, clave, campo, valor_anterior, valor_nuevo
    FROM Auditoria ORDER BY Id_Auditoria;
GO

-- ---------------------------------------------------------------------
-- 6. RESTABLECER LOS DATOS DE PRUEBA (opcional)
--    Borra la venta de la prueba 1 (el detalle cae en cascada) y devuelve
--    el stock. Los triggers tambien auditan esta limpieza.
--    El contador IDENTITY de Venta no se reinicia.
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;
    DELETE FROM Venta WHERE Id_Venta > 10;
    UPDATE Producto_Talle SET stock = stock + 2 WHERE Id_Producto = 8 AND Id_Talle = 1;
COMMIT TRANSACTION;

SELECT (SELECT COUNT(*) FROM Venta) AS ventas,
       (SELECT COUNT(*) FROM Detalle_Venta) AS renglones,
       (SELECT stock FROM Producto_Talle WHERE Id_Producto = 8 AND Id_Talle = 1) AS stock_p8_t1;
GO
