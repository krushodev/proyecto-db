# Manejo de transacciones – Etapa V – Intensa Jeans

**Tema técnico:** 2 – Manejo de transacciones
**Scripts:** [`scripts.sql`](scripts.sql) y [`scripts_concurrencia.sql`](scripts_concurrencia.sql)
**Evidencias:** [`evidencias/`](evidencias/)
**Reglas de negocio:** RN.02, RN.04, RN.07, RN.08

---

## 1. Definición y objetivo

Una **transacción** es un conjunto de operaciones SQL que se ejecutan como una **única unidad lógica de trabajo**: o se aplican todas (`COMMIT`) o no se aplica ninguna (`ROLLBACK`). El motor garantiza las propiedades **ACID**:

| Propiedad | Significado | Cómo se ve en este proyecto |
| :--- | :--- | :--- |
| **A**tomicidad | Todo o nada | Una venta sin stock no deja encabezado ni detalle |
| **C**onsistencia | Se pasa de un estado válido a otro válido | El stock nunca queda negativo y el total coincide con el detalle |
| **A**islamiento | Las transacciones simultáneas no se pisan | Dos ventas de la última unidad no la venden dos veces |
| **D**urabilidad | Lo confirmado no se pierde | Una venta confirmada sobrevive a una caída del servidor |

**Objetivo en este proyecto:** que registrar una venta, que toca tres tablas (`Venta`, `Detalle_Venta` y `Producto_Talle`), no pueda dejar información incompleta ni inconsistente.

## 2. Ventajas y aplicaciones

| Ventaja | Por qué importa |
| :--- | :--- |
| **Sin registros parciales** | Si falla el paso 3, los pasos 1 y 2 se deshacen solos. |
| **Reglas de negocio garantizadas** | RN.02: no se vende más de lo que hay en stock. |
| **Recuperación ante errores** | Con `TRY/CATCH` el error se captura y la base queda como estaba. |
| **Concurrencia segura** | Los bloqueos de SQL Server ordenan las operaciones simultáneas. |

**Aplicaciones típicas:** ventas y cobros, transferencias entre cuentas, reservas, altas que afectan varias tablas.

## 3. Implementación en SQL Server Express

Las transacciones están disponibles en todas las ediciones, incluida Express.

### 3.1. Elementos utilizados

| Elemento | Qué hace |
| :--- | :--- |
| `BEGIN TRANSACTION` | Abre la transacción. Desde acá los cambios no son definitivos. |
| `COMMIT TRANSACTION` | Confirma todos los cambios. |
| `ROLLBACK TRANSACTION` | Deshace todos los cambios desde el `BEGIN`. |
| `BEGIN TRY ... BEGIN CATCH` | Captura los errores de ejecución. |
| `SET XACT_ABORT ON` | Ante un error de ejecución, la transacción queda anulada y no puede confirmarse. Evita transacciones abiertas a medias. |
| `XACT_STATE()` | Estado de la transacción en el `CATCH`: `1` confirmable, `-1` condenada, `0` sin transacción. Con `<> 0` se hace el `ROLLBACK`. |
| `THROW` | Lanza un error propio. Acá se usa para abortar la venta cuando falta stock. |
| `@@ROWCOUNT` | Cantidad de filas que afectó la última sentencia. |

### 3.2. Decisiones de implementación

- **Estructura única para todas las pruebas:** `BEGIN TRAN` → pasos 1, 2 y 3 → control de stock → `COMMIT`, todo dentro de `TRY`, y el `ROLLBACK` en el `CATCH`.
- **Descuento de stock atómico:** `UPDATE ... SET stock = stock - cantidad WHERE stock >= cantidad`, y se compara `@@ROWCOUNT` con la cantidad de renglones. Es una sola sentencia, por lo que no hay un intervalo entre "leer el stock" y "descontarlo" en el que otra venta pueda colarse. La alternativa de la guía (leer `@stock_actual`, comparar y después descontar) sí tiene ese intervalo.
- **Total y descuento calculados antes de insertar la venta**, porque `rol_mostrador` tiene `DENY UPDATE` sobre `Venta` (ver [`seguridad.md`](../seguridad.md)) y no podría corregir el total después.
- **Precio histórico:** el precio unitario del detalle es el de lista con la liquidación aplicada (RN.06 y RN.08), y el descuento por método de pago (RN.07) se calcula sobre el subtotal.
- **Varios renglones por venta:** los renglones se cargan en una variable tipo tabla, de modo que la misma lógica sirve para una venta de 1 o de N productos.
- **Sin procedimientos almacenados:** ese tema le corresponde a otro integrante. Los bloques se pueden envolver en un procedimiento sin cambiar la lógica (ver sección 6).

## 4. Caso concreto en el sistema de ventas

**Escenario:** el personal de mostrador registra una venta. La operación debe:

1. Crear el encabezado en `Venta`.
2. Crear los renglones en `Detalle_Venta`, con el precio histórico.
3. Descontar el stock del talle vendido en `Producto_Talle`.

Si no hay stock suficiente en **algún** renglón, no se registra la venta, no se registra el detalle y no se modifica el stock de ningún renglón.

| Prueba | Tipo | Caso |
| :-: | :-: | :--- |
| P1 | Correcta | 2 unidades del producto 8, talle 1 (stock 10), pagadas en efectivo (15 %) |
| P2 | Incorrecta | 10 unidades del producto 4, talle 3 (stock 9) |
| P3 | Incorrecta, varios renglones | Renglón 1 con stock y renglón 2 sin stock (producto 4, talle 4: stock 5, se piden 6) |
| P4 | Error inesperado | Producto 1 con talle 10, que no tiene stock cargado: falla la clave foránea del detalle con la venta ya insertada |
| Concurrencia | Aislamiento | Dos sesiones compiten por la última unidad de un talle |

## 5. Script de demostración y resultados obtenidos

[`scripts.sql`](scripts.sql) corre las cuatro pruebas y verifica el resultado. Salida completa: [`evidencias/resultados_scripts.txt`](evidencias/resultados_scripts.txt).

### 5.1. Resultados

| Prueba | Resultado | Ventas nuevas | Renglones nuevos | Filas de auditoría nuevas | Stock antes → después |
| :-: | :--- | :-: | :-: | :-: | :-: |
| **P1** | `COMMIT`: venta 11 registrada | 1 | 1 | 1 | 10 → 8 |
| **P2** | `ROLLBACK`: stock insuficiente | 0 | 0 | 0 | 9 → 9 |
| **P3** | `ROLLBACK`: stock insuficiente | 0 | 0 | 0 | prod. 8 talle 2: 10 → 10; prod. 4 talle 4: 5 → 5 |
| **P4** | `ROLLBACK`: viola `FK_DetalleVenta_ProductoTalle` | 0 | 0 | 0 | sin cambios |

Lo que demuestran:

- **P1 (atomicidad, caso correcto):** la venta queda registrada con su detalle y el stock baja. El total es consistente: subtotal de renglones 56000.00 − descuento 8400.00 (15 %) = 47600.00, igual al total guardado.
- **P2 y P3 (atomicidad, caso incorrecto):** el encabezado y el detalle ya se habían insertado cuando falló el control de stock, y el `ROLLBACK` los deshizo. En P3 el renglón válido tampoco descontó stock.
- **P4 (errores inesperados):** con `XACT_ABORT ON`, un error que no es de negocio también deja la base intacta.
- **Integración con los triggers de auditoría:** en P1 el trigger de `Producto_Talle` registró el movimiento de stock (`10 → 8`). En P2, P3 y P4 no quedó ninguna fila: el `ROLLBACK` deshace también lo que escriben los triggers, porque se ejecutan dentro de la misma transacción.

### 5.2. Demostración de aislamiento

[`scripts_concurrencia.sql`](scripts_concurrencia.sql) se ejecuta en **dos ventanas** de consulta. El producto 8, talle 2 queda con 1 unidad y dos ventas compiten por ella:

| Sesión | Qué hace | Resultado |
| :--- | :--- | :--- |
| **A** | Abre una transacción, descuenta la unidad y espera 10 s antes de confirmar | Vendió la última unidad (`filas_actualizadas = 1`) |
| **B** | Empieza 3 s después e intenta descontar la misma unidad | Se bloquea hasta que A confirma (esperó 6.9 s) y luego recibe `filas_actualizadas = 0`: sin stock, la venta se rechaza |

El stock nunca llegó a ser negativo y la unidad no se vendió dos veces. Salida: [`evidencias/resultados_concurrencia.txt`](evidencias/resultados_concurrencia.txt).

### 5.3. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Opcional: ejecutar `docs/etapa-05/triggers_auditoria/scripts.sql`, para ver también la auditoría. Sin ella, la columna de auditoría queda en `NULL`.
3. Ejecutar `scripts.sql`. La sección 6 restablece los datos al terminar (borra la venta 11 y devuelve el stock).
4. Para la concurrencia, seguir las instrucciones de `scripts_concurrencia.sql`.

> Las capturas de pantalla se pueden agregar en `evidencias/` si el equipo las pide. La salida en texto es la misma que se obtiene en SSMS.

## 6. Integración con los demás temas

- **Procedimientos:** estos bloques son la base de un procedimiento de venta, por ejemplo `sp_RegistrarVentaCompleta`. Alcanza con convertir las variables `@id_cliente`, `@id_metodo`, `@canal` e `@items` en parámetros. Ese procedimiento debería incluir la transacción tal como está acá.
- **Seguridad:** [`seguridad.md`](../seguridad.md) prevé quitar al mostrador los permisos directos de `INSERT` sobre `Venta` y `Detalle_Venta` y de `UPDATE (stock)`, y darle `EXECUTE` sobre el procedimiento. Funciona por encadenamiento de propiedad, y la transacción no cambia.
- **Triggers de auditoría:** `trg_Producto_Talle_Auditoria` se dispara dentro de la transacción de la venta. Si la venta se revierte, la auditoría también.

## 7. Limitaciones

- **`READ COMMITTED` es el nivel por defecto.** Evita lecturas sucias, pero dos lecturas dentro de una misma transacción pueden dar valores distintos. Para este caso no hace falta un nivel más alto, porque el descuento de stock es una sola sentencia atómica.
- **Una transacción larga retiene bloqueos.** En la demostración, B espera mientras A no confirma. En la práctica, las transacciones de venta deben ser cortas.
- **Posibles interbloqueos (deadlocks)** si dos ventas actualizan los mismos talles en distinto orden. Los renglones se procesan en una sola sentencia, lo que reduce el riesgo pero no lo elimina.
- **`@@ROWCOUNT` cuenta renglones, no unidades.** El control funciona porque la variable de renglones tiene clave primaria `(Id_Producto, Id_Talle)`, es decir, no admite el mismo talle dos veces.
- **Los bloques están repetidos en cada prueba.** Es intencional para que cada prueba sea independiente, y desaparece cuando la lógica pase a un procedimiento.
