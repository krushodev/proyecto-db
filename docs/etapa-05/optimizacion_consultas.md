# Etapa 05: Optimización de Consultas SQL

## 1. Introducción

La optimización de consultas SQL no depende únicamente de la infraestructura o estructuras avanzadas del motor, sino en gran medida de cómo escribimos el código T-SQL. Escribir consultas eficientes reduce el consumo de CPU, disminuye el uso de memoria RAM temporal en el servidor y acelera la respuesta del sistema.

En esta etapa se documentan las mejores prácticas de refactorización de código aplicadas al modelo de datos del proyecto (`COMPRA`, `DETALLEDECOMPRA`, `CLIENTE`, `METODO_DE_PAGO`).

---

## 2. Principios y Técnicas Aplicadas

### A. SARGabilidad (Search Argumentable)

Una consulta es **SARGable** cuando el motor de base de datos puede evaluar las condiciones del `WHERE` de forma directa sobre los datos originales, sin tener que transformar cada fila mediante funciones.

- **Anti-patrón (Mal uso):** Encerrar columnas en funciones como `MONTH(fecha)`, `YEAR(fecha)`, `LEFT(nombre, 1)`.
- **Solución Eficiente:** Usar comparaciones de rango directo (ej. `fecha >= '2026-01-01' AND fecha < '2026-04-01'`) o patrones `LIKE 'M%'`.

### B. Evitar Subconsultas Repetidas (Tablas Auxiliares y CTEs)

Cuando una consulta requiere calcular un total o resumen (como la suma de un detalle de venta) para usarlo en filtros o mostrarlo en pantalla, escribir subconsultas dentro de la cláusula `SELECT` ejecuta esa subconsulta repetidamente por cada fila de la tabla principal.

- **Uso de Tablas Temporales (`#`):** Permite procesar los datos de forma intermedia, guardarlos temporalmente en disco/memoria y reutilizarlos limpia y rápidamente.
- **Uso de Expresiones de Tabla Común (`WITH CTE`):** Permite aislar lógicamente agregaciones (`GROUP BY`) antes de realizar los `JOIN`, evitando la duplicación innecesaria de filas en memoria.

### C. Agregación Condicional (`SUM` / `COUNT` + `CASE`)

En lugar de ejecutar 3 o 4 consultas separadas para calcular totales por categorías o métodos de pago, se utiliza la combinación de `SUM(CASE WHEN ... THEN ... END)` dentro de un solo `SELECT`. Esto permite procesar la tabla **una sola vez**.

### D. Manejo Correcto de Empates (`TOP WITH TIES`)

Al consultar rankings o los valores más altos/bajos de una tabla, la cláusula `TOP N` corta la lista de forma arbitraria. Al agregar `WITH TIES` junto a un `ORDER BY`, SQL Server garantiza que si existen registros con la misma puntuación en el límite fijado, se incluyan todos en el resultado final para mantener la integridad de los datos reportados.

---

## 3. Resumen de Buenas Prácticas de Sintaxis

1. **Evitar el uso de `SELECT *`:** Especificar únicamente las columnas necesarias para reducir el consumo de ancho de banda y memoria.
2. **Espaciado y Delimitación:** Usar alias limpios (ej. `[Día de la semana]` o `dia_semana`) para evitar errores de sintaxis al incluir espacios.
3. **Independencia de Idioma:** En funciones de fecha como `DATEPART(dw, fecha)`, utilizar valores numéricos combinados con `SET DATEFIRST` para evitar fallos si el servidor está configurado en inglés o español.

---

## 4. Archivos Relacionados

- Script ejecutable: `docs/etapa-05/optimizacion_consultas.sql`
