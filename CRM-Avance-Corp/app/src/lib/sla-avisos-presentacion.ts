import type { AlertaCRM } from './alertas'
import type { Rol } from './roles'
import type { AvisoSla, ResumenAvisosSla } from './sla-operacion'

const causas: Record<AvisoSla['bucket'], string> = {
  primera_atencion: 'contactos iniciales', tarea_vencida: 'actividades por revisar',
  seguimiento: 'seguimientos por retomar', revision_comercial: 'casos por decidir',
  datos_incompletos: 'fichas por revisar', por_repartir: 'oportunidades por asignar',
}

/** Una entrada acotada abre la lista paginada. No enumera la cartera ni calcula plazos. */
export function alertaResumenSla(resumen: ResumenAvisosSla, actor: string, rol: Rol | null): AlertaCRM[] {
  if (resumen.modo !== 'activo' || resumen.total_oportunidades === 0) return []
  const total = resumen.total_oportunidades.toLocaleString('es-PE')
  return [{
    id: `sla-v2:${actor}`, tipo: 'seguimiento_comercial',
    severidad: resumen.criticas > 0 ? 'critica' : 'atencion',
    alcance: rol === 'vendedor' ? 'personal' : rol === 'supervisor' ? 'equipo' : 'empresa',
    titulo: `Revisa ${total} ${resumen.total_oportunidades === 1 ? 'oportunidad pendiente' : 'oportunidades pendientes'}`,
    detalle: resumen.grupos.map((grupo) => `${grupo.total.toLocaleString('es-PE')} ${causas[grupo.bucket]}`).join(' · '),
    responsableId: null, responsable: null, valor: resumen.total_oportunidades,
    destino: { vista: 'seguimiento', etiqueta: 'Ver pendientes' },
    // Sin miembros/reconocimiento: leer este aviso no resuelve sus condiciones.
  }]
}
