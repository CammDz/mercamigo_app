# Mercamigo

Aplicación Android desarrollada en Flutter para comprar en una tienda de
autoservicio: catálogo digital, escáner de códigos de barras, carrito, pedidos
para recoger, caja y administración. El pago se realiza **físicamente en caja**;
la app no procesa pagos electrónicos.

Proyecto académico de la materia **Aplicaciones Móviles**, programa Tecnología
en Desarrollo de Sistemas Informáticos, **Universitaria Tecnológica de
Santander**, grupo **B191**.

| Integrante |
|---|
| Dayron Camilo Diaz Gallo |
| Yiseth Tatiana Morales Alarcón |
| Santiago Alejandro Figueroa Hernández |
| Will Smith Quiroga Trillos |

- Versión de la app: `1.0.0+1`
- `applicationId`: `com.mercamigo.mercamigo_app`
- Flutter 3.47.7 · Dart 3.13.5
- Backend: Supabase (PostgreSQL + Auth + Storage)

---

## 1. Funcionalidades

### Comprador

- Inicio con dos modalidades: **Estoy en la tienda** o **Pedir para recoger**.
- Escáner real de códigos de barras (Code 128), linterna, ingreso manual e
  historial de escaneos.
- Catálogo por categorías, búsqueda con tolerancia a mayúsculas y tildes,
  detalle de producto con precio y disponibilidad.
- Carrito persistente, cantidades, totales inmediatos y confirmaciones al
  eliminar o vaciar.
- Orden con número visible (`MCA-000123`) y el mismo identificador en código de
  barras; caducidad de 15 minutos controlada por el servidor.
- Mis pedidos, detalle con precios históricos y cancelación de pedidos
  pendientes de pago.

### Administrador

- Panel con acceso a **Productos**, **Promociones**, **Tienda** y **Mi cuenta**.
- Alta y edición de productos con foto subida a Supabase Storage.
- Código principal de 14 dígitos generado automáticamente en el servidor y
  códigos adicionales sin duplicados.
- Activación/desactivación lógica de productos (conserva códigos e historial).
- Promociones `dos_por_uno`, `tres_por_dos` y `precio_paquete`, con productos
  asociados y banner opcional; el descuento se aplica en el servidor.
- Configuración de la tienda: nombre, dirección y coordenadas en mapa.
- Las pantallas de códigos y de personal de caja conservan su ruta y sus RPC,
  aunque el panel actual prioriza los cuatro accesos anteriores.

### Personal de caja

- Órdenes pendientes, en proceso (pagadas) y completadas.
- Búsqueda por número de orden o escaneo del código de barras.
- Recibo con cliente, origen, ítems, precios históricos y total en COP.
- Confirmación de pago y de entrega física, idempotentes y validadas en el
  servidor.
- Reportes de ventas por día, semana o mes, en zona horaria `America/Bogota`.

---

## 2. Tecnologías

| Capa | Herramientas |
|---|---|
| App | Flutter, Dart, Provider |
| UI | Tema propio (azul/lila), Jaro + League Spartan, `flutter_svg`, `flutter_map` |
| Cámara y códigos | `mobile_scanner`, `barcode_widget` (Code 128) |
| Servicios del dispositivo | `geolocator`, `image_picker`, `share_plus`, `url_launcher` |
| Persistencia local | `shared_preferences` detrás de repositorios |
| Backend | Supabase: PostgreSQL, Auth, Storage, RPC `SECURITY DEFINER` |

---

## 3. Estructura

```text
lib/
  core/            configuracion, tema, fechas de Bogota, moneda, validadores
  data/            modelos, catalogo local y almacenamiento clave-valor
  repositories/    catalogo, carrito, pedidos, perfil, tienda, admin y caja
  services/        Supabase, autenticacion, camara, escaner, imagenes, compartir
  state/           controladores de Provider
  ui/screens/      una pantalla por archivo
  ui/widgets/      componentes reutilizables
supabase/
  migrations/      SQL versionado del esquema, RPC y politicas RLS
  CONFIGURACION_CORREO.md
docs/              arquitectura, base de datos, codigos y creditos
tool/              compilacion del APK y generacion del PDF de codigos
```

Documentación ampliada:

- [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md)
- [`docs/BASE_DE_DATOS.md`](docs/BASE_DE_DATOS.md)
- [`docs/CODIGOS_DE_BARRAS.md`](docs/CODIGOS_DE_BARRAS.md)
- [`docs/MANUAL_USUARIO.md`](docs/MANUAL_USUARIO.md)
- [`docs/CREDITOS_IMAGENES.md`](docs/CREDITOS_IMAGENES.md)

---

## 4. Requisitos

| Herramienta | Versión recomendada |
|---|---|
| Flutter | 3.47.x (stable) |
| Dart | 3.13.x |
| JDK | 17 o 21 (no usar 25) |
| Android SDK | platform 34/35/36, build-tools 35/36 |
| Python (solo para el PDF) | 3.10 o superior |

```powershell
$env:ANDROID_HOME     = "C:\dev\android-sdk"
$env:ANDROID_SDK_ROOT = "C:\dev\android-sdk"
$env:JAVA_HOME        = "C:\Program Files\Java\jdk-21.0.10"
$env:PATH             = "C:\dev\flutter\bin;C:\dev\android-sdk\platform-tools;$env:PATH"
```

---

## 5. Configuración

La configuración se inyecta en tiempo de compilación con `--dart-define`; no hay
credenciales escritas en el código Dart.

1. Copia [`.env.example`](.env.example) como `.env` y completa los valores de tu
   proyecto Supabase.
2. Exporta las variables en la terminal (o usa el script de compilación, que las
   lee del entorno):

```powershell
$env:SUPABASE_URL             = "https://TU-PROYECTO.supabase.co"
$env:SUPABASE_PUBLISHABLE_KEY = "TU_CLAVE_PUBLICABLE"
```

> Usa únicamente la clave **publicable** (`sb_publishable_...` o `anon`). La
> clave `service_role` y la contraseña de PostgreSQL nunca deben incluirse en la
> app ni en el repositorio.

Sin las variables, la app arranca en **modo local**: el catálogo y los pedidos
quedan solo en el dispositivo y las funciones de servidor (caja, reportes,
roles) no están disponibles.

### Ejecutar en desarrollo

```powershell
flutter pub get
flutter run `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY
```

---

## 6. Compilación del APK

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1
# APK: build\app\outputs\flutter-apk\app-release.apk
```

El script:

- exige `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en el entorno (ver
  sección 5);
- localiza Flutter, el SDK de Android y un JDK 17/21;
- detiene los daemons de Gradle/Kotlin y limpia intermedios (bloqueos típicos en
  Windows/OneDrive);
- compila en release con las variables de Supabase;
- reintenta una vez si Gradle deja archivos bloqueados.

El APK de release se firma con la clave de **debug** de `flutter create`. Para
publicar en Google Play hay que crear un keystore propio; cambiar la firma no
altera el `applicationId`, pero obliga a desinstalar/reinstalar.

---

## 7. Base de datos y seguridad

Tablas principales: `categorias`, `productos`, `codigos_producto`, `pedidos`,
`detalle_pedido`, `perfiles`, `roles_usuario`, `tiendas`, `promociones` y
`promocion_productos`.

- RLS activo en todas las tablas públicas.
- El cliente no escribe el catálogo ni los pedidos directamente: usa RPC
  `SECURITY DEFINER` que verifican rol, precios, disponibilidad y estados
  dentro de la transacción.
- El comprador solo ve sus pedidos; caja y administración reciben únicamente lo
  necesario.
- Los precios y nombres históricos se conservan en `detalle_pedido`.
- Las fotos viven en el bucket público `producto-imagenes`; subir o borrar
  exige `public.es_administrador()`.

El detalle de tablas, RPC, políticas y migraciones está en
[`docs/BASE_DE_DATOS.md`](docs/BASE_DE_DATOS.md).

### Roles

| Rol | Obtención | Interfaz |
|---|---|---|
| Comprador | Registro público | Inicio de compra |
| Administrador | Otorgado por otro administrador | Panel de administración |
| Personal de caja | Otorgado por un administrador | Órdenes, historial y reportes |

El rol se comprueba siempre en el servidor con `es_administrador()` y
`es_personal()`; ocultar una pantalla no autoriza nada. La confirmación de
correo es obligatoria y el enlace de recuperación vuelve por
`mercamigo://auth/callback`.

---

## 8. Catálogo e imágenes

El catálogo tiene **40 productos activos** y los 40 tienen fotografía:

- 3 conservan los recursos locales del prototipo (`assets/figma/...`).
- 37 usan fotos reales almacenadas en el bucket público
  `producto-imagenes/catalogo/<uuid>.jpg`, recortadas a 600 × 600 px y
  optimizadas en JPEG.
- Los productos de prueba `Pantalla`, `Pantalla2` y `Test` se desactivaron para
  que no aparezcan en el catálogo; no se borraron.

Las fuentes, autores y licencias de las fotos están en
[`docs/CREDITOS_IMAGENES.md`](docs/CREDITOS_IMAGENES.md).

---

## 9. Códigos de barras

- Cada producto tiene un código principal numérico de 14 dígitos, generado por
  `crear_producto`.
- Cada orden usa su número visible (`MCA-000123`) como contenido del código.
- Ambos se dibujan en el dispositivo con Code 128 (`barcode_widget`); no son
  tokens de autorización.
- El PDF [`mercamigo_codigos_de_barras.pdf`](mercamigo_codigos_de_barras.pdf)
  contiene los 40 productos activos en etiquetas A4 (2 páginas), con nombre,
  código legible y código Code 128 en blanco y negro.

Para regenerarlo:

```powershell
python -m pip install reportlab pillow python-barcode
python tool/generar_codigos_pdf.py
```

Más detalles en [`docs/CODIGOS_DE_BARRAS.md`](docs/CODIGOS_DE_BARRAS.md).

---

## 10. Calidad y verificación

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

Resultados de la entrega:

| Comprobación | Resultado |
|---|---|
| `dart format --set-exit-if-changed` | Sin cambios pendientes (133 archivos) |
| `flutter analyze` | `No issues found!` |
| `flutter test` | **166 pruebas superadas**, 2 omitidas |
| `flutter build apk --release` | APK generado correctamente |

Las 2 pruebas omitidas son las de integración real con Supabase: se activan
solo al compilar con `--dart-define`.

### Verificado

- Lectura real del catálogo con la clave publicable.
- 37 fotos subidas a Storage y verificadas por HTTP 200 con `image/jpeg`.
- Generación del PDF con los 40 códigos activos.
- Compilación del APK release.

### Limitaciones conocidas

- No hay pagos electrónicos ni reembolsos: el pago se recibe en caja.
- La disponibilidad es lógica: un producto activo se puede comprar y uno
  desactivado no. No se lleva conteo de existencias ni se descuenta inventario;
  cuando un producto se agota, se desactiva desde administración.
- Cámara, GPS, deep links de correo y compartir nativo dependen de hardware y
  cuentas reales; no se validaron por completo en esta entrega.
- No se añadieron actualizaciones remotas (Shorebird) ni notificaciones push.

---

## 11. Uso académico

Proyecto desarrollado con fines académicos. Las fotografías del catálogo
proceden de Wikimedia Commons y se usan únicamente en el prototipo; las
atribuciones y licencias se documentan en `docs/CREDITOS_IMAGENES.md`.

Las marcas y productos mostrados pertenecen a sus respectivos titulares. Este
repositorio no representa una tienda real ni procesa dinero real.
