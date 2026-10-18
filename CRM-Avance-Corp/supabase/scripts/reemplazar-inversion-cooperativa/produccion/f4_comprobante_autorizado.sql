-- Cuerpo de PRODUCCIÓN (= banco reemplazo-inv-db, 18/10/2026) de private.f4_comprobante_autorizado(text), tal como lo devuelve pg_get_functiondef con
-- search_path vacío. Lo usa reversa.sql para devolver el ayudante del bucket a su huella anterior. NO editar.
CREATE OR REPLACE FUNCTION private.f4_comprobante_autorizado(p_ruta text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_persona uuid; v_solicitud uuid; v_ctx jsonb; v_s crm.inversion_solicitudes%rowtype;
begin
  if p_ruta is null or p_ruta !~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then return false; end if;
  begin v_persona:=split_part(p_ruta,'/',1)::uuid; v_solicitud:=split_part(p_ruta,'/',2)::uuid;
  exception when invalid_text_representation then return false; end;
  v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=v_solicitud),v_solicitud,null::uuid);
  select * into v_s from crm.inversion_solicitudes where id=v_solicitud for share;
  return found and v_s.inversionista_id=v_persona and v_s.estado='preparada'
    and (v_s.puerta='cliente_existente' or v_s.responsable_esperado_id=(v_ctx->>'responsable_id')::uuid)
    and private.venta_cruzada_opera(v_solicitud)
    and v_s.datos#>>'{evidencia,ruta}'=p_ruta;
exception when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then return false;
end;
$function$

;
