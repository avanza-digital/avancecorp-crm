-- Solo lectura. Confirmar catalogo antes de cualquier activacion.
begin read only;
set local search_path=pg_catalog;
set local quote_all_identifiers=off;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
begin
 if (select count(*) from supabase_migrations.schema_migrations)<>524
   or (select md5(string_agg(version||':'||coalesce(name,'')||':'||coalesce(array_to_string(statements,E'\n'),''),E'\n' order by version)) from supabase_migrations.schema_migrations where version<='20261018053228')<>'8fe3fd28649301bac91ed91973d1dc8c'
   or (select count(*) from supabase_migrations.schema_migrations where version>'20261018053228')<>15 then
   raise exception 'Historial distinto del paquete ensayado' using errcode='55000';
 end if;
 if exists(
   with esperado(version,nombre,huella) as (values
      ('20261019001500','crm_recorrido_evaluacion','4ad66afc274531dac9d8c488dca47034'),
      ('20261019001501','crm_recorrido_evaluacion_hardening','8535973e1a14efea415de4045a033ca2'),
      ('20261019001600','crm_recorrido_oficina','8a179542deceff1b66e3cde26172a2aa'),
      ('20261019001601','crm_recorrido_oficina_hardening','bafbf8f54c1ccb2d4d3c1a8076331cde'),
      ('20261019001700','crm_recorrido_conversion','464b6c7808b549b980bd9cb695ba4395'),
      ('20261019001701','crm_recorrido_conversion_hardening','b46941581ac2e1695d2e09601cae566b'),
      ('20261019001702','crm_recorrido_revision_pr','0b1b1fc3e5ed6f03d3ca302b2309031b'),
      ('20261019001703','crm_recorrido_revision_pr_hardening','af15dca5751fb54cf3cb43e86db9e3e9'),
      ('20261019061000','crm_recorrido_todos_pendientes','93efbccf4710936c1f30fc3e290f3804'),
      ('20261019061001','crm_recorrido_todos_pendientes_hardening','f04e23ea2f809ac62489c841149962b7'),
      ('20261019061002','crm_recorrido_indice_cita','5bf8249322647d58add23632d2630852'),
      ('20261019061003','crm_recorrido_conflicto_http','22f3b5a2e6ea8c33e60a88b845340e59'),
      ('20261019061004','crm_recorrido_conflicto_http_hardening','3db06897cbeab7075858e73876be7fc9'),
      ('20261019061005','crm_recorrido_revision_claude','e681672bec7bbc521561fa5bca5e8613'),
      ('20261019061006','crm_recorrido_revision_claude_hardening','0959abf39b91c3d875e5e48c39a83144')
   ), instalado as (
     select version,name as nombre,md5(array_to_string(statements,E'\n')) as huella
       from supabase_migrations.schema_migrations where version>'20261018053228'
   )
   select 1 from esperado e full join instalado i using(version)
   where e.version is null or i.version is null or e.nombre is distinct from i.nombre or e.huella is distinct from i.huella
 ) then
   raise exception 'Identidad o contenido distinto en las migraciones instaladas' using errcode='55000';
 end if;
 if not exists(select 1 from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attname='oficina_tarea_id'
   where i.indexrelid=to_regclass('crm.actividad_ciclo_contexto_oficina_tarea_idx')
     and i.indrelid='crm.actividad_ciclo_contexto'::regclass and i.indisvalid and i.indisready and i.indkey[0]=a.attnum) then
   raise exception 'El indice de la cita del recorrido no esta operativo' using errcode='55000';
 end if;
 if not exists(select 1 from crm.recorrido_control where id and modo='observacion' and revision=1 and cohorte_desde is null) then
   raise exception 'La instalacion no conserva su estado inicial de observacion' using errcode='55000';
 end if;
 if exists(select 1 from pg_trigger where tgrelid in ('crm.leads'::regclass,'crm.actividades'::regclass,'crm.tareas'::regclass,'crm.inversion_solicitudes'::regclass) and not tgisinternal and tgenabled<>'O') then
   raise exception 'Hay triggers inactivos en las tablas del recorrido';
 end if;
end $$;
do $$
declare r record;v_firma text;v_md5 text;
begin
  for v_firma,v_md5 in select * from (values
    ('crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text)','3a5b9b0a233295b4d4fcbdf813a9a465'),
    ('crm.recorrido_configurar_fn(text,text,integer,timestamp with time zone)','e117179d10e2bc67b203e929647f7c53'),
    ('crm.recorrido_leads_fn(uuid[])','8490c4183e4f7a52753b53bed70b344a'),
    ('private.recorrido_bloquear_insert()','e8f30dcb71d5a0797e18a167ba64e953'),
    ('private.recorrido_capturar_actividad()','f4cd2764fe29966230687b1b2e250982'),
    ('private.recorrido_contexto_guard()','503d0ff5b52825e0a28f03ccde47b552'),
    ('private.recorrido_control_guard()','14cf400ab3e7b6cb19d84e572570a05a'),
    ('private.recorrido_evaluar(uuid[])','5ee9a8d476e315aa8f9b94c4e9c93cad'),
    ('private.recorrido_exigir(uuid,text)','aa974c790c6e8418968111a496861fc0'),
    ('private.recorrido_insert_convertido_guard()','fb93076ab61b64588264bba57a826f7b'),
    ('private.recorrido_serializar_invalidacion()','70e15621fbcf5d8ac38bb524114616e7'),
    ('private.recorrido_solicitud_guard()','b8706eb77e491f3e9492899633401817'),
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','b45c309fce1003058ee42de5804d95a9'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','33af606a814c74de5de8a080430bb299'),
    ('crm.eliminar_lead_error_carga(uuid,text)','a83f9db00b71b3efa7114fbced3203bb'),
    ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','df451bd3cc831e2b47a26eb867c9e65e'),
    ('private.conversion_lead_con_inversion()','e8c5fff978355f9c78a56cab67a1c65e')
  ) x(firma,huella) loop
    if to_regprocedure(v_firma) is null or md5(pg_get_functiondef(to_regprocedure(v_firma)))<>v_md5 then
      raise exception 'Contrato distinto: %',v_firma using errcode='55000';
    end if;
  end loop;
end $$;
select private.assert_sla_nucleo() as sla;
select modo,revision,cohorte_desde from crm.recorrido_control;
commit;
