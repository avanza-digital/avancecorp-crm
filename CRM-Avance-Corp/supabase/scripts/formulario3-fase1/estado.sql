-- Foto sin datos personales: permisos, definiciones y huellas de filas anteriores.
select jsonb_build_object(
  'funciones', (select jsonb_agg(jsonb_build_object(
    'firma',p.oid::regprocedure::text,'cuerpo_md5',md5(p.prosrc),
    'definicion_md5',md5(pg_get_functiondef(p.oid)),
    'config',p.proconfig,'definer',p.prosecdef,
    'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text
  ) order by p.oid::regprocedure::text) from pg_proc p where p.oid in (
    'crm.importar_lead_fn(jsonb)'::regprocedure,
    'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'::regprocedure,
    'private.registrar_solicitud_cliente_fn(uuid,text,jsonb)'::regprocedure)),
  'permisos_columnas_anteriores', (select md5(string_agg(
    a.attname||':'||has_column_privilege('authenticated',a.attrelid,a.attnum,'SELECT')::text||':'||
    has_column_privilege('authenticated',a.attrelid,a.attnum,'INSERT')::text||':'||
    has_column_privilege('authenticated',a.attrelid,a.attnum,'UPDATE')::text,
    ',' order by a.attnum)) from pg_attribute a
    where a.attrelid='crm.leads'::regclass and a.attnum>0 and not a.attisdropped
      and a.attname<>'campania_origen'),
  'historicos',jsonb_build_object(
    'leads',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5((to_jsonb(t)-'campania_origen')::text),'' order by id))) from crm.leads t),
    'asignaciones',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from crm.lead_asignaciones t),
    'actividades',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from crm.actividades t),
    'actividades_cliente',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from crm.actividades_cliente t),
    'tareas',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from crm.tareas t),
    'perfiles',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from public.perfiles t),
    'auth_users',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by id))) from auth.users t),
    'flags',(select jsonb_build_object('n',count(*),'md5',md5(string_agg(md5(to_jsonb(t)::text),'' order by nombre))) from crm.multiempresa_flags t)),
  'campania_existe',exists(select 1 from pg_attribute where attrelid='crm.leads'::regclass and attname='campania_origen' and not attisdropped),
  'campanias_no_nulas',(select count(*) from crm.leads l where to_jsonb(l)->>'campania_origen' is not null),
  'rls',(select relrowsecurity from pg_class where oid='crm.leads'::regclass),
  'controles_c1',chr(133) ~ '[[:cntrl:]]' and chr(159) ~ '[[:cntrl:]]',
  'escritores_insert',(select jsonb_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('crm','private') and p.prosrc ~* 'insert\s+into\s+crm\.leads')
) as estado;
