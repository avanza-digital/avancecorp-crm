import type { CompletarTareaInput } from '@/lib/store'
import { CrmApiError } from './crm-api'
import { ejecutarComandoSla } from './sla-operacion-comandos'

/** El formulario de cierre existente suministra resultado, capital y próxima
 * acción. El servidor crea la cita real; nunca se inserta una tarea optimista. */
export async function registrarAtencionOficina(actor: string, leadId: string, input: CompletarTareaInput): Promise<void> {
  if (input.estado !== 'completada' || !input.resultado_reunion) {
    throw new CrmApiError('Confirma la asistencia y el resultado de la entrevista.', '22023')
  }
  await ejecutarComandoSla(actor, 'recorrido_atender_oficina_fn', leadId, {
    p_lead_id: leadId,
    p_resultado_reunion: input.resultado_reunion,
    p_detalle: input.resultado_detalle ?? null,
    p_siguiente: input.siguiente ?? null,
    p_capital_estimado: input.capital?.monto_estimado ?? null,
    p_moneda: input.capital?.moneda ?? null,
    p_ubicacion: 'Oficina',
  })
}
