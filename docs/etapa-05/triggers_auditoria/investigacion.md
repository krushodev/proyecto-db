# Triggers de auditoría – Etapa V – Intensa Jeans

**Script:** [`scripts.sql`](scripts.sql)
**Evidencias:** [`evidencias/`](evidencias/)
**Reglas de negocio:** RN.02, RN.05, RN.06, RN.08

---

## 1. Definición y objetivo

Un **trigger** (disparador) es un bloque de código SQL asociado a una tabla que el motor ejecuta **automáticamente** cuando ocurre un `INSERT`, un `UPDATE` o un `DELETE` sobre ella. Nadie lo invoca: se dispara solo, y quien modifica los datos no puede omitirlo.

Un **trigger de auditoría** es el que usa esa propiedad para dejar registrado **quién cambió qué, cuándo y con qué valor anterior**.

**Objetivo en este proyecto:** que todo cambio de precio, de liquidación o de stock de un producto quede registrado en la tabla `Auditoria`, sin depender de que la aplicación o el usuario se acuerden de anotarlo.

## 2. Ventajas y aplicaciones

| Ventaja | Por qué importa |
| :--- | :--- |
| **No se puede esquivar** | Se ejecuta aunque el cambio se haga desde SSMS, un script o la aplicación. |
| **Automático** | No hay que llamar a nada ni modificar los procedimientos existentes. |
| **Acceso al valor anterior** | La tabla especial `deleted` conserva lo que había antes del cambio. |
| **Trazabilidad, seguridad y cumplimiento** | Permite reconstruir el historial y detectar cambios indebidos. |

**Aplicaciones típicas:** historial de precios, control de movimientos de inventario, registro de accesos y cambios en datos sensibles, y evidencia ante un reclamo o una auditoría.

## 3. Implementación en SQL Server Express

Los triggers están disponibles en todas las ediciones, incluida Express, y no requieren configuración adicional.

### 3.1. Conceptos y sintaxis

```sql
CREATE OR ALTER TRIGGER nombre
ON tabla
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- usar las tablas inserted y deleted
END;
```

| Elemento | Detalle |
| :--- | :--- |
| `AFTER` | El trigger corre **después** de que el cambio se aplicó y pasó las restricciones (`CHECK`, `FOREIGN KEY`). Si el cambio es rechazado, el trigger no se ejecuta. |
| `INSTEAD OF` | Reemplaza la operación. No se usa acá porque la auditoría debe registrar, no modificar el comportamiento. |
| `inserted` | Tabla temporal con las filas **nuevas** (en `INSERT`) o los valores **nuevos** (en `UPDATE`). |
| `deleted` | Tabla temporal con las filas **borradas** (en `DELETE`) o los valores **anteriores** (en `UPDATE`). |
| `SUSER_SNAME()` | Login que ejecutó la operación. |
| `SYSDATETIME()` | Fecha y hora del servidor. |

### 3.2. Tabla `Auditoria`

Guarda **una fila por cada campo modificado**. Así una misma tabla sirve para cualquier trigger.

| Columna | Qué guarda |
| :--- | :--- |
| `Id_Auditoria` | Identificador del registro |
| `tabla` | Tabla afectada (`Producto` o `Producto_Talle`) |
| `operacion` | `INSERT`, `UPDATE` o `DELETE` (con `CHECK`) |
| `clave` | PK de la fila afectada, por ejemplo `Id_Producto=4` |
| `campo` | Columna modificada |
| `valor_anterior` / `valor_nuevo` | Valores antes y después |
| `usuario` | `SUSER_SNAME()`, por defecto |
| `fecha_hora` | `SYSDATETIME()`, por defecto |

### 3.3. Decisiones de implementación

- **Set-based:** los triggers trabajan con `inserted` y `deleted` mediante `JOIN`, sin variables. Por eso registran bien un `UPDATE` que afecta muchas filas.
- **Solo registra cambios reales:** si el valor nuevo es igual al anterior, no inserta nada.
- **Una fila por campo:** si en un mismo `UPDATE` cambian el precio y el porcentaje de liquidación, quedan dos filas.
- **Re-ejecutable:** `CREATE OR ALTER TRIGGER` y `IF OBJECT_ID(...) IS NULL` permiten correr el script varias veces.

## 4. Caso concreto en el sistema de ventas

| Trigger | Tabla | Qué audita | Regla de negocio |
| :--- | :--- | :--- | :--- |
| `trg_Producto_Auditoria` | `Producto` | `precio_lista`, `en_liquidacion`, `porcentaje_liquidacion` | RN.05, RN.06 |
| `trg_Producto_Talle_Auditoria` | `Producto_Talle` | `stock` | RN.02 |

El precio de venta que se cobra sale de estos campos, y el precio unitario queda guardado en cada venta (RN.08). Si alguien modifica un precio, el historial de `Auditoria` permite explicar por qué dos ventas del mismo producto tienen importes distintos. El stock se audita porque cada venta lo descuenta: queda el historial de movimientos de inventario.

### Datos que se registran

| Dato pedido | Dónde queda |
| :--- | :--- |
| Fecha y hora | `fecha_hora` |
| Usuario | `usuario` |
| Producto | `clave` (`Id_Producto=...`); el nombre se obtiene con un `JOIN` a `Producto` |
| Precio anterior | `valor_anterior` (con `campo = 'precio_lista'`) |
| Precio nuevo | `valor_nuevo` |
| Tipo de operación | `operacion` |

## 5. Script de demostración y resultados obtenidos

### 5.1. Demo: cambiar un precio y comprobar que quedó registrado solo

El `UPDATE` no escribe nada en `Auditoria`: lo hace el trigger.

```sql
-- Antes: el Jean Slim Fit Celeste (Id_Producto = 4) cuesta 46000.00
UPDATE Producto SET precio_lista = 48000 WHERE Id_Producto = 4;

-- Consulta de la tabla de auditoria
SELECT a.fecha_hora, a.usuario, p.nombre AS producto, a.campo,
       a.valor_anterior AS precio_anterior, a.valor_nuevo AS precio_nuevo, a.operacion
FROM Auditoria a
JOIN Producto p ON a.clave = CONCAT('Id_Producto=', p.Id_Producto)
WHERE a.tabla = 'Producto' AND a.campo = 'precio_lista'
ORDER BY a.Id_Auditoria DESC;
```

| Antes | Operación | Registro generado automáticamente |
| :--- | :--- | :--- |
| Producto 4 – *Jean Slim Fit Celeste*, precio 46000.00 | `UPDATE Producto SET precio_lista = 48000 WHERE Id_Producto = 4` | `producto`: Jean Slim Fit Celeste · `precio_anterior`: 46000.00 · `precio_nuevo`: 48000.00 · `operacion`: UPDATE · `usuario`: login que ejecutó · `fecha_hora`: momento del cambio |

> Para volver al precio original después de la demo: `UPDATE Producto SET precio_lista = 46000 WHERE Id_Producto = 4;`. Ese cambio también queda auditado, y es lo esperado.

### 5.2. Pruebas del script

`scripts.sql` incluye 9 pruebas. Cada una corre dentro de una transacción que se deshace con `ROLLBACK`, así la base queda como estaba.

| Prueba | Tipo | Caso | Resultado obtenido |
| :-: | :-: | :--- | :--- |
| P1 | Éxito | Cambio de precio del producto 1 | 1 fila: 45000.00 → 46000.00 |
| P2 | Límite | `UPDATE` que no cambia ningún valor | 0 filas |
| P3 | Límite | Un `UPDATE` sobre 2 productos y 2 campos | 4 filas (una por producto y campo) |
| P4 | Éxito | Descuento de stock (producto 1, talle 2) | 1 fila: 15 → 14 |
| P5 | Límite | Reposición en los 4 talles del producto 6 | 4 filas |
| P6 | Éxito | Alta y baja de un producto | 2 filas (`INSERT` y `DELETE`) |
| P7 | Error | Stock negativo | El `CHECK` lo rechaza; 0 filas en `Auditoria` |
| P8 | Error | Borrar un producto con stock asociado | La clave foránea lo rechaza; 0 filas en `Auditoria` |
| P9 | Verificación | Estado final de `Auditoria` | 0 filas (todo se deshizo) |

Las capturas de cada prueba están en [`evidencias/`](evidencias/).

## 6. Integración con seguridad

La tabla `Auditoria` pierde valor si quien audita puede modificarla. Siguiendo la sección 8 de `docs/etapa-05/seguridad.md`:

- `rol_mostrador` **no recibe ningún permiso** sobre `Auditoria`.
- `rol_administrador` recibe, como máximo, `SELECT`.
- Las tablas nuevas no heredan permisos, así que cada una necesita su propio `GRANT`.

Los triggers escriben en `Auditoria` aunque el usuario que hace el cambio no tenga permisos sobre ella, porque el trigger se ejecuta con el encadenamiento de propiedad de la base (mismo dueño para las tablas y para `Auditoria`).

## 7. Limitaciones

- **Un usuario con permisos de administración puede deshabilitarlos** (`DISABLE TRIGGER`). Por eso hay que restringir quién tiene `ALTER` sobre las tablas.
- **No registran lecturas:** los triggers DML no se disparan con `SELECT`.
- **`TRUNCATE TABLE` no los dispara**, ni las cargas masivas que no activen la opción `FIRE_TRIGGERS`.
- **`usuario` es el login:** si la aplicación se conecta siempre con una misma cuenta, todas las filas muestran esa cuenta.
- **Costo:** cada cambio genera escrituras extra. Es aceptable en estas dos tablas, pero no conviene auditar todo.
- **Los triggers de `INSERT` y `DELETE` guardan un resumen en texto**, no cada campo por separado.

## 8. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Ejecutar `docs/etapa-05/triggers_auditoria/scripts.sql`. Crea la tabla `Auditoria` y los dos triggers, y corre las 9 pruebas.
3. Ejecutar la demo de la sección 5.1 y consultar `Auditoria`.
4. Guardar las capturas en `evidencias/`.
