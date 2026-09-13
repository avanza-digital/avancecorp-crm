-- Oráculo transaccional para crm.leads_recibidos_analista_fn.
--
-- Requiere que la migración ya esté instalada. Usa datos reales del banco sin
-- modificarlos y termina en ROLLBACK.

begin;

set local session_replication_role = replica;

do $preparar_oraculo$
declare
  v_analista uuid;
  v_no_analista uuid;
  v_fixture_analista constant uuid := 'f1980000-0000-4000-8000-000000000001';
  v_fixture_no_analista constant uuid := 'f1980000-0000-4000-8000-000000000002';
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date := v_hoy - 30;
  v_inicio timestamptz := v_desde::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (v_hoy + 1)::timestamp at time zone 'America/Lima';
  v_total integer;
  v_aproximados integer;
  v_dia_vacio date;
begin
  select equipo.perfil_id
  into v_analista
  from crm.equipo equipo
  join public.perfiles perfil on perfil.id = equipo.perfil_id
  where equipo.rol_crm = 'vendedor'
    and equipo.activo = true
    and perfil.activo = true
  order by equipo.perfil_id
  limit 1;

  select equipo.perfil_id
  into v_no_analista
  from crm.equipo equipo
  join public.perfiles perfil on perfil.id = equipo.perfil_id
  where equipo.rol_crm is distinct from 'vendedor'
    and equipo.activo = true
    and perfil.activo = true
  order by equipo.perfil_id
  limit 1;

  -- Una branch recién creada no contiene datos. En ese caso el oráculo crea
  -- solo los dos actores mínimos bajo session_replication_role=replica. Viven
  -- dentro de esta transacción y el ROLLBACK final los retira junto al ledger.
  if v_analista is null then
    v_analista := v_fixture_analista;
    insert into public.perfiles (id, nombre_completo, rol, activo)
    values (v_analista, 'ORACULO ANALISTA LEADS RECIBIDOS', 'analista', true);
    insert into crm.equipo (perfil_id, rol_crm, activo)
    values (v_analista, 'vendedor', true);
  end if;

  if v_no_analista is null then
    v_no_analista := v_fixture_no_analista;
    insert into public.perfiles (id, nombre_completo, rol, activo)
    values (v_no_analista, 'ORACULO GERENCIA LEADS RECIBIDOS', 'admin', true);
    insert into crm.equipo (perfil_id, rol_crm, activo)
    values (v_no_analista, 'gerencia', true);
  end if;

  -- Tres casos que el oráculo puede distinguir sin copiar el predicado de la
  -- RPC: NULL/NULL sí es una entrada, misma bandeja identificada no suma y una
  -- fila de otro actor jamás cruza el filtro por auth.uid(). Los triggers se
  -- desactivan solo dentro de esta transacción para sembrar el ledger inmutable;
  -- constraints e índices siguen validando las filas y ROLLBACK las retira.
  insert into crm.lead_asignaciones (
    lead_id,
    ciclo_n,
    episodio_n,
    analista_id,
    motivo_apertura,
    asignado_en,
    supervisor_origen_id,
    sla_global_iniciado_en,
    sla_politica_asignacion_id,
    primera_gestion_limite_en,
    primer_contacto_limite_en,
    moneda,
    origen,
    finalizado_en,
    motivo_cierre,
    supervisor_destino_id
  ) values
    (
      'f1990000-0000-4000-8000-000000000001',
      1,
      1,
      v_analista,
      'asignado',
      v_inicio,
      null,
      v_inicio,
      'f1990000-0000-4000-8000-00000000f001',
      v_inicio + interval '1 hour',
      v_inicio + interval '2 hours',
      'PEN',
      'oraculo_leads_recibidos',
      v_inicio + interval '1 minute',
      'parqueado',
      null
    ),
    (
      'f1990000-0000-4000-8000-000000000002',
      1,
      1,
      v_analista,
      'asignado',
      v_inicio + interval '1 hour',
      v_no_analista,
      v_inicio + interval '1 hour',
      'f1990000-0000-4000-8000-00000000f001',
      v_inicio + interval '2 hours',
      v_inicio + interval '3 hours',
      'PEN',
      'oraculo_leads_recibidos',
      v_inicio + interval '2 hours',
      'parqueado',
      v_no_analista
    ),
    (
      'f1990000-0000-4000-8000-000000000003',
      1,
      1,
      v_no_analista,
      'asignado',
      v_inicio + interval '3 hours',
      null,
      v_inicio + interval '3 hours',
      'f1990000-0000-4000-8000-00000000f001',
      v_inicio + interval '4 hours',
      v_inicio + interval '5 hours',
      'PEN',
      'oraculo_leads_recibidos',
      v_inicio + interval '4 hours',
      'desactivado',
      null
    ),
    -- Ambos lados exactos de [inicio, fin): antes y en fin deben quedar fuera.
    (
      'f1990000-0000-4000-8000-000000000004',
      1,
      1,
      v_analista,
      'asignado',
      v_inicio - interval '1 microsecond',
      null,
      v_inicio - interval '1 microsecond',
      'f1990000-0000-4000-8000-00000000f001',
      v_inicio + interval '1 hour',
      v_inicio + interval '2 hours',
      'PEN',
      'oraculo_leads_recibidos',
      v_inicio,
      'desactivado',
      null
    ),
    (
      'f1990000-0000-4000-8000-000000000005',
      1,
      1,
      v_analista,
      'asignado',
      v_fin,
      null,
      v_fin,
      'f1990000-0000-4000-8000-00000000f001',
      v_fin + interval '1 hour',
      v_fin + interval '2 hours',
      'PEN',
      'oraculo_leads_recibidos',
      v_fin + interval '1 minute',
      'desactivado',
      null
    );

  select
    (
      pg_catalog.count(*)
      - pg_catalog.count(*) filter (
          where asignacion.motivo_cierre = 'parqueado'
            and asignacion.supervisor_origen_id is not null
            and asignacion.supervisor_destino_id = asignacion.supervisor_origen_id
        )
    )::integer,
    (
      pg_catalog.count(*) filter (where asignacion.aproximado)
      - pg_catalog.count(*) filter (
          where asignacion.aproximado
            and asignacion.motivo_cierre = 'parqueado'
            and asignacion.supervisor_origen_id is not null
            and asignacion.supervisor_destino_id = asignacion.supervisor_origen_id
        )
    )::integer
  into v_total, v_aproximados
  from crm.lead_asignaciones asignacion
  where asignacion.analista_id = v_analista
    and asignacion.asignado_en >= v_inicio
    and asignacion.asignado_en < v_fin;

  select dia::date
  into v_dia_vacio
  from pg_catalog.generate_series(v_hoy - 365, v_hoy, interval '1 day') dia
  where not exists (
    select 1
    from crm.lead_asignaciones asignacion
    where asignacion.analista_id = v_analista
      and asignacion.asignado_en >= dia::date::timestamp at time zone 'America/Lima'
      and asignacion.asignado_en < (dia::date + 1)::timestamp at time zone 'America/Lima'
      and not (
        asignacion.motivo_cierre is not distinct from 'parqueado'
        and asignacion.supervisor_origen_id is not null
        and asignacion.supervisor_destino_id is not distinct from asignacion.supervisor_origen_id
      )
  )
  order by dia desc
  limit 1;

  if v_dia_vacio is null then
    raise exception 'FALLO fixture: no existe un día vacío del analista en los últimos 366 días';
  end if;

  perform pg_catalog.set_config('test.leads_recibidos.analista', v_analista::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.no_analista', v_no_analista::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.desde', v_desde::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.hasta', v_hoy::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.total', v_total::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.aproximados', v_aproximados::text, true);
  perform pg_catalog.set_config('test.leads_recibidos.dia_vacio', v_dia_vacio::text, true);
end;
$preparar_oraculo$;

set local session_replication_role = default;

-- Analista activo: contrato, totales y serie diaria completa.
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  pg_catalog.jsonb_build_object(
    'sub', pg_catalog.current_setting('test.leads_recibidos.analista'),
    'role', 'authenticated'
  )::text,
  true
);
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  pg_catalog.current_setting('test.leads_recibidos.analista'),
  true
);

do $probar_analista$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
  v_esperado integer := pg_catalog.current_setting('test.leads_recibidos.total')::integer;
  v_aproximados integer := pg_catalog.current_setting('test.leads_recibidos.aproximados')::integer;
  v_payload jsonb;
  v_suma integer;
  v_suma_aproximados integer;
begin
  v_payload := crm.leads_recibidos_analista_fn(v_desde, v_hasta);

  if (v_payload->>'version')::integer <> 1
     or v_payload->'periodo'->>'desde' <> v_desde::text
     or v_payload->'periodo'->>'hasta' <> v_hasta::text
     or (v_payload->'periodo'->>'dias')::integer <> 31
     or v_payload->'periodo'->>'zona' <> 'America/Lima' then
    raise exception 'FALLO contrato: periodo/version inesperados — %', v_payload;
  end if;

  if (v_payload->>'total')::integer <> v_esperado
     or (v_payload->>'aproximados')::integer <> v_aproximados then
    raise exception 'FALLO total: esperaba %/% y recibió %/%',
      v_esperado,
      v_aproximados,
      v_payload->>'total',
      v_payload->>'aproximados';
  end if;

  if pg_catalog.jsonb_array_length(v_payload->'dias') <> 31
     or v_payload->'dias'->0->>'fecha' <> v_desde::text
     or v_payload->'dias'->30->>'fecha' <> v_hasta::text then
    raise exception 'FALLO serie diaria: deben existir los 31 días inclusivos — %',
      v_payload->'dias';
  end if;

  select
    coalesce(pg_catalog.sum((dia->>'total')::integer), 0)::integer,
    coalesce(pg_catalog.sum((dia->>'aproximados')::integer), 0)::integer
  into v_suma, v_suma_aproximados
  from pg_catalog.jsonb_array_elements(v_payload->'dias') dia;

  if v_suma <> v_esperado or v_suma_aproximados <> v_aproximados then
    raise exception 'FALLO suma diaria: %/% no coincide con %/%',
      v_suma,
      v_suma_aproximados,
      v_esperado,
      v_aproximados;
  end if;

  if v_payload::text ~ '"(lead_id|nombre|telefono|correo|dni)"' then
    raise exception 'FALLO privacidad: el payload expone una clave de PII — %', v_payload;
  end if;

  begin
    perform crm.leads_recibidos_analista_fn(v_hasta, v_desde);
    raise exception 'FALLO validación: aceptó desde > hasta';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta + 1);
    raise exception 'FALLO validación: aceptó una fecha futura';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform crm.leads_recibidos_analista_fn(v_hasta - 366, v_hasta);
    raise exception 'FALLO validación: aceptó más de 366 días';
  exception when sqlstate '22023' then null;
  end;

  v_desde := pg_catalog.current_setting('test.leads_recibidos.dia_vacio')::date;
  v_payload := crm.leads_recibidos_analista_fn(v_desde, v_desde);
  if (v_payload->>'total')::integer <> 0
     or pg_catalog.jsonb_array_length(v_payload->'dias') <> 1
     or v_payload->'dias'->0->>'fecha' <> v_desde::text
     or (v_payload->'dias'->0->>'total')::integer <> 0 then
    raise exception 'FALLO día vacío: la serie debe publicar el cero explícito — %', v_payload;
  end if;
end;
$probar_analista$;

-- Las dos capas de vigencia son obligatorias incluso con un JWT aún válido.
reset role;
set local session_replication_role = replica;
update crm.equipo
set activo = false
where perfil_id = pg_catalog.current_setting('test.leads_recibidos.analista')::uuid;
set local session_replication_role = default;
set local role authenticated;

do $probar_membresia_inactiva$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta);
    raise exception 'FALLO gate: una membresía CRM inactiva pudo consultar el reporte';
  exception when sqlstate '42501' then null;
  end;
end;
$probar_membresia_inactiva$;

reset role;
set local session_replication_role = replica;
update crm.equipo
set activo = true
where perfil_id = pg_catalog.current_setting('test.leads_recibidos.analista')::uuid;
update public.perfiles
set activo = false
where id = pg_catalog.current_setting('test.leads_recibidos.analista')::uuid;
set local session_replication_role = default;
set local role authenticated;

do $probar_perfil_inactivo$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta);
    raise exception 'FALLO gate: un perfil inactivo pudo consultar el reporte';
  exception when sqlstate '42501' then null;
  end;
end;
$probar_perfil_inactivo$;

reset role;
set local session_replication_role = replica;
update public.perfiles
set activo = true
where id = pg_catalog.current_setting('test.leads_recibidos.analista')::uuid;
set local session_replication_role = default;
set local role authenticated;

-- Un actor activo con otro rol no puede convertir la RPC en reporte global.
select pg_catalog.set_config(
  'request.jwt.claims',
  pg_catalog.jsonb_build_object(
    'sub', pg_catalog.current_setting('test.leads_recibidos.no_analista'),
    'role', 'authenticated'
  )::text,
  true
);
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  pg_catalog.current_setting('test.leads_recibidos.no_analista'),
  true
);

do $probar_otro_rol$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta);
    raise exception 'FALLO gate: un actor no vendedor pudo consultar el reporte';
  exception when sqlstate '42501' then null;
  end;
end;
$probar_otro_rol$;

-- Sin identidad: el gate de rol se evalúa antes que las fechas.
select pg_catalog.set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

do $probar_sin_sesion$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_hasta, v_desde);
    raise exception 'FALLO gate: un actor sin auth.uid() alcanzó la validación de fechas';
  exception when sqlstate '42501' then null;
  end;
end;
$probar_sin_sesion$;

reset role;

-- anon no posee EXECUTE; ni siquiera alcanza el gate interno.
set local role anon;

do $probar_anon$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta);
    raise exception 'FALLO grants: anon pudo ejecutar la RPC';
  exception when insufficient_privilege then null;
  end;
end;
$probar_anon$;

reset role;

-- service_role tampoco tiene EXECUTE: la lectura privilegiada no forma parte
-- del contrato de esta pantalla.
set local role service_role;

do $probar_service_role$
declare
  v_desde date := pg_catalog.current_setting('test.leads_recibidos.desde')::date;
  v_hasta date := pg_catalog.current_setting('test.leads_recibidos.hasta')::date;
begin
  begin
    perform crm.leads_recibidos_analista_fn(v_desde, v_hasta);
    raise exception 'FALLO grants: service_role pudo ejecutar la RPC';
  exception when insufficient_privilege then null;
  end;
end;
$probar_service_role$;

reset role;

do $exito$
begin
  raise notice 'LEADS_RECIBIDOS_ANALISTA_TX_OK';
end;
$exito$;

rollback;
