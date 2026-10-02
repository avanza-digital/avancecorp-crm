-- SOLO LECTURA: contexto de seguridad (Codex R1): definer/invoker de la cadena y RLS de crm.inversionistas
select json_build_object(
 'funciones', (select json_agg(json_build_object('f', n.nspname||'.'||p.proname, 'definer', p.prosecdef, 'owner', pg_get_userbyid(p.proowner)) order by n.nspname, p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where (n.nspname='private' and p.proname in ('inversionista_canonica','postventa_tarea_json','tareas_clientes_autorizadas','postventa_visible'))
      or (n.nspname='crm' and p.proname in ('postventa_agenda_fn','postventa_tarea_fn','postventa_agendar_fn','cola_accion_v3_fn','tareas_pendientes_fn'))),
 'rls_inversionistas', (select json_build_object('rls', c.relrowsecurity, 'forzada', c.relforcerowsecurity, 'owner', pg_get_userbyid(c.relowner)) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='crm' and c.relname='inversionistas'),
 'policies', (select json_agg(json_build_object('p', policyname, 'cmd', cmd, 'roles', roles::text, 'qual', qual)) from pg_policies where schemaname='crm' and tablename='inversionistas')
)::text v;
