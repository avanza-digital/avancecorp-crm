-- Reversa de 20261006150254_crm_llamadas_celular_salud_sin_hora.sql (undécima). Repone el cuerpo y el COMMENT de
-- private.celulares_salud_listar de la quinta (20261005143843), copiados tal cual por el generador: la huella vuelve a
-- la de la décima. Sin datos. OJO: vuelve a mostrar la hora exacta del latido (la fuga que esta migración cierra).
--
-- Orden de las reversas: esta → décima (reversa-bandeja-con-origen.sql) → novena → …
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-salud-sin-hora.sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $precondicion$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') = 0 then
    raise exception 'REVERSA_SALUD_SIN_HORA: la migración 20261006150254 no está aplicada';
  end if;
end;
$precondicion$;

create or replace function private.celulares_salud_listar(p_actor uuid)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
           'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
           'ultimo_latido_en', s.ultimo_latido_en, 'latido_celular_en', s.latido_celular_en,
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

comment on function private.celulares_salud_listar(uuid) is
  'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Solo latido, versión de la macro y cola: sin envíos ni último envío (N1, cuentan llamadas personales). Sin hash de credencial.';

do $postcheck$
begin
  if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.celulares_salud_listar(uuid)'::regprocedure), 'estado_latido') > 0 then
    raise exception 'REVERSA_SALUD_SIN_HORA: no se volvió al estado de la décima';
  end if;
end;
$postcheck$;

notify pgrst, 'reload schema';
commit;
