// «Base para gestión» (#/rescate) — despacha por rol con el molde de screens/gestion-diaria.tsx.
// F1 (02/10/2026): el analista trabaja SU base (sus descartados, para volver a intentarlo);
// Supervisión y Gerencia conservan el Centro de rescate (mosaico, carpeta y reparto) sin cambios.
import type { JSX } from 'react'
import { ArchiveRestore } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { PanelVacio } from '@/components/common/estado-panel'
import { RescateDescartados } from '@/screens/rescate-descartados'
import { BaseGestionAnalista } from '@/screens/rescate/analista'

export function BaseGestion(): JSX.Element {
  const { yo } = useAuth()
  if (!yo) return <PanelVacio icono={ArchiveRestore} titulo="Sin sesión" detalle="Vuelve a entrar para ver tu base para gestión." />
  // vistas.ts solo deja entrar al analista y a quien reparte; si llega otro rol por una sesión rara,
  // se dice y no se fabrica nada (el servidor también lo rechaza).
  if (yo.rol === 'vendedor') return <BaseGestionAnalista />
  if (yo.rol === 'supervisor' || yo.rol === 'gerencia') return <RescateDescartados />
  return <PanelVacio icono={ArchiveRestore} titulo="La base para gestión no está disponible para tu rol" detalle="Es para analistas, supervisores y gerencia." />
}
