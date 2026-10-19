CREATE OR REPLACE FUNCTION crm.cerrar_reunion_v2(p_operacion_id uuid, p_tarea_id uuid, p_estado text, p_resultado_reunion text DEFAULT NULL::text, p_motivo_no_realizada text DEFAULT NULL::text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select private.sla_ejecutar_comando(p_operacion_id,'cerrar_reunion',p_tarea_id,
   jsonb_build_object('estado',p_estado,'resultado_reunion',p_resultado_reunion,
     'motivo_no_realizada',p_motivo_no_realizada,'detalle',nullif(btrim(p_detalle),''),'siguiente',p_siguiente));
$function$
