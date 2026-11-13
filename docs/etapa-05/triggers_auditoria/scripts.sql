USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - TRIGGERS DE AUDITORIA
-- Registra en la tabla Auditoria quien modifico precios, liquidaciones
-- y stock, con el valor anterior y el nuevo.
--
-- Contenido:
--   1. Tabla Auditoria
--   2. Trigger sobre Producto        (precio_lista, en_liquidacion, porcentaje_liquidacion)
--   3. Trigger sobre Producto_Talle  (stock)
--   4. Pruebas: exito, sin cambios, varias filas, INSERT/DELETE,
--      stock negativo y violacion de FK
-- =====================================================================

-- =====================================================================
-- 1. TABLA: Auditoria
--    Una fila por cada campo modificado (modelo "largo"): sirve para
--    cualquier tabla y permite agregar triggers sin tocar su estructura.
--    Nadie la modifica a mano: la llenan los triggers.
-- =====================================================================
IF OBJECT_ID(N'dbo.Auditoria', N'U') IS NULL
BEGIN
    CREATE TABLE Auditoria (
        Id_Auditoria   INT IDENTITY(1,1) NOT NULL,
        tabla          VARCHAR(50)  NOT NULL,                -- tabla afectada (ej. Producto)
        operacion      VARCHAR(10)  NOT NULL,                -- INSERT, UPDATE o DELETE
        clave          VARCHAR(100) NOT NULL,                -- PK de la fila afectada (ej. Id_Producto=4)
        campo          VARCHAR(50)  NULL,                    -- columna modificada (NULL en INSERT/DELETE de fila completa)
        valor_anterior VARCHAR(200) NULL,
        valor_nuevo    VARCHAR(200) NULL,
        usuario        SYSNAME      NOT NULL CONSTRAINT DF_Auditoria_usuario DEFAULT (SUSER_SNAME()),
        fecha_hora     DATETIME2(0) NOT NULL CONSTRAINT DF_Auditoria_fecha   DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_Auditoria PRIMARY KEY (Id_Auditoria),
        CONSTRAINT CHK_Auditoria_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
    );
END;
GO

-- =====================================================================
-- 2. TRIGGER: trg_Producto_Auditoria
--    Audita precio de lista y liquidacion de Producto (RN.05 y RN.06).
--    - UPDATE: una fila por cada campo que realmente cambio (si el valor
--      nuevo es igual al anterior, no registra nada).
--    - INSERT / DELETE: una fila por producto con el resumen del registro.
--    Es set-based: funciona igual con una fila o con muchas en un mismo
--    comando, porque trabaja con las tablas inserted y deleted.
-- =====================================================================
CREATE OR ALTER TRIGGER trg_Producto_Auditoria
ON Producto
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: existe en inserted y no en deleted
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_nuevo)
    SELECT 'Producto', 'INSERT', CONCAT('Id_Producto=', i.Id_Producto), NULL,
           CONCAT(i.nombre, ' | precio_lista=', i.precio_lista,
                  ' | en_liquidacion=', i.en_liquidacion,
                  ' | porcentaje_liquidacion=', i.porcentaje_liquidacion)
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.Id_Producto = i.Id_Producto);

    -- DELETE: existe en deleted y no en inserted
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_anterior)
    SELECT 'Producto', 'DELETE', CONCAT('Id_Producto=', d.Id_Producto), NULL,
           CONCAT(d.nombre, ' | precio_lista=', d.precio_lista,
                  ' | en_liquidacion=', d.en_liquidacion,
                  ' | porcentaje_liquidacion=', d.porcentaje_liquidacion)
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i WHERE i.Id_Producto = d.Id_Producto);

    -- UPDATE: existe en ambas; se registra solo lo que cambio
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_anterior, valor_nuevo)
    SELECT 'Producto', 'UPDATE', CONCAT('Id_Producto=', i.Id_Producto), c.campo, c.anterior, c.nuevo
    FROM inserted i
    JOIN deleted d ON d.Id_Producto = i.Id_Producto
    CROSS APPLY (VALUES
        ('precio_lista',           CONVERT(VARCHAR(200), d.precio_lista),           CONVERT(VARCHAR(200), i.precio_lista)),
        ('en_liquidacion',         CONVERT(VARCHAR(200), d.en_liquidacion),         CONVERT(VARCHAR(200), i.en_liquidacion)),
        ('porcentaje_liquidacion', CONVERT(VARCHAR(200), d.porcentaje_liquidacion), CONVERT(VARCHAR(200), i.porcentaje_liquidacion))
    ) AS c (campo, anterior, nuevo)
    WHERE c.anterior <> c.nuevo;
END;
GO

-- =====================================================================
-- 3. TRIGGER: trg_Producto_Talle_Auditoria
--    Audita el stock por talle (RN.02). Misma logica que el trigger de
--    Producto. La PK es compuesta (Id_Producto, Id_Talle), por eso la
--    clave registrada incluye ambas columnas.
--    Se dispara en cada venta que descuente stock: es lo esperado, deja
--    el historial de movimientos de inventario.
-- =====================================================================
CREATE OR ALTER TRIGGER trg_Producto_Talle_Auditoria
ON Producto_Talle
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: existe en inserted y no en deleted
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_nuevo)
    SELECT 'Producto_Talle', 'INSERT',
           CONCAT('Id_Producto=', i.Id_Producto, ', Id_Talle=', i.Id_Talle), 'stock',
           CONVERT(VARCHAR(200), i.stock)
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM deleted d
                      WHERE d.Id_Producto = i.Id_Producto AND d.Id_Talle = i.Id_Talle);

    -- DELETE: existe en deleted y no en inserted
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_anterior)
    SELECT 'Producto_Talle', 'DELETE',
           CONCAT('Id_Producto=', d.Id_Producto, ', Id_Talle=', d.Id_Talle), 'stock',
           CONVERT(VARCHAR(200), d.stock)
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i
                      WHERE i.Id_Producto = d.Id_Producto AND i.Id_Talle = d.Id_Talle);

    -- UPDATE: existe en ambas; se registra solo si el stock cambio
    INSERT INTO Auditoria (tabla, operacion, clave, campo, valor_anterior, valor_nuevo)
    SELECT 'Producto_Talle', 'UPDATE',
           CONCAT('Id_Producto=', i.Id_Producto, ', Id_Talle=', i.Id_Talle), 'stock',
           CONVERT(VARCHAR(200), d.stock), CONVERT(VARCHAR(200), i.stock)
    FROM inserted i
    JOIN deleted d ON d.Id_Producto = i.Id_Producto AND d.Id_Talle = i.Id_Talle
    WHERE i.stock <> d.stock;
END;
GO

-- =====================================================================
-- 4. PRUEBAS
--    Cada prueba corre dentro de una transaccion que se deshace al final
--    (ROLLBACK), asi la base de datos queda como estaba y las pruebas se
--    pueden repetir. Cada una muestra solo las filas de Auditoria que
--    genero (Id_Auditoria > @ultimo).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Prueba 1 (exito): cambio de precio de lista.
-- Esperado: 1 fila UPDATE, Id_Producto=1, precio_lista 45000.00 -> 46000.00
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    UPDATE Producto SET precio_lista = 46000 WHERE Id_Producto = 1;
    SELECT 'P1' AS prueba, operacion, clave, campo, valor_anterior, valor_nuevo, usuario, fecha_hora
    FROM Auditoria WHERE Id_Auditoria > @ultimo ORDER BY Id_Auditoria;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 2 (caso limite): UPDATE que no cambia ningun valor.
-- Esperado: 0 filas (el trigger no registra cambios inexistentes).
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    UPDATE Producto SET precio_lista = precio_lista WHERE Id_Producto = 2;
    SELECT 'P2' AS prueba, COUNT(*) AS filas_auditadas
    FROM Auditoria WHERE Id_Auditoria > @ultimo;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 3 (caso limite): un solo UPDATE sobre varias filas y varios campos.
-- Esperado: 4 filas. Productos 1 y 6: en_liquidacion 0 -> 1 y
-- porcentaje_liquidacion 0.00 -> 10.00 (una fila por producto y por campo).
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    UPDATE Producto SET en_liquidacion = 1, porcentaje_liquidacion = 10
    WHERE Id_Producto IN (1, 6);
    SELECT 'P3' AS prueba, operacion, clave, campo, valor_anterior, valor_nuevo
    FROM Auditoria WHERE Id_Auditoria > @ultimo ORDER BY clave, campo;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 4 (exito): descuento de stock de un talle.
-- Esperado: 1 fila UPDATE, Id_Producto=1, Id_Talle=2, stock 15 -> 14
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    UPDATE Producto_Talle SET stock = stock - 1 WHERE Id_Producto = 1 AND Id_Talle = 2;
    SELECT 'P4' AS prueba, operacion, clave, campo, valor_anterior, valor_nuevo
    FROM Auditoria WHERE Id_Auditoria > @ultimo ORDER BY Id_Auditoria;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 5 (caso limite): reposicion de stock en todos los talles de un producto.
-- Esperado: 4 filas (producto 6, talles 6, 7, 8 y 9), todas con +5.
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    UPDATE Producto_Talle SET stock = stock + 5 WHERE Id_Producto = 6;
    SELECT 'P5' AS prueba, operacion, clave, campo, valor_anterior, valor_nuevo
    FROM Auditoria WHERE Id_Auditoria > @ultimo ORDER BY clave;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 6 (exito): alta y baja de un producto.
-- Esperado: 2 filas, una INSERT (valor_nuevo con el resumen) y una DELETE
-- (valor_anterior con el resumen).
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    INSERT INTO Producto (nombre, precio_lista, Id_Categoria) VALUES ('Producto de prueba', 100, 8);
    DELETE FROM Producto WHERE nombre = 'Producto de prueba';
    SELECT 'P6' AS prueba, operacion, clave, valor_anterior, valor_nuevo
    FROM Auditoria WHERE Id_Auditoria > @ultimo ORDER BY Id_Auditoria;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 7 (error): stock negativo.
-- Esperado: el CHECK de Producto_Talle rechaza el UPDATE y no queda
-- ningun registro en Auditoria (0 filas).
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    BEGIN TRY
        UPDATE Producto_Talle SET stock = -1 WHERE Id_Producto = 1 AND Id_Talle = 2;
    END TRY
    BEGIN CATCH
        SELECT 'P7' AS prueba, ERROR_MESSAGE() AS error_recibido;
    END CATCH;
    SELECT 'P7' AS prueba, COUNT(*) AS filas_auditadas
    FROM Auditoria WHERE Id_Auditoria > @ultimo;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 8 (error): borrar un producto que tiene stock y ventas asociadas.
-- Esperado: la clave foranea lo rechaza y no queda registro en Auditoria.
-- ---------------------------------------------------------------------
DECLARE @ultimo INT = ISNULL((SELECT MAX(Id_Auditoria) FROM Auditoria), 0);
BEGIN TRAN;
    BEGIN TRY
        DELETE FROM Producto WHERE Id_Producto = 1;
    END TRY
    BEGIN CATCH
        SELECT 'P8' AS prueba, ERROR_MESSAGE() AS error_recibido;
    END CATCH;
    SELECT 'P8' AS prueba, COUNT(*) AS filas_auditadas
    FROM Auditoria WHERE Id_Auditoria > @ultimo;
ROLLBACK;
GO

-- ---------------------------------------------------------------------
-- Prueba 9 (verificacion): despues de las pruebas la auditoria no
-- conserva registros, porque cada una se deshizo con ROLLBACK.
-- ---------------------------------------------------------------------
SELECT 'P9' AS prueba, COUNT(*) AS filas_en_auditoria FROM Auditoria;
GO
