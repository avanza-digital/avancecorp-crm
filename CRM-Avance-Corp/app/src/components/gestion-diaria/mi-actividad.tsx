// «Mi actividad»: el segundo nivel de «Mi día».
//
// Aquí se mudó todo lo que NO ayuda a decidir a quién llamar: el marcador
// completo, las llamadas por hora, los compromisos de mañana en adelante y los
// descartes del día. Vivían en la pantalla principal y eran la mitad de las 27
// cosas que el analista veía de golpe; ahora se abren cuando se quieren mirar
// y la cola conserva su pestaña, su página y su persona elegida.
//
// Piso tipográfico 16 px, como el primer nivel: estar en segundo plano no es
// excusa para letra chica.
import { useState, type JSX } from 'react'
import { CalendarClock, RotateCcw } from 'lucide-react'
import { PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Tabs } from '@/components/ui/tabs'
import { presentarCitas } from '@/lib/terminologia'
import {
  COLOR_NIVEL, ETIQUETA_NIVEL, barrasPorHora, cuandoLimaDe, horaLimaDe, llamadasFueraDeFranja, textoTasa,
  type Descartado, type DiaAnalista,
} from '@/lib/gestion-diaria-analista'

type Seccion = 'resumen' | 'horas' | 'seguimiento' | 'descartes'

export function MiActividad({ dia, deshaciendo, onDeshacer, onAbrirFicha }: {
  dia: DiaAnalista
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  const [seccion, setSeccion] = useState<Seccion>('resumen')
  return (
    <Tabs
      etiqueta="Secciones de mi actividad"
      tamano="grande"
      valor={seccion}
      onCambio={setSeccion}
      pestanas={[
        { valor: 'resumen', etiqueta: 'Resumen' },
        { valor: 'horas', etiqueta: 'Llamadas por hora' },
        { valor: 'seguimiento', etiqueta: 'Mi seguimiento', extra: String(dia.compromisos_total) },
        { valor: 'descartes', etiqueta: 'Descartados hoy', extra: String(dia.descartados.length) },
      ]}
    >
      {seccion === 'resumen' && <Resumen dia={dia} />}
      {seccion === 'horas' && <PorHora dia={dia} />}
      {seccion === 'seguimiento' && <Seguimiento dia={dia} onAbrirFicha={onAbrirFicha} />}
      {seccion === 'descartes' && (
        <Descartados dia={dia} deshaciendo={deshaciendo} onDeshacer={onDeshacer} onAbrirFicha={onAbrirFicha} />
      )}
    </Tabs>
  )
}

function Cifra({ etiqueta, valor, tono, extra }: {
  etiqueta: string
  valor: string
  tono?: string | undefined
  extra?: JSX.Element | undefined
}): JSX.Element {
  return (
    <div className="space-y-1 rounded-xl border border-border p-5">
      <p className="text-base text-[var(--muted-foreground-strong)]">{etiqueta}</p>
      <p className="flex flex-wrap items-center gap-3 text-lg font-medium leading-7" style={tono ? { color: tono } : undefined}>
        {valor}{extra}
      </p>
    </div>
  )
}

function Resumen({ dia }: { dia: DiaAnalista }): JSX.Element {
  const m = dia.marcador
  const tonoTasa = m.nivel === null ? undefined : COLOR_NIVEL[m.nivel]
  return (
    <div className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Cifra etiqueta="Llamadas" valor={String(m.llamadas)} />
        <Cifra etiqueta="Contestadas" valor={String(m.contestadas)} />
        <Cifra etiqueta="Llamadas útiles" valor={String(m.utiles)} />
        <Cifra
          etiqueta="Tasa de contacto"
          valor={textoTasa(m)}
          tono={tonoTasa}
          {...(m.nivel !== null
            ? { extra: <Badge color={COLOR_NIVEL[m.nivel]} dot className="text-base font-normal leading-6">{ETIQUETA_NIVEL[m.nivel]}</Badge> }
            : {})}
        />
        <Cifra etiqueta="Leads tocados" valor={String(m.leads_tocados)} />
        <Cifra etiqueta={presentarCitas('Citas agendadas')} valor={String(m.citas_agendadas)} />
      </div>
      <p className="text-base text-[var(--muted-foreground-strong)]">
        Llamadas = marcadas + no contestadas. No incluye WhatsApp ni {presentarCitas('citas')}. Un número errado no entra en la tasa.
        {m.nivel === null && ` El nivel se juzga desde ${dia.umbrales.minimo_llamadas_utiles} llamadas útiles.`}
        {m.primera_llamada_en !== null && ` Primera ${horaLimaDe(m.primera_llamada_en)}, última ${horaLimaDe(m.ultima_llamada_en)} (Lima).`}
      </p>
    </div>
  )
}

function PorHora({ dia }: { dia: DiaAnalista }): JSX.Element {
  const m = dia.marcador
  if (m.llamadas === 0) {
    return <p className="text-base text-[var(--muted-foreground-strong)]">Todavía no has marcado hoy: el gráfico aparece con la primera llamada.</p>
  }
  const barras = barrasPorHora(m)
  const fuera = llamadasFueraDeFranja(m)
  return (
    <div className="space-y-3">
      {/* Cada columna se NOMBRA: el gráfico no puede ser la única vía al dato. */}
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ul role="list" aria-label="Llamadas por hora, de 08 a 20 (Lima)" className="flex items-end gap-2">
        {barras.map((b) => (
          <li key={b.hora} className="flex min-w-0 flex-1 flex-col items-center gap-2">
            {/* Texto REAL, no un `aria-label` sobre un `<li>` estático: el
                soporte de aria-label en un listitem no enfocable es desigual y
                todo lo demás va `aria-hidden`. `contestadas` no se dibuja en
                ninguna barra, así que este es su único camino. */}
            <span className="sr-only">
              {b.hora}:00 — {b.llamadas} {b.llamadas === 1 ? 'llamada' : 'llamadas'}, {b.contestadas} {b.contestadas === 1 ? 'contestada' : 'contestadas'}
            </span>
            <span aria-hidden className="text-base tabular-nums text-[var(--muted-foreground-strong)]">
              {b.llamadas === 0 ? '–' : b.llamadas}
            </span>
            <span
              aria-hidden
              className={b.llamadas === 0 ? 'w-full rounded-t bg-border' : 'w-full rounded-t bg-primary'}
              style={{ height: `${Math.round((b.llamadas / b.maximo) * 120) + 2}px` }}
            />
            <span aria-hidden className="text-base tabular-nums text-[var(--muted-foreground-strong)]">{b.hora}</span>
          </li>
        ))}
      </ul>
      {fuera > 0 && <p className="text-base text-[var(--muted-foreground-strong)]">{fuera} fuera de la franja 08–20.</p>}
    </div>
  )
}

/** Enlace al lead: un botón real, a 16 px y con objetivo de 44. */
function EnlaceLead({ nombre, onAbrir }: { nombre: string; onAbrir: () => void }): JSX.Element {
  return (
    <button
      type="button"
      onClick={onAbrir}
      className="inline-flex min-h-11 items-center rounded-md text-lg font-medium leading-7 text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-card"
    >
      {nombre}
    </button>
  )
}

function Seguimiento({ dia, onAbrirFicha }: { dia: DiaAnalista; onAbrirFicha: (leadId: string) => void }): JSX.Element {
  if (dia.compromisos.length === 0) {
    return <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." tamano="grande" />
  }
  return (
    <div className="space-y-3">
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ol role="list" aria-label="Mis compromisos" className="divide-y divide-border rounded-xl border border-border">
        {dia.compromisos.map((c) => (
          <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
            <div className="min-w-0">
              <EnlaceLead nombre={c.lead_nombre} onAbrir={() => onAbrirFicha(c.lead_id)} />
              <p className="text-base text-[var(--muted-foreground-strong)]">
                {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
                {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
              </p>
            </div>
            <span className="text-base font-medium tabular-nums text-foreground">{cuandoLimaDe(c.vence_en)}</span>
          </li>
        ))}
      </ol>
      {dia.compromisos_total > dia.compromisos.length && (
        <p className="text-base text-[var(--muted-foreground-strong)]">
          Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
        </p>
      )}
    </div>
  )
}

function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha }: {
  dia: DiaAnalista
  deshaciendo: string | null
  onDeshacer: (d: Descartado) => void
  onAbrirFicha: (leadId: string) => void
}): JSX.Element {
  if (dia.descartados.length === 0) {
    return <p className="text-base text-[var(--muted-foreground-strong)]">Hoy no has descartado a nadie.</p>
  }
  return (
    <div className="space-y-3">
      <p className="text-base text-[var(--muted-foreground-strong)]">
        Están en el Centro de rescate con su motivo. Puedes deshacer el descarte durante 24 horas; el lead vuelve a tu cartera con un ciclo nuevo.
      </p>
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ol role="list" aria-label="Descartados hoy" className="divide-y divide-border rounded-xl border border-border">
        {dia.descartados.map((d) => (
          <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
            <div className="min-w-0">
              <EnlaceLead nombre={d.lead_nombre} onAbrir={() => onAbrirFicha(d.lead_id)} />
              <p className="text-base text-[var(--muted-foreground-strong)]">
                {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
                {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
              </p>
            </div>
            {d.puede_deshacer ? (
              // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
              // manda el foco al body (regla de la casa, boton-guardar.tsx).
              <Button variant="outline" className="h-12 text-base font-normal aria-disabled:opacity-50 aria-disabled:cursor-default" aria-disabled={deshaciendo !== null}
                aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
                onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
                <RotateCcw aria-hidden /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
              </Button>
            ) : (
              <span className="text-base text-[var(--muted-foreground-strong)]">Sin deshacer</span>
            )}
          </li>
        ))}
      </ol>
    </div>
  )
}
