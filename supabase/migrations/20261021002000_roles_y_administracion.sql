-- =====================================================================
-- Mercamigo · 20261021002000_roles_y_administracion.sql
--
-- Perfil del usuario, roles de administrador y operaciones de
-- administracion.
--
-- NO recrea ninguna tabla, NO borra datos y NO abre permisos generales:
-- `anon` no gana ningun permiso de escritura y `authenticated` solo
-- puede escribir donde las politicas RLS lo permiten (es decir, solo si
-- es administrador, o en su propio perfil).
--
-- Decisiones de seguridad:
--
--   · La identidad de administrador NO se deduce de datos editables por
--     el cliente. Vive en `roles_usuario`, que solo se puede escribir
--     mediante funciones que exigen que quien llama ya sea
--     administrador.
--   · `perfiles` guarda solo el nombre y las fechas. Ni contrasenas ni
--     ningun otro dato de credencial: eso lo lleva Supabase Auth.
--   · Cada funcion SECURITY DEFINER comprueba la autorizacion y la
--     propiedad DENTRO de la operacion; no se apoya solo en RLS (que
--     las funciones SECURITY DEFINER esquivan al ejecutarse con el
--     propietario).
--   · Todas las funciones fijan `search_path = ''` y califican los
--     objetos de forma explicita.
--   · El cliente solo puede consultar SU PROPIO rol
--     (public.es_administrador(), sin parametros). Consultar el rol de
--     un UUID cualquiera es una operacion reservada al propietario del
--     servidor (public.es_administrador_de(uuid)).
--
-- ORDEN DE CREACION (importante: las politicas dependen de las funciones)
--   1. public.roles_usuario        (tabla + RLS, todavia sin politicas)
--   2. public.es_administrador()   (funcion)
--   3. public.es_administrador_de(uuid)
--   4. Politicas que usan es_administrador()
--   5. public.perfiles              (tabla + RLS + politicas)
--   6. public.handle_new_user()    (trigger de alta) + backfill
--   7. Funciones de administracion
--
-- ---------------------------------------------------------------------
-- EL PRIMER ADMINISTRADOR
--
-- El registro publico SIEMPRE crea una cuenta de comprador: no hay
-- selector publico de rol.
--
-- El primer administrador se asigna con una operacion EXCLUSIVA del
-- propietario del proyecto (no se puede llamar desde la app, porque
-- exige que quien llama ya sea administrador y en ese momento todavia
-- no lo hay):
--
--   1. El administrador crea su cuenta desde la app (Correo y
--      contrasena) o desde la consola de Supabase, y confirma el correo.
--   2. El propietario del proyecto ejecuta en el editor SQL:
--
--        select public.bootstrap_primer_administrador(
--            'dayroncamilo4+mercamigo@gmail.com'
--        );
--
--      La funcion comprueba primero que la cuenta EXISTE en
--      auth.users; si no existe, falla con un mensaje claro y NO asigna
--      ningun rol.
--
--   3. A partir de ahi, solo un administrador existente puede conceder
--      o retirar el rol con public.asignar_rol_administrador.
--
-- No hay contrasenas ni claves de administrador en el codigo de la app.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Roles (la autoridad NO es editable por el cliente).
-- ---------------------------------------------------------------------
create table if not exists public.roles_usuario (
    usuario_id uuid primary key references auth.users (id) on delete cascade,
    rol        text not null check (rol in ('administrador')),
    creado_en  timestamptz not null default pg_catalog.now()
);

comment on table public.roles_usuario is
    'Roles del usuario. Solo escribible mediante funciones que exigen que quien llama ya sea administrador.';

alter table public.roles_usuario enable row level security;


-- ---------------------------------------------------------------------
-- 2) Comprobacion de administrador del usuario ACTUAL.
--
--    No lleva parametro: el cliente solo puede preguntar por su propio
--    rol. Es la unica version ejecutable por `authenticated`.
--
--    SECURITY DEFINER: se ejecuta como propietario y por eso no entra
--    en recursion con la politica de `roles_usuario`.
-- ---------------------------------------------------------------------
create or replace function public.es_administrador()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
          from public.roles_usuario
         where usuario_id = auth.uid()
           and rol = 'administrador'
    );
$$;

comment on function public.es_administrador() is
    'Indica si el usuario de la sesion actual es administrador. No permite consultar el rol de otro UUID.';

revoke all on function public.es_administrador() from public, anon;
grant execute on function public.es_administrador() to authenticated;


-- ---------------------------------------------------------------------
-- 3) Comprobacion de administrador de un UUID concreto.
--
--    Reservada al propietario del proyecto: el cliente NO puede
--    consultar el rol de un UUID arbitrario.
-- ---------------------------------------------------------------------
create or replace function public.es_administrador_de(p_usuario uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
          from public.roles_usuario
         where usuario_id = p_usuario
           and rol = 'administrador'
    );
$$;

comment on function public.es_administrador_de(uuid) is
    'Indica si un usuario concreto es administrador. Solo ejecutable por el propietario del proyecto.';

revoke all on function public.es_administrador_de(uuid) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 4) Politicas que dependen de es_administrador().
--
--    · roles_usuario: cada usuario ve su propio rol; el administrador
--      ve todos.
--    · Catalogo: el administrador ve TAMBIEN los registros inactivos
--      (productos, codigos, categorias y tiendas desactivados). Es lo que
--      necesita el panel de administracion para revisar y reactivar lo
--      que ha quedado fuera de catalogo. El comprador sigue viendo solo
--      lo activo.
-- ---------------------------------------------------------------------
create policy roles_lectura on public.roles_usuario
    for select to authenticated
    using (
        usuario_id = (select auth.uid())
        or public.es_administrador()
    );

create policy productos_lectura_admin on public.productos
    for select to authenticated
    using (public.es_administrador());

create policy codigos_lectura_admin on public.codigos_producto
    for select to authenticated
    using (public.es_administrador());

create policy categorias_lectura_admin on public.categorias
    for select to authenticated
    using (public.es_administrador());

create policy tiendas_lectura_admin on public.tiendas
    for select to authenticated
    using (public.es_administrador());


-- ---------------------------------------------------------------------
-- 5) Perfil del usuario.
-- ---------------------------------------------------------------------
create table if not exists public.perfiles (
    id        uuid primary key references auth.users (id) on delete cascade,
    nombre    text not null,
    creado_en timestamptz not null default pg_catalog.now()
);

comment on table public.perfiles is
    'Perfil publico del usuario. Solo nombre y fechas: las credenciales las gestiona Supabase Auth.';

alter table public.perfiles enable row level security;

create policy perfiles_lectura on public.perfiles
    for select to authenticated
    using (
        id = (select auth.uid())
        or public.es_administrador()
    );

create policy perfiles_actualizacion on public.perfiles
    for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 6) Alta automatica del perfil al crear la cuenta, y relleno de los
--    perfiles de las cuentas que YA existen.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_nombre text;
begin
    v_nombre := coalesce(
        nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'nombre'), ''),
        nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'full_name'), ''),
        pg_catalog.split_part(coalesce(new.email, 'comprador'), '@', 1)
    );

    insert into public.perfiles (id, nombre)
    values (new.id, v_nombre)
    on conflict (id) do update
        set nombre = excluded.nombre;

    return new;
end;
$$;

comment on function public.handle_new_user() is
    'Crea el perfil del usuario al registrarse en Supabase Auth.';

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Relleno de los perfiles de las cuentas YA existentes.
-- `on conflict do nothing`: no sobrescribe un perfil que ya exista.
insert into public.perfiles (id, nombre)
select u.id,
       coalesce(
           nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'nombre'), ''),
           nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'full_name'), ''),
           pg_catalog.split_part(coalesce(u.email, 'comprador'), '@', 1)
       )
  from auth.users u
on conflict (id) do nothing;


-- ---------------------------------------------------------------------
-- 7) Permisos minimos.
--
--    El cliente NO escribe directamente en el catalogo: todas las
--    escrituras pasan por las funciones SECURITY DEFINER de la seccion
--    10 (crear_producto) y 11 (configurar_tienda), que comprueban el rol
--    DENTRO de la operacion. Por eso aqui NO se conceden permisos
--    INSERT/UPDATE/DELETE sobre productos, codigos_producto, categorias ni
--    tiendas: aunque existieran las politicas, el permiso acabaria
--    denegado en la capa de base de datos.
--
--    Operaciones disponibles para el cliente:
--      · SELECT del catalogo (solo activo) para cualquiera.
--      · SELECT del catalogo completo (incluido inactivo) para el
--        administrador, mediante las politicas *_lectura_admin.
--      · Crear producto con su codigo  -> public.crear_producto(...)
--      · Crear o editar la tienda      -> public.configurar_tienda(...)
--      · Crear pedidos                  -> public.crear_pedido(...)
--      · Reemitir su codigo de recogida-> public.reemitir_token_recogida(...)
--      · Consultar su propio rol       -> public.es_administrador()
--      · Editar su propio perfil       -> UPDATE public.perfiles (su fila)
--
--    `anon` no gana nada. `authenticated` solo escribe donde RLS lo
--    permite: en su propio perfil.
--    `pedidos` y `detalle_pedido` siguen siendo de solo lectura para el
--    cliente: se escriben exclusivamente via RPC.
--    `roles_usuario` no recibe permisos de escritura: sus filas solo se
--    crean desde el servidor.
-- ---------------------------------------------------------------------
grant update on public.perfiles to authenticated;
grant select on public.perfiles to authenticated;
grant select on public.roles_usuario to authenticated;


-- ---------------------------------------------------------------------
-- 8) Bootstrap del PRIMER administrador.
--
--    Exclusiva del propietario del proyecto: se revoca el permiso de
--    ejecucion a PUBLIC, anon y authenticated, asi que la app no puede
--    llamarla y ningun comprador puede auto-asignarse el rol.
--
--    Comprueba que la cuenta existe ANTES de asignar nada.
-- ---------------------------------------------------------------------
create or replace function public.bootstrap_primer_administrador(p_correo text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_usuario uuid;
    v_nombre  text;
begin
    if p_correo is null or pg_catalog.btrim(p_correo) = '' then
        raise exception 'El correo es obligatorio.'
            using errcode = '22023';
    end if;

    select u.id,
           coalesce(
               nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'nombre'), ''),
               nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'full_name'), ''),
               pg_catalog.split_part(coalesce(u.email, 'comprador'), '@', 1)
           )
      into v_usuario, v_nombre
      from auth.users u
     where lower(u.email) = lower(pg_catalog.btrim(p_correo));

    if v_usuario is null then
        raise exception
            'La cuenta % no existe todavia en auth.users. Creala, confirma el correo y vuelve a intentarlo.',
            p_correo
            using errcode = '22023';
    end if;

    insert into public.roles_usuario (usuario_id, rol)
    values (v_usuario, 'administrador')
    on conflict (usuario_id) do update
        set rol = 'administrador';

    insert into public.perfiles (id, nombre)
    values (v_usuario, v_nombre)
    on conflict (id) do nothing;

    return v_usuario;
end;
$$;

comment on function public.bootstrap_primer_administrador(text) is
    'Asigna el rol administrador a la primera cuenta. Solo ejecutable por el propietario del proyecto (no por la app). Exige que la cuenta ya exista en auth.users.';

revoke all on function public.bootstrap_primer_administrador(text) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 9) Asignar / retirar el rol de administrador.
--    Solo un administrador existente puede hacerlo: un comprador que
--    llama a la funcion recibe 42501 y no puede auto-asignarse el rol.
-- ---------------------------------------------------------------------
create or replace function public.asignar_rol_administrador(
    p_usuario uuid,
    p_asignar boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede gestionar los roles.'
            using errcode = '42501';
    end if;

    if p_usuario is null then
        raise exception 'El usuario es obligatorio.'
            using errcode = '22023';
    end if;

    if p_asignar then
        insert into public.roles_usuario (usuario_id, rol)
        values (p_usuario, 'administrador')
        on conflict (usuario_id) do update
            set rol = 'administrador';
    else
        delete from public.roles_usuario
         where usuario_id = p_usuario
           and rol = 'administrador';
    end if;
end;
$$;

comment on function public.asignar_rol_administrador(uuid, boolean) is
    'Concede o retira el rol administrador. Solo ejecutable por un administrador existente.';

revoke all on function public.asignar_rol_administrador(uuid, boolean) from public, anon;
grant execute on function public.asignar_rol_administrador(uuid, boolean) to authenticated;


-- ---------------------------------------------------------------------
-- 10) Crear producto + codigo, de forma atomica.
--     La autorizacion se comprueba DENTRO de la operacion.
--
--     Nota: en PostgreSQL los parametros con DEFAULT deben ir DETRAS de
--     los obligatorios, por eso el orden es
--     (categoria, nombre, precio, codigo, descripcion, stock, imagen, tipo).
-- ---------------------------------------------------------------------
create or replace function public.crear_producto(
    p_categoria_id   uuid,
    p_nombre         text,
    p_precio_cop     bigint,
    p_codigo         text,
    p_descripcion    text default 'Producto de demostracion para pruebas academicas',
    p_stock_demo     integer default 50,
    p_imagen_url     text default null,
    p_tipo_codigo    text default 'qr_demo'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_producto_id uuid;
begin
    -- Autorizacion dentro de la operacion (no basta con ocultar botones).
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede crear productos.'
            using errcode = '42501';
    end if;

    if p_nombre is null or pg_catalog.btrim(p_nombre) = '' then
        raise exception 'El nombre es obligatorio.'
            using errcode = '22023';
    end if;

    if p_precio_cop is null or p_precio_cop <= 0 then
        raise exception 'El precio debe ser mayor que cero.'
            using errcode = '22023';
    end if;

    if p_codigo is null or pg_catalog.btrim(p_codigo) = '' then
        raise exception 'El codigo es obligatorio.'
            using errcode = '22023';
    end if;

    if p_tipo_codigo is null
       or p_tipo_codigo not in ('qr_demo', 'qr', 'barras') then
        raise exception 'Tipo de codigo invalido: %', coalesce(p_tipo_codigo, 'null')
            using errcode = '22023';
    end if;

    if p_stock_demo is null or p_stock_demo < 0 then
        raise exception 'El stock no puede ser negativo.'
            using errcode = '22023';
    end if;

    if not exists (
        select 1 from public.categorias
         where id = p_categoria_id and activa
    ) then
        raise exception 'La categoria no existe o no esta activa.'
            using errcode = '22023';
    end if;

    -- Producto y codigo se crean en la misma transaccion: o se crean
    -- los dos, o no se crea ninguno.
    insert into public.productos (
        categoria_id, nombre, descripcion, precio_cop, imagen_url,
        stock_demo, activo, es_demostracion
    )
    values (
        p_categoria_id,
        pg_catalog.btrim(p_nombre),
        coalesce(p_descripcion, 'Producto de demostracion para pruebas academicas'),
        p_precio_cop,
        p_imagen_url,
        p_stock_demo,
        true,
        true
    )
    returning id into v_producto_id;

    insert into public.codigos_producto (producto_id, codigo, tipo)
    values (v_producto_id, pg_catalog.btrim(p_codigo), p_tipo_codigo);

    return pg_catalog.jsonb_build_object(
        'producto_id', v_producto_id,
        'codigo',      pg_catalog.btrim(p_codigo),
        'tipo',        p_tipo_codigo,
        'nombre',      pg_catalog.btrim(p_nombre)
    );
end;
$$;

comment on function public.crear_producto(uuid, text, bigint, text, text, integer, text, text) is
    'Crea un producto y su codigo registrado de forma atomica. Solo administradores (comprobado en el servidor).';

revoke all on function public.crear_producto(uuid, text, bigint, text, text, integer, text, text) from public, anon;
grant execute on function public.crear_producto(uuid, text, bigint, text, text, integer, text, text) to authenticated;


-- ---------------------------------------------------------------------
-- 11) Configurar la tienda.
--     Recibe el id de la tienda a editar: no se elige una fila
--     arbitraria (y `tiendas` no tiene columna `creado_en`).
--     Si `p_tienda_id` es null, se crea una tienda nueva.
--
--     La tabla `tiendas` esta vacia y no se inventa una ubicacion real:
--     hasta que un administrador registre una tienda activa, el RPC
--     `crear_pedido` rechaza las ordenes.
--     Latitud y longitud se configuran juntas o ninguna.
-- ---------------------------------------------------------------------
create or replace function public.configurar_tienda(
    p_tienda_id uuid,
    p_nombre    text,
    p_direccion text default null,
    p_latitud   double precision default null,
    p_longitud  double precision default null,
    p_activar   boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_tienda_id uuid;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede configurar la tienda.'
            using errcode = '42501';
    end if;

    if p_nombre is null or pg_catalog.btrim(p_nombre) = '' then
        raise exception 'El nombre de la tienda es obligatorio.'
            using errcode = '22023';
    end if;

    if (p_latitud is null) <> (p_longitud is null) then
        raise exception 'Latitud y longitud deben configurarse juntas.'
            using errcode = '22023';
    end if;

    if p_latitud is not null
       and (p_latitud < -90 or p_latitud > 90) then
        raise exception 'Latitud fuera de rango.'
            using errcode = '22023';
    end if;

    if p_longitud is not null
       and (p_longitud < -180 or p_longitud > 180) then
        raise exception 'Longitud fuera de rango.'
            using errcode = '22023';
    end if;

    if p_tienda_id is null then
        insert into public.tiendas (nombre, direccion, latitud, longitud, activa)
        values (
            pg_catalog.btrim(p_nombre),
            nullif(pg_catalog.btrim(p_direccion), ''),
            p_latitud,
            p_longitud,
            p_activar
        )
        returning id into v_tienda_id;
    else
        update public.tiendas
           set nombre    = pg_catalog.btrim(p_nombre),
               direccion = nullif(pg_catalog.btrim(p_direccion), ''),
               latitud   = p_latitud,
               longitud  = p_longitud,
               activa    = p_activar
         where id = p_tienda_id;

        if not found then
            raise exception 'La tienda indicada no existe.'
                using errcode = '22023';
        end if;

        v_tienda_id := p_tienda_id;
    end if;

    return pg_catalog.jsonb_build_object(
        'tienda_id', v_tienda_id,
        'nombre',    pg_catalog.btrim(p_nombre),
        'direccion', nullif(pg_catalog.btrim(p_direccion), ''),
        'latitud',   p_latitud,
        'longitud',  p_longitud,
        'activa',    p_activar
    );
end;
$$;

comment on function public.configurar_tienda(uuid, text, text, double precision, double precision, boolean) is
    'Configura (o crea) la tienda del proyecto. Solo administradores (comprobado en el servidor). Latitud y longitud se configuran juntas.';

revoke all on function public.configurar_tienda(uuid, text, text, double precision, double precision, boolean) from public, anon;
grant execute on function public.configurar_tienda(uuid, text, text, double precision, double precision, boolean) to authenticated;


-- ---------------------------------------------------------------------
-- 12) Endurecimiento opcional (lo reporta el linter de seguridad de
--     Supabase): la funcion disparadora `rls_auto_enable()` es
--     SECURITY DEFINER y el cliente podia invocarla por RPC. Es una
--     funcion de evento que solo usa el servidor, asi que se le puede
--     quitar el permiso de ejecucion. Se deja comentada para que la
--     decision sea explicita al aplicar la migracion.
--
--   revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
-- ---------------------------------------------------------------------
