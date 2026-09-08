-- Revierte exclusivamente 20260908160127; aborta si las inserciones cambiaron.
-- Conserva todas las solicitudes, decisiones, contratos y la política R4.
begin;
set local lock_timeout='5s';
do $rollback$
declare v_def text; v_bloque text;
begin
  v_def := pg_get_functiondef('crm.solicitar_tasa_fn(jsonb)'::regprocedure);
  v_bloque := E'  perform private.rentabilidad_bloquear_operacion(v_cliente, v_cat, v_origen);\n';
  if cardinality(string_to_array(v_def,v_bloque)) <> 2 then raise exception 'La puerta de solicitud cambió'; end if;
  execute replace(v_def,v_bloque,'');
  v_def := pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure);
  v_bloque := $insert$
 -- Fuera del manejador de observación: ni los errores ni P0411 se ignoran.
 -- R4 ya resolvió el origen y consumió su GUC una sola vez; no volver a leerlo.
 if tg_op = 'INSERT' and v_c.id is not null and v_c.es_demo is not true then
   perform private.rentabilidad_exigir_respuesta(v_c.cliente_id, v_c.categoria, coalesce(v_origen, v_origen_dec));
 end if;
$insert$;
  if cardinality(string_to_array(v_def,v_bloque)) <> 2 then raise exception 'El candado cambió'; end if;
  execute replace(v_def,v_bloque,'');
end;
$rollback$;
drop function private.rentabilidad_exigir_respuesta(uuid,text,uuid);
drop function private.rentabilidad_bloquear_operacion(uuid,text,uuid);
notify pgrst, 'reload schema';
commit;
