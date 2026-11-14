USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - 4. SEGURIDAD: DEMOSTRACION DE LA GUIA
-- Reproduce el caso de la guia de la etapa V adaptado a tienda_ropa:
--   Parte 1 - permisos dados directamente a usuarios con login
--   Parte 2 - permisos dados a traves de un rol
--   y la diferencia entre un INSERT directo y el mismo alta hecha
--   con un procedimiento almacenado.
--
-- Usuarios NUEVOS: no modifica rol_mostrador ni rol_administrador, asi
-- las pruebas de seguridad_pruebas.sql siguen dando el mismo resultado.
--
-- Requisitos:
--   1. seguridad.sql (crea rol_administrador).
--   2. ../procedimientos_funciones/scripts.sql (crea
--      sp_RegistrarVentaCompleta y el tipo tt_DetalleVenta).
--   3. Permiso ALTER ANY LOGIN en el servidor (para CREATE LOGIN).
--      Para conectarse con estos logins hace falta autenticacion mixta;
--      las pruebas de abajo usan EXECUTE AS USER y no la necesitan.
--
-- Se puede volver a ejecutar. Resultado esperado: 5 filas con ok = 'SI'.
-- =====================================================================

IF OBJECT_ID(N'dbo.sp_RegistrarVentaCompleta', N'P') IS NULL
   OR TYPE_ID(N'dbo.tt_DetalleVenta') IS NULL
    THROW 50100, 'Falta ejecutar procedimientos_funciones/scripts.sql', 1;
IF DATABASE_PRINCIPAL_ID('rol_administrador') IS NULL
    THROW 50101, 'Falta ejecutar seguridad.sql', 1;
GO

-- ---------------------------------------------------------------------
-- G.1 Inicios de sesion y usuarios
--     Contrasenas DE EJEMPLO: quedan en el repositorio, no usar en
--     un servidor real.
-- ---------------------------------------------------------------------
IF SUSER_ID('usuario_admin') IS NULL
    CREATE LOGIN usuario_admin   WITH PASSWORD = 'Ejemplo_Admin#2026';
IF SUSER_ID('usuario_lector') IS NULL
    CREATE LOGIN usuario_lector  WITH PASSWORD = 'Ejemplo_Lector#2026';
IF SUSER_ID('usuario_con_rol') IS NULL
    CREATE LOGIN usuario_con_rol WITH PASSWORD = 'Ejemplo_ConRol#2026';
IF SUSER_ID('usuario_sin_rol') IS NULL
    CREATE LOGIN usuario_sin_rol WITH PASSWORD = 'Ejemplo_SinRol#2026';
GO

IF DATABASE_PRINCIPAL_ID('usuario_admin') IS NULL
    CREATE USER usuario_admin   FOR LOGIN usuario_admin;
IF DATABASE_PRINCIPAL_ID('usuario_lector') IS NULL
    CREATE USER usuario_lector  FOR LOGIN usuario_lector;
IF DATABASE_PRINCIPAL_ID('usuario_con_rol') IS NULL
    CREATE USER usuario_con_rol FOR LOGIN usuario_con_rol;
IF DATABASE_PRINCIPAL_ID('usuario_sin_rol') IS NULL
    CREATE USER usuario_sin_rol FOR LOGIN usuario_sin_rol;
GO

-- ---------------------------------------------------------------------
-- G.2 Parte 1 - Permisos a nivel de usuarios
-- ---------------------------------------------------------------------

-- Administrador. La guia lo agrega a db_owner; aca se usa
-- rol_administrador, que es mas restrictivo (no modifica la estructura
-- ni el historial de ventas). Ver seguridad.md, seccion 10.
ALTER ROLE rol_administrador ADD MEMBER usuario_admin;
GO

-- Lector: permiso dado DIRECTAMENTE al usuario, sin rol.
-- Solo lectura sobre Venta; no tiene INSERT sobre ninguna tabla.
GRANT SELECT ON dbo.Venta TO usuario_lector;

-- ...pero puede registrar una venta a traves del procedimiento.
-- El procedimiento recibe una tabla, por eso tambien necesita permiso
-- sobre el tipo tt_DetalleVenta (igual que rol_mostrador, seccion 4.h).
GRANT EXECUTE ON dbo.sp_RegistrarVentaCompleta TO usuario_lector;
GRANT EXECUTE ON TYPE::dbo.tt_DetalleVenta     TO usuario_lector;
GO

-- ---------------------------------------------------------------------
-- G.3 Parte 2 - Permisos a nivel de roles
--     usuario_con_rol entra al rol; usuario_sin_rol queda afuera y no
--     recibe ningun permiso.
-- ---------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('rol_consulta_productos') IS NULL
    CREATE ROLE rol_consulta_productos;
GO

GRANT SELECT ON dbo.Producto TO rol_consulta_productos;
ALTER ROLE rol_consulta_productos ADD MEMBER usuario_con_rol;
GO

-- ---------------------------------------------------------------------
-- G.4 Demostracion: tabla de pruebas de la guia
--     Cada operacion se ejecuta como el usuario indicado y se revierte.
--     Un rechazo solo cuenta si el error es de permisos.
-- ---------------------------------------------------------------------
SET NOCOUNT ON;

DECLARE @pruebas TABLE (
    nro INT IDENTITY(1,1),
    prueba VARCHAR(60),
    usuario SYSNAME,
    sentencia NVARCHAR(MAX),
    debe_permitir BIT
);

DECLARE @select_producto NVARCHAR(MAX) = N'
    DECLARE @n INT;
    SELECT @n = COUNT(*) FROM dbo.Producto;';

DECLARE @insert_venta NVARCHAR(MAX) = N'
    INSERT INTO dbo.Venta (canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago)
    VALUES (''Local'', 0, 15000, 1, 4);';

-- Misma venta, pero con el procedimiento: 1 unidad del producto 6, talle 7.
DECLARE @exec_procedimiento NVARCHAR(MAX) = N'
    DECLARE @detalle dbo.tt_DetalleVenta;
    INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (6, 7, 1);
    DECLARE @id_venta INT;
    EXEC dbo.sp_RegistrarVentaCompleta
        @Id_Cliente     = 1,
        @Id_metodo_pago = 4,
        @canal          = ''Local'',
        @Detalle        = @detalle,
        @Id_Venta       = @id_venta OUTPUT;
    IF @id_venta IS NULL
        THROW 50102, ''El procedimiento no registro la venta'', 1;';

INSERT INTO @pruebas (prueba, usuario, sentencia, debe_permitir) VALUES
('SELECT sobre Producto',      'usuario_con_rol', @select_producto,    1),
('SELECT sobre Producto',      'usuario_sin_rol', @select_producto,    0),
('INSERT directo sobre Venta', 'usuario_admin',   @insert_venta,       1),
('INSERT directo sobre Venta', 'usuario_lector',  @insert_venta,       0),
('EXEC del procedimiento',     'usuario_lector',  @exec_procedimiento, 1);

DECLARE @resultados TABLE (
    nro INT,
    prueba VARCHAR(60),
    usuario SYSNAME,
    esperado VARCHAR(20),
    obtenido VARCHAR(20),
    ok VARCHAR(2),
    mensaje NVARCHAR(300)
);

DECLARE @nro INT = 1, @total INT = (SELECT COUNT(*) FROM @pruebas);
DECLARE @prueba VARCHAR(60), @usuario SYSNAME, @sentencia NVARCHAR(MAX), @debe BIT;
DECLARE @permitio BIT, @mensaje NVARCHAR(300);

WHILE @nro <= @total
BEGIN
    SELECT @prueba = prueba, @usuario = usuario, @sentencia = sentencia, @debe = debe_permitir
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
        SET @mensaje = ERROR_MESSAGE();
        SET @permitio = CASE WHEN ERROR_NUMBER() IN (229, 230, 262, 3701) THEN 0 END;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        REVERT;
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    INSERT INTO @resultados VALUES (
        @nro, @prueba, @usuario,
        CASE @debe WHEN 1 THEN 'Correcto' ELSE 'Acceso denegado' END,
        CASE @permitio WHEN 1 THEN 'Correcto' WHEN 0 THEN 'Acceso denegado' ELSE 'ERROR' END,
        CASE WHEN @debe = @permitio THEN 'SI' ELSE 'NO' END,
        @mensaje
    );

    SET @nro += 1;
END;

SELECT nro, prueba, usuario, esperado, obtenido, ok, mensaje
FROM @resultados
ORDER BY nro;
GO
