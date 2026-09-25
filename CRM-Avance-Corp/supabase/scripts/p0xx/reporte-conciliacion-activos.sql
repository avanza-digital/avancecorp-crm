-- P-0XX: pendientes de operaciones después del backfill S1.
-- Solo lectura. Ejecutar contra la rama; tras el merge manual, repetir en
-- producción para obtener la lista real y actualizada. No muestra cuenta ni CCI.
-- El analista responsable vigente es perfiles.asesor_perfil_id; el cierre
-- histórico del contrato puede pertenecer a otra persona.
select ct.numero_contrato,
       cli.nombre_completo as cliente,
       cli.dni,
       c.moneda,
       coalesce(analista.nombre_completo, 'Sin analista asignado') as analista,
       c.motivo
from private.conciliacion_cuentas_p0xx c
join public.contratos ct on ct.id = c.contrato_id
join public.perfiles cli on cli.id = c.cliente_id
left join public.perfiles analista on analista.id = cli.asesor_perfil_id
where c.clase = 'contrato'
  and ct.estado = 'activo'
  and not exists (
    select 1 from crm.contrato_cuentas_pago cp where cp.contrato_id = ct.id
  )
order by analista, cliente, c.moneda, ct.numero_contrato;
