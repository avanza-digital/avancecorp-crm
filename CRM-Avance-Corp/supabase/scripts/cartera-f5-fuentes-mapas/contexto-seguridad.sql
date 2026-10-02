-- SOLO LECTURA (producción): contexto de seguridad de private.cartera_f5_fuentes() y sus llamadores.
select json_build_object(
 'fuentes', (select json_build_object('definer', p.prosecdef, 'owner', pg_get_userbyid(p.proowner), 'acl', p.proacl::text, 'vol', p.provolatile, 'cfg', p.proconfig)
   from pg_proc p where p.oid = 'private.cartera_f5_fuentes()'::regprocedure),
 'llamadores', (select json_agg(json_build_object('f', n.nspname||'.'||p.proname, 'definer', p.prosecdef, 'owner', pg_get_userbyid(p.proowner)) order by n.nspname, p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('crm','private') and p.prosrc ~ 'cartera_f5_fuentes(_reales)?\(' and p.proname not in ('cartera_f5_fuentes')),
 'tablas', (select json_agg(json_build_object('t', n.nspname||'.'||c.relname, 'rls', c.relrowsecurity, 'forzada', c.relforcerowsecurity, 'owner', pg_get_userbyid(c.relowner),
     'policies', (select count(*) from pg_policies pp where pp.schemaname=n.nspname and pp.tablename=c.relname)) order by 1)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where (n.nspname='public' and c.relname='contratos') or (n.nspname='crm' and c.relname in ('inversionistas','inversiones','cierres_externos','leads','operaciones_cartera'))),
 'ejecutan_fuentes', (select json_agg(r.rolname) from pg_roles r where r.rolname in ('anon','authenticated','service_role') and has_function_privilege(r.rolname, 'private.cartera_f5_fuentes()', 'EXECUTE')),
 'canonica_y_cadena', (select json_agg(json_build_object('f', p.proname, 'definer', p.prosecdef, 'vol', p.provolatile, 'md5', md5(pg_get_functiondef(p.oid))))
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('inversionista_canonica','analista_atribuido_cadena'))
)::text as contexto;
