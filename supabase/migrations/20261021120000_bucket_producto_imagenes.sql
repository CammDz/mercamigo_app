-- ---------------------------------------------------------------------------
-- Bucket de fotos de los productos
--
-- Las fotos que el administrador sube desde el celular se guardan en
-- Supabase Storage, en el bucket `producto-imagenes`, con la ruta
--
--     productos/{producto_id}/{timestamp}.jpg
--
-- REGLAS
--
--   1. El bucket es publico: la app (y el comprador) muestran la foto con
--      su direccion publica, sin firmar peticiones ni guardar tokens.
--
--   2. Solo un **administrador** puede subir o borrar fotos. La autorizacion
--      usa `public.es_administrador()`, la misma funcion que protege las
--      demas operaciones del panel (no es "esconder botones").
--
--   3. Limite de 5 MB y solo imagenes (jpeg, png, webp): la app ya
--      redimensiona y comprime la foto antes de subirla.
--
--   4. No se toca `productos`, `categorias` ni `codigos_producto`: este
--      archivo solo crea el bucket y sus politicas de Storage.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'producto-imagenes',
    'producto-imagenes',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
    set public              = excluded.public,
        file_size_limit     = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

-- La foto se puede leer (la app la muestra con su direccion publica).
drop policy if exists "producto_imagenes_lectura" on storage.objects;
create policy "producto_imagenes_lectura"
    on storage.objects
    for select
    using (bucket_id = 'producto-imagenes');

-- Solo el administrador sube fotos.
drop policy if exists "producto_imagenes_subida_admin" on storage.objects;
create policy "producto_imagenes_subida_admin"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'producto-imagenes'
        and public.es_administrador()
    );

-- Solo el administrador borra fotos (al reemplazar una, se borra la
-- anterior para no acumular copias).
drop policy if exists "producto_imagenes_borrado_admin" on storage.objects;
create policy "producto_imagenes_borrado_admin"
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'producto-imagenes'
        and public.es_administrador()
    );
