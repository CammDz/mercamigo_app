# Manual de usuario

## 1. Primer acceso

1. Abrir la app.
2. **Crear cuenta** con nombre, correo y contraseña, o **iniciar sesión** si ya
   existe.
3. Confirmar el correo desde el enlace recibido (la confirmación es
   obligatoria).
4. Si se olvidó la contraseña, usar **Recuperar contraseña**: la app envía un
   código y permite definir una nueva.

La interfaz que se muestra depende del rol confirmado por el servidor:

- comprador → inicio de compra;
- administrador → panel de administración;
- personal de caja → órdenes, historial y reportes.

## 2. Comprador

### Comprar en la tienda

1. Elegir **Estoy en la tienda**.
2. Escanear el código del producto o buscarlo en el catálogo.
3. Agregar al carrito y ajustar cantidades.
4. Revisar el resumen y confirmar el pedido.
5. Mostrar el número y el código de barras de la orden en caja.

### Pedir para recoger

1. Elegir **Pedir para recoger**.
2. Explorar categorías o buscar productos.
3. Agregar al carrito, revisar y confirmar.
4. Presentar la orden en caja para pagar y recoger.

### Reglas útiles

- El pedido caduca a los **15 minutos** si no se paga.
- Solo se puede cancelar un pedido **pendiente de pago**.
- El pago es presencial en caja; la app no cobra en línea.
- El carrito se conserva si falla la creación del pedido.
- En **Mis pedidos** se consulta el estado y el detalle con los precios del
  momento de la compra.

## 3. Administrador

### Productos

- **Crear producto:** nombre, descripción, precio, categoría y foto. El código
  de 14 dígitos se genera solo y se muestra al terminar.
- **Editar:** cambia datos y foto sin alterar el código.
- **Desactivar/reactivar:** el producto desactivado deja de aparecer en el
  catálogo, pero conserva códigos e historial.
- La búsqueda filtra dentro de la sección activa.

### Promociones

- Tipos: **2 × 1**, **3 × 2** y **precio de paquete**.
- Se eligen los productos incluidos y, opcionalmente, un banner.
- El descuento se aplica en el servidor al crear el pedido.

### Tienda

- Nombre, dirección y coordenadas.
- El mapa permite elegir el punto; el comprador solo consulta la ubicación.

## 4. Personal de caja

1. Abrir **Órdenes** y localizar el pedido por número o escaneando su código.
2. Revisar el recibo: cliente, origen, ítems, cantidades y total.
3. **Confirmar pago recibido** cuando el cliente pague.
4. **Confirmar entrega** cuando se entregue el pedido.
5. Consultar **Historial** y **Reportes** por día, semana o mes.

Un pedido caducado o cancelado no se cobra; uno no pagado no se entrega. Las
acciones son idempotentes: repetirlas no duplica el cobro ni la entrega.

## 5. Preguntas frecuentes

**¿Se puede pagar con tarjeta o PSE dentro de la app?**
No. El pago se realiza en caja.

**¿Qué pasa si el pedido caduca?**
Debe crearse uno nuevo; el anterior queda como `expirado`.

**¿El código de la orden sirve para autorizar la entrega?**
No. La caja verifica el rol y el estado en el servidor.

**¿Por qué un producto no aparece en el catálogo?**
Puede estar desactivado por administración. Sus pedidos anteriores se
conservan.

**¿La app funciona sin internet?**
Solo en modo local (sin Supabase): catálogo y pedidos quedan en el dispositivo,
sin caja, reportes ni roles.
