import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { useAuth } from '@/lib/auth-context'
import type { Lead } from '@/lib/tipos'
import { DocumentoLeadSchema, type DocumentoLead } from '@/lib/documento-lead'
export type { DocumentoLead } from '@/lib/documento-lead'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'
export async function obtenerDocumentoLead(lead: string, signal?: AbortSignal): Promise<DocumentoLead> {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const consulta = sb.schema('crm').rpc('documento_lead_fn', { p_lead_id: lead })
  const documento = respuestaInversionistas(DocumentoLeadSchema, await (signal ? consulta.abortSignal(signal) : consulta))
  if (documento.lead_id !== lead) throw new CrmApiError('El documento no corresponde al lead consultado.', 'DOCUMENTO_LEAD_CONTRACT')
  return documento
}

/** Solo al abrir una ficha/conversión; nunca una consulta extra por fila de cartera.
 * `activa` en falso deja de leer: quien ya fijó el documento no necesita relecturas. */
export function useDocumentoLead(lead: Lead, activa = true) {
  const { yo } = useAuth()
  const consulta = useQuery({
    queryKey: ['crm', 'leads', 'documento', yo?.id, lead.id, lead.actualizado_en],
    queryFn: ({ signal }) => obtenerDocumentoLead(lead.id, signal),
    enabled: Boolean(yo && !yo.demo) && activa, retry: false, staleTime: 0, gcTime: 0,
  })
  const demo: DocumentoLead = {
    lead_id: lead.id, inversionista_id: null, identificador_id: null,
    tipo: lead.documento?.tipo ?? 'DNI', numero: lead.documento?.numero ?? lead.dni ?? null,
    puede_corregir: false,
  }
  return { ...consulta, data: yo?.demo ? demo : consulta.data,
    isPending: Boolean(!yo?.demo && consulta.isPending), isError: Boolean(!yo?.demo && consulta.isError),
    isFetchedAfterMount: Boolean(yo?.demo) || consulta.isFetchedAfterMount }
}
