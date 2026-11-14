# Seguridad – Etapa V – Intensa Jeans

**Tema técnico:** 4 – Seguridad
**Scripts:** [`seguridad.sql`](seguridad.sql), [`seguridad_pruebas.sql`](seguridad_pruebas.sql) y [`seguridad_guia.sql`](seguridad_guia.sql)
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

Los roles salen de los actores definidos en [`casos-uso.md`](../../etapa-04/casos-uso.md). `rol_administrador` es miembro de `rol_mostrador`, lo que implementa la generalización entre ambos actores: el administrador hereda todo lo que puede hacer el mostrador.

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
2. Ejecutar `docs/etapa-05/procedimientos_funciones/scripts.sql`.
3. Ejecutar `seguridad.sql`. Se puede volver a correr sin errores.
4. Ejecutar `seguridad_pruebas.sql` y verificar que todas las filas tengan `ok = 'SI'`.
5. Ejecutar `seguridad_guia.sql` y verificar que las 5 filas tengan `ok = 'SI'` (sección 10).

Para crear un usuario real con contraseña, usar la plantilla de la sección 4.g de `seguridad.sql`.

## 10. Demostración de la guía de la etapa V

La guía pide cuatro demostraciones puntuales. [`seguridad_guia.sql`](seguridad_guia.sql) las implementa con **usuarios nuevos**, sin tocar `rol_mostrador` ni `rol_administrador`, para que las 24 pruebas de la sección 6 sigan valiendo.

| Demostración | Cómo se implementa |
| :--- | :--- |
| Usuarios con inicio de sesión | `CREATE LOGIN ... WITH PASSWORD` y `CREATE USER ... FOR LOGIN` para `usuario_admin`, `usuario_lector`, `usuario_con_rol` y `usuario_sin_rol`. |
| Permisos dados directamente a un usuario | `usuario_lector` recibe `GRANT SELECT ON Venta` sin pasar por ningún rol. |
| `INSERT` directo frente a procedimiento | `usuario_lector` no tiene `INSERT` sobre ninguna tabla, pero tiene `GRANT EXECUTE` sobre `sp_RegistrarVentaCompleta` y sobre el tipo `tt_DetalleVenta`. |
| Permisos dados a través de un rol | `rol_consulta_productos` tiene `SELECT` sobre `Producto`. `usuario_con_rol` es miembro; `usuario_sin_rol` no. |

**Resultado esperado:**

| Prueba | Usuario | Resultado esperado |
| :--- | :--- | :--- |
| `SELECT` sobre `Producto` | `usuario_con_rol` | Correcto |
| `SELECT` sobre `Producto` | `usuario_sin_rol` | Acceso denegado |
| `INSERT` directo sobre `Venta` | `usuario_admin` | Correcto |
| `INSERT` directo sobre `Venta` | `usuario_lector` | Acceso denegado |
| `EXEC` del procedimiento | `usuario_lector` | Correcto |

**Por qué el lector puede registrar la venta con el procedimiento.** El procedimiento y las tablas que modifica (`Venta`, `Detalle_Venta`, `Producto_Talle`) tienen el mismo dueño, `dbo`. Por el encadenamiento de propiedad (*ownership chaining*), SQL Server controla solo el permiso `EXECUTE` sobre el procedimiento y no vuelve a controlar los permisos sobre esas tablas. Así el usuario no puede escribir en la tabla directamente, pero sí puede hacer la operación autorizada, con las validaciones y reglas del procedimiento.

Decisiones respecto de la guía:

- **Administrador.** La guía agrega `usuario_admin` a `db_owner`. Acá se lo agrega a `rol_administrador`, que es más restrictivo: no puede modificar la estructura ni el historial de ventas. Alcanza para la prueba del `INSERT` directo y respeta el mínimo privilegio.
- **Contraseñas.** Son de ejemplo, porque quedan guardadas en el repositorio. No se deben usar en un servidor real.
- **Ejecución de las pruebas.** Igual que `seguridad_pruebas.sql`, se usa `EXECUTE AS USER` y cada operación se revierte. Para conectarse de verdad con estos logins, el servidor necesita autenticación mixta.
