// Las piezas de la línea de tiempo, montadas SOLAS (sin la ficha del lead): el riel con
// sus filas extra antes y después de los ítems, la presentación propia de cada ficha,
// la racha de etapas que se despliega y el esqueleto mientras el riel está ocupado.
// La ficha del lead (que las usa con sus valores de siempre) la cubre timeline-historial.
import { describe, expect, it } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Ban } from 'lucide-react'
import type { Actividad } from '@/lib/tipos'
import type { ItemTimeline } from '@/lib/timeline-lead'
import { EsqueletoLinea, FilaActividad, GrupoEtapa, LineaDeTiempo } from './linea-de-tiempo'

// Viernes 2 de octubre de 2026, 12:00 en Lima (17:00 UTC).
const AHORA = Date.parse('2026-10-02T17:00:00Z')

function act(sobre: Partial<Actividad>): Actividad {
  return { id: 'a', lead_id: 'l', tipo: 'nota', detalle: null, autor_nombre: 'ANA PÉREZ', creado_en: '2026-10-02T15:00:00Z', ...sobre }
}

const suelta = (a: Actividad): ItemTimeline => ({ clase: 'act', act: a })

describe('LineaDeTiempo — el riel', () => {
  it('pinta el <ol> con el riel y, en orden: lo de `antes`, los ítems y los `children`', () => {
    render(
      <LineaDeTiempo
        items={[suelta(act({ id: '1', tipo: 'llamada_realizada' })), suelta(act({ id: '2', tipo: 'whatsapp_enviado' }))]}
        ahora={AHORA}
        aria-label="Historial del lead"
        antes={<li>Fila de antes</li>}
      >
        <li>Lead creado</li>
      </LineaDeTiempo>,
    )

    const riel = screen.getByRole('list', { name: 'Historial del lead' })
    expect(riel.tagName).toBe('OL')
    expect(riel).toHaveClass('relative', 'space-y-4', 'before:absolute', 'before:inset-y-2', 'before:left-[13px]', 'before:w-px', 'before:bg-border')
    expect(riel).not.toHaveAttribute('aria-busy')
    const filas = within(riel).getAllByRole('listitem').map((li) => li.textContent)
    expect(filas).toEqual([
      'Fila de antes',
      expect.stringContaining('Llamada realizada'),
      expect.stringContaining('WhatsApp enviado'),
      'Lead creado',
    ])
  })

  it('sin `presentar`, cada actividad lleva el título, el icono y el «hace X» de siempre', () => {
    const { container } = render(<LineaDeTiempo items={[suelta(act({ tipo: 'nota', detalle: 'Llamar el lunes' }))]} ahora={AHORA} />)

    expect(screen.getByText('Nota')).toBeInTheDocument()
    expect(screen.getByText('ANA PÉREZ · hace 2 h')).toBeInTheDocument()
    expect(container.querySelector('.lucide-sticky-note')).not.toBeNull()
  })

  it('con `presentar`, la ficha decide título, icono y tiempo de cada actividad; el detalle es el mismo', () => {
    const { container } = render(
      <LineaDeTiempo
        items={[suelta(act({ id: 'nc', metadata: { evento: 'no_contactar', accion: 'marcar' }, detalle: 'Pidió que no lo llamen' }))]}
        ahora={AHORA}
        presentar={(a) => ({ titulo: a.metadata?.evento === 'no_contactar' ? 'Marcado «No contactar»' : undefined, Icono: Ban, cuando: 'Hoy, 10:00' })}
      />,
    )

    expect(screen.getByText('Marcado «No contactar»')).toBeInTheDocument()
    expect(screen.queryByText('Nota')).not.toBeInTheDocument()
    expect(screen.getByText('Pidió que no lo llamen')).toBeInTheDocument()
    expect(screen.getByText('ANA PÉREZ · Hoy, 10:00')).toBeInTheDocument()
    expect(container.querySelector('.lucide-ban')).not.toBeNull()
    expect(container.querySelector('.lucide-sticky-note')).toBeNull()
  })

  it('una racha de etapas va como grupo plegado y `presentar` alcanza a sus filas al desplegarla', async () => {
    const user = userEvent.setup()
    const etapas = [act({ id: 'e1', tipo: 'cambio_etapa' }), act({ id: 'e2', tipo: 'cambio_etapa' })]
    render(
      <LineaDeTiempo
        items={[{ clase: 'grupo_etapa', id: 'grp-e1', items: etapas }]}
        ahora={AHORA}
        presentar={(a) => ({ titulo: `Etapa ${a.id}` })}
      />,
    )

    expect(screen.getByText('2 cambios de etapa')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Ver los 2 cambios de etapa' }))
    expect(screen.getByText('Etapa e1')).toBeInTheDocument()
    expect(screen.getByText('Etapa e2')).toBeInTheDocument()
  })
})

describe('FilaActividad', () => {
  it('respeta los saltos de línea del detalle (pre-line) y no desborda (break-words)', () => {
    render(
      <ol>
        <FilaActividad a={act({ detalle: 'Primera línea\nSegunda línea' })} ahora={AHORA} />
      </ol>,
    )

    const detalle = screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === 'Primera línea\nSegunda línea')
    expect(detalle).toHaveClass('whitespace-pre-line', 'break-words')
  })

  it('una conversión resalta su hito en el color primario', () => {
    const { container } = render(
      <ol>
        <FilaActividad a={act({ tipo: 'conversion' })} ahora={AHORA} />
      </ol>,
    )

    expect(container.querySelector('.lucide-badge-check')?.parentElement).toHaveClass('border-primary/30', 'text-primary')
  })
})

describe('GrupoEtapa — desplegable', () => {
  const etapas = [
    act({ id: 'e1', tipo: 'cambio_etapa', detalle: 'Contactado → Reunión agendada', creado_en: '2026-10-02T16:00:00Z' }),
    act({ id: 'e2', tipo: 'cambio_etapa', detalle: 'Nuevo → Contactado' }),
    act({ id: 'e3', tipo: 'cambio_etapa', detalle: 'Contactado → Nuevo' }),
  ]

  it('plegado resume la racha con la más reciente; desplegado muestra cada cambio y vuelve a agruparse', async () => {
    const user = userEvent.setup()
    render(
      <ol>
        <GrupoEtapa items={etapas} ahora={AHORA} />
      </ol>,
    )

    expect(screen.getByText('3 cambios de etapa')).toBeInTheDocument()
    expect(screen.getByText('Último: Contactado → Cita agendada')).toBeInTheDocument()
    expect(screen.getByText('ANA PÉREZ · hace 1 h · toca para ver todos')).toBeInTheDocument()
    expect(screen.getAllByRole('listitem')).toHaveLength(1)

    await user.click(screen.getByRole('button', { name: 'Ver los 3 cambios de etapa' }))
    expect(screen.getAllByText('Cambio de etapa')).toHaveLength(3)
    expect(screen.getAllByRole('listitem')).toHaveLength(4)

    await user.click(screen.getByRole('button', { name: 'Agrupar 3 cambios de etapa' }))
    expect(screen.getByText('3 cambios de etapa')).toBeInTheDocument()
    expect(screen.queryByText('Cambio de etapa')).not.toBeInTheDocument()
  })

  it('sin ítems no pinta nada', () => {
    const { container } = render(
      <ol>
        <GrupoEtapa items={[]} ahora={AHORA} />
      </ol>,
    )
    expect(container.querySelector('li')).toBeNull()
  })
})

describe('EsqueletoLinea', () => {
  it('ocupa el riel (aria-busy) con filas ocultas a los lectores de pantalla', () => {
    render(<LineaDeTiempo items={[]} ahora={AHORA} aria-label="Historial" ariaBusy antes={<EsqueletoLinea />} />)

    const riel = screen.getByRole('list', { name: 'Historial', hidden: true })
    expect(riel).toHaveAttribute('aria-busy', 'true')
    const filas = riel.querySelectorAll('li')
    expect(filas).toHaveLength(2)
    for (const li of filas) expect(li).toHaveAttribute('aria-hidden', 'true')
    expect(screen.queryAllByRole('listitem')).toHaveLength(0)
  })

  it('acepta otro número de filas; con el riel libre, aria-busy="false"', () => {
    render(<LineaDeTiempo items={[]} ahora={AHORA} aria-label="Historial" ariaBusy={false} antes={<EsqueletoLinea filas={3} />} />)

    const riel = screen.getByRole('list', { name: 'Historial', hidden: true })
    expect(riel).toHaveAttribute('aria-busy', 'false')
    expect(riel.querySelectorAll('li')).toHaveLength(3)
  })
})
