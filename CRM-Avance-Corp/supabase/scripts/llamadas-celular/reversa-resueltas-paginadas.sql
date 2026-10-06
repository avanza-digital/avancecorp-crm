-- Reversa de 20261005224330_crm_llamadas_celular_resueltas_paginadas.sql (novena: «Qué pasó hoy» paginada y por la
-- hora de resolución). Quita la lectura paginada y sus dos índices y repone la lectura de la octava TAL CUAL: cuerpos y
-- COMMENT copiados de 20261005201010 por el generador, para que la huella del catálogo vuelva a la de la octava. Sin
-- tablas ni datos: corre en cualquier momento (la pestaña vuelve a recibir un arreglo sin cursor).
--
-- Orden de las reversas: undécima → décima (reversa-bandeja-con-origen.sql) → esta → octava (reversa-lecturas-analista.sql)
-- → séptima → F4-a → corrección → elegibilidad → ingesta → núcleo → datos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-resueltas-paginadas.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)'::regprocedure),
                       'evento_origen_id') > 0 then
    raise exception 'REVERSA_RESUELTAS_PAGINADAS: la décima (20261006150154) sigue instalada; corre antes reversa-bandeja-con-origen.sql';
  end if;
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)') is null then
    raise exception 'REVERSA_RESUELTAS_PAGINADAS: la migración 20261005224330 no está aplicada';
  end if;
end;
$precondicion$;

drop function crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid);
drop function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid);
drop index crm.llamadas_celular_enlaces_actualizado_idx;
drop index crm.llamadas_celular_eventos_descartado_en_idx;

-- La lectura de la octava, copiada de 20261005201010.
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

revoke all on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function crm.llamadas_celular_resueltas_hoy_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.llamadas_celular_resueltas_hoy_fn(integer) to authenticated;

comment on function private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz) is
  'Núcleo de «Qué pasó hoy» (F4-b, hallazgo 1): llamadas del celular recibidas el día de Lima de p_ahora que ya no están pendientes (registradas o descartadas con motivo), visibles para el actor (private.llamada_celular_visible), con el resultado de la actividad enlazada (y si se deshizo), la vía del enlace o el motivo del descarte. Más reciente primero, hasta p_limite. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
comment on function crm.llamadas_celular_resueltas_hoy_fn(integer) is
  'PUERTA de «Qué pasó hoy» en la pestaña «Llamadas del celular» (F4-b): analista, supervisión y gerencia (42501 para los demás); el ámbito lo decide el servidor, como en la bandeja. p_limite de 1 a 200 (22023). Solo el día de hoy en Lima (decisión de Jhosep, 05/10). Devuelve un arreglo de filas.';

do $postcheck$
begin
  if to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer,timestamptz,uuid)') is not null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz,timestamptz,uuid)') is not null
     or to_regclass('crm.llamadas_celular_enlaces_actualizado_idx') is not null
     or to_regclass('crm.llamadas_celular_eventos_descartado_en_idx') is not null
     or to_regprocedure('crm.llamadas_celular_resueltas_hoy_fn(integer)') is null
     or to_regprocedure('private.llamadas_celular_resueltas_hoy(uuid,integer,timestamptz)') is null then
    raise exception 'REVERSA_RESUELTAS_PAGINADAS: no se volvió al estado de la octava';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
