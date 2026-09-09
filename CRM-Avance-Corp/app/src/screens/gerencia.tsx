import type { JSX } from 'react'
import { HoyGerencia } from '@/screens/hoy/gerencia'
import { useAuth } from '@/lib/auth-context'
import { CitasGerencia } from '@/screens/hoy/citas-gerencia'

export function ConversionesGerencia(): JSX.Element {
  return <HoyGerencia seccion="conversiones" />
}

export function RankingVendedoresGerencia(): JSX.Element {
  return <HoyGerencia seccion="ranking-vendedores" />
}

export function ReunionesGerencia(): JSX.Element {
  const { yo } = useAuth()
  return yo?.rol === 'gerencia' ? <CitasGerencia key={yo.id} /> : <HoyGerencia seccion="reuniones" />
}

export function MetasGerencia(): JSX.Element {
  return <HoyGerencia seccion="metas" />
}

export function RendimientoGerencia(): JSX.Element {
  return <HoyGerencia seccion="rendimiento" />
}
