-- Llamadas desde el celular · octava migración (F4-b): dos LECTURAS para la pantalla del analista. Plan:
-- docs/plans/llamadas-celular/F4B-PLAN-CORTO.md (B2), aprobado por Jhosep el 05/10/2026; hallazgos 1 y 3 de
-- F4-PLAN-CORTO.md. Se publica con F4-b (la pestaña «Llamadas del celular»), después de las siete.
--
-- Qué hace (solo lectura; sin tablas, sin datos, sin tocar puertas existentes):
--   1. crm.llamadas_celular_resueltas_hoy_fn(p_limite): «Qué pasó hoy» (hallazgo 1). Las llamadas recibidas HOY (día de
--      Lima) que ya no están pendientes —registradas o descartadas—, con su resultado (de la actividad enlazada: cuál y
--      si se deshizo), la vía del enlace o el motivo del descarte. Decisión de Jhosep (05/10): solo el día de hoy.
--   2. crm.actividades_con_llamada_celular_fn(p_actividad_ids): la marca «Celular C1» en «¿Qué hice hoy?» (hallazgo 3).
--      De una lista de gestiones que la pantalla ya tiene, cuáles están unidas a una llamada del celular, con la
--      etiqueta y la vía. NO se toca crm.registro_actividad_fn: cambiar su salida sería un cambio de contrato de una
--      puerta que usan otras pantallas (decisión 2 del plan corto).
--   El ámbito es el de la bandeja: private.llamada_celular_visible (lead activo y del ámbito del actor, gerencia
--   incluida; sin lead, la llamada es del analista o de su supervisión). Roles: analista, supervisión y gerencia.
--
-- Capas (estándar de 4 capas): puertas DEFINER en crm (EXECUTE solo authenticated) que validan y delegan en un núcleo
-- INVOKER de private, sin EXECUTE para nadie. Excepción single-tenant (F2.3.3): sin columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-lecturas-analista.sql (solo quita las cuatro funciones: sin datos,
-- corre en cualquier momento). Verificación: npm run test:llamadas:local (pasada 15: oráculo
-- tests/llamadas-celular/oraculo-lecturas-analista.sql, huella del catálogo, reversa y mutantes) y el bloque
-- testLlamadasCelular de test-rls.mjs con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is not null
     or to_regprocedure('crm.actividades_con_llamada_celular_fn(uuid[])') is not null then
    raise exception 'LLAMADAS_LECTURAS_ANALISTA: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regprocedure('private.llamada_celular_cumplir_intencion(uuid)') is null
     or to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)') is null
     or to_regprocedure('private.llamadas_celular_actor(text[])') is null then
    raise exception 'LLAMADAS_LECTURAS_ANALISTA: faltan las siete migraciones de llamadas (la última, 20261005182227)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_cumplir_intencion(uuid)'::regprocedure),
                       'for key share nowait') = 0 then
    raise exception 'LLAMADAS_LECTURAS_ANALISTA: falta la séptima (20261005182227)';
  end if;
end;
$precondicion$;

-- ── 1. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────

-- «Qué pasó hoy»: llamadas recibidas hoy (Lima) ya resueltas, visibles para el actor, de la más reciente a la más vieja.
create function private.llamadas_celular_resueltas_hoy(p_actor uuid, p_limite integer, p_ahora timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with dia as (
    select (pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima') as desde
  ), resueltas as (
    select e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.atencion, e.lead_id, e.analista_id,
           e.motivo_descarte, e.motivo_descarte_detalle, l.nombre_completo as lead_nombre, ca.etiqueta,
           en.actividad_id, en.via, a.metadata ->> 'resultado' as resultado, (a.metadata ? 'deshecho_en') as deshecho
    from dia, crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
    left join crm.llamadas_celular_enlaces en on en.evento_id = e.id
    left join crm.actividades a on a.id = en.actividad_id
    where e.atencion in ('registrado', 'descartado_con_motivo')
      and e.recibido_en >= dia.desde and e.recibido_en < dia.desde + interval '1 day'
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc, e.id desc
    limit p_limite
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'evento_id', r.id, 'recibido_en', r.recibido_en, 'ocurrio_en', r.ocurrio_en, 'numero', r.numero_canonico,
           'atencion', r.atencion, 'lead_id', r.lead_id, 'lead_nombre', r.lead_nombre, 'analista_id', r.analista_id,
           'es_propia', r.analista_id = p_actor, 'etiqueta', r.etiqueta,
           'actividad_id', r.actividad_id, 'resultado', r.resultado, 'deshecho', coalesce(r.deshecho, false), 'via', r.via,
           'motivo_descarte', r.motivo_descarte, 'motivo_descarte_detalle', r.motivo_descarte_detalle)
         order by r.recibido_en desc, r.id desc), '[]'::jsonb)
  from resueltas r
$function$;

-- La marca «Celular»: de las gestiones pedidas, las unidas a una llamada del celular visible para el actor.
create function private.actividades_con_llamada_celular(p_actor uuid, p_actividad_ids uuid[])
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'actividad_id', en.actividad_id, 'evento_id', e.id, 'etiqueta', ca.etiqueta, 'via', en.via)
         order by en.actividad_id), '[]'::jsonb)
  from crm.llamadas_celular_enlaces en
  join crm.llamadas_celular_eventos e on e.id = en.evento_id
  left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
  where en.actividad_id = any(p_actividad_ids)
    and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
$function$;

-- ── 2. Puertas (DEFINER, EXECUTE solo authenticated) ─────────────────────────────────────────
create function crm.llamadas_celular_resueltas_hoy_fn(p_limite integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  if p_limite is null or p_limite not between 1 and 200 then
    raise exception using errcode = '22023', message = 'El límite va de 1 a 200';
  end if;
  return private.llamadas_celular_resueltas_hoy(v_actor, p_limite, pg_catalog.now());
end;
$function$;

create function crm.actividades_con_llamada_celular_fn(p_actividad_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
begin
  if p_actividad_ids is null or pg_catalog.cardinality(p_actividad_ids) = 0 then
    return '[]'::jsonb;
  end if;
  if pg_catalog.cardinality(p_actividad_ids) > 500 then
    raise exception using errcode = '22023', message = 'Como máximo 500 gestiones por consulta';
  end if;
  return private.actividades_con_llamada_celular(v_actor, p_actividad_ids);
end;
$function$;

-- ── 3. Permisos ──────────────────────────────────────────────────────────────────────────────
do $permisos$
declare
  v_f text;
begin
  foreach v_f in array array[
    'private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)',
    'private.actividades_con_llamada_celular(uuid,uuid[])'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
  foreach v_f in array array[
    'crm.llamadas_celular_resueltas_hoy_fn(integer)',
    'crm.actividades_con_llamada_celular_fn(uuid[])'] loop
    execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
    execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
  end loop;
end;
$permisos$;

-- ── 4. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz) is
  'Núcleo de «Qué pasó hoy» (F4-b, hallazgo 1): llamadas del celular recibidas el día de Lima de p_ahora que ya no están pendientes (registradas o descartadas con motivo), visibles para el actor (private.llamada_celular_visible), con el resultado de la actividad enlazada (y si se deshizo), la vía del enlace o el motivo del descarte. Más reciente primero, hasta p_limite. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.actividades_con_llamada_celular(uuid,uuid[]) is
  'Núcleo de la marca «Celular» de «¿Qué hice hoy?» (F4-b, hallazgo 3): de las actividades pedidas, las unidas a una llamada del celular visible para el actor, con la etiqueta del celular y la vía del enlace. Sin número ni datos del lead.';
comment on function crm.llamadas_celular_resueltas_hoy_fn(integer) is
  'PUERTA de «Qué pasó hoy» en la pestaña «Llamadas del celular» (F4-b): analista, supervisión y gerencia (42501 para los demás); el ámbito lo decide el servidor, como en la bandeja. p_limite de 1 a 200 (22023). Solo el día de hoy en Lima (decisión de Jhosep, 05/10). Devuelve un arreglo de filas.';
comment on function crm.actividades_con_llamada_celular_fn(uuid[]) is
  'PUERTA de la marca «Celular C1» en «¿Qué hice hoy?» (F4-b): de hasta 500 actividades que la pantalla ya tiene (22023 si son más), cuáles están unidas a una llamada del celular visible para quien pregunta, con la etiqueta y la vía. Lista vacía o nula → []. Analista, supervisión y gerencia (42501 para los demás). No cambia crm.registro_actividad_fn.';

-- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  for v_f in
    select * from (values
      ('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)', false, null),
      ('private.actividades_con_llamada_celular(uuid,uuid[])', false, null),
      ('crm.llamadas_celular_resueltas_hoy_fn(integer)', true, 'authenticated'),
      ('crm.actividades_con_llamada_celular_fn(uuid[])', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_LECTURAS_ANALISTA: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
