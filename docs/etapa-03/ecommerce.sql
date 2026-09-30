IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'tienda_ropa')
BEGIN
    CREATE DATABASE tienda_ropa;
END;
GO

USE tienda_ropa;
GO
-- 1. TABLA: Categoria
CREATE TABLE Categoria (
    Id_Categoria INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion VARCHAR(255) NULL,
    CONSTRAINT PK_Categoria PRIMARY KEY (Id_Categoria)
);
GO

-- 2. TABLA: Talle
CREATE TABLE Talle (
    Id_Talle INT IDENTITY(1,1) NOT NULL,
    descripcion VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Talle PRIMARY KEY (Id_Talle)
);
GO

-- 3. TABLA: Metodo_pago
CREATE TABLE Metodo_pago (
    Id_metodo_pago INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    porcentaje_descuento DECIMAL(5, 2) NOT NULL CONSTRAINT DF_Metodo_pago_descuento DEFAULT (0.00),
    CONSTRAINT PK_Metodo_pago PRIMARY KEY (Id_metodo_pago),
    CONSTRAINT CHK_Metodo_pago_descuento CHECK (porcentaje_descuento >= 0 AND porcentaje_descuento <= 100)
);
GO

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
GO

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
GO

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
GO

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
GO

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
GO