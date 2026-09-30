-- Retirar primero el frontend que llama a estas RPC. Sin CASCADE ni borrado de datos.
begin;
drop function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text);
drop function crm.crear_lead_documento_fn(jsonb,text,text);
drop function crm.fijar_documento_lead_fn(uuid,text,text,uuid,text);
drop function crm.documento_lead_fn(uuid);
drop function private.validar_documento_lead(text,text);
notify pgrst,'reload schema';
commit;
