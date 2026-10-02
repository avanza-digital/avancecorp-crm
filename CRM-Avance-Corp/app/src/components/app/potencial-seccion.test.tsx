// Sección «Potencial» de la ficha: quién ve botones, qué dice la nota y qué
// pasa al marcar. Los hooks de datos se sustituyen: aquí se prueba lo que se
// PINTA y lo que se pide, no el transporte (eso está en potencial-queries.test).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { fechaLima } from '@/lib/agenda-derivada'
import { sumarDiasFecha, type PotencialLead } from '@/lib/potencial'

let POTENCIAL: { habilitada: boolean; item: PotencialLead | undefined } = { habilitada: false, item: undefined }
let MARCANDO = false
const marcar = vi.fn()
vi.mock('@/data/potencial-queries', () => ({
  usePotencialLead: () => POTENCIAL,
  useMarcarPotencial: () => ({ marcar, marcando: MARCANDO }),
}))

const { SeccionPotencial } = await import('./potencial-seccion')

const LEAD = { id: 'lead-1', etapa: 'contactado' } as const
const HOY = fechaLima(Date.now())

function item(sobre: Partial<PotencialLead> = {}): PotencialLead {
  return {
    lead_id: 'lead-1', nivel: null, origen: null, nivel_marcado: null, marcado_en: null,
    dias_sin_gestion: null, baja_a: null, baja_el: null, puede_marcar: true, ...sobre,
  }
}
const estrella = (sobre: Partial<PotencialLead> = {}) => item({
  nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', marcado_en: '2026-09-29T15:00:00Z',
  dias_sin_gestion: 1, baja_a: 'tibio', baja_el: sumarDiasFecha(HOY, 1), ...sobre,
})

function conMovimiento() {
  vi.spyOn(window, 'matchMedia').mockImplementation((query: string) => ({
    matches: false, media: query, onchange: null, addEventListener: () => {}, removeEventListener: () => {},
    addListener: () => {}, removeListener: () => {}, dispatchEvent: () => false,
  }))
}

beforeEach(() => { marcar.mockClear() })
afterEach(() => { POTENCIAL = { habilitada: false, item: undefined }; MARCANDO = false })

const botones = () => within(screen.getByRole('group', { name: 'Potencial del lead' })).getAllByRole('button')
const pulsadoDe = (nombre: string) => screen.getByRole('button', { name: nombre }).getAttribute('aria-pressed')

describe('SeccionPotencial', () => {
  it('ESTADO DE PRODUCCIÓN (bandera apagada): la sección no existe', () => {
    POTENCIAL = { habilitada: false, item: undefined }
    const { container, rerender } = render(<SeccionPotencial lead={LEAD} />)
    expect(container).toBeEmptyDOMElement()
    // Apagada manda aunque quede un dato viejo a mano.
    POTENCIAL = { habilitada: false, item: estrella() }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('mientras no llega la respuesta no pinta nada (no adelanta un «sin marcar» que puede ser falso)', () => {
    POTENCIAL = { habilitada: true, item: undefined }
    const { container } = render(<SeccionPotencial lead={LEAD} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('ESTADO DE PRODUCCIÓN (encendida, lead sin marca): tres botones sin pulsar y «Sin marcar»', () => {
    POTENCIAL = { habilitada: true, item: item() }
    render(<SeccionPotencial lead={LEAD} />)
    expect(screen.getByRole('region', { name: 'Potencial' })).toBeInTheDocument()
    expect(botones().map((b) => [b.textContent, b.getAttribute('aria-pressed')])).toEqual([
      ['Frío', 'false'], ['Tibio', 'false'], ['Estrella', 'false'],
    ])
    // La nota visible NO es región viva: al abrir la ficha no se anuncia nada.
    expect(screen.getByText('Sin marcar. La cambian el analista del lead y su supervisor.')).not.toHaveAttribute('aria-live')
    expect(screen.getByRole('status')).toBeEmptyDOMElement()
  })

  it('abrir la ficha de un lead YA marcado tampoco anuncia nada: la región viva nace vacía', () => {
    POTENCIAL = { habilitada: true, item: estrella() }
    render(<SeccionPotencial lead={LEAD} />)
    expect(screen.getByRole('status')).toBeEmptyDOMElement()
    expect(screen.getByRole('status')).toHaveClass('sr-only')
    expect(screen.getByText('Baja a Tibio mañana si no se gestiona.')).not.toHaveAttribute('aria-live')
  })

  it('al marcar: calla mientras guarda y, al terminar, anuncia el nivel y la nota final', () => {
    POTENCIAL = { habilitada: true, item: item() }
    const { rerender } = render(<SeccionPotencial lead={LEAD} />)
    const estado = screen.getByRole('status')
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))

    // La marca viaja: nivel optimista, sin fecha todavía. La región sigue callada.
    MARCANDO = true
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 0, baja_a: null, baja_el: null }) }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(estado).toBeEmptyDOMElement()
    expect(screen.getByText('Guardando la marca…')).not.toHaveAttribute('aria-live')

    // Terminó de guardar: se oye el nivel y lo que dijo el servidor.
    MARCANDO = false
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 0 }) }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(estado).toHaveTextContent('Estrella. Baja a Tibio mañana si no se gestiona.')
    expect(screen.getByRole('status')).toBe(estado)
  })

  it('si el servidor rechaza la marca de un lead sin marca, la región viva sigue callada (avisa el toast)', () => {
    POTENCIAL = { habilitada: true, item: item() }
    const { rerender } = render(<SeccionPotencial lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Tibio' }))
    MARCANDO = true
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    MARCANDO = false
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(screen.getByRole('status')).toBeEmptyDOMElement()
  })

  it('marcar pide la marca del nivel elegido para ese lead', () => {
    POTENCIAL = { habilitada: true, item: item() }
    render(<SeccionPotencial lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))
    expect(marcar).toHaveBeenCalledExactlyOnceWith('lead-1', 'estrella')
  })

  it('con marca: su botón queda pulsado y la nota dice cuándo baja', () => {
    POTENCIAL = { habilitada: true, item: estrella() }
    render(<SeccionPotencial lead={LEAD} />)
    expect([pulsadoDe('Frío'), pulsadoDe('Tibio'), pulsadoDe('Estrella')]).toEqual(['false', 'false', 'true'])
    expect(screen.getByText('Baja a Tibio mañana si no se gestiona.')).toBeInTheDocument()
  })

  it('una marca que bajó sola: pulsado el nivel de HOY y la nota cuenta de dónde vino', () => {
    POTENCIAL = { habilitada: true, item: estrella({ nivel: 'tibio', origen: 'caducidad', dias_sin_gestion: 6, baja_a: 'frio' }) }
    render(<SeccionPotencial lead={LEAD} />)
    expect([pulsadoDe('Tibio'), pulsadoDe('Estrella')]).toEqual(['true', 'false'])
    expect(screen.getByText('Bajó sola de Estrella a Tibio: 6 días sin gestión.')).toBeInTheDocument()
  })

  it('volver a pulsar el nivel activo también marca: reinicia el reloj', () => {
    POTENCIAL = { habilitada: true, item: estrella() }
    render(<SeccionPotencial lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))
    expect(marcar).toHaveBeenCalledExactlyOnceWith('lead-1', 'estrella')
  })

  it('quien no puede marcar (gerencia, otro equipo) ve la marca y la nota, sin botones', () => {
    POTENCIAL = { habilitada: true, item: estrella({ puede_marcar: false }) }
    render(<SeccionPotencial lead={LEAD} />)
    expect(screen.queryByRole('group', { name: 'Potencial del lead' })).not.toBeInTheDocument()
    expect(screen.queryAllByRole('button')).toHaveLength(0)
    expect(screen.getByTitle('Potencial: Estrella')).toBeInTheDocument()
    expect(screen.getByText('Baja a Tibio mañana si no se gestiona.')).toBeInTheDocument()
  })

  it('quien no puede marcar y el lead no tiene marca: solo «Sin marcar.»', () => {
    POTENCIAL = { habilitada: true, item: item({ puede_marcar: false }) }
    render(<SeccionPotencial lead={LEAD} />)
    expect(screen.queryAllByRole('button')).toHaveLength(0)
    expect(screen.getByText('Sin marcar.')).toBeInTheDocument()
  })

  it.each(['convertido', 'descartado'] as const)('lead %s: la marca queda congelada aunque el servidor aún diga que se puede', (etapa) => {
    POTENCIAL = { habilitada: true, item: estrella({ puede_marcar: true }) }
    render(<SeccionPotencial lead={{ id: 'lead-1', etapa }} />)
    expect(screen.queryAllByRole('button')).toHaveLength(0)
    expect(screen.getByTitle('Potencial: Estrella')).toBeInTheDocument()
    expect(screen.getByText('Lead cerrado: la marca ya no cambia.')).toBeInTheDocument()
  })

  it('sin marca en vuelo, los botones no dicen estar ocupados', () => {
    POTENCIAL = { habilitada: true, item: item() }
    render(<SeccionPotencial lead={LEAD} />)
    expect(screen.getByRole('group', { name: 'Potencial del lead' })).not.toHaveAttribute('aria-busy')
    for (const boton of botones()) {
      expect(boton).not.toHaveAttribute('aria-disabled')
      expect(boton).toBeEnabled()
    }
  })

  it('mientras una marca viaja al servidor: los tres botones lo dicen, el foco no se mueve y no se manda otra', () => {
    // Estado optimista: el nivel ya cambió, pero aún no se sabe cuándo bajará.
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 0, baja_a: null, baja_el: null }) }
    const { rerender } = render(<SeccionPotencial lead={LEAD} />)
    const pulsado = screen.getByRole('button', { name: 'Estrella' })
    pulsado.focus()
    MARCANDO = true
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)

    expect(screen.getByRole('group', { name: 'Potencial del lead' })).toHaveAttribute('aria-busy', 'true')
    expect(botones().map((b) => b.getAttribute('aria-disabled'))).toEqual(['true', 'true', 'true'])
    // `aria-disabled` y no `disabled`: el botón recién pulsado conserva el foco.
    for (const boton of botones()) expect(boton).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Estrella' })).toBe(pulsado)
    expect(pulsado).toHaveFocus()
    expect(pulsado).toHaveAttribute('aria-pressed', 'true')

    fireEvent.click(screen.getByRole('button', { name: 'Tibio' }))
    fireEvent.click(pulsado)
    expect(marcar).not.toHaveBeenCalled()
  })

  it('mientras la marca viaja la nota dice «Guardando la marca…» y no adelanta ninguna fecha', () => {
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 0, baja_a: null, baja_el: null }) }
    MARCANDO = true
    const { rerender } = render(<SeccionPotencial lead={LEAD} />)
    const nota = screen.getByText('Guardando la marca…')
    expect(nota).not.toHaveAttribute('aria-live')
    expect(screen.queryByText(/^Baja a /)).not.toBeInTheDocument()
    expect(screen.queryByText(/^Marcado como /)).not.toBeInTheDocument()

    // Termina la relectura: se pinta lo que dijo el servidor, en el mismo párrafo.
    MARCANDO = false
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 0, baja_a: 'tibio', baja_el: sumarDiasFecha(HOY, 1) }) }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(nota).toHaveTextContent('Baja a Tibio mañana si no se gestiona.')
    expect(botones().some((b) => b.hasAttribute('aria-disabled'))).toBe(false)
  })

  it('a qué nivel baja lo dice el servidor: una Estrella vencida puede anunciar Frío', () => {
    POTENCIAL = { habilitada: true, item: estrella({ dias_sin_gestion: 9, baja_a: 'frio', baja_el: sumarDiasFecha(HOY, 1) }) }
    render(<SeccionPotencial lead={LEAD} />)
    expect(pulsadoDe('Estrella')).toBe('true')
    expect(screen.getByText('Baja a Frío mañana si no se gestiona.')).toBeInTheDocument()
  })

  it('chispas al confirmar Estrella, y solo si antes no lo era', () => {
    conMovimiento()
    POTENCIAL = { habilitada: true, item: item() }
    const { container, rerender } = render(<SeccionPotencial lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Tibio' }))
    expect(container.querySelector('.pot-chispas')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))
    expect(container.querySelectorAll('.pot-chispa')).toHaveLength(10)
    expect(container.querySelector('.pot-chispas')).toHaveAttribute('aria-hidden', 'true')
    // Las chispas no cambian el nombre del botón.
    expect(screen.getByRole('button', { name: 'Estrella' })).toBeInTheDocument()

    // Ya es Estrella puesta a mano: reconfirmarla no vuelve a celebrar.
    POTENCIAL = { habilitada: true, item: estrella() }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    const antes = container.querySelector('.pot-chispas')
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))
    expect(container.querySelector('.pot-chispas')).toBe(antes)
  })

  it('si los botones dejan de existir con el foco dentro, el foco pasa a la sección en vez de perderse', () => {
    POTENCIAL = { habilitada: true, item: estrella() }
    const { rerender } = render(<SeccionPotencial lead={LEAD} />)
    const seccion = screen.getByRole('region', { name: 'Potencial' })
    expect(seccion).toHaveAttribute('tabindex', '-1')
    screen.getByRole('button', { name: 'Estrella' }).focus()
    expect(screen.getByRole('button', { name: 'Estrella' })).toHaveFocus()

    // La relectura dice que esta persona ya no puede marcar (p. ej. el lead cambió de dueño).
    POTENCIAL = { habilitada: true, item: estrella({ puede_marcar: false }) }
    rerender(<SeccionPotencial lead={{ ...LEAD }} />)
    expect(screen.queryByRole('group', { name: 'Potencial del lead' })).not.toBeInTheDocument()
    expect(seccion).toHaveFocus()
  })

  it('si el foco estaba en otro sitio, que desaparezcan los botones no lo mueve', () => {
    POTENCIAL = { habilitada: true, item: estrella() }
    const { rerender } = render(
      <>
        <button type="button">Otro control</button>
        <SeccionPotencial lead={LEAD} />
      </>,
    )
    // El foco pasa por un botón de potencial y SALE a otro control.
    screen.getByRole('button', { name: 'Tibio' }).focus()
    screen.getByRole('button', { name: 'Otro control' }).focus()
    POTENCIAL = { habilitada: true, item: estrella({ puede_marcar: false }) }
    rerender(
      <>
        <button type="button">Otro control</button>
        <SeccionPotencial lead={{ ...LEAD }} />
      </>,
    )
    expect(screen.getByRole('button', { name: 'Otro control' })).toHaveFocus()
  })

  it('sin movimiento no hay chispas', () => {
    // La suite corre con «reducir movimiento» activo (test/setup.ts).
    POTENCIAL = { habilitada: true, item: item() }
    const { container } = render(<SeccionPotencial lead={LEAD} />)
    fireEvent.click(screen.getByRole('button', { name: 'Estrella' }))
    expect(marcar).toHaveBeenCalledExactlyOnceWith('lead-1', 'estrella')
    expect(container.querySelector('.pot-chispas')).toBeNull()
  })
})
