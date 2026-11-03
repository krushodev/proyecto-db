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
