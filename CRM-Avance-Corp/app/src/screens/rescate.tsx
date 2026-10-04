// «Base para gestión» (#/rescate) — despacha por rol con el molde de screens/gestion-diaria.tsx.
// F1 (02/10/2026): el analista trabaja SU base (sus descartados, para volver a intentarlo).
// F4 (03/10/2026): Supervisión y Gerencia entran a dos pestañas: «Descartes del mes» (el Centro de rescate de siempre:
// mosaico, carpeta y reparto, sin cambios) y «Gestión de la base» (panel por analista, hoja del equipo, «No contactar»).
import type { JSX } from 'react'
import { ArchiveRestore } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { PanelVacio } from '@/components/common/estado-panel'
import { BaseGestionSupervision } from '@/screens/rescate/supervision'
import { BaseGestionAnalista } from '@/screens/rescate/analista'

export function BaseGestion(): JSX.Element {
  const { yo } = useAuth()
  if (!yo) return <PanelVacio icono={ArchiveRestore} titulo="Sin sesión" detalle="Vuelve a entrar para ver tu base para gestión." />
  // vistas.ts solo deja entrar al analista y a quien reparte; si llega otro rol por una sesión rara,
  // se dice y no se fabrica nada (el servidor también lo rechaza).
  if (yo.rol === 'vendedor') return <BaseGestionAnalista />
  if (yo.rol === 'supervisor' || yo.rol === 'gerencia') return <BaseGestionSupervision />
  return <PanelVacio icono={ArchiveRestore} titulo="La base para gestión no está disponible para tu rol" detalle="Es para analistas, supervisores y gerencia." />
}
