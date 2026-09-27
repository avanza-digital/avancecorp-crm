// Pantalla Hoy (F1c) — wrapper que enruta por rol: cada rango ve SU propio
// universo e inteligencia (screens/hoy/*). El ámbito de datos lo recorta el
// store (useCRMData().ambito); aquí solo se decide QUÉ panel renderizar.
import type { JSX } from 'react'
import { useAuth } from '@/lib/auth-context'
import { HoyVendedor } from './hoy/vendedor'
// Puesto de mando (27/09/2026). Rollback = volver a <HoySupervisor /> de './hoy/supervisor'.
import { HoySupervisorMando } from './hoy/supervisor-mando'
import { HoyGerencia } from './hoy/gerencia'
import { HoyDirectorio } from './hoy/directorio'
import { ConfiguracionRespuestasTasa } from '@/components/app/respuestas-tasa'

export function Hoy(): JSX.Element {
  const { yo } = useAuth()
  switch (yo?.rol) {
    case 'supervisor':
      return <><ConfiguracionRespuestasTasa soloActivacion /><HoySupervisorMando /></>
    case 'gerencia':
      return <HoyGerencia seccion="resumen" />
    case 'directorio':
      return <HoyDirectorio />
    case 'vendedor':
    default:
      // Rol desconocido degrada al panel de analista: su ámbito es el más
      // restrictivo (solo leads propios — para una sesión rara, ninguno).
      return <><ConfiguracionRespuestasTasa soloActivacion /><HoyVendedor /></>
  }
}
