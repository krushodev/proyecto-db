## 1. Introducción y Contexto

El objetivo de este documento es redactar paso a paso el proceso de normalización aplicado al modelo de datos del sistema **Intensa Jeans**. Se parte de una estructura no normalizada (UNF / Tabla Universal) que reúne todos los datos del dominio expresados en los requerimientos y reglas de negocio (RN.01 a RN.09), para luego avanzar progresivamente a través de la **Primera Forma Normal (1FN)**, **Segunda Forma Normal (2FN)** y **Tercera Forma Normal (3FN)**.

## 2. Forma No Normalizada (UNF - Tabla Universal)

En el estado inicial, se asume una única vista o tabla lógica no normalizada (`TABLA_UNIVERSAL_VENTAS`) que contiene toda la información de las operaciones diarias de la tienda. Esta estructura incluye grupos repetitivos (como los distintos ítems que componen una compra o la gestión de múltiples talles por producto).

### Estructura de la Tabla Universal (UNF)

`VENTA_UNF` (

    Id_Venta, fecha_hora, canal, descuento_aplicado, total,

    Id_Cliente, nombre_cliente, apellido_cliente, dni_cliente, telefono_cliente, email_cliente, direccion_cliente,

    Id_metodo_pago, nombre_metodo_pago, porcentaje_descuento_pago,

    **{** nro_item, cantidad, precio_unitario, subtotal_item,

      Id_Producto, nombre_producto, descripcion_producto, precio_lista, en_liquidacion, porcentaje_liquidacion,

      Id_Categoria, nombre_categoria, descripcion_categoria,

      Id_Talle, descripcion_talle, stock_talle **}**

)

### Problemas identificados en UNF

* **Valores no atómicos y grupos repetitivos:** Un mismo registro de venta contiene múltiples ítems comprados (marcados entre llaves `{...}`).

* **Redundancia extrema:** Si un cliente realiza varias compras o se vende el mismo producto en distintas ventas, sus datos se repiten innecesariamente.

* **Anomalías de actualización, inserción y borrado:** No se puede registrar un producto sin asociarlo a una venta concreta.

## 3. Paso a la Primera Forma Normal (1FN)

### Regla de la 1FN

Una relación está en **1FN** si y solo si todos sus atributos contienen **valores atómicos** (indivisibles) y no existen **grupos repetitivos** de datos. Además, debe definirse una Clave Primaria (PK).

### Proceso de Transformación

1. Se elimina el grupo repetitivo correspondiente a los ítems de venta.

2. Se extrae el detalle de compra hacia una nueva entidad, manteniendo la clave primaria de la venta como Clave Foránea (FK) para relacionarlos.

3. Se garantiza la atomicidad de todos los atributos.

### Resultado en 1FN

#### Tabla: `VENTA_1FN`

Representa los datos de cabecera de la venta.

* **Clave Primaria:** `Id_Venta`

* **Atributos:** `Id_Venta`, `fecha_hora`, `canal`, `descuento_aplicado`, `total`, `Id_Cliente`, `nombre_cliente`, `apellido_cliente`, `dni_cliente`, `telefono_cliente`, `email_cliente`, `direccion_cliente`, `Id_metodo_pago`, `nombre_metodo_pago`, `porcentaje_descuento_pago`

#### Tabla: `DETALLE_VENTA_1FN`

Representa los ítems comprados.

* **Clave Primaria Compuesta:** (`Id_Venta`, `nro_item`)

* **Atributos:** `Id_Venta`, `nro_item`, `cantidad`, `precio_unitario`, `subtotal`, `Id_Producto`, `nombre_producto`, `descripcion_producto`, `precio_lista`, `en_liquidacion`, `porcentaje_liquidacion`, `Id_Categoria`, `nombre_categoria`, `descripcion_categoria`, `Id_Talle`, `descripcion_talle`, `stock`

## 4. Paso a la Segunda Forma Normal (2FN)

### Regla de la 2FN

Una relación está en **2FN** si:

1. Ya se encuentra en **1FN**.

2. **Todos los atributos no clave tienen dependencia funcional completa** respecto a la clave primaria. Es decir, ningún atributo no clave depende de solo una parte de una clave primaria compuesta.

### Análisis de Dependencias Funcionales en 1FN

En `DETALLE_VENTA_1FN`, la clave primaria es compuesta: `(Id_Venta, nro_item)`.
Se identifican las siguientes **dependencias parciales**:

1. $(Id\_Venta, nro\_item) \rightarrow cantidad, precio\_unitario, subtotal, Id\_Producto, Id\_Talle$ *(Dependencia completa de la clave del detalle)*.

2. $Id\_Producto \rightarrow nombre\_producto, descripcion\_producto, precio\_lista, en\_liquidacion, porcentaje\_liquidacion, Id\_Categoria, nombre\_categoria, descripcion\_categoria$ *(Dependencia parcial: no dependen de `Id_Venta` ni `nro_item`)*.

3. $Id\_Talle \rightarrow descripcion\_talle$ *(Dependencia parcial)*.

4. $(Id\_Producto, Id\_Talle) \rightarrow stock$ *(El stock depende de la combinación del producto y el talle específico, según RN.01)*.

### Proceso de Transformación

Se descomponen los atributos con dependencia parcial creando entidades independientes para `Producto`, `Talle`, y la relación de stock por talle (`Producto_Talle`).

### Resultado en 2FN

* **`VENTA_1FN`** *(se mantiene igual a la espera de la 3FN)*

* **`DETALLE_VENTA_2FN`**

  * **PK:** (`Id_Venta`, `nro_item`)

  * **Atributos:** `Id_Venta`, `nro_item`, `cantidad`, `precio_unitario`, `subtotal`, `Id_Producto` (FK), `Id_Talle` (FK)

* **`PRODUCTO_2FN`**

  * **PK:** `Id_Producto`

  * **Atributos:** `Id_Producto`, `nombre`, `descripcion`, `precio_lista`, `en_liquidacion`, `porcentaje_liquidacion`, `Id_Categoria`, `nombre_categoria`, `descripcion_categoria`

* **`TALLE`**

  * **PK:** `Id_Talle`

  * **Atributos:** `Id_Talle`, `descripcion`

* **`PRODUCTO_TALLE`**

  * **PK Compuesta:** (`Id_Producto`, `Id_Talle`)

  * **Atributos:** `Id_Producto` (FK), `Id_Talle` (FK), `stock`

## 5. Paso a la Tercera Forma Normal (3FN)

### Regla de la 3FN

Una relación está en **3FN** si:

1. Ya se encuentra en **2FN**.

2. **No existen dependencias transitivas** entre atributos no clave. Es decir, ningún atributo que no sea parte de una clave debe depender de otro atributo no clave.

### Análisis de Dependencias Transitivas en 2FN

1. **En `VENTA_1FN`:**

   * $Id\_Venta \rightarrow Id\_Cliente \rightarrow (nombre\_cliente, apellido\_cliente, dni, telefono, email, direccion)$

     *Existe dependencia transitiva:* los datos personales del cliente dependen de `Id_Cliente`, no directamente de `Id_Venta`.

   * $Id\_Venta \rightarrow Id\_metodo\_pago \rightarrow (nombre\_metodo\_pago, porcentaje\_descuento\_pago)$

     *Existe dependencia transitiva:* la información del medio de pago depende de `Id_metodo_pago`.

2. **En `PRODUCTO_2FN`:**

   * $Id\_Producto \rightarrow Id\_Categoria \rightarrow (nombre\_categoria, descripcion\_categoria)$

     *Existe dependencia transitiva:* el nombre y descripción de la categoría dependen de `Id_Categoria`, no de `Id_Producto` (cumpliendo además RN.03).

### Proceso de Transformación

Se extraen las dependencias transitivas creando tablas separadas para `Cliente`, `Metodo_pago` y `Categoria`, reemplazándolas en sus tablas de origen por las correspondientes Claves Foráneas (FK).

## 6. Esquema Relacional Final (Modelo en 3FN)

A continuación se detalla la estructura final de tablas completamente normalizada, la cual coincide de manera exacta con el Diagrama Entidad-Relación / Esquema Relacional del proyecto:

### 1. `Categoria`

* **PK:** `Id_Categoria`

* **Atributos:** `nombre`, `descripcion`

### 2. `Producto`

* **PK:** `Id_Producto`

* **FK:** `Id_Categoria` $\rightarrow$ `Categoria(Id_Categoria)`

* **Atributos:** `nombre`, `descripcion`, `precio_lista`, `en_liquidacion`, `porcentaje_liquidacion`, `Id_Categoria`

### 3. `Talle`

* **PK:** `Id_Talle`

* **Atributos:** `descripcion`

### 4. `Producto_Talle`

* **PK Compuesta:** (`Id_Producto`, `Id_Talle`)

* **FK1:** `Id_Producto` $\rightarrow$ `Producto(Id_Producto)`

* **FK2:** `Id_Talle` $\rightarrow$ `Talle(Id_Talle)`

* **Atributos:** `Id_Producto`, `Id_Talle`, `stock`

### 5. `Cliente`

* **PK:** `Id_Cliente`

* **Atributos:** `nombre`, `apellido`, `dni`, `telefono`, `email`, `direccion`

### 6. `Metodo_pago`

* **PK:** `Id_metodo_pago`

* **Atributos:** `nombre`, `porcentaje_descuento`

### 7. `Venta`

* **PK:** `Id_Venta`

* **FK1:** `Id_Cliente` $\rightarrow$ `Cliente(Id_Cliente)`

* **FK2:** `Id_metodo_pago` $\rightarrow$ `Metodo_pago(Id_metodo_pago)`

* **Atributos:** `fecha_hora`, `canal`, `descuento_aplicado`, `total`, `Id_Cliente`, `Id_metodo_pago`

### 8. `Detalle_Venta`

* **PK Compuesta:** (`Id_Venta`, `nro_item`)

* **FK1:** `Id_Venta` $\rightarrow$ `Venta(Id_Venta)`

* **FK2:** (`Id_Producto`, `Id_Talle`) $\rightarrow$ `Producto_Talle(Id_Producto, Id_Talle)`

* **Atributos:** `nro_item`, `Id_Venta`, `cantidad`, `precio_unitario`, `subtotal`, `Id_Producto`, `Id_Talle`

## 7. Justificación de Cumplimiento de Reglas de Negocio en 3FN

* **RN.01 y RN.02 (Variantes y Stock por Talle):** Resuelto mediante la entidad intermedia `Producto_Talle`, garantizando que el stock sea independiente por variante/talle.

* **RN.03 (Categorías):** Mantenido mediante la relación N:1 entre `Producto` y `Categoria`.

* **RN.04 (Clientes):** La entidad `Cliente` desacopla los datos del comprador de la transacción misma.

* **RN.05, RN.06 y RN.07 (Precios y Descuentos):** Los precios base y descuentos de liquidación se gestionan en `Producto`, los descuentos por medio de pago en `Metodo_pago`, y los finales aplicados en `Venta`.

* **RN.08 (Historización de Precio en Detalle):** El campo `precio_unitario` en `Detalle_Venta` guarda el valor histórico en el instante de la transacción, evitando alterarse si `precio_lista` en `Producto` cambia a futuro.