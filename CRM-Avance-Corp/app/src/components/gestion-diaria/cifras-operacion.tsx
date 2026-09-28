// Las 4 cifras de la operación (decisión de Miguel, 27/09/2026) en una franja
// FINA: la jerarquía es de la tabla de equipos y de la ficha, como en el
// supervisor. Cada número abre su lista exacta (revisión Codex del plan):
// Llamadas y Contacto → Registro general en «Llamadas» (con el resultado de cada
// llamada); Citas → los equipos ordenados por citas; Sin registro → quiénes son.
import type { JSX } from 'react'
import { cifraPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
import { referenciaCifra } from '@/lib/gestion-diaria-operacion'
import { cn } from '@/lib/utils'
import { FOCO } from './estilos-gestion'

export type DestinoCifra = 'llamadas' | 'contacto' | 'citas' | 'sin_registro'

export function CifrasOperacion({ pulso, esHoy, abrir }: {
  pulso: PulsoGerencia
  esHoy: boolean
  abrir: (destino: DestinoCifra, origen: HTMLElement) => void
}): JSX.Element {
  const a = pulso.actual
  const cifras: { destino: DestinoCifra; etiqueta: string; valor: string; detalle: string; referencia: string; accion: string }[] = [
    { destino: 'llamadas', etiqueta: 'Llamadas', valor: cifraPulso(a.llamadas), detalle: `${a.contestadas} contestaron`,
      referencia: referenciaCifra(pulso, 'llamadas', esHoy), accion: 'Ver las llamadas en el registro general' },
    { destino: 'contacto', etiqueta: 'Contacto', valor: a.tasa_contacto === null ? '—' : `${Math.round(a.tasa_contacto)} %`, detalle: `de ${a.utiles} útiles`,
      referencia: referenciaCifra(pulso, 'tasa_contacto', esHoy, true), accion: 'Ver las llamadas y su resultado en el registro general' },
    { destino: 'citas', etiqueta: 'Citas agendadas', valor: cifraPulso(a.citas_agendadas), detalle: esHoy ? 'hoy' : 'ese día',
      referencia: referenciaCifra(pulso, 'citas_agendadas', esHoy), accion: 'Ver los equipos ordenados por citas' },
    { destino: 'sin_registro', etiqueta: 'Sin registro', valor: `${a.sin_actividad} de ${a.analistas_activos}`, detalle: 'analistas',
      referencia: referenciaCifra(pulso, 'sin_actividad', esHoy), accion: 'Ver quiénes no tienen registro' },
  ]
  return (
    <section aria-label="Cifras de la operación" className="shrink-0 rounded-2xl border border-border bg-card">
      <dl className="grid grid-cols-2 lg:grid-cols-4">
        {cifras.map((c, i) => (
          <div key={c.destino} className={cn('min-w-0 px-5 py-2.5', i % 2 === 1 && 'border-l border-border',
            i === 2 && 'lg:border-l lg:border-border', i >= 2 && 'border-t border-border lg:border-t-0')}>
            <dt className="text-[11.5px] font-bold uppercase tracking-[0.04em] text-[var(--muted-foreground-strong)]">{c.etiqueta}</dt>
            <dd className="mt-0.5 flex flex-wrap items-baseline gap-x-2">
              <button type="button" onClick={(e) => abrir(c.destino, e.currentTarget)} aria-label={`${c.etiqueta}: ${c.valor}. ${c.accion}`}
                className={cn('cursor-pointer rounded-md text-[22px] font-extrabold leading-tight tabular-nums text-primary underline-offset-4 hover:underline pointer-coarse:min-h-11', FOCO)}>
                {c.valor}
              </button>
              <span className="text-xs text-[var(--muted-foreground-strong)]">{c.detalle}</span>
            </dd>
            <dd className="text-[11.5px] tabular-nums text-[var(--muted-foreground-strong)]">{c.referencia}</dd>
          </div>
        ))}
      </dl>
    </section>
  )
}
