# Mercamigo

Aplicación Android en Flutter para la compra en tienda y el retiro de pedidos,
con catálogo digital, códigos de barras reales, caja y administración.

El diseño (azul/lila, tarjetas redondeadas, logo y tipografías Jaro + League
Spartan) sigue el prototipo de Figma
`https://www.figma.com/design/e5VVOAv4C13hgnFCMxU49w/App`.

El catálogo, los códigos, la tienda, las cuentas, los pedidos y los reportes
viven en el proyecto **Supabase `moviles-mercamigo`**
(`project_ref = kbbbwdoommxsczjliqlu`, PostgreSQL 17.11). El esquema existente
se conserva: los cambios se hicieron con migraciones aditivas.

> **Los códigos son de barras, no QR.** La app lee y dibuja Code 128 en el
> dispositivo. El código de una orden representa su **número visible**
> (`MCA-000123`); no es un token de autorización. La autorización para cobrar
> o entregar la decide el servidor según el rol de caja.

---

## 1. Requisitos

| Herramienta | Versión usada |
|---|---|
| Flutter | 3.47.7 (stable) |
| Dart | 3.13.5 |
| JDK | 21 (Temurin/Microsoft); 17 o 21 sirven, **no** 25 |
| Android SDK | platform 34/35/36, build-tools 35/36, NDK 28.2 |

```powershell
$env:ANDROID_HOME     = "C:\dev\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\dev\android-sdk"
$env:JAVA_HOME        = "C:\Program Files\Java\jdk-21.0.10"
$env:PATH             = "C:\dev\flutter\bin;C:\dev\android-sdk\platform-tools;$env:PATH"
```

---

## 2. Configuración y compilación

La configuración se pasa en tiempo de compilación con `--dart-define`; no hay
credenciales escritas en Dart.

```powershell
$env:SUPABASE_URL             = "https://<project-ref>.supabase.co"
$env:SUPABASE_PUBLISHABLE_KEY = "<supabase-publishable-key>"
```

Script único (usa la clave **publicable**; nunca `service_role`):

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1
# APK: build\app\outputs\flutter-apk\app-release.apk
```

Sin los `--dart-define` la app arranca en **modo local**: el catálogo y los
pedidos quedan solo en el dispositivo y las funciones de servidor (caja,
reportes, roles) no están disponibles.

### Firma y APK

- `applicationId`: `com.mercamigo.mercamigo_app` (sin cambios).
- El APK de release se firma con las claves de **debug** (valor por defecto de
  `flutter create`). Para publicar en Google Play hay que crear un keystore
  propio en `android/app/build.gradle.kts`. Cambiar la firma no altera el
  `applicationId`, pero sí impide actualizar instalaciones firmadas con la
  clave anterior: hay que desinstalar/reinstalar.
- El proyecto vive en OneDrive. `build/` puede ser un junction a
  `C:\dev\build_mercamigo` para evitar bloqueos de archivos; no se elimina sin
  comprobarlo.
- En Windows, Gradle y el daemon de Kotlin dejan ficheros abiertos en
  `build\<plugin>\...` y la recompilación falla con `Unable to delete
  directory`. `tool/build_apk.ps1` detiene ambos daemons y limpia los
  intermedios antes de compilar. Además `android/gradle.properties` usa
  `kotlin.compiler.execution.strategy=in-process`, así que no queda un daemon
  de Kotlin suelto tras la compilación.
- Usa JDK 17 o 21. Con Java 25 (el `java` del sistema) Gradle falla con
  `JAVA_HOME is set to an invalid directory`; el script busca un JDK válido.

### Ejecutar en un teléfono

```powershell
flutter devices
flutter run --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
            --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY
```

---

## 3. Cuentas y roles

| Rol | Cómo se obtiene | A dónde entra |
|---|---|---|
| Comprador | Registro público (correo + contraseña) | Inicio de compra |
| Administrador | Rol concedido por otro administrador | Panel de administración |
| Personal de caja (`personal`) | Un administrador lo asigna por correo | Interfaz de caja |

- El proveedor anónimo está **deshabilitado** y no se habilita.
- La confirmación de correo es obligatoria; el enlace vuelve por
  `mercamigo://auth/callback` (debe estar permitido en Supabase Auth → URL
  Configuration).
- El rol se comprueba **en el servidor**: `es_administrador()` y
  `es_personal()`. Ocultar una pantalla no autoriza nada.
- Mientras el servidor confirma el rol se muestra un splash neutro con el
  logo: al entrar como administrador o caja **no** aparece el inicio de
  comprador ni un parpadeo de otra pantalla.
- El permiso de cámara se pide cada vez que falte (también la primera vez);
  si el usuario lo bloqueó, se ofrece abrir Ajustes. La ubicación pide el
  permiso antes de comprobar el GPS.
- Cancelar el cambio de contraseña conserva la sesión abierta, incluso si se
  pulsa "Cancelar" y además se usa el botón Atrás.
- La autoasignación está bloqueada: `asignar_rol_personal`,
  `asignar_rol_personal_por_correo` y `asignar_rol_administrador` rechazan
  cambiar el rol de quien llama.
- El administrador gestiona la caja desde **Panel → Personal de caja**:
  escribe el correo de una cuenta existente y asigna o quita el rol. La
  función remota comprueba el rol de administrador y rechaza autocambios y
  degradar a otro administrador.

### Primer administrador

El registro público siempre crea compradores. El primer administrador se
asigna una sola vez desde el servidor:

```sql
select public.asignar_rol_administrador(
  (select id from auth.users where email = 'dayroncamilo4+mercamigo@gmail.com')
);
```

---

## 4. Pantallas y flujos

### Comprador

| Pantalla | Contenido |
|---|---|
| Inicio | Dos orígenes: **Estoy en la tienda** (`en_tienda`) o **Pedir para recoger** (`para_recoger`) |
| Escáner | Cámara real, linterna, ingreso manual, encontrado / no encontrado |
| Catálogo y búsqueda | Categorías del servidor, búsqueda global, detalle con stock |
| Carrito | Cantidades, eliminación con confirmación, vaciado con confirmación, totales inmediatos |
| Resumen | Origen, productos, total y aviso de pago en caja |
| Orden generada | Número + código de barras (el mismo identificador), caducidad del servidor y compartir |
| Mis pedidos / detalle | Estados reales, precios históricos, código vigente y cancelación |
| Mi cuenta | Nombre, correo, cambio de contraseña, cierre de sesión |

Reglas del flujo de compra:

- El carrito se conserva si falla la creación del pedido; solo se vacía si el
  servidor confirma la orden.
- El total y los precios los valida y recalcula el servidor
  (`crear_pedido`). La app nunca inventa precios ni descuenta stock por su
  cuenta.
- La orden nace `pendiente_pago` y caduca a los **15 minutos** según el reloj
  del servidor. La app muestra la cuenta regresiva con el instante recibido.
- El pago es **físico en caja**. No hay pagos electrónicos ni reembolsos
  simulados.
- Se puede cancelar solo un pedido `pendiente_pago` propio. Un pedido pagado
  se resuelve físicamente en caja y conserva su estado.
- El código de barras y el número visible son el mismo identificador. No
  incluye tokens ni secretos.

### Administrador

| Pantalla | Contenido |
|---|---|
| Panel | Accesos a productos, códigos, tienda, personal de caja y cuenta |
| Productos | Activos e inactivos, búsqueda, alta, edición, desactivar/reactivar con confirmación |
| Formulario | Nombre, descripción, precio, categoría y foto subida a Storage |
| Códigos | Código principal generado (solo lectura) y códigos adicionales |
| Tienda | Nombre, dirección y coordenadas; mapa y validación |
| Personal de caja | Asignar/quitar rol por correo |

Reglas de productos y códigos:

- Al crear, la app **no pide ni envía código**. `crear_producto` genera un
  código numérico único de 14 dígitos, tipo `barras`, y lo devuelve; la app lo
  muestra en un diálogo.
- Editar un producto **no regenera** el código principal.
- Los códigos adicionales no sustituyen al principal; se rechazan duplicados
  en el servidor.
- Desactivar conserva códigos y pedidos históricos. El comprador deja de ver
  el producto, pero los pedidos ya creados mantienen nombre y precio.
- Las fotos se suben al bucket público `producto-imagenes` y se guarda la URL
  remota, no una ruta local del teléfono.
- Salir del formulario con cambios pide confirmación.

### Personal de caja

| Pantalla | Contenido |
|---|---|
| Caja | Pestañas **Pendientes**, **En proceso** (pagados) y **Completados** |
| Búsqueda / escáner | Número de orden escrito o código de barras escaneado; estado no encontrado |
| Recibo | MERCAMIGO, número, cliente real, origen, fecha, estado, ítems, cantidades, precios históricos y total COP |
| Historial | Filtros por estado y búsqueda por número o cliente |
| Reportes | Hoy / Semana / Mes: ventas, pedidos, ticket promedio, serie diaria y top productos |

Transiciones (siempre atómicas y en el servidor):

1. **Confirmar pago recibido** → `pendiente_pago` pasa a `pagado` y se guarda
   `pagado_en`. No entrega el pedido.
2. **Confirmar entrega física** → `pagado` pasa a `entregado` y se guarda
   `entregado_en`. Nunca se entrega un pedido sin pagar.

Las dos acciones son idempotentes: repetir la llamada no cobra dos veces, no
duplica la entrega y devuelve el estado real. Un pedido caducado no se cobra;
uno cancelado no se cobra ni se entrega. La interfaz bloquea el botón mientras
la operación está en curso y muestra el resultado.

Reportes:

- Se calculan con `reporte_ventas` en `America/Bogota`.
- Cada pedido se cuenta **una sola vez** porque `pagado` y `entregado` son
  estados excluyentes de la misma fila; la fecha de venta es
  `coalesce(pagado_en, creado_en)`.
- No hay cifras fijas, porcentajes inventados ni datos de prototipo.

---

## 5. Arquitectura

```
lib/
  core/            configuración, tema, fechas de Bogotá, moneda
  data/models/     Product, CartItem, Order, StaffOrder, SalesReport, ...
  repositories/    catálogo, carrito, pedidos, perfil, tienda,
                   administración y caja (RPC)
  services/        Supabase, autenticación, escáner, cámara, compartir
  state/           controladores de provider
  ui/screens/      una pantalla por archivo
  ui/widgets/      componentes reutilizables (OrderBarcode, ProductBarcode, ...)
```

- Persistencia local detrás de repositorios (`KeyValueStore`).
- El catálogo, el perfil, la tienda, los pedidos y los reportes vienen de
  Supabase.
- El carrito y el origen de compra se guardan en el dispositivo.
- El código de barras se dibuja localmente con `barcode_widget` (Code 128).
- Las fechas se muestran siempre en `America/Bogota` y se guardan en UTC.

Dependencias principales: `provider`, `shared_preferences`, `supabase_flutter`,
`mobile_scanner`, `barcode_widget`, `geolocator`, `url_launcher`,
`flutter_svg`, `flutter_map`, `share_plus`, `image_picker`, `uuid`, `intl`.

---

## 6. Base de datos y seguridad

Tablas principales: `categorias`, `productos`, `codigos_producto`,
`detalle_pedido`, `pedidos`, `perfiles`, `roles_usuario`, `tiendas`.

RPC usadas por la app:

| RPC | Quién | Qué hace |
|---|---|---|
| `crear_pedido` | Comprador | Crea la orden, valida stock/precios, recalcula total, aplica idempotencia y caducidad |
| `cancelar_pedido` | Comprador (propio) / caja | Cancela solo `pendiente_pago`; un pago no se cancela desde la app |
| `crear_producto` | Administrador | Crea producto y genera el código principal |
| `editar_producto` | Administrador | Edita datos sin regenerar el código |
| `establecer_estado_producto` | Administrador | Activa/desactiva (borrado lógico) |
| `registrar_codigo_producto` | Administrador | Agrega código adicional, rechaza duplicados |
| `configurar_tienda` | Administrador | Guarda nombre, dirección y coordenadas |
| `listar_personal` | Administrador | Lista cuentas con rol |
| `asignar_rol_personal` | Administrador | Asigna/quita el rol por uuid; bloquea autoasignación |
| `asignar_rol_personal_por_correo` | Administrador | Igual, por correo |
| `listar_pedidos_personal` | Caja | Lista/filtra pedidos con nombre del cliente |
| `detalle_pedido_personal` | Caja | Recibo completo |
| `buscar_pedido_personal` | Caja | Busca por número o uuid |
| `confirmar_pago_pedido` | Caja | `pendiente_pago` → `pagado`, idempotente |
| `confirmar_entrega_pedido` | Caja | `pagado` → `entregado`, idempotente |
| `reporte_ventas` | Caja | Reporte real por periodo en Bogotá |

Notas de seguridad:

- RLS activo en todas las tablas públicas.
- El cliente **no** escribe directamente el catálogo ni los pedidos: todo pasa
  por RPC `SECURITY DEFINER` que comprueban el rol y los estados dentro de la
  transacción (`for update`, actualizaciones condicionadas).
- El comprador solo ve sus pedidos; la caja ve únicamente lo necesario, con el
  **nombre** del cliente, sin correo, teléfono ni datos de autenticación.
- El precio, el total, la disponibilidad y las transiciones se validan en el
  servidor. Los precios y nombres históricos se conservan en
  `detalle_pedido`.
- El código visible no autoriza: la autorización es el rol de caja.
- No se usa `service_role` ni secretos en Flutter.

---

## 7. Migraciones aplicadas

En `moviles-mercamigo` (`kbbbwdoommxsczjliqlu`), según
`supabase_migrations.schema_migrations`:

| Versión remota | Nombre | Fichero local relacionado |
|---|---|---|
| `20261021043230` | `mercamigo_esquema_y_catalogo_inicial` | (esquema inicial) |
| `20261021063714` | `20261021001000_crear_pedido` | `20261021001000_crear_pedido.sql` |
| `20261021063804` | `20261021002000_roles_y_administracion` | `20261021002000_roles_y_administracion.sql` |
| `20261021065012` | `20261021004000_endurecer_permisos` | `20261021004000_endurecer_permisos.sql` |
| `20261021201249` | `bucket_producto_imagenes` | `20261021120000_bucket_producto_imagenes.sql` |
| `20261021234427` | `zona_horaria_predeterminada_bogota` | (ajuste de zona horaria) |
| `20261122151831` | `generar_codigos_productos_automaticos_barras` | (código automático de 14 dígitos) |
| `20261125120000` | `personal_caja_reportes` | `20261125120000_personal_caja_reportes.sql` |
| `20261125130000` | `personal_por_correo` | `20261125130000_personal_por_correo.sql` |

Los ficheros locales `20261021100000_admin_productos_y_codigos.sql` y
`20261021110000_caducidad_pedidos.sql` **no figuran** en el historial remoto:
se conservan como referencia, pero no se aplicaron en esta entrega.

`20261021003000_validacion_token_recogida.sql` **no se aplicó**: el flujo de
caja actual no depende de ese token.

Verificación de funciones tras aplicar:

```sql
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'es_personal','listar_personal','asignar_rol_personal_por_correo',
    'listar_pedidos_personal','detalle_pedido_personal',
    'buscar_pedido_personal','confirmar_pago_pedido',
    'confirmar_entrega_pedido','cancelar_pedido','reporte_ventas'
  )
order by proname;
```

---

## 8. Pruebas

```powershell
flutter pub get
flutter analyze     # No issues found!
flutter test        # 164 pruebas
```

| Archivo | Qué cubre |
|---|---|
| `test/cart_test.dart` | Sumar/eliminar, totales, stock, persistencia |
| `test/catalog_search_test.dart` | Búsqueda, tildes, categorías, códigos |
| `test/order_test.dart` | Creación, números únicos, doble pulsación, carrito intacto, código = número visible |
| `test/order_history_test.dart` | Mapeo del servidor, precios históricos, paginación, vacío/error |
| `test/admin_role_test.dart` | Roles, rutas de comprador/administrador/caja, bloqueo de secciones |
| `test/admin_product_creation_test.dart` | Alta sin `p_codigo`, lectura del código devuelto, código adicional |
| `test/staff_order_test.dart` | Recibo de caja, nombre del cliente, totales y reportes |
| `test/barcode_service_test.dart` | Modelo de códigos y fotos |
| `test/widget_test.dart` | Sesión, acceso y navegación |
| `test/supabase_integration_test.dart` | Lectura real del catálogo (se omite sin `--dart-define`) |

### Verificado en esta entrega

- `flutter analyze`: sin incidencias.
- `flutter test`: **164 pruebas en verde** (2 omitidas por falta de
  `--dart-define`).
- Migraciones aplicadas y registradas en `supabase_migrations`.
- Funciones de caja y reportes creadas; autoasignación de rol bloqueada con
  una prueba SQL contra el servidor.
- `reporte_ventas` rechaza a quien no tiene rol de caja
  (`42501: Tu cuenta no tiene permisos de caja`), comprobado contra el
  proyecto remoto.
- Compilación del APK release.
- APK instalado y abierto en un teléfono físico (Xiaomi 2201117SG, Android
  13): la pantalla de inicio de sesión se muestra correctamente.

### No verificado (requiere hardware o cuentas reales)

- Cámara real y permisos en un teléfono físico (el teléfono se desconectó
  antes de completar el recorrido autenticado).
- Compartir con la hoja nativa de Android.
- GPS y permisos de ubicación en hardware.
- Confirmación de correo y recuperación de contraseña abriendo el deep link.
- Un ciclo completo de caja con una cuenta `personal` real: no existe una
  segunda cuenta de prueba y no se creó una en producción.
- Reportes con pedidos pagados/entregados reales: hoy el proyecto remoto solo
  tiene pedidos `expirado`, así que el reporte se validó con datos simulados y
  la consulta SQL, no con ventas reales.

---

## 9. Alcance y limitaciones

- **No hay pagos electrónicos.** El pago se recibe físicamente en caja.
- **No hay reembolsos electrónicos.** Un pedido pagado se resuelve en caja.
- `stock_demo` sigue siendo un inventario de demostración del esquema; hoy no
  se descuenta automáticamente.
- Las promociones no existen en el esquema actual; la app no inventa ninguna.
- El antiguo QR se retiró: productos y órdenes usan códigos de barras Code 128.
- No se añadió Shorebird ni actualizaciones remotas.
