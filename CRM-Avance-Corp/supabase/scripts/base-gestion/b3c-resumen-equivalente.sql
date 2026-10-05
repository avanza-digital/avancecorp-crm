-- B3c · equivalencia del resumen: el cuerpo VIVO (antes de B3c) contra el nuevo, por rol, sobre los mismos datos.
-- Una transacción con ROLLBACK. Falla el proceso si alguna fila difiere.
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
-- El resumen VIVO, idéntico salvo el nombre (solo en esta transacción).
create function private.base_gestion_resumen_vivo_b3c()
returns table (vendedor_id uuid, nombre text, en_base integer, rellamadas_hoy integer, intentos_hoy integer, reactivaciones_mes integer)
language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_rol := private.base_gestion_rol(v_uid);
  if v_rol <> 'supervisor' and v_rol <> 'gerencia' then
    raise exception 'Solo Supervision y Gerencia ven el resumen de la base' using errcode = '42501';
  end if;
  return query
  select e.perfil_id, p.nombre_completo,
         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)),
         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
            and l.proxima_llamada_en is not null and (l.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
         -- Atribucion por DUEÑO del lead: lo que Supervision o Gerencia registran sobre un lead del analista cuenta para el analista.
         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'intento_base'
             and (a.creado_en at time zone 'America/Lima')::date = v_hoy),
         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'reactivacion_base'
             and date_trunc('month', a.creado_en at time zone 'America/Lima') = date_trunc('month', v_hoy::timestamp))
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'vendedor' and e.activo and p.activo
    and (v_rol = 'gerencia' or e.perfil_id in (select private.vendedor_ids_visibles(v_uid)))
  order by p.nombre_completo;
end;
$fn$;
grant execute on function private.base_gestion_resumen_vivo_b3c() to authenticated;
-- Datos: intentos de hoy de A y de C, una rellamada de hoy, una reactivación del mes.
select pg_temp.sesion('b0000000-0000-4000-8000-000000000002'); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000a1', 'volver_a_llamar', 'x', now() + interval '1 minute');
reset role;
select pg_temp.sesion('b0000000-0000-4000-8000-000000000013'); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000c1', 'no_contesto', 'x');
reset role;
select pg_temp.sesion('b0000000-0000-4000-8000-000000000012'); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000b1', 'agendo_reunion', 'x');
reset role;
create function pg_temp.dif() returns text language sql as $$
  select (select count(*) from (select * from crm.base_gestion_resumen() except all select * from private.base_gestion_resumen_vivo_b3c()) a)::text || '/' ||
         (select count(*) from (select * from private.base_gestion_resumen_vivo_b3c() except all select * from crm.base_gestion_resumen()) b)::text || ' de ' ||
         (select count(*) from crm.base_gestion_resumen())::text || ' filas, con datos: ' ||
         (select (sum(en_base) > 0 and sum(intentos_hoy) > 0)::text || ', reactivaciones: ' || sum(reactivaciones_mes)::text from crm.base_gestion_resumen()) $$;
grant execute on function pg_temp.dif() to authenticated;
select pg_temp.sesion('b0000000-0000-4000-8000-000000000001'); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'S1 (supervisor de A y B): nuevo = vivo', '0/0 de 2 filas, con datos: true, reactivaciones: 1', pg_temp.dif();
reset role;
select pg_temp.sesion('b0000000-0000-4000-8000-000000000011'); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'S2 (supervisor de C): nuevo = vivo', '0/0 de 1 filas, con datos: true, reactivaciones: 0', pg_temp.dif();
reset role;
select pg_temp.sesion('b0000000-0000-4000-8000-000000000003'); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'G (gerencia): nuevo = vivo', '0/0 de 3 filas, con datos: true, reactivaciones: 1', pg_temp.dif();
reset role;
update r set ok = coalesce(obtenido = esperado, false);
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, obtenido) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B3c equivalencia: hay casos FAIL'; end if; end $$;
rollback;
