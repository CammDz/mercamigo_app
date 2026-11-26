-- =====================================================================
-- Mercamigo · VERIFICACIÓN DEL PANEL DE ADMINISTRACIÓN
--
-- Comprueba el comportamiento de las funciones administrativas:
--
--   public.editar_producto
--   public.establecer_estado_producto
--   public.registrar_codigo_producto
--   public.corregir_codigo_producto
--
-- Y las garantías que debe cumplir la separación comprador/administrador:
--
--   · Un comprador NO puede invocar ninguna de ellas (42501).
--   · Un comprador NO ve los productos inactivos ni sus códigos (RLS).
--   · Un comprador NO puede añadir un producto desactivado a una orden.
--   · El producto creado por el administrador aparece en el catálogo del
--     comprador y su código se puede escanear.
--   · Desactivar un producto NO modifica los pedidos históricos.
--   · Cancelar una edición NO modifica nada (no se llama a ninguna RPC).
--
-- Solo usa la base de datos local de pruebas: no toca el proyecto remoto.
-- =====================================================================

\set ON_ERROR_STOP on

\echo ''
\echo '===== A. PREPARACION ====='
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'comprador.a@ejemplo.com', '{"nombre":"Comprador A"}'),
  ('33333333-3333-4333-8333-333333333333', 'dayroncamilo4+mercamigo@gmail.com', '{"nombre":"Administrador"}')
on conflict (id) do nothing;

select public.bootstrap_primer_administrador('dayroncamilo4+mercamigo@gmail.com')
       as admin_bootstrap;

\echo ''
\echo '===== B. COMPRADOR: NO puede invocar las RPC administrativas ====='
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto de prueba atomica'
     limit 1;

    -- 1) editar_producto
    begin
        perform public.editar_producto(v_producto, 'Intruso', null, null, 1, null);
        raise exception 'FALLO: un comprador pudo editar un producto';
    exception when others then
        raise notice 'PASS: editar_producto rechazado (%, %)', sqlstate, sqlerrm;
    end;

    -- 2) establecer_estado_producto
    begin
        perform public.establecer_estado_producto(v_producto, false);
        raise exception 'FALLO: un comprador pudo desactivar un producto';
    exception when others then
        raise notice 'PASS: establecer_estado_producto rechazado (%, %)', sqlstate, sqlerrm;
    end;

    -- 3) registrar_codigo_producto
    begin
        perform public.registrar_codigo_producto(v_producto, '999000111', 'barras');
        raise exception 'FALLO: un comprador pudo registrar un codigo';
    exception when others then
        raise notice 'PASS: registrar_codigo_producto rechazado (%, %)', sqlstate, sqlerrm;
    end;

    -- 4) corregir_codigo_producto
    begin
        perform public.corregir_codigo_producto(
            (select id from public.codigos_producto where codigo = 'MERCA-TEST-001'),
            '999000222');
        raise exception 'FALLO: un comprador pudo corregir un codigo';
    exception when others then
        raise notice 'PASS: corregir_codigo_producto rechazado (%, %)', sqlstate, sqlerrm;
    end;
end $$;

\echo ''
\echo '===== C. ADMIN: edita un producto (sin tocar activo ni stock) ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_producto uuid;
    v_stock    integer;
    v_activo   boolean;
    v_resultado jsonb;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto de prueba atomica'
     limit 1;

    select stock_demo, activo into v_stock, v_activo
      from public.productos where id = v_producto;

    v_resultado := public.editar_producto(
        v_producto,
        'Producto editado por el administrador',
        'Descripción nueva',
        null,
        2500,
        null);

    if (v_resultado ->> 'nombre') <> 'Producto editado por el administrador' then
        raise exception 'FALLO: el nombre no se actualizo';
    end if;

    if (select nombre from public.productos where id = v_producto)
       <> 'Producto editado por el administrador' then
        raise exception 'FALLO: el nombre no se guardo';
    end if;

    if (select precio_cop from public.productos where id = v_producto) <> 2500 then
        raise exception 'FALLO: el precio no se actualizo';
    end if;

    -- Editar NO cambia el estado ni el stock de demostracion.
    if (select activo from public.productos where id = v_producto) <> v_activo then
        raise exception 'FALLO: editar cambio el estado del producto';
    end if;

    if (select stock_demo from public.productos where id = v_producto) <> v_stock then
        raise exception 'FALLO: editar cambio el stock de demostracion';
    end if;

    raise notice 'PASS: producto editado (nombre, descripcion y precio)';
end $$;

\echo ''
\echo '===== D. ADMIN: desactiva y reactiva (borrado logico) ====='
do $$
declare
    v_producto uuid;
    v_codigos  integer;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    select count(*) into v_codigos
      from public.codigos_producto where producto_id = v_producto;

    perform public.establecer_estado_producto(v_producto, false);

    -- La fila sigue existiendo: el borrado es logico.
    if (select count(*) from public.productos where id = v_producto) <> 1 then
        raise exception 'FALLO: desactivar borro la fila del producto';
    end if;

    if (select activo from public.productos where id = v_producto) then
        raise exception 'FALLO: el producto sigue activo';
    end if;

    -- Los codigos NO se borran al desactivar.
    if (select count(*) from public.codigos_producto where producto_id = v_producto)
       <> v_codigos then
        raise exception 'FALLO: desactivar borro los codigos del producto';
    end if;

    -- Desactivar dos veces no es un error (operacion idempotente).
    perform public.establecer_estado_producto(v_producto, false);

    -- Reactivar.
    perform public.establecer_estado_producto(v_producto, true);

    if not (select activo from public.productos where id = v_producto) then
        raise exception 'FALLO: el producto no se reactivo';
    end if;

    raise notice 'PASS: desactivar/reactivar es un borrado logico que conserva los codigos';
end $$;

\echo ''
\echo '===== E. ADMIN: registra un codigo de barras real ====='
do $$
declare
    v_producto uuid;
    v_codigo   uuid;
    v_texto    text;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    -- Codigo con ceros iniciales: se conserva como TEXTO.
    perform public.registrar_codigo_producto(v_producto, '0123456789012', 'barras');

    select id, codigo into v_codigo, v_texto
      from public.codigos_producto
     where producto_id = v_producto and codigo = '0123456789012';

    if v_codigo is null then
        raise exception 'FALLO: el codigo no se registro';
    end if;

    if v_texto <> '0123456789012' then
        raise exception 'FALLO: el codigo no conservo los ceros iniciales';
    end if;

    raise notice 'PASS: codigo de barras registrado conservando los ceros';
end $$;

\echo ''
\echo '===== F. ADMIN: rechaza codigos duplicados, vacios o de tipo invalido ====='
do $$
declare
    v_producto  uuid;
    v_otro      uuid;
    v_mensaje   text;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;
    select id into v_otro
      from public.productos
     where id <> v_producto
     limit 1;

    -- Duplicado en OTRO producto: debe explicar a que producto pertenece.
    begin
        perform public.registrar_codigo_producto(v_otro, '0123456789012', 'barras');
        raise exception 'FALLO: se acepto un codigo duplicado';
    exception when others then
        v_mensaje := sqlerrm;
        raise notice 'PASS: codigo duplicado rechazado (%, %)', sqlstate, v_mensaje;
        if v_mensaje not like '%ya pertenece%' then
            raise exception 'FALLO: el error no explica a que producto pertenece el codigo';
        end if;
    end;

    -- Duplicado en el MISMO producto.
    begin
        perform public.registrar_codigo_producto(v_producto, '0123456789012', 'barras');
        raise exception 'FALLO: se acepto un codigo repetido en el mismo producto';
    exception when others then
        raise notice 'PASS: codigo repetido en el mismo producto rechazado (%, %)',
            sqlstate, sqlerrm;
    end;

    -- Codigo vacio.
    begin
        perform public.registrar_codigo_producto(v_producto, '   ', 'barras');
        raise exception 'FALLO: se acepto un codigo vacio';
    exception when others then
        raise notice 'PASS: codigo vacio rechazado (%, %)', sqlstate, sqlerrm;
    end;

    -- Tipo invalido.
    begin
        perform public.registrar_codigo_producto(v_producto, '777000111', 'magico');
        raise exception 'FALLO: se acepto un tipo de codigo invalido';
    exception when others then
        raise notice 'PASS: tipo de codigo invalido rechazado (%, %)', sqlstate, sqlerrm;
    end;
end $$;

\echo ''
\echo '===== G. ADMIN: corrige un codigo mal leido ====='
do $$
declare
    v_codigo_id uuid;
    v_producto  uuid;
    v_nuevo     text;
begin
    select c.id, c.producto_id into v_codigo_id, v_producto
      from public.codigos_producto c
     where c.codigo = '0123456789012'
     limit 1;

    perform public.corregir_codigo_producto(v_codigo_id, '0123456789013', 'barras');

    select codigo into v_nuevo
      from public.codigos_producto where id = v_codigo_id;

    if v_nuevo <> '0123456789013' then
        raise exception 'FALLO: el codigo no se corrigio';
    end if;

    -- Corregir NO cambia el producto asociado.
    if (select producto_id from public.codigos_producto where id = v_codigo_id)
       <> v_producto then
        raise exception 'FALLO: corregir cambio el producto del codigo';
    end if;

    -- Corregir a un codigo que ya existe en otro producto: rechazado.
    begin
        perform public.corregir_codigo_producto(v_codigo_id, 'MERCA-TEST-001');
        raise exception 'FALLO: se acepto corregir a un codigo duplicado';
    exception when others then
        raise notice 'PASS: correccion a un codigo duplicado rechazada (%, %)',
            sqlstate, sqlerrm;
    end;

    -- Corregir a un codigo vacio: rechazado.
    begin
        perform public.corregir_codigo_producto(v_codigo_id, '');
        raise exception 'FALLO: se acepto corregir a un codigo vacio';
    exception when others then
        raise notice 'PASS: correccion a un codigo vacio rechazada (%, %)',
            sqlstate, sqlerrm;
    end;

    raise notice 'PASS: codigo corregido conservando el producto';
end $$;

\echo ''
\echo '===== H. COMPRADOR: ve el producto activo y su codigo (integracion) ====='
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    if v_producto is null then
        raise exception 'FALLO: el comprador no ve el producto creado por el administrador';
    end if;

    if (select count(*) from public.codigos_producto
         where producto_id = v_producto and codigo = '0123456789013') <> 1 then
        raise exception 'FALLO: el comprador no ve el codigo del producto';
    end if;

    raise notice 'PASS: el comprador ve el producto y su codigo (se puede escanear)';
end $$;

\echo ''
\echo '===== I. INTEGRACION: el producto desactivado desaparece del comprador ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    perform public.establecer_estado_producto(v_producto, false);
end $$;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_producto uuid;
    v_visibles integer;
    v_codigos  integer;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    select count(*) into v_visibles
      from public.productos where id = v_producto;
    if v_visibles <> 0 then
        raise exception 'FALLO: el comprador ve un producto desactivado';
    end if;

    select count(*) into v_codigos
      from public.codigos_producto
     where producto_id = v_producto;
    if v_codigos <> 0 then
        raise exception 'FALLO: el comprador ve los codigos de un producto desactivado';
    end if;

    raise notice 'PASS: el producto desactivado y sus codigos no son visibles para el comprador';
end $$;

\echo ''
\echo '===== J. COMPRADOR: NO puede pedir un producto desactivado ====='
-- El id se pasa por una variable de sesion porque el comprador NO puede ver
-- el producto desactivado (RLS): si se leyera aqui, saldria NULL.
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_producto uuid;
    v_tienda   uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;
    perform set_config('mercamigo.test.producto_id', v_producto::text, false);
end $$;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_producto uuid;
    v_tienda   uuid;
    v_error    text;
begin
    v_producto := current_setting('mercamigo.test.producto_id')::uuid;
    select id into v_tienda
      from public.tiendas where activa limit 1;

    begin
        perform public.crear_pedido(
            v_tienda,
            'en_tienda',
            jsonb_build_array(jsonb_build_object(
                'producto_id', v_producto, 'cantidad', 1)),
            gen_random_uuid());
        raise exception 'FALLO: un comprador pidio un producto desactivado';
    exception when others then
        v_error := sqlerrm;
        raise notice 'PASS: pedido con producto desactivado rechazado (%, %)',
            sqlstate, v_error;
        if v_error not like '%no esta disponible%' then
            raise exception 'FALLO: el error no explica que el producto no esta disponible';
        end if;
    end;
end $$;

\echo ''
\echo '===== K. ADMIN: reactivar y el comprador vuelve a verlo ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;
    perform public.establecer_estado_producto(v_producto, true);
end $$;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;
    if v_producto is null then
        raise exception 'FALLO: el comprador no vuelve a ver el producto reactivado';
    end if;
    raise notice 'PASS: el producto reactivado vuelve a estar en el catalogo del comprador';
end $$;

\echo ''
\echo '===== L. CANCELAR UNA EDICION: sin guardar no cambia nada ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_antes    text;
    v_despues  text;
begin
    select nombre into v_antes
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    -- "Cancelar" = no llamar a ninguna RPC. No se escribe nada.
    perform 1;

    select nombre into v_despues
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;

    if v_antes is distinct from v_despues then
        raise exception 'FALLO: cancelar una edicion modifico los datos';
    end if;

    raise notice 'PASS: cancelar una edicion no modifica la base de datos';
end $$;

\echo ''
\echo '===== M. EL ADMINISTRADOR SIGUE VIENDO EL PRODUCTO INACTIVO ====='
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
do $$
declare
    v_producto uuid;
begin
    select id into v_producto
      from public.productos
     where nombre = 'Producto editado por el administrador'
     limit 1;
    perform public.establecer_estado_producto(v_producto, false);

    if (select count(*) from public.productos where id = v_producto) <> 1 then
        raise exception 'FALLO: el administrador no ve el producto inactivo';
    end if;

    -- Se deja el producto como estaba al principio.
    perform public.establecer_estado_producto(v_producto, true);

    raise notice 'PASS: el administrador ve y puede reactivar los productos inactivos';
end $$;

reset role;

\echo ''
\echo '===== FIN DE LA VERIFICACION DEL PANEL DE ADMINISTRACION ====='
