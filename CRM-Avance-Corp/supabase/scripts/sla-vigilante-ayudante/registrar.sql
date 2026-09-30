-- REGISTRO en supabase_migrations.schema_migrations de 20260930154341_crm_sla_vigilante_ayudante. Correr DESPUÉS de aplicar. Idempotente; se niega si el
-- guardián no tiene la huella nueva o sus invariantes, o si la versión ya está registrada con otro nombre; relee la fila.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_sla_vigilante_ayudante'));
do $chk$
declare
  v_md5 text; v_oid oid := 'private.assert_sla_avisos()'::regprocedure;
  v_owner text; v_acl text; v_secdef boolean; v_vol "char"; v_cfg text[];
begin
  select md5(pg_get_functiondef(v_oid)), pg_get_userbyid(p.proowner), p.proacl::text, p.prosecdef, p.provolatile, p.proconfig
    into v_md5, v_owner, v_acl, v_secdef, v_vol, v_cfg from pg_proc p where p.oid = v_oid;
  if v_md5 is distinct from 'c90f23b049f1777eef68db925d6b8b57' then
    raise exception 'REGISTRO: el guardián no tiene la huella nueva (%); aplica primero la migración 20260930154341', v_md5;
  end if;
  -- Invariantes que la huella NO cubre: dueño y ACL exacta (nunca NULL); DEFINER, STABLE y search_path vacío (guardado
  -- como search_path=""). IS NOT TRUE: un NULL rechaza.
  if (v_owner = 'postgres' and v_acl is not null and v_acl = '{postgres=X/postgres}' and v_secdef is true and v_vol = 's'
    and exists (select 1 from unnest(v_cfg) x where x in ('search_path=', 'search_path=""'))) is not true then
    raise exception 'REGISTRO: invariantes del guardián incorrectos (dueño %, acl %, definer %, vol %, cfg %); no se registra', v_owner, v_acl, v_secdef, v_vol, v_cfg;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260930154341' and coalesce(name,'') <> 'crm_sla_vigilante_ayudante') then
    raise exception 'REGISTRO: la versión 20260930154341 ya está registrada con otro nombre';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260930154341', 'crm_sla_vigilante_ayudante', array[$stm$
CREATE OR REPLACE FUNCTION private.assert_sla_avisos()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;v_cuerpo text;
begin
  perform private.assert_sla_nucleo();
  for v in select * from (values
    ('crm.avisos_sla_resumen_v2_fn()','sla_operacion_autorizada'),
    ('private.sla_operacion_autorizada(uuid[],boolean)','sla_operacion_leads')
  ) d(firma,dependencia) loop
    select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
      into strict v_cuerpo from pg_proc p where p.oid=v.firma::regprocedure;
    if v_cuerpo !~ ('\mprivate\.'||v.dependencia||'\s*\(') then
      raise exception 'SLA avisos: % dejo de consumir %',v.firma,v.dependencia;
    end if;
    if v.firma like 'crm.%' and v_cuerpo ~ '\mcrm\.(leads|tareas|actividades|lead_sla_etapas)\M' then
      raise exception 'SLA avisos: adaptador lee hechos crudos';
    end if;
  end loop;
  if has_function_privilege('anon','crm.avisos_sla_resumen_v2_fn()','execute')
    or has_function_privilege('service_role','crm.avisos_sla_resumen_v2_fn()','execute')
    or not has_function_privilege('authenticated','crm.avisos_sla_resumen_v2_fn()','execute') then
    raise exception 'SLA avisos: permisos incorrectos del resumen';
  end if;
  -- Vigilante del ayudante (30/09/2026, auditor-rls P2-2): existe con su huella, dueño postgres, INVOKER, STABLE,
  -- search_path vacío y sin ejecutores de la API; y el resumen se lo pasa al núcleo (no vuelve a pedir TODAS las
  -- oportunidades). Si el ayudante cambia legítimamente, se resella aquí en la misma migración.
  if to_regprocedure('private.sla_leads_operativos()') is null then
    raise exception 'SLA avisos: falta el ayudante private.sla_leads_operativos()';
  end if;
  if not exists (select 1 from pg_proc p where p.oid='private.sla_leads_operativos()'::regprocedure
      and md5(pg_get_functiondef(p.oid))='8d478d783e4c591662388ddf7405058a'
      and p.proowner='postgres'::regrole and p.prosecdef is false and p.provolatile='s'
      and p.proconfig=array['search_path=""'] and p.proacl::text='{postgres=X/postgres}') then
    raise exception 'SLA avisos: el ayudante sla_leads_operativos no es el esperado (huella, dueño, definer, volatilidad, search_path o permisos)';
  end if;
  select regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','gs')
    into strict v_cuerpo from pg_proc p where p.oid='crm.avisos_sla_resumen_v2_fn()'::regprocedure;
  if v_cuerpo !~ '\mprivate\.sla_operacion_autorizada\s*\(\s*private\.sla_leads_operativos\s*\(\s*\)\s*,' then
    raise exception 'SLA avisos: el resumen dejo de evaluar solo las oportunidades operativas';
  end if;
  return 'OK: avisos derivados del nucleo, con autoridad y resumen completo';
end;
$function$
$stm$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260930154341' and name = 'crm_sla_vigilante_ayudante') then
    raise exception 'REGISTRO: tras el insert, la versión 20260930154341 no quedó con el nombre esperado';
  end if;
  raise notice 'REGISTRO_VIGILANTE_OK';
end $post$;
select version, name from supabase_migrations.schema_migrations where version = '20260930154341';
commit;
