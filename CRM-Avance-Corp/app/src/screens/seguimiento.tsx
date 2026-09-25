import { ColaSeguimiento } from '@/components/app/cola-seguimiento'

/** Cartera operativa actual: no consume el período ni el origen de Gerencia. */
export function Seguimiento() {
  return (
    <div className="mx-auto w-full max-w-[1640px]">
      <ColaSeguimiento />
    </div>
  )
}
