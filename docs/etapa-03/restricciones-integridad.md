# Restricciones de Integridad - Intensa Jeans

**Equipo:** Grupo 21

**Proyecto:** Intensa Jeans - Sistema de Administración de Tienda de Jeans

**Materia:** Bases de Datos I - UNNE

**Etapa:** Etapa 03 

## 1. Introducción

El presente documento define formalmente el conjunto de **Restricciones de Integridad** aplicables a la base de datos relacional de **Intensa Jeans**. Estas restricciones garantizan la consistencia, exactitud, validez y coherencia de los datos almacenados, alineándose con las Reglas de Negocio (RN.01 a RN.09) identificadas en la Etapa I del proyecto.

Las restricciones se clasifican en cuatro categorías fundamentales:

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

```
-- 1. Categoria
CREATE TABLE Categoria (
    Id_Categoria INT AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(255) NULL,
    CONSTRAINT PK_Categoria PRIMARY KEY (Id_Categoria)
);

-- 2. Producto
CREATE TABLE Producto (
    Id_Producto INT AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT NULL,
    precio_lista DECIMAL(10,2) NOT NULL,
    en_liquidacion BOOLEAN NOT NULL DEFAULT FALSE,
    porcentaje_liquidacion DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    Id_Categoria INT NOT NULL,
    CONSTRAINT PK_Producto PRIMARY KEY (Id_Producto),
    CONSTRAINT CHK_PrecioLista_Positivo CHECK (precio_lista >= 0),
    CONSTRAINT CHK_PorcentajeLiq_Rango CHECK (porcentaje_liquidacion BETWEEN 0.00 AND 100.00)
);

-- 3. Talle
CREATE TABLE Talle (
    Id_Talle INT AUTO_INCREMENT,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Talle PRIMARY KEY (Id_Talle)
);

-- 4. Producto_Talle
CREATE TABLE Producto_Talle (
    Id_Producto INT NOT NULL,
    Id_Talle INT NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Producto_Talle PRIMARY KEY (Id_Producto, Id_Talle),
    CONSTRAINT CHK_Stock_NoNegativo CHECK (stock >= 0)
);

-- 5. Cliente
CREATE TABLE Cliente (
    Id_Cliente INT AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    dni VARCHAR(15) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL,
    direccion VARCHAR(150) NULL,
    CONSTRAINT PK_Cliente PRIMARY KEY (Id_Cliente)
);

-- 6. Metodo_pago
CREATE TABLE Metodo_pago (
    Id_metodo_pago INT AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    porcentaje_descuento DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT PK_Metodo_pago PRIMARY KEY (Id_metodo_pago),
    CONSTRAINT CHK_PorcentajeDesc_Rango CHECK (porcentaje_descuento BETWEEN 0.00 AND 100.00)
);

-- 7. Venta
CREATE TABLE Venta (
    Id_Venta INT AUTO_INCREMENT,
    fecha_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    canal VARCHAR(20) NOT NULL,
    descuento_aplicado DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL,
    Id_Cliente INT NOT NULL,
    Id_metodo_pago INT NOT NULL,
    CONSTRAINT PK_Venta PRIMARY KEY (Id_Venta),
    CONSTRAINT CHK_Canal_Valido CHECK (canal IN ('MOSTRADOR', 'ONLINE')),
    CONSTRAINT CHK_Descuento_NoNegativo CHECK (descuento_aplicado >= 0),
    CONSTRAINT CHK_Total_NoNegativo CHECK (total >= 0)
);

-- 8. Detalle_Venta
CREATE TABLE Detalle_Venta (
    nro_item INT NOT NULL,
    Id_Venta INT NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    Id_Producto INT NOT NULL,
    Id_Talle INT NOT NULL,
    CONSTRAINT PK_Detalle_Venta PRIMARY KEY (Id_Venta, nro_item),
    CONSTRAINT CHK_Cantidad_Positiva CHECK (cantidad > 0),
    CONSTRAINT CHK_PrecioUnitario_Positivo CHECK (precio_unitario >= 0),
    CONSTRAINT CHK_Subtotal_Positivo CHECK (subtotal >= 0)
);

```

## 5. Restricciones de Unicidad (UNIQUE)

Impiden la duplicación de datos de negocio clave dentro del sistema.

| Entidad | Campo(s) UNIQUE | Propósito de Negocio | 
 | ----- | ----- | ----- | 
| **`Cliente`** | `dni` | Evitar la duplicación de cuentas o fichas de clientes. | 
| **`Cliente`** | `email` | Garantizar emails únicos para autenticación en canal online. | 
| **`Categoria`** | `nombre` | No permitir categorías redundantes con el mismo nombre. | 
| **`Talle`** | `descripcion` | Evitar nombres de talles duplicados en la base de datos. | 
| **`Metodo_pago`** | `nombre` | Prevenir duplicación en los nombres de métodos de pago. | 

## 6. Restricciones Complejas y Reglas de Negocio (Triggers)

Determinadas reglas del negocio no pueden resolverse únicamente mediante restricciones estáticas (CHECK) y requieren mecanismos procedimentales o triggers:

### 6.1. Control de Stock Suficiente (RN.02)

* **Regla:** No se permite efectuar una venta si la `cantidad` en `Detalle_Venta` supera el `stock` disponible en `Producto_Talle` para el producto y talle seleccionados.

* **Mecanismo:** `BEFORE INSERT ON Detalle_Venta`

* **Acción:** Si `NEW.cantidad > Producto_Talle.stock`, el sistema lanza una excepción abortando la transacción (`SIGNAL SQLSTATE '45000'`).

### 6.2. Descuento Automático de Stock (RN.02)

* **Regla:** Al confirmarse un ítem de venta, el stock debe reducirse automáticamente.

* **Mecanismo:** `AFTER INSERT ON Detalle_Venta`

* **Acción:** Ejecuta la actualización:
  

  $$
  \text{stock}_{\text{nuevo}} = \text{stock}_{\text{actual}} - \text{NEW.cantidad}
  $$

### 6.3. Congelamiento de Precio Unitario e Inmutabilidad (RN.08)

* **Regla:** El precio asignado en `Detalle_Venta.precio_unitario` debe congelarse con el valor vigente al momento de vender y no actualizarse si cambia `Producto.precio_lista`.

* **Mecanismo:** Asignación explícita mediante lógica de aplicación o trigger `BEFORE INSERT` que calcula:
  

  $$
  \text{precio\_unitario} = \text{precio\_lista} \times (1 - \text{porcentaje\_liquidacion} / 100)
  $$

## 7. Matriz de Cobertura: Reglas de Negocio vs. Restricciones

| Código RN | Descripción de la Regla | Tipo de Restricción Aplicada | Ubicación en el Esquema | 
 | ----- | ----- | ----- | ----- | 
| **RN.01** | Variantes y stock por talle / Talle único en accesorios. | PK Compuesta, NOT NULL, Registro 'Talle Único' en `Talle`. | `Producto_Talle(Id_Producto, Id_Talle)` | 
| **RN.02** | Validación y descuento automático de stock. | `CHECK (stock >= 0)` + Trigger de control de stock. | `Producto_Talle.stock` | 
| **RN.03** | Pertenece a una única categoría. | `FK NOT NULL` hacia `Categoria`. | `Producto.Id_Categoria` | 
| **RN.04** | Venta siempre asociada a cliente registrado. | `FK NOT NULL` hacia `Cliente`, `UNIQUE` en DNI/Email. | `Venta.Id_Cliente`, `Cliente` | 
| **RN.05** | Precio de lista como base. | `CHECK (precio_lista >= 0)`, `NOT NULL`. | `Producto.precio_lista` | 
| **RN.06** | Descuento por liquidación sobre lista. | `CHECK (porcentaje_liquidacion BETWEEN 0 AND 100)`. | `Producto.porcentaje_liquidacion` | 
| **RN.07 / RN.09** | Descuento según método de pago. | `CHECK (porcentaje_descuento BETWEEN 0 AND 100)`. | `Metodo_pago.porcentaje_descuento` | 
| **RN.08** | Precio histórico en detalle independiente. | `CHECK (precio_unitario >= 0)` e inmutabilidad por FK RESTRICT. | `Detalle_Venta.precio_unitario` | 
