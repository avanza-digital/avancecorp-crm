-- REGISTRO en supabase_migrations.schema_migrations de 20261005224330_crm_llamadas_celular_resueltas_paginadas (novena: «Qué pasó hoy» paginada y por la hora de resolución).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 a7d269eb26268d0f442c74a20bb9f53d, con finales de línea LF:
-- correrlo desde un checkout LF, como la Mac de Miguel; en una copia de Windows con CRLF el md5 no coincide y se
-- niega). La ÚLTIMA sentencia, después del commit, es una fila de veredicto: `db query --linked` no muestra los
-- raise notice (corrección de Miguel al #173; molde: scripts/anexo-cronograma/registrar-20260929151350.sql).
-- En una copia Docker se corre con `psql -f`: `db query --local --file` falla con varias sentencias.
-- Generado el 05/10/2026 desde la migración en LF. Patrón: los registrar-*.sql de esta carpeta.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
begin
  if (
    to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is not null
    and to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)') is not null
    and to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is null
    and to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is null
    and to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is not null
    and to_regclass('crm.llamadas_celular_eventos_descartado_en_idx') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261005224330 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261005224330' and (coalesce(name, '') <> 'crm_llamadas_celular_resueltas_paginadas' or statements is distinct from array[$mig$-- Llamadas desde el celular · novena migración (F4-b): «Qué pasó hoy» por páginas y por la hora en que se RESOLVIÓ cada
-- llamada. Responde a la revisión de Miguel en el #195 (05/10/2026, 22:00 UTC): la lectura de la octava devolvía hasta
-- 200 filas sin cursor y llamaba «hoy» a lo RECIBIDO hoy. Plan: docs/plans/llamadas-celular/F4B-PLAN-CORTO.md (B2,
-- enmienda del 05/10). La octava no se edita: esta la enmienda.
--
-- Decisiones de Jhosep (05/10/2026):
--   · Paginar como la bandeja: {filas, siguiente} con cursor (resuelto_en, evento_id); límite de 1 a 200, 50 por defecto.
--   · «Hoy» = lo RESUELTO hoy en Lima, aunque la llamada sea de ayer. Registrada: cuando su enlace nació o pasó al
--     resultado corregido tras un Deshacer (crm.llamadas_celular_enlaces.actualizado_en, que sella el trigger del
--     candado). Descartada: crm.llamadas_celular_eventos.descartado_en. La cifra del día no cambia (cuenta por la fecha
--     del resultado).
--   · Dos índices, para que la lectura no recorra todos los enlaces: las registradas se conservan siempre.
--   · Límite conocido (anotado, no se cubre): una llamada registrada AYER cuyo resultado se deshace HOY y no se vuelve a
--     registrar no sale en «Qué pasó hoy» (Deshacer solo marca la actividad, no toca el enlace). La marca «Celular» y el
--     historial del lead sí la muestran.
--
-- Qué hace:
--   1. Retira la lectura de la octava (crm.llamadas_celular_resueltas_hoy_fn(integer) y su núcleo): con las dos firmas,
--      una llamada con solo p_limite sería ambigua en PostgREST. No tiene consumidores: la octava no está publicada y la
--      pantalla todavía no la llama. Precedente: la quinta retiró la bandeja duplicada.
--   2. La crea de nuevo con cursor: crm.llamadas_celular_resueltas_hoy_fn(p_limite, p_antes_resuelto_en, p_antes_id).
--   3. Índices: enlaces por (actualizado_en, evento_id) y eventos descartados por (descartado_en, id); este último le
--      sirve también a la purga de descartados, que filtra por lo mismo.
--   La marca «Celular» (crm.actividades_con_llamada_celular_fn) no cambia.
--
-- Capas (estándar de 4 capas): como la octava, puerta DEFINER en crm (EXECUTE solo authenticated) que valida y delega en
-- un núcleo INVOKER de private sin EXECUTE para nadie. Excepción single-tenant (F2.3.3): sin columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-resueltas-paginadas.sql (quita la lectura nueva y los dos índices y
-- repone la de la octava tal cual; sin datos, corre en cualquier momento). Verificación: npm run test:llamadas:local
-- (pasada 16: oráculo tests/llamadas-celular/oraculo-resueltas-paginadas.sql, huella del catálogo, reversa y mutantes)
-- y el tramo de F4-b de testLlamadasCelular en test-rls.mjs con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is not null
     or to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is not null
     or to_regclass('crm.llamadas_celular_eventos_descartado_en_idx') is not null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is null
     or to_regprocedure('crm.actividades_con_llamada_celular_fn(uuid[])') is null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: falta la octava (20261005201010)';
  end if;
end;
$precondicion$;

-- ── 1. Retirar la lectura de la octava ───────────────────────────────────────────────────────
drop function crm.llamadas_celular_resueltas_hoy_fn(integer);
drop function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz);

-- ── 2. Índices ───────────────────────────────────────────────────────────────────────────────
-- Registradas resueltas en un día: el enlace nace con actualizado_en = creado_en y el trigger lo vuelve a sellar al
-- pasar al resultado corregido.
create index llamadas_celular_enlaces_actualizado_idx
  on crm.llamadas_celular_enlaces (actualizado_en, evento_id);
-- Descartadas en un día (y la purga de descartados).
create index llamadas_celular_eventos_descartado_en_idx
  on crm.llamadas_celular_eventos (descartado_en, id) where atencion = 'descartado_con_motivo';

-- ── 3. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────

-- «Qué pasó hoy»: llamadas resueltas hoy (Lima), visibles para el actor, de la resuelta más tarde a la más temprana.
-- Cada rama aplica su ventana del día y el cursor sobre su propio momento; una llamada está en una sola rama.
create function private.llamadas_celular_resueltas_hoy(
  p_actor uuid, p_limite integer, p_ahora timestamptz, p_antes_resuelto_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with dia as (
    select (pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima') as desde
  ), resueltas as (
    -- Registradas: cuando su enlace nació o pasó al resultado corregido.
    select en.evento_id as id, en.actualizado_en as resuelto_en
    from dia, crm.llamadas_celular_enlaces en
    join crm.llamadas_celular_eventos e on e.id = en.evento_id
    where e.atencion = 'registrado'
      and en.actualizado_en >= dia.desde and en.actualizado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (en.actualizado_en, en.evento_id) < (p_antes_resuelto_en, p_antes_id))
    union all
    -- Descartadas: cuando se descartaron.
    select e.id, e.descartado_en
    from dia, crm.llamadas_celular_eventos e
    where e.atencion = 'descartado_con_motivo'
      and e.descartado_en >= dia.desde and e.descartado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (e.descartado_en, e.id) < (p_antes_resuelto_en, p_antes_id))
  ), limitada as (
    select r.resuelto_en, e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.atencion, e.lead_id, e.analista_id,
           e.motivo_descarte, e.motivo_descarte_detalle, l.nombre_completo as lead_nombre, ca.etiqueta,
           en.actividad_id, en.via, a.metadata ->> 'resultado' as resultado, (a.metadata ? 'deshecho_en') as deshecho
    from resueltas r
    join crm.llamadas_celular_eventos e on e.id = r.id
    left join crm.leads l on l.id = e.lead_id
    left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
    left join crm.llamadas_celular_enlaces en on en.evento_id = e.id
    left join crm.actividades a on a.id = en.actividad_id
    where private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by r.resuelto_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.resuelto_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'resuelto_en', p.resuelto_en, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'atencion', p.atencion, 'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor, 'etiqueta', p.etiqueta,
               'actividad_id', p.actividad_id, 'resultado', p.resultado, 'deshecho', coalesce(p.deshecho, false),
               'via', p.via, 'motivo_descarte', p.motivo_descarte, 'motivo_descarte_detalle', p.motivo_descarte_detalle)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('resuelto_en', u.resuelto_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

-- ── 4. Puerta (DEFINER, EXECUTE solo authenticated) ──────────────────────────────────────────
create function crm.llamadas_celular_resueltas_hoy_fn(
  p_limite integer default 50, p_antes_resuelto_en timestamptz default null, p_antes_id uuid default null)
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
  if (p_antes_resuelto_en is null) <> (p_antes_id is null) then
    raise exception using errcode = '22023', message = 'El cursor lleva resuelto_en y evento_id juntos';
  end if;
  return private.llamadas_celular_resueltas_hoy(v_actor, p_limite, pg_catalog.now(), p_antes_resuelto_en, p_antes_id);
end;
$function$;

-- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
revoke all on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) to authenticated;

-- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid) is
  'Núcleo de «Qué pasó hoy» (F4-b, novena): llamadas del celular RESUELTAS el día de Lima de p_ahora —registradas (hora del enlace: actualizado_en, que se vuelve a sellar al pasar al resultado corregido) o descartadas con motivo (descartado_en)—, aunque se hayan recibido antes, visibles para el actor (private.llamada_celular_visible), con el resultado de la actividad enlazada (y si se deshizo), la vía del enlace o el motivo del descarte. Orden (resuelto_en, evento_id) descendente; página de p_limite con cursor estricto. Devuelve {filas, siguiente}. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) is
  'PUERTA de «Qué pasó hoy» en la pestaña «Celular» (F4-b, novena): lo resuelto hoy en Lima, aunque la llamada sea de ayer (decisión de Jhosep, 05/10). Analista, supervisión y gerencia (42501 para los demás); el ámbito lo decide el servidor, como en la bandeja. Paginada como la bandeja: p_limite de 1 a 200 (22023); el cursor (p_antes_resuelto_en, p_antes_id) va completo o no va (22023) y se devuelve TAL CUAL lo dio «siguiente» (texto con microsegundos: pasarlo por Date pierde filas empatadas). Devuelve {filas, siguiente}; siguiente es null en la última página.';

-- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is not null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is not null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: sigue la lectura de la octava (dos firmas: PostgREST no sabría cuál llamar)';
  end if;
  if to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is null
     or (select i.indpred is null from pg_catalog.pg_index i
         where i.indexrelid = to_regclass('crm.llamadas_celular_eventos_descartado_en_idx')) is distinct from false then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: faltan los índices (el de descartadas, parcial)';
  end if;
  for v_f in
    select * from (values
      ('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)', false, null),
      ('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261005224330 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261005224330', 'crm_llamadas_celular_resueltas_paginadas', array[$mig$-- Llamadas desde el celular · novena migración (F4-b): «Qué pasó hoy» por páginas y por la hora en que se RESOLVIÓ cada
-- llamada. Responde a la revisión de Miguel en el #195 (05/10/2026, 22:00 UTC): la lectura de la octava devolvía hasta
-- 200 filas sin cursor y llamaba «hoy» a lo RECIBIDO hoy. Plan: docs/plans/llamadas-celular/F4B-PLAN-CORTO.md (B2,
-- enmienda del 05/10). La octava no se edita: esta la enmienda.
--
-- Decisiones de Jhosep (05/10/2026):
--   · Paginar como la bandeja: {filas, siguiente} con cursor (resuelto_en, evento_id); límite de 1 a 200, 50 por defecto.
--   · «Hoy» = lo RESUELTO hoy en Lima, aunque la llamada sea de ayer. Registrada: cuando su enlace nació o pasó al
--     resultado corregido tras un Deshacer (crm.llamadas_celular_enlaces.actualizado_en, que sella el trigger del
--     candado). Descartada: crm.llamadas_celular_eventos.descartado_en. La cifra del día no cambia (cuenta por la fecha
--     del resultado).
--   · Dos índices, para que la lectura no recorra todos los enlaces: las registradas se conservan siempre.
--   · Límite conocido (anotado, no se cubre): una llamada registrada AYER cuyo resultado se deshace HOY y no se vuelve a
--     registrar no sale en «Qué pasó hoy» (Deshacer solo marca la actividad, no toca el enlace). La marca «Celular» y el
--     historial del lead sí la muestran.
--
-- Qué hace:
--   1. Retira la lectura de la octava (crm.llamadas_celular_resueltas_hoy_fn(integer) y su núcleo): con las dos firmas,
--      una llamada con solo p_limite sería ambigua en PostgREST. No tiene consumidores: la octava no está publicada y la
--      pantalla todavía no la llama. Precedente: la quinta retiró la bandeja duplicada.
--   2. La crea de nuevo con cursor: crm.llamadas_celular_resueltas_hoy_fn(p_limite, p_antes_resuelto_en, p_antes_id).
--   3. Índices: enlaces por (actualizado_en, evento_id) y eventos descartados por (descartado_en, id); este último le
--      sirve también a la purga de descartados, que filtra por lo mismo.
--   La marca «Celular» (crm.actividades_con_llamada_celular_fn) no cambia.
--
-- Capas (estándar de 4 capas): como la octava, puerta DEFINER en crm (EXECUTE solo authenticated) que valida y delega en
-- un núcleo INVOKER de private sin EXECUTE para nadie. Excepción single-tenant (F2.3.3): sin columna de tenant.
-- Reversión: ../scripts/llamadas-celular/reversa-resueltas-paginadas.sql (quita la lectura nueva y los dos índices y
-- repone la de la octava tal cual; sin datos, corre en cualquier momento). Verificación: npm run test:llamadas:local
-- (pasada 16: oráculo tests/llamadas-celular/oraculo-resueltas-paginadas.sql, huella del catálogo, reversa y mutantes)
-- y el tramo de F4-b de testLlamadasCelular en test-rls.mjs con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is not null
     or to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is not null
     or to_regclass('crm.llamadas_celular_eventos_descartado_en_idx') is not null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: los objetos ya existen; no se sobrescriben';
  end if;
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is null
     or to_regprocedure('crm.actividades_con_llamada_celular_fn(uuid[])') is null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: falta la octava (20261005201010)';
  end if;
end;
$precondicion$;

-- ── 1. Retirar la lectura de la octava ───────────────────────────────────────────────────────
drop function crm.llamadas_celular_resueltas_hoy_fn(integer);
drop function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz);

-- ── 2. Índices ───────────────────────────────────────────────────────────────────────────────
-- Registradas resueltas en un día: el enlace nace con actualizado_en = creado_en y el trigger lo vuelve a sellar al
-- pasar al resultado corregido.
create index llamadas_celular_enlaces_actualizado_idx
  on crm.llamadas_celular_enlaces (actualizado_en, evento_id);
-- Descartadas en un día (y la purga de descartados).
create index llamadas_celular_eventos_descartado_en_idx
  on crm.llamadas_celular_eventos (descartado_en, id) where atencion = 'descartado_con_motivo';

-- ── 3. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────

-- «Qué pasó hoy»: llamadas resueltas hoy (Lima), visibles para el actor, de la resuelta más tarde a la más temprana.
-- Cada rama aplica su ventana del día y el cursor sobre su propio momento; una llamada está en una sola rama.
create function private.llamadas_celular_resueltas_hoy(
  p_actor uuid, p_limite integer, p_ahora timestamptz, p_antes_resuelto_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with dia as (
    select (pg_catalog.date_trunc('day', p_ahora at time zone 'America/Lima') at time zone 'America/Lima') as desde
  ), resueltas as (
    -- Registradas: cuando su enlace nació o pasó al resultado corregido.
    select en.evento_id as id, en.actualizado_en as resuelto_en
    from dia, crm.llamadas_celular_enlaces en
    join crm.llamadas_celular_eventos e on e.id = en.evento_id
    where e.atencion = 'registrado'
      and en.actualizado_en >= dia.desde and en.actualizado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (en.actualizado_en, en.evento_id) < (p_antes_resuelto_en, p_antes_id))
    union all
    -- Descartadas: cuando se descartaron.
    select e.id, e.descartado_en
    from dia, crm.llamadas_celular_eventos e
    where e.atencion = 'descartado_con_motivo'
      and e.descartado_en >= dia.desde and e.descartado_en < dia.desde + interval '1 day'
      and (p_antes_resuelto_en is null or (e.descartado_en, e.id) < (p_antes_resuelto_en, p_antes_id))
  ), limitada as (
    select r.resuelto_en, e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.atencion, e.lead_id, e.analista_id,
           e.motivo_descarte, e.motivo_descarte_detalle, l.nombre_completo as lead_nombre, ca.etiqueta,
           en.actividad_id, en.via, a.metadata ->> 'resultado' as resultado, (a.metadata ? 'deshecho_en') as deshecho
    from resueltas r
    join crm.llamadas_celular_eventos e on e.id = r.id
    left join crm.leads l on l.id = e.lead_id
    left join crm.celulares_asignaciones ca on ca.id = e.asignacion_id
    left join crm.llamadas_celular_enlaces en on en.evento_id = e.id
    left join crm.actividades a on a.id = en.actividad_id
    where private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by r.resuelto_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.resuelto_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'resuelto_en', p.resuelto_en, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'atencion', p.atencion, 'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor, 'etiqueta', p.etiqueta,
               'actividad_id', p.actividad_id, 'resultado', p.resultado, 'deshecho', coalesce(p.deshecho, false),
               'via', p.via, 'motivo_descarte', p.motivo_descarte, 'motivo_descarte_detalle', p.motivo_descarte_detalle)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('resuelto_en', u.resuelto_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

-- ── 4. Puerta (DEFINER, EXECUTE solo authenticated) ──────────────────────────────────────────
create function crm.llamadas_celular_resueltas_hoy_fn(
  p_limite integer default 50, p_antes_resuelto_en timestamptz default null, p_antes_id uuid default null)
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
  if (p_antes_resuelto_en is null) <> (p_antes_id is null) then
    raise exception using errcode = '22023', message = 'El cursor lleva resuelto_en y evento_id juntos';
  end if;
  return private.llamadas_celular_resueltas_hoy(v_actor, p_limite, pg_catalog.now(), p_antes_resuelto_en, p_antes_id);
end;
$function$;

-- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
revoke all on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) to authenticated;

-- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid) is
  'Núcleo de «Qué pasó hoy» (F4-b, novena): llamadas del celular RESUELTAS el día de Lima de p_ahora —registradas (hora del enlace: actualizado_en, que se vuelve a sellar al pasar al resultado corregido) o descartadas con motivo (descartado_en)—, aunque se hayan recibido antes, visibles para el actor (private.llamada_celular_visible), con el resultado de la actividad enlazada (y si se deshizo), la vía del enlace o el motivo del descarte. Orden (resuelto_en, evento_id) descendente; página de p_limite con cursor estricto. Devuelve {filas, siguiente}. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid) is
  'PUERTA de «Qué pasó hoy» en la pestaña «Celular» (F4-b, novena): lo resuelto hoy en Lima, aunque la llamada sea de ayer (decisión de Jhosep, 05/10). Analista, supervisión y gerencia (42501 para los demás); el ámbito lo decide el servidor, como en la bandeja. Paginada como la bandeja: p_limite de 1 a 200 (22023); el cursor (p_antes_resuelto_en, p_antes_id) va completo o no va (22023) y se devuelve TAL CUAL lo dio «siguiente» (texto con microsegundos: pasarlo por Date pierde filas empatadas). Devuelve {filas, siguiente}; siguiente es null en la última página.';

-- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is not null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is not null then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: sigue la lectura de la octava (dos firmas: PostgREST no sabría cuál llamar)';
  end if;
  if to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is null
     or (select i.indpred is null from pg_catalog.pg_index i
         where i.indexrelid = to_regclass('crm.llamadas_celular_eventos_descartado_en_idx')) is distinct from false then
    raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: faltan los índices (el de descartadas, parcial)';
  end if;
  for v_f in
    select * from (values
      ('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)', false, null),
      ('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)', true, 'authenticated')
    ) as f(firma, definer, rol)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % debería ser %', v_f.firma,
        case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
        and a.grantee <> p.proowner
        and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
      or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_RESUELTAS_PAGINADAS: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261005224330' and name = 'crm_llamadas_celular_resueltas_paginadas' and cardinality(statements) = 1
                   and md5(statements[1]) = 'a7d269eb26268d0f442c74a20bb9f53d') then
    raise exception 'REGISTRO: la fila 20261005224330 / crm_llamadas_celular_resueltas_paginadas no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261005224330 / crm_llamadas_celular_resueltas_paginadas (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261005224330' and name = 'crm_llamadas_celular_resueltas_paginadas' and md5(statements[1]) = 'a7d269eb26268d0f442c74a20bb9f53d') = 1
       as veredicto_registro_20261005224330;
