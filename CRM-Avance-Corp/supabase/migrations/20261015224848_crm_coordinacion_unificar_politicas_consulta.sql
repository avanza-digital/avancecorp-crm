-- Consolida los OR equivalentes y elimina los avisos de policies SELECT duplicadas.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy
    where polrelid='crm.leads'::regclass and polname='leads_select'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  select pg_get_expr(polqual,polrelid) into b from pg_policy
    where polrelid='crm.leads'::regclass and polname='leads_coordinacion_consulta'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  if md5(a) is distinct from '073deaeb5700bac14209ec795b71567e'
    or md5(b) is distinct from 'fba6e31dada25538a9633d9c7608fa6a' then
    raise exception 'Cambió la policy de consulta de leads; revisar antes de aplicar';
  end if;
  execute format('alter policy leads_select on crm.leads using ((%s) or (%s))',a,b);
end; $$;
drop policy leads_coordinacion_consulta on crm.leads;
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy
    where polrelid='crm.actividades'::regclass and polname='actividades_select'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  select pg_get_expr(polqual,polrelid) into b from pg_policy
    where polrelid='crm.actividades'::regclass and polname='actividades_coordinacion_consulta'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  if md5(a) is distinct from 'e80e3af900b8d9616c28dcd836f1ac94'
    or md5(b) is distinct from 'd2f5929cb5e463dff782f37e68c3c463' then
    raise exception 'Cambió la policy de consulta de actividades; revisar antes de aplicar';
  end if;
  execute format('alter policy actividades_select on crm.actividades using ((%s) or (%s))',a,b);
end; $$;
drop policy actividades_coordinacion_consulta on crm.actividades;
do $$ declare a text; b text; begin
  select pg_get_expr(polqual,polrelid) into a from pg_policy
    where polrelid='crm.tareas'::regclass and polname='tareas_select'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  select pg_get_expr(polqual,polrelid) into b from pg_policy
    where polrelid='crm.tareas'::regclass and polname='tareas_coordinacion_consulta'
      and polcmd='r' and polpermissive and polroles=array['authenticated'::regrole::oid];
  if md5(a) is distinct from '073deaeb5700bac14209ec795b71567e'
    or md5(b) is distinct from '69b46464b2a5cf3c947324d0994a577a' then
    raise exception 'Cambió la policy de consulta de tareas; revisar antes de aplicar';
  end if;
  execute format('alter policy tareas_select on crm.tareas using ((%s) or (%s))',a,b);
end; $$;
drop policy tareas_coordinacion_consulta on crm.tareas;
notify pgrst,'reload schema';
commit;
