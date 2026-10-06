import type { AlertaCRM } from './alertas'

/** Misma selección para Resumen y bandeja; el orden de la fuente no se muta. */
export function alertasActivas(alertas: readonly AlertaCRM[]): AlertaCRM[] {
  const activas = alertas.filter(a => a.reconocimiento == null
    && a.corte?.estado !== 'reconocido' && a.corte?.estado !== 'pospuesto')
  return activas.sort((a, b) => Number(b.severidad === 'critica') - Number(a.severidad === 'critica'))
}

export function textoActualizacion(generadoEn: string | null): string {
  if (!generadoEn || !Number.isFinite(Date.parse(generadoEn))) return 'Actualización no disponible'
  return `Actualizado ${new Intl.DateTimeFormat('es-PE', {
    day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'America/Lima',
  }).format(Date.parse(generadoEn))}`
}

export const VACIO_GERENCIA = 'No se generaron avisos con los datos evaluables. Puede faltar un corte de revisión, una meta o muestra suficiente.'
