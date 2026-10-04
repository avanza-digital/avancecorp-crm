// Contrato del selector «¿Qué pasó con la llamada?» (refactor del 03/10/2026):
// controlado; contrae al elegir y «Cambiar resultado» lo reabre; el foco vuelve
// al radio elegido (buscado en SU div); los atajos 1–7 se acotan con `dentro`,
// fuera de los campos de texto, se ignoran con `deshabilitado` y, contraído,
// solo vale el del resultado elegido; ayudas (`detalles`) y `describedBy`.
import { useRef, useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { esCampoDeTexto } from '@/lib/campo-de-texto'
import type { ResultadoLlamada } from '@/lib/resultado-llamada'
import { SelectorResultado, type SelectorResultadoProps } from './selector-resultado'

type Extra = Partial<Pick<SelectorResultadoProps, 'detalles' | 'deshabilitado' | 'invalido' | 'describedBy' | 'grande'>>

interface Montaje {
  inicial?: ResultadoLlamada | null
  abiertoInicial?: boolean
  nombre?: string
  /** Envuelve el selector en un `<fieldset disabled>` (como Gestión Diaria mientras guarda). */
  congelado?: boolean
  alElegir?: (r: ResultadoLlamada, desdeAtajo: boolean) => void
  extra?: Extra
}

/** Quien lo monta guarda el estado: elegir = guardar y contraer; alternar = invertir. */
function Pantalla({ inicial = null, abiertoInicial = true, nombre = 'prueba', congelado = false, alElegir, extra = {} }: Montaje) {
  const [valor, setValor] = useState<ResultadoLlamada | null>(inicial)
  const [abierto, setAbierto] = useState(abiertoInicial)
  const raiz = useRef<HTMLDivElement>(null)
  return (
    <>
      <button type="button">Fuera</button>
      <div ref={raiz} data-testid={`raiz-${nombre}`}>
        <fieldset disabled={congelado}>
          <SelectorResultado
            valor={valor} abierto={abierto}
            onElegir={(r, desdeAtajo) => { alElegir?.(r, desdeAtajo); setValor(r); setAbierto(false) }}
            onAlternar={() => setAbierto((a) => !a)}
            dentro={(objetivo) => objetivo instanceof Node && Boolean(raiz.current?.contains(objetivo))}
            nombre={nombre} idOpciones={`opciones-${nombre}`} leyenda="Resultado" ayudaAtajos="Atajos: 1 a 7."
            {...extra}
          />
        </fieldset>
        <input aria-label={`Nota ${nombre}`} />
      </div>
    </>
  )
}

const radios = () => Array.from(document.querySelectorAll<HTMLInputElement>('input[name^="resultado-llamada"]'))
const radio = (nombre: RegExp) => screen.getByRole('radio', { name: nombre })
/** Foco dentro del selector sin elegir nada (como el foco inicial de la tarjeta). */
const enfocarPrimero = () => radios()[0]?.focus()

describe('SelectorResultado — elegir y alternar', () => {
  it('contrae al elegir, conserva el foco en el radio elegido y enlaza el botón con las opciones', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla alElegir={alElegir} />)
    expect(radios()).toHaveLength(7)
    expect(radios().every((r) => r.name === 'resultado-llamada-prueba')).toBe(true)
    // Sin resultado no hay nada que cambiar.
    expect(screen.queryByRole('button', { name: /resultado/ })).not.toBeInTheDocument()
    expect(screen.getByText('Atajos: 1 a 7.')).toBeInTheDocument()

    await user.click(radio(/no le interesa/))
    expect(alElegir).toHaveBeenCalledWith('no_interesado', false)
    expect(radios()).toHaveLength(1)
    expect(radio(/no le interesa/)).toBeChecked()
    expect(radio(/no le interesa/)).toHaveFocus()
    expect(screen.getByText('Para elegir otro, usa «Cambiar resultado».')).toBeInTheDocument()
    const boton = screen.getByRole('button', { name: 'Cambiar resultado' })
    expect(boton).toHaveAttribute('aria-expanded', 'false')
    expect(boton).toHaveAttribute('aria-controls', 'opciones-prueba')
    expect(document.getElementById('opciones-prueba')).toContainElement(radio(/no le interesa/))
  })

  it('«Cambiar resultado» reabre los siete y «Mantener resultado» contrae; en ambos el foco vuelve al elegido', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla alElegir={alElegir} />)
    await user.click(radio(/No contestó/))
    await user.click(screen.getByRole('button', { name: 'Cambiar resultado' }))
    expect(radios()).toHaveLength(7)
    expect(radio(/No contestó/)).toHaveFocus()
    expect(radio(/No contestó/)).toBeChecked()
    expect(screen.getByRole('button', { name: 'Mantener resultado' })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByText('Atajos: 1 a 7.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Mantener resultado' }))
    expect(radios()).toHaveLength(1)
    expect(radio(/No contestó/)).toHaveFocus()
    // Alternar no es elegir.
    expect(alElegir).toHaveBeenCalledTimes(1)
  })

  it('el foco tras elegir se busca en SU div: con otro selector en pantalla no salta al radio ajeno', async () => {
    const user = userEvent.setup()
    render(<><Pantalla nombre="a" /><Pantalla nombre="b" /></>)
    const b = within(screen.getByTestId('raiz-b'))
    await user.click(b.getByRole('radio', { name: /volver a llamar/ }))
    expect(b.getByRole('radio', { name: /volver a llamar/ })).toHaveFocus()
    // El otro selector sigue intacto, con sus siete opciones y nada marcado.
    const radiosA = within(screen.getByTestId('raiz-a')).getAllByRole('radio')
    expect(radiosA).toHaveLength(7)
    expect(radiosA.every((r) => !(r as HTMLInputElement).checked)).toBe(true)
  })

  it('dentro de un <fieldset disabled> radios y «Cambiar resultado» quedan inertes', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla inicial="no_contesto" abiertoInicial={false} congelado extra={{ deshabilitado: true }} alElegir={alElegir} />)
    expect(radio(/No contestó/)).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cambiar resultado' })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Cambiar resultado' }))
    expect(radios()).toHaveLength(1)
    expect(alElegir).not.toHaveBeenCalled()
  })
})

describe('SelectorResultado — atajos 1–7', () => {
  it('un atajo elige (desde atajo) y contrae; contraído, otro atajo NO cuenta y el mismo sí', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla alElegir={alElegir} />)
    enfocarPrimero()
    await user.keyboard('3')
    expect(alElegir).toHaveBeenLastCalledWith('agendo_reunion', true)
    expect(radios()).toHaveLength(1)
    expect(radio(/agendó cita/)).toBeChecked()
    expect(radio(/agendó cita/)).toHaveFocus()

    await user.keyboard('5')
    expect(alElegir).toHaveBeenCalledTimes(1)
    expect(radio(/agendó cita/)).toBeChecked()
    expect(screen.queryByRole('radio', { name: /Número errado/ })).not.toBeInTheDocument()

    await user.keyboard('3')
    expect(alElegir).toHaveBeenCalledTimes(2)
    expect(alElegir).toHaveBeenLastCalledWith('agendo_reunion', true)

    // Reabierto, cualquier atajo vuelve a valer.
    await user.click(screen.getByRole('button', { name: 'Cambiar resultado' }))
    await user.keyboard('5')
    expect(alElegir).toHaveBeenLastCalledWith('numero_errado', true)
    expect(radio(/Número errado/)).toBeChecked()
    expect(radios()).toHaveLength(1)
  })

  it('`dentro`: con el foco fuera del selector el atajo no cuenta; tampoco en un campo de texto ni con modificador', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla alElegir={alElegir} />)
    await user.click(screen.getByRole('button', { name: 'Fuera' }))
    await user.keyboard('2')
    expect(alElegir).not.toHaveBeenCalled()

    // La nota está DENTRO de la presentación, pero ahí un dígito es texto.
    const nota = screen.getByRole('textbox', { name: 'Nota prueba' })
    await user.click(nota)
    await user.keyboard('2')
    expect(alElegir).not.toHaveBeenCalled()
    expect(nota).toHaveValue('2')

    enfocarPrimero()
    await user.keyboard('{Control>}2{/Control}')
    expect(alElegir).not.toHaveBeenCalled()
    await user.keyboard('2')
    expect(alElegir).toHaveBeenCalledWith('volver_a_llamar', true)
  })

  it('`deshabilitado` ignora los atajos aunque el foco esté dentro', async () => {
    const user = userEvent.setup()
    const alElegir = vi.fn()
    render(<Pantalla alElegir={alElegir} extra={{ deshabilitado: true }} />)
    enfocarPrimero()
    await user.keyboard('2')
    expect(alElegir).not.toHaveBeenCalled()
    expect(radios()).toHaveLength(7)
    expect(radios().every((r) => !r.checked)).toBe(true)
  })
})

describe('SelectorResultado — ayudas y descripción', () => {
  // jsdom no aplica CSS: etiqueta y ayuda (dos spans de bloque) salen pegadas en el nombre.
  it('sin `detalles` pinta la ayuda de cada resultado', () => {
    render(<Pantalla />)
    expect(screen.getByText('Se propone el siguiente intento')).toBeInTheDocument()
    expect(radio(/No contestó/)).toHaveAccessibleName(/^No contestó\s*Se propone el siguiente intento$/)
  })

  it('`detalles={null}` = presentación compacta, sin ayuda bajo ninguna opción', () => {
    render(<Pantalla extra={{ detalles: null }} />)
    expect(radios()).toHaveLength(7)
    expect(screen.queryByText('Se propone el siguiente intento')).not.toBeInTheDocument()
    expect(radio(/No contestó/)).toHaveAccessibleName('No contestó')
  })

  it('un mapa de `detalles` sustituye las ayudas; la que falta queda sin ayuda', () => {
    render(<Pantalla extra={{ detalles: { no_contesto: 'Cuenta como intento' } }} />)
    expect(radio(/No contestó/)).toHaveAccessibleName(/^No contestó\s*Cuenta como intento$/)
    expect(screen.queryByText('Se propone el siguiente intento')).not.toBeInTheDocument()
    expect(radio(/volver a llamar/)).toHaveAccessibleName('Contestó · volver a llamar')
  })

  it('`describedBy` se suma a la ayuda propia del grupo y `invalido` lo marca', () => {
    render(<><p id="error-resultado">Elige el resultado de la llamada</p><Pantalla extra={{ describedBy: 'error-resultado', invalido: true }} /></>)
    const grupo = screen.getByRole('group', { name: /Resultado/ })
    expect(grupo.getAttribute('aria-describedby')?.split(' ')).toEqual(['resultado-llamada-prueba-descripcion', 'error-resultado'])
    expect(grupo).toHaveAccessibleDescription('Atajos: 1 a 7. Elige el resultado de la llamada')
    expect(grupo).toHaveAttribute('aria-invalid', 'true')
  })
})

describe('esCampoDeTexto', () => {
  const crear = (html: string): Element | null => {
    const caja = document.createElement('div')
    caja.innerHTML = html
    return caja.firstElementChild
  }

  it('textos, fechas, áreas y selects son campos; radios, casillas y botones no', () => {
    expect(esCampoDeTexto(crear('<input type="text">'))).toBe(true)
    expect(esCampoDeTexto(crear('<input type="date">'))).toBe(true)
    expect(esCampoDeTexto(crear('<textarea></textarea>'))).toBe(true)
    expect(esCampoDeTexto(crear('<select></select>'))).toBe(true)
    expect(esCampoDeTexto(crear('<input type="radio">'))).toBe(false)
    expect(esCampoDeTexto(crear('<input type="checkbox">'))).toBe(false)
    expect(esCampoDeTexto(crear('<button type="button">x</button>'))).toBe(false)
    expect(esCampoDeTexto(null)).toBe(false)
    expect(esCampoDeTexto(document)).toBe(false)
  })
})
