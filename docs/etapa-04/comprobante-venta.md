# Comprobante de venta – Etapa IV – Intensa Jeans

**Caso de uso:** CU-01 – Emitir comprobante de venta (incluye CU-04 – Calcular importes)
**Script:** [`comprobante_venta.sql`](comprobante_venta.sql)
**Reglas de negocio:** RN.04, RN.07, RN.08

---

## 1. Necesidad de información

Consolidar en una sola consulta el **encabezado** de una venta (número, fecha y hora, canal, cliente y método de pago) con su **detalle** (producto, talle, cantidad y precio unitario), calculando el **subtotal de cada renglón** y el **total acumulado**. Lo usa el personal de mostrador para entregar el comprobante al cliente.

## 2. Estrategia SQL

| Elemento | Decisión |
| :--- | :--- |
| **Tablas** | `Venta`, `Cliente`, `Metodo_pago`, `Detalle_Venta`, `Producto`, `Talle` (6 `JOIN` internos) |
| **Parámetro** | `@id_venta`: número de la venta a emitir |
| **Subtotal por renglón** | `cantidad * precio_unitario` |
| **Total acumulado** | `SUM(...) OVER (PARTITION BY Id_Venta ORDER BY nro_item ROWS UNBOUNDED PRECEDING)`: suma corrida renglón a renglón, sin `GROUP BY`, para conservar el detalle completo |
| **Precio** | Se toma de `Detalle_Venta.precio_unitario` y no de `Producto.precio_lista`, de modo que un cambio posterior de precio no altera el comprobante (RN.08) |

El script tiene tres consultas:

- **1.a – Comprobante renglón por renglón:** encabezado repetido en cada fila, más subtotal por renglón y total acumulado.
- **1.b – Pie del comprobante:** subtotal de renglones, descuento por método de pago (RN.07) y total final. Compara el total recalculado con `Venta.total` (`control_ok`).
- **1.c – Control global:** lista las ventas cuyo total registrado no coincide con su detalle.

## 3. Resultado esperado (venta 1)

**1.a**

| nro_item | producto | talle | cantidad | precio_unitario | subtotal_renglon | total_acumulado |
| :-: | :-- | :-: | :-: | --: | --: | --: |
| 1 | Jean Mom Tiro Alto | 38 | 1 | 45000.00 | 45000.00 | 45000.00 |
| 2 | Remera Básica Algodón | M | 2 | 15000.00 | 30000.00 | 75000.00 |

Encabezado: venta 1, 2026-08-03 10:15, canal Local, cliente Fernández, Lucía (DNI 38456123), método Efectivo.

**1.b**

| metodo_pago | pct_descuento | subtotal_renglones | descuento | total_calculado | total_registrado | control_ok |
| :-- | --: | --: | --: | --: | --: | :-: |
| Efectivo | 15.00 | 75000.00 | 11250.00 | 63750.00 | 63750.00 | 1 |

**1.c:** 0 filas, es decir, los totales de las 10 ventas de prueba son consistentes con su detalle.

## 4. Flujos alternativos (según CU-01)

- **A1 – Venta inexistente:** con un `@id_venta` que no existe, las consultas no devuelven filas.
- **A2 – Precio modificado en el catálogo:** si se actualiza `Producto.precio_lista`, el comprobante no cambia, porque usa el precio histórico del detalle.

## 5. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Ejecutar `comprobante_venta.sql`.
3. Cambiar `@id_venta` (1 a 10) para emitir otros comprobantes. Por ejemplo, la venta 5 tiene 3 renglones y paga con tarjeta de débito (5 %).
