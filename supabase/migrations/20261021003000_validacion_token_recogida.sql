-- =====================================================================
-- Mercamigo · 20261021003000_validacion_token_recogida.sql
--
-- OPCIONAL / NO ESTRICTAMENTE NECESARIO PARA LA APP DE COMPRAS.
--
-- La app cliente no necesita estas funciones: ella solo genera la imagen
-- del QR a partir del token que le devuelve public.crear_pedido.
-- Son para el lado del personal (cajero) que valida la recogida.
--
-- NO recrea tablas ni borra datos. Solo añade funciones.
--
-- El token se busca por su SHA-256: en la base nunca se guarda el token
-- en texto plano.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Validar un token de recogida (sin consumirlo).
-- ---------------------------------------------------------------------
create or replace function public.validar_token_recogida(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_token    public.tokens_recogida%rowtype;
    v_pedido   public.pedidos%rowtype;
    v_hash     text;
begin
    if p_token is null or btrim(p_token) = '' then
        raise exception 'Token vacio.' using errcode = '22023';
    end if;

    v_hash := encode(extensions.digest(btrim(p_token), 'sha256'), 'hex');

    select * into v_token
      from public.tokens_recogida
     where token_hash = v_hash;

    if not found then
        return jsonb_build_object('valido', false, 'motivo', 'token_desconocido');
    end if;

    if v_token.revocado_en is not null then
        return jsonb_build_object('valido', false, 'motivo', 'token_revocado',
                                  'pedido_id', v_token.pedido_id);
    end if;

    if v_token.usado_en is not null then
        return jsonb_build_object('valido', false, 'motivo', 'token_usado',
                                  'pedido_id', v_token.pedido_id);
    end if;

    if v_token.expira_en is not null and v_token.expira_en <= now() then
        return jsonb_build_object('valido', false, 'motivo', 'token_expirado',
                                  'pedido_id', v_token.pedido_id);
    end if;

    select * into v_pedido
      from public.pedidos
     where id = v_token.pedido_id;

    return jsonb_build_object(
        'valido',       true,
        'pedido_id',    v_pedido.id,
        'numero_orden', v_pedido.numero_orden,
        'origen',       v_pedido.origen,
        'total_cop',    v_pedido.total_cop,
        'estado',       v_pedido.estado,
        'expira_en',    v_token.expira_en,
        'items',        public._detalle_de_orden(v_pedido.id)
    );
end;
$$;

comment on function public.validar_token_recogida(text) is
    'Valida un token de recogida y devuelve el pedido asociado. No lo consume.';

revoke all on function public.validar_token_recogida(text) from public, anon;
grant execute on function public.validar_token_recogida(text) to authenticated, service_role;


-- ---------------------------------------------------------------------
-- Consumir el token: marca la recogida como atendida.
-- ---------------------------------------------------------------------
create or replace function public.consumir_token_recogida(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_validacion jsonb;
begin
    v_validacion := public.validar_token_recogida(p_token);

    if not coalesce((v_validacion ->> 'valido')::boolean, false) then
        return v_validacion;
    end if;

    update public.tokens_recogida
       set usado_en = now()
     where pedido_id = (v_validacion ->> 'pedido_id')::uuid;

    return v_validacion || jsonb_build_object('consumido', true);
end;
$$;

comment on function public.consumir_token_recogida(text) is
    'Consume el token de recogida: lo marca como usado. Idempotente por diseno (un token usado no vuelve a ser valido).';

revoke all on function public.consumir_token_recogida(text) from public, anon;
grant execute on function public.consumir_token_recogida(text) to authenticated, service_role;


-- ---------------------------------------------------------------------
-- Revocar el token de un pedido (por ejemplo, si el cliente lo pierde).
-- ---------------------------------------------------------------------
create or replace function public.revocar_token_recogida(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.tokens_recogida
       set revocado_en = now()
     where pedido_id = p_pedido_id
       and revocado_en is null;

    return jsonb_build_object(
        'pedido_id' => p_pedido_id,
        'revocado'  => found
    );
end;
$$;

comment on function public.revocar_token_recogida(uuid) is
    'Revoca el token de recogida del pedido indicado.';

revoke all on function public.revocar_token_recogida(uuid) from public, anon;
grant execute on function public.revocar_token_recogida(uuid) to authenticated, service_role;
