-- MARCHA ATRAS de P-055 F7.1 (cerrar lo que quedo suelto).
-- Devuelve los EXECUTE originales (v1/v2 con la danza del rol puente) y retira
-- del libro las 7 filas de ESTA ola (candado bajado NOMBRADO, doctrina
-- limpieza-leads). La adopcion de metricas_altas_analista_fn NO se revierte:
-- fue un no-op al byte y su partida de nacimiento se queda.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- 0) PREFLIGHT anti-pisado: el mundo debe estar en el estado F7.1.
do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres}']
  ];
  v_fila text[];
begin
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'rollback F7.1: % NO esta en el estado F7.1 (%) — regenerar el rollback', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;
  if (select count(*) from private.f7_piezas_en_observacion where ola = 'F7.1') <> 7 then
    raise exception 'rollback F7.1: el libro no tiene las 7 filas de la ola';
  end if;
end $$;

-- 1) Devolver los EXECUTE (v1/v2 como el dueño, con la danza medida).
grant crm_metricas_bridge to postgres with set true;
set local role crm_metricas_bridge;
grant execute on function crm.metricas_distribucion_leads_fn(date,date)    to authenticated;
grant execute on function crm.metricas_distribucion_leads_v2_fn(date,date) to authenticated;
reset role;
grant crm_metricas_bridge to postgres with set false;

grant execute on function crm.metricas_cartera_fn(date)                        to authenticated, service_role;
grant execute on function crm.metricas_altas_analista_fn(integer)              to authenticated;
grant execute on function crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)     to authenticated;
grant execute on function crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.actualizar_numero_contrato(uuid,text,text,text) to authenticated, service_role;

-- 2) Retirar las 7 filas de ESTA ola: candado bajado NOMBRADO y re-activado.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_01_no_borrar;
delete from private.f7_piezas_en_observacion where ola = 'F7.1';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_01_no_borrar;

-- 3) POSTFLIGHT: ACL originales al literal, candado re-armado, danza deshecha.
do $$
declare
  v_fn constant text[][] := array[
    array['crm.metricas_distribucion_leads_fn(date,date)',    '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_distribucion_leads_v2_fn(date,date)', '{crm_metricas_bridge=X/crm_metricas_bridge,authenticated=X/crm_metricas_bridge}'],
    array['crm.metricas_cartera_fn(date)',                    '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
    array['crm.metricas_altas_analista_fn(integer)',          '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)', '{postgres=X/postgres,authenticated=X/postgres}'],
    array['public.actualizar_numero_contrato(uuid,text,text,text)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}']
  ];
  v_fila text[];
begin
  foreach v_fila slice 1 in array v_fn loop
    if (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure)
       is distinct from v_fila[2] then
      raise exception 'rollback F7.1: % no volvio al ACL original (%)', v_fila[1],
        (select p.proacl::text from pg_proc p where p.oid = v_fila[1]::regprocedure);
    end if;
  end loop;
  if (select count(*) from private.f7_piezas_en_observacion where ola = 'F7.1') <> 0 then
    raise exception 'rollback F7.1: quedaron filas de la ola en el libro';
  end if;
  if not exists (select 1 from pg_trigger t
    where t.tgrelid = 'private.f7_piezas_en_observacion'::regclass
      and t.tgname = 'trg_f7_obs_01_no_borrar' and t.tgenabled in ('O','A')) then
    raise exception 'rollback F7.1: el candado anti-borrar quedo APAGADO';
  end if;
  if exists (select 1 from pg_auth_members m
              where m.roleid = 'crm_metricas_bridge'::regrole
                and m.member = 'postgres'::regrole and m.set_option) then
    raise exception 'rollback F7.1: postgres se quedo con la opcion SET del rol puente';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
