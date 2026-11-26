-- Los clientes anonimos solo consultan promociones activas y nunca necesitan
-- ejecutar la funcion administrativa es_administrador().
drop policy if exists promociones_lectura_publica on public.promociones;
create policy promociones_lectura_anon on public.promociones
    for select to anon
    using (activa);
create policy promociones_lectura_authenticated on public.promociones
    for select to authenticated
    using (activa or public.es_administrador());

drop policy if exists promocion_productos_lectura_publica
    on public.promocion_productos;
create policy promocion_productos_lectura_anon
    on public.promocion_productos
    for select to anon
    using (
        exists (
            select 1
              from public.promociones p
             where p.id = promocion_id
               and p.activa
        )
    );
create policy promocion_productos_lectura_authenticated
    on public.promocion_productos
    for select to authenticated
    using (
        exists (
            select 1
              from public.promociones p
             where p.id = promocion_id
               and (p.activa or public.es_administrador())
        )
    );
