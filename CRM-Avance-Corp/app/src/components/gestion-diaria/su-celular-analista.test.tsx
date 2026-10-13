// F4-e: el bloque «Su celular» de la ficha del analista del supervisor.
import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import { EQUIPO_DEMO } from '@/lib/demo'
import { operacionCelularDesdeDemo } from '@/lib/llamadas-celular-operacion-demo'
import type { OperacionCelularHook } from '@/data/llamadas-celular-operacion-queries'
import { SuCelularAnalista } from './su-celular-analista'

const datos = operacionCelularDesdeDemo(EQUIPO_DEMO, Date.parse('2026-10-13T15:00:00Z'), 'd-ger', 'gerencia')
const listo: OperacionCelularHook = { datos, cargando: false, enVuelo: false, error: null, recargar: async () => {} }
const analista = (id: string) => datos.analistas.find((a) => a.analista_id === id)

describe('Su celular', () => {
  it('dice la salud del celular, las cifras de hoy con su detalle y avisa de la cola', () => {
    render(<SuCelularAnalista estado={listo} analista={analista('d-v2')} />)
    const bloque = screen.getByRole('region', { name: 'Su celular' })
    expect(within(bloque).getByRole('heading', { level: 4 })).toHaveTextContent('Su celular · C2')
    expect(within(bloque).getByText('Sin latido · 9 h')).toBeInTheDocument()
    expect(within(bloque).getByText('En el celular').nextElementSibling).toHaveTextContent('6llamadas a leads detectadas hoy')
    expect(within(bloque).getByText('Con resultado').nextElementSibling).toHaveTextContent('350 % de las de hoy')
    expect(within(bloque).getByText('Resultados hoy').nextElementSibling).toHaveTextContent('43 al colgar · 1 desde la pestaña')
    expect(within(bloque).getByText('Sin resultado').nextElementSibling).toHaveTextContent('22 de hoy')
    expect(within(bloque).getByText(/Macro/)).toHaveTextContent('Macro llamadas-v3 · 3 avisos en cola')
    expect(within(bloque).getByText('Las 3 llamadas en cola no están en estas cifras hasta que el celular las envíe.')).toBeInTheDocument()
  })
  it('sin señal del celular y sin llamadas muestra «—», no 0 (D1)', () => {
    render(<SuCelularAnalista estado={listo} analista={analista('d-v3')} />)
    const bloque = screen.getByRole('region', { name: 'Su celular' })
    expect(within(bloque).getByText('Nunca habló')).toBeInTheDocument()
    expect(within(bloque).getByText('En el celular').nextElementSibling).toHaveTextContent('—Sin dato del celularsin señal del celular')
    expect(within(bloque).getByText('Con resultado').nextElementSibling).toHaveTextContent('—Sin dato del celular')
    expect(within(bloque).getByText(/Esperando el primer latido/)).toBeInTheDocument()
  })
  it('la deshecha sin corregir se dice aparte', () => {
    render(<SuCelularAnalista estado={listo} analista={analista('d-v1')} />)
    expect(screen.getByText('Deshechas sin corregir').nextElementSibling).toHaveTextContent('1esperan «Registrar el corregido»')
  })
  it('quien no está en la foto, la carga y el fallo se dicen sin inventar cifras; reintentar vuelve a consultar', () => {
    const { rerender } = render(<SuCelularAnalista estado={listo} analista={undefined} />)
    expect(screen.getByRole('status')).toHaveTextContent('No aparece en las cifras del celular de hoy.')
    rerender(<SuCelularAnalista estado={{ ...listo, datos: null, cargando: true }} analista={undefined} />)
    expect(screen.getByRole('status')).toHaveTextContent('Consultando su celular…')
    const recargar = vi.fn(async () => {})
    rerender(<SuCelularAnalista estado={{ ...listo, datos: null, error: new Error('x'), recargar }} analista={undefined} />)
    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo consultar su celular.')
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(recargar).toHaveBeenCalledTimes(1)
  })
})
