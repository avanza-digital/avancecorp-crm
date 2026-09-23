set search_path=pg_catalog;
select jsonb_build_object(
 'tablas',(select jsonb_agg(jsonb_build_object('nombre',c.oid::regclass::text,
 'tipo',c.relkind,'owner',c.relowner::regrole::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
 'opciones',c.reloptions,
 'columnas',(select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,
   a.attidentity,a.attgenerated,pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
   from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
   where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 'restricciones',(select jsonb_agg(jsonb_build_array(k.conname,pg_get_constraintdef(k.oid),k.convalidated) order by k.conname)
   from pg_constraint k where k.conrelid=c.oid),
 'indices',(select jsonb_agg(jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) order by pg_get_indexdef(i.indexrelid))
   from pg_index i where i.indrelid=c.oid),
 'politicas',(select jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polpermissive,
   (select array_agg(r::regrole::text order by r::regrole::text) from unnest(p.polroles) r),
   pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname)
   from pg_policy p where p.polrelid=c.oid),
 'triggers',(select jsonb_agg(jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgname)
   from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
 'vista',case when c.relkind in ('v','m') then pg_get_viewdef(c.oid) else null end,
 'acl',(select jsonb_agg(jsonb_build_array(a.grantee::regrole::text,a.privilege_type,a.is_grantable)
   order by a.grantee::regrole::text,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a)) order by c.oid::regclass::text)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('crm','private','public') and c.relkind in('r','p','v','m')),
 'roles',(select jsonb_agg(jsonb_build_object('nombre',rolname,'login',rolcanlogin,'bypass',rolbypassrls,
   'super',rolsuper,'createrole',rolcreaterole,'createdb',rolcreatedb,'inherit',rolinherit,'config',rolconfig) order by rolname)
   from pg_roles where rolname like 'crm_%'),
 'membresias',(select jsonb_agg(jsonb_build_array(r.rolname,m.rolname,g.rolname,a.admin_option,a.inherit_option,a.set_option)
   order by r.rolname,m.rolname,g.rolname) from pg_auth_members a join pg_roles r on r.oid=a.roleid
   join pg_roles m on m.oid=a.member join pg_roles g on g.oid=a.grantor where r.rolname like 'crm_%' or m.rolname like 'crm_%'),
 'storage_policies',(select jsonb_agg(to_jsonb(p) order by tablename,policyname) from pg_policies p where schemaname='storage'),
 'auth_triggers',(select jsonb_agg(jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgname)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='auth' and not t.tgisinternal)
) as estructura;
