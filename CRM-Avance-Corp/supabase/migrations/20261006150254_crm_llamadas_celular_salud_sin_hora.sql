-- Llamadas desde el celular · undécima migración (F4-c/F4-d): la salud de los celulares sin la hora exacta del latido.
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
