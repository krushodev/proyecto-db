## 1. Introducción y Propósito

El presente documento expone y justifica las decisiones de diseño adoptadas en el modelado conceptual y relacional de la base de datos para el sistema **Intensa Jeans**. El objetivo principal es explicitar el razonamiento técnico y de negocio detrás de la estructura de tablas, selección de claves, estrategias de trazabilidad y normalización, asegurando el cumplimiento de los requerimientos funcionales y reglas de negocio (RN.01 a RN.09).

## 2. Decisiones de Diseño por Módulo

### 2.1. Gestión de Variantes, Talles y Stock por Prenda (RN.01, RN.02)

#### Planteo del problema

Una misma prenda de indumentaria (por ejemplo, "Jean recto azul") posee múltiples talles, y cada talle mantiene un control de inventario independiente. Además, existen artículos de categoría "Accesorios" que no requieren diferenciación de talle.

#### Alternativas consideradas

1. **Crear un registro independiente en `Producto` por cada combinación de prenda y talle:**

   *Desventaja:* Provoca redundancia masiva de datos generales del producto (nombre, descripción, categoría, precio de lista, flags de liquidación).

2. **Modelo N:M con tabla intermedia `Producto_Talle`:**

   *Ventaja:* Desacopla la entidad abstracta del catálogo (`Producto`) del inventario físico disponible por talle (`Producto_Talle`).

#### Decisión adoptada

Se implementó el patrón N:M mediante la entidad asociativa **`Producto_Talle`**:

* **`Producto`:** Contiene los atributos descriptivos generales y de precio de lista base.

* **`Talle`:** Contiene el catálogo global de talles (ej.: S, M, L, XL, 38, 40, 42).

* **`Producto_Talle`:** Almacena la Clave Primaria Compuesta (`Id_Producto`, `Id_Talle`) y el atributo **`stock`**.

#### Estrategia para Accesorios

Para cumplir la regla RN.01 sin violar la integridad referencial ni admitir valores `NULL` en claves foráneas:

* Se define en la tabla `Talle` un registro especial/genérico denominado **"Talle Único"** (o "Talle Genérico").

* Todos los accesorios se vinculan en `Producto_Talle` obligatoriamente a este `Id_Talle` genérico, unificando la lógica de consulta de stock para el sistema sin requerir condicionales especiales en el código de aplicación.

### 2.2. Preservación del Precio Histórico e Inmutabilidad de Ventas (RN.08)

#### Planteo del problema

Los precios de lista de los productos y sus porcentajes de liquidación sufren variaciones a lo largo del tiempo por inflación o estrategias comerciales. Una venta realizada en el pasado debe mantener inalterados los montos aplicados en el momento exacto de la compra.

#### Decisión adoptada

Se incluyó el atributo **`precio_unitario`** dentro de la entidad **`Detalle_Venta`**:

* En el momento de confirmar la transacción, el sistema toma el precio vigente del catálogo (`Producto.precio_lista` afectado por `en_liquidacion` / `porcentaje_liquidacion` si correspondiera) y lo guarda como una captura (*snapshot*) en `Detalle_Venta.precio_unitario`.

* **Justificación de redundancia controlada:** Aunque conceptualmente el precio proviene de `Producto`, almacenarlo en `Detalle_Venta` garantiza que modificaciones posteriores en la tabla `Producto` no alteren los registros históricos de facturación ni la contabilidad del negocio.

### 2.3. Esquema de Precios, Liquidaciones y Descuentos por Pago (RN.05, RN.06, RN.07, RN.09)

#### Planteo del problema

El cálculo del monto final de una compra involucra dos niveles de descuentos:

1. **Nivel de Producto:** Liquidación sobre el precio de lista base (RN.05, RN.06).

2. **Nivel de Transacción:** Descuento adicional por medio de pago seleccionado (Efectivo/Transferencia vs. Tarjeta) (RN.07, RN.09).

#### Decisión adoptada

* **En `Producto`:** Se agregaron los atributos booleanos y numéricos `en_liquidacion` y `porcentaje_liquidacion`. Esto permite a la administración definir productos en oferta global sin modificar permanentemente el `precio_lista` original.

* **En `Metodo_pago`:** Se añadió el atributo `porcentaje_descuento`. Ejemplos de datos maestrizados:

  * Efectivo $\rightarrow 10\%$

  * Transferencia $\rightarrow 10\%$

  * Tarjeta de Crédito/Débito $\rightarrow 0\%$

* **En `Venta`:** Se incluyen los atributos consolidados `descuento_aplicado` y `total`. Almacenar el total final calculado al cierre de la venta agiliza la generación de reportes comerciales y previene diferencias por cálculo de decimales.

### 2.4. Unificación de Clientes y Canales de Comercialización (RN.04)

#### Planteo del problema

La tienda opera bajo dos modalidades: venta presencial en mostrador y catálogo web online. Los clientes pueden comprar por cualquiera de los dos medios.

#### Decisión adoptada

* **Tabla Única de `Cliente`:** Se utiliza una sola entidad `Cliente` para registrar a los compradores tanto presenciales como virtuales. Si es un comprador presencial por primera vez, se registran sus datos mínimos obligatorios (nombre, apellido, DNI, teléfono/email) al momento del cobro.

* **Atributo `canal` en `Venta`:** En lugar de crear tablas de ventas separadas (`Venta_Online` y `Venta_Mostrador`), se utiliza un único encabezado de venta con un atributo enumerado `canal` (valores: `'MOSTRADOR'`, `'ONLINE'`).

* **Justificación:** Centraliza la facturación y la historia de compra del cliente en un solo lugar, simplificando análisis de comportamiento de compra *omnichannel*.

### 2.5. Selección de Claves Primarias y Compuestas

#### Claves Primarias Simples (Surrogate Keys)

Se utilizaron identificadores numéricos autonumérico/secuenciales (`Id_Cliente`, `Id_Producto`, `Id_Venta`, `Id_Categoria`, `Id_Talle`, `Id_metodo_pago`) para las entidades principales.

* **Justificación:** Mejoran el rendimiento de los índices B-Tree, reducen el tamaño ocupado por claves foráneas en tablas secundarias y evitan problemas ante cambios en datos naturales (como cambios de DNI o códigos de barra).

#### Claves Primarias Compuestas

1. **`Producto_Talle`** $\rightarrow$ **(`Id_Producto`, `Id_Talle`):**

   * Previene duplicados garantizando que una combinación de prenda y talle tenga una única entrada de stock.

2. **`Detalle_Venta`** $\rightarrow$ **(`Id_Venta`, `nro_item`):**

   * Modela el número ordinal de renglón dentro de la factura/ticket (Ítem 1, Ítem 2, etc.) asociado a una venta específica.

### 2.6. Almacenamiento de Atributos Calculados (`subtotal` y `total`)

#### Consideración teórica

En la teoría pura de bases de datos relacionales, los atributos derivados ($subtotal = cantidad \times precio\_unitario$) no deberían almacenarse para mantener la estricta 3FN sin redundancia.

#### Justificación técnica de su inclusión

Se decidió almacenar `subtotal` en `Detalle_Venta` y `total` en `Venta`:

* **Rendimiento (Performance):** Evita realizar operaciones aritméticas complejas e intercaladas con agregaciones (`SUM`) en consultas masivas de auditoría, reportes de ventas mensuales o cierres de caja diarios.

* **Seguridad de Datos:** El valor guardado al momento del cobro es inmutable y legalmente vinculante con la venta efectuada.

## 3. Matriz de Trazabilidad: Reglas de Negocio vs. Tablas del Modelo

| Regla de Negocio | Entidad / Atributo Responsable | Mecanismo de Control | 
 | ----- | ----- | ----- | 
| **RN.01** (Variantes y Talles) | `Producto_Talle` (`Id_Producto`, `Id_Talle`) | Relación M:N. Registro de talle genérico para accesorios. | 
| **RN.02** (Descuento de Stock) | `Producto_Talle.stock` | Control de stock a nivel de clave compuesta producto/talle. | 
| **RN.03** (Categoría Única) | `Producto.Id_Categoria` (FK) | Clave foránea no nula hacia la tabla `Categoria`. | 
| **RN.04** (Cliente Asociado) | `Venta.Id_Cliente` (FK) | Vinculación obligatoria de la venta a un registro de cliente. | 
| **RN.05 / RN.06** (Precios y Liquidación) | `Producto.precio_lista`, `en_liquidacion`, `porcentaje_liquidacion` | Parámetros base para el cálculo del precio antes de la venta. | 
| **RN.07 / RN.09** (Descuentos por Medio de Pago) | `Metodo_pago.porcentaje_descuento`, `Venta.descuento_aplicado` | Regla configurada por método de pago aplicada en la cabecera. | 
| **RN.08** (Precio Histórico en Detalle) | `Detalle_Venta.precio_unitario` | Captura inmutable del precio al momento de confirmar la transacción. | 

## 4. Alcance y Exclusiones del Diseño

Para mantener la consistencia en esta etapa inicial del proyecto, se registran formalmente las siguientes **exclusiones de diseño**:

* **Gestión de Proveedores y Ordenes de Compra:** La base de datos asume que el stock se carga/actualiza directamente en `Producto_Talle` sin registrar el comprobante de ingreso del proveedor.

* **Logística de Envíos:** No se almacenan datos de empresas de transporte, números de seguimiento (*tracking*) ni direcciones de entrega alternativas para la venta online.

* **Integración con Pasarelas de Pago:** No se persisten tokens de transacción ni respuestas de pasarelas externas (MercadoPago, MPO, etc.). Solo se registra el método de pago seleccionado y su descuento.