-- Asignación del rol de caja desde la interfaz de administración.
--
-- `asignar_rol_personal` trabaja con el uuid del usuario, que el
-- administrador no conoce. Estas dos funciones permiten gestionarlo por
-- correo, siempre con la comprobación de administrador en el servidor:
--
--   · `listar_personal()`: quién tiene el rol (para mostrarlo en la app).
--   · `asignar_rol_personal_por_correo(correo, asignar)`.
--
-- Nunca se puede asignar el rol a uno mismo y nunca se degrada a otro
-- administrador. Ninguna función queda disponible para `anon`.

create or replace function public.listar_personal()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_items jsonb;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede ver el personal.'
            using errcode = '42501';
    end if;

    select coalesce(
               pg_catalog.jsonb_agg(
                   pg_catalog.jsonb_build_object(
                       'usuario_id', r.usuario_id,
                       'rol',        r.rol,
                       'nombre',     coalesce(pr.nombre, ''),
                       'correo',     coalesce(u.email, '')
                   )
                   order by r.rol, pr.nombre, u.email
               ),
               '[]'::jsonb
           )
      into v_items
      from public.roles_usuario r
      left join public.perfiles pr on pr.id = r.usuario_id
      left join auth.users u on u.id = r.usuario_id;

    return v_items;
end;
$function$;

revoke all on function public.listar_personal() from public, anon;
grant execute on function public.listar_personal() to authenticated;

create or replace function public.asignar_rol_personal_por_correo(
    p_correo text,
    p_asignar boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_correo text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_correo, '')));
    v_usuario uuid;
    v_nombre text;
begin
    if not public.es_administrador() then
        raise exception 'Solo un administrador puede gestionar el rol de caja.'
            using errcode = '42501';
    end if;

    if v_correo = '' then
        raise exception 'El correo es obligatorio.'
            using errcode = '22023';
    end if;

    select u.id,
           coalesce(
               nullif(pg_catalog.btrim(pr.nombre), ''),
               nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'nombre'), ''),
               pg_catalog.split_part(u.email, '@', 1)
           )
      into v_usuario, v_nombre
      from auth.users u
      left join public.perfiles pr on pr.id = u.id
     where pg_catalog.lower(u.email) = v_correo;

    if v_usuario is null then
        raise exception 'No existe una cuenta con el correo %.', v_correo
            using errcode = '22023';
    end if;

    if v_usuario = auth.uid() then
        raise exception 'No puedes cambiar tu propio rol.'
            using errcode = '42501';
    end if;

    if p_asignar then
        insert into public.roles_usuario (usuario_id, rol)
        values (v_usuario, 'personal')
        on conflict (usuario_id) do nothing;
    else
        if exists (
            select 1
              from public.roles_usuario
             where usuario_id = v_usuario
               and rol = 'administrador'
        ) then
            raise exception 'No se puede quitar el rol a un administrador.'
                using errcode = '42501';
        end if;

        delete from public.roles_usuario
         where usuario_id = v_usuario
           and rol = 'personal';
    end if;

    return pg_catalog.jsonb_build_object(
        'usuario_id', v_usuario,
        'nombre',     coalesce(v_nombre, ''),
        'correo',     v_correo,
        'rol',        case when p_asignar then 'personal' else 'comprador' end
    );
end;
$function$;

revoke all on function public.asignar_rol_personal_por_correo(text, boolean)
    from public, anon;
grant execute on function public.asignar_rol_personal_por_correo(text, boolean)
    to authenticated;
