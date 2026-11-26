-- Promociones configurables desde el panel de administración.
create table if not exists public.promociones (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    tipo text not null check (tipo in ('dos_por_uno', 'tres_por_dos', 'precio_paquete')),
    cantidad_compra integer not null default 2 check (cantidad_compra between 1 and 100),
    cantidad_gratis integer not null default 1 check (cantidad_gratis between 0 and 100),
    cantidad_paquete integer not null default 2 check (cantidad_paquete between 2 and 100),
    precio_paquete_cop bigint check (precio_paquete_cop is null or precio_paquete_cop >= 0),
    banner_url text,
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint promociones_paquete_precio check (
        (tipo = 'precio_paquete' and precio_paquete_cop is not null)
        or (tipo <> 'precio_paquete')
    )
);

create table if not exists public.promocion_productos (
    promocion_id uuid not null references public.promociones(id) on delete cascade,
    producto_id uuid not null references public.productos(id) on delete cascade,
    primary key (promocion_id, producto_id),
    unique (producto_id)
);

alter table public.promociones enable row level security;
alter table public.promocion_productos enable row level security;

revoke all on public.promociones, public.promocion_productos from public, anon, authenticated;
grant select on public.promociones, public.promocion_productos to anon, authenticated;
grant insert, update, delete on public.promociones, public.promocion_productos to authenticated;

create policy promociones_lectura_publica on public.promociones
    for select to anon, authenticated using (activa or public.es_administrador());
create policy promociones_admin_insert on public.promociones
    for insert to authenticated with check (public.es_administrador());
create policy promociones_admin_update on public.promociones
    for update to authenticated using (public.es_administrador())
    with check (public.es_administrador());
create policy promociones_admin_delete on public.promociones
    for delete to authenticated using (public.es_administrador());

create policy promocion_productos_lectura_publica on public.promocion_productos
    for select to anon, authenticated using (
        exists (select 1 from public.promociones p where p.id = promocion_id
                and (p.activa or public.es_administrador()))
    );
create policy promocion_productos_admin_insert on public.promocion_productos
    for insert to authenticated with check (public.es_administrador());
create policy promocion_productos_admin_delete on public.promocion_productos
    for delete to authenticated using (public.es_administrador());

create or replace function public.guardar_promocion(
    p_nombre text,
    p_tipo text,
    p_cantidad_compra integer,
    p_cantidad_gratis integer,
    p_cantidad_paquete integer,
    p_precio_paquete_cop bigint,
    p_banner_url text,
    p_productos uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede configurar promociones.'
            using errcode = '42501';
    end if;
    if p_tipo not in ('dos_por_uno', 'tres_por_dos', 'precio_paquete') then
        raise exception 'El tipo de promoción no es válido.' using errcode = '22023';
    end if;
    if p_nombre is null or pg_catalog.btrim(p_nombre) = '' then
        raise exception 'El nombre de la promoción es obligatorio.' using errcode = '22023';
    end if;
    if p_productos is null or pg_catalog.cardinality(p_productos) = 0 then
        raise exception 'Selecciona al menos un producto.' using errcode = '22023';
    end if;
    if p_tipo = 'precio_paquete'
       and (p_cantidad_paquete < 2 or p_precio_paquete_cop is null or p_precio_paquete_cop <= 0) then
        raise exception 'El paquete necesita cantidad y precio mayores que cero.' using errcode = '22023';
    end if;
    if exists (
        select 1
          from pg_catalog.unnest(p_productos) x(id)
          left join public.productos p on p.id = x.id
         where p.id is null or not p.activo
    ) then
        raise exception 'Todos los productos deben existir y estar activos.' using errcode = '22023';
    end if;

    insert into public.promociones (
        nombre, tipo, cantidad_compra, cantidad_gratis, cantidad_paquete,
        precio_paquete_cop, banner_url, activa
    ) values (
        pg_catalog.btrim(p_nombre), p_tipo,
        p_cantidad_compra, p_cantidad_gratis, p_cantidad_paquete,
        case when p_tipo = 'precio_paquete' then p_precio_paquete_cop else null end,
        p_banner_url, true
    ) returning id into v_id;

    delete from public.promocion_productos pp
     where pp.producto_id = any(p_productos);
    insert into public.promocion_productos (promocion_id, producto_id)
    select v_id, x.id
      from (select distinct u.id from pg_catalog.unnest(p_productos) as u(id)) x;
    update public.promociones pr
       set activa = false
     where pr.activa
       and pr.id <> v_id
       and not exists (select 1 from public.promocion_productos pp where pp.promocion_id = pr.id);

    return pg_catalog.jsonb_build_object('id', v_id);
end;
$$;

revoke all on function public.guardar_promocion(text, text, integer, integer, integer, bigint, text, uuid[])
    from public, anon;
grant execute on function public.guardar_promocion(text, text, integer, integer, integer, bigint, text, uuid[])
    to authenticated;

comment on table public.promociones is
    'Promociones del catálogo: 2x1, 3x2 y paquetes a precio fijo, configuradas por administración.';

-- Guarda el descuento aplicado por línea; el total de cada pedido sigue
-- calculándose en el servidor, nunca desde un precio enviado por el móvil.
alter table public.detalle_pedido
    alter column subtotal_cop drop expression;
alter table public.detalle_pedido
    add column if not exists descuento_cop bigint not null default 0
        check (descuento_cop >= 0);

create or replace function public._aplicar_promocion_a_detalle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_tipo text;
    v_compra integer;
    v_gratis integer;
    v_cantidad_paquete integer;
    v_precio_paquete bigint;
    v_pago bigint;
begin
    select pr.tipo, pr.cantidad_compra, pr.cantidad_gratis,
           pr.cantidad_paquete, pr.precio_paquete_cop
      into v_tipo, v_compra, v_gratis, v_cantidad_paquete, v_precio_paquete
      from public.promocion_productos pp
      join public.promociones pr on pr.id = pp.promocion_id
     where pp.producto_id = new.producto_id
       and pr.activa
     limit 1;

    v_pago := new.cantidad::bigint * new.precio_unitario_cop;
    if v_tipo = 'dos_por_uno' then
        v_pago := ((new.cantidad + 1) / 2)::bigint * new.precio_unitario_cop;
    elsif v_tipo = 'tres_por_dos' then
        v_pago := ((new.cantidad / 3) * 2 + (new.cantidad % 3))::bigint
                  * new.precio_unitario_cop;
    elsif v_tipo = 'precio_paquete' and v_cantidad_paquete > 0 then
        v_pago := (new.cantidad / v_cantidad_paquete)::bigint * v_precio_paquete
                  + (new.cantidad % v_cantidad_paquete)::bigint * new.precio_unitario_cop;
    end if;

    new.descuento_cop := greatest(
        new.cantidad::bigint * new.precio_unitario_cop - v_pago, 0
    );
    new.subtotal_cop := new.cantidad::bigint * new.precio_unitario_cop
                        - new.descuento_cop;
    return new;
end;
$$;

revoke all on function public._aplicar_promocion_a_detalle() from public, anon, authenticated;
drop trigger if exists detalle_pedido_aplicar_promocion on public.detalle_pedido;
create trigger detalle_pedido_aplicar_promocion
    before insert on public.detalle_pedido
    for each row execute function public._aplicar_promocion_a_detalle();

create or replace function public._actualizar_total_pedido_con_promociones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.pedidos p
       set total_cop = (select coalesce(sum(d.subtotal_cop), 0)
                          from public.detalle_pedido d
                         where d.pedido_id = new.pedido_id)
     where p.id = new.pedido_id;
    return new;
end;
$$;

revoke all on function public._actualizar_total_pedido_con_promociones() from public, anon, authenticated;
drop trigger if exists detalle_pedido_actualizar_total on public.detalle_pedido;
create trigger detalle_pedido_actualizar_total
    after insert on public.detalle_pedido
    for each row execute function public._actualizar_total_pedido_con_promociones();

-- La función original mantiene su validación e idempotencia. Se añade una
-- lectura posterior del pedido para devolver el total rebajado por el trigger.
do $$
declare
    v_def text;
    v_marker text := 'v_token := public._emitir_token_recogida(v_pedido.id);';
begin
    v_def := pg_catalog.pg_get_functiondef(
        'public.crear_pedido(uuid,text,jsonb,uuid)'::pg_catalog.regprocedure
    );
    if pg_catalog.strpos(v_def, v_marker) = 0 then
        raise exception 'No se pudo actualizar crear_pedido para devolver el total promocional.';
    end if;
    v_def := pg_catalog.replace(
        v_def,
        v_marker,
        v_marker || E'\n        select p.* into v_pedido from public.pedidos p where p.id = v_pedido.id;'
    );
    execute v_def;
end;
$$;
