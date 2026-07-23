// Identidades demo — espejo de miembros REALES de EQUIPO_DEMO (lib/demo.ts)
// para que el ámbito jerárquico del store funcione (contrato F1c).
// Se mantienen LITERALES a propósito: importar demo.ts aquí metería el chunk
// de fixtures en el bundle de producción. La sincronía con EQUIPO_DEMO la
// garantiza un test (auth-demo-sincronia), no un import en runtime.
// Directorio NO está en crm.equipo (es lector global del portal), igual que
// en producción: conserva un id sintético fuera del organigrama.
import type { Rol } from './roles'

export const DEMO_YO: Record<Rol, { id: string; nombre_completo: string }> = {
  vendedor: { id: 'd-v1', nombre_completo: 'VENDEDOR UNO' },
  supervisor: { id: 'd-sup1', nombre_completo: 'SUPERVISOR UNO' },
  gerencia: { id: 'd-ger', nombre_completo: 'GERENCIA DEMO' },
  directorio: { id: 'demo-directorio', nombre_completo: 'DIRECTORIO (DEMO)' },
  // Coordinador (C1): tampoco pertenece al organigrama — reparte la cola global
  // a las bandejas de supervisión. Id sintético fuera de EQUIPO_DEMO.
  coordinador: { id: 'demo-coordinador', nombre_completo: 'COORDINADOR (DEMO)' },
}
