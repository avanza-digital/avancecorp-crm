// La fila «Por potencial» de Leads: cuatro pastillas cuyo número ES el filtro.
// Aquí no se cuenta nada (los conteos vienen del servidor): se prueba qué se
// pinta en cada estado y qué se le pide a la pantalla al pulsar.
import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { ConteosPotencial, FiltroPotencial } from '@/lib/potencial'
import { FiltroPotencialCartera } from './potencial-filtro'

const CONTEOS: ConteosPotencial = { filtro: null, estrella: 12, tibio: 31, frio: 9, sin_marca: 234 }

function montar(over: Partial<Parameters<typeof FiltroPotencialCartera>[0]> = {}) {
  const onCambio = vi.fn<(siguiente: FiltroPotencial | null) => void>()
  render(<FiltroPotencialCartera conteos={CONTEOS} valor={null} sinCifras={false} ocupado={false} onCambio={onCambio} {...over} />)
  const grupo = screen.getByRole('group', { name: 'Distribución por potencial' })
  return { onCambio, grupo, pastilla: (nombre: RegExp) => within(grupo).getByRole('button', { name: nombre }) }
}

describe('FiltroPotencialCartera', () => {
  it('cuatro pastillas con su número, en el orden Frío · Tibio · Estrella · Sin marcar', () => {
    const { grupo } = montar()
    expect(within(grupo).getAllByRole('button').map((b) => b.textContent)).toEqual(['Frío 9', 'Tibio 31', 'Estrella 12', 'Sin marcar 234'])
    for (const boton of within(grupo).getAllByRole('button')) {
      expect(boton).toHaveAttribute('aria-pressed', 'false')
      expect(boton).not.toHaveAttribute('aria-disabled')
    }
    expect(grupo).not.toHaveAttribute('aria-busy')
  })

  it('pulsar una pastilla pide ese nivel; pulsar la elegida lo quita', () => {
    const { onCambio, pastilla } = montar({ valor: 'tibio' })
    expect(pastilla(/^Tibio 31$/)).toHaveAttribute('aria-pressed', 'true')
    fireEvent.click(pastilla(/^Estrella 12$/))
    expect(onCambio).toHaveBeenLastCalledWith('estrella')
    fireEvent.click(pastilla(/^Sin marcar 234$/))
    expect(onCambio).toHaveBeenLastCalledWith('sin_marca')
    fireEvent.click(pastilla(/^Tibio 31$/))
    expect(onCambio).toHaveBeenLastCalledWith(null)
  })

  it('cada pastilla lleva la clase de su nivel: de ahí sale el color al elegirla', () => {
    const { grupo } = montar({ valor: 'estrella' })
    expect(within(grupo).getAllByRole('button').map((b) => [...b.classList].filter((c) => c.startsWith('pot-filtro--'))[0]))
      .toEqual(['pot-filtro--frio', 'pot-filtro--tibio', 'pot-filtro--estrella', 'pot-filtro--sin_marca'])
  })

  it('una cifra en cero no se abre; si es la elegida, se puede soltar', () => {
    const conteos = { ...CONTEOS, frio: 0, estrella: 0 }
    const { onCambio, pastilla } = montar({ conteos, valor: 'estrella' })
    expect(pastilla(/^Frío 0$/)).toHaveAttribute('aria-disabled', 'true')
    // Atenuada con su propia clase (gris legible, sin reaccionar al mouse), no con opacidad.
    expect(pastilla(/^Frío 0$/)).toHaveClass('pot-filtro--vacia')
    expect(pastilla(/^Frío 0$/).className).not.toMatch(/opacity/)
    expect(pastilla(/^Estrella 0$/)).not.toHaveClass('pot-filtro--vacia')
    fireEvent.click(pastilla(/^Frío 0$/))
    expect(onCambio).not.toHaveBeenCalled()
    expect(pastilla(/^Estrella 0$/)).not.toHaveAttribute('aria-disabled')
    fireEvent.click(pastilla(/^Estrella 0$/))
    expect(onCambio).toHaveBeenLastCalledWith(null)
  })

  it('con la consulta en vuelo las pastillas se quedan, sin cifra, y no se pulsan', () => {
    const { onCambio, grupo, pastilla } = montar({ valor: 'tibio', sinCifras: true, ocupado: true })
    expect(grupo).toHaveAttribute('aria-busy', 'true')
    // El número viejo no se enseña: «—», que el lector de pantalla dice como «cargando».
    expect(pastilla(/^Tibio cargando$/)).toHaveAttribute('aria-pressed', 'true')
    for (const boton of within(grupo).getAllByRole('button')) expect(boton).toHaveAttribute('aria-disabled', 'true')
    fireEvent.click(pastilla(/^Tibio cargando$/))
    fireEvent.click(pastilla(/^Frío cargando$/))
    expect(onCambio).not.toHaveBeenCalled()
  })

  it('si la consulta falló, sin cifras pero se puede soltar o cambiar de nivel', () => {
    const { onCambio, pastilla } = montar({ valor: 'tibio', sinCifras: true, ocupado: false })
    expect(pastilla(/^Tibio sin dato$/)).not.toHaveAttribute('aria-disabled')
    fireEvent.click(pastilla(/^Frío sin dato$/))
    expect(onCambio).toHaveBeenLastCalledWith('frio')
    fireEvent.click(pastilla(/^Tibio sin dato$/))
    expect(onCambio).toHaveBeenLastCalledWith(null)
  })

  it('si la fila se retira con el foco dentro, avisa para que el foco no caiga al body', () => {
    const alRetirarConFoco = vi.fn()
    const { rerender, unmount } = render(
      <FiltroPotencialCartera conteos={CONTEOS} valor="tibio" sinCifras={false} ocupado={false} onCambio={vi.fn()} alRetirarConFoco={alRetirarConFoco} />,
    )
    screen.getByRole('button', { name: /^Tibio 31$/ }).focus()
    // Volver a pintarse (otros conteos, otra elección) NO es retirarse.
    rerender(<FiltroPotencialCartera conteos={{ ...CONTEOS, tibio: 30 }} valor={null} sinCifras={false} ocupado={false} onCambio={vi.fn()} alRetirarConFoco={alRetirarConFoco} />)
    expect(alRetirarConFoco).not.toHaveBeenCalled()
    unmount()
    expect(alRetirarConFoco).toHaveBeenCalledTimes(1)
  })

  it('si el foco estaba en otro control, retirarse no lo mueve', () => {
    const alRetirarConFoco = vi.fn()
    const { unmount } = render(
      <>
        <button type="button">otro control</button>
        <FiltroPotencialCartera conteos={CONTEOS} valor={null} sinCifras={false} ocupado={false} onCambio={vi.fn()} alRetirarConFoco={alRetirarConFoco} />
      </>,
    )
    screen.getByRole('button', { name: 'otro control' }).focus()
    unmount()
    expect(alRetirarConFoco).not.toHaveBeenCalled()
  })
})
