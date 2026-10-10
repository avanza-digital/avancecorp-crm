CREATE OR REPLACE FUNCTION private.facturacion_operaciones_visibles(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with quien as materialized (
    -- Una sola vez: quién pregunta y con qué rol. `private.rol_crm` devuelve
    -- NULL para quien no es miembro del CRM.
    select
      (select auth.uid()) as uid,
      private.rol_crm((select auth.uid())) as rol,
      private.es_lector_global() as lector
  ),
  ambito as materialized (
    -- La verja, en tres columnas. NULL = 'gerencia' es NULL, y el coalesce lo
    -- cierra en false. `ok` abre el núcleo; `es_global` y `subarbol` recortan.
    select
      q.uid,
      coalesce(q.uid is not null and (q.rol = 'gerencia' or q.lector), false) as es_global,
      coalesce(q.uid is not null and (q.rol in ('gerencia', 'supervisor') or q.lector), false) as ok,
      -- El subárbol de HOY del supervisor (él incluido). Para cualquier otro
      -- rol queda VACÍO a propósito: así el predicado final no puede abrirse
      -- por accidente para nadie más.
      case when coalesce(q.uid is not null and q.rol = 'supervisor', false)
           then array(select private.vendedor_ids_visibles(q.uid))
           else '{}'::uuid[] end as subarbol
    from quien q
  )
  select ep.*
  from (select * from ambito a where a.ok) a
  -- La dependencia de a.ok mantiene el lateral detrás de la verja incluso si
  -- el planificador reordena joins: con cero actores autorizados no se llama.
  cross join lateral private.facturacion_operaciones(
    case when a.ok then p_desde end, p_hasta
  ) ep
  -- EL RECORTE DEL SUPERVISOR (ver cabecera): el supervisor de entonces es él o
  -- alguien de su subárbol, o la venta es suya. Gerencia y el lector global
  -- pasan enteros. Un `= any('{}')` es false y un supervisor NULL da NULL: para
  -- quien no es supervisor solo queda `es_global`, que para él es false — y de
  -- todos modos `episodios` ya salió vacío por `a.ok`.
  where a.es_global
     or ep.supervisor_id = any(a.subarbol)
     or ep.analista_id = a.uid;
$function$
