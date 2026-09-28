import type { JSX } from 'react'
import { HoyGerencia } from '@/screens/hoy/gerencia'
import { useAuth } from '@/lib/auth-context'
import { can } from '@/lib/roles'
import { CitasGerencia } from '@/screens/hoy/citas-gerencia'

export function ConversionesGerencia(): JSX.Element {
  return <HoyGerencia seccion="conversiones" />
}

export function RankingVendedoresGerencia(): JSX.Element {
  return <HoyGerencia seccion="ranking-vendedores" />
}

export function ReunionesGerencia(): JSX.Element {
  const { yo } = useAuth()
  return can(yo?.rol, 'verCitasEquipo') ? <CitasGerencia key={yo?.id} /> : <HoyGerencia seccion="reuniones" />
}

export function MetasGerencia(): JSX.Element {
  return <HoyGerencia seccion="metas" />
}

export function RendimientoGerencia(): JSX.Element {
  return <HoyGerencia seccion="rendimiento" />
}
