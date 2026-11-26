# Códigos de barras y PDF imprimible

## 1. Códigos de la app

| Elemento | Formato | Dónde se genera |
|---|---|---|
| Producto | Numérico de 14 dígitos, tipo `barras` | `crear_producto` (servidor) |
| Código adicional | Libre, sin duplicados | `registrar_codigo_producto` |
| Orden | Número visible `MCA-000123` | `crear_pedido` (servidor) |

- Se dibujan con **Code 128** mediante `barcode_widget`, en el dispositivo.
- El código de una orden **no autoriza** nada: la caja valida el rol en el
  servidor.
- Editar un producto no regenera su código principal.
- Desactivar un producto conserva sus códigos y el historial de pedidos.

## 2. PDF del catálogo

Archivo: `mercamigo_codigos_de_barras.pdf` (raíz del proyecto).

Contenido:

- Una etiqueta por producto **activo con código**.
- Nombre, código Code 128 en negro sobre blanco y el mismo código en texto
  legible.
- Hoja A4 vertical, 3 columnas × 7 filas = **21 etiquetas por página**.
- Márgenes de impresión, marco punteado por etiqueta y ninguna etiqueta
  partida entre páginas.
- Encabezado con título, fecha de generación y total de productos.
- Pie con numeración `Página X de Y`.
- Sin credenciales, datos de clientes ni códigos QR de pedidos.

En la entrega actual: **40 productos activos → 2 páginas**.

Los productos de prueba `Pantalla`, `Pantalla2` y `Test` se excluyen y además
están desactivados en el catálogo.

## 3. Regenerar el PDF

Requisitos:

```powershell
python -m pip install reportlab pillow python-barcode
```

Obligatoriamente define el proyecto Supabase antes de generar:

```powershell
$env:SUPABASE_URL             = "https://TU-PROYECTO.supabase.co"
$env:SUPABASE_PUBLISHABLE_KEY = "TU_CLAVE_PUBLICABLE"
```

Generar:

```powershell
python tool/generar_codigos_pdf.py
# o indicando otra ruta:
python tool/generar_codigos_pdf.py salida.pdf
```

El script lee los productos activos por la API REST pública con la clave
publicable. No necesita `service_role`.

## 4. Impresión

- Imprimir al **100 %** (sin "ajustar a la página") para conservar el tamaño
  del código.
- Papel A4 blanco; el contraste negro/blanco es suficiente para lectores
  láser y de cámara.
- Verificar con el escáner de la app antes de pegar las etiquetas.
