import type { CSSProperties } from 'react'
import { Check, CircleAlert, Minus, TrendingUp, TriangleAlert } from 'lucide-react'
import { colorVsObjetivo } from '@/lib/inteligencia'
import { SEMAFORO } from '@/lib/semaforo'
import { numero } from '@/lib/format'

const SENALES = {
  cumplida: { texto: 'Meta alcanzada', color: SEMAFORO.ok, tinta: 'var(--accent-press)', Icono: Check },
  ritmo: { texto: 'A ritmo del mes', color: SEMAFORO.ok, tinta: 'var(--muted-foreground-strong)', Icono: TrendingUp },
  atencion: { texto: 'Por mejorar', color: SEMAFORO.atencion, tinta: 'var(--warning-text)', Icono: TriangleAlert },
  prioridad: { texto: 'Brecha alta: revisar', color: SEMAFORO.critico, tinta: 'var(--destructive-text)', Icono: CircleAlert },
  sin_base: { texto: 'Sin base para evaluar', color: SEMAFORO.neutro, tinta: 'var(--muted-foreground-strong)', Icono: Minus },
} as const
export type SenalResultado = keyof typeof SENALES
function clasificarResultado(valor: number | null, objetivo: number, ritmo?: number | null): SenalResultado {
  if (valor === null || !Number.isFinite(valor) || objetivo <= 0 || !Number.isFinite(objetivo)) return 'sin_base'
  if (valor >= objetivo) return 'cumplida'
  if (ritmo === null) return 'sin_base'
  const color = colorVsObjetivo(valor, ritmo ?? objetivo)
  return color === SEMAFORO.ok ? 'ritmo' : color === SEMAFORO.atencion ? 'atencion' : 'prioridad'
}
export function SenalMetrica({ valor, objetivo, ritmo, etiqueta, abrir, barra = false }: {
  valor: number | null; objetivo: number; ritmo?: number | null | undefined; etiqueta: string;
  abrir?: (() => void) | undefined; barra?: boolean;
}) {
  const estado = clasificarResultado(valor, objetivo, ritmo)
  const { texto, color, tinta, Icono } = SENALES[estado]
  const estilo = { '--cm-senal': color, '--cm-tinta': tinta } as CSSProperties
  const cifra = valor === null ? '—' : `${numero(valor, 1)}%`
  const nombre = `${etiqueta}: ${cifra}. ${texto}`
  const contenido = <><strong>{cifra}</strong>{estado !== 'sin_base' && <Icono aria-hidden />}<span className="sr-only"> · {texto}</span></>
  return <div className="cm-metrica" style={estilo}>
    {abrir ? <button type="button" className="cm-senal" data-senal={estado} aria-label={`${nombre}. Ver detalle`} title={`${nombre}. Ver detalle`} onClick={abrir}>{contenido}</button>
      : <span className="cm-senal" data-senal={estado} title={nombre}>{contenido}</span>}
    {barra && <div className="cm-progreso" title={ritmo == null ? 'Sin referencia del mes' : `Ritmo orientativo: ${numero(ritmo, 1)}%`}>
      <span style={{ width: `${Math.max(0, Math.min(100, valor ?? 0))}%` }} />
      {ritmo != null && <i style={{ left: `${ritmo}%` }} aria-hidden />}
    </div>}
  </div>
}
export function LeyendaResultados() {
  return <div className="cm-leyenda" aria-label="Significado de los colores">{Object.entries(SENALES).map(([id, { texto, tinta, Icono }]) =>
    <span key={id}><Icono aria-hidden style={{ color: tinta }} />{id === 'prioridad' ? 'Prioridad' : id === 'sin_base' ? 'Sin base' : id === 'ritmo' ? 'A ritmo' : texto}</span>)}</div>
}
