-- =====================================================================
-- Mercamigo · ESQUEMA INICIAL (solo para la base de pruebas local)
--
-- Réplica del esquema que ya existe en el proyecto Supabase
-- `moviles-mercamigo`, para poder instalar y probar las migraciones en un
-- PostgreSQL local.
--
-- ⚠ ESTE ARCHIVO NO ES UNA MIGRACIÓN. NO se aplica al proyecto remoto:
--    el esquema remoto ya existe y no se toca.
--
-- Incluye un sustituto minimo del esquema `auth` (tabla users + auth.uid())
-- y de `extensions` (pgcrypto), que en Supabase los gestiona la plataforma.
-- =====================================================================

create schema if not exists auth;
create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;

-- Roles de prueba: los usuarios simulados (anon / authenticated).
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end
$$;

grant usage on schema public to anon, authenticated;


-- ---------------------------------------------------------------------
-- Equivalente local del disparador de evento de Supabase.
--
-- En el proyecto real, `public.rls_auto_enable()` lo crea la plataforma:
-- es un event trigger (RETURNS event_trigger) que habilita RLS en las
-- tablas nuevas del esquema public. Se replica aqui para poder probar la
-- migracion de endurecimiento (que le revoca EXECUTE al cliente) y
-- comprobar que el disparador sigue funcionando.
-- ---------------------------------------------------------------------
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $$
declare
    cmd record;
    tbl name;
begin
    for cmd in
        select * from pg_event_trigger_ddl_commands()
         where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
           and object_type in ('table', 'partitioned table')
    loop
        if cmd.schema_name = 'public' then
            select c.relname into tbl
              from pg_catalog.pg_class c
             where c.oid = cmd.objid;
            execute format(
                'alter table if exists %I.%I enable row level security',
                cmd.schema_name, tbl);
        end if;
    end loop;
end;
$$;

create event trigger rls_auto_enable_trigger
    on ddl_command_end
    execute function public.rls_auto_enable();

-- ---------------------------------------------------------------------
-- Sustituto minimo de auth.users y auth.uid().
-- ---------------------------------------------------------------------
create table if not exists auth.users (
    id                 uuid primary key default gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at         timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
    select coalesce(
        nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), ''),
        (nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid;
$$;

-- ---------------------------------------------------------------------
-- Tablas del proyecto (columnas, restricciones y defaults del remoto).
-- ---------------------------------------------------------------------
create table public.categorias (
    id      uuid primary key default gen_random_uuid(),
    nombre  text not null unique,
    activa  boolean not null default true
);

create table public.productos (
    id              uuid primary key default gen_random_uuid(),
    categoria_id    uuid not null references public.categorias (id),
    nombre          text not null,
    descripcion     text not null default 'Producto de demostración para pruebas académicas',
    precio_cop      bigint not null check (precio_cop > 0),
    imagen_url      text,
    stock_demo      integer not null default 50 check (stock_demo >= 0),
    activo          boolean not null default true,
    es_demostracion boolean not null default true,
    creado_en       timestamptz not null default now()
);

create index if not exists productos_categoria_idx
    on public.productos (categoria_id);

create table public.codigos_producto (
    id          uuid primary key default gen_random_uuid(),
    producto_id uuid not null references public.productos (id),
    codigo      text not null unique,
    tipo        text not null default 'qr_demo'
        check (tipo in ('qr_demo', 'qr', 'barras'))
);

create table public.tiendas (
    id        uuid primary key default gen_random_uuid(),
    nombre    text not null,
    direccion text,
    latitud   double precision check (latitud between -90 and 90),
    longitud  double precision check (longitud between -180 and 180),
    activa    boolean not null default false
);

create table public.pedidos (
    id                 uuid primary key default gen_random_uuid(),
    numero_orden       bigint generated always as identity unique,
    usuario_id         uuid not null references auth.users (id),
    tienda_id          uuid not null references public.tiendas (id),
    origen             text not null check (origen in ('en_tienda', 'para_recoger')),
    total_cop          bigint not null check (total_cop >= 0),
    estado             text not null default 'pendiente_pago'
        check (estado in ('pendiente_pago', 'pagado', 'entregado', 'cancelado', 'expirado')),
    clave_idempotencia uuid not null,
    creado_en          timestamptz not null default now(),
    unique (usuario_id, clave_idempotencia)
);

create index if not exists pedidos_usuario_fecha_idx
    on public.pedidos (usuario_id, creado_en desc);
create index if not exists pedidos_tienda_idx
    on public.pedidos (tienda_id);

create table public.detalle_pedido (
    id                  uuid primary key default gen_random_uuid(),
    pedido_id           uuid not null references public.pedidos (id),
    producto_id         uuid not null references public.productos (id),
    nombre_producto     text not null,
    cantidad            integer not null check (cantidad > 0),
    precio_unitario_cop bigint not null check (precio_unitario_cop > 0),
    subtotal_cop        bigint generated always as
                        (cantidad::bigint * precio_unitario_cop) stored,
    unique (pedido_id, producto_id)
);

create index if not exists detalle_producto_idx
    on public.detalle_pedido (producto_id);

create table public.tokens_recogida (
    id          uuid primary key default gen_random_uuid(),
    pedido_id   uuid not null unique references public.pedidos (id),
    token_hash  text not null unique check (length(token_hash) = 64),
    creado_en   timestamptz not null default now(),
    expira_en   timestamptz,
    usado_en    timestamptz,
    revocado_en timestamptz,
    check (expira_en is null or expira_en > creado_en)
);

-- ---------------------------------------------------------------------
-- RLS y permisos: exactamente los del proyecto remoto.
-- ---------------------------------------------------------------------
alter table public.categorias       enable row level security;
alter table public.productos        enable row level security;
alter table public.codigos_producto enable row level security;
alter table public.tiendas          enable row level security;
alter table public.pedidos          enable row level security;
alter table public.detalle_pedido   enable row level security;
alter table public.tokens_recogida  enable row level security;

create policy categorias_lectura on public.categorias
    for select to anon, authenticated
    using (activa);

create policy productos_lectura on public.productos
    for select to anon, authenticated
    using (
        activo
        and exists (
            select 1 from public.categorias c
             where c.id = productos.categoria_id and c.activa
        )
    );

create policy codigos_lectura on public.codigos_producto
    for select to anon, authenticated
    using (
        exists (
            select 1 from public.productos p
             where p.id = codigos_producto.producto_id and p.activo
        )
    );

create policy tiendas_lectura on public.tiendas
    for select to anon, authenticated
    using (activa);

create policy pedidos_propios on public.pedidos
    for select to authenticated
    using (usuario_id = (select auth.uid()));

create policy detalles_propios on public.detalle_pedido
    for select to authenticated
    using (
        exists (
            select 1 from public.pedidos p
             where p.id = detalle_pedido.pedido_id
               and p.usuario_id = (select auth.uid())
        )
    );

grant select on public.categorias       to anon, authenticated;
grant select on public.productos        to anon, authenticated;
grant select on public.codigos_producto to anon, authenticated;
grant select on public.tiendas          to anon, authenticated;
grant select on public.pedidos          to authenticated;
grant select on public.detalle_pedido   to authenticated;

-- El cliente nunca ESCRIBE: los pedidos se crean via RPC.
-- (El SELECT si se conserva: el comprador necesita leer sus pedidos.)
revoke insert, update, delete on public.pedidos        from anon, authenticated;
revoke insert, update, delete on public.detalle_pedido from anon, authenticated;
revoke all on public.tokens_recogida from anon, authenticated;
