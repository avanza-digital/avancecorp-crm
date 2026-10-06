-- Reversa de 20261006150154_crm_llamadas_celular_bandeja_con_origen.sql (décima). Repone los cuerpos de la bandeja
-- (20261001212258) y del detalle (20261001160219) y sus COMMENT vigentes (20261005143843 y 20261001160219), copiados
-- tal cual por el generador: la huella vuelve a la de la novena. Sin datos: corre en cualquier momento (registrar desde
-- la pestaña vuelve a caer a la v4).
--
-- Orden de las reversas: undécima (reversa-salud-sin-hora.sql) → esta → novena → octava → séptima → …
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-bandeja-con-origen.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') > 0 then
    raise exception 'REVERSA_BANDEJA_CON_ORIGEN: la undécima (20261006150254) sigue instalada; corre antes reversa-salud-sin-hora.sql';
  end if;
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') = 0 then
    raise exception 'REVERSA_BANDEJA_CON_ORIGEN: la migración 20261006150154 no está aplicada';
  end if;
end;
$precondicion$;

create or replace function private.llamadas_celular_bandeja(
  p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with limitada as (
    select e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
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
    -- La misma forma de fila que private.llamadas_celular_pendientes (F2-c).
    'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'evento_id', p.id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
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
    'evento_id', v_ev.id, 'recibido_en', v_ev.recibido_en, 'ocurrio_en', v_ev.ocurrio_en,
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

comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
  'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function private.llamada_celular_detalle(uuid,uuid) is
  'Detalle de una llamada visible para el actor, con su enlace y efectos_anulados derivado de metadata.deshecho_en del resultado (decisión 4).';

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure), 'evento_origen_id') > 0
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_detalle(uuid,uuid)'::regprocedure), 'evento_origen_id') > 0 then
    raise exception 'REVERSA_BANDEJA_CON_ORIGEN: no se volvió al estado de la novena';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
