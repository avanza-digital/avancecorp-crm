-- Solo lectura. Ejecutar inmediatamente antes del merge de la rama autorizada.
begin read only;
set local search_path=pg_catalog;
set local quote_all_identifiers=off;
set local statement_timeout='30s';
set local lock_timeout='3s';
do $$
begin
 if (select count(*) from supabase_migrations.schema_migrations)<>509
   or (select md5(string_agg(version||':'||coalesce(name,'')||':'||coalesce(array_to_string(statements,E'\n'),''),E'\n' order by version)) from supabase_migrations.schema_migrations)<>'8fe3fd28649301bac91ed91973d1dc8c' then
   raise exception 'Cambio el historial productivo; reconciliar antes del merge' using errcode='55000';
 end if;
 if to_regclass('crm.recorrido_control') is not null then
   raise exception 'El recorrido ya existe; no repetir instalacion inicial' using errcode='55000';
 end if;
 if current_setting('server_version_num')::integer/10000<>17 then
   raise exception 'Revisar version de PostgreSQL antes de instalar';
 end if;
end $$;
do $$
declare r record;v_firma text;v_md5 text;
begin
  for v_firma,v_md5 in select * from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','38229cbb9fde4d9b5e23ee55ca6e6784'),
    ('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)','c0fa9a8ebb04cf84bc41155d4a318e30'),
    ('crm.confirmar_inversion_revisada_fn(uuid,integer)','68828d0a443160310a3fb2fd82cd7041'),
    ('crm.eliminar_lead_error_carga(uuid,text)','15ce9327e21306ec9682552815936e71'),
    ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','b40dded8a923dcd02f028b24bc4de94e'),
    ('private.conversion_lead_con_inversion()','0edf5180578781961aacbf0e78df242e')
  ) x(firma,huella) loop
    if to_regprocedure(v_firma) is null or md5(pg_get_functiondef(to_regprocedure(v_firma)))<>v_md5 then
      raise exception 'Contrato distinto: %',v_firma using errcode='55000';
    end if;
  end loop;
end $$;
select current_setting('server_version') as postgres,private.assert_sla_nucleo() as sla;
commit;
