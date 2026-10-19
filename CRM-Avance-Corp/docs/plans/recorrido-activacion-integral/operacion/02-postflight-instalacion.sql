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
