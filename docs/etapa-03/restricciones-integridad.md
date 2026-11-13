# Restricciones de Integridad - Intensa Jeans

**Equipo:** Grupo 21

**Proyecto:** Intensa Jeans - Sistema de Administración de Tienda de Jeans

**Materia:** Bases de Datos I - UNNE

**Etapa:** Etapa 03 

## 1. Introducción

El presente documento define formalmente el conjunto de **Restricciones de Integridad** aplicables a la base de datos relacional de **Intensa Jeans**. Estas restricciones garantizan la consistencia, exactitud, validez y coherencia de los datos almacenados, alineándose con las Reglas de Negocio (RN.01 a RN.10) identificadas en la Etapa I del proyecto.

Las restricciones se clasifican en cinco categorías fundamentales:

1. **Integridad de Entidad:** Definición de Claves Primarias (PK).

2. **Integridad Referencial:** Claves Foráneas (FK) y comportamiento ante operaciones de actualización/borrado (`ON UPDATE`, `ON DELETE`).

3. **Integridad de Dominio:** Tipos de datos, nulidad (`NOT NULL`) y restricciones de rango/valores permitidos (`CHECK`).

4. **Integridad de Unicidad:** Atributos con valores únicos (`UNIQUE`).

5. **Restricciones de Negocio complejas:** Reglas de validación procedimentales (Triggers / Procedimientos Almacenados).

## 2. Integridad de Entidad (Claves Primarias - PK)

Cada entidad posee una Clave Primaria que identifica de manera única e unívoca a cada uno de sus registros. No se admiten valores nulos (`NOT NULL`) ni duplicados en los campos que componen la PK.

| Entidad | Atributo(s) Clave Primaria | Tipo de Clave | Descripción / Justificación | 
 | ----- | ----- | ----- | ----- | 
| **`Categoria`** | `Id_Categoria` | Simple (Surrogate) | Identificador entero autonumérico único por categoría. | 
| **`Producto`** | `Id_Producto` | Simple (Surrogate) | Identificador entero autonumérico único por variante/prenda. | 
| **`Talle`** | `Id_Talle` | Simple (Surrogate) | Identificador entero único por talle (incluye "Talle Único"). | 
| **`Producto_Talle`** | (`Id_Producto`, `Id_Talle`) | Compuesta | Identifica la disponibilidad de inventario para una variante concreta en un talle específico. | 
| **`Cliente`** | `Id_Cliente` | Simple (Surrogate) | Identificador entero autonumérico único por cliente. | 
| **`Metodo_pago`** | `Id_metodo_pago` | Simple (Surrogate) | Identificador entero único por forma de cobro. | 
| **`Venta`** | `Id_Venta` | Simple (Surrogate) | Identificador entero autonumérico único por transacción efectuada. | 
| **`Detalle_Venta`** | (`Id_Venta`, `nro_item`) | Compuesta | Identifica cada renglón o ítem en el comprobante de venta. | 

## 3. Integridad Referencial (Claves Foráneas - FK)

Asegura que las relaciones entre tablas se mantengan válidas. Toda clave foránea debe hacer referencia a una clave primaria existente en la tabla padre asociada.

### 3.1. Detalle de Claves Foráneas y Comportamiento de Borrado/Actualización

#### 1. Tabla `Producto`

* **FK:** `Id_Categoria` $\rightarrow$ Referencia a `Categoria(Id_Categoria)`.

* **Regla `ON UPDATE`:** `CASCADE` (Si cambia el ID de la categoría, se actualiza automáticamente en el producto).

* **Regla `ON DELETE`:** `RESTRICT` (No se puede eliminar una categoría si existen productos asociados a ella).

#### 2. Tabla `Producto_Talle`

* **FK1:** `Id_Producto` $\rightarrow$ Referencia a `Producto(Id_Producto)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `RESTRICT` (Evita borrar un producto si tiene registros de stock configurados).

* **FK2:** `Id_Talle` $\rightarrow$ Referencia a `Talle(Id_Talle)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `RESTRICT` (Evita borrar un talle si está asociado a productos en inventario).

#### 3. Tabla `Venta`

* **FK1:** `Id_Cliente` $\rightarrow$ Referencia a `Cliente(Id_Cliente)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `RESTRICT` (Garantiza trazabilidad de clientes con historial de compras; no se borran clientes con ventas registradas).

* **FK2:** `Id_metodo_pago` $\rightarrow$ Referencia a `Metodo_pago(Id_metodo_pago)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `RESTRICT` (Preserva el método de pago utilizado en transacciones históricas).

#### 4. Tabla `Detalle_Venta`

* **FK1:** `Id_Venta` $\rightarrow$ Referencia a `Venta(Id_Venta)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `CASCADE` (Si se anula o elimina la cabecera de venta, se eliminan en cascada sus ítems de detalle).

* **FK2 Compuesta:** (`Id_Producto`, `Id_Talle`) $\rightarrow$ Referencia a `Producto_Talle(Id_Producto, Id_Talle)`.

  * **`ON UPDATE`:** `CASCADE`

  * **`ON DELETE`:** `RESTRICT` (Protege el historial de ítems vendidos impidiendo eliminar la variante/talle de la base de datos).

## 4. Integridad de Dominio (Nulidad, Tipos de Datos y Restricciones CHECK)

Define el conjunto de valores válidos admitidos por cada atributo dentro de las tablas.

### 4.1. Definición por Entidad

```sql
-- 1. TABLA: Categoria
CREATE TABLE Categoria (
    Id_Categoria INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion VARCHAR(255) NULL,
    CONSTRAINT PK_Categoria PRIMARY KEY (Id_Categoria)
);

-- 2. TABLA: Talle
CREATE TABLE Talle (
    Id_Talle INT IDENTITY(1,1) NOT NULL,
    descripcion VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Talle PRIMARY KEY (Id_Talle)
);

-- 3. TABLA: Metodo_pago
CREATE TABLE Metodo_pago (
    Id_metodo_pago INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    porcentaje_descuento DECIMAL(5, 2) NOT NULL CONSTRAINT DF_Metodo_pago_descuento DEFAULT (0.00),
    CONSTRAINT PK_Metodo_pago PRIMARY KEY (Id_metodo_pago),
    CONSTRAINT CHK_Metodo_pago_descuento CHECK (porcentaje_descuento >= 0 AND porcentaje_descuento <= 100)
);

-- 4. TABLA: Cliente
CREATE TABLE Cliente (
    Id_Cliente INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    apellido VARCHAR(80) NOT NULL,
    dni VARCHAR(20) NOT NULL,
    telefono VARCHAR(30) NULL,
    email VARCHAR(120) NOT NULL,
    direccion VARCHAR(200) NULL,
    CONSTRAINT PK_Cliente PRIMARY KEY (Id_Cliente),
    CONSTRAINT UQ_Cliente_dni UNIQUE (dni),
    CONSTRAINT UQ_Cliente_email UNIQUE (email)
);

-- 5. TABLA: Producto
CREATE TABLE Producto (
    Id_Producto INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(120) NOT NULL,
    descripcion VARCHAR(500) NULL,
    precio_lista DECIMAL(10, 2) NOT NULL,
    en_liquidacion BIT NOT NULL CONSTRAINT DF_Producto_en_liquidacion DEFAULT (0),
    porcentaje_liquidacion DECIMAL(5, 2) NOT NULL CONSTRAINT DF_Producto_porcentaje DEFAULT (0.00),
    Id_Categoria INT NOT NULL,
    CONSTRAINT PK_Producto PRIMARY KEY (Id_Producto),
    CONSTRAINT FK_Producto_Categoria FOREIGN KEY (Id_Categoria)
        REFERENCES Categoria (Id_Categoria)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT CHK_Producto_precio CHECK (precio_lista >= 0),
    CONSTRAINT CHK_Producto_porcentaje CHECK (porcentaje_liquidacion >= 0 AND porcentaje_liquidacion <= 100)
);

-- 6. TABLA: Producto_Talle
CREATE TABLE Producto_Talle (
    Id_Producto INT NOT NULL,
    Id_Talle INT NOT NULL,
    stock INT NOT NULL CONSTRAINT DF_ProductoTalle_stock DEFAULT (0),
    CONSTRAINT PK_Producto_Talle PRIMARY KEY (Id_Producto, Id_Talle),
    CONSTRAINT FK_ProdTalle_Producto FOREIGN KEY (Id_Producto)
        REFERENCES Producto (Id_Producto)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_ProdTalle_Talle FOREIGN KEY (Id_Talle)
        REFERENCES Talle (Id_Talle)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT CHK_Producto_Talle_stock CHECK (stock >= 0)
);

-- 7. TABLA: Venta
CREATE TABLE Venta (
    Id_Venta INT IDENTITY(1,1) NOT NULL,
    fecha_hora DATETIME2(0) NOT NULL CONSTRAINT DF_Venta_fechahora DEFAULT (SYSDATETIME()),
    canal VARCHAR(50) NOT NULL,
    descuento_aplicado DECIMAL(10, 2) NOT NULL CONSTRAINT DF_Venta_descuento DEFAULT (0.00),
    total DECIMAL(10, 2) NOT NULL CONSTRAINT DF_Venta_total DEFAULT (0.00),
    Id_Cliente INT NOT NULL,
    Id_metodo_pago INT NOT NULL,
    CONSTRAINT PK_Venta PRIMARY KEY (Id_Venta),
    CONSTRAINT FK_Venta_Cliente FOREIGN KEY (Id_Cliente)
        REFERENCES Cliente (Id_Cliente)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_Venta_Metodo_pago FOREIGN KEY (Id_metodo_pago)
        REFERENCES Metodo_pago (Id_metodo_pago)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT CHK_Venta_descuento CHECK (descuento_aplicado >= 0),
    CONSTRAINT CHK_Venta_total CHECK (total >= 0)
);

-- 8. TABLA: Detalle_Venta
CREATE TABLE Detalle_Venta (
    Id_Venta INT NOT NULL,
    nro_item INT NOT NULL,
    Id_Producto INT NOT NULL,
    Id_Talle INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario DECIMAL(10, 2) NOT NULL,
    subtotal DECIMAL(10, 2) NOT NULL,
    CONSTRAINT PK_Detalle_Venta PRIMARY KEY (Id_Venta, nro_item),
    CONSTRAINT FK_DetalleVenta_Venta FOREIGN KEY (Id_Venta)
        REFERENCES Venta (Id_Venta)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT FK_DetalleVenta_ProductoTalle FOREIGN KEY (Id_Producto, Id_Talle)
        REFERENCES Producto_Talle (Id_Producto, Id_Talle)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT CHK_DetalleVenta_cantidad CHECK (cantidad > 0),
    CONSTRAINT CHK_DetalleVenta_precio CHECK (precio_unitario >= 0),
    CONSTRAINT CHK_DetalleVenta_subtotal CHECK (subtotal >= 0)
);
```

## 5. Restricciones de Unicidad (UNIQUE)

Impiden la duplicación de datos de negocio clave dentro del sistema.

| Entidad | Campo(s) UNIQUE | Propósito de Negocio | 
 | ----- | ----- | ----- | 
| **`Cliente`** | `dni` | Evitar la duplicación de cuentas o fichas de clientes. | 
| **`Cliente`** | `email` | Garantizar emails únicos para autenticación en canal online. | 

En el esquema implementado la unicidad se aplica solo a los datos de identificación del cliente (`UQ_Cliente_dni` y `UQ_Cliente_email`). Los nombres de `Categoria`, `Talle` y `Metodo_pago` no tienen restricción `UNIQUE`: los datos de prueba no los repiten, pero la base no lo impide.

## 6. Restricciones Complejas y Reglas de Negocio (T-SQL)

Determinadas reglas del negocio no pueden resolverse únicamente con restricciones estáticas (`CHECK`). En SQL Server se resuelven con procedimientos almacenados, transacciones y triggers, que se implementan en la Etapa V (`docs/etapa-05/`):

### 6.1. Control de Stock Suficiente (RN.02)

* **Regla:** No se permite efectuar una venta si la `cantidad` solicitada supera el `stock` disponible en `Producto_Talle` para el producto y talle seleccionados.

* **Mecanismo:** el procedimiento `sp_RegistrarVentaCompleta` verifica el stock con `fn_StockDisponible` antes de registrar la venta. La restricción `CHECK (stock >= 0)` impide que el stock quede negativo aunque se intente actualizar por otra vía.

* **Acción:** si el stock no alcanza, se ejecuta `THROW 50001, 'Stock insuficiente', 1` y se revierte la transacción.

### 6.2. Descuento Automático de Stock (RN.02)

* **Regla:** Al confirmarse un ítem de venta, el stock debe reducirse automáticamente.

* **Mecanismo:** el mismo procedimiento actualiza `Producto_Talle` dentro de la transacción de la venta, de modo que el descuento de stock y el registro de la venta se confirman o se revierten juntos.

### 6.3. Congelamiento de Precio Unitario e Inmutabilidad (RN.08)

* **Regla:** El precio asignado en `Detalle_Venta.precio_unitario` debe congelarse con el valor vigente al momento de vender y no actualizarse si cambia `Producto.precio_lista`.

* **Mecanismo:** el procedimiento calcula el precio al insertar el renglón y lo guarda en `Detalle_Venta`:

  $$
  \text{precio\_unitario} = \text{precio\_lista} \times (1 - \text{porcentaje\_liquidacion} / 100)
  $$

## 7. Matriz de Cobertura: Reglas de Negocio vs. Restricciones

| Código RN | Descripción de la Regla | Tipo de Restricción Aplicada | Ubicación en el Esquema | 
 | ----- | ----- | ----- | ----- | 
| **RN.01** | Variantes y stock por talle / Talle único en accesorios. | PK Compuesta, NOT NULL, Registro 'Talle Único' en `Talle`. | `Producto_Talle(Id_Producto, Id_Talle)` | 
| **RN.02** | Validación y descuento automático de stock. | `CHECK (stock >= 0)` + procedimiento de venta con control de stock. | `Producto_Talle.stock` | 
| **RN.03** | Pertenece a una única categoría. | `FK NOT NULL` hacia `Categoria`. | `Producto.Id_Categoria` | 
| **RN.04** | Venta siempre asociada a cliente registrado. | `FK NOT NULL` hacia `Cliente`, `UNIQUE` en DNI/Email. | `Venta.Id_Cliente`, `Cliente` | 
| **RN.05** | Precio de lista como base. | `CHECK (precio_lista >= 0)`, `NOT NULL`. | `Producto.precio_lista` | 
| **RN.06** | Descuento por liquidación sobre lista. | `CHECK (porcentaje_liquidacion BETWEEN 0 AND 100)`. | `Producto.porcentaje_liquidacion` | 
| **RN.07 / RN.09** | Descuento según método de pago. | `CHECK (porcentaje_descuento BETWEEN 0 AND 100)`. | `Metodo_pago.porcentaje_descuento` | 
| **RN.08** | Precio histórico en detalle independiente. | `CHECK (precio_unitario >= 0)` e inmutabilidad por FK RESTRICT. | `Detalle_Venta.precio_unitario` | 
| **RN.10** | Descuento por cliente frecuente. | Regla procedimental (`fn_CalcularDescuentoCliente` en `sp_RegistrarVentaCompleta`); `CHECK (descuento_aplicado >= 0)`. | `Venta.descuento_aplicado` |
