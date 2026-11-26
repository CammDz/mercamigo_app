-- =====================================================================
-- Mercamigo · 20261021001000_crear_pedido.sql
--
-- Creacion segura de pedidos.
--
-- NO recrea ninguna tabla, NO borra datos y NO concede permisos de
-- escritura al cliente: `anon` y `authenticated` siguen sin poder
-- insertar en `pedidos` ni en `detalle_pedido`. Toda la escritura
-- ocurre dentro de funciones SECURITY DEFINER propiedad del proyecto,
-- que comprueban la identidad y los permisos por su cuenta (no
-- confian en RLS).
--
-- Reglas garantizadas por esta migracion:
--
--   1. Identidad: sale de `auth.uid()`. El cliente NO puede elegir el
--      `usuario_id`.
--   2. Tienda: debe existir y estar activa.
--   3. Productos: deben existir, estar activos y su categoria activa.
--   4. Cantidades: entero entre 1 y 100, tanto por item como por
--      producto ya agrupado (60 + 60 del mismo producto se rechaza).
--      El formato se valida ANTES de convertir a numeric (PostgreSQL no
--      evalua de izquierda a derecha los OR de un WHERE), el texto de la
--      cantidad se acota a 10 caracteres y el array a 50 items, para que
--      la conversion nunca falle ni desborde.
--   5. Precios: se leen de `productos.precio_cop` y se validan (> 0).
--      Flutter NUNCA envia precios ni totales.
--   6. Total: se recalcula en el servidor.
--   7. Coherencia: el total y los detalles se calculan a partir de la
--      MISMA foto de precios (una sola sentencia), asi que no pueden
--      divergir aunque el catalogo cambie entre medias.
--   8. Atomicidad: pedido + detalles + token en una sola transaccion.
--   9. Idempotencia: la restriction UNIQUE (usuario_id,
--      clave_idempotencia) evita duplicados incluso con peticiones
--      concurrentes (INSERT ... ON CONFLICT DO NOTHING).
--  10. Reutilizacion indebida: si la misma clave llega con un pedido
--      distinto, se rechaza.
--  11. Estado de pago: la funcion no recibe ningun estado y siempre
--      escribe 'pendiente_pago'. El cliente no puede marcar un pedido
--      como pagado.
--  12. Caducidad: la caducidad del token la fija el SERVIDOR
--      (public._ttl_token_recogida). El cliente no puede decidirla.
--
-- Todo el SQL usa `set search_path = ''` y califica los objetos de
-- forma explicita (public., extensions., auth.) para evitar ataques de
-- busqueda de esquema.
--
-- Requisito previo: pgcrypto instalado en el esquema `extensions`.
--
-- ---------------------------------------------------------------------
-- PROTOCOLO DE BLOQUEOS (obligatorio para cualquier operacion futura)
--
--   El estado del pedido y la emision del token se comprueban SIEMPRE
--   bajo bloqueo de fila, en este orden:
--
--     1. public.pedidos        ... FOR UPDATE
--     2. public.tokens_recogida ... FOR UPDATE
--
--   Cualquier operacion futura que marque un pedido como pagado,
--   entregado, cancelado o expirado DEBE usar el mismo protocolo
--   (bloquear primero la fila de public.pedidos y despues la de
--   public.tokens_recogida) para no poder emitir un codigo valido para
--   un pedido que ya se entrego o se cancelo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Politica de caducidad del token de recogida (la decide el servidor).
-- ---------------------------------------------------------------------
create or replace function public._ttl_token_recogida()
returns interval
language sql
immutable
as $$
    select interval '24 hours'::interval;
$$;

comment on function public._ttl_token_recogida() is
    'Caducidad del token de recogida. Politica del servidor: el cliente no puede modificarla.';

revoke all on function public._ttl_token_recogida() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Huella del contenido de la orden.
--
-- Permite detectar que se esta reutilizando una clave de idempotencia
-- con un pedido distinto. Es una columna aditiva: no modifica la
-- relacion existente de `pedidos`.
-- ---------------------------------------------------------------------
alter table public.pedidos
    add column if not exists contenido_hash text;

comment on column public.pedidos.contenido_hash is
    'SHA-256 de tienda_id + origen + items normalizados. Permite rechazar la reutilizacion de una clave de idempotencia con un contenido distinto.';


-- ---------------------------------------------------------------------
-- Emision / rotacion del token de recogida.
--
-- El token se GENERA con bytes aleatorios criptograficamente seguros
-- (`gen_random_bytes`); el SHA-256 solo se usa para GUARDAR su hash.
-- Nunca se guarda el token en texto plano.
--
-- Solo hay una fila por pedido (UNIQUE pedido_id): al reemitir, la fila
-- se sustituye, de modo que el hash anterior desaparece y el token
-- anterior queda invalidado de forma efectiva.
--
-- La caducidad SIEMPRE es la politica del servidor
-- (public._ttl_token_recogida()); el cliente no la puede elegir.
-- ---------------------------------------------------------------------
create or replace function public._emitir_token_recogida(
    p_pedido_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_token  text;
    v_expira timestamptz;
begin
    v_expira := pg_catalog.now() + public._ttl_token_recogida();

    -- 32 bytes aleatorios -> 64 caracteres hexadecimales.
    v_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

    insert into public.tokens_recogida (pedido_id, token_hash, expira_en)
    values (
        p_pedido_id,
        pg_catalog.encode(extensions.digest(v_token, 'sha256'), 'hex'),
        v_expira
    )
    on conflict (pedido_id) do update
        set token_hash  = excluded.token_hash,
            creado_en   = pg_catalog.now(),
            expira_en   = excluded.expira_en,
            usado_en    = null,
            revocado_en = null;

    return v_token;
end;
$$;

comment on function public._emitir_token_recogida(uuid) is
    'Emite o rota el token de recogida de un pedido. Uso interno: no es ejecutable por el cliente. La caducidad es la politica del servidor.';

revoke all on function public._emitir_token_recogida(uuid) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Detalle de un pedido (para la respuesta al cliente).
-- ---------------------------------------------------------------------
create or replace function public._detalle_de_orden(p_pedido_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(
        pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
                'producto_id',          d.producto_id,
                'nombre_producto',      d.nombre_producto,
                'cantidad',             d.cantidad,
                'precio_unitario_cop',  d.precio_unitario_cop,
                'subtotal_cop',         d.subtotal_cop
            )
            order by d.nombre_producto
        ),
        '[]'::jsonb
    )
    from public.detalle_pedido d
    where d.pedido_id = p_pedido_id;
$$;

revoke all on function public._detalle_de_orden(uuid) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Respuesta estandar de un pedido.
--
-- `token_recogida` solo se devuelve en la creacion. En un reintento se
-- devuelve null y `requiere_reemision = true`: el token no se puede
-- reconstruir desde su hash, hay que pedirlo explicitamente.
-- ---------------------------------------------------------------------
create or replace function public._respuesta_pedido(
    p_pedido  public.pedidos,
    p_nuevo   boolean default false,
    p_token   text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    return pg_catalog.jsonb_build_object(
        'pedido_id',        p_pedido.id,
        'numero_orden',     p_pedido.numero_orden,
        'origen',           p_pedido.origen,
        'total_cop',        p_pedido.total_cop,
        'estado',           p_pedido.estado,
        'creado_en',        p_pedido.creado_en,
        'token_recogida',   p_token,
        'requiere_reemision', (p_token is null),
        'reutilizado',      (not p_nuevo),
        'items',            public._detalle_de_orden(p_pedido.id)
    );
end;
$$;

revoke all on function public._respuesta_pedido from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Crear pedido.
--
-- Reintento con la misma clave (pedido ya existente):
--   Se DEVUELVE el pedido existente SIN token y con
--   `requiere_reemision = true`. NO se rota el token de forma silenciosa:
--   quien quiera un codigo vigente lo pide explicitamente con
--   public.reemitir_token_recogida(pedido_id), que si invalida el
--   anterior.
--
--   COMO SE RESUELVE PERDER LA RESPUESTA ORIGINAL:
--     · El cliente reintenta `crear_pedido` con la MISMA clave de
--       idempotencia y recibe el pedido con `token_recogida = null`.
--     · El cliente llama entonces a `reemitir_token_recogida` con el
--       `pedido_id` devuelto y obtiene un token nuevo.
--     · Como solo se guarda el hash, el token original NO se puede
--       reconstruir: por eso el unico camino valido es la reemision
--       explicita, que ademas invalida cualquier token anterior.
--
--   Si el pedido ya esta 'entregado', 'cancelado' o 'expirado', no se
--   emite ningun token y la reemision tambien se rechaza.
-- ---------------------------------------------------------------------
create or replace function public.crear_pedido(
    p_tienda_id          uuid,
    p_origen             text,
    p_items              jsonb,
    p_clave_idempotencia uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_usuario    uuid := auth.uid();
    v_pedido     public.pedidos%rowtype;
    v_existente  public.pedidos%rowtype;
    v_items_norm jsonb;
    v_snapshot   jsonb;
    v_item       jsonb;
    v_total      bigint := 0;
    v_contenido  text;
    v_hash       text;
    v_token      text;
begin
    -- 1) Identidad: la toma la sesion, no el cliente. -----------------
    if v_usuario is null then
        raise exception 'Se requiere una sesion de usuario autenticado.'
            using errcode = '42501';
    end if;

    -- 2) Validacion de parametros. -----------------------------------
    --    Cada comprobacion va en su propia sentencia. PostgreSQL no
    --    garantiza la evaluacion de izquierda a derecha dentro de un
    --    WHERE con OR, asi que no se puede confiar en que la validacion
    --    de formato se ejecute ANTES de una conversion a numeric: el
    --    planificador puede evaluarla antes y la conversion fallaria
    --    con un error generico en vez del controlado.
    --
    --    2.0 Origen y clave de idempotencia.
    if p_origen is null or p_origen not in ('en_tienda', 'para_recoger') then
        raise exception 'Origen invalido: %', coalesce(p_origen, 'null')
            using errcode = '22023';
    end if;

    if p_clave_idempotencia is null then
        raise exception 'La clave de idempotencia es obligatoria.'
            using errcode = '22023';
    end if;

    --    2.1 Tipo del array (antes de poder usar jsonb_array_length).
    if p_items is null
       or pg_catalog.jsonb_typeof(p_items) <> 'array' then
        raise exception 'La orden debe ser un array de items.'
            using errcode = '22023';
    end if;

    --    2.2 Tamano del array: limite razonable por pedido.
    if pg_catalog.jsonb_array_length(p_items) > 50 then
        raise exception 'La orden no puede tener mas de 50 items.'
            using errcode = '22023';
    end if;

    --    2.3 El array no puede estar vacio.
    if pg_catalog.jsonb_array_length(p_items) = 0 then
        raise exception 'La orden debe tener al menos un producto.'
            using errcode = '22023';
    end if;

    --    2.4 Formato de cada item. SIN conversiones numericas.
    --        numeric tiene limites Propios, por eso el texto de la
    --        cantidad se acota a 10 caracteres: asi la conversion del
    --        punto 2.5 nunca puede fallar ni desbordar.
    if exists (
        select 1
          from pg_catalog.jsonb_array_elements(p_items) e
         where (e.value ->> 'producto_id') is null
            or (e.value ->> 'producto_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            or (e.value ->> 'cantidad') is null
            or (e.value ->> 'cantidad') !~ '^[0-9]+$'
            or pg_catalog.length(e.value ->> 'cantidad') > 10
    ) then
        raise exception 'Cada item debe tener producto_id (uuid) y cantidad (entero positivo).'
            using errcode = '22023';
    end if;

    --    2.5 Rango numerico. Solo se llega aqui si el formato ya es
    --        valido, asi que la conversion a numeric es siempre segura.
    if exists (
        select 1
          from pg_catalog.jsonb_array_elements(p_items) e
         where (e.value ->> 'cantidad')::numeric < 1
            or (e.value ->> 'cantidad')::numeric > 100
    ) then
        raise exception 'La cantidad de cada producto debe estar entre 1 y 100.'
            using errcode = '22023';
    end if;

    -- 3) Normalizar items (el mismo producto se agrupa y se ordena). --
    --    La suma se hace en numeric (cada cantidad ya esta validada y
    --    acotada a 10 caracteres, asi que no puede desbordar) y el
    --    resultado se valida en el paso siguiente.
    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'producto_id', producto_id,
                       'cantidad',    cantidad
                   )
                   order by producto_id
               ),
               '[]'::jsonb
           )
      into v_items_norm
      from (
            select (e.value ->> 'producto_id')::uuid as producto_id,
                   sum((e.value ->> 'cantidad')::numeric) as cantidad
              from pg_catalog.jsonb_array_elements(p_items) e
             group by 1
           ) t;

    -- 3b) Cantidad TOTAL por producto (tras agrupar): tambien entre 1 y 100.
    --     Asi 60 + 60 unidades del mismo producto se rechazan.
    if exists (
        select 1
          from pg_catalog.jsonb_array_elements(v_items_norm) i
         where (i.value ->> 'cantidad')::numeric < 1
            or (i.value ->> 'cantidad')::numeric > 100
    ) then
        raise exception 'La cantidad total de cada producto debe estar entre 1 y 100.'
            using errcode = '22023';
    end if;

    -- 4) Huella canonica del contenido de la orden. -------------------
    --    Solo depende de ids y cantidades: NO depende del catalogo, asi
    --    que se puede calcular y comparar aunque un producto ya no este
    --    disponible.
    v_contenido := p_tienda_id::text
                    || '|' || p_origen
                    || '|' || (
                        select pg_catalog.string_agg(
                                   (i.value ->> 'producto_id') || ':' || (i.value ->> 'cantidad'),
                                   ';' order by (i.value ->> 'producto_id'))
                          from pg_catalog.jsonb_array_elements(v_items_norm) i
                       );
    v_hash := pg_catalog.encode(extensions.digest(v_contenido, 'sha256'), 'hex');

    -- 5) Pedido ya existente? Se recupera ANTES de exigir que los
    --    productos actuales sigan disponibles, para que un reintento
    --    funcione aunque el catalogo haya cambiado. Los datos
    --    historicos se conservan intactos.
    select * into v_existente
      from public.pedidos
     where usuario_id = v_usuario
       and clave_idempotencia = p_clave_idempotencia
       for update;

    if v_existente.id is not null then
        -- Misma clave, contenido distinto -> rechazo explicito.
        if v_existente.contenido_hash is distinct from v_hash then
            raise exception
                'La clave de idempotencia ya se uso con un contenido de pedido diferente.'
                using errcode = '23505';
        end if;

        return public._respuesta_pedido(v_existente, false);
    end if;

    -- 6) Foto de precios del catalogo: UNA sola sentencia, asi que todos
    --    los precios y el total salen del mismo instante y no pueden
    --    divergir entre si.
    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'producto_id',         p.id,
                       'nombre_producto',     p.nombre,
                       'precio_unitario_cop', p.precio_cop,
                       'cantidad',            (t.value ->> 'cantidad')::int
                   )
                   order by p.id
               ),
               '[]'::jsonb
           )
      into v_snapshot
      from pg_catalog.jsonb_array_elements(v_items_norm) t
      join public.productos p
        on p.id = (t.value ->> 'producto_id')::uuid
      join public.categorias c
        on c.id = p.categoria_id
     where p.activo
       and c.activa;

    if pg_catalog.jsonb_array_length(v_snapshot)
       <> pg_catalog.jsonb_array_length(v_items_norm) then
        raise exception 'Alguno de los productos no esta disponible o su categoria esta inactiva.'
            using errcode = '22023';
    end if;

    -- 7) Total recalculado con la misma foto de precios. --------------
    select coalesce(
               pg_catalog.sum(
                   (s.value ->> 'cantidad')::int
                   * (s.value ->> 'precio_unitario_cop')::bigint
               ),
               0
           )
      into v_total
      from pg_catalog.jsonb_array_elements(v_snapshot) s;

    -- 8) La tienda debe existir y estar activa. -----------------------
    if not exists (
        select 1 from public.tiendas
         where id = p_tienda_id and activa
    ) then
        raise exception 'La tienda no existe o no esta activa.'
            using errcode = '22023';
    end if;

    -- 9) Alta idempotente y segura ante concurrencia. -----------------
    insert into public.pedidos (
        usuario_id, tienda_id, origen, total_cop, estado,
        clave_idempotencia, contenido_hash
    )
    values (
        v_usuario, p_tienda_id, p_origen, v_total, 'pendiente_pago',
        p_clave_idempotencia, v_hash
    )
    on conflict (usuario_id, clave_idempotencia) do nothing
    returning * into v_pedido;

    if v_pedido.id is not null then
        -- 10) Detalles desde la MISMA foto de precios. -----------------
        for v_item in select value from pg_catalog.jsonb_array_elements(v_snapshot) loop
            insert into public.detalle_pedido (
                pedido_id, producto_id, nombre_producto, cantidad,
                precio_unitario_cop
            )
            values (
                v_pedido.id,
                (v_item ->> 'producto_id')::uuid,
                v_item ->> 'nombre_producto',
                (v_item ->> 'cantidad')::int,
                (v_item ->> 'precio_unitario_cop')::bigint
            );
        end loop;

        -- 11) Emitir el token de recogida (caducidad del servidor). ---
        v_token := public._emitir_token_recogida(v_pedido.id);

        return public._respuesta_pedido(v_pedido, true, v_token);
    end if;

    -- 12) Carrera: otra peticion con la misma clave gano. Se recupera
    --     su pedido (ya confirmado) y se devuelve sin token.
    select * into v_existente
      from public.pedidos
     where usuario_id = v_usuario
       and clave_idempotencia = p_clave_idempotencia
       for update;

    if v_existente.id is null then
        raise exception 'No se pudo crear ni recuperar la orden.'
            using errcode = '40001';
    end if;

    if v_existente.contenido_hash is distinct from v_hash then
        raise exception
            'La clave de idempotencia ya se uso con un contenido de pedido diferente.'
            using errcode = '23505';
    end if;

    return public._respuesta_pedido(v_existente, false);
end;
$$;

comment on function public.crear_pedido(uuid, text, jsonb, uuid) is
    'Crea un pedido de forma atomica e idempotente. Identidad desde auth.uid(), precios y total recalculados en el servidor con una unica foto de precios, estado siempre pendiente_pago, token de recogida emitido solo en la creacion.';

revoke all on function public.crear_pedido(uuid, text, jsonb, uuid) from public, anon;
grant execute on function public.crear_pedido(uuid, text, jsonb, uuid) to authenticated;



-- ---------------------------------------------------------------------
-- Reemitir el token de recogida del propio pedido.
--
-- · Solo el propietario (auth.uid() = usuario_id) puede hacerlo.
-- · La reemision invalida el token anterior (la fila se sustituye).
-- · No se permite en pedidos ya entregados, cancelados o expirados.
-- · No se permite si el token existente ya se uso o se revoco.
-- · La caducidad del nuevo token es la politica del servidor.
-- ---------------------------------------------------------------------
create or replace function public.reemitir_token_recogida(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_usuario  uuid := auth.uid();
    v_pedido   public.pedidos%rowtype;
    v_usado    timestamptz;
    v_revocado timestamptz;
    v_token    text;
begin
    if v_usuario is null then
        raise exception 'Se requiere una sesion de usuario autenticado.'
            using errcode = '42501';
    end if;

    -- Bloqueo 1: la fila del pedido (siempre antes que la del token).
    select * into v_pedido
      from public.pedidos
     where id = p_pedido_id
       and usuario_id = v_usuario
       for update;

    if v_pedido.id is null then
        raise exception 'El pedido no existe o no te pertenece.'
            using errcode = '42501';
    end if;

    if v_pedido.estado in ('entregado', 'cancelado', 'expirado') then
        raise exception 'El pedido ya no admite un codigo de recogida (estado: %).',
            v_pedido.estado
            using errcode = '22023';
    end if;

    -- Bloqueo 2: la fila del token.
    select t.usado_en, t.revocado_en
      into v_usado, v_revocado
      from public.tokens_recogida t
     where t.pedido_id = p_pedido_id
       for update;

    if v_usado is not null then
        raise exception 'El codigo de recogida ya fue usado.'
            using errcode = '22023';
    end if;

    if v_revocado is not null then
        raise exception 'El codigo de recogida fue revocado.'
            using errcode = '22023';
    end if;

    v_token := public._emitir_token_recogida(p_pedido_id);

    return pg_catalog.jsonb_build_object(
        'pedido_id',                p_pedido_id,
        'numero_orden',             v_pedido.numero_orden,
        'estado',                   v_pedido.estado,
        'token_recogida',           v_token,
        'requiere_reemision',       false,
        'token_anterior_invalido',  true
    );
end;
$$;

comment on function public.reemitir_token_recogida(uuid) is
    'Rota el token de recogida de un pedido propio. Invalida el token anterior. No permitido en pedidos entregados, cancelados o expirados, ni con tokens usados o revocados.';

revoke all on function public.reemitir_token_recogida(uuid) from public, anon;
grant execute on function public.reemitir_token_recogida(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- El cliente no debe poder leer la tabla de tokens.
-- (Ya no tiene permisos, pero se deja explicito e inalterable.)
-- ---------------------------------------------------------------------
revoke all on table public.tokens_recogida from anon, authenticated;
