-- Solo lectura, después del merge. El vigía se ejecuta por separado cuando
-- estas guardas confirman el estado; no se borran ni cierran alertas a mano.
begin read only;
set local statement_timeout='15s';
do $verificar$
begin
  if md5(pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure))
    is distinct from '0abdf640b5f4f10ab2e85b6bd2494522' then
    raise exception 'SLA: definición productiva distinta de la ensayada';
  end if;
  if not exists(select 1 from pg_proc where oid='private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure
    and proowner='postgres'::regrole and proacl='{postgres=X/postgres}'::aclitem[]
    and not prosecdef and provolatile='s' and proconfig=array['search_path=""']) then
    raise exception 'SLA: atributos o ACL inesperados';
  end if;
  if not exists(select 1 from private.f7_piezas_en_observacion
    where firma='crm.metricas_cartera_fn(date)' and huella_md5='869853c25e903fe2f79245b8176c09b9'
    and estado='cerrada_permanente') then
    raise exception 'F7: declaración distinta de la ensayada';
  end if;
  perform private.assert_f7_piezas_cerradas();
  perform private.assert_sla_nucleo();
  perform private.assert_sla_avisos();
  perform private.assert_cola_v3();
  perform private.assert_gestion_diaria();
end $verificar$;
select jsonb_build_object(
 'fecha',now(),'estado','PASS','f7',private.assert_f7_piezas_cerradas(),
 'piezas_f7',(select count(*) from private.f7_piezas_en_observacion),
 'alertas_f7_abiertas',(select count(*) from private.vigia_alertas where fase='f7_piezas_cerradas' and resuelta_en is null),
 'sla_md5',md5(pg_get_functiondef('private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)'::regprocedure)),
 'guardianes',jsonb_build_array('sla_nucleo','sla_avisos','cola_v3','gestion_diaria'),
 'migraciones',(select jsonb_agg(jsonb_build_object('version',version,'nombre',name,'huella',md5(statements::text)) order by version)
  from supabase_migrations.schema_migrations where name in('crm_f7_redeclarar_huella_metricas_cartera','crm_sla_agrupar_tareas_por_lead'))
) as comprobacion;
rollback;
