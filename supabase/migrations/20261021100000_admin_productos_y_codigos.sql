-- =====================================================================
-- Mercamigo · 20261021100000_admin_productos_y_codigos.sql
--
-- Funciones administrativas para el panel de administración:
--
--   public.editar_producto              -> Editar un producto.
--   public.establecer_estado_producto   -> Desactivar / reactivar (borrado lógico).
--   public.registrar_codigo_producto    -> Registrar un código de barras o QR.
--   public.corregir_codigo_producto     -> Corregir un código ya registrado.
--
-- ---------------------------------------------------------------------
-- REGLAS QUE SIGUEN ESTAS FUNCIONES
--
--   1. Todas son SECURITY DEFINER con `SET search_path TO ''`: los objetos
--      que usan van cualificados con su esquema y no se puede injectar
--      código por el `search_path`.
--
--   2. La autorización NO es "ocultar botones": cada función llama a
--      public.es_administrador() y lanza 42501 si el usuario no es
--      administrador. Un comprador que invoque la RPC directamente recibe
--      un rechazo del servidor.
--
--   3. No hay INSERT/UPDATE/DELETE directos del cliente sobre el
--      catálogo: `productos` y `codigos_producto` siguen sin políticas de
--      escritura y sus privilegios de escritura para `authenticated` siguen
--      revocados (migración 20261021004000). Todas las escrituras
--      administrativas pasan por estas funciones.
--
--   4. El borrado es LÓGICO: desactivar un producto pone `activo = false`.
--      No se borra nunca una fila de `productos` ni de `codigos_producto`, de
--      modo que los pedidos históricos (`pedidos`, `detalle_pedido`) siguen
--      apuntando a datos válidos y sus códigos no se rompen.
--
--   5. Los códigos se guardan como TEXTO para conservar los ceros
--      iniciales de un código de barras ("0123456789012" no se convierte en
--      123456789012).
--
--   6. Atomicidad: cada operación de escritura va en una sola sentencia
--      (o en un bloque con la validación antes de la escritura), de forma
--      que no queden códigos huérfanos ni productos a medio actualizar.
--
-- ---------------------------------------------------------------------
-- LO QUE NO SE TOCA
--
--   · `tokens_recogida` ni el token QR del pedido: es otro sistema (el
--     token de recogida del pedido) y no se mezcla con los códigos de
--     producto. Ninguna función de este archivo lo lee ni lo escribe.
--   · `categorias`: en esta etapa no se administran categorías.
--   · `stock_demo`: no se presenta como inventario real. Editar un producto
--     no modifica el stock de demostración.
--   · Los permisos internos de Supabase (`auth`, `extensions`, `vault`...).
--   · `service_role` y `postgres`.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Editar producto
-- ---------------------------------------------------------------------
create or replace function public.editar_producto(
    p_producto_id  uuid,
    p_nombre       text,
    p_descripcion  text default null,
    p_categoria_id uuid default null,
    p_precio_cop   bigint default null,
    p_imagen_url   text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_producto public.productos%rowtype;
    v_categoria uuid;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede editar productos.'
            using errcode = '42501';
    end if;

    if p_producto_id is null then
        raise exception 'El producto es obligatorio.'
            using errcode = '22023';
    end if;

    select * into v_producto
      from public.productos
     where id = p_producto_id
     for update;

    if not found then
        raise exception 'El producto indicado no existe.'
            using errcode = '22023';
    end if;

    if p_nombre is not null then
        if pg_catalog.btrim(p_nombre) = '' then
            raise exception 'El nombre no puede quedar vacío.'
                using errcode = '22023';
        end if;
    end if;

    if p_precio_cop is not null and p_precio_cop <= 0 then
        raise exception 'El precio debe ser mayor que cero.'
            using errcode = '22023';
    end if;

    if p_categoria_id is not null then
        if not exists (
            select 1 from public.categorias
             where id = p_categoria_id and activa
        ) then
            raise exception 'La categoría no existe o no está activa.'
                using errcode = '22023';
        end if;
        v_categoria := p_categoria_id;
    else
        v_categoria := v_producto.categoria_id;
    end if;

    update public.productos
       set nombre       = case when p_nombre is null then nombre
                              else pg_catalog.btrim(p_nombre) end,
           descripcion  = case when p_descripcion is null then descripcion
                              else pg_catalog.btrim(p_descripcion) end,
           categoria_id = v_categoria,
           precio_cop   = coalesce(p_precio_cop, precio_cop),
           imagen_url   = coalesce(p_imagen_url, imagen_url)
     where id = p_producto_id
     returning * into v_producto;

    return pg_catalog.jsonb_build_object(
        'id',            v_producto.id,
        'nombre',        v_producto.nombre,
        'descripcion',   v_producto.descripcion,
        'categoria_id',  v_producto.categoria_id,
        'precio_cop',    v_producto.precio_cop,
        'imagen_url',    v_producto.imagen_url,
        'activo',        v_producto.activo,
        'es_demostracion', v_producto.es_demostracion
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- 2) Desactivar / reactivar producto (borrado lógico)
--
--    No borra filas: solo cambia `productos.activo`.
--    Los pedidos históricos no se ven afectados y los códigos se conservan.
-- ---------------------------------------------------------------------
create or replace function public.establecer_estado_producto(
    p_producto_id uuid,
    p_activo      boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_producto public.productos%rowtype;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede cambiar el estado de un producto.'
            using errcode = '42501';
    end if;

    if p_producto_id is null then
        raise exception 'El producto es obligatorio.'
            using errcode = '22023';
    end if;

    if p_activo is null then
        raise exception 'Indica si el producto queda activo o inactivo.'
            using errcode = '22023';
    end if;

    select * into v_producto
      from public.productos
     where id = p_producto_id
     for update;

    if not found then
        raise exception 'El producto indicado no existe.'
            using errcode = '22023';
    end if;

    update public.productos
       set activo = p_activo
     where id = p_producto_id
     returning * into v_producto;

    return pg_catalog.jsonb_build_object(
        'id',         v_producto.id,
        'nombre',     v_producto.nombre,
        'activo',     v_producto.activo,
        'mensaje',    case when v_producto.activo
                           then 'Producto reactivado.'
                           else 'Producto desactivado: ya no se puede anadir a nuevas compras.'
                      end
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- 3) Registrar un código de barras o QR de producto
--
--    `codigos_producto.codigo` es UNIQUE: un código no puede pertenecer a
--    dos productos. Si el código ya existe se informa a qué producto
--    pertenece (esta información solo se ve en la vista de administración).
-- ---------------------------------------------------------------------
create or replace function public.registrar_codigo_producto(
    p_producto_id uuid,
    p_codigo      text,
    p_tipo        text default 'barras'
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_producto public.productos%rowtype;
    v_existente record;
    v_dueno     text;
    v_codigo_id uuid;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede registrar codigos.'
            using errcode = '42501';
    end if;

    if p_producto_id is null then
        raise exception 'El producto es obligatorio.'
            using errcode = '22023';
    end if;

    if p_codigo is null or pg_catalog.btrim(p_codigo) = '' then
        raise exception 'El codigo no puede estar vacio.'
            using errcode = '22023';
    end if;

    if p_tipo is null
       or p_tipo not in ('qr_demo', 'qr', 'barras') then
        raise exception 'Tipo de codigo invalido: %', coalesce(p_tipo, 'null')
            using errcode = '22023';
    end if;

    select * into v_producto
      from public.productos
     where id = p_producto_id;

    if not found then
        raise exception 'El producto indicado no existe.'
            using errcode = '22023';
    end if;

    select c.id as id, c.producto_id as producto_id, p.nombre as nombre
      into v_existente
      from public.codigos_producto c
      join public.productos p on p.id = c.producto_id
     where c.codigo = pg_catalog.btrim(p_codigo);

    if v_existente.id is not null then
        if v_existente.producto_id = p_producto_id then
            raise exception 'Ese codigo ya esta registrado en este producto.'
                using errcode = '22005';
        end if;
        raise exception
            'Ese codigo ya pertenece al producto "%".', v_existente.nombre
            using errcode = '22005';
    end if;

    insert into public.codigos_producto (producto_id, codigo, tipo)
    values (p_producto_id, pg_catalog.btrim(p_codigo), p_tipo)
    returning id into v_codigo_id;

    return pg_catalog.jsonb_build_object(
        'id',          v_codigo_id,
        'producto_id', p_producto_id,
        'codigo',      pg_catalog.btrim(p_codigo),
        'tipo',        p_tipo
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- 4) Corregir un código ya registrado
--
--    Permite arreglar un dígito mal leído. No cambia de producto: el código
--    sigue asociado al mismo artículo.
-- ---------------------------------------------------------------------
create or replace function public.corregir_codigo_producto(
    p_codigo_id uuid,
    p_codigo    text,
    p_tipo      text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_codigo    public.codigos_producto%rowtype;
    v_existente record;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede corregir codigos.'
            using errcode = '42501';
    end if;

    if p_codigo_id is null then
        raise exception 'El codigo a corregir es obligatorio.'
            using errcode = '22023';
    end if;

    if p_codigo is null or pg_catalog.btrim(p_codigo) = '' then
        raise exception 'El codigo no puede estar vacio.'
            using errcode = '22023';
    end if;

    if p_tipo is not null
       and p_tipo not in ('qr_demo', 'qr', 'barras') then
        raise exception 'Tipo de codigo invalido: %', p_tipo
            using errcode = '22023';
    end if;

    select * into v_codigo
      from public.codigos_producto
     where id = p_codigo_id
     for update;

    if not found then
        raise exception 'El codigo indicado no existe.'
            using errcode = '22023';
    end if;

    select c.id as id, c.producto_id as producto_id, p.nombre as nombre
      into v_existente
      from public.codigos_producto c
      join public.productos p on p.id = c.producto_id
     where c.codigo = pg_catalog.btrim(p_codigo)
       and c.id <> p_codigo_id;

    if v_existente.id is not null then
        if v_existente.producto_id = v_codigo.producto_id then
            raise exception 'Ese codigo ya esta registrado en este producto.'
                using errcode = '22005';
        end if;
        raise exception
            'Ese codigo ya pertenece al producto "%".', v_existente.nombre
            using errcode = '22005';
    end if;

    update public.codigos_producto
       set codigo = pg_catalog.btrim(p_codigo),
           tipo   = coalesce(p_tipo, tipo)
     where id = p_codigo_id
     returning * into v_codigo;

    return pg_catalog.jsonb_build_object(
        'id',          v_codigo.id,
        'producto_id', v_codigo.producto_id,
        'codigo',      v_codigo.codigo,
        'tipo',        v_codigo.tipo
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- PERMISOS
--
--   · Se revoca EXECUTE a PUBLIC (y por tanto a `anon`) para que un
--     comprador anónimo no pueda invocarlas.
--   · Se concede EXECUTE a `authenticated`: la autorización real la hace
--     es_administrador() DENTRO de cada función.
--   · `service_role` y `postgres` conservan los permisos del propietario.
-- ---------------------------------------------------------------------
revoke all on function public.editar_producto(uuid, text, text, uuid, bigint, text)
    from public, anon;
revoke all on function public.establecer_estado_producto(uuid, boolean)
    from public, anon;
revoke all on function public.registrar_codigo_producto(uuid, text, text)
    from public, anon;
revoke all on function public.corregir_codigo_producto(uuid, text, text)
    from public, anon;

grant execute on function public.editar_producto(uuid, text, text, uuid, bigint, text)
    to authenticated;
grant execute on function public.establecer_estado_producto(uuid, boolean)
    to authenticated;
grant execute on function public.registrar_codigo_producto(uuid, text, text)
    to authenticated;
grant execute on function public.corregir_codigo_producto(uuid, text, text)
    to authenticated;
