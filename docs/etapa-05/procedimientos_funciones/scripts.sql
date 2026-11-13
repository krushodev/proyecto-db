USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - PROCEDIMIENTOS Y FUNCIONES ALMACENADAS
-- Registra una venta completa con un solo EXEC: valida stock, guarda
-- encabezado y detalle con precio historico, descuenta inventario y
-- aplica los descuentos.
--
-- Contenido:
--   1. Funcion  fn_StockDisponible
--   2. Funcion  fn_CalcularDescuentoCliente
--   3. Tipo     tt_DetalleVenta (renglones de la venta)
--   4. Procedimiento sp_RegistrarVentaCompleta
--   5. Procedimiento sp_ActualizarStock
--   6. Pruebas: exito, error y casos limite
--
-- Reglas de negocio: RN.02, RN.04, RN.05, RN.06, RN.07, RN.08
-- Requiere haber ejecutado antes ecommerce.sql y tienda_ropa_dml.sql.
-- Es re-ejecutable: usa CREATE OR ALTER y las pruebas se revierten.
-- =====================================================================

-- =====================================================================
-- 1. FUNCION: fn_StockDisponible
--    Devuelve el stock de un producto en un talle (el stock es por talle,
--    RN.01). Si la combinacion no existe devuelve 0.
-- =====================================================================
CREATE OR ALTER FUNCTION dbo.fn_StockDisponible (
    @Id_Producto INT,
    @Id_Talle    INT
)
RETURNS INT
AS
BEGIN
    DECLARE @stock INT;

    SELECT @stock = stock
    FROM dbo.Producto_Talle
    WHERE Id_Producto = @Id_Producto
      AND Id_Talle    = @Id_Talle;

    RETURN ISNULL(@stock, 0);
END;
GO

-- =====================================================================
-- 2. FUNCION: fn_CalcularDescuentoCliente
--    Descuento por cliente frecuente segun el monto acumulado de sus
--    compras (suma de Venta.total, ya con descuentos aplicados):
--      mas de 500000 -> 10 %
--      mas de 200000 ->  5 %
--      resto         ->  0 %
--    "Mas de" es estricto: exactamente 200000 todavia da 0 %.
-- =====================================================================
CREATE OR ALTER FUNCTION dbo.fn_CalcularDescuentoCliente (
    @Id_Cliente INT
)
RETURNS DECIMAL(5, 2)
AS
BEGIN
    DECLARE @acumulado  DECIMAL(12, 2);
    DECLARE @porcentaje DECIMAL(5, 2);

    SELECT @acumulado = ISNULL(SUM(total), 0)
    FROM dbo.Venta
    WHERE Id_Cliente = @Id_Cliente;

    SET @porcentaje = CASE
                          WHEN @acumulado > 500000 THEN 10.00
                          WHEN @acumulado > 200000 THEN  5.00
                          ELSE 0.00
                      END;

    RETURN @porcentaje;
END;
GO

-- =====================================================================
-- 3. TIPO DE TABLA: tt_DetalleVenta
--    Permite pasar varios renglones al procedimiento en una sola llamada.
--    La PK impide repetir el mismo producto-talle dentro de una venta.
-- =====================================================================
IF TYPE_ID(N'dbo.tt_DetalleVenta') IS NULL
BEGIN
    CREATE TYPE dbo.tt_DetalleVenta AS TABLE (
        Id_Producto INT NOT NULL,
        Id_Talle    INT NOT NULL,
        cantidad    INT NOT NULL,
        PRIMARY KEY (Id_Producto, Id_Talle)
    );
END;
GO

-- =====================================================================
-- 4. PROCEDIMIENTO: sp_RegistrarVentaCompleta
--    Pasos:
--      1. Valida cliente, metodo de pago y renglones.
--      2. Bloquea las filas de stock y verifica existencias (RN.02).
--      3. Inserta el encabezado en Venta.
--      4. Inserta los renglones con el precio historico: precio de lista
--         con la liquidacion aplicada (RN.05, RN.06, RN.08).
--      5. Descuenta el stock.
--      6. Calcula el descuento: cliente frecuente + metodo de pago, con
--         los porcentajes sumados (RN.07), y actualiza descuento y total.
--      7. Confirma. Si algo falla, deshace todo y relanza el error.
--    Devuelve el numero de venta en @Id_Venta (NULL si fallo).
--    Si se lo llama dentro de otra transaccion usa un savepoint, asi
--    solo deshace lo suyo y no la transaccion del que lo llamo.
-- =====================================================================
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarVentaCompleta
    @Id_Cliente     INT,
    @Id_metodo_pago INT,
    @canal          VARCHAR(50),
    @Detalle        dbo.tt_DetalleVenta READONLY,
    @Id_Venta       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Id_Venta = NULL;

    -- ---- 1. Validaciones previas (todavia no se modifico nada) --------
    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE Id_Cliente = @Id_Cliente)
        THROW 50002, 'El cliente no existe', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Metodo_pago WHERE Id_metodo_pago = @Id_metodo_pago)
        THROW 50003, 'El metodo de pago no existe', 1;

    IF NOT EXISTS (SELECT 1 FROM @Detalle)
        THROW 50004, 'La venta no tiene renglones', 1;

    IF EXISTS (SELECT 1 FROM @Detalle WHERE cantidad <= 0)
        THROW 50005, 'La cantidad de cada renglon debe ser mayor a 0', 1;

    IF EXISTS (SELECT 1
               FROM @Detalle d
               LEFT JOIN dbo.Producto_Talle pt
                      ON pt.Id_Producto = d.Id_Producto
                     AND pt.Id_Talle    = d.Id_Talle
               WHERE pt.Id_Producto IS NULL)
        THROW 50006, 'Hay un renglon con una combinacion producto-talle inexistente', 1;

    -- ---- Transaccion propia, o savepoint si ya habia una abierta -----
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @tran_propia = 1
            BEGIN TRANSACTION;
        ELSE
            SAVE TRANSACTION sp_venta;

        -- ---- 2. Bloqueo de stock y verificacion (RN.02) ---------------
        --    UPDLOCK + HOLDLOCK evitan que otra venta simultanea consuma
        --    el mismo stock entre la verificacion y el descuento.
        --    Se recorren todas las filas (COUNT) para tomar el bloqueo de
        --    cada una; el conteo en si no se usa despues.
        DECLARE @filas_bloqueadas INT;

        SELECT @filas_bloqueadas = COUNT(*)
        FROM dbo.Producto_Talle pt WITH (UPDLOCK, HOLDLOCK)
        JOIN @Detalle d
          ON d.Id_Producto = pt.Id_Producto
         AND d.Id_Talle    = pt.Id_Talle;

        -- Salvaguarda: cada renglon debe haber quedado bloqueado.
        IF @filas_bloqueadas <> (SELECT COUNT(*) FROM @Detalle)
            THROW 50006, 'Hay un renglon con una combinacion producto-talle inexistente', 1;

        IF EXISTS (SELECT 1
                   FROM @Detalle d
                   WHERE dbo.fn_StockDisponible(d.Id_Producto, d.Id_Talle) < d.cantidad)
            THROW 50001, 'Stock insuficiente', 1;

        -- ---- Descuentos (se calculan ANTES de registrar esta venta) ---
        DECLARE @pct_cliente DECIMAL(5, 2) = dbo.fn_CalcularDescuentoCliente(@Id_Cliente);
        DECLARE @pct_pago    DECIMAL(5, 2);
        DECLARE @pct_total   DECIMAL(5, 2);

        SELECT @pct_pago = porcentaje_descuento
        FROM dbo.Metodo_pago
        WHERE Id_metodo_pago = @Id_metodo_pago;

        SET @pct_total = @pct_cliente + @pct_pago;
        IF @pct_total > 100 SET @pct_total = 100;

        -- ---- 3. Encabezado de la venta --------------------------------
        INSERT INTO dbo.Venta (canal, Id_Cliente, Id_metodo_pago)
        VALUES (@canal, @Id_Cliente, @Id_metodo_pago);

        SET @Id_Venta = SCOPE_IDENTITY();

        -- ---- 4. Detalle con precio historico (RN.06, RN.08) -----------
        INSERT INTO dbo.Detalle_Venta
               (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
        SELECT @Id_Venta,
               ROW_NUMBER() OVER (ORDER BY d.Id_Producto, d.Id_Talle),
               d.Id_Producto,
               d.Id_Talle,
               d.cantidad,
               x.precio,
               d.cantidad * x.precio
        FROM @Detalle d
        JOIN dbo.Producto p ON p.Id_Producto = d.Id_Producto
        CROSS APPLY (
            SELECT CAST(p.precio_lista *
                        (1 - CASE WHEN p.en_liquidacion = 1
                                  THEN p.porcentaje_liquidacion ELSE 0 END / 100.0)
                        AS DECIMAL(10, 2)) AS precio
        ) x;

        -- ---- 5. Descuento de stock (RN.02) ----------------------------
        UPDATE pt
        SET pt.stock = pt.stock - d.cantidad
        FROM dbo.Producto_Talle pt
        JOIN @Detalle d
          ON d.Id_Producto = pt.Id_Producto
         AND d.Id_Talle    = pt.Id_Talle;

        -- ---- 6. Descuento y total de la venta (RN.07) -----------------
        DECLARE @subtotal  DECIMAL(10, 2);
        DECLARE @descuento DECIMAL(10, 2);

        SELECT @subtotal = SUM(subtotal)
        FROM dbo.Detalle_Venta
        WHERE Id_Venta = @Id_Venta;

        SET @descuento = ROUND(@subtotal * @pct_total / 100, 2);

        UPDATE dbo.Venta
        SET descuento_aplicado = @descuento,
            total              = @subtotal - @descuento
        WHERE Id_Venta = @Id_Venta;

        -- ---- 7. Confirmacion ------------------------------------------
        IF @tran_propia = 1
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        ELSE IF @tran_propia = 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION sp_venta;

        SET @Id_Venta = NULL;
        THROW;
    END CATCH;
END;
GO

-- =====================================================================
-- 5. PROCEDIMIENTO: sp_ActualizarStock
--    Suma o resta unidades al stock de un producto en un talle:
--      @cantidad > 0 -> ingreso de mercaderia
--      @cantidad < 0 -> ajuste a la baja (rotura, perdida, inventario)
--    No permite dejar el stock en negativo (RN.02) ni trabajar con una
--    combinacion producto-talle que no existe. Devuelve el stock
--    resultante en @stock_resultante.
--    Es una sola sentencia UPDATE, por lo que es atomica: no necesita
--    transaccion propia ni se pisa con ventas simultaneas.
-- =====================================================================
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarStock
    @Id_Producto      INT,
    @Id_Talle         INT,
    @cantidad         INT,
    @stock_resultante INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @stock_resultante = NULL;

    IF @cantidad = 0
        THROW 50007, 'La cantidad a ajustar no puede ser 0', 1;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.Producto_Talle
                   WHERE Id_Producto = @Id_Producto
                     AND Id_Talle    = @Id_Talle)
        THROW 50008, 'La combinacion producto-talle no existe', 1;

    -- El WHERE impide que el stock quede negativo: si el ajuste no
    -- corresponde, no se modifica ninguna fila.
    UPDATE dbo.Producto_Talle
    SET @stock_resultante = stock = stock + @cantidad
    WHERE Id_Producto = @Id_Producto
      AND Id_Talle    = @Id_Talle
      AND stock + @cantidad >= 0;

    IF @@ROWCOUNT = 0
    BEGIN
        SET @stock_resultante = NULL;
        THROW 50009, 'El ajuste dejaria el stock en negativo', 1;
    END;
END;
GO

-- =====================================================================
-- 6. PRUEBAS
--    Cada prueba indica el resultado esperado. Las de exito se ejecutan
--    dentro de una transaccion que se revierte (ROLLBACK), asi los datos
--    del DML quedan intactos y el script se puede repetir.
--    Datos de partida (tienda_ropa_dml.sql):
--      Stock (Producto, Talle): (1,1)=12  (6,7)=25  (2,1)=8
--                               (10,10)=30  (4,4)=5
--      Cliente 1 acumulado = 145950 | Cliente 2 = 48000 | Cliente 3 = 42390
-- =====================================================================

-- ---------------------------------------------------------------------
-- PRUEBA 1: funciones sobre los datos cargados
-- Esperado: fn_StockDisponible(1,1) = 12 ; (1,9) no existe = 0
--           fn_CalcularDescuentoCliente = 0 para todos (ninguno supera
--           200000 acumulados)
-- ---------------------------------------------------------------------
SELECT dbo.fn_StockDisponible(1, 1) AS stock_existente,
       dbo.fn_StockDisponible(1, 9) AS stock_combinacion_inexistente;

SELECT c.Id_Cliente, c.nombre, c.apellido,
       ISNULL((SELECT SUM(v.total) FROM dbo.Venta v WHERE v.Id_Cliente = c.Id_Cliente), 0) AS acumulado,
       dbo.fn_CalcularDescuentoCliente(c.Id_Cliente) AS descuento_pct
FROM dbo.Cliente c
ORDER BY c.Id_Cliente;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 2: umbrales de la funcion de descuento (casos limite)
-- Se agregan ventas de prueba al cliente 1 (acumulado inicial 145950).
-- Esperado: 200000.00 -> 0 % | 200000.01 -> 5 %
--           500000.00 -> 5 % | 500000.01 -> 10 %
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;

    INSERT INTO dbo.Venta (canal, total, Id_Cliente, Id_metodo_pago) VALUES ('Prueba',  54050.00, 1, 1);
    SELECT 'a) acumulado 200000.00' AS caso, dbo.fn_CalcularDescuentoCliente(1) AS descuento_pct;

    INSERT INTO dbo.Venta (canal, total, Id_Cliente, Id_metodo_pago) VALUES ('Prueba',      0.01, 1, 1);
    SELECT 'b) acumulado 200000.01' AS caso, dbo.fn_CalcularDescuentoCliente(1) AS descuento_pct;

    INSERT INTO dbo.Venta (canal, total, Id_Cliente, Id_metodo_pago) VALUES ('Prueba', 299999.99, 1, 1);
    SELECT 'c) acumulado 500000.00' AS caso, dbo.fn_CalcularDescuentoCliente(1) AS descuento_pct;

    INSERT INTO dbo.Venta (canal, total, Id_Cliente, Id_metodo_pago) VALUES ('Prueba',      0.01, 1, 1);
    SELECT 'd) acumulado 500000.01' AS caso, dbo.fn_CalcularDescuentoCliente(1) AS descuento_pct;

ROLLBACK TRANSACTION;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 3: EXITO - venta de un renglon
-- Cliente 2, Efectivo (15 %), Remera Basica (6) talle M (7) x 2.
-- Esperado: subtotal 30000.00 | descuento 4500.00 (0 % cliente + 15 %
--           pago) | total 25500.00 | stock (6,7): 25 -> 23
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;

    DECLARE @detalle dbo.tt_DetalleVenta;
    DECLARE @id_venta INT;

    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (6, 7, 2);

    EXEC dbo.sp_RegistrarVentaCompleta
         @Id_Cliente     = 2,
         @Id_metodo_pago = 1,
         @canal          = 'Local',
         @Detalle        = @detalle,
         @Id_Venta       = @id_venta OUTPUT;

    SELECT * FROM dbo.Venta WHERE Id_Venta = @id_venta;
    SELECT * FROM dbo.Detalle_Venta WHERE Id_Venta = @id_venta;
    SELECT Id_Producto, Id_Talle, stock FROM dbo.Producto_Talle WHERE Id_Producto = 6 AND Id_Talle = 7;

ROLLBACK TRANSACTION;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 4: EXITO - dos renglones, liquidacion y cliente frecuente
-- Se le suma una venta de prueba de 60000 al cliente 1 (acumulado
-- 205950 -> 5 %). Compra con Transferencia (10 %):
--   Jean Skinny Negro (2) talle 36 (1) x 1 : 42000 -20 % = 33600
--   Cinturon de Cuero (10) talle Unico (10) x 2 : 18000 -25 % = 13500
-- Esperado: items 1 y 2 | subtotal 60600.00 | descuento 9090.00
--           (5 % + 10 % = 15 %) | total 51510.00
--           stock (2,1): 8 -> 7 | stock (10,10): 30 -> 28
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;

    INSERT INTO dbo.Venta (canal, total, Id_Cliente, Id_metodo_pago) VALUES ('Prueba', 60000.00, 1, 1);

    DECLARE @detalle dbo.tt_DetalleVenta;
    DECLARE @id_venta INT;

    SELECT dbo.fn_CalcularDescuentoCliente(1) AS descuento_cliente_antes;

    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (2, 1, 1), (10, 10, 2);

    EXEC dbo.sp_RegistrarVentaCompleta
         @Id_Cliente     = 1,
         @Id_metodo_pago = 2,
         @canal          = 'Web',
         @Detalle        = @detalle,
         @Id_Venta       = @id_venta OUTPUT;

    SELECT * FROM dbo.Venta WHERE Id_Venta = @id_venta;
    SELECT * FROM dbo.Detalle_Venta WHERE Id_Venta = @id_venta ORDER BY nro_item;
    SELECT Id_Producto, Id_Talle, stock FROM dbo.Producto_Talle
    WHERE (Id_Producto = 2 AND Id_Talle = 1) OR (Id_Producto = 10 AND Id_Talle = 10);

ROLLBACK TRANSACTION;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 5: LIMITE - comprar exactamente todo el stock, y despues una
--           unidad mas
-- Cliente 3, Tarjeta de credito 1 pago (0 %), Jean Slim Fit Celeste (4)
-- talle 42 (4): stock 5, precio con liquidacion 39100.
-- Esperado: 1ra venta OK, total 195500.00 y stock 0.
--           2da venta rechazada: "Stock insuficiente" (error 50001).
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;

    DECLARE @detalle dbo.tt_DetalleVenta;
    DECLARE @id_venta INT;

    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (4, 4, 5);

    EXEC dbo.sp_RegistrarVentaCompleta
         @Id_Cliente = 3, @Id_metodo_pago = 4, @canal = 'Local',
         @Detalle = @detalle, @Id_Venta = @id_venta OUTPUT;

    SELECT Id_Venta, descuento_aplicado, total FROM dbo.Venta WHERE Id_Venta = @id_venta;
    SELECT dbo.fn_StockDisponible(4, 4) AS stock_despues;

    -- una unidad mas: no hay stock
    DELETE FROM @detalle;
    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (4, 4, 1);

    BEGIN TRY
        EXEC dbo.sp_RegistrarVentaCompleta
             @Id_Cliente = 3, @Id_metodo_pago = 4, @canal = 'Local',
             @Detalle = @detalle, @Id_Venta = @id_venta OUTPUT;
        PRINT 'ERROR: la venta se registro y debia ser rechazada';
    END TRY
    BEGIN CATCH
        PRINT 'OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
    END CATCH;

    -- la venta rechazada no dejo nada: solo existe la 1ra (10 del DML + 1)
    SELECT (SELECT COUNT(*) FROM dbo.Venta) AS ventas_esperado_11,
           dbo.fn_StockDisponible(4, 4)     AS stock_esperado_0;

ROLLBACK TRANSACTION;
GO

-- ---------------------------------------------------------------------
-- PRUEBAS 6 A 11: ERRORES. Cada una debe ser rechazada y no dejar nada.
-- ---------------------------------------------------------------------

-- 6. Stock insuficiente (se piden 999 y hay 12)  -> error 50001
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
INSERT INTO @detalle VALUES (1, 1, 999);
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 1, 1, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '6. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 7. Cliente inexistente  -> error 50002
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
INSERT INTO @detalle VALUES (1, 1, 1);
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 999, 1, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '7. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 8. Metodo de pago inexistente  -> error 50003
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
INSERT INTO @detalle VALUES (1, 1, 1);
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 1, 999, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '8. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 9. Venta sin renglones  -> error 50004
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 1, 1, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '9. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 10. Cantidad cero  -> error 50005
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
INSERT INTO @detalle VALUES (1, 1, 0);
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 1, 1, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '10. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 11. Combinacion producto-talle inexistente (el Jean Mom no tiene talle XL)  -> error 50006
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;
INSERT INTO @detalle VALUES (1, 9, 1);
BEGIN TRY
    EXEC dbo.sp_RegistrarVentaCompleta 1, 1, 'Local', @detalle, @id_venta OUTPUT;
    PRINT 'ERROR: debia ser rechazada';
END TRY
BEGIN CATCH
    PRINT '11. OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- ---------------------------------------------------------------------
-- PRUEBAS 12 A 19: sp_ActualizarStock
-- ---------------------------------------------------------------------

-- 12. EXITO - ingreso de mercaderia: (1,1) +20
--     Esperado: stock 12 -> 32 ; @stock_resultante = 32
BEGIN TRANSACTION;
    DECLARE @stock INT;
    SELECT dbo.fn_StockDisponible(1, 1) AS stock_antes;
    EXEC dbo.sp_ActualizarStock @Id_Producto = 1, @Id_Talle = 1, @cantidad = 20, @stock_resultante = @stock OUTPUT;
    SELECT @stock AS stock_resultante, dbo.fn_StockDisponible(1, 1) AS stock_despues;
ROLLBACK TRANSACTION;
GO

-- 13. EXITO - ajuste a la baja: (1,1) -5
--     Esperado: stock 12 -> 7 ; @stock_resultante = 7
BEGIN TRANSACTION;
    DECLARE @stock INT;
    SELECT dbo.fn_StockDisponible(1, 1) AS stock_antes;
    EXEC dbo.sp_ActualizarStock @Id_Producto = 1, @Id_Talle = 1, @cantidad = -5, @stock_resultante = @stock OUTPUT;
    SELECT @stock AS stock_resultante, dbo.fn_StockDisponible(1, 1) AS stock_despues;
ROLLBACK TRANSACTION;
GO

-- 14. LIMITE - dejar el stock exactamente en 0 y luego restar 1 mas
--     (4,4) tiene 5 unidades.
--     Esperado: -5 OK (stock 0) ; -1 rechazado con error 50009
BEGIN TRANSACTION;
    DECLARE @stock INT;
    EXEC dbo.sp_ActualizarStock @Id_Producto = 4, @Id_Talle = 4, @cantidad = -5, @stock_resultante = @stock OUTPUT;
    SELECT @stock AS stock_resultante_esperado_0;

    BEGIN TRY
        EXEC dbo.sp_ActualizarStock @Id_Producto = 4, @Id_Talle = 4, @cantidad = -1, @stock_resultante = @stock OUTPUT;
        PRINT 'ERROR: el ajuste se aplico y debia ser rechazado';
    END TRY
    BEGIN CATCH
        PRINT 'OK - rechazado (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
    END CATCH;

    SELECT dbo.fn_StockDisponible(4, 4) AS stock_esperado_0;
ROLLBACK TRANSACTION;
GO

-- 15. INTEGRACION - reponer stock y recien ahi poder vender
--     (4,4) tiene 5 unidades. Cliente 3, Tarjeta de credito 1 pago (0 %).
--     Esperado: vender 8 -> rechazado (50001) ; ingresar +10 -> stock 15 ;
--               vender 8 -> OK, total 312800.00 (8 x 39100.00), stock 7
BEGIN TRANSACTION;
    DECLARE @detalle dbo.tt_DetalleVenta;
    DECLARE @id_venta INT;
    DECLARE @stock INT;

    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (4, 4, 8);

    BEGIN TRY
        EXEC dbo.sp_RegistrarVentaCompleta
             @Id_Cliente = 3, @Id_metodo_pago = 4, @canal = 'Local',
             @Detalle = @detalle, @Id_Venta = @id_venta OUTPUT;
        PRINT 'ERROR: la venta se registro y debia ser rechazada';
    END TRY
    BEGIN CATCH
        PRINT 'OK - rechazada (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
    END CATCH;

    EXEC dbo.sp_ActualizarStock @Id_Producto = 4, @Id_Talle = 4, @cantidad = 10, @stock_resultante = @stock OUTPUT;
    SELECT @stock AS stock_tras_el_ingreso;

    EXEC dbo.sp_RegistrarVentaCompleta
         @Id_Cliente = 3, @Id_metodo_pago = 4, @canal = 'Local',
         @Detalle = @detalle, @Id_Venta = @id_venta OUTPUT;

    SELECT Id_Venta, descuento_aplicado, total FROM dbo.Venta WHERE Id_Venta = @id_venta;
    SELECT dbo.fn_StockDisponible(4, 4) AS stock_tras_la_venta;
ROLLBACK TRANSACTION;
GO

-- 16. ERROR - cantidad 0  -> error 50007
DECLARE @stock INT;
BEGIN TRY
    EXEC dbo.sp_ActualizarStock 1, 1, 0, @stock OUTPUT;
    PRINT 'ERROR: debia ser rechazado';
END TRY
BEGIN CATCH
    PRINT '16. OK - rechazado (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 17. ERROR - combinacion producto-talle inexistente  -> error 50008
DECLARE @stock INT;
BEGIN TRY
    EXEC dbo.sp_ActualizarStock 1, 9, 10, @stock OUTPUT;
    PRINT 'ERROR: debia ser rechazado';
END TRY
BEGIN CATCH
    PRINT '17. OK - rechazado (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- 18. ERROR - el ajuste deja el stock en negativo (se restan 13 y hay 12)  -> error 50009
DECLARE @stock INT;
BEGIN TRY
    EXEC dbo.sp_ActualizarStock 1, 1, -13, @stock OUTPUT;
    PRINT 'ERROR: debia ser rechazado';
END TRY
BEGIN CATCH
    PRINT '18. OK - rechazado (' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + '): ' + ERROR_MESSAGE();
END CATCH;
GO

-- ---------------------------------------------------------------------
-- PRUEBA 19: verificacion final - los errores y las pruebas revertidas
--            no dejaron rastros
-- Esperado: 10 ventas | 17 renglones | stock (1,1) = 12 | (6,7) = 25
--           | (4,4) = 5
-- ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM dbo.Venta)         AS ventas,
       (SELECT COUNT(*) FROM dbo.Detalle_Venta) AS renglones,
       dbo.fn_StockDisponible(1, 1)             AS stock_1_1,
       dbo.fn_StockDisponible(6, 7)             AS stock_6_7,
       dbo.fn_StockDisponible(4, 4)             AS stock_4_4;
GO

-- ---------------------------------------------------------------------
-- USO DE LA FUNCION EN UNA CONSULTA (como propone la guia)
-- ---------------------------------------------------------------------
SELECT nombre, apellido, dbo.fn_CalcularDescuentoCliente(Id_Cliente) AS descuento
FROM dbo.Cliente;
GO
