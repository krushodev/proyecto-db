# Pruebas y validación – Intensa Jeans

Este documento reúne las pruebas diseñadas para validar la base de datos `tienda_ropa`, una vez ejecutados en orden `ecommerce.sql` (DDL) y `tienda_ropa_dml.sql` (DML).

> **Estado:** las consultas están listas para ejecutarse. La columna **Resultado obtenido** debe completarse tras correrlas en SQL Server Management Studio.

---

## 1. Verificación de la carga de datos

**Objetivo:** confirmar que el DML cargó la cantidad esperada de registros en cada tabla.

```sql
USE tienda_ropa;
GO

SELECT 'Categoria'      AS tabla, COUNT(*) AS registros FROM Categoria      UNION ALL
SELECT 'Talle',                   COUNT(*)               FROM Talle          UNION ALL
SELECT 'Metodo_pago',             COUNT(*)               FROM Metodo_pago    UNION ALL
SELECT 'Cliente',                 COUNT(*)               FROM Cliente        UNION ALL
SELECT 'Producto',                COUNT(*)               FROM Producto       UNION ALL
SELECT 'Producto_Talle',          COUNT(*)               FROM Producto_Talle UNION ALL
SELECT 'Venta',                   COUNT(*)               FROM Venta          UNION ALL
SELECT 'Detalle_Venta',           COUNT(*)               FROM Detalle_Venta;
```

| Tabla | Esperado | Resultado obtenido |
| :--- | :---: | :--- |
| `Categoria` | 8 | |
| `Talle` | 10 | |
| `Metodo_pago` | 8 | |
| `Cliente` | 10 | |
| `Producto` | 10 | |
| `Producto_Talle` | 24 | |
| `Venta` | 10 | |
| `Detalle_Venta` | 17 | |

---

## 2. Integridad referencial

**Objetivo:** comprobar que no existen registros huérfanos. Todas las consultas deben devolver **0**.

```sql
-- Productos sin categoría
SELECT COUNT(*) AS huerfanos FROM Producto p
LEFT JOIN Categoria c ON c.Id_Categoria = p.Id_Categoria
WHERE c.Id_Categoria IS NULL;

-- Ventas sin cliente o sin método de pago
SELECT COUNT(*) AS huerfanos FROM Venta v
LEFT JOIN Cliente c     ON c.Id_Cliente = v.Id_Cliente
LEFT JOIN Metodo_pago m ON m.Id_metodo_pago = v.Id_metodo_pago
WHERE c.Id_Cliente IS NULL OR m.Id_metodo_pago IS NULL;

-- Renglones sin venta
SELECT COUNT(*) AS huerfanos FROM Detalle_Venta d
LEFT JOIN Venta v ON v.Id_Venta = d.Id_Venta
WHERE v.Id_Venta IS NULL;

-- Renglones cuya combinación producto-talle no existe
SELECT COUNT(*) AS huerfanos FROM Detalle_Venta d
LEFT JOIN Producto_Talle pt
       ON pt.Id_Producto = d.Id_Producto AND pt.Id_Talle = d.Id_Talle
WHERE pt.Id_Producto IS NULL;
```

| Verificación | Esperado | Resultado obtenido |
| :--- | :---: | :--- |
| Productos sin categoría | 0 | |
| Ventas sin cliente o método de pago | 0 | |
| Renglones sin venta | 0 | |
| Renglones con producto-talle inexistente | 0 | |

---

## 3. Consistencia de los datos cargados

**Objetivo:** verificar que los importes calculados sean coherentes. Todas las consultas deben devolver **0 filas**.

```sql
-- 3.1 subtotal = cantidad * precio_unitario
SELECT Id_Venta, nro_item
FROM Detalle_Venta
WHERE subtotal <> cantidad * precio_unitario;

-- 3.2 precio_unitario = precio de lista con la liquidación aplicada
SELECT d.Id_Venta, d.nro_item, d.precio_unitario, p.precio_lista
FROM Detalle_Venta d
JOIN Producto p ON p.Id_Producto = d.Id_Producto
WHERE d.precio_unitario <>
      CAST(p.precio_lista * (1 - CASE WHEN p.en_liquidacion = 1
                                      THEN p.porcentaje_liquidacion ELSE 0 END / 100.0)
           AS DECIMAL(10,2));

-- 3.3 descuento_aplicado y total coherentes con los renglones y el método de pago
SELECT v.Id_Venta, v.descuento_aplicado, v.total
FROM Venta v
JOIN (SELECT Id_Venta, SUM(subtotal) AS suma
      FROM Detalle_Venta GROUP BY Id_Venta) d ON d.Id_Venta = v.Id_Venta
JOIN Metodo_pago m ON m.Id_metodo_pago = v.Id_metodo_pago
WHERE v.descuento_aplicado <> ROUND(d.suma * m.porcentaje_descuento / 100, 2)
   OR v.total <> d.suma - v.descuento_aplicado;

-- 3.4 ventas sin ningún renglón
SELECT v.Id_Venta
FROM Venta v
LEFT JOIN Detalle_Venta d ON d.Id_Venta = v.Id_Venta
WHERE d.Id_Venta IS NULL;

-- 3.5 productos en liquidación sin porcentaje, o con porcentaje sin estar en liquidación
SELECT Id_Producto, en_liquidacion, porcentaje_liquidacion
FROM Producto
WHERE (en_liquidacion = 1 AND porcentaje_liquidacion = 0)
   OR (en_liquidacion = 0 AND porcentaje_liquidacion > 0);
```

| Verificación | Esperado | Resultado obtenido |
| :--- | :---: | :--- |
| 3.1 Subtotales incorrectos | 0 filas | |
| 3.2 Precios sin liquidación aplicada | 0 filas | |
| 3.3 Descuentos o totales incorrectos | 0 filas | |
| 3.4 Ventas sin renglones | 0 filas | |
| 3.5 Liquidaciones inconsistentes | 0 filas | |

---

## 4. Pruebas negativas (datos inválidos)

**Objetivo:** comprobar que la base rechaza datos que violan las reglas del modelo. Cada prueba **debe fallar**; el bloque `TRY...CATCH` muestra el error recibido. Las pruebas se ejecutan dentro de una transacción que se revierte, para no alterar los datos.

```sql
-- Plantilla de cada prueba
BEGIN TRANSACTION;
BEGIN TRY
    -- sentencia a probar
    PRINT 'ERROR: la sentencia se ejecutó y debía ser rechazada';
END TRY
BEGIN CATCH
    PRINT 'OK - rechazada: ' + ERROR_MESSAGE();
END CATCH;
ROLLBACK TRANSACTION;
```

| Nº | Prueba | Sentencia a ejecutar | Resultado esperado | Resultado obtenido |
| :-: | :--- | :--- | :--- | :--- |
| 1 | DNI duplicado | `INSERT INTO Cliente (nombre, apellido, dni, email) VALUES ('Test','Uno','38456123','test1@mail.com');` | Rechazada: viola la unicidad del DNI | |
| 2 | Email duplicado | `INSERT INTO Cliente (nombre, apellido, dni, email) VALUES ('Test','Dos','99999999','lucia.fernandez@mail.com');` | Rechazada: viola la unicidad del email | |
| 3 | Cliente sin email | `INSERT INTO Cliente (nombre, apellido, dni) VALUES ('Test','Tres','88888888');` | Rechazada: el email es obligatorio | |
| 4 | Stock negativo | `UPDATE Producto_Talle SET stock = -1 WHERE Id_Producto = 1 AND Id_Talle = 1;` | Rechazada: el stock no puede ser negativo | |
| 5 | Descuento de pago mayor a 100 | `INSERT INTO Metodo_pago (nombre, porcentaje_descuento) VALUES ('Test', 150);` | Rechazada: el porcentaje debe estar entre 0 y 100 | |
| 6 | Liquidación mayor a 100 | `UPDATE Producto SET porcentaje_liquidacion = 120 WHERE Id_Producto = 1;` | Rechazada: el porcentaje debe estar entre 0 y 100 | |
| 7 | Precio de lista negativo | `UPDATE Producto SET precio_lista = -10 WHERE Id_Producto = 1;` | Rechazada: el precio no puede ser negativo | |
| 8 | Cantidad cero en un renglón | `INSERT INTO Detalle_Venta VALUES (1, 99, 1, 1, 0, 45000, 0);` | Rechazada: la cantidad debe ser mayor a 0 | |
| 9 | Producto-talle inexistente | `INSERT INTO Detalle_Venta VALUES (1, 99, 1, 9, 1, 45000, 45000);` | Rechazada: la combinación producto-talle no existe | |
| 10 | Venta con cliente inexistente | `INSERT INTO Venta (canal, Id_Cliente, Id_metodo_pago) VALUES ('Web', 999, 1);` | Rechazada: el cliente no existe | |
| 11 | Producto con categoría inexistente | `INSERT INTO Producto (nombre, precio_lista, Id_Categoria) VALUES ('Test', 1000, 999);` | Rechazada: la categoría no existe | |
| 12 | Borrar categoría con productos | `DELETE FROM Categoria WHERE Id_Categoria = 1;` | Rechazada: tiene productos asociados | |
| 13 | Borrar cliente con ventas | `DELETE FROM Cliente WHERE Id_Cliente = 1;` | Rechazada: tiene ventas asociadas | |
| 14 | Repetir `nro_item` en una venta | `INSERT INTO Detalle_Venta VALUES (1, 1, 6, 6, 1, 15000, 15000);` | Rechazada: la clave (venta, ítem) ya existe | |

---

## 5. Pruebas de comportamiento

### 5.1. Valores por defecto

**Objetivo:** verificar que los valores por defecto se asignen correctamente.

```sql
BEGIN TRANSACTION;
    INSERT INTO Venta (canal, Id_Cliente, Id_metodo_pago) VALUES ('Web', 1, 1);
    SELECT TOP 1 fecha_hora, descuento_aplicado, total
    FROM Venta ORDER BY Id_Venta DESC;
ROLLBACK TRANSACTION;
```

| Resultado esperado | Resultado obtenido |
| :--- | :--- |
| `fecha_hora` con la fecha y hora actuales; `descuento_aplicado` y `total` en `0.00` | |

### 5.2. Borrado en cascada de una venta

**Objetivo:** verificar que al eliminar una venta se eliminen sus renglones.

```sql
BEGIN TRANSACTION;
    DELETE FROM Venta WHERE Id_Venta = 1;
    SELECT COUNT(*) AS renglones_restantes FROM Detalle_Venta WHERE Id_Venta = 1;
ROLLBACK TRANSACTION;
```

| Resultado esperado | Resultado obtenido |
| :--- | :--- |
| `renglones_restantes = 0` (la venta 1 tenía 2 renglones) | |

---

## 6. Consultas de negocio

**Objetivo:** comprobar que el modelo permite responder las consultas habituales del negocio.

```sql
-- 6.1 Ventas totales por canal
SELECT canal, COUNT(*) AS cantidad_ventas, SUM(total) AS monto_total
FROM Venta
GROUP BY canal
ORDER BY monto_total DESC;

-- 6.2 Stock total por producto
SELECT p.nombre, SUM(pt.stock) AS stock_total
FROM Producto p
JOIN Producto_Talle pt ON pt.Id_Producto = p.Id_Producto
GROUP BY p.nombre
ORDER BY stock_total DESC;

-- 6.3 Detalle completo de una venta
SELECT v.Id_Venta, v.fecha_hora, c.apellido, p.nombre AS producto,
       t.descripcion AS talle, d.cantidad, d.precio_unitario, d.subtotal
FROM Venta v
JOIN Cliente c        ON c.Id_Cliente = v.Id_Cliente
JOIN Detalle_Venta d  ON d.Id_Venta = v.Id_Venta
JOIN Producto p       ON p.Id_Producto = d.Id_Producto
JOIN Talle t          ON t.Id_Talle = d.Id_Talle
WHERE v.Id_Venta = 5;

-- 6.4 Productos en liquidación con su precio final
SELECT nombre, precio_lista, porcentaje_liquidacion,
       CAST(precio_lista * (1 - porcentaje_liquidacion / 100.0) AS DECIMAL(10,2)) AS precio_final
FROM Producto
WHERE en_liquidacion = 1;

-- 6.5 Productos más vendidos (unidades)
SELECT p.nombre, SUM(d.cantidad) AS unidades
FROM Detalle_Venta d
JOIN Producto p ON p.Id_Producto = d.Id_Producto
GROUP BY p.nombre
ORDER BY unidades DESC;

-- 6.6 Clientes con más de una compra
SELECT c.apellido, c.nombre, COUNT(*) AS compras
FROM Cliente c
JOIN Venta v ON v.Id_Cliente = c.Id_Cliente
GROUP BY c.apellido, c.nombre
HAVING COUNT(*) > 1;

-- 6.7 Ventas por método de pago
SELECT m.nombre, COUNT(*) AS ventas, SUM(v.descuento_aplicado) AS descuento_total
FROM Venta v
JOIN Metodo_pago m ON m.Id_metodo_pago = v.Id_metodo_pago
GROUP BY m.nombre;
```

| Consulta | Resultado esperado | Resultado obtenido |
| :--- | :--- | :--- |
| 6.1 | Una fila por canal: `Local`, `Web`, `Instagram` y `WhatsApp` | |
| 6.2 | Una fila por producto (10 filas) | |
| 6.3 | 3 renglones para la venta 5 | |
| 6.4 | 4 productos en liquidación | |
| 6.5 | `Remera Básica Algodón` encabeza la lista | |
| 6.6 | 1 cliente con más de una compra (Fernández, Lucía) | |
| 6.7 | Una fila por método de pago utilizado en las ventas | |

---

## 7. Hallazgos durante la validación

Observaciones sobre la consistencia entre scripts y documentación:

- El comentario del DML indica 28 registros en `Producto_Talle`, pero el `INSERT` carga **24**.
- Los canales de venta de los datos de prueba (`Local`, `Web`, `Instagram`, `WhatsApp`) no coinciden con los valores del modelo relacional de la etapa 2 (`Mostrador` / `Online`).
- La carga de ventas **no descuenta stock** de `Producto_Talle`: el stock inicial no refleja las unidades vendidas en los datos de prueba.

---

## 8. Conclusión

*Completar tras ejecutar las pruebas: cantidad de pruebas ejecutadas, cantidad aprobadas y observaciones.*

| Sección | Pruebas | Aprobadas |
| :--- | :---: | :---: |
| 1. Carga de datos | 8 | |
| 2. Integridad referencial | 4 | |
| 3. Consistencia | 5 | |
| 4. Pruebas negativas | 14 | |
| 5. Comportamiento | 2 | |
| 6. Consultas de negocio | 7 | |
