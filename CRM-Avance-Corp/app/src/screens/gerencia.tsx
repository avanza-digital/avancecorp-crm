import type { JSX } from 'react'
import { HoyGerencia } from '@/screens/hoy/gerencia'

export function AlertasGerencia(): JSX.Element {
  return <HoyGerencia seccion="alertas" />
}

export function ConversionesGerencia(): JSX.Element {
  return <HoyGerencia seccion="conversiones" />
}

export function RankingVendedoresGerencia(): JSX.Element {
  return <HoyGerencia seccion="ranking-vendedores" />
}

export function ReunionesGerencia(): JSX.Element {
  return <HoyGerencia seccion="reuniones" />
}

export function MetasGerencia(): JSX.Element {
  return <HoyGerencia seccion="metas" />
}

export function RendimientoGerencia(): JSX.Element {
  return <HoyGerencia seccion="rendimiento" />
}

export function CapitalCierresGerencia(): JSX.Element {
  return <HoyGerencia seccion="capital-cierres" />
}
