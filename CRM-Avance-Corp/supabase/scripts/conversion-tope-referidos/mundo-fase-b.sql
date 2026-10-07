-- Mundo sintético DETERMINISTA de la Fase B del tope de referidos. Lo incluye (\i) quien ya abrió la transacción; nada se
-- guarda: el que lo incluye termina en rollback. Mismos ids en cada corrida para poder comparar ANTES y DESPUÉS de la migración.
--   Octubre (con tope 15 %): A 15 cierres asignados (10 landing + 5 formulario) + 5 referidos y 65 llegadas más sin cerrar ⇒ base 15, tope 3.
--                            B 4 cierres asignados (landing) + 2 referidos ⇒ base 4, tope ceil(0,6) = 1.
--   Septiembre (sin tope):   A 10 cierres asignados (formulario) + 3 referidos; B 5 asignados (landing) + 1 referido.
-- Actores: gerencia G, supervisor S, vendedores A y B (con su fila en public.perfiles, que el roster exige).
set local session_replication_role = replica;
set local search_path = '';

create function pg_temp.exigir(p_ok boolean, p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FALLA: %', p_motivo; end if; end $$;

-- Las fuentes de las acreditaciones sintéticas son siempre elegibles.
create or replace function private.conversion_exclusion_fuente(p_tipo text, p_id uuid) returns text
  language sql stable set search_path = '' as $$ select 'elegible'::text $$;

create temp sequence sq_mundo;
create temp table ana as select
  'a0000000-0000-4000-8000-00000000000a'::uuid a, 'b0000000-0000-4000-8000-00000000000b'::uuid b,
  'd0000000-0000-4000-8000-00000000000d'::uuid g, 'e0000000-0000-4000-8000-00000000000e'::uuid s;

insert into public.perfiles (id, nombre_completo) select a, 'Analista A' from ana;
insert into public.perfiles (id, nombre_completo) select b, 'Analista B' from ana;
insert into public.perfiles (id, nombre_completo) select g, 'Gerencia G' from ana;
insert into public.perfiles (id, nombre_completo) select s, 'Supervisor S' from ana;
insert into crm.equipo (perfil_id, rol_crm) select g, 'gerencia' from ana;
insert into crm.equipo (perfil_id, rol_crm) select s, 'supervisor' from ana;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id) select a, 'vendedor', s from ana;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id) select b, 'vendedor', s from ana;

-- Una llegada (lead creado en el mes y asignado a un analista), sin cerrar.
create function pg_temp.llegada(p_analista uuid, p_origen text, p_mes date) returns uuid language plpgsql as $$
declare v_lead uuid := md5('llegada|' || nextval('sq_mundo'))::uuid; v_ts timestamptz := (p_mes + 2)::timestamp at time zone 'America/Lima' + interval '8 hours';
begin
  insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, creado_en)
    values (v_lead, 'Llegada ' || v_lead, '9' || substr(replace(v_lead::text, '-', ''), 1, 8), p_origen, 1000, v_ts);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en)
    values (v_lead, 1, 1, p_analista, 'asignado', v_ts, 'PEN', p_origen, v_ts, md5('pol')::uuid, v_ts + interval '1 day', v_ts + interval '1 day');
  return v_lead;
end $$;

-- Un cierre: el lead llega en el mes (cuenta en el divisor si es landing/formulario) y se acredita el día p_dia.
create function pg_temp.cierre(p_analista uuid, p_origen text, p_mes date, p_dia int) returns uuid language plpgsql as $$
declare v_lead uuid := md5('cierre|' || nextval('sq_mundo'))::uuid; v_ep uuid; v_fecha timestamptz := (p_mes + p_dia)::timestamp at time zone 'America/Lima';
  v_ts timestamptz := least((p_mes + 1)::timestamp at time zone 'America/Lima' + interval '8 hours',
                            (p_mes + p_dia)::timestamp at time zone 'America/Lima' - interval '1 hour');
  v_acred timestamptz := v_fecha + (nextval('sq_mundo') || ' seconds')::interval;
begin
  insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, creado_en, etapa, convertido_en)
    values (v_lead, 'Sintetico ' || v_lead, '9' || substr(replace(v_lead::text, '-', ''), 1, 8), p_origen, 1000, v_ts, 'convertido', v_fecha);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en,
      resultado, resultado_en, finalizado_en, motivo_cierre)
    values (v_lead, 1, 1, p_analista, 'asignado', v_ts, 'PEN', p_origen, v_ts, md5('pol')::uuid, v_fecha, v_fecha,
      'convertido', v_fecha, v_fecha, 'convertido') returning id into v_ep;
  insert into crm.conversion_acreditaciones (lead_id, episodio_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
      confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, politica_desde, motivo)
    values (v_lead, v_ep, p_analista, p_origen, 'contrato', md5('fuente|' || v_lead)::uuid, p_mes + (p_dia - 1),
      v_acred, v_acred, v_acred, p_mes, private.conversion_plazo_hasta(p_mes), 'acreditada', '2026-09-01', 'sintetico');
  return v_lead;
end $$;

do $mundo$
declare a uuid := (select a from ana); b uuid := (select b from ana); i int;
begin
  -- Octubre · A: 10 landing + 5 formulario + 5 referidos (días 2..6) cerrados; 50 landing + 15 formulario sin cerrar.
  for i in 1..10 loop perform pg_temp.cierre(a, 'landing', '2026-10-01', 1 + (i % 5)); end loop;
  for i in 1..5 loop perform pg_temp.cierre(a, 'formulario', '2026-10-01', 1 + (i % 5)); end loop;
  for i in 1..5 loop perform pg_temp.cierre(a, 'referido', '2026-10-01', 1 + i); end loop;
  for i in 1..50 loop perform pg_temp.llegada(a, 'landing', '2026-10-01'); end loop;
  for i in 1..15 loop perform pg_temp.llegada(a, 'formulario', '2026-10-01'); end loop;
  -- Octubre · B: 4 landing + 2 referidos cerrados; 26 landing sin cerrar; 3 referidos que llegan.
  for i in 1..4 loop perform pg_temp.cierre(b, 'landing', '2026-10-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(b, 'referido', '2026-10-01', 1 + i); end loop;
  for i in 1..26 loop perform pg_temp.llegada(b, 'landing', '2026-10-01'); end loop;
  for i in 1..3 loop perform pg_temp.llegada(b, 'referido', '2026-10-01'); end loop;
  -- Septiembre (sin tope) · A: 10 formulario + 3 referidos; B: 5 landing + 1 referido; llegadas sin cerrar.
  for i in 1..10 loop perform pg_temp.cierre(a, 'formulario', '2026-09-01', 1 + (i % 6)); end loop;
  for i in 1..3 loop perform pg_temp.cierre(a, 'referido', '2026-09-01', 10 + i); end loop;
  for i in 1..40 loop perform pg_temp.llegada(a, 'landing', '2026-09-01'); end loop;
  for i in 1..5 loop perform pg_temp.cierre(b, 'landing', '2026-09-01', 1 + i); end loop;
  perform pg_temp.cierre(b, 'referido', '2026-09-01', 9);
  for i in 1..20 loop perform pg_temp.llegada(b, 'landing', '2026-09-01'); end loop;
end
$mundo$;
