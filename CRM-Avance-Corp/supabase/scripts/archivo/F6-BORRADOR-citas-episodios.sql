-- P-055 Fase 6 · Bloque A — EL NUCLEO DE CITAS (borrador, SIN PUBLICAR).
--
-- QUE: una sola funcion que responde "¿que citas hubo y en que quedaron?".
-- Una fila por cita (tarea tipo reunion, viva) con TODAS las banderas que hoy
-- viven incrustadas en `private.metricas_reuniones_implementacion`. Extraccion
-- LITERAL: mismas expresiones, mismo huso, para que la paridad sea exigible.
--
-- DECISIONES FIRMADAS (contrato F6, 2026-08-30): la cita anulada QUEDA (columna
-- propia; pactadas la incluye) · ventana por `vence_en` en el rango pedido.
create or replace function private.citas_episodios(
  p_ini timestamptz,
  p_fin timestamptz,
  p_ahora timestamptz default now()
)
returns table (
  tarea_id uuid,
  lead_id uuid,
  vendedor_id uuid,
  cancelada_por_id uuid,
  vence_en timestamptz,
  estado text,
  modalidad text,
  resultado text,
  debio_ocurrir boolean,
  realizada boolean,
  no_show boolean,
  cancelada_asesor boolean,
  cancelada_sistema boolean,
  reprogramada boolean,
  pendiente_cierre boolean,
  programada_futura boolean
)
language sql
stable
security definer
set search_path to ''
as $function$
  select t.id,
         t.lead_id,
         t.vendedor_id,
         t.cancelada_por_id,
         t.vence_en,
         t.estado,
         coalesce(t.modalidad_reunion, 'sin_clasificar'),
         coalesce(t.resultado_reunion, 'sin_clasificar'),
         t.vence_en <= p_ahora,
         t.estado = 'completada',
         t.estado = 'no_show',
         (t.estado = 'cancelada' and t.cancelada_por = 'asesor'),
         (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor'),
         t.estado = 'reprogramada',
         (t.estado = 'pendiente' and t.vence_en <= p_ahora),
         (t.estado = 'pendiente' and t.vence_en > p_ahora)
  from crm.tareas t
  where t.tipo = 'reunion'
    and t.activo
    and t.vence_en >= p_ini
    and t.vence_en < p_fin;
$function$;

revoke all on function private.citas_episodios(timestamptz, timestamptz, timestamptz) from public;
