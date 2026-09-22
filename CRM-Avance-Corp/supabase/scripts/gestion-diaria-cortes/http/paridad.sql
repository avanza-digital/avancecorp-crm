-- Sólo catálogos, sin usuarios ni datos comerciales. Ejecutar idéntico en origen
-- y banco. El registro de migraciones no se copia ni se presenta como replay.
set search_path = '';
with esquemas as (select unnest(array['crm','public','private']) as n),
relaciones as (
  select c.*, n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  join esquemas e on e.n=n.nspname
  where not exists(select 1 from pg_depend d where d.classid='pg_class'::regclass
    and d.objid=c.oid and d.deptype='e')
), funciones as (
  select p.*, n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join esquemas e on e.n=n.nspname
  where p.prokind in ('f','p') and not exists(select 1 from pg_depend d
    where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e')
), todo as (
  select 'columnas' as categoria, c.nspname||'.'||c.relname||'.'||a.attname||' '||
    format_type(a.atttypid,a.atttypmod)||' null='||a.attnotnull||' identity='||a.attidentity::text||
    ' generated='||a.attgenerated::text||' default='||coalesce(pg_get_expr(d.adbin,d.adrelid),'-') as linea
  from relaciones c join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
  where c.relkind in ('r','p','v','m','f')
  union all
  select 'funciones', p.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '||
    md5(pg_get_functiondef(p.oid))||' owner='||p.proowner::regrole::text||
    ' comment='||coalesce(md5(obj_description(p.oid,'pg_proc')),'-')||' acl='||
    coalesce((select string_agg(a.grantor::regrole::text||':'||a.grantee::regrole::text||':'||
      a.privilege_type||':'||a.is_grantable,',' order by a.grantor::regrole::text,a.grantee::regrole::text,a.privilege_type)
      from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'-')
  from funciones p
  union all
  select 'triggers', c.nspname||'.'||c.relname||'.'||t.tgname||' '||md5(pg_get_triggerdef(t.oid))||' enabled='||t.tgenabled::text
  from pg_trigger t join relaciones c on c.oid=t.tgrelid where not t.tgisinternal
  union all
  select 'policies', schemaname||'.'||tablename||'.'||policyname||' '||cmd||' '||permissive||' roles='||roles::text||
    ' using='||coalesce(md5(qual),'-')||' check='||coalesce(md5(with_check),'-')
  from pg_policies join esquemas e on e.n=schemaname
  union all
  select 'rls', c.nspname||'.'||c.relname||' rls='||c.relrowsecurity||' forced='||c.relforcerowsecurity
  from relaciones c where c.relkind in ('r','p')
  union all
  select 'indices', c.nspname||'.'||c.relname||' '||md5(pg_get_indexdef(c.oid))
  from relaciones c where c.relkind in ('i','I')
  union all
  -- pretty=true evita que el agrupamiento interno redundante de AND, aplanado
  -- por pg_dump/restore, aparente cambiar tres CHECK. Se compara la definición
  -- canónica del servidor (misma versión 17.6), no los bytes de pg_constraint.
  select 'constraints', c.nspname||'.'||c.relname||'.'||co.conname||' '||md5(pg_get_constraintdef(co.oid,true))||' validated='||co.convalidated
  from pg_constraint co join relaciones c on c.oid=co.conrelid
  union all
  select 'vistas', c.nspname||'.'||c.relname||' '||md5(pg_get_viewdef(c.oid,true))||' opts='||coalesce(c.reloptions::text,'-')
  from relaciones c where c.relkind in ('v','m')
  union all
  select 'acl_tablas_secuencias', c.nspname||'.'||c.relname||' owner='||c.relowner::regrole::text||
    ' grantor='||a.grantor::regrole::text||' grantee='||a.grantee::regrole::text||' '||a.privilege_type||' grantable='||a.is_grantable
  from relaciones c cross join lateral aclexplode(coalesce(c.relacl,
    acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner))) a
  where c.relkind in ('r','p','v','m','S','f')
  union all
  select 'acl_columnas', c.nspname||'.'||c.relname||'.'||at.attname||' '||a.grantor::regrole::text||':'||
    a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable
  from relaciones c join pg_attribute at on at.attrelid=c.oid and at.attnum>0 and not at.attisdropped
  cross join lateral aclexplode(at.attacl) a
  union all
  select 'acl_esquemas', n.nspname||' owner='||n.nspowner::regrole::text||' '||a.grantor::regrole::text||':'||
    a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable
  from pg_namespace n join esquemas e on e.n=n.nspname
  cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
  union all
  select 'acl_default', d.defaclrole::regrole::text||'.'||coalesce(n.nspname,'global')||'.'||d.defaclobjtype::text||' '||
    a.grantor::regrole::text||':'||a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable
  from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) a
  where n.nspname in ('crm','public','private')
  union all
  select 'tipos_enum', n.nspname||'.'||t.typname||'.'||en.enumsortorder||'='||en.enumlabel
  from pg_enum en join pg_type t on t.oid=en.enumtypid join pg_namespace n on n.oid=t.typnamespace
  join esquemas e on e.n=n.nspname
  union all
  select 'rol_bridge', rolname||' super='||rolsuper||' inherit='||rolinherit||' login='||rolcanlogin||
    ' createdb='||rolcreatedb||' createrole='||rolcreaterole||' replication='||rolreplication||' bypassrls='||rolbypassrls
  from pg_roles where rolname='crm_metricas_bridge'
  union all
  select 'membresias_bridge', roleid::regrole::text||' member='||member::regrole::text||' grantor='||grantor::regrole::text||
    ' admin='||admin_option||' inherit='||inherit_option||' set='||set_option
  from pg_auth_members where roleid='crm_metricas_bridge'::regrole
)
select categoria,count(*) as n,md5(string_agg(linea,E'\n' order by linea)) as huella
from todo group by categoria order by categoria;
