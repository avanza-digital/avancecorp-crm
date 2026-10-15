import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import type { CategoriaContrato } from '@/lib/cronograma'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'

const Confirmacion = v.object({
  ok: v.literal(true), cambio: v.boolean(), contrato_id: v.pipe(v.string(), v.uuid()),
  categoria: v.picklist(['nuevo', 'renovacion', 'upgrade']),
})

export async function corregirCategoriaInversion(contrato: string, categoria: CategoriaContrato, motivo: string) {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const r = await sb.schema('crm').rpc('corregir_categoria_contrato_fn', {
    p_contrato_id: contrato, p_categoria: categoria, p_motivo: motivo.trim(),
  })
  const confirmado = respuestaInversionistas(Confirmacion, r)
  if (confirmado.contrato_id !== contrato || confirmado.categoria !== categoria) {
    throw new CrmApiError('No se confirmó la categoría de esta inversión. Vuelve a consultar.', 'RESPUESTA_INCOMPLETA')
  }
  return confirmado
}
