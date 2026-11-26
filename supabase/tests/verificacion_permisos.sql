-- =====================================================================
-- Mercamigo · VERIFICACIÓN DE PERMISOS EFECTIVOS (base local o remota)
--
-- ⚠ Esta comprobación se ejecuta DESPUÉS de aplicar
--   20261021004000_endurecer_permisos.sql.
--
-- No se limita a listar las concesiones: comprueba lo que el rol puede
-- hacer de verdad (has_table_privilege / has_function_privilege y
-- operaciones reales con el rol authenticated).
--
-- No crea cuentas, tiendas ni pedidos.
-- =====================================================================

\set ON_ERROR_STOP on

\echo ''
\echo '===== 1. MATRIZ DE PRIVILEGIOS EFECTIVOS (has_table_privilege) ====='
select t.tabla,
       r.rol,
       p.privilegio,
       has_table_privilege(r.rol, t.tabla, p.privilegio) as permitido
  from (values ('public.categorias'), ('public.codigos_producto'),
               ('public.detalle_pedido'), ('public.pedidos'),
               ('public.productos'), ('public.tiendas'),
               ('public.tokens_recogida'), ('public.perfiles'),
               ('public.roles_usuario')) as t(tabla)
 cross join (values ('anon'), ('authenticated')) as r(rol)
 cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(privilegio)
 order by t.tabla, r.rol, p.privilegio;

\echo ''
\echo '===== 2. MATRIZ DE EJECUCION DE FUNCIONES (has_function_privilege) ====='
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funcion,
       r.rol,
       has_function_privilege(r.rol, p.oid, 'EXECUTE') as puede_ejecutar
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 cross join (values ('anon'), ('authenticated')) as r(rol)
 where n.nspname = 'public'
 order by p.proname, r.rol;

\echo ''
\echo '===== 3. OPERACIONES REALES CON EL ROL authenticated ====='
-- Todas las sondas de esta seccion van dentro de UNA transaccion que se
-- revierte al final: aunque un privilegio estuviera mal, ningun INSERT,
-- UPDATE ni TRUNCATE podria dejar rastro.
begin;

-- Como el usuario no tiene sesion, se comprueba el permiso (no la RLS de
-- fila): lo que importa aqui es que el permiso exista o no.
set role authenticated;

do $$
declare
    v_ok boolean;
begin
    -- 3.1 Lectura del catalogo: permitida.
    v_ok := true;
    begin
        perform 1 from public.productos limit 1;
    exception when others then
        v_ok := false;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated no puede leer el catalogo';
    end if;
    raise notice 'PASS: authenticated puede leer el catalogo';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.2 Lectura de pedidos propios: permitida.
    v_ok := true;
    begin
        perform 1 from public.pedidos limit 1;
    exception when others then
        v_ok := false;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated no puede leer sus pedidos';
    end if;
    raise notice 'PASS: authenticated puede leer pedidos';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.3 Actualizacion del perfil propio: permitida (0 filas, sin error).
    v_ok := true;
    begin
        update public.perfiles set nombre = nombre where id = gen_random_uuid();
    exception when others then
        v_ok := false;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated no puede actualizar su perfil';
    end if;
    raise notice 'PASS: authenticated puede actualizar su perfil';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.4 Insercion en perfiles: DENEGADA (solo hay UPDATE).
    v_ok := false;
    begin
        insert into public.perfiles (id, nombre) values (gen_random_uuid(), 'x');
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede insertar en perfiles';
    end if;
    raise notice 'PASS: la insercion en perfiles esta denegada';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.5 TRUNCATE sobre las tablas con el exceso: DENEGADO.
    v_ok := false;
    begin
        truncate table public.perfiles;
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede TRUNCATE perfiles';
    end if;

    v_ok := false;
    begin
        truncate table public.roles_usuario;
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede TRUNCATE roles_usuario';
    end if;
    raise notice 'PASS: TRUNCATE denegado sobre perfiles y roles_usuario';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.6 Escritura directa en el catalogo: DENEGADA.
    v_ok := false;
    begin
        insert into public.productos (categoria_id, nombre, precio_cop, stock_demo)
        values ((select id from public.categorias limit 1), 'x', 1, 1);
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede insertar en productos';
    end if;

    v_ok := false;
    begin
        update public.productos set precio_cop = precio_cop
         where id = gen_random_uuid();
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede actualizar productos';
    end if;
    raise notice 'PASS: la escritura directa en el catalogo esta denegada';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.7 Lectura de tokens_recogida: DENEGADA.
    v_ok := false;
    begin
        perform 1 from public.tokens_recogida limit 1;
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede leer tokens_recogida';
    end if;
    raise notice 'PASS: la lectura de tokens_recogida esta denegada';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.8 Funciones reservadas al propietario: DENEGADAS.
    v_ok := false;
    begin
        perform public.bootstrap_primer_administrador('nadie@ejemplo.com');
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede llamar al bootstrap';
    end if;

    v_ok := false;
    begin
        perform public.es_administrador_de(gen_random_uuid());
    exception when others then
        v_ok := true;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated puede consultar el rol de otro UUID';
    end if;
    raise notice 'PASS: las funciones reservadas al propietario estan denegadas';
end $$;

do $$
declare
    v_ok boolean;
begin
    -- 3.9 RPC autorizadas: permitidas.
    v_ok := true;
    begin
        perform public.es_administrador();
    exception when others then
        v_ok := false;
    end;
    if not v_ok then
        raise exception 'FALLO: authenticated no puede llamar a es_administrador';
    end if;
    raise notice 'PASS: las RPC autorizadas siguen siendo ejecutables';
end $$;

reset role;

rollback;

\echo ''
\echo '===== 4. EL DISPARADOR DE EVENTO SIGUE FUNCIONANDO ====='
-- Se crea una tabla dentro de una transaccion que se deshace: la tabla
-- no llega a existir, pero el disparador de evento se ha ejecutado.
begin;
create table public._prueba_trigger_rls (id uuid primary key default gen_random_uuid());
select relname, relrowsecurity as rls_activada
  from pg_class where relname = '_prueba_trigger_rls';
do $$
begin
    if (select relrowsecurity from pg_class
         where relname = '_prueba_trigger_rls') is not true then
        raise exception 'FALLO: el disparador rls_auto_enable dejo de activar RLS';
    end if;
    raise notice 'PASS: rls_auto_enable sigue habilitando RLS en las tablas nuevas';
end $$;
rollback;

\echo ''
\echo '===== 5. ESTADO FINAL (sin datos de prueba) ====='
select
    (select count(*) from public.categorias)      as categorias,
    (select count(*) from public.productos)       as productos,
    (select count(*) from public.codigos_producto) as codigos,
    (select count(*) from public.tiendas)         as tiendas,
    (select count(*) from public.pedidos)         as pedidos,
    (select count(*) from public.perfiles)        as perfiles,
    (select count(*) from public.roles_usuario)   as roles,
    (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname='public' and c.relname='_prueba_trigger_rls') as tabla_de_prueba_residuo;

\echo ''
\echo '===== FIN DE LA VERIFICACION DE PERMISOS ====='
