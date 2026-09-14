import { colorVsObjetivo } from '@/lib/inteligencia'
import { SEMAFORO } from '@/lib/semaforo'
import { CORTE_DIA } from './modelo'

export const RITMO_ESPERADO = CORTE_DIA / 30 * 100
export const SENALES = {
  cumplida: { texto: 'Meta alcanzada', color: SEMAFORO.ok, tinta: 'var(--accent-press)' },
  ritmo: { texto: 'A ritmo del mes', color: SEMAFORO.ok, tinta: 'var(--muted-foreground-strong)' },
  atencion: { texto: 'Por mejorar', color: SEMAFORO.atencion, tinta: 'var(--warning-text)' },
  prioridad: { texto: 'Brecha alta: revisar', color: SEMAFORO.critico, tinta: 'var(--destructive-text)' },
  sin_base: { texto: 'Sin base para evaluar', color: SEMAFORO.neutro, tinta: 'var(--muted-foreground-strong)' },
} as const
export type Senal = keyof typeof SENALES

/** Misma escala comercial del CRM: meta, al menos la mitad, menos de la mitad. */
export function senalObjetivo(valor: number | null, objetivo: number): Senal {
  if (valor === null || !Number.isFinite(valor) || !Number.isFinite(objetivo) || objetivo <= 0) return 'sin_base'
  const color = colorVsObjetivo(valor, objetivo)
  return color === SEMAFORO.ok ? 'cumplida' : color === SEMAFORO.atencion ? 'atencion' : 'prioridad'
}

/** Señal orientativa; no cambia el porcentaje ni prorratea la meta de negocio. */
export function senalCitas(cumplimiento: number | null): Senal {
  if (cumplimiento === null || !Number.isFinite(cumplimiento)) return 'sin_base'
  if (cumplimiento >= 100) return 'cumplida'
  const ritmo = senalObjetivo(cumplimiento, RITMO_ESPERADO)
  return ritmo === 'cumplida' ? 'ritmo' : ritmo
}
