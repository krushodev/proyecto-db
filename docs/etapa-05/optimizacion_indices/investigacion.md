# Optimización de consultas a través de índices – Etapa V – Intensa Jeans

**Tema técnico:** Optimización de consultas a través de índices
**Script:** [`scripts.sql`](scripts.sql)
**Evidencias:** [`evidencias/`](evidencias/)
**Complemento:** reescritura de consultas en [`../optimizacion_consultas.md`](../optimizacion_consultas.md) (sección 7)

---

## 1. Definición y objetivo

Un **índice** es una estructura auxiliar, organizada como un árbol B (B-tree), que guarda los valores de una o más columnas ordenados y con un puntero a cada fila. Funciona como el índice de un libro: en vez de leer todas las páginas para encontrar un tema, se busca en el índice y se va directo a la página.

SQL Server tiene dos tipos principales:

| Tipo | Qué es | Cuántos por tabla |
| :--- | :--- | :-: |
| **Agrupado** (`CLUSTERED`) | Las hojas del árbol **son** las filas de la tabla: la tabla queda ordenada físicamente por la clave del índice. | 1 |
| **No agrupado** (`NONCLUSTERED`) | Estructura aparte con la clave ordenada y un puntero a la fila (el RID si la tabla es un *heap*, o la clave del agrupado). | Hasta 999 |

Una tabla sin índice agrupado se llama **heap** (montón): las filas no tienen orden y la única forma de filtrarlas es recorrerlas todas (**Table Scan**).

Un índice no agrupado **de cobertura** agrega con `INCLUDE` columnas que no forman parte de la clave pero se guardan en las hojas. Si la consulta solo usa columnas que están en el índice, el motor no tiene que ir a la tabla (se evita el **RID Lookup** o **Key Lookup**).

**Objetivo en este proyecto:** medir cuánto mejora una consulta por rango de fechas sobre las ventas cuando se pasa de no tener índice, a un índice agrupado y a uno no agrupado de cobertura, y decidir qué índice conviene en la tabla `Venta` real.

## 2. Ventajas y aplicaciones

| Ventaja | Por qué importa |
| :--- | :--- |
| **Menos lecturas** | Con un *seek* el motor lee solo las páginas del rango pedido, no toda la tabla. En el experimento se pasa de 6780 a 73 lecturas lógicas. |
| **Menos tiempo y CPU** | Menos páginas para revisar significa menos trabajo: de ~124 ms a ~10 ms. |
| **Orden "gratis"** | Si el índice ya está ordenado por la columna del `ORDER BY` o del `GROUP BY`, el motor puede evitar un *Sort*. |
| **Menos bloqueos** | Al leer menos filas, una consulta bloquea menos y molesta menos a las ventas que se registran en paralelo. |
| **Unicidad** | Las restricciones `PRIMARY KEY` y `UNIQUE` (por ejemplo el DNI y el email de `Cliente`) se implementan con índices. |

**Costos:** cada índice ocupa espacio y hace más lentos los `INSERT`, `UPDATE` y `DELETE`, porque hay que mantenerlo actualizado. Por eso no conviene indexar todo, sino las columnas que se usan en `WHERE`, `JOIN` y `ORDER BY` de las consultas frecuentes.

**Aplicaciones típicas:** búsquedas por rango de fechas (reportes por período), búsquedas por clave (un cliente por DNI), columnas de unión (claves foráneas) y reportes que se ejecutan seguido.

### Scan contra seek

| Operación | Qué hace | Cuándo aparece |
| :--- | :--- | :--- |
| **Table Scan** | Recorre todo el heap. | No hay índice útil. |
| **Clustered Index Scan / Index Scan** | Recorre todas las hojas del índice. | Hay índice pero el filtro no lo aprovecha, o se piden casi todas las filas. |
| **Clustered Index Seek / Index Seek** | Baja por el árbol hasta el primer valor del rango y lee solo ese tramo. | El filtro es sobre la clave del índice y es SARGable. |
| **RID Lookup / Key Lookup** | Por cada fila encontrada en un índice no agrupado, va a la tabla a buscar las columnas que faltan. | El índice no cubre todas las columnas de la consulta. |

## 3. Implementación en SQL Server Express

Los índices agrupados, no agrupados y con `INCLUDE` están disponibles en todas las ediciones, incluida Express. Las mediciones se hicieron en **SQL Server 2025 Express (17.0.1000.7)**, en un equipo con Intel Core i3-1125G4, 7,7 GB de RAM y disco SSD.

### 3.1. Elementos utilizados

| Elemento | Qué hace |
| :--- | :--- |
| `CREATE CLUSTERED INDEX ... ON tabla (col)` | Ordena físicamente la tabla por `col`. |
| `CREATE NONCLUSTERED INDEX ... ON tabla (col) INCLUDE (c1, c2)` | Índice aparte por `col` que además guarda `c1` y `c2` en las hojas (cobertura). |
| `DROP INDEX nombre ON tabla` | Borra el índice. Si era el agrupado, la tabla vuelve a ser un heap. |
| `SET STATISTICS TIME ON` | Muestra el tiempo de CPU y el tiempo transcurrido de cada sentencia. |
| `SET STATISTICS IO ON` | Muestra las lecturas por tabla. Las **lecturas lógicas** (páginas de 8 KB leídas desde memoria) son la medida más estable para comparar. |
| Plan de ejecución real (Ctrl+M en SSMS) | Muestra qué operaciones usó el motor: scan, seek, lookup. |
| `WITH (INDEX (nombre))` | Sugerencia (*hint*) que obliga a usar un índice. Solo se usa en la prueba extra. |

### 3.2. Decisiones de implementación

- **Tabla de pruebas aparte (`VentaHistorica`)**: la tabla `Venta` real tiene 10 filas y ya tiene un índice agrupado (la PK). Para que los índices se noten hace falta volumen, y para medir el escenario sin índice la tabla tiene que arrancar como heap. Por eso se creó una tabla con las mismas columnas que el encabezado de `Venta`, sin PK ni FK.
- **Carga masiva con `ROW_NUMBER()` y `CROSS JOIN` de `sys.objects`**: se generan 1.200.000 ventas, una cada 3 minutos desde el 1/1/2020 (hasta noviembre de 2026). Cliente y método de pago rotan sobre los Id reales (1 a 10 y 1 a 8), y el total es pseudoaleatorio entre \$5.000 y \$204.999.
- **Misma consulta en todos los escenarios**: ventas de enero de 2025 (14.880 filas, el 1,24 % de la tabla). El filtro es un rango directo sobre `fecha_hora`, sin funciones, para que sea SARGable.
- **Medición**: se usan las lecturas lógicas como dato principal porque no dependen de la caché. Los tiempos se midieron una vez en frío (después de `CHECKPOINT; DBCC DROPCLEANBUFFERS`) y siete veces en caliente; en la tabla se informa la mediana. Los tiempos varían de una ejecución a otra y de una máquina a otra; lo que importa es el orden de magnitud.

## 4. Caso concreto en el sistema de ventas

**Escenario:** el dueño de la tienda pide el listado de ventas de un mes (fecha, cliente y total) para el reporte mensual, y el reporte por categoría (CU-02) filtra las ventas por rango de fechas. Con varios años de ventas, recorrer toda la tabla para quedarse con un mes es un desperdicio.

```sql
SELECT Id_VentaHistorica, fecha_hora, Id_Cliente, total
FROM dbo.VentaHistorica
WHERE fecha_hora >= '2025-01-01T00:00:00'
  AND fecha_hora <  '2025-02-01T00:00:00';
```

| Escenario | Índice |
| :-: | :--- |
| **A** | Ninguno (heap) |
| **B** | `CREATE CLUSTERED INDEX IX_VentaHistorica_fecha ON VentaHistorica (fecha_hora)` |
| **C** | Se borra el anterior y se crea `CREATE NONCLUSTERED INDEX IX_VentaHistorica_fecha_cobertura ON VentaHistorica (fecha_hora) INCLUDE (Id_VentaHistorica, Id_Cliente, total)` |
| Extra | No agrupado solo por `fecha_hora`, sin `INCLUDE` |

## 5. Script de demostración y resultados obtenidos

[`scripts.sql`](scripts.sql) crea y carga la tabla, ejecuta la consulta en los tres escenarios con `STATISTICS TIME` e `IO`, y al final aplica el índice al modelo real. Salida completa de una ejecución con `sqlcmd`: [`evidencias/resultados_scripts.txt`](evidencias/resultados_scripts.txt).

### 5.1. Tabla comparativa

Tabla de 1.200.000 filas (6780 páginas, unos 53 MB). La consulta devuelve 14.880 filas en todos los casos.

| Escenario | Operación principal del plan | Lecturas lógicas | CPU en frío | Tiempo total en frío | CPU en caliente (mediana) | Tiempo total en caliente (mediana) |
| :--- | :--- | :-: | :-: | :-: | :-: | :-: |
| **A. Sin índice** | Table Scan | **6780** | 172 ms | 190 ms | 125 ms | 124 ms |
| **B. Agrupado** | Clustered Index Seek | **92** | 0 ms | 13 ms | 0 ms | 9 ms |
| **C. No agrupado de cobertura** | Index Seek (NonClustered) | **73** | 0 ms | 11 ms | 0 ms | 11 ms |
| Extra: no agrupado sin `INCLUDE` (forzado) | Index Seek + RID Lookup | 14921 | 31 ms | 32 ms | 16 ms | 22 ms |
| Extra: no agrupado sin `INCLUDE` (sin forzar) | Table Scan (el optimizador ignora el índice) | 7059 | 125 ms | 146 ms | 110 ms | 107 ms |

> "0 ms" de CPU significa menos de 1 ms: `STATISTICS TIME` no muestra fracciones. El tiempo total incluye entregar las 14.880 filas al cliente; ejecutado desde SSMS o `sqlcmd` (que además las imprime) da entre 50 y 65 ms en B y C, y alrededor de 155 ms en A (ver `resultados_scripts.txt`).
>
> En la prueba extra sin forzar la tabla tiene 7059 páginas en vez de 6780 porque viene de crear y borrar el índice agrupado, que reescribe el heap.

### 5.2. Planes de ejecución

Los planes reales están guardados en [`evidencias/`](evidencias/) como `.sqlplan` (se abren con doble clic en SSMS y se ven en forma gráfica). Las capturas son de esos mismos planes abiertos en SSMS:

| Escenario | Plan (XML) | Captura en SSMS |
| :-: | :--- | :--- |
| A | [`plan_A_sin_indice.sqlplan`](evidencias/plan_A_sin_indice.sqlplan) | `evidencias/01_plan_sin_indice.png` |
| B | [`plan_B_agrupado.sqlplan`](evidencias/plan_B_agrupado.sqlplan) | `evidencias/02_plan_agrupado.png` |
| C | [`plan_C_no_agrupado_cobertura.sqlplan`](evidencias/plan_C_no_agrupado_cobertura.sqlplan) | `evidencias/03_plan_no_agrupado_cobertura.png` |
| Extra | [`plan_D_no_agrupado_sin_cobertura.sqlplan`](evidencias/plan_D_no_agrupado_sin_cobertura.sqlplan) | `evidencias/04_plan_rid_lookup.png` |

En B y C, además del *seek*, el plan muestra `Constant Scan`, `Compute Scalar`, `Merge Interval` y `Nested Loops`. No es un problema: SQL Server **parametrizó** la consulta automáticamente (reemplazó las fechas fijas por parámetros para reutilizar el plan) y esos operadores solo arman el rango de búsqueda. El trabajo real lo hace el *seek*.

### 5.3. Análisis

- **Sin índice (A):** el motor no tiene forma de saber dónde están las ventas de enero, así que lee las 6780 páginas de la tabla y descarta el 98,8 % de las filas.
- **Agrupado (B):** la tabla queda ordenada por fecha, las ventas de enero están contiguas y el motor baja por el árbol hasta el 1/1/2025 y lee solo ese tramo: **92 lecturas, 98,6 % menos** que A, y el tiempo baja de ~124 ms a ~10 ms.
- **No agrupado de cobertura (C):** encuentra el rango igual que B, pero lee todavía menos (**73 lecturas, 98,9 % menos que A**) porque sus hojas solo guardan `fecha_hora`, `Id_VentaHistorica`, `Id_Cliente` y `total`; las hojas del agrupado guardan la fila completa (incluido `canal`), así que entran menos filas por página. Como el índice tiene todas las columnas de la consulta, no hay RID Lookup.
- **Por qué hace falta el `INCLUDE` (extra):** con un índice no agrupado solo por fecha, por cada una de las 14.880 filas hay que ir a la tabla a buscar `Id_Cliente` y `total` (un RID Lookup por fila). Eso da 14.921 lecturas, **más que recorrer toda la tabla**. Por eso, si no se fuerza, el optimizador lo descarta y vuelve al Table Scan. Un índice no agrupado sin cobertura solo sirve cuando el filtro devuelve muy pocas filas.
- **B y C rinden parecido en esta consulta.** La diferencia está en el diseño: solo puede haber un agrupado por tabla, mientras que no agrupados puede haber varios, uno por cada consulta importante.

### 5.4. Aplicación al modelo real

En `Venta`, el índice agrupado ya es la PK (`PK_Venta` sobre `Id_Venta`). **Conviene dejarlo así**: es una clave angosta (4 bytes) y creciente, por lo que las ventas nuevas se agregan al final sin reordenar páginas, y es la que usan el `JOIN` con `Detalle_Venta` y las claves foráneas. Cambiar el agrupado a `fecha_hora` obligaría a cambiar la PK a no agrupada y haría más pesados todos los índices no agrupados (que guardan la clave del agrupado).

Para las consultas por fecha se aplica el resultado del escenario C:

```sql
CREATE NONCLUSTERED INDEX IX_Venta_fecha_hora
    ON dbo.Venta (fecha_hora)
    INCLUDE (Id_Cliente, Id_metodo_pago, total);
```

`Id_Venta` no va en el `INCLUDE` porque todo índice no agrupado ya guarda la clave del agrupado. Este índice cubre el filtro por fechas del CU-02 y los reportes mensuales. Con las 10 ventas de prueba la tabla entra en una página y el optimizador puede seguir eligiendo un scan; el beneficio aparece con el volumen, como muestra el experimento.

### 5.5. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Abrir [`scripts.sql`](scripts.sql) en SSMS y activar **Incluir plan de ejecución real** (Ctrl+M).
3. Ejecutar el paso 0 (crea y carga `VentaHistorica`; tarda unos segundos).
4. Ejecutar cada escenario por separado y anotar, de la pestaña **Mensajes**, el tiempo de CPU, el tiempo transcurrido y las lecturas lógicas, y de la pestaña **Plan de ejecución**, la operación principal.
5. Al terminar, se puede borrar la tabla de pruebas con el `DROP TABLE` comentado al final del script.

## 6. Integración con los demás temas

- **Consultas de la Etapa IV:** el CU-02 filtra `Venta` por `fecha_hora`; con `IX_Venta_fecha_hora` ese filtro pasa a ser un *seek*.
- **Transacciones:** cada venta nueva tiene que actualizar también `IX_Venta_fecha_hora`. Es un costo chico (un índice angosto y una fila por venta), pero es la razón para no crear índices de más.
- **Reescritura de consultas (complemento):** un índice solo se aprovecha si el filtro es SARGable. `WHERE MONTH(fecha_hora) = 1` no puede usar `IX_Venta_fecha_hora` y vuelve al scan; `WHERE fecha_hora >= ... AND fecha_hora < ...` sí. Ese es el caso 1 de [`../optimizacion_consultas.md`](../optimizacion_consultas.md).

## 7. Complemento: reescritura de consultas

Antes del experimento con índices se documentaron técnicas de reescritura de consultas sobre el mismo modelo (SARGabilidad, tablas temporales, CTE, agregación condicional con `SUM` + `CASE` y `TOP WITH TIES`). Están en [`../optimizacion_consultas.md`](../optimizacion_consultas.md) y [`../optimizacion_consultas.sql`](../optimizacion_consultas.sql). Ambos enfoques se complementan: la reescritura hace que la consulta **pueda** usar un índice, y el índice hace que esa consulta lea pocas páginas.

## 8. Limitaciones

- **Los tiempos dependen de la máquina y de la caché.** Por eso el dato principal de la comparación son las lecturas lógicas, que se repiten igual en cualquier equipo con los mismos datos.
- **`VentaHistorica` es una tabla de pruebas.** No tiene claves foráneas ni detalle; solo sirve para medir.
- **Los índices tienen costo de mantenimiento.** No se midió el impacto en los `INSERT`; con una venta por vez es despreciable, pero en una carga masiva conviene crear los índices después de cargar.
- **SQL Server Express** limita la memoria del buffer y el tamaño de la base, y no permite crear índices en línea (`ONLINE = ON`). Para el volumen de esta tienda no es un problema.
