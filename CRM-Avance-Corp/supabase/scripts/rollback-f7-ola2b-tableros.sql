-- MARCHA ATRAS de la OLA 2b — recrea `metricas_altas_analista_fn` con su
-- DEFINICION VIVA capturada de produccion el 2026-09-01.
--
-- Su partida de nacimiento NO esta en el repo (el repo tiene 167 de 193
-- archivos): vive en el registro remoto, version 20260716203331. La fuente es
-- la captura viva, no la carpeta local.
--
-- ⚠️ La fila del registro NO se borra aqui: retirarla A MANO.
-- ⚠️ Se revoca EXPLICITAMENTE a los tres roles de la API: recrear una funcion
--    hace que los default privileges le devuelvan EXECUTE (lo cazo el
--    vigilante F7 durante el ensayo del 01/09).

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $rb_pre$
declare v_n int;
begin
  if to_regprocedure('crm.metricas_altas_analista_fn(integer)') is not null then
    raise exception 'rollback OLA 2b: la funcion YA existe — investigar antes de recrear';
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
  if v_n <> 1 then
    raise exception 'rollback OLA 2b: el libro no la marca demolida — el mundo no es el que este guion revierte';
  end if;
end $rb_pre$;

CREATE OR REPLACE FUNCTION crm.metricas_altas_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cli.creado_en at time zone 'America/Lima'))::date as mes,
    coalesce(cli.asesor_perfil_id, cli.creado_por) as analista_id,
    coalesce(asesor.nombre_completo, 'Sin asesor') as analista_nombre,
    count(*)::bigint as altas
  from public.perfiles cli
  left join public.perfiles asesor
         on asesor.id = coalesce(cli.asesor_perfil_id, cli.creado_por)
  cross join ambito a
  where cli.rol = 'cliente'
    and cli.creado_en >= ((date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))
          at time zone 'America/Lima')
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 4 desc;
$function$;
alter function crm.metricas_altas_analista_fn(integer) owner to postgres;
revoke all on function crm.metricas_altas_analista_fn(integer) from public, anon, authenticated, service_role;

-- El libro vuelve a `observacion`. La maquina de estados PROHIBE salir de
-- `demolida` salvo «por migracion con el candado bajado»: se baja el trigger
-- NOMBRADO y se vuelve a subir en la MISMA transaccion.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota,'') || ' | REVERTIDA a observacion por la marcha atras ('
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || '): recreada al byte desde la captura viva del 01/09.'
 where firma = 'crm.metricas_altas_analista_fn(integer)' and estado = 'demolida';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

do $rb_post$
declare v_h text; v_verd text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'crm.metricas_altas_analista_fn(integer)'::regprocedure;
  if v_h is distinct from 'df8a99e0dfc4e1d94794073787aa84d7' then
    raise exception 'rollback OLA 2b: no volvio al byte (huella %)', v_h;
  end if;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback OLA 2b: vigilante F7 en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-OLA2b-OK: metricas_altas_analista_fn recreada al byte y cerrada' as resultado;
commit;
