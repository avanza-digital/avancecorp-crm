import { useAuth } from './auth-context'
import { useCRMData } from './store-context'
import { ETAPA_INFO, type Actividad, type Lead } from './tipos'
import { COLOR_GESTIONADO, columnaDeLead } from './pipeline-columnas'

/** Rótulo operativo compartido; las etapas guardadas y sus acciones no cambian. */
export function etapaVisible(lead: Lead, actividadesDemo?: readonly Actividad[]) {
  if (lead.etapa !== 'nuevo' || !lead.activo || lead.vendedor_id == null) return { k: lead.etapa, ...ETAPA_INFO[lead.etapa] }
  const gestion = actividadesDemo
    ? columnaDeLead(lead, actividadesDemo) === 'gestionado'
    : lead.gestion_vigente
  if (gestion === true) return { k: 'gestionado', label: 'Gestionado', color: COLOR_GESTIONADO }
  if (gestion === false || lead.tenencia_desde == null) return { k: 'nuevo', ...ETAPA_INFO.nuevo }
  return { k: 'sin_verificar', label: 'Gestión sin verificar', color: ETAPA_INFO.nuevo.color }
}

export function useEtapaVisible() {
  const { yo } = useAuth()
  const { actividadesDelAmbito } = useCRMData()
  return (lead: Lead) => etapaVisible(lead, yo?.demo ? actividadesDelAmbito : undefined)
}
