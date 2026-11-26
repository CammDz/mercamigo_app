-- Personal de caja, transiciones de pago/entrega y reportes reales.
--
-- Contexto del proyecto:
--   · roles_usuario solo permitía 'administrador'.
--   · No existían funciones para cobrar, entregar, buscar pedidos por número
--     ni generar reportes.
--   · pedidos no guardaba la fecha de pago ni la de entrega.
--
-- Este archivo es idempotente en su mayor parte y no borra datos. Solo añade
-- el rol 'personal', dos columnas de fecha y las funciones de la caja.
--
-- Permisos:
--   · Ninguna función nueva queda disponible para anon.
--   · El rol 'personal' no puede autoasignarse: solo un administrador puede
--     concederlo y nunca puede degradar a otro administrador.

-- ---------------------------------------------------------------------------
-- 1) Rol de personal de caja
-- ---------------------------------------------------------------------------
alter table public.roles_usuario
    drop constraint if exists roles_usuario_rol_check;

alter table public.roles_usuario
    add constraint roles_usuario_rol_check
    check (rol in ('administrador', 'personal'));

create or replace function public.es_personal()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
    select exists (
        select 1
          from public.roles_usuario
         where usuario_id = auth.uid()
           and rol in ('personal', 'administrador')
    );
$function$;

revoke all on function public.es_personal() from public, anon;
grant execute on function public.es_personal() to authenticated;

-- Solo un administrador puede dar o quitar el rol de caja.
-- No se permite tocar el propio rol y nunca se degrada a un administrador.
create or replace function public.asignar_rol_personal(
    p_usuario uuid,
    p_asignar boolean default true
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede gestionar el rol de caja.'
            using errcode = '42501';
    end if;

    if p_usuario is null then
        raise exception 'El usuario es obligatorio.'
            using errcode = '22023';
    end if;

    if p_usuario = auth.uid() then
        raise exception 'No puedes cambiar tu propio rol.'
            using errcode = '42501';
    end if;

    if p_asignar then
        insert into public.roles_usuario (usuario_id, rol)
        values (p_usuario, 'personal')
        on conflict (usuario_id) do nothing;
    else
        delete from public.roles_usuario
         where usuario_id = p_usuario
           and rol = 'personal';
    end if;
end;
$function$;

revoke all on function public.asignar_rol_personal(uuid, boolean) from public, anon;
grant execute on function public.asignar_rol_personal(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Fechas reales de pago y entrega (para reportes y recibos)
-- ---------------------------------------------------------------------------
alter table public.pedidos
    add column if not exists pagado_en timestamptz,
    add column if not exists entregado_en timestamptz;

create index if not exists pedidos_pagado_en_idx
    on public.pedidos (pagado_en)
    where estado in ('pagado', 'entregado');

create index if not exists pedidos_estado_creado_idx
    on public.pedidos (estado, creado_en);

-- ---------------------------------------------------------------------------
-- 3) Validación de existencias en el detalle
-- ---------------------------------------------------------------------------
-- El stock es el campo existente `productos.stock_demo`. No se descuenta:
-- se valida que la cantidad pedida no supere lo disponible en ese momento.
-- Así el servidor no acepta una orden que la app no debería permitir.
create or replace function public._validar_stock_detalle()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_stock integer;
begin
    select p.stock_demo
      into v_stock
      from public.productos p
     where p.id = new.producto_id;

    if v_stock is null then
        raise exception 'El producto "%" ya no existe.', new.nombre_producto
            using errcode = '22023';
    end if;

    if new.cantidad > v_stock then
        raise exception 'No hay existencias suficientes de "%". Disponibles: %.',
            new.nombre_producto, v_stock
            using errcode = '22023';
    end if;

    return new;
end;
$function$;

revoke all on function public._validar_stock_detalle() from public, anon, authenticated;

drop trigger if exists detalle_pedido_stock on public.detalle_pedido;
create trigger detalle_pedido_stock
    before insert on public.detalle_pedido
    for each row execute function public._validar_stock_detalle();

-- ---------------------------------------------------------------------------
-- 4) Consultas de caja
-- ---------------------------------------------------------------------------

-- Lista de pedidos para el personal. Incluye solo el nombre del cliente
-- (nunca correo, teléfono ni identificadores de autenticación).
create or replace function public.listar_pedidos_personal(
    p_estados text[] default null,
    p_busqueda text default null,
    p_limite integer default 50,
    p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_limite  integer := least(greatest(coalesce(p_limite, 50), 1), 100);
    v_offset  integer := greatest(coalesce(p_offset, 0), 0);
    v_q       text;
    v_digitos text;
    v_total   bigint;
    v_items   jsonb;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    -- El cron de cada minuto también expira; esta llamada evita que una
    -- pantalla abierta muestre como pendiente un pedido ya vencido.
    perform public.expirar_pedidos_vencidos();

    if p_busqueda is not null and pg_catalog.btrim(p_busqueda) <> '' then
        v_q := pg_catalog.btrim(p_busqueda);
        v_digitos := pg_catalog.regexp_replace(v_q, '\D', '', 'g');
        v_digitos := pg_catalog.ltrim(v_digitos, '0');
    end if;

    if p_estados is not null and exists (
        select 1
          from pg_catalog.unnest(p_estados) e
         where e not in ('pendiente_pago', 'pagado', 'entregado', 'cancelado', 'expirado')
    ) then
        raise exception 'Filtro de estado inválido.'
            using errcode = '22023';
    end if;

    select count(*)
      into v_total
      from public.pedidos p
      left join public.perfiles pr on pr.id = p.usuario_id
     where (p_estados is null or pg_catalog.cardinality(p_estados) = 0
            or p.estado = any(p_estados))
       and (
            v_q is null
            or pr.nombre ilike '%' || v_q || '%'
            or (v_digitos <> '' and p.numero_orden::text = v_digitos)
       );

    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'pedido_id',       x.id,
                       'numero_orden',    x.numero_orden,
                       'estado',          x.estado,
                       'origen',          x.origen,
                       'total_cop',       x.total_cop,
                       'creado_en',       x.creado_en,
                       'expira_en',       x.expira_en,
                       'pagado_en',       x.pagado_en,
                       'entregado_en',    x.entregado_en,
                       'cliente_nombre',  x.cliente_nombre,
                       'unidades',        x.unidades
                   )
                   order by x.numero_orden desc
               ),
               '[]'::jsonb
           )
      into v_items
      from (
            select p.*,
                   coalesce(pr.nombre, '') as cliente_nombre,
                   (
                       select coalesce(pg_catalog.sum(d.cantidad), 0)
                         from public.detalle_pedido d
                        where d.pedido_id = p.id
                   ) as unidades
              from public.pedidos p
              left join public.perfiles pr on pr.id = p.usuario_id
             where (p_estados is null or pg_catalog.cardinality(p_estados) = 0
                    or p.estado = any(p_estados))
               and (
                    v_q is null
                    or pr.nombre ilike '%' || v_q || '%'
                    or (v_digitos <> '' and p.numero_orden::text = v_digitos)
               )
             order by p.numero_orden desc
             limit v_limite
            offset v_offset
      ) x;

    return pg_catalog.jsonb_build_object(
        'pedidos', v_items,
        'total',   v_total,
        'limite',  v_limite,
        'offset',  v_offset
    );
end;
$function$;

revoke all on function public.listar_pedidos_personal(text[], text, integer, integer)
    from public, anon;
grant execute on function public.listar_pedidos_personal(text[], text, integer, integer)
    to authenticated;

-- Detalle completo del recibo para el personal.
create or replace function public.detalle_pedido_personal(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_pedido public.pedidos%rowtype;
    v_cliente text;
    v_tienda text;
    v_direccion text;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    if p_pedido_id is null then
        raise exception 'El pedido es obligatorio.'
            using errcode = '22023';
    end if;

    select p.*
      into v_pedido
      from public.pedidos p
     where p.id = p_pedido_id;

    if not found then
        raise exception 'El pedido no existe.'
            using errcode = '22023';
    end if;

    select coalesce(pr.nombre, '')
      into v_cliente
      from public.perfiles pr
     where pr.id = v_pedido.usuario_id;

    select t.nombre, t.direccion
      into v_tienda, v_direccion
      from public.tiendas t
     where t.id = v_pedido.tienda_id;

    return pg_catalog.jsonb_build_object(
        'pedido_id',        v_pedido.id,
        'numero_orden',     v_pedido.numero_orden,
        'estado',           v_pedido.estado,
        'origen',           v_pedido.origen,
        'total_cop',        v_pedido.total_cop,
        'creado_en',        v_pedido.creado_en,
        'expira_en',        v_pedido.expira_en,
        'pagado_en',        v_pedido.pagado_en,
        'entregado_en',     v_pedido.entregado_en,
        'cliente_nombre',   coalesce(v_cliente, ''),
        'tienda_nombre',    v_tienda,
        'tienda_direccion', v_direccion,
        'items',            public._detalle_de_orden(v_pedido.id)
    );
end;
$function$;

revoke all on function public.detalle_pedido_personal(uuid) from public, anon;
grant execute on function public.detalle_pedido_personal(uuid) to authenticated;

-- Búsqueda por número de orden o por el código de barras que lo representa.
-- El número solo identifica el pedido: la autorización es el rol de caja.
create or replace function public.buscar_pedido_personal(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_valor   text := pg_catalog.btrim(coalesce(p_codigo, ''));
    v_digitos text;
    v_id      uuid;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    if v_valor = '' then
        return pg_catalog.jsonb_build_object(
            'encontrado', false,
            'mensaje', 'Escribe o escanea un número de orden.'
        );
    end if;

    v_digitos := pg_catalog.regexp_replace(v_valor, '\D', '', 'g');
    v_digitos := pg_catalog.ltrim(v_digitos, '0');

    select p.id
      into v_id
      from public.pedidos p
     where p.id::text = pg_catalog.lower(v_valor)
        or (v_digitos <> '' and p.numero_orden::text = v_digitos)
     order by p.numero_orden desc
     limit 1;

    if v_id is null then
        return pg_catalog.jsonb_build_object(
            'encontrado', false,
            'mensaje', 'No se encontró ningún pedido con ese número.'
        );
    end if;

    return pg_catalog.jsonb_build_object(
        'encontrado', true,
        'pedido',     public.detalle_pedido_personal(v_id)
    );
end;
$function$;

revoke all on function public.buscar_pedido_personal(text) from public, anon;
grant execute on function public.buscar_pedido_personal(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Transiciones atómicas de caja
-- ---------------------------------------------------------------------------

-- Registrar el pago físico. Es idempotente: repetir la llamada no cobra dos
-- veces ni cambia un pedido ya entregado. Un pedido vencido se marca expirado
-- y no se cobra. Un pedido cancelado no se puede cobrar.
create or replace function public.confirmar_pago_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_pedido  public.pedidos%rowtype;
    v_cliente text;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    if p_pedido_id is null then
        raise exception 'El pedido es obligatorio.'
            using errcode = '22023';
    end if;

    select p.*
      into v_pedido
      from public.pedidos p
     where p.id = p_pedido_id
     for update;

    if not found then
        raise exception 'El pedido no existe.'
            using errcode = '22023';
    end if;

    select coalesce(pr.nombre, '')
      into v_cliente
      from public.perfiles pr
     where pr.id = v_pedido.usuario_id;

    if v_pedido.estado = 'pendiente_pago'
       and v_pedido.expira_en is not null
       and v_pedido.expira_en <= pg_catalog.now() then
        update public.pedidos
           set estado = 'expirado'
         where id = v_pedido.id
           and estado = 'pendiente_pago';

        return pg_catalog.jsonb_build_object(
            'pedido_id',      v_pedido.id,
            'numero_orden',   v_pedido.numero_orden,
            'estado',         'expirado',
            'cliente_nombre', coalesce(v_cliente, ''),
            'pago_registrado', false,
            'ya_estaba',      false,
            'mensaje',        'El pedido caducó y no se puede cobrar.'
        );
    end if;

    if v_pedido.estado = 'pendiente_pago' then
        update public.pedidos
           set estado = 'pagado',
               pagado_en = pg_catalog.now(),
               expira_en = null
         where id = v_pedido.id
           and estado = 'pendiente_pago'
         returning * into v_pedido;

        return pg_catalog.jsonb_build_object(
            'pedido_id',      v_pedido.id,
            'numero_orden',   v_pedido.numero_orden,
            'estado',         v_pedido.estado,
            'cliente_nombre', coalesce(v_cliente, ''),
            'pago_registrado', true,
            'ya_estaba',      false,
            'mensaje',        'Pago registrado. Ahora confirma la entrega física.'
        );
    end if;

    if v_pedido.estado in ('pagado', 'entregado') then
        return pg_catalog.jsonb_build_object(
            'pedido_id',      v_pedido.id,
            'numero_orden',   v_pedido.numero_orden,
            'estado',         v_pedido.estado,
            'cliente_nombre', coalesce(v_cliente, ''),
            'pago_registrado', false,
            'ya_estaba',      true,
            'mensaje',        'Este pedido ya tenía el pago registrado.'
        );
    end if;

    raise exception 'No se puede cobrar un pedido en estado %.', v_pedido.estado
        using errcode = '22023';
end;
$function$;

revoke all on function public.confirmar_pago_pedido(uuid) from public, anon;
grant execute on function public.confirmar_pago_pedido(uuid) to authenticated;

-- Confirmar la entrega física. Solo se permite después del pago. Es
-- idempotente: repetir la llamada no crea una segunda entrega.
create or replace function public.confirmar_entrega_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_pedido  public.pedidos%rowtype;
    v_cliente text;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    if p_pedido_id is null then
        raise exception 'El pedido es obligatorio.'
            using errcode = '22023';
    end if;

    select p.*
      into v_pedido
      from public.pedidos p
     where p.id = p_pedido_id
     for update;

    if not found then
        raise exception 'El pedido no existe.'
            using errcode = '22023';
    end if;

    select coalesce(pr.nombre, '')
      into v_cliente
      from public.perfiles pr
     where pr.id = v_pedido.usuario_id;

    if v_pedido.estado = 'entregado' then
        return pg_catalog.jsonb_build_object(
            'pedido_id',         v_pedido.id,
            'numero_orden',      v_pedido.numero_orden,
            'estado',            v_pedido.estado,
            'cliente_nombre',    coalesce(v_cliente, ''),
            'entrega_registrada', false,
            'ya_estaba',         true,
            'mensaje',           'Este pedido ya estaba entregado.'
        );
    end if;

    if v_pedido.estado <> 'pagado' then
        raise exception
            'Solo se puede entregar un pedido pagado. Estado actual: %.',
            v_pedido.estado
            using errcode = '22023';
    end if;

    update public.pedidos
       set estado = 'entregado',
           entregado_en = pg_catalog.now()
     where id = v_pedido.id
       and estado = 'pagado'
     returning * into v_pedido;

    return pg_catalog.jsonb_build_object(
        'pedido_id',         v_pedido.id,
        'numero_orden',      v_pedido.numero_orden,
        'estado',            v_pedido.estado,
        'cliente_nombre',    coalesce(v_cliente, ''),
        'entrega_registrada', true,
        'ya_estaba',         false,
        'mensaje',           'Entrega registrada. El pedido quedó completado.'
    );
end;
$function$;

revoke all on function public.confirmar_entrega_pedido(uuid) from public, anon;
grant execute on function public.confirmar_entrega_pedido(uuid) to authenticated;

-- Cancelación explícita: solo pedidos pendientes de pago y no vencidos.
-- No se cancela un pedido pagado: no existe un reembolso electrónico en la
-- app y no se debe fingir uno. El dinero se devuelve físicamente en caja si
-- la tienda lo autoriza, pero el pedido conserva su estado pagado.
create or replace function public.cancelar_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_usuario uuid := auth.uid();
    v_pedido  public.pedidos%rowtype;
begin
    if v_usuario is null then
        raise exception 'Se requiere una sesión de usuario autenticado.'
            using errcode = '42501';
    end if;

    if p_pedido_id is null then
        raise exception 'El pedido es obligatorio.'
            using errcode = '22023';
    end if;

    select p.*
      into v_pedido
      from public.pedidos p
     where p.id = p_pedido_id
     for update;

    if not found
       or (v_pedido.usuario_id <> v_usuario and not public.es_personal()) then
        raise exception 'El pedido no existe o no te pertenece.'
            using errcode = '42501';
    end if;

    if v_pedido.estado = 'cancelado' then
        return pg_catalog.jsonb_build_object(
            'pedido_id',    v_pedido.id,
            'numero_orden', v_pedido.numero_orden,
            'estado',       v_pedido.estado,
            'cancelado',    false,
            'ya_estaba',    true,
            'mensaje',      'Este pedido ya estaba cancelado.'
        );
    end if;

    if v_pedido.estado = 'expirado' then
        return pg_catalog.jsonb_build_object(
            'pedido_id',    v_pedido.id,
            'numero_orden', v_pedido.numero_orden,
            'estado',       v_pedido.estado,
            'cancelado',    false,
            'ya_estaba',    true,
            'mensaje',      'Este pedido ya había caducado.'
        );
    end if;

    if v_pedido.estado <> 'pendiente_pago' then
        raise exception
            'Solo se puede cancelar un pedido pendiente de pago. '
            'Un pedido pagado se resuelve físicamente en caja.'
            using errcode = '22023';
    end if;

    if v_pedido.expira_en is not null
       and v_pedido.expira_en <= pg_catalog.now() then
        update public.pedidos
           set estado = 'expirado'
         where id = v_pedido.id
           and estado = 'pendiente_pago';

        return pg_catalog.jsonb_build_object(
            'pedido_id',    v_pedido.id,
            'numero_orden', v_pedido.numero_orden,
            'estado',       'expirado',
            'cancelado',    false,
            'ya_estaba',    false,
            'mensaje',      'El pedido caducó antes de cancelarse.'
        );
    end if;

    update public.pedidos
       set estado = 'cancelado'
     where id = v_pedido.id
       and estado = 'pendiente_pago'
     returning * into v_pedido;

    return pg_catalog.jsonb_build_object(
        'pedido_id',    v_pedido.id,
        'numero_orden', v_pedido.numero_orden,
        'estado',       v_pedido.estado,
        'cancelado',    true,
        'ya_estaba',    false,
        'mensaje',      'Pedido cancelado. No se realizó ningún cobro.'
    );
end;
$function$;

revoke all on function public.cancelar_pedido(uuid) from public, anon;
grant execute on function public.cancelar_pedido(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Reportes reales (America/Bogota)
-- ---------------------------------------------------------------------------
-- Las ventas se cuentan UNA sola vez por pedido: el estado pagado y el estado
-- entregado son excluyentes en la tabla (no hay dos filas), así que un pedido
-- entregado no se suma dos veces. La fecha de venta es `pagado_en`; si un
-- pedido histórico no la tiene se usa `creado_en` como respaldo transparente.
create or replace function public.reporte_ventas(
    p_desde date,
    p_hasta date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_inicio        timestamptz;
    v_fin           timestamptz;
    v_pedidos       bigint;
    v_ventas        bigint;
    v_promedio      bigint;
    v_serie         jsonb;
    v_top           jsonb;
begin
    if not public.es_personal() then
        raise exception 'Tu cuenta no tiene permisos de caja.'
            using errcode = '42501';
    end if;

    if p_desde is null or p_hasta is null then
        raise exception 'Indica el periodo del reporte.'
            using errcode = '22023';
    end if;

    if p_hasta < p_desde then
        raise exception 'La fecha final no puede ser anterior a la inicial.'
            using errcode = '22023';
    end if;

    if p_hasta - p_desde > 366 then
        raise exception 'El periodo del reporte no puede superar un año.'
            using errcode = '22023';
    end if;

    -- Límites del día en hora de Bogotá, convertidos a instantes UTC.
    v_inicio := (p_desde::timestamp at time zone 'America/Bogota');
    v_fin    := ((p_hasta + 1)::timestamp at time zone 'America/Bogota');

    select count(*), coalesce(pg_catalog.sum(p.total_cop), 0)
      into v_pedidos, v_ventas
      from public.pedidos p
     where p.estado in ('pagado', 'entregado')
       and coalesce(p.pagado_en, p.creado_en) >= v_inicio
       and coalesce(p.pagado_en, p.creado_en) < v_fin;

    v_promedio := case when v_pedidos = 0 then 0
                       else (v_ventas / v_pedidos)::bigint end;

    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'fecha',   pg_catalog.to_char(d.dia, 'YYYY-MM-DD'),
                       'pedidos', coalesce(s.pedidos, 0),
                       'ventas',  coalesce(s.ventas, 0)
                   )
                   order by d.dia
               ),
               '[]'::jsonb
           )
      into v_serie
      from pg_catalog.generate_series(
               p_desde::timestamp,
               p_hasta::timestamp,
               interval '1 day'
           ) d(dia)
      left join (
            select (coalesce(p.pagado_en, p.creado_en) at time zone 'America/Bogota')::date as fecha,
                   count(*) as pedidos,
                   coalesce(pg_catalog.sum(p.total_cop), 0) as ventas
              from public.pedidos p
             where p.estado in ('pagado', 'entregado')
               and coalesce(p.pagado_en, p.creado_en) >= v_inicio
               and coalesce(p.pagado_en, p.creado_en) < v_fin
             group by 1
      ) s on s.fecha = d.dia::date;

    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'nombre',   t.nombre_producto,
                       'unidades', t.unidades,
                       'ventas',   t.ventas
                   )
                   order by t.ventas desc, t.unidades desc, t.nombre_producto
               ),
               '[]'::jsonb
           )
      into v_top
      from (
            select d.nombre_producto,
                   pg_catalog.sum(d.cantidad)::bigint as unidades,
                   pg_catalog.sum(d.cantidad * d.precio_unitario_cop)::bigint as ventas
              from public.detalle_pedido d
              join public.pedidos p on p.id = d.pedido_id
             where p.estado in ('pagado', 'entregado')
               and coalesce(p.pagado_en, p.creado_en) >= v_inicio
               and coalesce(p.pagado_en, p.creado_en) < v_fin
             group by d.nombre_producto
             order by ventas desc, unidades desc, d.nombre_producto
             limit 5
      ) t;

    return pg_catalog.jsonb_build_object(
        'desde',          p_desde,
        'hasta',          p_hasta,
        'zona_horaria',   'America/Bogota',
        'total_ventas',   v_ventas,
        'total_pedidos',  v_pedidos,
        'ticket_promedio', v_promedio,
        'serie',          v_serie,
        'productos',      v_top
    );
end;
$function$;

revoke all on function public.reporte_ventas(date, date) from public, anon;
grant execute on function public.reporte_ventas(date, date) to authenticated;
