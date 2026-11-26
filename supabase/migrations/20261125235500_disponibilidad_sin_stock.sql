-- Disponibilidad sin conteo de existencias
-- ---------------------------------------------------------------------------
-- La compra se controla con `productos.activo`: un producto activo se puede
-- pedir y uno desactivado se rechaza al crear la orden. Ya no se valida ni se
-- descuenta stock.
--
-- `stock_demo` se conserva porque la app lo usa como tope del selector de
-- cantidad. Se fija en 100, el mismo maximo por producto que acepta
-- `crear_pedido`, para que el cliente nunca pueda pedir una cantidad que el
-- servidor vaya a rechazar.

drop trigger if exists detalle_pedido_stock on public.detalle_pedido;
drop function if exists public._validar_stock_detalle();

update public.productos
   set stock_demo = 100
 where stock_demo <> 100;

create or replace function public.crear_producto(
  p_categoria_id uuid,
  p_nombre text,
  p_precio_cop bigint,
  p_codigo text default null,
  p_descripcion text default 'Producto de demostracion para pruebas academicas',
  p_stock_demo integer default 100,
  p_imagen_url text default null,
  p_tipo_codigo text default 'barras'
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_producto_id uuid;
 v_codigo text;
begin
 if not public.es_administrador() then
  raise exception 'Solo un administrador puede crear productos.' using errcode='42501';
 end if;
 if p_nombre is null or pg_catalog.btrim(p_nombre)='' then
  raise exception 'El nombre es obligatorio.' using errcode='22023';
 end if;
 if p_precio_cop is null or p_precio_cop<=0 then
  raise exception 'El precio debe ser mayor que cero.' using errcode='22023';
 end if;
 if p_stock_demo is null or p_stock_demo<0 then
  raise exception 'El stock no puede ser negativo.' using errcode='22023';
 end if;
 if not exists(select 1 from public.categorias where id=p_categoria_id and activa) then
  raise exception 'La categoria no existe o no esta activa.' using errcode='22023';
 end if;
 insert into public.productos(categoria_id,nombre,descripcion,precio_cop,imagen_url,stock_demo,activo,es_demostracion)
 values(p_categoria_id,pg_catalog.btrim(p_nombre),coalesce(p_descripcion,'Producto de demostracion para pruebas academicas'),p_precio_cop,p_imagen_url,p_stock_demo,true,true)
 returning id into v_producto_id;
 loop
  v_codigo := pg_catalog.nextval('public.producto_codigo_numero_seq'::regclass)::text;
  insert into public.codigos_producto(producto_id,codigo,tipo)
  values(v_producto_id,v_codigo,'barras')
  on conflict (codigo) do nothing;
  exit when found;
 end loop;
 return pg_catalog.jsonb_build_object('producto_id',v_producto_id,'codigo',v_codigo,'tipo','barras','nombre',pg_catalog.btrim(p_nombre));
end;
$function$;
