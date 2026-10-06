-- REGISTRO en supabase_migrations.schema_migrations de 20261006150154_crm_llamadas_celular_bandeja_con_origen (décima: el id de origen en la bandeja y el detalle).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 c76e6dae55d7983a1daabccf2321218d, con finales de línea LF:
-- correrlo desde un checkout LF, como la Mac de Miguel; en una copia de Windows con CRLF el md5 no coincide y se
-- niega). La ÚLTIMA sentencia, después del commit, es una fila de veredicto: `db query --linked` no muestra los
-- raise notice (corrección de Miguel al #173; molde: scripts/anexo-cronograma/registrar-20260929151350.sql).
-- En una copia Docker se corre con `psql -f`: `db query --local --file` falla con varias sentencias.
-- Generado el 06/10/2026 desde la migración en LF. Patrón: los registrar-*.sql de esta carpeta.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_llamadas_celular_registro'));
do $chk$
begin
  if (
    pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), '''evento_origen_id''') > 0
    and pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), '''evento_origen_id''') > 0
  ) is not true then
    raise exception 'REGISTRO: la migración 20261006150154 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261006150154' and (coalesce(name, '') <> 'crm_llamadas_celular_bandeja_con_origen' or statements is distinct from array[$mig$-- Llamadas desde el celular · décima migración (F4-b): el id de origen del celular en la bandeja y en el detalle.
-- Hallazgo del análisis de F4-c/F4-d (06/10/2026, verificado): private.llamadas_celular_bandeja (20261001212258) y
-- private.llamada_celular_detalle (20261001160219) no devuelven evento_origen_id, así que «Registrar resultado» desde la
-- pestaña «Celular» no puede llamar a la v5 con el id: cae a la v4 y la llamada queda pendiente (solo se uniría a mano).
-- Decisión de Jhosep (06/10): arreglarlo con una migración pequeña en el #198.
--
-- Qué hace: create or replace de los DOS núcleos con la misma firma (las puertas crm.llamadas_celular_bandeja_fn y
-- crm.llamada_celular_detalle_fn no cambian: ni firma, ni roles, ni permisos; create or replace conserva los del
-- núcleo). Solo agrega 'evento_origen_id' a cada fila; el resto del cuerpo es el vigente, copiado del blob de git. El id
-- de origen no es dato personal (C<n>-<segundos>; la hora ya viaja en ocurrio_en).
--
-- Capas: núcleos INVOKER en private sin EXECUTE para nadie, como antes. Single-tenant (F2.3.3).
-- Reversión: ../scripts/llamadas-celular/reversa-bandeja-con-origen.sql (repone los dos cuerpos y sus COMMENT tal cual;
-- sin datos). Verificación: npm run test:llamadas:local (pasada 17) y el tramo de F4-b de testLlamadasCelular.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is null then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: falta la novena (20261005224330)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), 'evento_origen_id') > 0 then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. Bandeja: cada fila trae su id de origen ───────────────────────────────────────────────
create or replace function private.llamadas_celular_bandeja(
  p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with limitada as (
    select e.id, e.evento_origen_id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
           e.duracion_seg, e.identificacion, e.atencion, e.lead_id, e.analista_id,
           l.nombre_completo as lead_nombre
    from crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
      and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.recibido_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    -- La forma de fila de F2-c más el id de origen (décima): con él, registrar desde la pestaña une la llamada.
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'evento_origen_id', p.evento_origen_id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
               'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
               'atencion', private.llamada_celular_atencion_efectiva(p_actor, p.atencion, p.identificacion, p.lead_id),
               'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('recibido_en', u.recibido_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

-- ── 2. Detalle: también ──────────────────────────────────────────────────────────────────────
create or replace function private.llamada_celular_detalle(p_actor uuid, p_evento_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_deshecha boolean;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id;
  if found and v_enl.actividad_id is not null then
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'evento_id', v_ev.id, 'evento_origen_id', v_ev.evento_origen_id, 'recibido_en', v_ev.recibido_en, 'ocurrio_en', v_ev.ocurrio_en,
    'numero', v_ev.numero_canonico, 'direccion', v_ev.direccion, 'estado_tecnico', v_ev.estado_tecnico,
    'duracion_seg', v_ev.duracion_seg, 'calidad', v_ev.calidad, 'identificacion', v_ev.identificacion,
    'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id),
    'lead_id', v_ev.lead_id, 'metodo_asociacion', v_ev.metodo_asociacion, 'analista_id', v_ev.analista_id,
    'motivo_descarte', v_ev.motivo_descarte, 'motivo_descarte_detalle', v_ev.motivo_descarte_detalle,
    'actividad_id', v_enl.actividad_id,
    -- Decisión 4: los efectos deshechos se DERIVAN del resultado, no se copian.
    'efectos_anulados', coalesce(v_deshecha, false));
end;
$function$;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva y el id de origen del celular (evento_origen_id, desde 20261006150154: con él la pantalla registra por la v5 y la llamada queda unida). DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.llamada_celular_detalle(uuid,uuid) is
  'Detalle de una llamada visible para el actor, con su id de origen (evento_origen_id, desde 20261006150154), su enlace y efectos_anulados derivado de metadata.deshecho_en del resultado (decisión 4).';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), '''evento_origen_id''') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), '''evento_origen_id''') = 0 then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: la bandeja o el detalle siguen sin evento_origen_id';
  end if;
  for v_f in
    select * from (values
      ('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'),
      ('private.llamada_celular_detalle(uuid,uuid)')
    ) as f(firma)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % debería ser SECURITY INVOKER', v_f.firma;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261006150154 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261006150154', 'crm_llamadas_celular_bandeja_con_origen', array[$mig$-- Llamadas desde el celular · décima migración (F4-b): el id de origen del celular en la bandeja y en el detalle.
-- Hallazgo del análisis de F4-c/F4-d (06/10/2026, verificado): private.llamadas_celular_bandeja (20261001212258) y
-- private.llamada_celular_detalle (20261001160219) no devuelven evento_origen_id, así que «Registrar resultado» desde la
-- pestaña «Celular» no puede llamar a la v5 con el id: cae a la v4 y la llamada queda pendiente (solo se uniría a mano).
-- Decisión de Jhosep (06/10): arreglarlo con una migración pequeña en el #198.
--
-- Qué hace: create or replace de los DOS núcleos con la misma firma (las puertas crm.llamadas_celular_bandeja_fn y
-- crm.llamada_celular_detalle_fn no cambian: ni firma, ni roles, ni permisos; create or replace conserva los del
-- núcleo). Solo agrega 'evento_origen_id' a cada fila; el resto del cuerpo es el vigente, copiado del blob de git. El id
-- de origen no es dato personal (C<n>-<segundos>; la hora ya viaja en ocurrio_en).
--
-- Capas: núcleos INVOKER en private sin EXECUTE para nadie, como antes. Single-tenant (F2.3.3).
-- Reversión: ../scripts/llamadas-celular/reversa-bandeja-con-origen.sql (repone los dos cuerpos y sus COMMENT tal cual;
-- sin datos). Verificación: npm run test:llamadas:local (pasada 17) y el tramo de F4-b de testLlamadasCelular.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is null then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: falta la novena (20261005224330)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), 'evento_origen_id') > 0 then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. Bandeja: cada fila trae su id de origen ───────────────────────────────────────────────
create or replace function private.llamadas_celular_bandeja(
  p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with limitada as (
    select e.id, e.evento_origen_id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
           e.duracion_seg, e.identificacion, e.atencion, e.lead_id, e.analista_id,
           l.nombre_completo as lead_nombre
    from crm.llamadas_celular_eventos e
    left join crm.leads l on l.id = e.lead_id
    where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
      and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))
      and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
    order by e.recibido_en desc, e.id desc
    limit p_limite + 1
  ), pagina as (
    select x.*, pg_catalog.row_number() over (order by x.recibido_en desc, x.id desc) as n
    from limitada x
  )
  select pg_catalog.jsonb_build_object(
    -- La forma de fila de F2-c más el id de origen (décima): con él, registrar desde la pestaña une la llamada.
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'evento_origen_id', p.evento_origen_id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
               'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
               'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
               'atencion', private.llamada_celular_atencion_efectiva(p_actor, p.atencion, p.identificacion, p.lead_id),
               'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
               'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor)
             order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
    'siguiente', (select pg_catalog.jsonb_build_object('recibido_en', u.recibido_en, 'evento_id', u.id)
                  from pagina u
                  where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
  from pagina p
$function$;

-- ── 2. Detalle: también ──────────────────────────────────────────────────────────────────────
create or replace function private.llamada_celular_detalle(p_actor uuid, p_evento_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  v_deshecha boolean;
begin
  select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
  if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
    raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
  end if;
  select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id;
  if found and v_enl.actividad_id is not null then
    select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'evento_id', v_ev.id, 'evento_origen_id', v_ev.evento_origen_id, 'recibido_en', v_ev.recibido_en, 'ocurrio_en', v_ev.ocurrio_en,
    'numero', v_ev.numero_canonico, 'direccion', v_ev.direccion, 'estado_tecnico', v_ev.estado_tecnico,
    'duracion_seg', v_ev.duracion_seg, 'calidad', v_ev.calidad, 'identificacion', v_ev.identificacion,
    'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id),
    'lead_id', v_ev.lead_id, 'metodo_asociacion', v_ev.metodo_asociacion, 'analista_id', v_ev.analista_id,
    'motivo_descarte', v_ev.motivo_descarte, 'motivo_descarte_detalle', v_ev.motivo_descarte_detalle,
    'actividad_id', v_enl.actividad_id,
    -- Decisión 4: los efectos deshechos se DERIVAN del resultado, no se copian.
    'efectos_anulados', coalesce(v_deshecha, false));
end;
$function$;

-- ── 3. Comentarios ───────────────────────────────────────────────────────────────────────────
comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva y el id de origen del celular (evento_origen_id, desde 20261006150154: con él la pantalla registra por la v5 y la llamada queda unida). DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.llamada_celular_detalle(uuid,uuid) is
  'Detalle de una llamada visible para el actor, con su id de origen (evento_origen_id, desde 20261006150154), su enlace y efectos_anulados derivado de metadata.deshecho_en del resultado (decisión 4).';

-- ── 4. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), '''evento_origen_id''') = 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), '''evento_origen_id''') = 0 then
    raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: la bandeja o el detalle siguen sin evento_origen_id';
  end if;
  for v_f in
    select * from (values
      ('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'),
      ('private.llamada_celular_detalle(uuid,uuid)')
    ) as f(firma)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % debería ser SECURITY INVOKER', v_f.firma;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_BANDEJA_CON_ORIGEN: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
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
                 where version = '20261006150154' and name = 'crm_llamadas_celular_bandeja_con_origen' and cardinality(statements) = 1
                   and md5(statements[1]) = 'c76e6dae55d7983a1daabccf2321218d') then
    raise exception 'REGISTRO: la fila 20261006150154 / crm_llamadas_celular_bandeja_con_origen no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261006150154 / crm_llamadas_celular_bandeja_con_origen (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261006150154' and name = 'crm_llamadas_celular_bandeja_con_origen' and md5(statements[1]) = 'c76e6dae55d7983a1daabccf2321218d') = 1
       as veredicto_registro_20261006150154;
