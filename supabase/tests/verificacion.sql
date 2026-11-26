-- =====================================================================
-- Mercamigo · VERIFICACIÓN DE LAS MIGRACIONES (base de pruebas local)
--
-- ⚠ Este archivo es de PRUEBAS. No se aplica al proyecto remoto.
--
-- Cada comprobacion va en un bloque DO que afirma el resultado y escribe
-- un NOTICE con 'PASS' o aborta la ejecucion con un 'FALLO'.
--
--   1. Bootstrap del primer administrador (controlado, desde el servidor).
--   2. El cliente no puede llamar al bootstrap.
--   3. Un comprador no puede crear productos ni configurar la tienda.
--   4. Un comprador no puede autoasignarse el rol.
--   5. El administrador crea producto + codigo de forma atomica.
--   6. El administrador configura la tienda.
--   7. Creacion real de pedido y coherencia total == suma de detalles.
--   8. Token: hash de 64, caducidad del servidor, sin texto plano.
--   9. Reintento con la misma clave: mismo pedido, SIN token, sin rotar.
--  10. Reutilizacion de clave con otro contenido: rechazo.
--  11. Reemision explicita: el token anterior queda invalidado.
--  12. Un comprador no puede reemitir el token de otro.
--  13. Un comprador no ve los pedidos de otro (RLS).
--  14. Pedido entregado: no se reemite token.
--  15. Token revocado: no se reemite.
--  16. Producto desactivado: el reintento conserva los datos historicos.
--  17. El cliente solo consulta su propio rol.
--
-- Uso:  psql -U postgres -h 127.0.0.1 -p 5432 -d mercamigo_test -f verificacion.sql
-- =====================================================================

\set ON_ERROR_STOP on

\echo ''
\echo '===== 0. PREPARACION: usuarios de prueba ====='
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'comprador.a@ejemplo.com', '{"nombre":"Comprador A"}'),
  ('22222222-2222-4222-8222-222222222222', 'comprador.b@ejemplo.com', '{"nombre":"Comprador B"}'),
  ('33333333-3333-4333-8333-333333333333', 'dayroncamilo4+mercamigo@gmail.com', '{"nombre":"Administrador"}')
on conflict (id) do nothing;

select public.bootstrap_primer_administrador('dayroncamilo4+mercamigo@gmail.com')
       as admin_bootstrap;

\echo ''
\echo '===== 1. BOOTSTRAP: no asigna el rol si la cuenta no existe ====='
do $$
begin
    begin
        perform public.bootstrap_primer_administrador('no-existe@ejemplo.com');
    exception when others then
        raise notice 'PASS: bootstrap rechazado (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: el bootstrap deberia rechazar una cuenta inexistente';
end $$;

\echo ''
\echo '===== 2. PERMISOS: el cliente no puede llamar al bootstrap ====='
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
begin
    begin
        perform public.bootstrap_primer_administrador('22222222-2222-4222-8222-222222222222');
    exception when others then
        raise notice 'PASS: bootstrap no ejecutable por el cliente (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: un comprador pudo llamar al bootstrap';
end $$;

\echo ''
\echo '===== 3. ADMINISTRACION: un comprador NO puede crear producto ====='
do $$
begin
    begin
        perform public.crear_producto(
            (select id from public.categorias where nombre = 'Bebidas'),
            'Producto no autorizado', 1000, 'MERCA-TEST-NO');
    exception when others then
        raise notice 'PASS: crear_producto rechazado (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: un comprador pudo crear un producto';
end $$;

\echo ''
\echo '===== 4. ADMINISTRACION: un comprador NO puede configurar la tienda ====='
do $$
begin
    begin
        perform public.configurar_tienda(
            null, 'Tienda no autorizada', null, null, null, true);
    exception when others then
        raise notice 'PASS: configurar_tienda rechazado (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: un comprador pudo configurar la tienda';
end $$;

\echo ''
\echo '===== 5. ADMINISTRACION: un comprador NO puede asignarse el rol ====='
do $$
begin
    begin
        perform public.asignar_rol_administrador(
            '11111111-1111-4111-8111-111111111111', true);
    exception when others then
        raise notice 'PASS: autoasignacion de rol rechazada (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: un comprador pudo autoasignarse el rol';
end $$;

\echo ''
\echo '===== 6. ADMINISTRACION: el administrador SI puede crear producto + codigo ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_resultado jsonb;
    v_producto  uuid;
    v_codigos   integer;
begin
    v_resultado := public.crear_producto(
        (select id from public.categorias where nombre = 'Bebidas'),
        'Producto de prueba atomica', 1234, 'MERCA-TEST-001');

    v_producto := (v_resultado ->> 'producto_id')::uuid;

    select count(*) into v_codigos
      from public.codigos_producto
     where producto_id = v_producto and codigo = 'MERCA-TEST-001';

    if v_codigos <> 1 then
        raise exception 'FALLO: el codigo no se creo junto al producto';
    end if;

    if (select count(*) from public.productos where id = v_producto) <> 1 then
        raise exception 'FALLO: el producto no se creo';
    end if;

    raise notice 'PASS: producto % con codigo MERCA-TEST-001 creado de forma atomica',
        v_producto;
end $$;

\echo ''
\echo '===== 7. ADMINISTRACION: el administrador configura la tienda ====='
do $$
declare
    v_resultado jsonb;
begin
    v_resultado := public.configurar_tienda(
        null, 'Mercamigo Sede Test', 'Calle 100 # 20-30', 4.710989, -74.072092, true);
    raise notice 'PASS: tienda % creada', v_resultado ->> 'tienda_id';
end $$;

select nombre, direccion, latitud, longitud, activa from public.tiendas;

\echo ''
\echo '===== 8. PEDIDO REAL: un comprador crea una orden ====='
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_resultado jsonb;
    v_total    bigint;
    v_detalles bigint;
begin
    v_resultado := public.crear_pedido(
        (select id from public.tiendas where activa limit 1),
        'en_tienda',
        jsonb_build_array(
            jsonb_build_object('producto_id', '4b55cc13-9b24-4243-9245-bf0bd7a17be6', 'cantidad', 2),
            jsonb_build_object('producto_id', 'a1a7e190-bcc2-4057-b0cb-817d8818aea2', 'cantidad', 3)
        ),
        '44444444-4444-4444-8444-444444444444');

    if v_resultado ->> 'token_recogida' is null then
        raise exception 'FALLO: la creacion no devolvio token';
    end if;

    select total_cop into v_total
      from public.pedidos where id = (v_resultado ->> 'pedido_id')::uuid;
    select sum(subtotal_cop) into v_detalles
      from public.detalle_pedido where pedido_id = (v_resultado ->> 'pedido_id')::uuid;

    if v_total <> v_detalles then
        raise exception 'FALLO: total (%) != suma de detalles (%)', v_total, v_detalles;
    end if;

    if v_resultado ->> 'estado' <> 'pendiente_pago' then
        raise exception 'FALLO: el estado no es pendiente_pago';
    end if;

    raise notice 'PASS: pedido % numero % total % (= suma detalles %) token emitido',
        v_resultado ->> 'pedido_id',
        v_resultado ->> 'numero_orden',
        v_total, v_detalles;
end $$;

\echo ''
\echo '===== 9. COHERENCIA: total == suma de los detalles ====='
select
    (select total_cop from public.pedidos
      where usuario_id = '11111111-1111-4111-8111-111111111111') as total_pedido,
    (select sum(subtotal_cop) from public.detalle_pedido
      where pedido_id in (select id from public.pedidos
                          where usuario_id = '11111111-1111-4111-8111-111111111111')
    ) as suma_detalles,
    (select count(*) from public.pedidos
      where usuario_id = '11111111-1111-4111-8111-111111111111') as num_pedidos;

\echo ''
\echo '===== 10. TOKEN: hash de 64, caducidad del servidor, nunca en claro ====='
-- La tabla de tokens NO es legible por el cliente: la inspeccion se hace
-- como propietario del proyecto.
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select
    length(t.token_hash) as largo_hash,
    (t.expira_en - t.creado_en) as caducidad,
    (t.expira_en > now()) as vigente,
    (t.usado_en is null and t.revocado_en is null) as sin_usar
  from public.tokens_recogida t
  join public.pedidos p on p.id = t.pedido_id
 where p.usuario_id = '11111111-1111-4111-8111-111111111111';

do $$
begin
    if (select count(*) from public.tokens_recogida
         where length(token_hash) <> 64) <> 0 then
        raise exception 'FALLO: hay un token_hash que no mide 64 caracteres';
    end if;
    raise notice 'PASS: los tokens se guardan solo como hash SHA-256 (64 chars)';
end $$;

\echo ''
\echo '===== 11. REINTENTO: misma clave -> mismo pedido, SIN token, sin rotar ====='
do $$
declare
    v_hash_antes  text;
    v_hash_despues text;
    v_resultado   jsonb;
    v_pedido_id   uuid;
begin
    select t.token_hash into v_hash_antes
      from public.tokens_recogida t
      join public.pedidos p on p.id = t.pedido_id
     where p.usuario_id = '11111111-1111-4111-8111-111111111111';

    v_resultado := public.crear_pedido(
        (select id from public.tiendas where activa limit 1),
        'en_tienda',
        jsonb_build_array(
            jsonb_build_object('producto_id', '4b55cc13-9b24-4243-9245-bf0bd7a17be6', 'cantidad', 2),
            jsonb_build_object('producto_id', 'a1a7e190-bcc2-4057-b0cb-817d8818aea2', 'cantidad', 3)
        ),
        '44444444-4444-4444-8444-444444444444');

    v_pedido_id := (v_resultado ->> 'pedido_id')::uuid;

    if v_resultado ->> 'token_recogida' is not null then
        raise exception 'FALLO: el reintento devolvio un token (deberia pedir reemision)';
    end if;

    if (v_resultado ->> 'requiere_reemision')::boolean is not true then
        raise exception 'FALLO: el reintento no indica requiere_reemision';
    end if;

    select t.token_hash into v_hash_despues
      from public.tokens_recogida t where t.pedido_id = v_pedido_id;

    if v_hash_antes is distinct from v_hash_despues then
        raise exception 'FALLO: el reintento roto el token en silencio';
    end if;

    if (select count(*) from public.pedidos
         where usuario_id = '11111111-1111-4111-8111-111111111111') <> 1 then
        raise exception 'FALLO: el reintento creo un pedido duplicado';
    end if;

    raise notice 'PASS: reintento devuelve el mismo pedido %, sin token y sin rotar el hash',
        v_pedido_id;
end $$;

\echo ''
\echo '===== 12. IDEMPOTENCIA: misma clave con otro contenido -> rechazo ====='
do $$
begin
    begin
        perform public.crear_pedido(
            (select id from public.tiendas where activa limit 1),
            'en_tienda',
            jsonb_build_array(
                jsonb_build_object('producto_id', '4b55cc13-9b24-4243-9245-bf0bd7a17be6', 'cantidad', 9)
            ),
            '44444444-4444-4444-8444-444444444444');
    exception when others then
        raise notice 'PASS: clave reutilizada con otro contenido rechazada (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: se permitio reutilizar la clave con otro contenido';
end $$;

\echo ''
\echo '===== 13. REEMISION EXPLICITA: el token anterior queda invalidado ====='
do $$
declare
    v_hash_antes  text;
    v_hash_despues text;
    v_resultado   jsonb;
    v_pedido_id   uuid;
begin
    select id into v_pedido_id
      from public.pedidos
     where usuario_id = '11111111-1111-4111-8111-111111111111';

    select t.token_hash into v_hash_antes
      from public.tokens_recogida t where t.pedido_id = v_pedido_id;

    v_resultado := public.reemitir_token_recogida(v_pedido_id);

    if v_resultado ->> 'token_recogida' is null then
        raise exception 'FALLO: la reemision no devolvio token';
    end if;

    select t.token_hash into v_hash_despues
      from public.tokens_recogida t where t.pedido_id = v_pedido_id;

    if v_hash_antes is not distinct from v_hash_despues then
        raise exception 'FALLO: el token anterior no quedo invalidado';
    end if;

    if (select count(*) from public.tokens_recogida
         where pedido_id = v_pedido_id) <> 1 then
        raise exception 'FALLO: hay mas de una fila de token por pedido';
    end if;

    raise notice 'PASS: token reemitido, el hash anterior quedo invalidado';
end $$;

\echo ''
\echo '===== 14. AISLAMIENTO: un comprador NO puede reemitir el token de otro ====='
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
do $$
begin
    begin
        perform public.reemitir_token_recogida(
            (select id from public.pedidos
              where usuario_id = '11111111-1111-4111-8111-111111111111'));
    exception when others then
        raise notice 'PASS: reemision de pedido ajeno rechazada (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: un comprador pudo reemitir el token de otro';
end $$;

\echo ''
\echo '===== 15. AISLAMIENTO: un comprador NO ve los pedidos de otro (RLS) ====='
select count(*) as pedidos_visibles_por_B
  from public.pedidos
 where usuario_id = '11111111-1111-4111-8111-111111111111';

do $$
begin
    if (select count(*) from public.pedidos
         where usuario_id = '11111111-1111-4111-8111-111111111111') <> 0 then
        raise exception 'FALLO: el comprador B ve pedidos del comprador A';
    end if;
    raise notice 'PASS: RLS oculta los pedidos ajenos';
end $$;

\echo ''
\echo '===== 16. REGLAS: pedido entregado -> no se reemite token ====='
-- El cambio de estado lo hace el servidor: el cliente no puede escribirlo.
reset role;
update public.pedidos
   set estado = 'entregado'
 where usuario_id = '11111111-1111-4111-8111-111111111111';
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
begin
    begin
        perform public.reemitir_token_recogida(
            (select id from public.pedidos
              where usuario_id = '11111111-1111-4111-8111-111111111111'));
    exception when others then
        raise notice 'PASS: reemision en pedido entregado rechazada (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: se permitio reemitir el token de un pedido entregado';
end $$;

\echo ''
\echo '===== 17. REGLAS: token revocado -> no se reemite ====='
-- El revocado se hace como propietario: el cliente no puede tocar la tabla.
reset role;
update public.pedidos
   set estado = 'pendiente_pago'
 where usuario_id = '11111111-1111-4111-8111-111111111111';
update public.tokens_recogida
   set revocado_en = now()
 where pedido_id in (select id from public.pedidos
                      where usuario_id = '11111111-1111-4111-8111-111111111111');
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
begin
    begin
        perform public.reemitir_token_recogida(
            (select id from public.pedidos
              where usuario_id = '11111111-1111-4111-8111-111111111111'));
    exception when others then
        raise notice 'PASS: reemision de token revocado rechazada (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: se permitio reemitir un token revocado';
end $$;

\echo ''
\echo '===== 18. HISTORICO: producto desactivado -> el reintento conserva el pedido ====='
reset role;
update public.tokens_recogida
   set revocado_en = null
 where pedido_id in (select id from public.pedidos
                      where usuario_id = '11111111-1111-4111-8111-111111111111');
update public.productos
   set activo = false
 where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_resultado jsonb;
    v_total    bigint;
begin
    v_resultado := public.crear_pedido(
        (select id from public.tiendas where activa limit 1),
        'en_tienda',
        jsonb_build_array(
            jsonb_build_object('producto_id', '4b55cc13-9b24-4243-9245-bf0bd7a17be6', 'cantidad', 2),
            jsonb_build_object('producto_id', 'a1a7e190-bcc2-4057-b0cb-817d8818aea2', 'cantidad', 3)
        ),
        '44444444-4444-4444-8444-444444444444');

    select total_cop into v_total
      from public.pedidos
     where usuario_id = '11111111-1111-4111-8111-111111111111';

    if v_total <> 14000 then
        raise exception 'FALLO: el total historico cambio (%, %)', v_total, 14000;
    end if;

    raise notice 'PASS: el reintento devuelve el pedido historico (total %) sin exigir que el producto siga activo',
        v_total;
end $$;
reset role;
update public.productos set activo = true where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';

\echo ''
\echo '===== 19. ADMIN: el administrador VE los registros inactivos ====='
reset role;
update public.productos
   set activo = false
 where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
update public.categorias set activa = false where nombre = 'Despensa';
update public.tiendas set activa = false where nombre = 'Mercamigo Sede Test';

set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
select
    (select count(*) from public.productos
      where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6') as producto_inactivo_visible_admin,
    (select count(*) from public.categorias
      where nombre = 'Despensa') as categoria_inactiva_visible_admin,
    (select count(*) from public.tiendas
      where nombre = 'Mercamigo Sede Test') as tienda_inactiva_visible_admin;

do $$
begin
    if (select count(*) from public.productos
         where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6') <> 1
       or (select count(*) from public.categorias where nombre = 'Despensa') <> 1
       or (select count(*) from public.tiendas where nombre = 'Mercamigo Sede Test') <> 1 then
        raise exception 'FALLO: el administrador no ve los registros inactivos';
    end if;
    raise notice 'PASS: el administrador ve productos, categorias y tiendas inactivos';
end $$;

\echo ''
\echo '===== 20. AISLAMIENTO: el comprador NO ve los registros inactivos ====='
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select
    (select count(*) from public.productos
      where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6') as producto_inactivo_visible_comprador,
    (select count(*) from public.categorias
      where nombre = 'Despensa') as categoria_inactiva_visible_comprador,
    (select count(*) from public.tiendas
      where nombre = 'Mercamigo Sede Test') as tienda_inactiva_visible_comprador;

do $$
begin
    if (select count(*) from public.productos
         where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6') <> 0
       or (select count(*) from public.categorias where nombre = 'Despensa') <> 0
       or (select count(*) from public.tiendas where nombre = 'Mercamigo Sede Test') <> 0 then
        raise exception 'FALLO: un comprador ve registros inactivos';
    end if;
    raise notice 'PASS: RLS oculta al comprador los registros inactivos';
end $$;

reset role;
update public.productos set activo = true
 where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
update public.categorias set activa = true where nombre = 'Despensa';
update public.tiendas set activa = true where nombre = 'Mercamigo Sede Test';

\echo ''
\echo '===== 21. ADMIN: la escritura DIRECTA no esta permitida (solo RPC) ====='
set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_termino boolean := false;
begin
    -- INSERT directo sobre productos
    begin
        insert into public.productos (categoria_id, nombre, precio_cop, stock_demo)
        values ((select id from public.categorias where nombre = 'Bebidas'),
                'Inserto directo administrador', 100, 1);
        v_termino := true;
    exception when others then
        raise notice 'PASS: el administrador NO puede insertar directamente (%, %)', sqlstate, sqlerrm;
    end;
    if v_termino then
        raise exception 'FALLO: el administrador pudo insertar directamente';
    end if;

    -- UPDATE directo (cambio de precio)
    v_termino := false;
    begin
        update public.productos
           set precio_cop = 1
         where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
        v_termino := true;
    exception when others then
        raise notice 'PASS: el administrador NO puede cambiar precios directamente (%, %)', sqlstate, sqlerrm;
    end;
    if v_termino then
        raise exception 'FALLO: el administrador pudo cambiar un precio directamente';
    end if;

    -- UPDATE directo sobre una tienda
    v_termino := false;
    begin
        update public.tiendas set nombre = 'Tienda alterada'
         where nombre = 'Mercamigo Sede Test';
        v_termino := true;
    exception when others then
        raise notice 'PASS: el administrador NO puede editar tiendas directamente (%, %)', sqlstate, sqlerrm;
    end;
    if v_termino then
        raise exception 'FALLO: el administrador pudo editar la tienda directamente';
    end if;
end $$;

\echo ''
\echo '===== 22. AISLAMIENTO: un comprador tampoco puede escribir directamente ====='
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_termino boolean := false;
begin
    begin
        insert into public.productos (categoria_id, nombre, precio_cop, stock_demo)
        values ((select id from public.categorias where nombre = 'Bebidas'),
                'Inserto directo comprador', 100, 1);
        v_termino := true;
    exception when others then
        raise notice 'PASS: el comprador NO puede insertar directamente (%, %)', sqlstate, sqlerrm;
    end;
    if v_termino then
        raise exception 'FALLO: un comprador pudo insertar directamente';
    end if;

    v_termino := false;
    begin
        update public.productos set precio_cop = 1
         where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
        v_termino := true;
    exception when others then
        raise notice 'PASS: el comprador NO puede cambiar precios (%, %)', sqlstate, sqlerrm;
    end;
    if v_termino then
        raise exception 'FALLO: un comprador pudo cambiar un precio';
    end if;
end $$;

\echo ''
\echo '===== 23. CANTIDADES: todos los valores invalidos se rechazan ====='
-- Se ejecuta como propietario (con la sesion del comprador activa) para
-- poder comprobar que NO se crea ni el token. La validacion interna de
-- auth.uid() sigue aplicandose.
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_casos jsonb := '[
        {"nombre":"cantidad 0",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":0}]},
        {"nombre":"cantidad negativa",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":-3}]},
        {"nombre":"cantidad decimal",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":2.5}]},
        {"nombre":"cantidad nula",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":null}]},
        {"nombre":"cantidad no numerica",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":"abc"}]},
        {"nombre":"cantidad 101",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":101}]},
        {"nombre":"mismo producto 60 + 60",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":60},
                  {"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":60}]},
        {"nombre":"cantidad fuera del rango de integer",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":99999999999999999999}]},
        {"nombre":"cantidad con 11 digitos",
         "items":[{"producto_id":"4b55cc13-9b24-4243-9245-bf0bd7a17be6","cantidad":99999999999}]},
        {"nombre":"array de items vacio",
         "items":[]},
        {"nombre":"items ausente (null)",
         "items":null}
    ]';
    v_caso         jsonb;
    v_items        jsonb;
    v_error        text;
    v_estado       text;
    v_antes_pedidos  integer;
    v_antes_detalles integer;
    v_antes_tokens   integer;
begin
    for v_caso in select * from pg_catalog.jsonb_array_elements(v_casos) loop
        v_items := v_caso -> 'items';
        v_error := null;
        v_estado := null;

        select count(*) into v_antes_pedidos  from public.pedidos;
        select count(*) into v_antes_detalles from public.detalle_pedido;
        select count(*) into v_antes_tokens   from public.tokens_recogida;

        begin
            perform public.crear_pedido(
                (select id from public.tiendas where activa limit 1),
                'en_tienda',
                v_items,
                gen_random_uuid()
            );
        exception when others then
            v_error := sqlerrm;
            v_estado := sqlstate;
        end;

        if v_error is null then
            raise exception 'FALLO: el caso % NO fue rechazado', v_caso ->> 'nombre';
        end if;

        if (select count(*) from public.pedidos) <> v_antes_pedidos
           or (select count(*) from public.detalle_pedido) <> v_antes_detalles
           or (select count(*) from public.tokens_recogida) <> v_antes_tokens then
            raise exception 'FALLO: el caso % creo pedido, detalles o token',
                v_caso ->> 'nombre';
        end if;

        raise notice 'PASS: % rechazado sin crear registros (%, %)',
            v_caso ->> 'nombre', v_estado, left(v_error, 55);
    end loop;
end $$;

\echo ''
\echo '===== 23b. CANTIDADES: limite de 50 items por pedido ====='
do $$
declare
    v_items        jsonb := '[]'::jsonb;
    v_i            integer;
    v_termino      boolean := false;
    v_antes_pedidos integer;
begin
    for v_i in 1..51 loop
        v_items := v_items || jsonb_build_array(
            jsonb_build_object(
                'producto_id', '4b55cc13-9b24-4243-9245-bf0bd7a17be6',
                'cantidad', 1));
    end loop;

    select count(*) into v_antes_pedidos from public.pedidos;

    begin
        perform public.crear_pedido(
            (select id from public.tiendas where activa limit 1),
            'en_tienda',
            v_items,
            gen_random_uuid()
        );
        v_termino := true;
    exception when others then
        raise notice 'PASS: 51 items rechazado (%, %)', sqlstate, left(sqlerrm, 60);
    end;

    if v_termino then
        raise exception 'FALLO: se aceptaron 51 items';
    end if;

    if (select count(*) from public.pedidos) <> v_antes_pedidos then
        raise exception 'FALLO: 51 items creo un pedido';
    end if;
end $$;

\echo ''
\echo '===== 24. CANTIDADES: 100 unidades si son validas ====='
do $$declare
    v_clave uuid := gen_random_uuid();
    v_cant  integer;
begin
    perform public.crear_pedido(
        (select id from public.tiendas where activa limit 1),
        'en_tienda',
        jsonb_build_array(
            jsonb_build_object('producto_id','4b55cc13-9b24-4243-9245-bf0bd7a17be6','cantidad',100)
        ),
        v_clave
    );

    select d.cantidad into v_cant
      from public.detalle_pedido d
      join public.pedidos p on p.id = d.pedido_id
     where p.clave_idempotencia = v_clave;

    if v_cant <> 100 then
        raise exception 'FALLO: la cantidad guardada no es 100 (%)', v_cant;
    end if;

    raise notice 'PASS: 100 unidades se aceptan y se guardan (subtotal %)',
        (select subtotal_cop from public.detalle_pedido d
           join public.pedidos p on p.id = d.pedido_id
          where p.clave_idempotencia = v_clave);
end $$;

\echo ''
\echo '===== 25. ROL: el cliente solo consulta su propio rol ====='
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select public.es_administrador() as soy_admin_actual;
do $$
begin
    begin
        perform public.es_administrador_de('22222222-2222-4222-8222-222222222222');
    exception when others then
        raise notice 'PASS: es_administrador_de no es ejecutable por el cliente (%, %)', sqlstate, sqlerrm;
        return;
    end;
    raise exception 'FALLO: el cliente pudo consultar el rol de otro UUID';
end $$;

do $$
begin
    if public.es_administrador() then
        raise exception 'FALLO: un comprador se ha visto como administrador';
    end if;
    raise notice 'PASS: es_administrador() solo responde por el usuario de la sesion';
end $$;

reset role;

\echo ''
\echo '===== 26. RESUMEN FINAL ====='
reset role;
update public.productos set precio_cop = 2500
 where id = '4b55cc13-9b24-4243-9245-bf0bd7a17be6';
select
    (select count(*) from public.categorias)       as categorias,
    (select count(*) from public.productos)        as productos,
    (select count(*) from public.codigos_producto)  as codigos,
    (select count(*) from public.tiendas)          as tiendas,
    (select count(*) from public.pedidos)           as pedidos,
    (select count(*) from public.detalle_pedido)    as detalles,
    (select count(*) from public.tokens_recogida)   as tokens,
    (select count(*) from public.perfiles)          as perfiles,
    (select count(*) from public.roles_usuario)     as roles;

\echo ''
\echo '===== FIN DE LA VERIFICACION ====='
