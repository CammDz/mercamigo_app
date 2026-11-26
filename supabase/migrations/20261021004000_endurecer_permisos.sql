-- =====================================================================
-- Mercamigo · 20261021004000_endurecer_permisos.sql
--
-- Endurecimiento de permisos de la aplicacion.
--
-- NO recrea ninguna tabla, NO borra datos, NO toca tablas ajenas a
-- Mercamigo ni los permisos internos de Supabase (esquemas `auth`,
-- `extensions`, `vault`, ...). Solo modifica el ACL de los objetos
-- publicos de este proyecto.
--
-- ---------------------------------------------------------------------
-- HALLAZGO (auditoria previa de las 9 tablas publicas)
--
--   tabla               | anon                | authenticated                       | exceso
--   --------------------+---------------------+-------------------------------------+------------------
--   categorias         | SELECT              | SELECT                              | ninguno
--   codigos_producto   | SELECT              | SELECT                              | ninguno
--   detalle_pedido     | -                   | SELECT                              | ninguno
--   pedidos            | -                   | SELECT                              | ninguno
--   productos          | SELECT              | SELECT                              | ninguno
--   tiendas            | SELECT              | SELECT                              | ninguno
--   tokens_recogida    | -                   | -                                   | ninguno
--   perfiles           | MAINTAIN, REFERENCES, TRIGGER, TRUNCATE | MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE | MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
--   roles_usuario      | MAINTAIN, REFERENCES, TRIGGER, TRUNCATE | MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE | MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
--
--   Las dos ultimas tablas (perfiles y roles_usuario) se crearon en la
--   migracion 20261021002000 y heredaron los permisos por defecto que
--   Supabase concede a `anon` y `authenticated` para las tablas creadas
--   por el propietario del proyecto. Ninguna de las siete tablas
--   originales arrastra esos permisos sobrantes.
--
--   Nota: `MAINTAIN` (PostgreSQL 17) es del mismo tipo de privilegio
--   administrativo que TRUNCATE y no pasa por RLS, asi que se revoca
--   tambien. `TRUNCATE` tampoco pasa por RLS: con el privilegio, un
--   cliente podria vaciar la tabla saltandose la RLS por completo.
--
--   `service_role` conserva sus permisos habituales (SELECT y privilegios
--   de mantenimiento): es el rol de administracion de la plataforma y no
--   se toca. `postgres` (propietario) conserva los suyos.
--
-- ---------------------------------------------------------------------
-- FUNCIONES
--
--   public.rls_auto_enable() es un disparador de evento del SERVIDOR
--   (RETURNS event_trigger) que habilita RLS automaticamente en las
--   tablas nuevas del esquema public. Tenia `proacl = NULL`, es decir,
--   el permiso EXECUTE por defecto de PUBLIC: el cliente podia invocarla
--   por RPC. Se le revoca EXECUTE.
--
--   Esto NO afecta a su funcionamiento: los disparadores (normales y de
--   evento) los invoca el servidor y PostgreSQL NO comprueba el permiso
--   EXECUTE sobre la funcion del disparador. Se verifica despues de
--   aplicar, creando una tabla de prueba dentro de una transaccion que
--   se deshace.
--
--   Las demas funciones del proyecto conservan EXECUTE solo para
--   `authenticated` (las RPC del cliente) o solo para el propietario
--   (las internas y el bootstrap del administrador).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Privilegios sobrantes sobre las tablas del proyecto.
--
--    Se revoca en las nueve tablas publicas: en las siete originales es
--    una operacion sin efecto (no tienen esos privilegios) y deja el
--    estado explicito y documentado.
-- ---------------------------------------------------------------------
revoke all     on table public.categorias       from public, anon, authenticated;
revoke all     on table public.codigos_producto from public, anon, authenticated;
revoke all     on table public.detalle_pedido   from public, anon, authenticated;
revoke all     on table public.pedidos          from public, anon, authenticated;
revoke all     on table public.productos        from public, anon, authenticated;
revoke all     on table public.tiendas          from public, anon, authenticated;
revoke all     on table public.tokens_recogida   from public, anon, authenticated;
revoke all     on table public.perfiles         from public, anon, authenticated;
revoke all     on table public.roles_usuario    from public, anon, authenticated;

-- Se conceden de nuevo SOLO los permisos legitimos, para que el estado
-- final sea explicito y la migracion sea idempotente.
--   · Lectura del catalogo: anon y authenticated.
grant select on table public.categorias       to anon, authenticated;
grant select on table public.codigos_producto to anon, authenticated;
grant select on table public.productos        to anon, authenticated;
grant select on table public.tiendas          to anon, authenticated;

--   · Lectura de los pedidos propios: authenticated (la RLS ya limita
--     cada comprador a los suyos).
grant select on table public.pedidos          to authenticated;
grant select on table public.detalle_pedido   to authenticated;

--   · Perfil propio: lectura y actualizacion (la politica
--     perfiles_actualizacion limita la escritura a la propia fila).
grant select on table public.perfiles          to authenticated;
grant update on table public.perfiles          to authenticated;

--   · Consulta del propio rol.
grant select on table public.roles_usuario     to authenticated;

--   · tokens_recogida: sin permisos para el cliente (solo el
--     propietario y service_role). El token nunca se expone al cliente.
revoke all on table public.tokens_recogida from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 2) Disparador de evento del servidor: sin EXECUTE para el cliente.
--
--    Sigue funcionando como disparador de evento (el servidor lo invoca
--    sin comprobar permisos de ejecucion).
-- ---------------------------------------------------------------------
revoke all on function public.rls_auto_enable() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 3) Permisos de ejecucion de las funciones del proyecto.
--
--    Se dejan exactamente como estaban: las RPC del cliente solo para
--    `authenticated`, las internas y el bootstrap solo para el
--    propietario. Se revoca PUBLIC en todas ellas por si alguna hubiera
--    quedado con el permiso por defecto.
-- ---------------------------------------------------------------------
revoke all on function public.crear_pedido(uuid, text, jsonb, uuid)
    from public, anon;
grant execute on function public.crear_pedido(uuid, text, jsonb, uuid)
    to authenticated;

revoke all on function public.reemitir_token_recogida(uuid)
    from public, anon;
grant execute on function public.reemitir_token_recogida(uuid)
    to authenticated;

revoke all on function public.crear_producto(uuid, text, bigint, text, text, integer, text, text)
    from public, anon;
grant execute on function public.crear_producto(uuid, text, bigint, text, text, integer, text, text)
    to authenticated;

revoke all on function public.configurar_tienda(uuid, text, text, double precision, double precision, boolean)
    from public, anon;
grant execute on function public.configurar_tienda(uuid, text, text, double precision, double precision, boolean)
    to authenticated;

revoke all on function public.asignar_rol_administrador(uuid, boolean)
    from public, anon;
grant execute on function public.asignar_rol_administrador(uuid, boolean)
    to authenticated;

revoke all on function public.es_administrador()
    from public, anon;
grant execute on function public.es_administrador()
    to authenticated;

-- Internas y bootstrap: solo el propietario del proyecto.
revoke all on function public._ttl_token_recogida() from public, anon, authenticated;
revoke all on function public._emitir_token_recogida(uuid) from public, anon, authenticated;
revoke all on function public._detalle_de_orden(uuid) from public, anon, authenticated;
revoke all on function public._respuesta_pedido(public.pedidos, boolean, text) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.es_administrador_de(uuid) from public, anon, authenticated;
revoke all on function public.bootstrap_primer_administrador(text) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 4) Comentarios de auditoria.
-- ---------------------------------------------------------------------
comment on table public.perfiles is
    'Perfil publico del usuario. Solo nombre y fechas: las credenciales las gestiona Supabase Auth. El cliente solo puede leer y editar su propia fila.';

comment on table public.roles_usuario is
    'Roles del usuario. Solo escribible mediante funciones que exigen que quien llama ya sea administrador. El cliente solo puede consultar el rol.';

comment on function public.rls_auto_enable() is
    'Disparador de evento del servidor que habilita RLS en las tablas nuevas del esquema public. No es ejecutable por el cliente (no lo necesita).';
