# Triggers de auditoría – Etapa V – Intensa Jeans

**Script:** [`scripts.sql`](scripts.sql)
**Evidencias:** [`evidencias/`](evidencias/)
**Reglas de negocio:** RN.02, RN.05, RN.06

---

## 1. Necesidad

_Pendiente: qué se quiere registrar y por qué (trazabilidad de precios, liquidaciones y stock)._

## 2. Qué es un trigger

_Pendiente: definición, eventos (`INSERT`, `UPDATE`, `DELETE`), tablas `inserted` y `deleted`, `AFTER` vs `INSTEAD OF`, sintaxis básica._

## 3. Diseño de la auditoría

_Pendiente: tabla `Auditoria` (columnas, tipos), tablas auditadas (`Producto`, `Producto_Talle`) y campos vigilados._

## 4. Implementación

_Pendiente: explicación de cada trigger y decisiones (solo registrar si el valor cambió, actualizaciones de varias filas, `NULL`)._

## 5. Pruebas

_Pendiente: casos de éxito, de error y límite, con referencia a las capturas en `evidencias/`._

## 6. Integración con seguridad

_Pendiente: permisos sobre la tabla de auditoría (ver sección 8 de `docs/etapa-05/seguridad.md`)._

## 7. Limitaciones

_Pendiente._

## 8. Cómo probar

1. Ejecutar `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql`.
2. Ejecutar `scripts.sql`.
3. Ejecutar las pruebas del script y consultar la tabla `Auditoria`.
