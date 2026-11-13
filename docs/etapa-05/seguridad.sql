USE tienda_ropa;
GO

-- =====================================================================
-- ETAPA V - 4. SEGURIDAD
-- Roles, permisos minimos, proteccion del historial de ventas y
-- enmascaramiento de datos personales.
--
-- Los roles salen de los actores de la etapa IV (casos-uso.md):
--   rol_mostrador     -> Personal de mostrador
--   rol_administrador -> Administrador del negocio (hereda de mostrador)
--
-- Se puede volver a ejecutar sobre una base ya configurada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.a Roles
--     El administrador es miembro de rol_mostrador: asi se implementa la
--     generalizacion de casos-uso.md (hace todo lo que hace el mostrador).
-- ---------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('rol_mostrador') IS NULL
    CREATE ROLE rol_mostrador;
IF DATABASE_PRINCIPAL_ID('rol_administrador') IS NULL
    CREATE ROLE rol_administrador;
GO

ALTER ROLE rol_mostrador ADD MEMBER rol_administrador;
GO

-- ---------------------------------------------------------------------
-- 4.b Permisos de rol_mostrador
--     Consulta el catalogo, registra clientes y ventas, y descuenta stock.
--     No puede cambiar precios ni borrar datos.
-- ---------------------------------------------------------------------
GRANT SELECT ON Categoria      TO rol_mostrador;
GRANT SELECT ON Talle          TO rol_mostrador;
GRANT SELECT ON Metodo_pago    TO rol_mostrador;
GRANT SELECT ON Producto       TO rol_mostrador;
GRANT SELECT ON Producto_Talle TO rol_mostrador;
GRANT SELECT ON Cliente        TO rol_mostrador;
GRANT SELECT ON Venta          TO rol_mostrador;
GRANT SELECT ON Detalle_Venta  TO rol_mostrador;

-- RN.04: el cliente que compra por primera vez se registra en ese momento.
-- El DNI queda fuera del UPDATE: identifica al cliente y no se corrige en mostrador.
GRANT INSERT ON Cliente TO rol_mostrador;
GRANT UPDATE ON Cliente (nombre, apellido, telefono, email, direccion) TO rol_mostrador;

GRANT INSERT ON Venta         TO rol_mostrador;
GRANT INSERT ON Detalle_Venta TO rol_mostrador;

-- RN.02: solo la columna stock. El mostrador no puede tocar precios.
GRANT UPDATE ON Producto_Talle (stock) TO rol_mostrador;
GO

-- ---------------------------------------------------------------------
-- 4.c Permisos de rol_administrador
--     Suma la gestion del catalogo, los precios y las liquidaciones.
--     Lo demas lo hereda de rol_mostrador.
-- ---------------------------------------------------------------------
GRANT INSERT, UPDATE, DELETE ON Categoria      TO rol_administrador;
GRANT INSERT, UPDATE, DELETE ON Talle          TO rol_administrador;
GRANT INSERT, UPDATE, DELETE ON Metodo_pago    TO rol_administrador;
GRANT INSERT, UPDATE, DELETE ON Producto       TO rol_administrador;
GRANT INSERT, UPDATE, DELETE ON Producto_Talle TO rol_administrador;
GO

-- ---------------------------------------------------------------------
-- 4.d Proteccion del historial de ventas (RN.08)
--     DENY le gana a cualquier GRANT y lo hereda rol_administrador, asi
--     que una venta registrada no se puede modificar ni borrar.
-- ---------------------------------------------------------------------
DENY UPDATE, DELETE ON Venta         TO rol_mostrador;
DENY UPDATE, DELETE ON Detalle_Venta TO rol_mostrador;
GO

-- ---------------------------------------------------------------------
-- 4.e Enmascaramiento de datos personales (Dynamic Data Masking)
--     El mostrador ve el contacto del cliente enmascarado. El DNI queda
--     visible porque el comprobante de venta lo muestra (CU-01).
-- ---------------------------------------------------------------------
ALTER TABLE Cliente ALTER COLUMN email     ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE Cliente ALTER COLUMN telefono  ADD MASKED WITH (FUNCTION = 'partial(0,"XXXX-",4)');
ALTER TABLE Cliente ALTER COLUMN direccion ADD MASKED WITH (FUNCTION = 'default()');
GO

GRANT UNMASK TO rol_administrador;
GO

-- ---------------------------------------------------------------------
-- 4.h Permiso de ejecucion sobre los procedimientos de venta y stock
--     Etapa V, tema "procedimientos y funciones". Se otorga solo si los
--     objetos ya existen (procedimientos_funciones/scripts.sql), asi este
--     script se puede correr antes o despues. Si se ejecuta primero,
--     volver a correr esta seccion cuando los procedimientos esten creados.
--     rol_administrador hereda estos permisos de rol_mostrador.
-- ---------------------------------------------------------------------
IF OBJECT_ID(N'dbo.sp_RegistrarVentaCompleta', N'P') IS NOT NULL
    EXEC (N'GRANT EXECUTE ON dbo.sp_RegistrarVentaCompleta TO rol_mostrador;');
IF OBJECT_ID(N'dbo.sp_ActualizarStock', N'P') IS NOT NULL
    EXEC (N'GRANT EXECUTE ON dbo.sp_ActualizarStock TO rol_mostrador;');
-- El procedimiento de venta recibe una tabla como parametro: para poder
-- pasarla hay que tener permiso de uso sobre el tipo de tabla.
IF TYPE_ID(N'dbo.tt_DetalleVenta') IS NOT NULL
    EXEC (N'GRANT EXECUTE ON TYPE::dbo.tt_DetalleVenta TO rol_mostrador;');
GO

-- ---------------------------------------------------------------------
-- 4.f Usuarios de prueba, sin login
--     No tienen contrasena ni pueden conectarse: solo sirven para probar
--     los permisos con EXECUTE AS (ver seguridad_pruebas.sql).
-- ---------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID('usr_mostrador_demo') IS NULL
    CREATE USER usr_mostrador_demo WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('usr_admin_demo') IS NULL
    CREATE USER usr_admin_demo WITHOUT LOGIN;
GO

ALTER ROLE rol_mostrador     ADD MEMBER usr_mostrador_demo;
ALTER ROLE rol_administrador ADD MEMBER usr_admin_demo;
GO

-- ---------------------------------------------------------------------
-- 4.g Usuario real (plantilla, no se ejecuta)
--     Requiere autenticacion mixta en el servidor. Reemplazar la
--     contrasena y no guardarla nunca en el repositorio.
-- ---------------------------------------------------------------------
-- USE master;
-- CREATE LOGIN login_mostrador WITH PASSWORD = '<contrasena>', CHECK_POLICY = ON;
-- GO
-- USE tienda_ropa;
-- CREATE USER usuario_mostrador FOR LOGIN login_mostrador;
-- ALTER ROLE rol_mostrador ADD MEMBER usuario_mostrador;
-- GO
