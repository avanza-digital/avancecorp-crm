-- Cuerpo de PRODUCCIÓN (= banco reemplazo-inv-db, 18/10/2026) de private.f4_comprobante_visible(text), tal como lo devuelve pg_get_functiondef con
-- search_path vacío. Lo usa reversa.sql para devolver el ayudante del bucket a su huella anterior. NO editar.
CREATE OR REPLACE FUNCTION private.f4_comprobante_visible(p_ruta text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia') and exists (
    select 1 from crm.inversion_solicitudes s join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    where s.datos#>>'{evidencia,ruta}'=p_ruta and (
      private.rol_crm((select auth.uid()))='gerencia'
      or i.responsable_relacion_id in (select private.vendedor_ids_visibles((select auth.uid())))
      or (s.puerta='cliente_existente' and s.analista_cierre_id in (select private.vendedor_ids_visibles((select auth.uid()))))
    )
  ),false);
$function$

;
