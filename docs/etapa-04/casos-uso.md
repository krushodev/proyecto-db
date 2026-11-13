# Casos de uso – Etapa IV – Intensa Jeans

Un caso de uso describe las acciones de un sistema desde el punto de vista del usuario: son los servicios o funciones que el sistema ofrece a sus actores. Este documento modela con esa técnica las necesidades de información de la etapa IV: el comprobante de venta, el reporte agregado y la consulta de negocio avanzada.

---

## 1. Requerimientos relevados

Intensa Jeans necesita obtener información de las ventas registradas en la base de datos `tienda_ropa`. Hay dos tipos de usuarios: el **personal de mostrador** y el **administrador del negocio**.

El **personal de mostrador** podrá:

1. Emitir el comprobante de una venta, con su encabezado, su detalle, los subtotales por renglón y el total acumulado.

El **administrador del negocio** podrá:

1. Realizar todas las operaciones del personal de mostrador.
2. Consultar el total vendido por categoría de producto en un rango de fechas.
3. Identificar los clientes de mayor valor, es decir, los que acumulan un gasto superior a un monto mínimo.

Además, se relevaron necesidades complementarias:

- Todos los importes (subtotales y totales) se calculan a partir del precio unitario histórico guardado en el detalle de la venta, por lo que ese cálculo es común a las tres consultas.
- Es deseable poder acotar el reporte por categoría a un canal de venta determinado.
- Es deseable conocer con qué métodos de pago compra cada cliente de mayor valor.

---

## 2. Actores

| Actor | Descripción |
| :--- | :--- |
| **Personal de mostrador** | Registra las ventas en el local y necesita entregar el comprobante al cliente en el momento. |
| **Administrador del negocio** | Gestiona el catálogo, los precios y las liquidaciones, y analiza las ventas. Puede hacer todo lo que hace el personal de mostrador (relación de generalización). |

---

## 3. Casos de uso identificados

| Código | Caso de uso | Tipo | Actor |
| :--- | :--- | :--- | :--- |
| **CU-01** | Emitir comprobante de venta | Principal | Personal de mostrador, Administrador |
| **CU-02** | Consultar ventas por categoría en un rango de fechas | Principal | Administrador |
| **CU-03** | Identificar clientes de mayor valor | Principal | Administrador |
| **CU-04** | Calcular importes de la venta | Incluido (`<<include>>`) | – |
| **CU-05** | Filtrar por canal de venta | Extensión (`<<extend>>`) | Administrador |
| **CU-06** | Desglosar por método de pago | Extensión (`<<extend>>`) | Administrador |

Los casos CU-01, CU-02 y CU-03 se implementan con los scripts de la etapa. Los casos CU-04, CU-05 y CU-06 modelan funcionalidad común u opcional dentro de esos mismos scripts.

---

## 4. Especificación de los casos de uso

### CU-01 – Emitir comprobante de venta

| Campo | Descripción |
| :--- | :--- |
| **Actor principal** | Personal de mostrador (también el administrador) |
| **Objetivo** | Obtener el comprobante de una venta con su encabezado, el detalle de productos y los importes calculados. |
| **Precondiciones** | La venta está registrada y tiene al menos un renglón de detalle. Se conoce su número de venta. |
| **Postcondición** | El actor dispone del comprobante para entregar o archivar. El sistema no modifica ningún dato. |
| **Relaciones** | `<<include>>` CU-04 Calcular importes de la venta |
| **Tablas involucradas** | `Venta`, `Cliente`, `Metodo_pago`, `Detalle_Venta`, `Producto`, `Talle` |
| **Reglas de negocio** | RN.04, RN.07, RN.08 |

**Flujo principal**

1. El actor indica el número de la venta.
2. El sistema recupera el encabezado: número, fecha y hora, canal, cliente y método de pago.
3. El sistema recupera cada renglón: producto, talle, cantidad y precio unitario registrado.
4. El sistema incluye CU-04 para calcular los subtotales y el total acumulado.
5. El sistema muestra el descuento aplicado por el método de pago y el total final.

**Flujos alternativos**

- **A1 – Venta inexistente:** si el número no corresponde a ninguna venta, la consulta no devuelve resultados.
- **A2 – Precio modificado en el catálogo:** si el precio del producto cambió después de la venta, el comprobante conserva el precio histórico del detalle (RN.08).

---

### CU-02 – Consultar ventas por categoría en un rango de fechas

| Campo | Descripción |
| :--- | :--- |
| **Actor principal** | Administrador del negocio |
| **Objetivo** | Conocer cuánto y qué se vendió en cada categoría dentro de un período, para decidir sobre catálogo y liquidaciones. |
| **Precondiciones** | Existen ventas registradas. Se define una fecha de inicio y una de fin. |
| **Postcondición** | El actor obtiene un informe agregado por categoría. El sistema no modifica ningún dato. |
| **Relaciones** | `<<include>>` CU-04 Calcular importes de la venta; extendido por CU-05 Filtrar por canal de venta |
| **Tablas involucradas** | `Venta`, `Detalle_Venta`, `Producto`, `Categoria` |
| **Reglas de negocio** | RN.03, RN.08 |
| **Punto de extensión** | Selección de ventas del período (donde se puede acotar por canal) |

**Flujo principal**

1. El actor indica la fecha de inicio y la fecha de fin.
2. El sistema selecciona las ventas cuya fecha esté dentro del rango.
3. El sistema agrupa los renglones por categoría del producto.
4. El sistema incluye CU-04 para calcular el monto de cada renglón.
5. Para cada categoría, el sistema obtiene la cantidad de ventas, las unidades vendidas y el monto total.
6. El sistema muestra el informe ordenado de mayor a menor monto.

**Flujos alternativos**

- **A1 – Sin ventas en el período:** el informe se devuelve vacío.
- **A2 – Categoría sin ventas:** no aparece en el informe.
- **A3 – Filtro por canal:** si el actor elige un canal, se ejecuta CU-05 y el informe considera solo esas ventas.

---

### CU-03 – Identificar clientes de mayor valor

| Campo | Descripción |
| :--- | :--- |
| **Actor principal** | Administrador del negocio |
| **Objetivo** | Identificar a los clientes recurrentes que más gastan, para orientar promociones o acciones de fidelización. |
| **Precondiciones** | Existen clientes con ventas registradas. |
| **Postcondición** | El actor obtiene la lista de clientes que cumplen ambos criterios. El sistema no modifica ningún dato. |
| **Relaciones** | `<<include>>` CU-04 Calcular importes de la venta; extendido por CU-06 Desglosar por método de pago |
| **Tablas involucradas** | `Cliente`, `Venta`, `Detalle_Venta`, `Metodo_pago` |
| **Reglas de negocio** | RN.04, RN.09 |
| **Punto de extensión** | Resumen de ventas de cada cliente (donde se puede desglosar por método de pago) |

**Flujo principal**

1. El actor indica el período a analizar (por ejemplo, un año).
2. El sistema resume cada venta del período con su total y la cantidad de prendas del detalle.
3. El sistema incluye CU-04 para calcular los importes a partir del detalle.
4. El sistema agrupa por cliente y obtiene la cantidad de ventas, las prendas, el gasto acumulado y el ticket promedio.
5. El sistema calcula el gasto promedio por cliente entre todos los que compraron en el período.
6. El sistema conserva solo a los clientes con al menos dos ventas y un gasto igual o superior a ese promedio.
7. El sistema muestra la lista ordenada de mayor a menor gasto.

**Flujos alternativos**

- **A1 – Ningún cliente cumple el criterio:** el resultado se devuelve vacío.
- **A2 – Cliente con una única venta:** no se incluye, aunque su gasto supere el promedio.
- **A3 – Desglose por método de pago:** el sistema ejecuta CU-06 y agrega, para cada cliente, la cantidad de ventas pagadas con efectivo, tarjeta, transferencia y otros medios.

---

### CU-04 – Calcular importes de la venta (incluido)

| Campo | Descripción |
| :--- | :--- |
| **Tipo** | Caso de uso incluido: lo necesitan CU-01, CU-02 y CU-03 para cumplir su tarea. |
| **Objetivo** | Calcular los importes a partir del detalle de la venta. |
| **Precondiciones** | La venta tiene renglones de detalle con precio unitario y cantidad. |
| **Postcondición** | Quedan calculados el subtotal de cada renglón y el total acumulado. |
| **Tablas involucradas** | `Detalle_Venta`, `Venta` |
| **Reglas de negocio** | RN.08 |

**Flujo principal**

1. El sistema toma la cantidad y el precio unitario histórico de cada renglón.
2. El sistema calcula el subtotal de cada renglón (cantidad × precio unitario).
3. El sistema suma los subtotales para obtener el total acumulado.

---

### CU-05 – Filtrar por canal de venta (extensión)

| Campo | Descripción |
| :--- | :--- |
| **Tipo** | Caso de uso de extensión: comportamiento opcional que amplía CU-02. |
| **Condición** | El actor elige un canal de venta (por ejemplo, `Local` o `Web`). |
| **Objetivo** | Acotar el informe por categoría a las ventas de un único canal. |
| **Postcondición** | El informe de CU-02 considera solo las ventas del canal elegido. |
| **Tablas involucradas** | `Venta` |

---

### CU-06 – Desglosar por método de pago (extensión)

| Campo | Descripción |
| :--- | :--- |
| **Tipo** | Caso de uso de extensión: comportamiento opcional que amplía CU-03. |
| **Condición** | El actor quiere conocer los hábitos de pago de los clientes de mayor valor. |
| **Objetivo** | Mostrar, para cada cliente de la lista, cuántas ventas pagó con cada método (efectivo, tarjeta, transferencia y otros). |
| **Postcondición** | La lista de CU-03 incluye una columna por método de pago. |
| **Tablas involucradas** | `Venta`, `Metodo_pago` |

--- | :--- |
| **Tipo** | Caso de uso de extensión: comportamiento opcional que amplía CU-03. |
| **Condición** | El actor elige un método de pago (por ejemplo, `Efectivo`). |
| **Objetivo** | Acotar la lista de clientes de mayor valor a las ventas pagadas con un método. |
| **Postcondición** | La lista de CU-03 considera solo las ventas con el método elegido. |
| **Tablas involucradas** | `Venta`, `Metodo_pago` |

---

## 5. Trazabilidad

| Necesidad del enunciado | Caso de uso | Archivo |
| :--- | :--- | :--- |
| Factura/Comprobante: encabezado, detalle, subtotales por renglón y total acumulado | CU-01 (incluye CU-04) | `comprobante-venta.md` |
| Reporte agregado por categoría en un rango de fechas (`GROUP BY`, `SUM`, `COUNT`) | CU-02 (incluye CU-04, extendido por CU-05) | `reporte-agregado.md` |
| Consulta avanzada con al menos 3 tablas con `JOIN` y filtro con `HAVING` o subconsultas | CU-03 (incluye CU-04, extendido por CU-06) | `consulta-avanzada.md` |
