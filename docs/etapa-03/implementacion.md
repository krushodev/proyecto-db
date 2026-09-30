# Implementación – Intensa Jeans

Este documento describe la implementación física del modelo relacional de la etapa 2, materializada en dos scripts:

- [`ecommerce.sql`](ecommerce.sql): script DDL que crea la base de datos y las tablas.
- [`tienda_ropa_dml.sql`](tienda_ropa_dml.sql): script DML que carga datos iniciales de prueba.

---

## 1. Entorno

| Aspecto | Detalle |
| :--- | :--- |
| **Motor** | Microsoft SQL Server (sintaxis T-SQL) |
| **Base de datos** | `tienda_ropa` |
| **Scripts** | `docs/etapa-03/ecommerce.sql` y `docs/etapa-03/tienda_ropa_dml.sql` |
| **Creación de la BD** | Condicional: se crea solo si no existe en `sys.databases` |
| **Separador de lotes** | `GO` |

### Ejecución

Los scripts deben ejecutarse en este orden, desde SQL Server Management Studio (o Azure Data Studio):

1. `ecommerce.sql`: crea la base `tienda_ropa`, la selecciona con `USE` y genera las 8 tablas en orden de dependencia.
2. `tienda_ropa_dml.sql`: selecciona `tienda_ropa` y carga los datos de prueba.

> Ninguno de los dos scripts es re-ejecutable sobre una base ya creada o poblada: el DDL crea las tablas sin `IF NOT EXISTS` y el DML inserta sin verificar duplicados. Para volver a correrlos hay que eliminar antes las tablas o la base.

---

## 2. Orden de creación de tablas

El orden respeta las dependencias entre tablas:

1. `Categoria`
2. `Talle`
3. `Metodo_pago`
4. `Cliente`
5. `Producto` (depende de `Categoria`)
6. `Producto_Talle` (depende de `Producto` y `Talle`)
7. `Venta` (depende de `Cliente` y `Metodo_pago`)
8. `Detalle_Venta` (depende de `Venta` y `Producto_Talle`)

---

## 3. Tablas implementadas

### 3.1. `Categoria`
| Columna | Tipo |
| :--- | :--- |
| `Id_Categoria` | `INT IDENTITY(1,1)` |
| `nombre` | `VARCHAR(100)` |
| `descripcion` | `VARCHAR(255)` |

### 3.2. `Talle`
| Columna | Tipo |
| :--- | :--- |
| `Id_Talle` | `INT IDENTITY(1,1)` |
| `descripcion` | `VARCHAR(50)` |

### 3.3. `Metodo_pago`
| Columna | Tipo |
| :--- | :--- |
| `Id_metodo_pago` | `INT IDENTITY(1,1)` |
| `nombre` | `VARCHAR(80)` |
| `porcentaje_descuento` | `DECIMAL(5,2)` |

### 3.4. `Cliente`
| Columna | Tipo |
| :--- | :--- |
| `Id_Cliente` | `INT IDENTITY(1,1)` |
| `nombre` | `VARCHAR(80)` |
| `apellido` | `VARCHAR(80)` |
| `dni` | `VARCHAR(20)` |
| `telefono` | `VARCHAR(30)` |
| `email` | `VARCHAR(120)` |
| `direccion` | `VARCHAR(200)` |

### 3.5. `Producto`
| Columna | Tipo |
| :--- | :--- |
| `Id_Producto` | `INT IDENTITY(1,1)` |
| `nombre` | `VARCHAR(120)` |
| `descripcion` | `VARCHAR(500)` |
| `precio_lista` | `DECIMAL(10,2)` |
| `en_liquidacion` | `BIT` |
| `porcentaje_liquidacion` | `DECIMAL(5,2)` |
| `Id_Categoria` | `INT` |

### 3.6. `Producto_Talle`
| Columna | Tipo |
| :--- | :--- |
| `Id_Producto` | `INT` |
| `Id_Talle` | `INT` |
| `stock` | `INT` |

### 3.7. `Venta`
| Columna | Tipo |
| :--- | :--- |
| `Id_Venta` | `INT IDENTITY(1,1)` |
| `fecha_hora` | `DATETIME2(0)` |
| `canal` | `VARCHAR(50)` |
| `descuento_aplicado` | `DECIMAL(10,2)` |
| `total` | `DECIMAL(10,2)` |
| `Id_Cliente` | `INT` |
| `Id_metodo_pago` | `INT` |

### 3.8. `Detalle_Venta`
| Columna | Tipo |
| :--- | :--- |
| `Id_Venta` | `INT` |
| `nro_item` | `INT` |
| `Id_Producto` | `INT` |
| `Id_Talle` | `INT` |
| `cantidad` | `INT` |
| `precio_unitario` | `DECIMAL(10,2)` |
| `subtotal` | `DECIMAL(10,2)` |

---

## 4. Diferencias de tipos respecto del modelo relacional (etapa 2)

Durante la implementación se adaptaron algunos tipos a SQL Server:

| Elemento | Modelo relacional | Implementación | Motivo |
| :--- | :--- | :--- | :--- |
| `Producto.descripcion` | `TEXT` | `VARCHAR(500)` | `TEXT` está obsoleto en SQL Server |
| `Producto.en_liquidacion` | `BOOLEAN` | `BIT` | SQL Server no tiene `BOOLEAN` |
| `Venta.fecha_hora` | `DATETIME` | `DATETIME2(0)` | Tipo recomendado, precisión al segundo |
| Autoincremental | `Auto Increment` | `IDENTITY(1,1)` | Sintaxis propia de SQL Server |
| Longitudes `VARCHAR` | `nombre` 150, cliente 100, `Metodo_pago.nombre` 50, etc. | 120, 80, 80, etc. | Ajuste de longitudes |

---

## 5. Carga de datos iniciales

El script `tienda_ropa_dml.sql` inserta datos de prueba en todas las tablas, respetando el orden de dependencias. Las tablas con `IDENTITY` no reciben el identificador: se genera automáticamente en el orden de inserción.

| Tabla | Registros | Contenido |
| :--- | :---: | :--- |
| `Categoria` | 8 | Jeans Mujer, Jeans Hombre, Camperas, Remeras, Camisas, Shorts, Polleras, Accesorios |
| `Talle` | 10 | Numéricos (36 a 44), letras (S, M, L, XL) y `Único` |
| `Metodo_pago` | 8 | Efectivo (15 %), Transferencia bancaria (10 %), Tarjeta de débito (5 %), Mercado Pago (5 %), y tarjeta de crédito en 1, 3 y 6 cuotas y Gift card (0 %) |
| `Cliente` | 10 | Clientes de Corrientes y Resistencia; algunos sin teléfono o sin dirección |
| `Producto` | 10 | Uno o más productos por categoría; 4 en liquidación (con 10 %, 15 %, 20 % y 25 %) |
| `Producto_Talle` | 24 | Jeans y shorts en talles numéricos, prendas superiores en letras y accesorios en talle único, con su stock |
| `Venta` | 10 | Ventas entre agosto y septiembre de 2026 |
| `Detalle_Venta` | 17 | Entre 1 y 3 renglones por venta |

### Criterios de los datos de prueba

- **Canales de venta:** se usan `Local`, `Web`, `Instagram` y `WhatsApp`. Difieren de los valores `Mostrador` / `Online` que figuran en el modelo relacional de la etapa 2.
- **Precio congelado:** `Detalle_Venta.precio_unitario` guarda el precio con la liquidación ya aplicada. Por ejemplo, un producto de \$42.000 con 20 % de liquidación se registra a \$33.600.
- **Descuento por método de pago:** `Venta.descuento_aplicado` es el porcentaje del método de pago aplicado sobre la suma de los subtotales, y `Venta.total` es el importe final. Ambos se cargan ya calculados. Ejemplo: la venta 1 suma \$75.000 en renglones, con 15 % de descuento por pago en efectivo queda en \$63.750.
- **Cliente recurrente:** el cliente 1 registra dos compras (ventas 1 y 8), por canal y método de pago distintos.
- **Ventas sin descuento:** las pagadas con tarjeta de crédito (ventas 2, 6 y 8) tienen `descuento_aplicado` en `0.00`.
