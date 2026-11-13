# Documentación del Caso de Uso: Consulta de Negocio Avanzada

## 1. Identificación del Caso de Uso

- **Nombre del Caso de Uso:** CU-03 - Análisis y Segmentación de Clientes VIP y Hábitos de Pago.
- **Módulo:** Ventas & Analítica de Clientes.
- **Tablas Involucradas:** `Cliente`, `Venta`, `Detalle_Venta`, `Metodo_pago`.
- **Motor Objetivo:** Microsoft SQL Server (base `tienda_ropa`).

## 2. Descripción Funcional y Objetivo de Negocio

El objetivo de esta consulta avanzada es identificar el segmento de clientes con mayor impacto comercial para el negocio (**Clientes VIP**).

Para ser considerado dentro de este segmento, el cliente debe cumplir con dos criterios combinados:

1. Haber realizado al menos dos (2) ventas independientes dentro del período anual analizado.
2. Registrar un gasto acumulado igual o superior al **promedio de gasto por cliente** del mismo período. Ese promedio se calcula sobre **todos** los clientes que compraron, no solo sobre los recurrentes.

Adicionalmente, el reporte desglosa las prendas totales adquiridas, el ticket promedio por venta y la cantidad de ventas pagadas con cada medio de pago (`Efectivo`, `Tarjeta`, `Transferencia bancaria` y otros medios como Mercado Pago o Gift card).

## 3. Aspectos Técnicos de la Consulta T-SQL

### A. Estructuración con CTEs (Common Table Expressions)

- **`PrendasPorVenta`:** resume `Detalle_Venta` a una fila por venta con la cantidad de prendas. Se hace antes de unir con `Venta` para no duplicar el total de la venta una vez por cada renglón del detalle.
- **`GastoPorCliente`:** una fila por cliente con cantidad de ventas, prendas, gasto, ticket promedio y desglose por medio de pago.
- **`PromedioGlobal`:** calcula el umbral de gasto promedio sobre todos los clientes que compraron. La condición de "2 o más ventas" se aplica recién en la consulta final, para que no altere ese promedio.

### B. Optimización de Filtros (SARGability)

- La condición de fecha usa un rango (`fecha_hora >= '2026-01-01' AND fecha_hora < '2027-01-01'`) en lugar de funciones como `YEAR(fecha_hora)`, para que el motor pueda usar índices sobre la columna.

### C. Agregación Condicional (`SUM + CASE`)

- Para determinar el medio de pago sin hacer varias consultas o `JOIN` repetidos se emplea `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`. Las tarjetas (débito y crédito en sus distintas cuotas) se agrupan con `LIKE 'Tarjeta%'`.

## 4. Estructura de Salida Esperada

| Columna             | Tipo de Dato    | Descripción                                                  |
| :------------------ | :-------------- | :----------------------------------------------------------- |
| `Id_Cliente`        | `INT`           | Identificador único del cliente.                             |
| `nombre`            | `VARCHAR`       | Nombre del cliente.                                          |
| `apellido`          | `VARCHAR`       | Apellido del cliente.                                        |
| `email`             | `VARCHAR`       | Correo electrónico de contacto.                              |
| `cantidad_ventas`   | `INT`           | Total de ventas registradas en el período.                   |
| `total_prendas`     | `INT`           | Sumatoria total de unidades compradas.                       |
| `gasto_total`       | `DECIMAL(10,2)` | Monto acumulado (suma de `Venta.total`).                     |
| `ticket_promedio`   | `DECIMAL(10,2)` | Promedio gastado por venta.                                  |
| `uso_efectivo`      | `INT`           | Ventas abonadas en efectivo.                                 |
| `uso_tarjeta`       | `INT`           | Ventas abonadas con tarjeta (débito o crédito).              |
| `uso_transferencia` | `INT`           | Ventas abonadas por transferencia bancaria.                  |
| `uso_otros`         | `INT`           | Ventas abonadas con otros medios (Mercado Pago, Gift card).  |

## 5. Resultado Esperado con los Datos de Prueba

En el DML cargado, solo el cliente 1 (Lucía Fernández) tiene dos ventas (la 1 y la 8). El promedio de gasto entre los 9 clientes que compraron es aproximadamente 65.362,22, y el gasto de Lucía lo supera. La consulta devuelve **una fila**:

| Id_Cliente | cantidad_ventas | total_prendas | gasto_total | ticket_promedio | uso_efectivo | uso_tarjeta | uso_transferencia | uso_otros |
| :--------- | :-------------- | :------------ | :---------- | :-------------- | :----------- | :---------- | :---------------- | :-------- |
| 1          | 2               | 5             | 145950.00   | 72975.00        | 1            | 1           | 0                 | 0         |

## 6. Archivos Relacionados

- Script SQL ejecutable: `docs/etapa-04/consulta_avanzada.sql`
