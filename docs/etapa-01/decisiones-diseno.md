# Decisiones de diseño

Este documento registra las decisiones tomadas al definir el dominio, el alcance y el modelo de datos del sistema de **Intensa Jeans**, y el motivo de cada una. Se apoya en la [descripción del caso](descripcion-caso.md), el [alcance](alcance.md) y las [reglas de negocio](reglas-negocio.md).

## 1. Contexto y dominio

- **Decisión:** el sistema gestiona la operatoria de **Intensa Jeans**, una tienda de indumentaria especializada en jeans y accesorios relacionados, que vende por dos canales: **presencial** (local físico, mostrador) y **online** (catálogo web).
- **Motivo:** el rubro cubre todos los requerimientos mínimos (stock, clientes, historial de precios unitarios y métodos de pago) y aporta una particularidad interesante: el stock se gestiona **por talle**, no solo por producto.
- **Usuarios del sistema:**
  - **Personal de mostrador:** registra ventas y consulta stock en el momento.
  - **Administración del negocio:** gestiona el catálogo, las categorías, los precios y las liquidaciones.
- **Prioridades de diseño:** garantizar la **consistencia entre el stock disponible y las ventas concretadas** y la **trazabilidad de los precios aplicados** en cada operación.

## 2. Alcance del sistema

- **Decisión:** se incluyen catálogo, clientes, ventas (presencial y online) y cálculo de precios finales. Se excluyen proveedores y compras de mercadería, logística de envíos, facturación electrónica y pasarelas de pago externas.
- **Motivo:** el objetivo es un modelo de entre 6 y 10 relaciones que soporte el ciclo completo de venta. Los módulos excluidos agregarían complejidad sin aportar a ese objetivo.

## 3. Entidades del modelo

El modelo cuenta con **7 relaciones**, dentro del rango de 6 a 10 esperado.

| Entidad | Propósito | Reglas |
|---|---|---|
| `Categoria` | Agrupa los productos del catálogo. | RN.03 |
| `Producto` | Variante de producto (por ejemplo, “Jean recto azul”) con su precio de lista y datos de liquidación. | RN.01, RN.05, RN.06 |
| `Talle` | Catálogo de talles disponibles, incluido el talle único genérico para accesorios. | RN.01 |
| `Producto_Talle` | Stock de cada producto por talle. | RN.01, RN.02 |
| `Cliente` | Datos del comprador. | RN.04 |
| `Metodo_pago` | Medio de pago y su porcentaje de descuento. | RN.07, RN.09 |
| `Venta` | Encabezado de la venta. | RN.04, RN.07 |
| `Detalle_Venta` | Renglones de cada venta con su precio unitario histórico. | RN.02, RN.08 |

## 4. Decisiones de modelado

### 4.1 Producto como variante y stock por talle mediante `Producto_Talle`

- **Decisión:** cada registro de `Producto` representa una **variante** (por ejemplo, “Jean recto azul”). La relación N:M entre `Producto` y `Talle` se resuelve con la tabla `Producto_Talle`, cuya clave primaria es compuesta (`Id_Producto`, `Id_Talle`) y que contiene el atributo `stock`.
- **Motivo:** una misma variante tiene varios talles, cada uno con stock propio e independiente (**RN.01**). Guardar el stock en `Producto` violaría la atomicidad y no permitiría controlar la disponibilidad por talle (**RN.02**).
- **Accesorios:** los productos que no requieren talle se asocian a un talle único genérico, evitando una excepción en el modelo.
- **Alternativa descartada:** una tabla aparte para "modelo" y otra para "variante" agregaría una relación más sin necesidad. Con las 7 relaciones actuales el dominio queda cubierto.

### 4.2 Categoría como entidad separada

- **Decisión:** `Categoria` es una tabla propia y `Producto` la referencia con `Id_Categoria` (relación 1:N).
- **Motivo:** cada producto pertenece a una única categoría y una categoría agrupa muchos productos (**RN.03**). Evita repetir nombre y descripción de la categoría en cada producto (dependencia transitiva, 3FN).

### 4.3 Precio unitario histórico en `Detalle_Venta`

- **Decisión:** `Detalle_Venta` guarda `precio_unitario` y `subtotal` en el momento de la venta, y su clave primaria es compuesta (`nro_item`, `Id_Venta`).
- **Motivo:** si el precio del catálogo cambia, las ventas ya realizadas no deben modificarse (**RN.08**). Es un requerimiento explícito del proyecto y una de las prioridades del negocio (trazabilidad de precios).
- **Referencia al producto:** cada renglón referencia a `Producto_Talle` mediante la FK compuesta (`Id_Talle`, `Id_Producto`), de modo que identifica exactamente qué talle se vendió y de qué stock se descuenta.

### 4.4 Liquidación como atributos de `Producto`

- **Decisión:** el estado de liquidación se modela con `en_liquidacion` y `porcentaje_liquidacion` dentro de `Producto`, junto con `precio_lista`.
- **Motivo:** la liquidación es una propiedad del producto y no requiere una entidad propia en este alcance (**RN.05** y **RN.06**). El precio de liquidación se calcula a partir del precio de lista, por lo que no se almacena.
- **Limitación conocida:** el modelo guarda solo la liquidación vigente, no un historial de liquidaciones. El historial de precios de las operaciones ya queda cubierto por `Detalle_Venta`.

### 4.5 Método de pago como entidad

- **Decisión:** `Metodo_pago` es una tabla con `nombre` y `porcentaje_descuento`, referenciada desde `Venta`.
- **Motivo:** el descuento adicional depende del método elegido: efectivo o transferencia con descuento, tarjeta sin descuento (**RN.07** y **RN.09**). Al ser una tabla, el porcentaje se modifica sin tocar la estructura y se evita repetir texto en cada venta.
- **Aplicación del descuento:** se calcula sobre el precio vigente (lista o liquidación, según corresponda), no sobre el precio de lista.

### 4.6 Canal de venta como atributo de `Venta`

- **Decisión:** el canal (presencial u online) se guarda como atributo `canal` en `Venta`.
- **Motivo:** ambos canales comparten las mismas reglas y estructura, por lo que no justifican entidades separadas.

### 4.7 Datos calculados en `Venta`

- **Decisión:** `Venta` conserva `descuento_aplicado` y `total`.
- **Motivo:** como los precios y los porcentajes pueden cambiar, se registra el descuento efectivamente aplicado y el total de esa venta, para que el comprobante sea reproducible a futuro.
- **A revisar en la normalización:** `subtotal` y `total` son datos derivables, por lo que hay que decidir en la Etapa II si se conservan como dato histórico o se calculan en las consultas.

### 4.8 Cliente obligatorio en toda venta

- **Decisión:** `Venta` tiene una FK obligatoria a `Cliente`, que registra nombre, apellido, DNI, teléfono, email y dirección.
- **Motivo:** toda venta debe estar asociada a un cliente registrado, y si es su primera compra se lo registra en el momento, tanto en el canal online como en el presencial (**RN.04**).

### 4.9 Personal de mostrador fuera del modelo

- **Decisión:** no se modela una entidad de vendedor o empleado.
- **Motivo:** los requerimientos del caso se centran en el catálogo, los clientes y las ventas. El personal de mostrador aparece como usuario del sistema, pero ninguna regla de negocio exige registrar quién realizó cada venta.
- **Consecuencia:** el reporte agregado de la Etapa IV se hará **por categoría de producto** y no por vendedor.

## 5. Normalización

- **Objetivo:** el esquema debe alcanzar la **Tercera Forma Normal (3FN)**.
- **Cómo se cumple:**
  - **1FN:** todos los atributos son atómicos y no hay grupos repetitivos (los talles y los renglones de venta están en tablas propias).
  - **2FN:** en las tablas con clave compuesta (`Producto_Talle`, `Detalle_Venta`), los atributos dependen de la clave completa.
  - **3FN:** los datos de categoría, cliente y método de pago están en tablas separadas, sin dependencias transitivas en `Producto` ni en `Venta`.
- La documentación paso a paso se desarrolla en la Etapa II.

## 6. Decisiones pendientes

- **Datos derivados:** definir si `subtotal` y `total` se almacenan o se calculan (ver 4.7).
- **Restricciones:** la definición de tipos de datos, `CHECK`, `UNIQUE` (por ejemplo, DNI del cliente) y reglas de borrado/modificación de las FK se resolverá en la Etapa III.
- **Stock y ventas:** la validación de RN.02 (no vender más que el stock disponible) y el descuento automático del stock se implementarán en la Etapa V con transacciones y triggers.
