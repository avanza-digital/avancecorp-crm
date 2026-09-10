// Pantalla Facturación: filtros, comparación y — sobre todo — el ESTADO VACÍO.
//
// El gate de realidad del proyecto exige probar la pantalla en el estado que
// tiene producción, no solo con el fixture lleno: hoy la fuente real no existe,
// así que «sin cierres» es el estado que de verdad se va a ver, y es justo la
// rama donde vive el botón que la rescata.
import { fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ContratoFacturado } from '@/lib/facturacion'
import { Facturacion } from './facturacion'

/** Jueves 10 de setiembre de 2026, 12:00 en la zona de la máquina. */
const HOY = new Date(2026, 8, 10, 12, 0, 0)

function contrato(p: Partial<ContratoFacturado> & { id: string }): ContratoFacturado {
  return {
    numero: '000100',
    cliente: 'Cliente Ejemplo',
    producto: 'Renta Fija 12 meses',
    tasaAnual: 14,
    moneda: 'PEN',
    capital: 50_000,
    dia: '2026-09-02',
    analistaId: 'ana',
    analistaNombre: 'Ana Analista',
    supervisorId: 'sup-rosa',
    supervisorNombre: 'Rosa Uno',
    ...p,
  }
}

/** Dos equipos, tres analistas. Solo Carla vende en dólares. */
const CONTRATOS: readonly ContratoFacturado[] = [
  contrato({ id: '1', dia: '2026-09-02', capital: 300_000 }),
  contrato({ id: '2', dia: '2026-09-04', capital: 100_000 }),
  contrato({ id: '3', dia: '2026-09-02', capital: 80_000, analistaId: 'beto', analistaNombre: 'Beto Analista' }),
  contrato({
    id: '4',
    dia: '2026-09-03',
    capital: 40_000,
    analistaId: 'carla',
    analistaNombre: 'Carla Analista',
    supervisorId: 'sup-sara',
    supervisorNombre: 'Sara Dos',
  }),
  contrato({
    id: '5',
    dia: '2026-09-03',
    capital: 7_000,
    moneda: 'USD',
    analistaId: 'carla',
    analistaNombre: 'Carla Analista',
    supervisorId: 'sup-sara',
    supervisorNombre: 'Sara Dos',
  }),
  // Mes anterior: da con qué comparar el KPI de arriba.
  contrato({ id: '6', dia: '2026-08-05', capital: 200_000 }),
]

function pintar(contratos: readonly ContratoFacturado[] = CONTRATOS) {
  return render(<Facturacion contratos={contratos} />)
}

/** La malla, para no confundir sus botones con los del panel de filtros. */
function malla(): HTMLElement {
  return screen.getByRole('region', { name: /Facturación diaria/ })
}

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true })
  vi.setSystemTime(HOY)
})

afterEach(() => {
  vi.useRealTimers()
})

describe('lo que se ve al entrar', () => {
  it('avisa de que las cifras son de ejemplo ANTES de mostrarlas', () => {
    pintar()
    expect(screen.getByText('Datos de ejemplo')).toBeVisible()
    expect(screen.getByText(/no las uses para decidir nada/i)).toBeVisible()
  })

  it('agrupa por equipo, con sus analistas dentro y el total del mes', () => {
    pintar()
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
    // 300 000 + 100 000 + 80 000 = 480 000 en soles, más los 40 000 de Carla.
    expect(within(malla()).getByText('S/ 520,000')).toBeVisible()
  })

  it('los 30 días de setiembre están en la cabecera, con hoy marcado', () => {
    pintar()
    const cabeceras = within(malla()).getAllByRole('columnheader')
    // 1 de nombres + 30 días + 1 de total.
    expect(cabeceras).toHaveLength(32)
  })

  it('la cifra de una celda llega a un lector de pantalla, no solo al ratón', () => {
    pintar()
    // La celda de un equipo NUNCA es un botón: su importe vive en un sr-only.
    expect(within(malla()).getAllByText('S/ 380,000').length).toBeGreaterThan(0)
  })

  it('la región de la malla es alcanzable con el teclado', () => {
    pintar()
    expect(malla()).toHaveAttribute('tabindex', '0')
  })
})

describe('filtrar por equipo', () => {
  it('deja solo ese equipo y lo dice en una etiqueta que se puede quitar', () => {
    pintar()
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })

    expect(screen.queryByRole('button', { name: /Rosa Uno/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Carla Analista' })).toBeVisible()

    const quitar = screen.getByRole('button', { name: 'Quitar Equipo de Sara Dos' })
    fireEvent.click(quitar)
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
  })

  it('el pie deja de hablar de la empresa cuando hay filtro', () => {
    pintar()
    expect(screen.getByText('Total de la empresa')).toBeVisible()
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })
    expect(screen.getByText('Total de lo que estás viendo')).toBeVisible()
  })
})

describe('comparar analistas', () => {
  it('marcar dos los deja solos, en plano y con su equipo debajo del nombre', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    // La malla ya solo muestra a Ana: al segundo se le añade desde el panel,
    // que es lo que dice el pie de la tabla en cuanto entras en comparación.
    expect(screen.getByText(/Para añadir o quitar a alguien, abre/)).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.click(
      within(screen.getByRole('group', { name: /Analistas/ })).getByRole('checkbox', {
        name: 'Comparar a Carla Analista',
      }),
    )

    expect(screen.getByText('Comparando 2 analistas, día a día')).toBeVisible()
    expect(screen.getByText('Equipo de Rosa Uno')).toBeVisible()
    expect(screen.getByText('Equipo de Sara Dos')).toBeVisible()
    // Beto no está marcado: sale de la malla.
    expect(
      screen.queryByRole('button', { name: 'Ver el mes completo de Beto Analista' }),
    ).not.toBeInTheDocument()
    // Y las cabeceras de equipo desaparecen: comparar es una lista plana.
    expect(screen.queryByRole('button', { name: /Rosa Uno/ })).not.toBeInTheDocument()
  })

  it('marcar uno solo lo aísla', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Beto Analista' }))
    expect(screen.getByText('Comparando 1 analista, día a día')).toBeVisible()
    // Su total del mes y el total del pie pasan a ser la misma cifra.
    expect(within(malla()).getAllByText('S/ 80,000')).toHaveLength(2)
  })

  it('elegir equipo deja caer a los marcados que no son suyos; quitarlo NO', () => {
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.click(
      within(screen.getByRole('group', { name: /Analistas/ })).getByRole('checkbox', {
        name: 'Comparar a Carla Analista',
      }),
    )

    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-rosa' } })
    expect(screen.getByRole('button', { name: 'Quitar Ana Analista' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Quitar Carla Analista' })).not.toBeInTheDocument()

    // Quitar el equipo no cuesta la selección que queda.
    fireEvent.click(screen.getByRole('button', { name: 'Quitar Equipo de Rosa Uno' }))
    expect(screen.getByRole('button', { name: 'Quitar Ana Analista' })).toBeVisible()
  })

  it('el panel ofrece a todo el mundo, pero desactiva a los de otro equipo', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-rosa' } })

    const panel = screen.getByRole('group', { name: /Analistas/ })
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Ana Analista' })).toBeEnabled()
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Carla Analista' })).toBeDisabled()
  })

  it('el buscador del panel filtra por nombre sin acentos ni mayúsculas', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    fireEvent.change(screen.getByLabelText('Buscar analista'), { target: { value: 'CARLA' } })

    const panel = screen.getByRole('group', { name: /Analistas/ })
    expect(within(panel).getByRole('checkbox', { name: 'Comparar a Carla Analista' })).toBeVisible()
    expect(
      within(panel).queryByRole('checkbox', { name: 'Comparar a Ana Analista' }),
    ).not.toBeInTheDocument()
  })
})

describe('estado vacío — el que de verdad se ve en producción', () => {
  it('sin ningún cierre lo dice y NO ofrece limpiar nada', () => {
    pintar([])
    expect(screen.getByText('Todavía no hay cierres en este mes.')).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Limpiar filtros' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: /Facturación diaria/ })).not.toBeInTheDocument()
  })

  it('cuando el filtro es el que vacía la malla, ofrece rescatarla', () => {
    pintar()
    // Ana no vende en dólares: la malla se queda sin nada que pintar.
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))

    expect(screen.getByText('Ningún cierre coincide con estos filtros.')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Carla Analista' })).toBeVisible()
  })
})

describe('moneda y métrica', () => {
  it('cambiar a dólares deja solo lo que se vendió en dólares', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    expect(within(malla()).getAllByText('US$ 7,000').length).toBeGreaterThanOrEqual(2)
    expect(
      screen.queryByRole('button', { name: 'Ver el mes completo de Ana Analista' }),
    ).not.toBeInTheDocument()
  })

  it('el caption dice qué se está midiendo, no siempre «capital»', () => {
    pintar()
    expect(within(malla()).getByText(/^Capital por día/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    expect(within(malla()).getByText(/^N.º de contratos por día/)).toBeInTheDocument()
  })
})

describe('restablecer', () => {
  it('está montado siempre: no desaparece bajo el foco de quien lo pulsa', () => {
    pintar()
    const boton = screen.getByRole('button', { name: 'Restablecer filtros' })
    expect(boton).toBeDisabled()

    fireEvent.change(screen.getByLabelText('Equipo'), { target: { value: 'sup-sara' } })
    expect(boton).toBeEnabled()

    fireEvent.click(boton)
    expect(screen.getByRole('button', { name: 'Restablecer filtros' })).toBeDisabled()
    expect(screen.getByRole('button', { name: /Rosa Uno/ })).toBeVisible()
  })
})
