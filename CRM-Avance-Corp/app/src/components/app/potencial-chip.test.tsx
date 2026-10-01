// Chip del potencial y lo que una fila o tarjeta necesita para pintarlo.
import { afterEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import type { PotencialLead } from '@/lib/potencial'

let POTENCIAL: { habilitada: boolean; item: PotencialLead | undefined } = { habilitada: false, item: undefined }
vi.mock('@/data/potencial-queries', () => ({ usePotencialLead: () => POTENCIAL }))

const { ChipPotencial, ChipPotencialDeLead } = await import('./potencial-chip')
const { idsDescripcion, potencialCarta, potencialFila, seguirCursorPotencial } = await import('./potencial-efectos')

function marca(sobre: Partial<PotencialLead> = {}): PotencialLead {
  return {
    lead_id: 'lead-1', nivel: 'estrella', origen: 'manual', nivel_marcado: 'estrella', marcado_en: '2026-09-29T15:00:00Z',
    dias_sin_gestion: 1, baja_a: 'tibio', baja_el: '2026-10-06', puede_marcar: true, ...sobre,
  }
}

/** jsdom no trae `matchMedia` real: aquí la persona SÍ acepta movimiento. */
function conMovimiento() {
  vi.spyOn(window, 'matchMedia').mockImplementation((query: string) => ({
    matches: false, media: query, onchange: null, addEventListener: () => {}, removeEventListener: () => {},
    addListener: () => {}, removeListener: () => {}, dispatchEvent: () => false,
  }))
}

afterEach(() => { POTENCIAL = { habilitada: false, item: undefined } })

describe('ChipPotencial', () => {
  it.each([
    ['frio', 'Frío'], ['tibio', 'Tibio'], ['estrella', 'Estrella'],
  ] as const)('%s: ícono y texto, con el nombre completo para quien no ve el color', (nivel, etiqueta) => {
    render(<ChipPotencial marca={marca({ nivel })} />)
    const chip = screen.getByTitle(`Potencial: ${etiqueta}`)
    expect(chip).toHaveTextContent(`Potencial: ${etiqueta}`)
    expect(chip).toHaveClass('pot-chip', `pot-chip--${nivel}`)
    // El ícono es decorativo: el texto es el que informa.
    expect(chip.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')
  })

  it('sin marca o sin dato no pinta nada', () => {
    const { container, rerender } = render(<ChipPotencial marca={marca({ nivel: null })} />)
    expect(container).toBeEmptyDOMElement()
    rerender(<ChipPotencial marca={undefined} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('acepta un `id` para que una fila lo use como descripción; sin él no pinta el atributo', () => {
    const { rerender } = render(<ChipPotencial id="potencial-lead-1" marca={marca()} />)
    expect(screen.getByTitle('Potencial: Estrella')).toHaveAttribute('id', 'potencial-lead-1')
    rerender(<ChipPotencial marca={marca()} />)
    expect(screen.getByTitle('Potencial: Estrella')).not.toHaveAttribute('id')
  })

  it('en el Pipeline va a 10 px', () => {
    render(<ChipPotencial marca={marca({ nivel: 'tibio' })} pequeno />)
    expect(screen.getByTitle('Potencial: Tibio')).toHaveClass('pot-chip--pequeno')
  })

  it('el chip de la ficha depende de la bandera', () => {
    POTENCIAL = { habilitada: false, item: marca() }
    const { container, rerender } = render(<ChipPotencialDeLead leadId="lead-1" />)
    expect(container).toBeEmptyDOMElement()
    POTENCIAL = { habilitada: true, item: marca() }
    rerender(<ChipPotencialDeLead leadId="lead-1" />)
    expect(screen.getByTitle('Potencial: Estrella')).toBeInTheDocument()
  })
})

describe('ids para aria-describedby', () => {
  it('une los que aplican y no pinta el atributo vacío', () => {
    expect(idsDescripcion('potencial-1', 'procedencia-1')).toBe('potencial-1 procedencia-1')
    expect(idsDescripcion(null, 'procedencia-1')).toBe('procedencia-1')
    expect(idsDescripcion(undefined, false, '')).toBeUndefined()
  })
})

describe('atributos de fila y de tarjeta', () => {
  it('sin marca no añaden nada', () => {
    expect(potencialFila(undefined)).toEqual({})
    expect(potencialFila(marca({ nivel: null }))).toEqual({})
    expect(potencialCarta(undefined, false)).toEqual({})
  })

  it('Frío y Tibio solo llevan la franja; Estrella además sigue al cursor', () => {
    expect(potencialFila(marca({ nivel: 'frio' }))).toEqual({ 'data-potencial': 'frio' })
    expect(potencialCarta(marca({ nivel: 'tibio' }), false)).toEqual({ 'data-potencial': 'tibio' })
    expect(potencialFila(marca())).toEqual({ 'data-potencial': 'estrella', onPointerMove: seguirCursorPotencial })
    expect(Object.keys(potencialCarta(marca(), false)).sort()).toEqual(
      ['data-potencial', 'onPointerCancel', 'onPointerDown', 'onPointerLeave', 'onPointerMove', 'onPointerUp'],
    )
  })

  it('el foco de la fila sigue al cursor con variables CSS, sin re-render', () => {
    render(<button type="button" {...potencialFila(marca())}>fila</button>)
    const fila = screen.getByRole('button')
    vi.spyOn(fila, 'getBoundingClientRect').mockReturnValue({ left: 100, top: 40, width: 400, height: 62 } as DOMRect)
    fireEvent.pointerMove(fila, { clientX: 250, clientY: 60 })
    expect(fila.style.getPropertyValue('--pot-mx')).toBe('150px')
    expect(fila.style.getPropertyValue('--pot-my')).toBe('20px')
  })

  it('la tarjeta Estrella se inclina hacia el cursor y se endereza al salir', () => {
    conMovimiento()
    render(<div data-testid="carta" {...potencialCarta(marca(), false)} />)
    const carta = screen.getByTestId('carta')
    vi.spyOn(carta, 'getBoundingClientRect').mockReturnValue({ left: 0, top: 0, width: 200, height: 100 } as DOMRect)
    // Esquina superior izquierda: se inclina hacia arriba y a la izquierda.
    fireEvent.pointerMove(carta, { clientX: 0, clientY: 0 })
    expect(carta.style.getPropertyValue('--pot-rx')).toBe('6.00deg')
    expect(carta.style.getPropertyValue('--pot-ry')).toBe('-7.00deg')
    expect(carta.style.getPropertyValue('--pot-alza')).toBe('-3px')
    expect(carta.style.getPropertyValue('--pot-luz')).toBe('1')
    fireEvent.pointerLeave(carta)
    expect(carta.style.getPropertyValue('--pot-rx')).toBe('')
    expect(carta.style.getPropertyValue('--pot-luz')).toBe('')
  })

  it('al pulsar se endereza y espera: de ahí puede nacer un arrastre', () => {
    conMovimiento()
    render(<div data-testid="carta" {...potencialCarta(marca(), false)} />)
    const carta = screen.getByTestId('carta')
    vi.spyOn(carta, 'getBoundingClientRect').mockReturnValue({ left: 0, top: 0, width: 200, height: 100 } as DOMRect)
    fireEvent.pointerMove(carta, { clientX: 200, clientY: 100 })
    expect(carta.style.getPropertyValue('--pot-ry')).toBe('7.00deg')
    fireEvent.pointerDown(carta)
    expect(carta.style.getPropertyValue('--pot-ry')).toBe('')
    // Con el botón pulsado, mover no la inclina.
    fireEvent.pointerMove(carta, { clientX: 0, clientY: 0 })
    expect(carta.style.getPropertyValue('--pot-ry')).toBe('')
    // El navegador cancela el puntero al empezar el arrastre: después vuelve a inclinarse.
    fireEvent.pointerCancel(carta)
    fireEvent.pointerMove(carta, { clientX: 0, clientY: 0 })
    expect(carta.style.getPropertyValue('--pot-ry')).toBe('-7.00deg')
  })

  it('mientras se arrastra (o con el menú abierto) la tarjeta no escucha al puntero', () => {
    expect(potencialCarta(marca(), true)).toEqual({ 'data-potencial': 'estrella', 'data-pot-quieta': '' })
  })

  it('sin movimiento la tarjeta no se inclina (sigue siendo dorada por su atributo)', () => {
    // La suite corre con «reducir movimiento» activo (test/setup.ts).
    render(<div data-testid="carta" {...potencialCarta(marca(), false)} />)
    const carta = screen.getByTestId('carta')
    vi.spyOn(carta, 'getBoundingClientRect').mockReturnValue({ left: 0, top: 0, width: 200, height: 100 } as DOMRect)
    fireEvent.pointerMove(carta, { clientX: 0, clientY: 0 })
    expect(carta.style.getPropertyValue('--pot-rx')).toBe('')
    expect(carta).toHaveAttribute('data-potencial', 'estrella')
  })
})
