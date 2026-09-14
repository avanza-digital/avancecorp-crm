-- CANDIDATA DE PREPARACIÓN: no instalar en producción durante esta sesión.
-- Requiere las candidatas de borradores y base asignada. Preserva los núcleos.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table crm.control_citas_aplicaciones (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique references crm.control_citas_versiones(version),
  mes_inicio date not null check (mes_inicio=date_trunc('month',mes_inicio)::date),
  aplicado_en timestamptz not null default now(),
  aplicado_por uuid not null references public.perfiles(id)
);
alter table crm.control_citas_aplicaciones enable row level security;
revoke all on table crm.control_citas_aplicaciones from public,anon,authenticated;
create index control_citas_aplicaciones_vigencia on crm.control_citas_aplicaciones(mes_inicio desc,version desc);
create index control_citas_aplicaciones_actor on crm.control_citas_aplicaciones(aplicado_por);
create index control_citas_versiones_actor on crm.control_citas_versiones(guardado_por);
create trigger control_citas_aplicacion_inmutable before update or delete on crm.control_citas_aplicaciones
  for each row execute function private.control_citas_version_inmutable();
create trigger control_citas_aplicacion_truncado_denegado before truncate on crm.control_citas_aplicaciones
  for each statement execute function private.control_citas_version_inmutable();
create trigger trg_audit_control_citas_aplicaciones after insert or update or delete on crm.control_citas_aplicaciones
  for each row execute function private.log_audit_crm();

create function private.control_citas_vigente(p_mes date)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce((
    select jsonb_build_object('version',v.version,'configuracion',v.configuracion,
      'mes_inicio',to_char(a.mes_inicio,'YYYY-MM'))
    from crm.control_citas_aplicaciones a join crm.control_citas_versiones v using(version)
    where a.mes_inicio<=p_mes
    order by a.mes_inicio desc,a.version desc limit 1
  ),jsonb_build_object('version',0,'mes_inicio',null,'configuracion',jsonb_build_object(
    'citas_por_lead',1.25,'entrevistas_porcentaje',70,'depositos_porcentaje',70,
    'excluir_manuales_base',false,'actividad_manuales','incluir','conteo_entrevistas','citas_realizadas',
    'base_avance','actividad_real','mes_resultado',null,'analista_resultado',null,
    'mes_inicio',null,'mostrar_meta_citas',false,'base_depositos',null)));
$$;
revoke all on function private.control_citas_vigente(date) from public,anon,authenticated,service_role;

create or replace function crm.control_citas_configuracion_fn()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_historial jsonb; v_ultimo jsonb; v_aplicaciones jsonb;
begin
  if auth.uid() is null or public.es_superadmin() is not true then
    raise exception using errcode='42501',message='Solo Superadmin puede consultar el control de Citas.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(fila)-'id' order by fila.version desc),'[]'::jsonb)
    into v_historial from (select * from crm.control_citas_versiones order by version desc limit 20) fila;
  v_ultimo:=v_historial->0;
  select coalesce(jsonb_agg(jsonb_build_object('version',a.version,
    'mes_inicio',to_char(a.mes_inicio,'YYYY-MM'),'aplicado_en',a.aplicado_en,
    'aplicado_por',a.aplicado_por) order by a.version desc),'[]'::jsonb)
    into v_aplicaciones from crm.control_citas_aplicaciones a;
  return jsonb_build_object('version_actual',coalesce((v_ultimo->>'version')::integer,0),
    'ultimo',v_ultimo,'historial',v_historial,'aplicaciones',v_aplicaciones);
end $$;

create function crm.aplicar_control_citas_fn(p_version_esperada integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_version integer; v_config jsonb; v_mes date; v_clave text;
begin
  if auth.uid() is null or public.es_superadmin() is not true then
    raise exception using errcode='42501',message='Solo Superadmin puede aplicar el control de Citas.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(214731,1257070);
  select coalesce(max(version),0) into v_version from crm.control_citas_versiones;
  if p_version_esperada is null or p_version_esperada<1 or p_version_esperada<>v_version then
    raise exception using errcode='PT409',message='La configuración cambió en otra sesión. Carga la última versión.';
  end if;
  select configuracion into v_config from crm.control_citas_versiones where version=v_version;
  foreach v_clave in array array['actividad_manuales','conteo_entrevistas','base_avance',
    'mes_resultado','analista_resultado','base_depositos','mes_inicio'] loop
    if v_config->v_clave is null or v_config->v_clave='null'::jsonb then
      raise exception using errcode='22023',message='Completa todas las reglas antes de aplicar.';
    end if;
  end loop;
  v_mes:=((v_config->>'mes_inicio')||'-01')::date;
  if v_mes<date_trunc('month',now() at time zone 'America/Lima')::date then
    raise exception using errcode='22023',message='No se reescriben meses anteriores. Elige el mes actual o uno posterior.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),(v_mes-date '2000-01-01')::integer);
  if exists(select 1 from crm.periodos_cerrados where periodo=v_mes) then
    raise exception using errcode='22023',message='El mes está sellado. Elige un mes abierto para aplicar las reglas.';
  end if;
  insert into crm.control_citas_aplicaciones(version,mes_inicio,aplicado_por)
    values(v_version,v_mes,auth.uid());
  return crm.control_citas_configuracion_fn();
end $$;
revoke all on function crm.aplicar_control_citas_fn(integer) from public,anon,authenticated;
grant execute on function crm.aplicar_control_citas_fn(integer) to authenticated;

commit;
