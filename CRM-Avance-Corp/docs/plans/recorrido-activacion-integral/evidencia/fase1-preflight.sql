begin transaction read only;set local quote_all_identifiers=off;set local statement_timeout='15s';
select jsonb_build_object(
 'fecha',clock_timestamp(),
 'contratos', (select jsonb_agg(jsonb_build_object('firma',firma,'esperado',huella,'actual',case when to_regprocedure(firma) is not null then md5(pg_get_functiondef(to_regprocedure(firma))) end,'coincide',case when to_regprocedure(firma) is not null then md5(pg_get_functiondef(to_regprocedure(firma)))=huella else false end)) from (values
 ('crm.eliminar_lead_error_carga(uuid,text)','15ce9327e21306ec9682552815936e71'),
 ('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)','c0fa9a8ebb04cf84bc41155d4a318e30'),
 ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','b40dded8a923dcd02f028b24bc4de94e'),
 ('crm.confirmar_inversion_revisada_fn(uuid,integer)','68828d0a443160310a3fb2fd82cd7041'),
 ('crm.acceso_inversion_fn(uuid,text,jsonb)','38229cbb9fde4d9b5e23ee55ca6e6784'),
 ('private.conversion_lead_con_inversion()','0edf5180578781961aacbf0e78df242e')) as esperado(firma,huella)),
 'triggers_conversion',(select jsonb_agg(jsonb_build_object('tabla',tgrelid::regclass::text,'trigger',tgname,'definicion',pg_get_triggerdef(oid),'habilitado',tgenabled)) from pg_trigger where tgfoid=to_regprocedure('private.conversion_lead_con_inversion()')),
 'instalado',to_regclass('crm.recorrido_control') is not null
) as diagnostico;rollback;
