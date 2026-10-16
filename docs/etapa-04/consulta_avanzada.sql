-- ============================================================================
-- SCRIPT DE BASE DE DATOS: CONSULTA DE NEGOCIO AVANZADA
-- ============================================================================

-- 1. CREACIÓN DE LA ESTRUCTURA DE TABLAS (DDL)
-- ----------------------------------------------------------------------------

CREATE TABLE Persona (
    codigo INT PRIMARY KEY IDENTITY(1,1),
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    telefono VARCHAR(20),
    direccion VARCHAR(100)
);

CREATE TABLE Cliente (
    id_cliente INT PRIMARY KEY IDENTITY(1,1),
    codigo_persona INT NOT NULL,
    CONSTRAINT FK_Cliente_Persona FOREIGN KEY (codigo_persona) 
        REFERENCES Persona(codigo) ON DELETE CASCADE
);

CREATE TABLE Proveedor (
    id_proveedor INT PRIMARY KEY IDENTITY(1,1),
    codigo_persona INT NOT NULL,
    provincia VARCHAR(50),
    CONSTRAINT FK_Proveedor_Persona FOREIGN KEY (codigo_persona) 
        REFERENCES Persona(codigo) ON DELETE CASCADE
);

CREATE TABLE Producto (
    codigo INT PRIMARY KEY IDENTITY(1,1),
    descripcion VARCHAR(100) NOT NULL,
    precio DECIMAL(10,2) NOT NULL,
    stock INT DEFAULT 0
);

CREATE TABLE Compra (
    id_compra INT PRIMARY KEY IDENTITY(1,1),
    fecha DATE NOT NULL,
    id_cliente INT NOT NULL,
    CONSTRAINT FK_Compra_Cliente FOREIGN KEY (id_cliente) 
        REFERENCES Cliente(id_cliente)
);

CREATE TABLE Detalle_Compra (
    id_compra INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL,
    PRIMARY KEY (id_compra, id_producto),
    CONSTRAINT FK_Detalle_Compra FOREIGN KEY (id_compra) 
        REFERENCES Compra(id_compra) ON DELETE CASCADE,
    CONSTRAINT FK_Detalle_Producto FOREIGN KEY (id_producto) 
        REFERENCES Producto(codigo)
);

-- ----------------------------------------------------------------------------
-- 2. INSERCIÓN DE DATOS DE PRUEBA (DML)
-- ----------------------------------------------------------------------------

-- Personas
INSERT INTO Persona (nombre, apellido, telefono, direccion) VALUES
('Lucía', 'Gómez', '1122334455', 'Av. Corrientes 1234'),
('Carlos', 'Fernández', '1133445566', 'Calle San Martín 456'),
('Juan', 'Pérez', '1144556677', 'Av. Belgrano 789'),
('Mariana', 'López', '1155667788', 'Mitre 321');

-- Clientes
INSERT INTO Cliente (codigo_persona) VALUES
(1), -- Lucía Gómez (id_cliente = 1)
(2), -- Carlos Fernández (id_cliente = 2)
(3), -- Juan Pérez (id_cliente = 3)
(4); -- Mariana López (id_cliente = 4)

-- Productos
INSERT INTO Producto (descripcion, precio, stock) VALUES
('Silla Ergonómica Oficina', 85000.00, 50),
('Escritorio Ejecutivo', 150000.00, 20),
('Lámpara LED Escritorio', 25000.00, 100),
('Organizador de Archivos', 15000.00, 200);

-- Compras (2024)
INSERT INTO Compra (fecha, id_cliente) VALUES
('2024-01-15', 1), -- Compra 1 (Lucía)
('2024-02-10', 1), -- Compra 2 (Lucía)
('2024-03-05', 1), -- Compra 3 (Lucía)
('2024-03-20', 1), -- Compra 4 (Lucía)
('2024-01-20', 2), -- Compra 5 (Carlos)
('2024-02-18', 2), -- Compra 6 (Carlos)
('2024-03-12', 2), -- Compra 7 (Carlos)
('2024-01-10', 3); -- Compra 8 (Juan)

-- Detalle de Compras
INSERT INTO Detalle_Compra (id_compra, id_producto, cantidad) VALUES
-- Compras de Lucía (Cliente 1)
(1, 1, 2), -- 2 Sillas
(1, 2, 1), -- 1 Escritorio
(2, 3, 4), -- 4 Lámparas
(3, 1, 1), -- 1 Silla
(4, 2, 2), -- 2 Escritorios
-- Compras de Carlos (Cliente 2)
(5, 1, 1), -- 1 Silla
(6, 3, 2), -- 2 Lámparas
(7, 4, 5), -- 5 Organizadores
-- Compras de Juan (Cliente 3)
(8, 4, 2); -- 2 Organizadores

-- ----------------------------------------------------------------------------
-- 3. CONSULTA DE NEGOCIO AVANZADA
-- ----------------------------------------------------------------------------
-- Objetivo: Reportar clientes VIP que hayan realizado al menos 3 compras distintas
-- y cuyo gasto total acumulado en el año 2024 supere el promedio general por cliente.

SELECT 
    p.codigo AS codigo_cliente,
    p.nombre,
    p.apellido,
    COUNT(DISTINCT c.id_compra) AS total_compras_realizadas,
    SUM(dc.cantidad) AS unidades_totales_compradas,
    SUM(dc.cantidad * prod.precio) AS monto_total_gastado
FROM Persona p
INNER JOIN Cliente cl ON p.codigo = cl.codigo_persona
INNER JOIN Compra c ON cl.id_cliente = c.id_cliente
INNER JOIN Detalle_Compra dc ON c.id_compra = dc.id_compra
INNER JOIN Producto prod ON dc.id_producto = prod.codigo
WHERE c.fecha >= '2024-01-01'
GROUP BY p.codigo, p.nombre, p.apellido
HAVING COUNT(DISTINCT c.id_compra) >= 3 
   AND SUM(dc.cantidad * prod.precio) > (
       -- Subconsulta: Calcula el gasto promedio general por cliente
       SELECT AVG(monto_cliente) 
       FROM (
           SELECT SUM(dc2.cantidad * pr2.precio) AS monto_cliente
           FROM Compra c2
           INNER JOIN Detalle_Compra dc2 ON c2.id_compra = dc2.id_compra
           INNER JOIN Producto pr2 ON dc2.id_producto = pr2.codigo
           GROUP BY c2.id_cliente
       ) AS sub_promedios
   )
ORDER BY monto_total_gastado DESC;