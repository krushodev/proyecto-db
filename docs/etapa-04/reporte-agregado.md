# Reporte agregado – Etapa IV – Intensa Jeans

**Caso de uso:** CU-02 – Consultar ventas por categoría en un rango de fechas (incluye CU-04 – Calcular importes)
**Script:** [`reporte_agregado.sql`](reporte_agregado.sql)
**Reglas de negocio:** RN.03, RN.06, RN.08

---

## 1. Necesidad de información

Conocer el **total de ventas por categoría de producto** dentro de un **rango de fechas**: cuántas ventas hubo, cuántas unidades se vendieron y cuánto se facturó en cada categoría. Lo usa el administrador para tomar decisiones sobre el catálogo y las liquidaciones.

El enunciado permite agrupar por vendedor o por categoría. Como el modelo no tiene la entidad `Vendedor`, el reporte se agrupa por **categoría** (RN.03: cada producto pertenece a una única categoría).

## 2. Estrategia SQL

| Elemento | Decisión |
| :--- | :--- |
| **Tablas** | `Categoria`, `Producto`, `Detalle_Venta`, `Venta` |
| **Parámetros** | `@fecha_desde` y `@fecha_hasta`: rango de fechas del reporte, ambos inclusive |
| **Filtro de fechas** | `fecha_hora >= @fecha_desde AND fecha_hora < DATEADD(DAY, 1, @fecha_hasta)`, para incluir todas las ventas del último día sin importar la hora |
| **Agrupamiento** | `GROUP BY` por categoría |
| **cant_ventas** | `COUNT(DISTINCT Id_Venta)`: una venta con dos productos de la misma categoría cuenta una sola vez |
| **cant_items** | `COUNT(nro_item)`: renglones de detalle vendidos |
| **unidades** | `SUM(cantidad)` |
| **total_vendido** | `SUM(subtotal)`: importe de los renglones, con el precio de liquidación ya aplicado (RN.06) y tomado del detalle de la venta (RN.08). No incluye el descuento por método de pago, porque ese descuento es de la venta completa y no se puede repartir por categoría |
| **ticket_promedio** | `total_vendido / cant_ventas`, con `NULLIF` para evitar la división por cero |

El script tiene dos consultas:

- **2.a – Reporte por categoría:** usa `LEFT JOIN` desde `Categoria`, de modo que las categorías sin ventas en el rango también aparecen, con valores en 0 (`COALESCE`). Se ordena por `total_vendido` de mayor a menor.
- **2.b – Reporte con total general:** usa `GROUP BY ROLLUP`, que agrega al final una fila `TOTAL GENERAL` con la suma de todas las categorías. Muestra solo las categorías con ventas.

## 3. Resultado esperado (01/08/2026 al 30/09/2026)

Con los datos de prueba de la etapa III, las 10 ventas caen dentro del rango.

**2.a**

| categoria | cant_ventas | cant_items | unidades | total_vendido | ticket_promedio |
| :-- | :-: | :-: | :-: | --: | --: |
| Jeans Mujer | 3 | 3 | 4 | 168600.00 | 56200.00 |
| Jeans Hombre | 3 | 3 | 3 | 135100.00 | 45033.33 |
| Remeras | 4 | 4 | 7 | 105000.00 | 26250.00 |
| Camperas | 1 | 1 | 1 | 68000.00 | 68000.00 |
| Shorts | 2 | 2 | 2 | 56000.00 | 28000.00 |
| Polleras | 1 | 1 | 1 | 35000.00 | 35000.00 |
| Camisas | 1 | 1 | 1 | 34200.00 | 34200.00 |
| Accesorios | 2 | 2 | 2 | 27000.00 | 13500.00 |

**2.b:** las mismas 8 categorías y, al final, la fila `TOTAL GENERAL` con 10 ventas, 21 unidades y 628900.00 de total vendido. La fila de total cuenta 10 ventas y no la suma de la columna, porque `COUNT(DISTINCT)` no repite una venta que tiene productos de varias categorías.

## 4. Flujos alternativos (según CU-02)

- **A1 – Rango sin ventas:** la consulta 2.a muestra todas las categorías con valores en 0, y la 2.b no devuelve filas.
- **A2 – Categoría sin ventas:** en la 2.a aparece con valores en 0, para que el administrador vea qué categorías no se movieron en el período. En la 2.b no aparece.
- **A3 – Filtro por canal (CU-05):** se puede acotar el reporte agregando `AND v.canal = @canal` a la condición de fechas.

## 5. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Ejecutar `reporte_agregado.sql`.
3. Cambiar `@fecha_desde` y `@fecha_hasta` para probar otros rangos. Por ejemplo, del 01/09/2026 al 30/09/2026 se consideran solo las ventas 8, 9 y 10.
