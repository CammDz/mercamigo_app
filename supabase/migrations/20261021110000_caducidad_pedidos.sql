-- =====================================================================
-- Mercamigo · 20261021110000_caducidad_pedidos.sql
--
-- Vigencia de 15 minutos para las ordenes PENDIENTES DE PAGO.
--
-- ---------------------------------------------------------------------
-- QUE HACE
--
--   1. Anade `pedidos.expira_en`: la fecha de expiracion, guardada de
--      forma persistente en la base de datos.
--   2. Al crear una orden pendiente de pago, el plazo se fija en
--      `creado_en + 15 minutos` (un BEFORE INSERT trigger, de modo que
--      **cualquier** via de alta respeta la regla).
--   3. El plazo **no se reinicia** al reintentar la creacion con la misma
--      clave de idempotencia (el reintento devuelve la orden existente, no
--      inserta otra fila), ni al reemitir o compartir el QR.
--   4. El token de recogida caduca **como maximo** con el pedido: se
--      cambia la vigencia de 24 horas a 15 minutos y se limita al plazo del
--      pedido.
--   5. `public.expirar_pedidos_vencidos()` marca como 'expirado' las
--      ordenes pendientes vencidas (respeta el protocolo de bloqueos).
--   6. Ninguna operacion sensible reembolsa una orden vencida: ni emitir
--      token, ni reemitirlo, ni recuperarla.
--   7. La respuesta del servidor incluye `expira_en`, para que la app
--      muestre la cuenta regresiva con el reloj del servidor.
--
-- ---------------------------------------------------------------------
-- QUE HACE CON LAS ORDENES QUE YA EXISTEN
--
--   · Solo se les pone plazo a las que siguen en 'pendiente_pago' y que
--     aun no tenian: `expira_en = creado_en + 15 minutos`.
--   · Las ordenes 'pagado', 'entregado' o 'cancelado' **no se tocan**:
--     quedan con `expira_en = null` (no caducan) y su estado no cambia.
--   · No se borra ninguna orden ni sus detalles: el historial se conserva.
--   · La orden pendiente que exista en el momento de aplicar esto puede
--     quedar 'expirado' en la primera pasada de
--     `expirar_pedidos_vencidos()`: es el comportamiento pedido (no hay
--     ordenes fantasma), y su historial sigue visible con estado
--     'Expirado'.
--
-- ---------------------------------------------------------------------
-- LIMPIEZA AUTOMATICA
--
--   Se usa `pg_cron` (disponible en Supabase) para pasar cada minuto:
--
--       select public.expirar_pedidos_vencidos();
--
--   Si `pg_cron` no se puede instalar o agendar en el proyecto, la
--   migracion lo avisa con un NOTICE y la caducidad **sigue siendo
--   efectiva** porque todas las operaciones sensibles comprueban `expira_en`
--   en el momento de ejecutarse (no dependen de que la tarea haya
--   pasado).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Columna de expiracion
-- ---------------------------------------------------------------------
alter table public.pedidos
    add column if not exists expira_en timestamptz;

comment on column public.pedidos.expira_en is
    'Fecha de expiracion de la orden pendiente de pago (creado_en + 15 minutos). NULL en ordenes pagadas, entregadas o canceladas.';

-- ---------------------------------------------------------------------
-- 2) Plazo de las ordenes pendientes que ya existen
--
--    Solo las 'pendiente_pago'. Las demas no se modifican.
-- ---------------------------------------------------------------------
update public.pedidos
   set expira_en = creado_en + interval '15 minutes'
 where estado = 'pendiente_pago'
   and expira_en is null;

-- ---------------------------------------------------------------------
-- 3) La expiracion, si existe, es posterior a la creacion
-- ---------------------------------------------------------------------
alter table public.pedidos
    drop constraint if exists pedidos_expira_en_check;
alter table public.pedidos
    add constraint pedidos_expira_en_check
    check (expira_en is null or expira_en > creado_en);

-- ---------------------------------------------------------------------
-- 4) Al crear la orden, el plazo se fija en 15 minutos
-- ---------------------------------------------------------------------
create or replace function public._asignar_caducidad_pedido()
returns trigger
language plpgsql
security invoker
set search_path to ''
as $function$
begin
    -- Solo las ordenes pendientes de pago caducan.
    if new.estado = 'pendiente_pago' and new.expira_en is null then
        new.expira_en := new.creado_en + interval '15 minutes';
    end if;
    return new;
end;
$function$;

drop trigger if exists pedidos_caducidad on public.pedidos;
create trigger pedidos_caducidad
    before insert on public.pedidos
    for each row
    execute function public._asignar_caducidad_pedido();

-- ---------------------------------------------------------------------
-- 5) Vigencia del token de recogida: 15 minutos
--
--    Antes eran 24 horas. Ahora el token no puede vivir mas que el pedido.
-- ---------------------------------------------------------------------
create or replace function public._ttl_token_recogida()
returns interval
language sql
stable
set search_path to ''
as $function$
    select interval '15 minutes'::interval;
$function$;

-- ---------------------------------------------------------------------
-- 6) Emitir el token: nunca para una orden vencida
--    y el token caduca como maximo con el pedido.
-- ---------------------------------------------------------------------
create or replace function public._emitir_token_recogida(p_pedido_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_token   text;
    v_expira  timestamptz;
    v_pedido  public.pedidos%rowtype;
begin
    -- Bloqueo de la fila del pedido (mismo orden que el resto de
    -- operaciones sobre la orden).
    select * into v_pedido
      from public.pedidos
     where id = p_pedido_id
     for update;

    if v_pedido.id is null then
        raise exception 'El pedido no existe.'
            using errcode = '22023';
    end if;

    if v_pedido.estado in ('entregado', 'cancelado', 'expirado') then
        raise exception 'El pedido ya no admite un codigo de recogida (estado: %).',
            v_pedido.estado
            using errcode = '22023';
    end if;

    -- although the state may not have been updated yet, the deadline is
    -- the authority: an expired order does not get a token.
    if v_pedido.expira_en is not null
       and v_pedido.expira_en <= pg_catalog.now() then
        raise exception 'El pedido ya caduco (plazo: %).', v_pedido.expira_en
            using errcode = '22023';
    end if;

    -- El token caduca con el pedido, nunca despues.
    v_expira := pg_catalog.now() + public._ttl_token_recogida();
    if v_pedido.expira_en is not null and v_pedido.expira_en < v_expira then
        v_expira := v_pedido.expira_en;
    end if;

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
$function$;

-- ---------------------------------------------------------------------
-- 7) Reemitir el token: no reactiva una orden vencida
--
--    Se conserva la firma (devuelve jsonb) y la respuesta existentes; solo
--    se anaden las comprobaciones de caducidad.
-- ---------------------------------------------------------------------
create or replace function public.reemitir_token_recogida(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

    -- El plazo es la autoridad: aunque el estado aun no se haya actualizado,
    -- una orden vencida no se reactiva.
    if v_pedido.expira_en is not null
       and v_pedido.expira_en <= pg_catalog.now() then
        raise exception 'El pedido ya caduco (plazo: %).', v_pedido.expira_en
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
        'expira_en',                v_pedido.expira_en,
        'token_recogida',           v_token,
        'requiere_reemision',       false,
        'token_anterior_invalido',  true
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- 8) Marcar como expiradas las ordenes pendientes vencidas
--
--    Idempotente y con el protocolo de bloqueos: `for update skip locked`
--    evita competir con una operacion que este en curso sobre la misma
--    orden.
-- ---------------------------------------------------------------------
create or replace function public.expirar_pedidos_vencidos()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_ordenes integer := 0;
    v_id      uuid;
begin
    for v_id in
        select p.id
          from public.pedidos p
         where p.estado = 'pendiente_pago'
           and p.expira_en is not null
           and p.expira_en <= pg_catalog.now()
           for update skip locked
    loop
        update public.pedidos
           set estado = 'expirado'
         where id = v_id
           and estado = 'pendiente_pago';

        if found then
            v_ordenes := v_ordenes + 1;
        end if;
    end loop;

    return v_ordenes;
end;
$function$;

-- ---------------------------------------------------------------------
-- 9) La respuesta incluye la fecha de expiracion
--    (la app la usa para la cuenta regresiva: el reloj es el del servidor).
-- ---------------------------------------------------------------------
create or replace function public._respuesta_pedido(
    p_pedido public.pedidos,
    p_nuevo  boolean,
    p_token  text
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
begin
    return pg_catalog.jsonb_build_object(
        'pedido_id',        p_pedido.id,
        'numero_orden',     p_pedido.numero_orden,
        'origen',           p_pedido.origen,
        'total_cop',        p_pedido.total_cop,
        'estado',           p_pedido.estado,
        'creado_en',        p_pedido.creado_en,
        'expira_en',        p_pedido.expira_en,
        'token_recogida',   p_token,
        'requiere_reemision', (p_token is null),
        'reutilizado',      (not p_nuevo),
        'items',            public._detalle_de_orden(p_pedido.id)
    );
end;
$function$;

-- ---------------------------------------------------------------------
-- 10) Limpieza periodica con pg_cron (opcional)
--
--     Si el proyecto no permite instalar o agendar pg_cron, la caducidad
--     sigue siendo efectiva porque todas las operaciones sensibles
--     comprueban `expira_en` en el momento de ejecutarse.
-- ---------------------------------------------------------------------
do $block$
begin
    begin
        create extension if not exists pg_cron with schema extensions;
    exception when others then
        raise notice 'No se pudo instalar pg_cron: %', sqlerrm;
    end;

    begin
        perform cron.unschedule('mercamigo_expirar_pedidos');
    exception when others then
        null;
    end;

    begin
        perform cron.schedule(
            'mercamigo_expirar_pedidos',
            '* * * * *',
            'select public.expirar_pedidos_vencidos();'
        );
        raise notice 'Tarea de caducidad programada cada minuto.';
    exception when others then
        raise notice 'No se pudo agendar la tarea periodica: %', sqlerrm;
    end;
end
$block$;

-- ---------------------------------------------------------------------
-- 11) Permisos
--
--     `expirar_pedidos_vencidos` la ejecuta el planificador (postgres) y,
--     si hace falta, un administrador desde la app. No se da acceso a
--     `anon` ni a `authenticated` para forzar la caducidad a mano.
-- ---------------------------------------------------------------------
revoke all on function public.expirar_pedidos_vencidos() from public, anon, authenticated;
grant execute on function public.expirar_pedidos_vencidos() to postgres, service_role;

revoke all on function public._asignar_caducidad_pedido() from public, anon, authenticated;
