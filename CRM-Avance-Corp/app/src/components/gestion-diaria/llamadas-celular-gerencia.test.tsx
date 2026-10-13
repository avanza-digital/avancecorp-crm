// F4-e: la tercera pestaña de «Toda la operación hoy» con la operación de ejemplo.
import { describe, expect, it } from 'vitest'
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { EQUIPO_DEMO } from '@/lib/demo'
import { operacionCelularDesdeDemo } from '@/lib/llamadas-celular-operacion-demo'
import { LlamadasCelularGerencia } from './llamadas-celular-gerencia'

const AHORA = Date.parse('2026-10-13T15:00:00Z')
const montar = (estrecho = false) => render(<LlamadasCelularGerencia datos={operacionCelularDesdeDemo(EQUIPO_DEMO, AHORA, 'd-ger', 'gerencia')} estrecho={estrecho} hora="10:00" />)

describe('Llamadas del celular por equipo (gerencia)', () => {
  it('lista los equipos con sus cifras, el pie de toda la operación y los rótulos de cada reloj', () => {
    montar()
    const tabla = screen.getByRole('table', { name: 'Llamadas del celular por equipo' })
    const filas = within(tabla).getAllByRole('button', { name: /^Seleccionar / }).map((b) => b.getAttribute('aria-label'))
    expect(filas).toEqual(['Seleccionar Equipo de SUPERVISOR UNO', 'Seleccionar Equipo de SUPERVISOR DOS'])
    const uno = within(tabla).getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' }).closest('tr')!
    expect(within(uno).getByRole('rowheader')).toHaveTextContent('SUPERVISOR UNO2 analistas · 2 celulares · 2 con atención')
    const celdas = within(uno).getAllByRole('cell')
    expect(celdas.map((c) => c.textContent)).toEqual(['14', '857 %', '8de 11', '1', '43 de hoy · 1 anterior', '1', '21 sin latido'])
    // Supervisor Dos: su único analista no dio señal → «—», no «0».
    const dos = within(tabla).getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR DOS' }).closest('tr')!
    expect(within(dos).getAllByRole('cell')[0]).toHaveTextContent('—')
    expect(within(dos).getAllByText('Sin dato del celular')).toHaveLength(2)
    const pie = within(tabla).getByRole('rowheader', { name: /^Toda la operación/ }).closest('tr')!
    expect(within(pie).getAllByRole('cell').map((c) => c.textContent)).toEqual(['14', '857 %', '8de 11', '1', '43 de hoy · 1 anterior', '1', '32 sin latido'])
    expect(screen.getByText('2 de 2 equipos')).toBeInTheDocument()
    expect(screen.getByText(/No se suma a la cifra del día/)).toBeInTheDocument()
  })
  it('seleccionar un equipo abre su ficha con los cuadros, quiénes necesitan atención y los rótulos; cerrar la vacía y devuelve el foco', async () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' }))
    const ficha = screen.getByRole('region', { name: 'Detalle del Equipo de SUPERVISOR UNO' })
    expect(within(ficha).getByRole('heading', { level: 3 })).toHaveTextContent('Detalle del Equipo de SUPERVISOR UNO')
    expect(within(ficha).getByText('Equipo de 2 analistas · 2 celulares')).toBeInTheDocument()
    expect(within(ficha).getByText('En el celular').nextElementSibling).toHaveTextContent('14')
    expect(within(ficha).getByText('Con resultado').nextElementSibling).toHaveTextContent('857 % de las de hoy')
    expect(within(ficha).getByText('Resultados hoy').nextElementSibling).toHaveTextContent('118 al colgar · 2 desde la pestaña · 1 a mano')
    expect(within(ficha).getByText('Sin resultado').nextElementSibling).toHaveTextContent('43 de hoy · 1 anterior')
    const atencion = within(ficha).getByRole('list', { name: 'Analistas que necesitan atención' })
    expect(within(atencion).getAllByRole('listitem').map((li) => li.textContent)).toEqual([
      'ANALISTA DOS2 llamadas sin resultado · C2 sin latido · 9 h · C2 con 3 avisos en cola',
      'ANALISTA UNO2 llamadas sin resultado · 1 deshecha sin corregir · 1 llamada por revisar',
    ])
    expect(within(ficha).getByText(/Llamadas de hoy \(por la hora de la llamada\)/)).toBeInTheDocument()
    expect(within(ficha).getByText(/Sin resultado ahora \(hasta 30 días\)/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' })).toHaveAttribute('aria-current', 'true')
    fireEvent.click(within(ficha).getByRole('button', { name: 'Cerrar detalle' }))
    expect(screen.getByRole('region', { name: 'Llamadas del celular' })).toHaveTextContent('Elige un equipo de la tabla')
    // a11y: el foco vuelve a la fila que abrió la ficha.
    await act(async () => { await new Promise((r) => requestAnimationFrame(() => r(null))) })
    expect(screen.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR UNO' })).toHaveFocus()
  })
  it('las pastillas filtran y el buscador y el orden también; el orden se anuncia', () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: /^Con por revisar/ }))
    expect(screen.getAllByRole('button', { name: /^Seleccionar / })).toHaveLength(1)
    expect(screen.getByText('1 de 2 equipos')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^Todos/ }))
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar equipo' }), { target: { value: 'dos' } })
    expect(screen.getAllByRole('button', { name: /^Seleccionar / }).map((b) => b.getAttribute('aria-label'))).toEqual(['Seleccionar Equipo de SUPERVISOR DOS'])
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar equipo' }), { target: { value: '' } })
    fireEvent.click(screen.getByRole('button', { name: 'Ordenar equipos por equipo' }))
    expect(screen.getAllByRole('button', { name: /^Seleccionar / }).map((b) => b.getAttribute('aria-label'))).toEqual(['Seleccionar Equipo de SUPERVISOR DOS', 'Seleccionar Equipo de SUPERVISOR UNO'])
    expect(screen.getByRole('columnheader', { name: /Equipo/ })).toHaveAttribute('aria-sort', 'ascending')
    expect(screen.getByText('Equipos ordenados por equipo, ascendente.')).toBeInTheDocument()
  })
})

describe('Llamadas del celular por equipo: lector de pantalla', () => {
  it('«—» de «Con resultado» también tiene su frase, y en pantalla estrecha seleccionar se anuncia igual', () => {
    montar(true)
    const dos = screen.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR DOS' }).closest('tr')!
    expect(within(within(dos).getAllByRole('cell')[1]!).getByText('Sin dato del celular')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Seleccionar Equipo de SUPERVISOR DOS' }))
    expect(screen.getByText('Seleccionado Equipo de SUPERVISOR DOS. Detalle disponible.')).toBeInTheDocument()
    const ficha = screen.getByRole('region', { name: 'Detalle del Equipo de SUPERVISOR DOS' })
    expect(within(ficha).getByText('En el celular').nextElementSibling).toHaveTextContent('—Sin dato del celularningún celular dio señal')
    expect(within(ficha).getByText('Con resultado').nextElementSibling).toHaveTextContent('—Sin dato del celularningún celular dio señal')
  })
})
