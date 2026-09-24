# Modelo Relacional – Intensa Jeans

A continuación se presenta la especificación formal del **Modelo Relacional** derivado del Diagrama Entidad-Relación (DER) del sistema, detallando esquemas de tablas, claves primarias (PK), claves foráneas (FK), tipos de datos y relaciones.

---

## 1. Esquema Relacional de Tablas

### 1.1. `Categoria`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Categoria` | `INT` | **PK**, Auto Increment | Identificador único de la categoría |
| `nombre` | `VARCHAR(100)` | NOT NULL | Nombre descriptivo de la categoría |
| `descripcion` | `VARCHAR(255)` | NULL | Breve detalle de la categoría |

---

### 1.2. `Producto`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Producto` | `INT` | **PK**, Auto Increment | Identificador único del producto |
| `nombre` | `VARCHAR(150)` | NOT NULL | Nombre del producto |
| `descripcion` | `TEXT` | NULL | Descripción detallada de la prenda |
| `precio_lista` | `DECIMAL(10,2)` | NOT NULL, Check (> 0) | Precio unitario base de lista |
| `en_liquidacion` | `BOOLEAN` | NOT NULL, Default FALSE | Indica si la prenda está en liquidación |
| `porcentaje_liquidacion` | `DECIMAL(5,2)` | NOT NULL, Default 0.00 | Porcentaje de descuento por liquidación |
| `Id_Categoria` | `INT` | **FK** | Referencia a `Categoria(Id_Categoria)` |

---

### 1.3. `Talle`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Talle` | `INT` | **PK**, Auto Increment | Identificador único del talle |
| `descripcion` | `VARCHAR(50)` | NOT NULL | Denominación del talle (ej. S, M, L, 42, Genérico) |

---

### 1.4. `Producto_Talle`
*Resuelve la relación muchos a muchos entre Producto y Talle, administrando el stock específico.*

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Talle` | `INT` | **PK**, **FK** | Referencia a `Talle(Id_Talle)` |
| `Id_Producto` | `INT` | **PK**, **FK** | Referencia a `Producto(Id_Producto)` |
| `stock` | `INT` | NOT NULL, Check (>= 0) | Stock disponible para ese talle |

> **Clave Primaria Compuesta:** `(Id_Talle, Id_Producto)`

---

### 1.5. `Cliente`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Cliente` | `INT` | **PK**, Auto Increment | Identificador único del cliente |
| `nombre` | `VARCHAR(100)` | NOT NULL | Nombre(s) del cliente |
| `apellido` | `VARCHAR(100)` | NOT NULL | Apellido(s) del cliente |
| `dni` | `VARCHAR(20)` | UNIQUE, NOT NULL | Documento Nacional de Identidad |
| `telefono` | `VARCHAR(30)` | NULL | Teléfono de contacto |
| `email` | `VARCHAR(150)` | UNIQUE, NULL | Correo electrónico |
| `direccion` | `VARCHAR(255)` | NULL | Domicilio |

---

### 1.6. `Metodo_pago`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_metodo_pago` | `INT` | **PK**, Auto Increment | Identificador único del medio de pago |
| `nombre` | `VARCHAR(50)` | NOT NULL | Nombre (Efectivo, Débito, Transferencia, etc.) |
| `porcentaje_descuento` | `DECIMAL(5,2)` | NOT NULL, Default 0.00 | Descuento bonificado según medio |

---

### 1.7. `Venta`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `Id_Venta` | `INT` | **PK**, Auto Increment | Identificador único de la transacción |
| `fecha_hora` | `DATETIME` | NOT NULL | Fecha y hora de la venta |
| `canal` | `VARCHAR(30)` | NOT NULL | Canal (`Mostrador` / `Online`) |
| `descuento_aplicado` | `DECIMAL(10,2)` | NOT NULL, Default 0.00 | Monto descontado por pago/promoción |
| `total` | `DECIMAL(10,2)` | NOT NULL | Importe final de la transacción |
| `Id_Cliente` | `INT` | **FK** | Referencia a `Cliente(Id_Cliente)` |
| `Id_metodo_pago` | `INT` | **FK** | Referencia a `Metodo_pago(Id_metodo_pago)` |

---

### 1.8. `Detalle_Venta`
| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `nro_item` | `INT` | **PK** | Número secuencial de renglón en la venta |
| `Id_Venta` | `INT` | **PK**, **FK** | Referencia a `Venta(Id_Venta)` |
| `cantidad` | `INT` | NOT NULL, Check (> 0) | Unidades vendidas |
| `precio_unitario` | `DECIMAL(10,2)` | NOT NULL | Precio unitario histórico al momento de la venta |
| `subtotal` | `DECIMAL(10,2)` | NOT NULL | Subtotal (`cantidad * precio_unitario`) |
| `Id_Talle` | `INT` | **FK** | Referencia a `Producto_Talle(Id_Talle)` |
| `Id_Producto` | `INT` | **FK** | Referencia a `Producto_Talle(Id_Producto)` |

> **Clave Primaria Compuesta:** `(nro_item, Id_Venta)`  
> **Clave Foránea Compuesta hacia Producto_Talle:** `(Id_Talle, Id_Producto)` referenciando a `Producto_Talle(Id_Talle, Id_Producto)`

---

## 2. Relaciones e Integridad Referencial

1. **`Producto` → `Categoria`:** N a 1 (`Producto.Id_Categoria` → `Categoria.Id_Categoria`).
2. **`Producto_Talle` → `Producto` y `Talle`:** Resuelve la relación N a M entre productos y talles con claves foráneas compuestas.
3. **`Venta` → `Cliente`:** N a 1 (`Venta.Id_Cliente` → `Cliente.Id_Cliente`).
4. **`Venta` → `Metodo_pago`:** N a 1 (`Venta.Id_metodo_pago` → `Metodo_pago.Id_metodo_pago`).
5. **`Detalle_Venta` → `Venta`:** N a 1 (`Detalle_Venta.Id_Venta` → `Venta.Id_Venta`).
6. **`Detalle_Venta` → `Producto_Talle`:** N a 1 mediante FK compuesta `(Id_Talle, Id_Producto)` apuntando a `Producto_Talle(Id_Talle, Id_Producto)` para trazabilidad y descuento de inventario.