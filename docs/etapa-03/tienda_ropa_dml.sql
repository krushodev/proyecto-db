/* =====================================================================
   SCRIPT DML - Poblado inicial de la base tienda_ropa
   ---------------------------------------------------------------------
   - Correr DESPUÉS del script DDL (ecommerce.sql), sobre la base
     recién creada (tablas vacías y sin uso previo).
   - Las tablas con IDENTITY NO reciben el ID: lo genera SQL Server.
     Como la base es nueva, los IDs salen 1, 2, 3... en el mismo orden
     en que están escritos los INSERT. Las FK de más abajo usan esos
     números, así que NO cambies el orden de las filas.
   - Todo va en una transacción: si algo falla, no queda nada a medias.
   - Los datos son coherentes entre sí:
       * precio_unitario = precio_lista con la liquidación aplicada
       * subtotal        = cantidad * precio_unitario
       * descuento       = suma de subtotales * % del método de pago
       * total           = suma de subtotales - descuento
   ===================================================================== */

USE tienda_ropa;
GO

-- =====================================================================
-- 1. Categoria (8 registros) -> IDs 1 a 8
-- =====================================================================
INSERT INTO Categoria (nombre, descripcion) VALUES
('Jeans Mujer',  'Pantalones de jean para mujer en distintos cortes'),   -- 1
('Jeans Hombre', 'Pantalones de jean para hombre en distintos cortes'),  -- 2
('Camperas',     'Camperas de jean y abrigos livianos'),                 -- 3
('Remeras',      'Remeras de algodón lisas y estampadas'),               -- 4
('Camisas',      'Camisas de jean y gabardina'),                         -- 5
('Shorts',       'Shorts de jean para temporada de verano'),             -- 6
('Polleras',     'Polleras de jean cortas y midi'),                      -- 7
('Accesorios',   'Cinturones, gorras y otros complementos');             -- 8

-- =====================================================================
-- 2. Talle (10 registros) -> IDs 1 a 10
-- =====================================================================
INSERT INTO Talle (descripcion) VALUES
('36'),     -- 1
('38'),     -- 2
('40'),     -- 3
('42'),     -- 4
('44'),     -- 5
('S'),      -- 6
('M'),      -- 7
('L'),      -- 8
('XL'),     -- 9
('Único');  -- 10

-- =====================================================================
-- 3. Metodo_pago (8 registros) -> IDs 1 a 8
-- =====================================================================
INSERT INTO Metodo_pago (nombre, porcentaje_descuento) VALUES
('Efectivo',                     15.00),  -- 1
('Transferencia bancaria',       10.00),  -- 2
('Tarjeta de débito',             5.00),  -- 3
('Tarjeta de crédito 1 pago',     0.00),  -- 4
('Tarjeta de crédito 3 cuotas',   0.00),  -- 5
('Mercado Pago',                  5.00),  -- 6
('Tarjeta de crédito 6 cuotas',   0.00),  -- 7
('Gift card',                     0.00);  -- 8

-- =====================================================================
-- 4. Cliente (10 registros) -> IDs 1 a 10
-- =====================================================================
INSERT INTO Cliente (nombre, apellido, dni, telefono, email, direccion) VALUES
('Lucía',     'Fernández', '38456123', '3794-551234', 'lucia.fernandez@mail.com',  'Junín 1250, Corrientes'),          -- 1
('Martín',    'Gómez',     '35987412', '3794-662345', 'martin.gomez@mail.com',     'San Martín 840, Corrientes'),      -- 2
('Sofía',     'Romero',    '41236987', '3794-773456', 'sofia.romero@mail.com',     'Av. 3 de Abril 520, Corrientes'),  -- 3
('Juan',      'Benítez',   '33654789', '3624-484567', 'juan.benitez@mail.com',     'Av. Alberdi 1100, Resistencia'),   -- 4
('Camila',    'Acosta',    '40125874', '3794-395678', 'camila.acosta@mail.com',    'La Rioja 675, Corrientes'),        -- 5
('Federico',  'Sosa',      '36874125', NULL,          'federico.sosa@mail.com',    'Pellegrini 930, Corrientes'),      -- 6
('Valentina', 'Ramírez',   '42369851', '3794-516789', 'valen.ramirez@mail.com',    NULL),                              -- 7
('Nicolás',   'Ojeda',     '37741258', '3624-627890', 'nicolas.ojeda@mail.com',    'Av. Sarmiento 2100, Resistencia'), -- 8
('Agustina',  'Vallejos',  '43852147', '3794-738901', 'agus.vallejos@mail.com',    'Mendoza 410, Corrientes'),         -- 9
('Diego',     'Cabrera',   '34963258', '3794-849012', 'diego.cabrera@mail.com',    'Bolívar 1580, Corrientes');        -- 10

-- =====================================================================
-- 5. Producto (10 registros) -> IDs 1 a 10
--    Los que están en liquidación tienen su % cargado; el resto, 0.
-- =====================================================================
INSERT INTO Producto (nombre, descripcion, precio_lista, en_liquidacion, porcentaje_liquidacion, Id_Categoria) VALUES
('Jean Mom Tiro Alto',         'Jean de mujer corte mom, tiro alto, azul clásico',   45000.00, 0,  0.00, 1),  -- 1
('Jean Skinny Negro',          'Jean de mujer chupín elastizado color negro',         42000.00, 1, 20.00, 1),  -- 2
('Jean Recto Clásico',         'Jean de hombre corte recto, denim rígido',            48000.00, 0,  0.00, 2),  -- 3
('Jean Slim Fit Celeste',      'Jean de hombre slim fit, lavado celeste',             46000.00, 1, 15.00, 2),  -- 4
('Campera de Jean Oversize',   'Campera de jean unisex calce amplio',                 68000.00, 0,  0.00, 3),  -- 5
('Remera Básica Algodón',      'Remera lisa 100% algodón, varios colores',            15000.00, 0,  0.00, 4),  -- 6
('Camisa de Jean Manga Larga', 'Camisa de jean liviano con botones a presión',        38000.00, 1, 10.00, 5),  -- 7
('Short de Jean Tiro Alto',    'Short de jean con ruedo desflecado',                  28000.00, 0,  0.00, 6),  -- 8
('Pollera de Jean Midi',       'Pollera de jean largo midi con tajo lateral',         35000.00, 0,  0.00, 7),  -- 9
('Cinturón de Cuero',          'Cinturón de cuero vacuno con hebilla metálica',       18000.00, 1, 25.00, 8);  -- 10

-- =====================================================================
-- 6. Producto_Talle (28 registros) -> sin IDENTITY, PK compuesta
--    Jeans/shorts en talles numéricos, prendas de arriba en letras,
--    accesorios en talle único.
-- =====================================================================
INSERT INTO Producto_Talle (Id_Producto, Id_Talle, stock) VALUES
-- Jean Mom Tiro Alto
(1, 1, 12), (1, 2, 15), (1, 3, 10),
-- Jean Skinny Negro
(2, 1, 8),  (2, 2, 6),
-- Jean Recto Clásico
(3, 3, 10), (3, 4, 12), (3, 5, 7),
-- Jean Slim Fit Celeste
(4, 3, 9),  (4, 4, 5),
-- Campera de Jean Oversize
(5, 6, 5),  (5, 7, 8),  (5, 8, 6),
-- Remera Básica Algodón
(6, 6, 20), (6, 7, 25), (6, 8, 18), (6, 9, 10),
-- Camisa de Jean Manga Larga
(7, 7, 7),  (7, 8, 6),
-- Short de Jean Tiro Alto
(8, 1, 10), (8, 2, 10),
-- Pollera de Jean Midi
(9, 6, 6),  (9, 7, 6),
-- Cinturón de Cuero
(10, 10, 30);

-- =====================================================================
-- 7. Venta (10 registros) -> IDs 1 a 10
--    descuento_aplicado y total ya calculados según el detalle.
-- =====================================================================
INSERT INTO Venta (fecha_hora, canal, descuento_aplicado, total, Id_Cliente, Id_metodo_pago) VALUES
('2026-08-03 10:15:00', 'Local',     11250.00, 63750.00, 1, 1),  -- 1:  75000 - 15%
('2026-08-05 18:40:00', 'Web',           0.00, 48000.00, 2, 4),  -- 2:  48000 - 0%
('2026-08-08 21:05:00', 'Instagram',  4710.00, 42390.00, 3, 2),  -- 3:  47100 - 10%
('2026-08-12 14:30:00', 'Web',        3400.00, 64600.00, 4, 6),  -- 4:  68000 - 5%
('2026-08-15 11:00:00', 'Local',      3380.00, 64220.00, 5, 3),  -- 5:  67600 - 5%
('2026-08-20 17:20:00', 'Local',         0.00, 63000.00, 6, 5),  -- 6:  63000 - 0%
('2026-08-24 09:45:00', 'WhatsApp',   6750.00, 38250.00, 7, 1),  -- 7:  45000 - 15%
('2026-09-02 20:10:00', 'Web',           0.00, 82200.00, 1, 7),  -- 8:  82200 - 0% (cliente que repite)
('2026-09-10 16:00:00', 'Local',      9000.00, 81000.00, 8, 2),  -- 9:  90000 - 10%
('2026-09-18 19:30:00', 'Instagram',  2150.00, 40850.00, 9, 6);  -- 10: 43000 - 5%

-- =====================================================================
-- 8. Detalle_Venta (17 registros) -> sin IDENTITY, PK (Id_Venta, nro_item)
--    precio_unitario = precio con liquidación ya aplicada:
--      P2 42000 -20% = 33600 | P4 46000 -15% = 39100
--      P7 38000 -10% = 34200 | P10 18000 -25% = 13500
-- =====================================================================
INSERT INTO Detalle_Venta (Id_Venta, nro_item, Id_Producto, Id_Talle, cantidad, precio_unitario, subtotal) VALUES
-- Venta 1
(1, 1, 1, 2,  1, 45000.00, 45000.00),
(1, 2, 6, 7,  2, 15000.00, 30000.00),
-- Venta 2
(2, 1, 3, 4,  1, 48000.00, 48000.00),
-- Venta 3
(3, 1, 2, 1,  1, 33600.00, 33600.00),
(3, 2, 10, 10, 1, 13500.00, 13500.00),
-- Venta 4
(4, 1, 5, 7,  1, 68000.00, 68000.00),
-- Venta 5
(5, 1, 4, 3,  1, 39100.00, 39100.00),
(5, 2, 6, 8,  1, 15000.00, 15000.00),
(5, 3, 10, 10, 1, 13500.00, 13500.00),
-- Venta 6
(6, 1, 9, 6,  1, 35000.00, 35000.00),
(6, 2, 8, 2,  1, 28000.00, 28000.00),
-- Venta 7
(7, 1, 6, 6,  3, 15000.00, 45000.00),
-- Venta 8
(8, 1, 7, 7,  1, 34200.00, 34200.00),
(8, 2, 3, 3,  1, 48000.00, 48000.00),
-- Venta 9
(9, 1, 1, 3,  2, 45000.00, 90000.00),
-- Venta 10
(10, 1, 8, 1, 1, 28000.00, 28000.00),
(10, 2, 6, 9, 1, 15000.00, 15000.00);

GO


