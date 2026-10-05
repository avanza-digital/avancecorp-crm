-- Pruebas de B1 en el banco (solo lectura + ensayos deshechos). Salida: una línea por prueba.
\set ON_ERROR_STOP on
select 'columnas: ' || string_agg(column_name || ':' || data_type, ', ' order by column_name)
  from information_schema.columns where table_schema='crm' and table_name='leads'
   and column_name in ('reactivado_en','enfriado_hasta');
select 'check validado: ' || convalidated from pg_constraint
 where conrelid='crm.actividades'::regclass and conname='actividades_intento_base_forma';
select 'constantes: ' || max_intentos || '/' || dias_enfriamiento || '/' || dias_max_rellamada from private.base_gestion_constantes();
select 'B1b columna: ' || data_type from information_schema.columns where table_schema='crm' and table_name='leads' and column_name='proxima_llamada_en';
select 'B1b sello cubre 3 columnas: ' || (array_length(tgattr::smallint[],1) = 3) from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_sello_base_gestion';
select 'B1b indice parcial: ' || indisvalid from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='idx_leads_base_rellamada';
select 'sello: ' || tgname || ' enabled=' || tgenabled::text || ' before=' || ((tgtype & 2) = 2)
  from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_sello_base_gestion';
select 'grant select authenticated: ' || (has_column_privilege('authenticated','crm.leads','reactivado_en','SELECT')
   and has_column_privilege('authenticated','crm.leads','enfriado_hasta','SELECT'));
select 'sin insert/update por columna API: ' || ((select count(*) from pg_attribute a, aclexplode(a.attacl) e
  where a.attrelid='crm.leads'::regclass and a.attname in ('reactivado_en','enfriado_hasta')
    and e.privilege_type in ('INSERT','UPDATE') and e.grantee in ('anon'::regrole,'authenticated'::regrole)) = 0);
select 'acl por columna exacta (6 SELECT: authenticated+service_role x 3): ' || ((select count(*) from pg_attribute a, aclexplode(a.attacl) e
  where a.attrelid='crm.leads'::regclass and a.attname in ('reactivado_en','enfriado_hasta','proxima_llamada_en')
    and e.privilege_type='SELECT' and e.grantee in ('authenticated'::regrole,'service_role'::regrole)) = 6);
select 'acl de tabla leads (debe ser la de prod: authenticated=rw, service_role=arwd): ' || coalesce(relacl::text, 'NULL') from pg_class where oid='crm.leads'::regclass;
-- Negativo del CHECK: intento_base SIN resultado (trampa NULL cerrada con coalesce).
do $$
declare v_lead uuid; begin
  select id into v_lead from crm.leads where activo order by creado_en limit 1;
  begin
    insert into crm.actividades (lead_id, tipo, detalle, metadata) values (v_lead, 'nota', 'TEST',
      '{"evento":"intento_base","intento_n":"1","ciclo_n":"1","proxima_llamada_en":"2026-10-03T15:00:00-05:00"}');
    raise exception 'el CHECK acepto un intento sin resultado';
  exception when check_violation then raise notice 'check sin resultado: PASS (23514)'; end;
end $$;
-- Positivo del CHECK (deshecho): forma válida con volver_a_llamar + tarea_id.
do $$
declare v_lead uuid; begin
  select id into v_lead from crm.leads order by creado_en limit 1;
  if v_lead is null then raise notice 'check positivo: NO RUN (sin leads)'; return; end if;
  begin
    insert into crm.actividades (lead_id, tipo, detalle, metadata) values (v_lead, 'nota', 'TEST',
      '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"2","ciclo_n":"1","proxima_llamada_en":"2026-10-03T15:00:00-05:00"}');
    raise exception 'DESHACER' using errcode='P0002';
  exception when no_data_found then raise notice 'check positivo: PASS (insert valido, deshecho)'; end;
end $$;
-- Planes: la base por analista y las rellamadas deben usar índices existentes, no Seq Scan.
do $$
declare v jsonb; v_t text; v_idx text;
begin
  execute $q$explain (format json) select l.id from crm.leads l
     where l.activo and l.etapa = 'descartado'
       and l.vendedor_id = (select vendedor_id from crm.leads where vendedor_id is not null limit 1)
       and (l.enfriado_hasta is null or l.enfriado_hasta <= current_date)
     order by l.descartado_en desc$q$ into v;
  v_t := v::text;
  select string_agg(m[1], ',') into v_idx from regexp_matches(v_t, '"Index Name": "([^"]+)"', 'g') m;
  raise notice 'plan base analista: %', case when v_t ~ 'Seq Scan on leads' then 'SEQ SCAN en leads' else 'INDEX (' || coalesce(v_idx, 'otro') || ')' end;
  execute $q$explain (format json) select t.id from crm.tareas t
     where t.estado = 'pendiente' and t.activo and t.tipo = 'llamada' and t.vence_en <= now()
       and t.vendedor_id = (select vendedor_id from crm.tareas where vendedor_id is not null limit 1)$q$ into v;
  v_t := v::text;
  select string_agg(m[1], ',') into v_idx from regexp_matches(v_t, '"Index Name": "([^"]+)"', 'g') m;
  raise notice 'plan rellamadas: %', case when v_t ~ 'Seq Scan on tareas' then 'SEQ SCAN en tareas' else 'INDEX (' || coalesce(v_idx, 'otro') || ')' end;
end $$;
select 'filas: leads=' || (select count(*) from crm.leads) || ' descartados=' || (select count(*) from crm.leads where etapa='descartado')
  || ' actividades=' || (select count(*) from crm.actividades) || ' tareas=' || (select count(*) from crm.tareas);
