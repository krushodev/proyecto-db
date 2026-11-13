# 4. Reglas de negocio

## Gestión de productos y stock

- **RN.01** — Cada prenda pertenece a una variante de producto (por ejemplo, “Jean recto azul”) y se gestiona por talle. Una misma variante puede tener múltiples talles, cada uno con stock propio e independiente. Los accesorios, que no requieren talle, se gestionan con un talle único genérico.
- **RN.02** — El stock se descuenta automáticamente por talle al confirmarse una venta. No se puede completar una venta si la cantidad solicitada supera el stock disponible de ese talle.

---

## Categorías

- **RN.03** — Todo producto pertenece a una única categoría. Una misma categoría puede agrupar múltiples productos.

---

## Clientes

- **RN.04** — Toda venta queda asociada a un cliente registrado (con nombre y datos de contacto). Si el cliente compra por primera vez, sus datos se registran en el momento de la compra, tanto en el canal online como en el presencial.

---

## Precios y descuentos

- **RN.05** — Cada producto tiene un precio de lista, que es el precio base de referencia.
- **RN.06** — Si el producto está en liquidación, se aplica un descuento sobre el precio de lista, obteniendo un precio de liquidación.
- **RN.07** — Sobre el precio vigente (de lista o de liquidación, según corresponda), se aplica un descuento adicional cuyo porcentaje depende del método de pago elegido (efectivo, transferencia, tarjeta de débito y Mercado Pago tienen descuento; las tarjetas de crédito y la gift card no).
- **RN.10** — Los clientes frecuentes reciben un descuento adicional según el total de sus compras anteriores: 5 % si superan \$200.000 y 10 % si superan \$500.000. Este descuento se suma al de RN.07 (con un tope del 100 %) y se aplica sobre el precio vigente.

---

## Detalle de compra

- **RN.08** — El precio unitario de cada producto se registra en el detalle de la venta en el momento de concretarse, de forma independiente al precio vigente en el catálogo. Así, si el precio del producto cambia con posterioridad, las ventas ya realizadas no se ven afectadas.

---

## Métodos de pago

- **RN.09** — La venta admite como método de pago efectivo, transferencia bancaria, tarjeta de débito, tarjeta de crédito (1 pago, 3 o 6 cuotas), Mercado Pago o gift card. El método seleccionado determina el porcentaje de descuento adicional descripto en RN.07.
