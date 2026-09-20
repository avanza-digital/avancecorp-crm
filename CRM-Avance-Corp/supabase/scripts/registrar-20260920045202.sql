-- Registra 20260920045202 (crm_tareas_pendientes_lead_embebido) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/tareas-lead-embebido/generar-registrador.mjs leyendo
-- la migración del archivo: no editar a mano; regenerar. Orden de la casa: PRIMERO
-- aplicar la migración con `db query --linked --file`, DESPUÉS este registrador.
do $reg_lead_emb$
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := $mig_lead_emb$-- ============================================================================
-- 20260920045202 — Tareas por cursor: el lead embebido completo (Fase 4b «sin topes»)
-- ============================================================================
-- POR QUÉ. La Fase 4 retira la foto inicial de leads del navegador. La Agenda
-- (y las Citas de gerencia en demo) sacaban de esa foto, por cada tarea, el
-- teléfono del lead (enlace de recordatorio por WhatsApp), su capital en juego
-- (monto y moneda) y su tenencia (vendedor y bandeja de supervisor, «el lead
-- manda» al agrupar por persona). `crm.tareas_pendientes_fn` (Fase 2,
-- 20260919235100) ya embebía nombre y etapa; sin lo demás, la Agenda sin foto
-- perdería el recordatorio, el capital y el agrupado fiel. Este cambio es
-- ADITIVO: el núcleo devuelve ocho claves más por fila y el payload conserva
-- `version: 1` (claves nuevas en la RESPUESTA; el front las trata como
-- opcionales, así que el orden de publicación es libre).
--
-- QUÉ CAMBIA (y qué no):
--   · `private.tareas_pendientes_core(int,timestamptz,uuid)` — `create or
--     replace` con el MISMO cuerpo de la Fase 2 más `lead_telefono`,
--     `lead_monto_estimado`, `lead_moneda`, `lead_vendedor_id`,
--     `lead_supervisor_id`, `lead_correo`, `lead_no_contactar` y
--     `lead_telefono_alternativo` (todas bajo `leads_select`, nulas si el lead
--     no es visible, igual que `lead_nombre`/`lead_etapa`). Las tres últimas
--     las piden las acciones de contacto de la tarjeta (la veta legal de «no
--     contactar» y el panel de resultado de llamada de Gestión Diaria). Sigue INVOKER, stable,
--     `search_path=""`, sin predicado de ámbito copiado y sin `count(`.
--   · `private.assert_tareas_pendientes_base()` — `create or replace` con las
--     ocho columnas nuevas de `crm.leads` en la comprobación de grants POR
--     COLUMNA (una columna sin grant haría fallar el núcleo con 42501 para
--     TODOS los actores, la Agenda entera caída; la base lo detecta antes).
--   · `private.assert_tareas_pendientes_mutantes()` — `create or replace` con
--     los 17 mutantes de la Fase 2 más uno para las ocho comprobaciones nuevas
--     (auditor-rls 20/09). Solo lo corre el banco.
--   · NO cambian la puerta `crm.tareas_pendientes_fn`, el índice ni el gate
--     `private.assert_tareas_pendientes()`: el gate vigila
--     FORMA y ACL del núcleo (no el md5 del cuerpo), y `create or replace`
--     conserva dueño y ACL. El registrador de esta versión vuelve a medir los
--     md5 de puerta y núcleo en producción.
--
-- PREFLIGHT (aborta si algo no es cierto): la base de la Fase 2 responde OK,
-- puerta y núcleo existen, el gate responde OK y `authenticated` ya puede leer
-- las ocho columnas nuevas (las lee hoy la cartera por cursor, INVOKER).
-- POSTFLIGHT: base nueva OK, gate OK, la primera fila del núcleo trae las 10
-- claves del lead, y los 4 gates del mundo SLA (los otros 4 controles del
-- servidor siguen en rojo por trabajos ajenos y no se invocan).
--
-- REVERSA: volver a crear `private.tareas_pendientes_core`,
-- `private.assert_tareas_pendientes_base` y `..._mutantes` con los cuerpos
-- EXACTOS de 20260919235100 (están en ese archivo; el gate sigue OK con ambos
-- cuerpos). El front tolera la ausencia de las claves nuevas. La fila de
-- `schema_migrations` de esta versión quedaría registrada con un cuerpo que ya
-- no sería el vivo (misma limitación que toda reversa de la casa: anotarlo).
-- ============================================================================

begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $preflight$
declare
  v_gate text;
begin
  perform private.assert_tareas_pendientes_base();
  if to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.tareas_pendientes_core(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.assert_tareas_pendientes()') is null then
    raise exception 'Las tareas por cursor (20260919235100) no estan instaladas: instalarlas antes';
  end if;
  v_gate := private.assert_tareas_pendientes();
  if v_gate not like 'OK:%' then
    raise exception 'El gate de las tareas por cursor no responde OK antes de tocar el nucleo: %', v_gate;
  end if;
  if not has_column_privilege('authenticated', 'crm.leads', 'telefono', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'monto_estimado', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'moneda', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'vendedor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'asignado_supervisor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'correo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'no_contactar', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'telefono_alternativo', 'SELECT') then
    raise exception 'authenticated no puede leer telefono/monto_estimado/moneda/vendedor_id/asignado_supervisor_id/correo/no_contactar/telefono_alternativo de crm.leads: el nucleo fallaria con 42501 para todos los actores';
  end if;
end;
$preflight$;

-- ── Base del trinquete (Fase 2) con las columnas nuevas ──────────────────────
create or replace function private.assert_tareas_pendientes_base() returns text
language plpgsql stable security definer set search_path='' as $function$
declare
  v_huella text;
  v_nombres text[];
begin
  if to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null then
    raise exception 'Faltan los ayudantes de autoridad del CRM';
  end if;
  -- La cadena puerta (invoker) → núcleo (private) corre como el actor.
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated no tiene USAGE sobre private: la cadena invoker no funcionaria';
  end if;
  if not has_table_privilege('authenticated', 'crm.tareas', 'SELECT') then
    raise exception 'authenticated no puede leer crm.tareas: el nucleo no devolveria nada';
  end if;
  -- Las policies solo cuentan si la RLS esta ACTIVA: desactivarla las deja en el
  -- catalogo sin aplicarse, y una puerta invoker expondria filas ajenas
  -- (revision de Codex del 19/09).
  if not exists (select 1 from pg_class c where c.oid = 'crm.tareas'::regclass and c.relrowsecurity)
     or not exists (select 1 from pg_class c where c.oid = 'crm.leads'::regclass and c.relrowsecurity) then
    raise exception 'RLS desactivada en crm.tareas o crm.leads: la puerta invoker expondria filas ajenas';
  end if;
  -- crm.leads tiene grants POR COLUMNA (regimen del 17/07/2026, CLAUDE.md del
  -- subproyecto): las ONCE que lee el nucleo (Fase 2 + Fase 4b), una a una.
  if not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'nombre_completo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'etapa', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'telefono', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'monto_estimado', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'moneda', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'vendedor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'asignado_supervisor_id', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'correo', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'no_contactar', 'SELECT')
     or not has_column_privilege('authenticated', 'crm.leads', 'telefono_alternativo', 'SELECT') then
    raise exception 'authenticated no puede leer alguna de las once columnas de crm.leads que embebe el nucleo (id, nombre_completo, etapa, telefono, monto_estimado, moneda, vendedor_id, asignado_supervisor_id, correo, no_contactar, telefono_alternativo)';
  end if;

  -- La policy de lectura de tareas, tal cual se auditó el 19/09/2026.
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'tareas_select';
  if v_huella is distinct from '073deaeb5700bac14209ec795b71567e' then
    raise exception 'tareas_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;

  -- El CONJUNTO de permisivas de lectura: exactamente una, solo para
  -- authenticated; y las dos restrictivas que acotan la lectura, presentes.
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.tareas'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['tareas_select']::text[] then
    raise exception 'crm.tareas tiene otras permisivas de lectura (%): re-auditar quien ve que',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  if exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'tareas_select'
      and pol.polroles is distinct from array['authenticated'::regrole::oid]
  ) then
    raise exception 'tareas_select ya no aplica solo a authenticated';
  end if;
  if not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.tareas'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) then
    raise exception 'Falta la restrictiva crm_actor_activo_gate en crm.tareas';
  end if;
  return 'OK: tareas_select sellada por huella y por conjunto, restrictiva del actor activo presente, grants de la cadena invoker presentes (once columnas de crm.leads)';
end;
$function$;
comment on function private.assert_tareas_pendientes_base() is
  'Base del trinquete de las tareas por cursor: ayudantes de autoridad, USAGE/grants de la cadena invoker (crm.tareas y las columnas id/nombre_completo/etapa/telefono/monto_estimado/moneda/vendedor_id/asignado_supervisor_id/correo/no_contactar/telefono_alternativo de crm.leads), y tareas_select sellada por md5 y por conjunto de permisivas, con la restrictiva crm_actor_activo_gate presente.';
revoke all on function private.assert_tareas_pendientes_base()
  from public, anon, authenticated, service_role;

-- ── CAPA 2 · NÚCLEO (mismo cuerpo de la Fase 2 + ocho claves del lead) ───────
create or replace function private.tareas_pendientes_core(
  p_limite integer,
  p_despues_de timestamptz,
  p_despues_id uuid
) returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with pagina as (
    select
      t.id, t.lead_id, t.perfil_id, t.vendedor_id, t.asignado_supervisor_id,
      t.tipo, t.titulo, t.nota, t.vence_en, t.duracion_min, t.estado,
      t.modalidad_reunion, t.ubicacion_reunion, t.enlace_reunion,
      t.resultado_reunion, t.motivo_no_realizada, t.detalle_cierre_reunion,
      t.confirmada_en, t.reagendada_de, t.reprogramaciones, t.activo, t.creado_en,
      l.nombre_completo as lead_nombre,
      l.etapa as lead_etapa,
      l.telefono as lead_telefono,
      l.monto_estimado as lead_monto_estimado,
      l.moneda as lead_moneda,
      l.vendedor_id as lead_vendedor_id,
      l.asignado_supervisor_id as lead_supervisor_id,
      l.correo as lead_correo,
      l.no_contactar as lead_no_contactar,
      l.telefono_alternativo as lead_telefono_alternativo
    from crm.tareas t
    left join crm.leads l on l.id = t.lead_id
    where t.estado = 'pendiente'
      and t.activo
      and (t.lead_id is not null or t.perfil_id is not null)
      and (p_despues_de is null or (t.vence_en, t.id) > (p_despues_de, p_despues_id))
    order by t.vence_en asc, t.id asc
    limit p_limite
  )
  select jsonb_build_object(
    'version', 1,
    'items', coalesce((
      select jsonb_agg(to_jsonb(pg) order by pg.vence_en asc, pg.id asc)
      from pagina pg
    ), '[]'::jsonb)
  );
$function$;

comment on function private.tareas_pendientes_core(integer, timestamptz, uuid) is
  'NÚCLEO: página keyset (vence_en asc, id asc) de las tareas pendientes vivas ancladas a un lead o a un perfil, bajo la RLS del actor, con el lead embebido (nombre, etapa, telefono, monto_estimado, moneda, vendedor_id, supervisor, correo, no_contactar, telefono_alternativo; nulos si el lead no es visible). Puro: sin auth ni autoridad propia.';

-- `create or replace` conserva dueño y ACL; se reafirman para que el archivo
-- sea la verdad completa de la ACL {postgres, authenticated}.
revoke all on function private.tareas_pendientes_core(integer, timestamptz, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.tareas_pendientes_core(integer, timestamptz, uuid)
  to authenticated;

-- ── Mutantes del trinquete (los 17 de la Fase 2 + 1 para las columnas nuevas) ──
-- SOLO PARA EL BANCO (lo llama test-rls por la vía fuera de banda). Mismo
-- corredor que la Fase 2 (subtransacción por mutante; DETECTADO / NO DETECTADO /
-- NO APLICADO). El mutante 18 prueba las ocho comprobaciones nuevas de la base:
-- deja a authenticated SOLO las tres columnas de la Fase 2 (revoca la tabla y
-- concede por columna id/nombre_completo/etapa); el gate debe gritar por las
-- ocho restantes (un revoke de una columna suelta NO serviría: mientras exista
-- el grant de TABLA, has_column_privilege sigue siendo true; auditor-rls 20/09).
create or replace function private.assert_tareas_pendientes_mutantes() returns text
language plpgsql volatile security definer set search_path='' as $function$
declare
  v_detectados integer := 0;
  v_mutante text;
  v_nombre text;
  v_ddl text;
  -- «nombre|DDL». Ningún DDL lleva «|».
  v_mutantes constant text[] := array[
    'la puerta pasa a DEFINER|alter function crm.tareas_pendientes_fn(integer, timestamptz, uuid) security definer',
    'el nucleo pasa a DEFINER|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) security definer',
    'tareas_select se abre (cambia la huella)|alter policy tareas_select on crm.tareas using (true)',
    'una permisiva NUEVA en crm.tareas (la huella de la vieja no cambia)|create policy tareas_mutante_cursor on crm.tareas for select to authenticated using (true)',
    'la puerta pierde su guardia de admision|create or replace function crm.tareas_pendientes_fn(p_limite integer default 500, p_despues_de timestamptz default null, p_despues_id uuid default null) returns jsonb language sql stable security invoker set search_path to '''' as $b$ select private.tareas_pendientes_core(p_limite, p_despues_de, p_despues_id) $b$',
    'la puerta conserva el nombre de la guardia solo en un comentario|create or replace function crm.tareas_pendientes_fn(p_limite integer default 500, p_despues_de timestamptz default null, p_despues_id uuid default null) returns jsonb language sql stable security invoker set search_path to '''' as $b$ /* puede_acceder_crm 42501 */ select private.tareas_pendientes_core(p_limite, p_despues_de, p_despues_id) $b$',
    'la puerta se concede a anon|grant execute on function crm.tareas_pendientes_fn(integer, timestamptz, uuid) to anon',
    'el nucleo se concede a anon|grant execute on function private.tareas_pendientes_core(integer, timestamptz, uuid) to anon',
    'el nucleo pierde el search_path vacio|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) reset search_path',
    'el nucleo pasa a VOLATILE|alter function private.tareas_pendientes_core(integer, timestamptz, uuid) volatile',
    'tareas_select deja de ser solo para authenticated|alter policy tareas_select on crm.tareas to public',
    'desaparece la restrictiva del actor activo|drop policy crm_actor_activo_gate on crm.tareas',
    'authenticated pierde la lectura de crm.leads (el revoke de TABLA arrastra las columnas; el bloque lo deshace)|revoke select on table crm.leads from authenticated',
    'authenticated pierde la lectura de crm.tareas|revoke select on table crm.tareas from authenticated',
    'authenticated pierde USAGE sobre private|revoke usage on schema private from authenticated',
    'crm.tareas queda sin RLS (las policies siguen ahi pero no se aplican)|alter table crm.tareas disable row level security',
    'crm.leads queda sin RLS|alter table crm.leads disable row level security',
    'crm.leads solo concede a authenticated las tres columnas de la Fase 2 (el nucleo lee once)|do $m$ begin revoke select on table crm.leads from authenticated; grant select (id, nombre_completo, etapa) on crm.leads to authenticated; end $m$'
  ];
begin
  foreach v_mutante in array v_mutantes loop
    v_nombre := split_part(v_mutante, '|', 1);
    v_ddl := split_part(v_mutante, '|', 2);
    begin
      execute v_ddl;
      begin
        perform private.assert_tareas_pendientes();
      exception when others then
        raise exception 'MUTANTE DETECTADO';
      end;
      raise exception 'MUTANTE NO DETECTADO: % paso el gate', v_nombre;
    exception when others then
      if sqlerrm = 'MUTANTE DETECTADO' then
        v_detectados := v_detectados + 1;
      elsif sqlerrm like 'MUTANTE NO DETECTADO%' then
        raise;
      else
        raise exception 'MUTANTE NO APLICADO (%): %', v_nombre, sqlerrm;
      end if;
    end;
  end loop;
  return format('OK: %s mutantes detectados por private.assert_tareas_pendientes()', v_detectados);
end;
$function$;
comment on function private.assert_tareas_pendientes_mutantes() is
  'Mutantes del trinquete de las tareas por cursor (solo banco): los 17 de la Fase 2 más uno para las once columnas de crm.leads que lee el núcleo; cada mutación vive en una subtransacción que se deshace; distingue detectado / no detectado / no aplicado y falla en los dos últimos.';
revoke all on function private.assert_tareas_pendientes_mutantes()
  from public, anon, authenticated, service_role;

do $postflight$
declare
  v_gate text;
  v_muestra jsonb;
begin
  perform private.assert_tareas_pendientes_base();
  v_gate := private.assert_tareas_pendientes();
  if v_gate not like 'OK:%' then
    raise exception 'El gate de las tareas por cursor no responde OK tras el cambio: %', v_gate;
  end if;
  -- La primera fila (si hay alguna pendiente) trae las diez claves del lead:
  -- `to_jsonb` conserva las nulas, asi que la ausencia de una clave delata un
  -- cuerpo distinto del publicado.
  v_muestra := private.tareas_pendientes_core(1, null, null) -> 'items' -> 0;
  if v_muestra is not null and not (v_muestra ?& array[
       'lead_nombre', 'lead_etapa', 'lead_telefono', 'lead_monto_estimado',
       'lead_moneda', 'lead_vendedor_id', 'lead_supervisor_id', 'lead_correo', 'lead_no_contactar',
       'lead_telefono_alternativo']) then
    -- Solo las claves que faltan: la fila es una tarea real (PII), nunca al log.
    raise exception 'El nucleo no embebe estas claves del lead: %', (
      select string_agg(k, ',') from unnest(array[
        'lead_nombre', 'lead_etapa', 'lead_telefono', 'lead_monto_estimado',
        'lead_moneda', 'lead_vendedor_id', 'lead_supervisor_id', 'lead_correo', 'lead_no_contactar',
        'lead_telefono_alternativo']) k where not (v_muestra ? k));
  end if;
  -- Los gates del mundo SLA (que también lee crm.tareas); los otros cuatro
  -- controles del servidor siguen en rojo por trabajos ajenos y no se invocan.
  perform private.assert_sla_nucleo();
  perform private.assert_sla_operacion();
  perform private.assert_sla_comandos();
  perform private.assert_sla_avisos();
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig_lead_emb$;

  -- 1) PIN: lo que la migración hizo ES verdad — puerta, núcleo y gate existen
  --    con la definición publicada (md5 medidos en producción) y el gate propio
  --    responde OK en ESTA base.
  if to_regprocedure('crm.tareas_pendientes_fn(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.tareas_pendientes_core(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.assert_tareas_pendientes()') is null
     or md5(pg_get_functiondef('crm.tareas_pendientes_fn(integer,timestamptz,uuid)'::regprocedure)) is distinct from '5edd699559108383a0e44a90b51d9ad6'
     or md5(pg_get_functiondef('private.tareas_pendientes_core(integer,timestamptz,uuid)'::regprocedure)) is distinct from '699288313e80228963b92b8a56c3fe5c' then
    raise exception 'registrar lead embebido: la migración 20260920045202 no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  if private.assert_tareas_pendientes() not like 'OK:%' then
    raise exception 'registrar lead embebido: el gate propio no responde OK';
  end if;

  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920045202' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar lead embebido: la versión 20260920045202 existe con OTRO cuerpo — investigar antes de tocar';
  end if;

  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260920045202', 'crm_tareas_pendientes_lead_embebido', array[v_cuerpo])
  on conflict (version) do nothing;

  -- 4) RELECTURA fail-closed: la fila EXACTA, o se cae la transacción entera.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '20260920045202' and name = 'crm_tareas_pendientes_lead_embebido'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar lead embebido: la relectura no encontró la fila exacta';
  end if;
end $reg_lead_emb$;
