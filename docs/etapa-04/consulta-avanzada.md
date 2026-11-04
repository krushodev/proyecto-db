# Documentación del Caso de Uso: Consulta de Negocio Avanzada

## 1. Identificación del Caso de Uso

- **Nombre del Caso de Uso:** CU-03 - Análisis y Segmentación de Clientes VIP y Hábitos de Pago.
- **Módulo:** Ventas & Analítica de Clientes.
- **Tablas Involucradas:** `Cliente`, `Venta`, `Detalle_Venta`, `Metodo_pago`, `Producto`.
- **Motor Objetivo:** Microsoft SQL Server.

## 2. Descripción Funcional y Objetivo de Negocio

El objetivo de esta consulta avanzada es identificar el segmento de clientes con mayor impacto comercial para el negocio (**Clientes VIP**).

Para ser considerado dentro de este segmento, el cliente debe cumplir con dos criterios combinados:

1. Haber realizado al menos dos (2) operaciones de compra independientes dentro del período anual analizado.
2. Registrar un gasto acumulado superior al **promedio global de gasto por cliente** en el mismo período.

Adicionalmente, el reporte desglosa las prendas totales adquiridas, el ticket promedio por compra y la frecuencia de uso de cada medio de pago (`Efectivo`, `Tarjeta`, `Transferencia`).

## 3. Aspectos Técnicos de la Consulta T-SQL

### A. Estructuración con CTEs (Common Table Expressions)

- **`ResumenCliente`:** Agrupa las transacciones en la tabla `Venta` y `Detalle_Venta` utilizando `GROUP BY` y `HAVING` para filtrar a los clientes recurrentes sin repetir lecturas sobre la base de datos.
- **`PromedioGlobal`:** Calcula el umbral dinámico de gasto promedio para comparar a cada cliente contra la media de la tienda.

### B. Optimización de Filtros (SARGability)

- La condición de fecha utiliza un rango estricto (`fecha_venta >= '2026-01-01' AND fecha_venta < '2027-01-01'`) en lugar de funciones como `YEAR(fecha_venta)`, garantizando la eficiencia en la evaluación del motor.

### C. Agregación Condicional (`SUM + CASE`)

- Para determinar la preferencia en los métodos de pago sin realizar múltiples `JOIN` repetidos o subconsultas, se emplea la técnica `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`.

## 4. Estructura de Salida Esperada

| Columna             | Tipo de Dato    | Descripción                              |
| :------------------ | :-------------- | :--------------------------------------- |
| `id_cliente`        | `INT`           | Identificador único del cliente.         |
| `nombre`            | `VARCHAR`       | Nombre del cliente.                      |
| `apellido`          | `VARCHAR`       | Apellido del cliente.                    |
| `email`             | `VARCHAR`       | Correo electrónico de contacto.          |
| `cantidad_ventas`   | `INT`           | Total de ventas registradas.             |
| `total_prendas`     | `INT`           | Sumatoria total de unidades compradas.   |
| `gasto_total`       | `DECIMAL(10,2)` | Monto acumulado consumido.               |
| `ticket_promedio`   | `DECIMAL(10,2)` | Promedio gastado por compra.             |
| `uso_efectivo`      | `INT`           | Compras abonadas en efectivo.            |
| `uso_tarjeta`       | `INT`           | Compras abonadas con tarjeta.            |
| `uso_transferencia` | `INT`           | Compras abonadas mediante transferencia. |

## 5. Archivos Relacionados

- Script SQL ejecutable: `docs/etapa-04/consulta_avanzada.sql`
