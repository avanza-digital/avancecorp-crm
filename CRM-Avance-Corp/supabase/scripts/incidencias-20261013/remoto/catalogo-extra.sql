set search_path=pg_catalog;
select jsonb_build_object(
 'f7',(select jsonb_agg(to_jsonb(t) order by firma) from private.f7_piezas_en_observacion t),
 'esquemas',(select jsonb_agg(jsonb_build_array(nspname,nspowner::regrole::text,
  (select jsonb_agg(jsonb_build_array(grantee::regrole::text,privilege_type,is_grantable) order by grantee::regrole::text,privilege_type,is_grantable) from aclexplode(nspacl))) order by nspname)
  from pg_namespace where nspname in('crm','private','public','supabase_migrations')),
 'acl_columnas',(select jsonb_agg(jsonb_build_array(c.oid::regclass::text,a.attname,
  (select jsonb_agg(jsonb_build_array(grantee::regrole::text,privilege_type,is_grantable) order by grantee::regrole::text,privilege_type,is_grantable) from aclexplode(a.attacl))) order by c.oid::regclass::text,a.attname)
  from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in('crm','private','public') and a.attnum>0 and not a.attisdropped and a.attacl is not null),
 'default_acl',(select jsonb_agg(jsonb_build_array(defaclrole::regrole::text,n.nspname,defaclobjtype,
  (select jsonb_agg(jsonb_build_array(grantee::regrole::text,privilege_type,is_grantable) order by grantee::regrole::text,privilege_type,is_grantable) from aclexplode(defaclacl))) order by defaclrole::regrole::text,n.nspname,defaclobjtype)
  from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace where n.nspname in('crm','private','public')),
 'extensiones',(select jsonb_agg(jsonb_build_array(extname,nspname,extversion) order by extname) from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'publicaciones',(select jsonb_agg(jsonb_build_array(pubname,schemaname,tablename) order by pubname,schemaname,tablename)
  from pg_publication_tables where schemaname in('crm','private','public')),
 'ledger',(select jsonb_build_object('cantidad',count(*),'huella',md5(string_agg(to_jsonb(t)::text,E'\n' order by version)))
  from supabase_migrations.schema_migrations t where name is null or name not in('crm_f7_redeclarar_huella_metricas_cartera','crm_sla_agrupar_tareas_por_lead')),
 'nuevas',(select jsonb_agg(jsonb_build_object('version',version,'nombre',name,'huella',md5(statements::text)) order by version)
  from supabase_migrations.schema_migrations where name in('crm_f7_redeclarar_huella_metricas_cartera','crm_sla_agrupar_tareas_por_lead'))
) as extra;
