# Seguridad – Etapa V – Intensa Jeans

**Tema técnico:** 4 – Seguridad
**Scripts:** [`seguridad.sql`](seguridad.sql) y [`seguridad_pruebas.sql`](seguridad_pruebas.sql)
**Reglas de negocio:** RN.02, RN.04, RN.08

---

## 1. Necesidad

Hasta la etapa IV, cualquier usuario conectado a la base podía hacer lo mismo que su dueño: cambiar un precio, borrar una venta o eliminar una tabla. Este tema aplica el **principio de mínimo privilegio**: cada usuario tiene solo los permisos que necesita para su trabajo.

## 2. Mecanismos implementados

| Mecanismo | Para qué se usa |
| :--- | :--- |
| **Roles de base de datos** | Los permisos se asignan al rol y no a cada persona. Para dar de alta a un empleado, alcanza con sumarlo al rol. |
| **`GRANT` por tabla y por columna** | Da solo lo necesario. Por ejemplo, el mostrador puede actualizar `stock`, pero ninguna otra columna de `Producto_Talle`. |
| **`DENY`** | Protege el historial de ventas. Tiene prioridad sobre cualquier `GRANT`. |
| **Dynamic Data Masking** | Oculta el contacto del cliente a quien no necesita verlo. Está disponible en SQL Server Express. |

## 3. Roles

Los roles salen de los actores definidos en [`casos-uso.md`](../etapa-04/casos-uso.md). `rol_administrador` es miembro de `rol_mostrador`, lo que implementa la generalización entre ambos actores: el administrador hereda todo lo que puede hacer el mostrador.

| Rol | Actor | Función |
| :--- | :--- | :--- |
| `rol_mostrador` | Personal de mostrador | Consulta el catálogo, registra clientes y ventas, y descuenta stock. |
| `rol_administrador` | Administrador del negocio | Además, gestiona el catálogo, los precios y las liquidaciones. |

## 4. Matriz de permisos

| Tabla | `rol_mostrador` | `rol_administrador` (suma a lo heredado) |
| :--- | :--- | :--- |
| `Categoria`, `Talle`, `Metodo_pago`, `Producto` | `SELECT` | `INSERT`, `UPDATE`, `DELETE` |
| `Producto_Talle` | `SELECT`, `UPDATE (stock)` | `INSERT`, `UPDATE`, `DELETE` |
| `Cliente` | `SELECT`, `INSERT`, `UPDATE` sin `dni` | `UNMASK` (ve los datos sin enmascarar) |
| `Venta`, `Detalle_Venta` | `SELECT`, `INSERT`, **`DENY UPDATE, DELETE`** | Sin cambios: el `DENY` se hereda |

Decisiones:

- **Nadie modifica una venta registrada.** El `DENY` alcanza también al administrador, porque el comprobante y los reportes dependen de ese historial (RN.08).
- **El administrador tampoco borra clientes.** Toda venta queda asociada a un cliente registrado (RN.04).
- **Ningún rol modifica la estructura.** Crear o eliminar tablas queda reservado al dueño de la base.

## 5. Enmascaramiento de datos

| Columna | Función | Mostrador ve | Administrador ve |
| :--- | :--- | :--- | :--- |
| `email` | `email()` | `lXXX@XXXX.com` | `lucia.fernandez@mail.com` |
| `telefono` | `partial(0,"XXXX-",4)` | `XXXX-1234` | `3794-551234` |
| `direccion` | `default()` | `xxxx` | `Junín 1250, Corrientes` |
| `dni` | Sin máscara | `38456123` | `38456123` |

El DNI queda visible porque el comprobante de venta lo muestra (CU-01).

## 6. Pruebas

[`seguridad_pruebas.sql`](seguridad_pruebas.sql) ejecuta 24 operaciones con `EXECUTE AS USER`, cada una como `usr_mostrador_demo` o `usr_admin_demo`, y revierte todas al terminar. Un rechazo solo se da por bueno si el error es de permisos.

**Resultado obtenido:** las 24 operaciones dieron el resultado esperado, y los datos quedaron sin cambios.

| Usuario | Permitidas | Rechazadas |
| :--- | :--- | :--- |
| `usr_mostrador_demo` | Emitir comprobante, registrar una venta completa, registrar un cliente, corregir un teléfono | Cambiar un precio, crear un producto, cambiar un DNI, borrar un cliente, modificar o borrar una venta, borrar stock de un talle, crear o eliminar una tabla |
| `usr_admin_demo` | Emitir comprobante, registrar una venta, cambiar un precio, poner un producto en liquidación, crear un producto, crear y borrar una categoría | Modificar o borrar una venta, modificar un detalle, borrar un cliente, eliminar una tabla |

## 7. Limitaciones

- **La máscara no es cifrado.** Los datos siguen guardados tal cual. Además, quien puede consultar la tabla puede deducir un valor filtrando con `WHERE` (por ejemplo, `WHERE email = '...'`).
- **El dueño de la base (`dbo`) no tiene restricciones.** No debe usarse para el trabajo diario.
- **El mostrador tiene permisos directos sobre las tablas.** Registrar una venta hoy requiere `INSERT` y `UPDATE (stock)` directos, por lo que el mostrador podría cargar importes incorrectos. Ver la sección 8.

## 8. Integración con los demás temas

Con los procedimientos de venta y los triggers de auditoría ya implementados:

1. **Permiso de ejecución (ya incluido en `seguridad.sql`, sección 4.h).** `rol_mostrador` puede ejecutar `sp_RegistrarVentaCompleta` y `sp_ActualizarStock`, y usar el tipo de tabla `tt_DetalleVenta` que recibe el primero. El administrador lo hereda. Los permisos se otorgan solo si los procedimientos ya existen; si `seguridad.sql` se ejecutó antes, hay que volver a correr esa sección.

   Para reforzar el control, se pueden quitar los permisos directos sobre las tablas. No se hizo en `seguridad.sql` porque las pruebas de `seguridad_pruebas.sql` registran una venta con `INSERT` directo:

   ```sql
   REVOKE INSERT ON Venta FROM rol_mostrador;
   REVOKE INSERT ON Detalle_Venta FROM rol_mostrador;
   REVOKE UPDATE ON Producto_Talle (stock) FROM rol_mostrador;
   ```

   El procedimiento sigue funcionando sin esos permisos, por el encadenamiento de propiedad (*ownership chaining*): si el procedimiento y las tablas tienen el mismo dueño, SQL Server no vuelve a controlar los permisos sobre las tablas.

2. No dar a `rol_mostrador` ningún permiso sobre la tabla de auditoría. Si hace falta, el administrador recibe solo `SELECT`.

Las tablas nuevas no heredan permisos: cada una necesita sus propios `GRANT`.

## 9. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Ejecutar `seguridad.sql`. Se puede volver a correr sin errores.
3. Ejecutar `seguridad_pruebas.sql` y verificar que todas las filas tengan `ok = 'SI'`.

Para crear un usuario real con contraseña, usar la plantilla de la sección 4.g de `seguridad.sql`.
