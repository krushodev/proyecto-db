-- =====================================================================
-- ETAPA V - 2. MANEJO DE TRANSACCIONES: AISLAMIENTO (dos sesiones)
-- Dos ventas simultaneas compiten por la ULTIMA unidad de un talle.
-- Demuestra la propiedad I (aislamiento) de ACID: la segunda sesion
-- espera a que la primera termine y despues ve el stock ya descontado,
-- asi que el stock nunca queda negativo ni se vende dos veces la misma
-- unidad.
--
-- Como ejecutarlo: abrir DOS ventanas de consulta en SSMS.
--   1. Ventana 1: ejecutar la seccion 0 (preparar).
--   2. Ventana 1: ejecutar la seccion A (retiene la transaccion 10 s).
--   3. Ventana 2: dentro de esos 10 s, ejecutar la seccion B.
--   4. Cuando termine, ejecutar la seccion C (restablecer).
-- Se usa READ COMMITTED, el nivel de aislamiento por defecto de SQL Server.
-- =====================================================================

-- ==== 0. PREPARAR ====================================================
-- El producto 8, talle 2 queda con una sola unidad.
USE tienda_ropa;
GO
UPDATE Producto_Talle SET stock = 1 WHERE Id_Producto = 8 AND Id_Talle = 2;
SELECT 'preparado' AS paso, stock FROM Producto_Talle WHERE Id_Producto = 8 AND Id_Talle = 2;
GO

-- ==== A. SESION A: vende la ultima unidad y tarda en confirmar =========
USE tienda_ropa;
GO
SET XACT_ABORT ON;
DECLARE @inicio DATETIME2(3) = SYSDATETIME(), @filas INT;
BEGIN TRANSACTION;
    UPDATE Producto_Talle SET stock = stock - 1
    WHERE Id_Producto = 8 AND Id_Talle = 2 AND stock >= 1;
    SET @filas = @@ROWCOUNT;
    WAITFOR DELAY '00:00:10';          -- la transaccion sigue abierta y retiene el bloqueo
COMMIT TRANSACTION;
SELECT 'SESION A' AS sesion, @filas AS filas_actualizadas,
       CASE WHEN @filas = 1 THEN 'VENDIO la ultima unidad' ELSE 'SIN STOCK' END AS resultado,
       DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()) AS ms_totales;
GO

-- ==== B. SESION B: intenta vender la misma unidad ======================
USE tienda_ropa;
GO
SET XACT_ABORT ON;
DECLARE @inicio DATETIME2(3) = SYSDATETIME(), @filas INT;
BEGIN TRANSACTION;
    UPDATE Producto_Talle SET stock = stock - 1      -- se bloquea hasta que A confirme
    WHERE Id_Producto = 8 AND Id_Talle = 2 AND stock >= 1;
    SET @filas = @@ROWCOUNT;
COMMIT TRANSACTION;
SELECT 'SESION B' AS sesion, @filas AS filas_actualizadas,
       CASE WHEN @filas = 1 THEN 'VENDIO la ultima unidad' ELSE 'SIN STOCK: la venta se rechaza' END AS resultado,
       DATEDIFF(MILLISECOND, @inicio, SYSDATETIME()) AS ms_esperando;
GO

-- ==== C. RESTABLECER ================================================
USE tienda_ropa;
GO
UPDATE Producto_Talle SET stock = 10 WHERE Id_Producto = 8 AND Id_Talle = 2;
SELECT 'restablecido' AS paso, stock FROM Producto_Talle WHERE Id_Producto = 8 AND Id_Talle = 2;
GO
