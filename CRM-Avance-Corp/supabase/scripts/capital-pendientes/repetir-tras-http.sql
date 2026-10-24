-- Solo se antepone desde verificar.mjs, que fija la rama autorizada.
-- Se vacía la fixture HTTP DENTRO de la transacción de prueba. El ROLLBACK final
-- restaura íntegramente sus usuarios/sesiones/ventas; no es una limpieza de negocio.
begin;
set local statement_timeout='90s';
set local lock_timeout='5s';
do $$ begin
  if (select count(*) from auth.users)<>7 or exists(select 1 from auth.users
    where id not in (select ('f3000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,7) n)
      or email not like 'capital-pendientes-%@example.test')
    or (select count(*) from public.contratos)<>3 or exists(select 1 from public.contratos
      where id not in (select ('f3000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(201,203) n)) then
    raise exception 'Solo se permite repetir sobre la fixture HTTP sintética exacta';
  end if;
end $$;
set local session_replication_role=replica;
truncate crm.capital_cortes_valorados,crm.capital_valoraciones,crm.tipo_cambio_diario,crm.tipo_cambio_trabajos,
  crm.meta_periodos,crm.conversion_pesos,crm.productos_inversion,public.contratos,public.perfiles,auth.users,crm.equipo cascade;
set local session_replication_role=origin;
