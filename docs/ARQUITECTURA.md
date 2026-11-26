# Arquitectura de Mercamigo

## 1. Visión general

Mercamigo es una app Flutter con un backend Supabase. La app **no decide**
precios, stock, roles ni transiciones de estado: esas reglas viven en funciones
SQL `SECURITY DEFINER` y en políticas RLS. El cliente solo presenta datos y
solicita operaciones.

```text
┌──────────────────────────────┐
│ UI (screens + widgets)       │
│ Provider (estado)            │
│ Repositorios                 │
│ Servicios (Supabase, cámara) │
└──────────────┬───────────────┘
               │ HTTPS (clave publicable)
┌──────────────▼───────────────┐
│ Supabase                     │
│ Auth · PostgREST · Storage   │
│ RPC SECURITY DEFINER + RLS   │
└──────────────────────────────┘
```

## 2. Capas

| Carpeta | Responsabilidad |
|---|---|
| `lib/core/` | Configuración, tema, tipografías, fechas de Bogotá, moneda, validadores |
| `lib/data/models/` | Modelos inmutables (`Product`, `Order`, `StaffOrder`, `Promotion`, …) |
| `lib/data/local/` | `KeyValueStore` sobre `shared_preferences` |
| `lib/data/catalog/` | Catálogo de respaldo y recursos locales del prototipo |
| `lib/repositories/` | Acceso a datos: catálogo, carrito, pedidos, perfil, tienda, administración, caja |
| `lib/services/` | Supabase, autenticación, cámara, escáner, imágenes, compartir, ubicación |
| `lib/state/` | Controladores de Provider (carrito, catálogo, pedidos, recuperación) |
| `lib/ui/` | Pantallas y widgets; una pantalla por archivo |

## 3. Arranque

1. `main.dart` inicializa Flutter y carga la configuración de `--dart-define`.
2. `BootstrapScreen` prepara el almacenamiento local y el cliente Supabase.
3. `AuthGate` decide la interfaz según la sesión y el rol confirmado por el
   servidor:
   - sin sesión → `LoginScreen`;
   - comprador → `HomeScreen`;
   - administrador → `AdminPanelScreen`;
   - personal de caja → `StaffHomeScreen`.
4. Mientras se consulta el rol se muestra un splash neutro para evitar
   parpadeos entre interfaces.

## 4. Flujos principales

### Compra

```text
Inicio → origen (tienda/recoger)
      → escáner o catálogo → detalle
      → carrito → resumen
      → crear_pedido (servidor)
      → orden generada (número + Code 128 + caducidad)
```

- El carrito se guarda en el dispositivo y solo se vacía si el servidor confirma
  la orden.
- `crear_pedido` recalcula precios, aplica promociones, valida stock y devuelve
  el total y la caducidad reales.
- La orden nace `pendiente_pago` y caduca a los 15 minutos según el reloj del
  servidor.

### Caja

```text
Órdenes pendientes → buscar/escanear
                   → confirmar_pago_pedido   (pendiente_pago → pagado)
                   → confirmar_entrega_pedido (pagado → entregado)
```

Ambas RPC son idempotentes y rechazan estados inválidos.

### Administración

```text
Panel → Productos → alta/edición/desactivar
      → Promociones → guardar_promocion
      → Tienda → configurar_tienda
      → Mi cuenta
```

## 5. Persistencia

- **Servidor:** catálogo, códigos, tienda, perfiles, roles, pedidos, promociones
  y reportes.
- **Dispositivo:** carrito, origen de compra, historial de escaneos y ajustes
  locales.
- **Storage:** fotos de productos en el bucket público `producto-imagenes`.

## 6. Configuración

Variables en tiempo de compilación (`lib/core/config/app_config.dart`):

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Sin ellas la app funciona en **modo local**: catálogo y pedidos solo en el
dispositivo, sin caja, reportes ni roles.

## 7. Decisiones de diseño

- **Servidor autoritativo:** precios, totales, stock y estados se validan en SQL.
- **RPC en lugar de escrituras directas:** el cliente no puede alterar el
  catálogo ni los pedidos saltándose las reglas.
- **Roles en el servidor:** `es_administrador()` y `es_personal()`; la UI solo
  oculta accesos.
- **Borrado lógico:** desactivar un producto conserva códigos e historial.
- **Códigos sin secretos:** el código de una orden es su número visible, no un
  token de autorización.
- **Idempotencia:** creación de pedidos, pago y entrega toleran reintentos.
- **Zona horaria:** se guarda en UTC y se muestra en `America/Bogota`.

## 8. Pruebas

- Pruebas unitarias y de widgets en `test/`.
- Pruebas de integración reales en `test/supabase_integration_test.dart`, que se
  omiten si no se compila con `--dart-define`.
- Las pruebas de layout cargan las fuentes reales para medir con las métricas
  del prototipo.
