# Base de datos y seguridad

Backend: Supabase (PostgreSQL). El esquema se versiona en
`supabase/migrations/`.

## 1. Tablas

| Tabla | Contenido |
|---|---|
| `categorias` | Secciones del catálogo y su estado |
| `productos` | Nombre, descripción, precio COP, categoría, foto y disponibilidad lógica |
| `codigos_producto` | Códigos de barras/QR asociados; el principal es de 14 dígitos |
| `pedidos` | Orden, cliente, origen, estado, total, caducidad e idempotencia |
| `detalle_pedido` | Ítems con nombre y precio históricos, cantidad y descuento |
| `perfiles` | Nombre visible del usuario |
| `roles_usuario` | Rol `administrador` o `personal` |
| `tiendas` | Nombre, dirección y coordenadas de la tienda |
| `promociones` | Nombre, tipo, cantidades, precio de paquete, banner y vigencia |
| `promocion_productos` | Productos incluidos en cada promoción |
| `tokens_recogida` | Soporte histórico del flujo de recogida; no se usa en la app actual |

## 2. RPC usadas por la app

| RPC | Quién | Qué hace |
|---|---|---|
| `crear_pedido` | Comprador | Valida precios y disponibilidad, aplica promociones, calcula total, controla idempotencia y caducidad |
| `cancelar_pedido` | Comprador / caja | Cancela solo pedidos `pendiente_pago` |
| `crear_producto` | Administrador | Crea el producto y genera su código principal de 14 dígitos |
| `editar_producto` | Administrador | Edita datos sin regenerar el código |
| `establecer_estado_producto` | Administrador | Activa/desactiva (borrado lógico) |
| `registrar_codigo_producto` | Administrador | Añade un código adicional; rechaza duplicados |
| `corregir_codigo_producto` | Administrador | Corrige un código existente |
| `configurar_tienda` | Administrador | Guarda nombre, dirección y coordenadas |
| `guardar_promocion` | Administrador | Crea/actualiza una promoción y sus productos |
| `listar_personal` | Administrador | Lista cuentas con rol |
| `asignar_rol_personal` | Administrador | Asigna/quita rol por UUID; bloquea autocambios |
| `asignar_rol_personal_por_correo` | Administrador | Igual, por correo |
| `listar_pedidos_personal` | Caja | Lista y filtra pedidos con el nombre del cliente |
| `detalle_pedido_personal` | Caja | Recibo completo |
| `buscar_pedido_personal` | Caja | Busca por número visible o UUID |
| `confirmar_pago_pedido` | Caja | `pendiente_pago` → `pagado`, idempotente |
| `confirmar_entrega_pedido` | Caja | `pagado` → `entregado`, idempotente |
| `reporte_ventas` | Caja | Ventas, pedidos, ticket promedio y top productos por periodo |
| `es_administrador` / `es_personal` | Autenticado | Comprueban el rol en el servidor |

Funciones internas (no ejecutables por el cliente):
`_aplicar_promocion_a_detalle()` y
`_actualizar_total_pedido_con_promociones()`, invocadas por triggers sobre
`detalle_pedido`.

### Disponibilidad

La compra se controla con `productos.activo`: un producto activo se puede pedir
y uno desactivado se rechaza al crear la orden. No hay conteo de existencias ni
descuento de inventario. Cuando un producto se agota en la tienda se desactiva
desde administración y deja de aparecer en el catálogo; al reponerlo se
reactiva.

`stock_demo` solo actúa como tope técnico del selector de cantidad: se fija en
100, el mismo máximo por producto que valida `crear_pedido`, para que el
cliente no pueda pedir una cantidad que el servidor vaya a rechazar.

## 3. Promociones

Tipos admitidos por `guardar_promocion`:

| Tipo | Regla |
|---|---|
| `dos_por_uno` | 2 unidades, se cobra 1 |
| `tres_por_dos` | 3 unidades, se cobran 2 |
| `precio_paquete` | Paquete de N unidades a un precio fijo |

El descuento se calcula en el servidor al crear el pedido; el cliente solo
muestra el resultado. La lectura de promociones activas es pública y la
escritura exige `es_administrador()`.

## 4. Storage

- Bucket público: `producto-imagenes`.
- Ruta usada por el catálogo: `catalogo/<uuid-del-producto>.jpg`.
- Lectura pública; subida y borrado solo para administradores
  (`public.es_administrador()`).
- Límite y tipos MIME definidos en
  `20261021120000_bucket_producto_imagenes.sql`.

## 5. Seguridad

- RLS activo en todas las tablas públicas.
- El comprador solo ve sus propios pedidos.
- Caja y administración reciben únicamente los datos necesarios; no se exponen
  correos, teléfonos ni datos de autenticación del cliente.
- Las RPC `SECURITY DEFINER` fijan `search_path` y validan el rol dentro de la
  transacción.
- La clave usada por la app es la **publicable**; `service_role` no se usa.
- Los precios y nombres históricos se conservan en `detalle_pedido`.

## 6. Migraciones aplicadas

| Versión | Nombre |
|---|---|
| `20261021043230` | `mercamigo_esquema_y_catalogo_inicial` |
| `20261021063714` | `20261021001000_crear_pedido` |
| `20261021063804` | `20261021002000_roles_y_administracion` |
| `20261021065012` | `20261021004000_endurecer_permisos` |
| `20261021201249` | `bucket_producto_imagenes` |
| `20261021234427` | `zona_horaria_predeterminada_bogota` |
| `20261122151831` | `generar_codigos_productos_automaticos_barras` |
| `20261125120000` | `personal_caja_reportes` |
| `20261125130000` | `personal_por_correo` |
| `20261125140000` | `promociones_admin` |
| `20261125231057` | `fix_public_promotion_read` |
| `20261125235500` | `disponibilidad_sin_stock` |

Los archivos `20261021003000_validacion_token_recogida.sql`,
`20261021100000_admin_productos_y_codigos.sql` y
`20261021110000_caducidad_pedidos.sql` se conservan como referencia; el flujo
actual no depende de ellos o su contenido quedó incluido en las migraciones
aplicadas.

## 7. Verificación rápida

```sql
-- Roles y funciones esperadas
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'es_administrador','es_personal','crear_pedido','cancelar_pedido',
    'crear_producto','editar_producto','establecer_estado_producto',
    'registrar_codigo_producto','configurar_tienda','guardar_promocion',
    'listar_personal','asignar_rol_personal_por_correo',
    'listar_pedidos_personal','detalle_pedido_personal',
    'buscar_pedido_personal','confirmar_pago_pedido',
    'confirmar_entrega_pedido','reporte_ventas'
  )
order by proname;

-- Estado del catálogo
select count(*) filter (where activo) as activos,
       count(*) filter (where imagen_url is null) as sin_foto
from public.productos;
```
