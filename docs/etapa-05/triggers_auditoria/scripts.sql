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
