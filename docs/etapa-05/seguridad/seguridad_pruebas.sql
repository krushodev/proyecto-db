USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - 4. SEGURIDAD: PRUEBAS
-- Ejecuta cada operacion como un usuario de prueba y compara el resultado
-- con el esperado. Cada operacion se revierte, asi que no altera datos.
--
-- Requisito: haber ejecutado seguridad.sql.
-- Resultado esperado: todas las filas con ok = 'SI'.
-- =====================================================================
SET NOCOUNT ON;

DECLARE @pruebas TABLE (
    nro INT IDENTITY(1,1),
    usuario SYSNAME,
    operacion VARCHAR(60),
    sentencia NVARCHAR(MAX),
    debe_permitir BIT
);

DECLARE @comprobante NVARCHAR(MAX) = N'
    DECLARE @n INT;
    SELECT @n = COUNT(*)
    FROM Venta v
    JOIN Cliente c        ON c.Id_Cliente = v.Id_Cliente
    JOIN Metodo_pago mp   ON mp.Id_metodo_pago = v.Id_metodo_pago
    JOIN Detalle_Venta dv ON dv.Id_Venta = v.Id_Venta
    JOIN Producto p       ON p.Id_Producto = dv.Id_Producto
    JOIN Talle t          ON t.Id_Talle = dv.Id_Talle;';

DECLARE @venta NVARCHAR(MAX) = N'
    INSERT INTO Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (''Local'', 0, 15000, 1, 4);
    INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal)
    VALUES (SCOPE_IDENTITY(), 1, 6, 7, 1, 15000, 15000);
    UPDATE Producto_Talle SET stock = stock - 1 WHERE Id_Producto = 6 AND Id_Talle = 7;';

INSERT INTO @pruebas (usuario, operacion, sentencia, debe_permitir) VALUES
-- Mostrador: lo que necesita para trabajar
('usr_mostrador_demo', 'Emitir comprobante (CU-01)',     @comprobante, 1),
('usr_mostrador_demo', 'Registrar una venta completa',   @venta, 1),
('usr_mostrador_demo', 'Registrar un cliente nuevo',     N'INSERT INTO Cliente (nombre, apellido, dni, email) VALUES (''Ana'', ''Paz'', ''99999999'', ''ana.paz@mail.com'');', 1),
('usr_mostrador_demo', 'Corregir telefono de un cliente', N'UPDATE Cliente SET telefono = ''3794-000000'' WHERE Id_Cliente = 1;', 1),
-- Mostrador: lo que no debe poder hacer
('usr_mostrador_demo', 'Cambiar un precio',              N'UPDATE Producto SET precio_lista = 1 WHERE Id_Producto = 1;', 0),
('usr_mostrador_demo', 'Crear un producto',              N'INSERT INTO Producto (nombre, precio_lista, Id_Categoria) VALUES (''X'', 1, 1);', 0),
('usr_mostrador_demo', 'Cambiar el DNI de un cliente',   N'UPDATE Cliente SET dni = ''1'' WHERE Id_Cliente = 1;', 0),
('usr_mostrador_demo', 'Borrar un cliente',              N'DELETE FROM Cliente WHERE Id_Cliente = 10;', 0),
('usr_mostrador_demo', 'Modificar el total de una venta', N'UPDATE Venta SET total = 1 WHERE Id_Venta = 1;', 0),
('usr_mostrador_demo', 'Borrar una venta',               N'DELETE FROM Venta WHERE Id_Venta = 1;', 0),
('usr_mostrador_demo', 'Borrar stock de un talle',       N'DELETE FROM Producto_Talle WHERE Id_Producto = 5 AND Id_Talle = 8;', 0),
('usr_mostrador_demo', 'Crear una tabla',                N'CREATE TABLE dbo.tabla_prohibida (id INT);', 0),
('usr_mostrador_demo', 'Eliminar una tabla',             N'DROP TABLE Detalle_Venta;', 0),
-- Administrador: hereda lo del mostrador y suma el catalogo
('usr_admin_demo', 'Emitir comprobante (heredado)',      @comprobante, 1),
('usr_admin_demo', 'Registrar una venta (heredado)',     @venta, 1),
('usr_admin_demo', 'Cambiar un precio',                  N'UPDATE Producto SET precio_lista = 50000 WHERE Id_Producto = 1;', 1),
('usr_admin_demo', 'Poner un producto en liquidacion',   N'UPDATE Producto SET en_liquidacion = 1, porcentaje_liquidacion = 30 WHERE Id_Producto = 1;', 1),
('usr_admin_demo', 'Crear un producto',                  N'INSERT INTO Producto (nombre, precio_lista, Id_Categoria) VALUES (''X'', 1, 1);', 1),
('usr_admin_demo', 'Crear y borrar una categoria',       N'INSERT INTO Categoria (nombre) VALUES (''X''); DELETE FROM Categoria WHERE nombre = ''X'';', 1),
-- Administrador: el historial y la estructura siguen protegidos
('usr_admin_demo', 'Modificar el total de una venta',    N'UPDATE Venta SET total = 1 WHERE Id_Venta = 1;', 0),
('usr_admin_demo', 'Borrar una venta',                   N'DELETE FROM Venta WHERE Id_Venta = 1;', 0),
('usr_admin_demo', 'Modificar un detalle de venta',      N'UPDATE Detalle_Venta SET precio_unitario = 1 WHERE Id_Venta = 1;', 0),
('usr_admin_demo', 'Borrar un cliente',                  N'DELETE FROM Cliente WHERE Id_Cliente = 10;', 0),
('usr_admin_demo', 'Eliminar una tabla',                 N'DROP TABLE Detalle_Venta;', 0);

DECLARE @resultados TABLE (
    nro INT,
    usuario SYSNAME,
    operacion VARCHAR(60),
    esperado VARCHAR(10),
    obtenido VARCHAR(10),
    ok VARCHAR(2),
    mensaje NVARCHAR(300)
);

DECLARE @nro INT = 1, @total INT = (SELECT COUNT(*) FROM @pruebas);
DECLARE @usuario SYSNAME, @operacion VARCHAR(60), @sentencia NVARCHAR(MAX), @debe BIT;
DECLARE @permitio BIT, @mensaje NVARCHAR(300);

WHILE @nro <= @total
BEGIN
    SELECT @usuario = usuario, @operacion = operacion, @sentencia = sentencia, @debe = debe_permitir
    FROM @pruebas WHERE nro = @nro;

    SET @mensaje = NULL;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXECUTE AS USER = @usuario;
        EXEC sp_executesql @sentencia;
        REVERT;
        SET @permitio = 1;
    END TRY
    BEGIN CATCH
        -- Primero el ROLLBACK: con la transaccion condenada, REVERT falla
        -- y la sesion seguiria actuando como el usuario de prueba.
        SET @mensaje = ERROR_MESSAGE();
        -- Solo cuenta como rechazo un error de permisos (229, 230, 262, 3701).
        SET @permitio = CASE WHEN ERROR_NUMBER() IN (229, 230, 262, 3701) THEN 0 END;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        REVERT;
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    INSERT INTO @resultados VALUES (
        @nro, @usuario, @operacion,
        CASE @debe WHEN 1 THEN 'PERMITE' ELSE 'RECHAZA' END,
        CASE @permitio WHEN 1 THEN 'PERMITE' WHEN 0 THEN 'RECHAZA' ELSE 'ERROR' END,
        CASE WHEN @debe = @permitio THEN 'SI' ELSE 'NO' END,
        @mensaje
    );

    SET @nro += 1;
END;

SELECT nro, usuario, operacion, esperado, obtenido, ok, mensaje
FROM @resultados
ORDER BY nro;

-- ---------------------------------------------------------------------
-- Enmascaramiento: el mismo cliente visto por cada usuario.
-- ---------------------------------------------------------------------
DECLARE @mascara TABLE (usuario SYSNAME, dni VARCHAR(20), email VARCHAR(120), telefono VARCHAR(30), direccion VARCHAR(200));

EXECUTE AS USER = 'usr_mostrador_demo';
INSERT INTO @mascara SELECT USER_NAME(), dni, email, telefono, direccion FROM Cliente WHERE Id_Cliente = 1;
REVERT;

EXECUTE AS USER = 'usr_admin_demo';
INSERT INTO @mascara SELECT USER_NAME(), dni, email, telefono, direccion FROM Cliente WHERE Id_Cliente = 1;
REVERT;

SELECT usuario, dni, email, telefono, direccion FROM @mascara;
GO
