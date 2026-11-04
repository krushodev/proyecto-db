# Procedimientos y funciones almacenadas – Etapa V – Intensa Jeans

**Script:** [`scripts.sql`](scripts.sql)
**Evidencias:** [`evidencias/`](evidencias/)
**Reglas de negocio:** RN.02, RN.04, RN.05, RN.06, RN.07, RN.08

---

## 1. Definición y objetivo

Un **procedimiento almacenado** (*stored procedure*) es un programa SQL guardado en la base de datos con un nombre, que se ejecuta con una sola llamada (`EXEC`). Puede consultar, insertar, actualizar, validar y controlar errores.

Una **función definida por el usuario** es una rutina que recibe parámetros y **devuelve un valor** (o una tabla). Se usa dentro de una consulta, como una fórmula.

| | Procedimiento almacenado | Función |
| :--- | :--- | :--- |
| **Para qué sirve** | Operar: registrar, modificar, validar | Calcular y devolver un resultado |
| **Cómo se invoca** | `EXEC nombre ...` | Dentro de un `SELECT`, `WHERE`, etc. |
| **Puede modificar datos** | Sí | No |

**Objetivo en este proyecto:** que una venta completa se registre con un único `EXEC`, sin que quien la carga tenga que validar el stock, guardar el precio histórico ni aplicar los descuentos a mano. Un segundo procedimiento, `sp_ActualizarStock`, permite reponer o corregir el inventario sin que el stock quede en negativo.

## 2. Ventajas y aplicaciones

| Ventaja | Por qué importa |
| :--- | :--- |
| **Reutilización** | Mostrador, web, Instagram y WhatsApp llaman al mismo procedimiento. |
| **Reglas centralizadas** | Si cambia el descuento por cliente frecuente, se modifica la función en un solo lugar. |
| **Menos código repetido y más mantenible** | Una venta son 5 pasos; acá es una sola llamada. |
| **Seguridad** | Se puede dar permiso para ejecutar el procedimiento sin dar acceso directo a las tablas. |
| **Rendimiento** | El motor guarda el plan de ejecución y se envían menos sentencias por la red. |
| **Consistencia** | Con una transacción interna, la venta se registra completa o no se registra. |

**Aplicaciones típicas:** alta de ventas, cálculo de precios y comisiones, validaciones complejas y reportes parametrizados.

## 3. Implementación en SQL Server Express

Procedimientos y funciones están disponibles en todas las ediciones, incluida **Express**, sin configuración adicional.

### 3.1. Sintaxis y elementos clave

```sql
CREATE OR ALTER FUNCTION dbo.nombre (@parametro INT)
RETURNS INT
AS
BEGIN
    RETURN 1;
END;

CREATE OR ALTER PROCEDURE dbo.nombre
    @entrada INT,
    @salida  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
END;
```

| Elemento | Detalle |
| :--- | :--- |
| `CREATE OR ALTER` | Crea el objeto o lo reemplaza si existe: el script se puede ejecutar varias veces. |
| `OUTPUT` | Parámetro por el que el procedimiento devuelve un valor (acá, el número de venta). |
| `CREATE TYPE ... AS TABLE` | Tipo de tabla: permite pasar **varias filas** como parámetro (`READONLY`), por ejemplo los renglones de la venta. |
| `THROW número, 'mensaje', estado` | Lanza un error propio (números desde 50000). |
| `TRY ... CATCH` y `TRANSACTION` | Deshacen toda la operación si algo falla y relanzan el error con `THROW;`. |
| `UPDLOCK, HOLDLOCK` | Bloquean las filas de stock hasta el final de la transacción, para que dos ventas simultáneas no consuman el mismo stock. |

### 3.2. Objetos implementados

| Objeto | Tipo | Qué hace |
| :--- | :--- | :--- |
| `dbo.fn_StockDisponible(@Id_Producto, @Id_Talle)` | Función | Devuelve el stock de un producto en un talle (0 si la combinación no existe). |
| `dbo.fn_CalcularDescuentoCliente(@Id_Cliente)` | Función | Devuelve el porcentaje de descuento según el monto acumulado de compras. |
| `dbo.tt_DetalleVenta` | Tipo de tabla | Renglones de la venta: `Id_Producto`, `Id_Talle`, `cantidad`. |
| `dbo.sp_RegistrarVentaCompleta` | Procedimiento | Registra la venta completa. |
| `dbo.sp_ActualizarStock` | Procedimiento | Suma o resta unidades al stock de un producto en un talle. |

### 3.3. Decisiones de implementación

- **El stock es por talle:** las funciones y procedimientos reciben producto **y** talle (RN.01).
- **Varios renglones por llamada:** los productos viajan en un `tt_DetalleVenta`, cuya clave `(Id_Producto, Id_Talle)` impide repetir un ítem.
- **Acumulado y umbrales:** el acumulado es la suma de `Venta.total` (lo efectivamente pagado) y "más de" es estricto: exactamente 200000 todavía da 0 %.
- **Los descuentos se suman:** cliente frecuente + método de pago (por ejemplo 5 % + 10 % = 15 %), con tope de 100 %. El del cliente se calcula antes de registrar la venta, para que la compra actual no cuente en su propio acumulado.
- **Precio histórico (RN.08):** cada renglón guarda el precio de lista con la liquidación aplicada (RN.06).
- **Validaciones en dos momentos:** los datos inválidos se rechazan antes de abrir la transacción; el stock se verifica dentro, con las filas bloqueadas. Si ya había una transacción abierta, se usa un punto de guardado y solo se deshace lo propio.
- **`sp_ActualizarStock`:** la cantidad lleva signo (positivo = ingreso, negativo = ajuste a la baja) y es un único `UPDATE` con la condición `stock + cantidad >= 0`: es atómico y nunca deja el stock en negativo (RN.02).

## 4. Caso concreto en el sistema de ventas

### 4.1. Función: descuento por cliente frecuente

| Monto acumulado de compras | Descuento |
| :--- | :---: |
| Más de 500000 | 10 % |
| Más de 200000 | 5 % |
| Hasta 200000 | 0 % |

```sql
SELECT nombre, apellido, dbo.fn_CalcularDescuentoCliente(Id_Cliente) AS descuento
FROM dbo.Cliente;
```

### 4.2. Procedimiento: registrar una venta completa

El procedimiento valida cliente, método de pago y renglones (RN.04); verifica y bloquea el stock (RN.02); inserta el encabezado y el detalle con el precio histórico (RN.05, RN.06, RN.08); descuenta el stock; calcula el descuento y actualiza `descuento_aplicado` y `total` (RN.07). Si algo falla, deshace todo.

```sql
DECLARE @detalle dbo.tt_DetalleVenta;
DECLARE @id_venta INT;

INSERT INTO @detalle (Id_Producto, Id_Talle, cantidad) VALUES (6, 7, 2);

EXEC dbo.sp_RegistrarVentaCompleta
     @Id_Cliente     = 2,
     @Id_metodo_pago = 1,
     @canal          = 'Local',
     @Detalle        = @detalle,
     @Id_Venta       = @id_venta OUTPUT;
```

### 4.3. Procedimiento: actualizar stock

Sirve para reponer mercadería o corregir diferencias de inventario. Los dos procedimientos trabajan sobre el mismo stock: una venta rechazada por falta de stock puede concretarse después de reponerlo (prueba 15).

```sql
DECLARE @stock INT;

-- Ingreso de 20 unidades del Jean Mom Tiro Alto (producto 1), talle 36 (talle 1)
EXEC dbo.sp_ActualizarStock @Id_Producto = 1, @Id_Talle = 1, @cantidad = 20, @stock_resultante = @stock OUTPUT;

-- Ajuste a la baja de 5 unidades
EXEC dbo.sp_ActualizarStock @Id_Producto = 1, @Id_Talle = 1, @cantidad = -5, @stock_resultante = @stock OUTPUT;
```

### 4.4. Errores que devuelven los procedimientos

| Número | Mensaje | Procedimiento |
| :---: | :--- | :--- |
| 50001 | Stock insuficiente | `sp_RegistrarVentaCompleta` |
| 50002 | El cliente no existe | `sp_RegistrarVentaCompleta` |
| 50003 | El metodo de pago no existe | `sp_RegistrarVentaCompleta` |
| 50004 | La venta no tiene renglones | `sp_RegistrarVentaCompleta` |
| 50005 | La cantidad de cada renglon debe ser mayor a 0 | `sp_RegistrarVentaCompleta` |
| 50006 | Hay un renglon con una combinacion producto-talle inexistente | `sp_RegistrarVentaCompleta` |
| 50007 | La cantidad a ajustar no puede ser 0 | `sp_ActualizarStock` |
| 50008 | La combinacion producto-talle no existe | `sp_ActualizarStock` |
| 50009 | El ajuste dejaria el stock en negativo | `sp_ActualizarStock` |

## 5. Script de demostración y resultados obtenidos

Las pruebas están en [`scripts.sql`](scripts.sql), sección 6. Datos de partida: los de `tienda_ropa_dml.sql`. Las pruebas de éxito corren dentro de una transacción que se revierte, por lo que los datos originales quedan intactos.

| Nº | Tipo | Prueba | Resultado esperado |
| :-: | :--- | :--- | :--- |
| 1 | Función | `fn_StockDisponible` y `fn_CalcularDescuentoCliente` con los datos cargados | Stock (1,1) = 12; combinación inexistente = 0; descuento 0 % para todos |
| 2 | Límite | Umbrales de descuento con ventas de prueba del cliente 1 | 200000.00 → 0 %; 200000.01 → 5 %; 500000.00 → 5 %; 500000.01 → 10 % |
| 3 | Éxito | Venta de 1 renglón: cliente 2, Efectivo, Remera Básica talle M × 2 | Subtotal 30000.00; descuento 4500.00 (15 %); total 25500.00; stock 25 → 23 |
| 4 | Éxito | Venta de 2 renglones con liquidación; cliente frecuente (5 %) + Transferencia (10 %) | Subtotal 60600.00; descuento 9090.00 (15 %); total 51510.00; stock 8 → 7 y 30 → 28 |
| 5 | Límite | Comprar todo el stock (5) y luego 1 unidad más | 1.ª venta OK, total 195500.00, stock 0; 2.ª rechazada (50001) sin dejar nada |
| 6 a 11 | Error | Stock insuficiente, cliente inexistente, método inexistente, venta sin renglones, cantidad 0, producto-talle inexistente | Errores 50001 a 50006, uno por prueba |
| 12 | Éxito | `sp_ActualizarStock`: ingreso de 20 unidades (producto 1, talle 36) | Stock 12 → 32 |
| 13 | Éxito | `sp_ActualizarStock`: ajuste a la baja de 5 unidades | Stock 12 → 7 |
| 14 | Límite | Dejar el stock en 0 (producto 4, talle 42) y restar 1 más | Primer ajuste: stock 0; segundo: error 50009 |
| 15 | Integración | Vender 8 con stock 5, reponer 10 y vender de nuevo | 1.ª venta rechazada; stock 15; 2.ª venta OK, total 312800.00; stock 7 |
| 16 a 18 | Error | `sp_ActualizarStock` con cantidad 0, combinación inexistente y resta de 13 con stock 12 | Errores 50007, 50008 y 50009 |
| 19 | Verificación | Los errores y las pruebas revertidas no dejaron rastros | 10 ventas; 17 renglones; stock (1,1) = 12, (6,7) = 25 y (4,4) = 5 |

**Cálculo de la prueba 4:** Jean Skinny Negro 42000 − 20 % = 33600.00; Cinturón de Cuero 18000 − 25 % = 13500.00 × 2 = 27000.00. Subtotal 60600.00; descuento 15 % = 9090.00; total 51510.00.

### Evidencias

Capturas tomadas en SQL Server Management Studio al ejecutar `scripts.sql`, guardadas en `evidencias/`:

| Archivo | Contenido |
| :--- | :--- |
| `01_creacion_objetos.png` | Creación de los objetos sin errores y visibles en el Explorador de objetos |
| `02_funciones_datos.png` | Prueba 1 |
| `03_umbrales_descuento.png` | Prueba 2 |
| `04_venta_un_renglon.png` | Prueba 3 |
| `05_venta_dos_renglones.png` | Prueba 4 |
| `06_limite_stock.png` | Prueba 5 |
| `07_errores.png` | Pruebas 6 a 11 (pestaña **Mensajes**) |
| `08_actualizar_stock_exito.png` | Pruebas 12 y 13 |
| `09_actualizar_stock_limite.png` | Prueba 14 |
| `10_integracion_reposicion_venta.png` | Prueba 15 |
| `11_errores_stock.png` | Pruebas 16 a 18 (pestaña **Mensajes**) |
| `12_verificacion_final.png` | Prueba 19 |

> Una vez tomadas las capturas, se enlazan con `![descripción](evidencias/archivo.png)`.

**Resultado obtenido:** *completar tras ejecutar el script en SQL Server Management Studio.*
