-- Evidencia de solo lectura capturada después de la activación.
-- Conserva valores observados en producción, sin usar el banco como evidencia.
begin read only;
set local search_path=pg_catalog;
set local quote_all_identifiers=off;
set local statement_timeout='30s';
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
), comparacion as (
  select coalesce(i.version,e.version) as version,i.nombre,i.huella,
    e.nombre as nombre_esperado,e.huella as huella_esperada,
    e.version is not null and i.version is not null
      and e.nombre is not distinct from i.nombre and e.huella is not distinct from i.huella as coincide
  from esperado e full join instalado i using(version)
)
select jsonb_build_object(
  'fecha_captura',clock_timestamp(),
  'proyecto','dctqcbznekcyxhjujuci',
  'entorno','produccion',
  'alcance','Revalidacion de solo lectura posterior a la activacion; no sustituye ni retrodata el control inicial observado',
  'sql_fuente','../operacion/06-evidencia-paquete-produccion.sql',
  'postgres',current_setting('server_version'),
  'historial',jsonb_build_object(
    'total',(select count(*) from supabase_migrations.schema_migrations),
    'base',(select count(*) from supabase_migrations.schema_migrations where version<='20261018053228'),
    'paquete',(select count(*) from instalado),
    'base_digest',(select md5(string_agg(version||':'||coalesce(name,'')||':'||coalesce(array_to_string(statements,E'\n'),''),E'\n' order by version)) from supabase_migrations.schema_migrations where version<='20261018053228')
  ),
  'identidad_paquete_coincide',(select count(*)=15 and bool_and(coincide) from comparacion),
  'migraciones',(select jsonb_agg(jsonb_build_object('version',version,'nombre',nombre,'md5_statements',huella,'nombre_esperado',nombre_esperado,'md5_esperado',huella_esperada,'coincide',coincide) order by version) from comparacion),
  'control_al_capturar',(select jsonb_build_object('modo',modo,'revision',revision,'cohorte_desde',cohorte_desde) from crm.recorrido_control where id)
) as evidencia;
commit;
