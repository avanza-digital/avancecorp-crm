-- REGISTRO en supabase_migrations.schema_migrations de 20261006150254_crm_llamadas_celular_salud_sin_hora (undécima: la salud de los celulares sin la hora exacta del latido).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración, en un mensaje aparte (punto 18 de
-- REVISION-2026-10-02.md; guía PUBLICAR-F2-F3.md: cada registrador justo después de su migración). Idempotente; se
-- niega si los objetos no están con su forma o si la versión ya está registrada con otro nombre u otro contenido;
-- relee la fila antes de confirmar. statements = el archivo entero (md5 32f1c8ecce31ff871ad0f1f93fb7964d, con finales de línea LF:
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
    pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''estado_latido''') > 0
    and pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''ultimo_latido_en''') = 0
  ) is not true then
    raise exception 'REGISTRO: la migración 20261006150254 no está aplicada (o no con su forma); aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261006150254' and (coalesce(name, '') <> 'crm_llamadas_celular_salud_sin_hora' or statements is distinct from array[$mig$-- Llamadas desde el celular · undécima migración (F4-c/F4-d): la salud de los celulares sin la hora exacta del latido.
-- Hallazgo del análisis de F4-e (06/10/2026, verificado): la macro manda el latido también cuando su cola se acaba de
-- vaciar (macrodroid.md §3c), y la cola recibe TODA llamada saliente, personales incluidas. Así ultimo_latido_en (y
-- latido_celular_en) es casi la hora de la última llamada, y private.celulares_salud_listar se la mostraba a supervisión
-- y gerencia: la misma fuga que la N1 cerró al retirar ultimo_envio_en. Decisión de Jhosep (06/10): arreglarlo en la
-- macro (latido solo por intervalo) Y en el servidor (esta migración), antes de activar C1.
--
-- Qué hace: create or replace del núcleo con la misma firma (la puerta crm.celulares_salud_fn no cambia). En lugar de
-- las dos horas, devuelve estado_latido (al_dia | sin_latido pasadas 7 h | nunca), horas_sin_latido (enteras) y
-- reloj_desfasado (más de 5 min entre el reloj del celular y el del servidor). Las horas se siguen guardando en
-- private.celulares_estado (las usa el cálculo); solo dejan de salir. Sin consumidores: la tarjeta «Celulares» (F4-c)
-- aún no existe y nada está publicado.
--
-- Capas: núcleo INVOKER en private sin EXECUTE para nadie, como antes. Single-tenant (F2.3.3).
-- Reversión: ../scripts/llamadas-celular/reversa-salud-sin-hora.sql (repone el cuerpo y el COMMENT de la quinta tal
-- cual; sin datos). Verificación: npm run test:llamadas:local (pasada 18) y el tramo de salud de testLlamadasCelular.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') = 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: falta la décima (20261006150154)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') > 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. Salud: estado y horas enteras, sin horas exactas ──────────────────────────────────────
create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           -- Sin la hora exacta del latido (undécima): la macro lo mandaba al vaciarse la cola, así que su hora era casi la
           -- de la última llamada, personales incluidas (la misma fuga que la N1). Solo el estado y las horas enteras.
           'estado_latido', case when s.ultimo_latido_en is null then 'nunca'
                                 when pg_catalog.now() - s.ultimo_latido_en > interval '7 hours' then 'sin_latido'
                                 else 'al_dia' end,
           -- Piso en 0: un latido sellado con el reloj real puede ir un instante por delante de now(). Sin latido, nulo
           -- (greatest ignora los nulos: sin el case daría 0).
           'horas_sin_latido', case when s.ultimo_latido_en is null then null
                                    else greatest(0, pg_catalog.floor(extract(epoch from pg_catalog.now() - s.ultimo_latido_en) / 3600)::integer) end,
           'reloj_desfasado', coalesce(pg_catalog.abs(extract(epoch from s.latido_celular_en - s.ultimo_latido_en)) > 300, false),
           'version_macro', s.version_macro, 'eventos_en_cola', s.eventos_en_cola)
         order by a.etiqueta), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join private.celulares_estado s on s.asignacion_id = a.id
  left join public.perfiles p on p.id = a.analista_id
  where a.vigente_hasta is null
    and (private.rol_crm(p_actor) = 'gerencia'
         or (private.rol_crm(p_actor) = 'supervisor'
             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
$function$;

-- ── 2. Comentario ────────────────────────────────────────────────────────────────────────────
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Desde 20261006150254 sin horas exactas: estado_latido (al_dia, sin_latido pasadas 7 h, nunca), horas_sin_latido enteras y reloj_desfasado (el reloj del celular y el del servidor difieren en más de 5 min); la hora del latido delataba la de la última llamada, personales incluidas (como la N1). Además la versión de la macro y los avisos en cola. Sin envíos ni hash de credencial.';

-- ── 3. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''ultimo_latido_en''') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''latido_celular_en''') > 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: la salud sigue devolviendo la hora exacta del latido';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''estado_latido''') = 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: falta estado_latido';
  end if;
  for v_f in
    select * from (values
      ('private.celulares_salud_listar(uuid)')
    ) as f(firma)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % debería ser SECURITY INVOKER', v_f.firma;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
    end if;
  end loop;
end;
$postflight$;

notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261006150254 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261006150254', 'crm_llamadas_celular_salud_sin_hora', array[$mig$-- Llamadas desde el celular · undécima migración (F4-c/F4-d): la salud de los celulares sin la hora exacta del latido.
-- Hallazgo del análisis de F4-e (06/10/2026, verificado): la macro manda el latido también cuando su cola se acaba de
-- vaciar (macrodroid.md §3c), y la cola recibe TODA llamada saliente, personales incluidas. Así ultimo_latido_en (y
-- latido_celular_en) es casi la hora de la última llamada, y private.celulares_salud_listar se la mostraba a supervisión
-- y gerencia: la misma fuga que la N1 cerró al retirar ultimo_envio_en. Decisión de Jhosep (06/10): arreglarlo en la
-- macro (latido solo por intervalo) Y en el servidor (esta migración), antes de activar C1.
--
-- Qué hace: create or replace del núcleo con la misma firma (la puerta crm.celulares_salud_fn no cambia). En lugar de
-- las dos horas, devuelve estado_latido (al_dia | sin_latido pasadas 7 h | nunca), horas_sin_latido (enteras) y
-- reloj_desfasado (más de 5 min entre el reloj del celular y el del servidor). Las horas se siguen guardando en
-- private.celulares_estado (las usa el cálculo); solo dejan de salir. Sin consumidores: la tarjeta «Celulares» (F4-c)
-- aún no existe y nada está publicado.
--
-- Capas: núcleo INVOKER en private sin EXECUTE para nadie, como antes. Single-tenant (F2.3.3).
-- Reversión: ../scripts/llamadas-celular/reversa-salud-sin-hora.sql (repone el cuerpo y el COMMENT de la quinta tal
-- cual; sin datos). Verificación: npm run test:llamadas:local (pasada 18) y el tramo de salud de testLlamadasCelular.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') = 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: falta la décima (20261006150154)';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') > 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: ya está aplicada; no se sobrescribe';
  end if;
end;
$precondicion$;

-- ── 1. Salud: estado y horas enteras, sin horas exactas ──────────────────────────────────────
create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           -- Sin la hora exacta del latido (undécima): la macro lo mandaba al vaciarse la cola, así que su hora era casi la
           -- de la última llamada, personales incluidas (la misma fuga que la N1). Solo el estado y las horas enteras.
           'estado_latido', case when s.ultimo_latido_en is null then 'nunca'
                                 when pg_catalog.now() - s.ultimo_latido_en > interval '7 hours' then 'sin_latido'
                                 else 'al_dia' end,
           -- Piso en 0: un latido sellado con el reloj real puede ir un instante por delante de now(). Sin latido, nulo
           -- (greatest ignora los nulos: sin el case daría 0).
           'horas_sin_latido', case when s.ultimo_latido_en is null then null
                                    else greatest(0, pg_catalog.floor(extract(epoch from pg_catalog.now() - s.ultimo_latido_en) / 3600)::integer) end,
           'reloj_desfasado', coalesce(pg_catalog.abs(extract(epoch from s.latido_celular_en - s.ultimo_latido_en)) > 300, false),
           'version_macro', s.version_macro, 'eventos_en_cola', s.eventos_en_cola)
         order by a.etiqueta), '[]'::jsonb)
  from crm.celulares_asignaciones a
  left join private.celulares_estado s on s.asignacion_id = a.id
  left join public.perfiles p on p.id = a.analista_id
  where a.vigente_hasta is null
    and (private.rol_crm(p_actor) = 'gerencia'
         or (private.rol_crm(p_actor) = 'supervisor'
             and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
$function$;

-- ── 2. Comentario ────────────────────────────────────────────────────────────────────────────
comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Desde 20261006150254 sin horas exactas: estado_latido (al_dia, sin_latido pasadas 7 h, nunca), horas_sin_latido enteras y reloj_desfasado (el reloj del celular y el del servidor difieren en más de 5 min); la hora del latido delataba la de la última llamada, personales incluidas (como la N1). Además la versión de la macro y los avisos en cola. Sin envíos ni hash de credencial.';

-- ── 3. Postflight ────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''ultimo_latido_en''') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''latido_celular_en''') > 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: la salud sigue devolviendo la hora exacta del latido';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), '''estado_latido''') = 0 then
    raise exception 'LLAMADAS_SALUD_SIN_HORA: falta estado_latido';
  end if;
  for v_f in
    select * from (values
      ('private.celulares_salud_listar(uuid)')
    ) as f(firma)
  loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % debería ser SECURITY INVOKER', v_f.firma;
    end if;
    if exists (
      select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
      where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
    ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: EXECUTE inesperado en %', v_f.firma;
    end if;
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: search_path inesperado en %', v_f.firma;
    end if;
    if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) <> 's' then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % debería ser STABLE (solo lee)', v_f.firma;
    end if;
    if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % sin COMMENT', v_f.firma;
    end if;
    if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
      raise exception 'LLAMADAS_SALUD_SIN_HORA: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
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
                 where version = '20261006150254' and name = 'crm_llamadas_celular_salud_sin_hora' and cardinality(statements) = 1
                   and md5(statements[1]) = '32f1c8ecce31ff871ad0f1f93fb7964d') then
    raise exception 'REGISTRO: la fila 20261006150254 / crm_llamadas_celular_salud_sin_hora no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261006150254 / crm_llamadas_celular_salud_sin_hora (1 sentencia: el archivo entero)';
end $post$;
commit;
select (select count(*) from supabase_migrations.schema_migrations
        where version = '20261006150254' and name = 'crm_llamadas_celular_salud_sin_hora' and md5(statements[1]) = '32f1c8ecce31ff871ad0f1f93fb7964d') = 1
       as veredicto_registro_20261006150254;
