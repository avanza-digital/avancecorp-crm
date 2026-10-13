// Bloque «Su celular» de la ficha del analista en «Mi equipo hoy» (F4-e, prototipo aprobado el 06/10): las cifras
// de hoy de las llamadas de SU celular y la salud del aparato, debajo del resumen del día. Solo hoy: la puerta no
// mira otros días. «—» cuando el celular no dio señal y no hay llamadas (no es 0: decisión D1).
import type { JSX, ReactNode } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { SinDato } from './llamadas-celular-gerencia'
import { presentarSalud, type TonoSalud } from '@/lib/celulares'
import { detallePendientes, detalleVias, plural, porcentaje, type AnalistaCelular } from '@/lib/llamadas-celular-operacion'
import type { OperacionCelularHook } from '@/data/llamadas-celular-operacion-queries'

export const COLOR_TONO: Record<TonoSalud, string> = {
  bien: 'var(--accent)',
  aviso: 'var(--warning-text)',
  quieto: 'var(--muted-foreground-strong)',
  mal: 'var(--destructive-text)',
}
const TEXTO = 'text-[13px] text-[var(--muted-foreground-strong)]'

export function SuCelularAnalista({ estado, analista }: { estado: OperacionCelularHook; analista: AnalistaCelular | undefined }): JSX.Element {
  let cuerpo: JSX.Element
  if (estado.error) {
    cuerpo = <div role="alert" className="flex flex-wrap items-center justify-between gap-2">
      <p className={TEXTO}>No se pudo consultar su celular. Las demás cifras del día no cambian.</p>
      <Button variant="ghost" className="h-9 text-[13px] pointer-coarse:h-11" disabled={estado.enVuelo} onClick={() => { void estado.recargar() }}>Reintentar</Button>
    </div>
  } else if (estado.cargando || !estado.datos) {
    cuerpo = <p role="status" className={TEXTO}>Consultando su celular…</p>
  } else if (!analista) {
    cuerpo = <p role="status" className={TEXTO}>No aparece en las cifras del celular de hoy.</p>
  } else {
    cuerpo = <Cifras a={analista} />
  }
  return (
    <section aria-label="Su celular" className="space-y-2.5 rounded-xl border border-border bg-card px-3.5 py-3">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <h4 className="text-[15px] font-extrabold text-primary">Su celular{analista && analista.celulares.length > 0 && <> · {analista.celulares.map((c) => c.etiqueta).join(' y ')}</>}</h4>
        {analista?.celulares.map((c) => {
          const s = presentarSalud(c, null)
          return <span key={c.etiqueta} className="flex flex-wrap items-center gap-1.5">
            <Badge variant="outline" dot color={COLOR_TONO[s.principal.tono]}>{analista.celulares.length > 1 ? `${c.etiqueta}: ` : ''}{s.principal.texto}</Badge>
            {s.extras.map((x) => <Badge key={x.texto} variant="outline" color={COLOR_TONO[x.tono]}>{x.texto}</Badge>)}
          </span>
        })}
        {analista && analista.celulares.length === 0 && <Badge variant="outline" dot color={COLOR_TONO.quieto}>Sin celular asignado</Badge>}
      </div>
      {cuerpo}
    </section>
  )
}

function Cifras({ a }: { a: AnalistaCelular }): JSX.Element {
  const dato = (n: number): ReactNode => a.sin_dato ? <SinDato /> : String(n)
  const pct = porcentaje(a.llamadas_hoy.con_resultado, a.llamadas_hoy.total)
  const cola = a.celulares.reduce((n, c) => n + (c.eventos_en_cola ?? 0), 0)
  return <>
    <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-[13px] sm:grid-cols-3">
      <Dato etiqueta="En el celular" valor={dato(a.llamadas_hoy.total)} nota={a.sin_dato ? 'sin señal del celular' : 'llamadas a leads detectadas hoy'} />
      <Dato etiqueta="Con resultado" valor={dato(a.llamadas_hoy.con_resultado)} nota={pct === null ? null : `${pct} % de las de hoy`} />
      <Dato etiqueta="Resultados hoy" valor={String(a.resultados_hoy.total)} nota={detalleVias(a.resultados_hoy) || null} />
      <Dato etiqueta="Sin resultado" valor={String(a.pendientes.total)} nota={detallePendientes(a.pendientes) || null} alerta={a.pendientes.total > 0} />
      <Dato etiqueta="Por revisar" valor={String(a.por_revisar)} nota={a.por_revisar > 0 ? 'ambiguas o de la bolsa' : null} />
      {a.pendientes.deshechas_sin_corregir > 0 && <Dato etiqueta="Deshechas sin corregir" valor={String(a.pendientes.deshechas_sin_corregir)} nota="esperan «Registrar el corregido»" alerta />}
    </dl>
    {a.celulares.map((c) => {
      const s = presentarSalud(c, null)
      return <div key={c.etiqueta} className="space-y-1">
        <p className={TEXTO}>{a.celulares.length > 1 ? `${c.etiqueta} · ` : ''}Macro <span className="font-semibold text-foreground">{s.macroTexto}</span> · {s.colaTexto === '—' ? 'avisos en cola: sin dato' : plural(c.eventos_en_cola ?? 0, 'aviso en cola', 'avisos en cola')}{s.pista ? ` · ${s.pista}` : ''}</p>
      </div>
    })}
    {cola > 0 && <p className="text-xs font-semibold leading-relaxed text-[var(--warning-text)]">{cola === 1 ? 'La llamada en cola no está en estas cifras hasta que el celular la envíe.' : `Las ${cola} llamadas en cola no están en estas cifras hasta que el celular las envíe.`}</p>}
  </>
}

function Dato({ etiqueta, valor, nota, alerta = false }: { etiqueta: string; valor: ReactNode; nota: string | null; alerta?: boolean }): JSX.Element {
  return (
    <div className="min-w-0">
      <dt className="text-xs font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</dt>
      <dd className="mt-0.5 min-w-0">
        <span className={alerta && valor !== '0' ? 'text-lg font-extrabold tabular-nums text-[var(--warning-text)]' : 'text-lg font-extrabold tabular-nums text-primary'}>{valor}</span>
        {nota && <span className="block text-[11.5px] text-[var(--muted-foreground-strong)]">{nota}</span>}
      </dd>
    </div>
  )
}
