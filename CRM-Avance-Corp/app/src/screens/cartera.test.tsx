// Tests de integración de la pantalla "Cartera" (la tabla de LEADS del ámbito).
// Fijan las dos mentiras que cantaba su chip de capital:
//  1) "S/ 0" cuando el capital del analista está íntegramente en dólares — la
//     cifra grande debe ser la moneda que de verdad tiene volumen (mismo
//     criterio ya aprobado en Pipeline). PEN y USD JAMÁS se suman.
//  2) el capital sumaba leads DESCARTADOS y CONVERTIDOS, es decir dinero que ya
//     no está en juego (y que en el caso del convertido ya vive como contrato
//     en la otra cartera, duplicado).
// Se mockean auth y store (sin red, sin providers): aquí se prueba la pantalla.
// Los asserts se acotan al CHIP (la tabla repite los mismos montos por fila).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, within } from '@testing-library/react'
import type { FiltrosCarteraLocal } from '@/lib/cartera-keyset'
import type { Lead } from '@/lib/tipos'
import type { CierreEstado } from '@/lib/cierre-estado'
import type { FiltrosCartera } from '@/data/crm-api'
import { fechaLima } from '@/lib/agenda-derivada'
import { desplazarFechaDerivaciones } from '@/lib/use-periodo-derivaciones'

let YO: { id: string; rol: string; demo: boolean } | null = null
let LEADS: Lead[] = []
let ESTADO_CIERRES: CierreEstado[] = []
const ABRIR_LEAD = vi.fn()

beforeEach(() => {
  ABRIR_LEAD.mockClear()
})

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS, vendedores: [
      { perfil_id: 'v-1', nombre_completo: 'ANA TORRES' },
      { perfil_id: 'v-2', nombre_completo: 'LUIS PEREZ' },
    ], esGlobal: YO?.rol === 'gerencia' },
    actividadesDelAmbito: [],
    // Espejo demo del estado de los cierres, leído en cada render igual que
    // LEADS: los dos mundos sirven la MISMA forma.
    cierresEstado: ESTADO_CIERRES,
  }),
  usePanelesActions: () => ({ abrirLead: ABRIR_LEAD }),
}))
// La marca «CIERRE ANULADO» sale de `crm.cierres_estado_fn`. Se sustituye por lo
// mismo que la tabla y el resumen: este archivo prueba lo que se PINTA, no el
// transporte, y montar un QueryClientProvider para eso sería ruido.
vi.mock('@/data/crm-queries', () => ({
  useCierresEstado: () => ({ data: ESTADO_CIERRES }),
}))

// F2: la TABLA la sirve `crm.cartera_pagina_fn` por cursor. Aquí se sustituye
// por el MISMO espejo puro que usa el modo demo (`lib/cartera-keyset`), que es
// justo lo que garantiza que demo y real filtren y ordenen igual. Sin este
// mock la pantalla exigiría un QueryClientProvider para probar un chip.
vi.mock('@/data/use-cartera-paginada', async () => {
  const { filtrarCarteraLocal, ordenarCarteraLocal } = await import('@/lib/cartera-keyset')
  const { resumenCarteraDesdeAmbito } = await import('@/lib/resumen-cartera')
  return {
    useCarteraPaginada: (leads: Lead[], filtros: FiltrosCartera & FiltrosCarteraLocal) => ({
      leads: ordenarCarteraLocal(filtrarCarteraLocal(leads, { ...filtros, recepcionDemo: filtros.recepcion ?? null })),
      resumen: resumenCarteraDesdeAmbito(filtrarCarteraLocal(leads, { ...filtros, recepcionDemo: filtros.recepcion ?? null }), [], Date.now(), Boolean(filtros.recepcion)),
      hayMas: false,
      cargando: false,
      cargandoMas: false,
      error: null,
      cargarMas: vi.fn(),
      recargar: vi.fn(),
    }),
  }
})

const { Cartera } = await import('./cartera')

describe('Cartera · vista previa local conectada', () => {
  function montarVistaPrevia(rol = 'vendedor', adicionales: Lead[] = []) {
    YO = { id: 'v-1', rol, demo: true }
    const hoy = fechaLima(Date.now())
    const fecha = (dias: number) => `${desplazarFechaDerivaciones(hoy, dias)}T12:00:00-05:00`
    LEADS = [
      lead({ id: 'hoy', nombre_completo: 'LEAD DE HOY', tenencia_desde: fecha(0), monto_estimado: 1000 }),
      lead({ id: 'ayer', nombre_completo: 'LEAD DE AYER', tenencia_desde: fecha(-1), etapa: 'contactado', monto_estimado: 2000, vendedor_id: 'v-2' }),
      lead({ id: 'anterior', nombre_completo: 'LEAD ANTERIOR', tenencia_desde: fecha(-20), monto_estimado: 4000 }),
      ...adicionales,
    ]
    ESTADO_CIERRES = []
    render(<Cartera />)
    return hoy
  }

  it.each(['vendedor', 'supervisor'])('%s: fechas y etapa actualizan filas, total, capital, activos y distribución', (rol) => {
    montarVistaPrevia(rol)
    expect(screen.queryByRole('region', { name: 'Leads recibidos por período' })).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('3')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'semana' } })
    expect(screen.queryByText('LEAD ANTERIOR')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('2')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 3,000')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'contactado' } })
    expect(screen.queryByText('LEAD DE HOY')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Activos')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 2,000')).toBeInTheDocument()
    const distribucion = screen.getByText('Distribución por etapa').closest('[data-slot="card"]')!
    expect(within(distribucion as HTMLElement).getByText('1 lead')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('row', { name: 'Abrir ficha de LEAD DE AYER' }))
    expect(ABRIR_LEAD).toHaveBeenCalledWith('ayer')
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(within(chipDe('Total leads')).getByText('3')).toBeInTheDocument()
    expect(screen.getByText('LEAD ANTERIOR')).toBeInTheDocument()
  })

  it('supervisor: combina la recepción con el analista elegido', () => {
    montarVistaPrevia('supervisor')
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'semana' } })
    fireEvent.change(screen.getByLabelText('Filtrar por analista'), { target: { value: 'v-2' } })
    expect(screen.getByText('LEAD DE AYER')).toBeInTheDocument()
    expect(screen.queryByText('LEAD DE HOY')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
  })

  it('supervisor: cuenta recepción del equipo, no bandeja ni analistas ajenos', () => {
    montarVistaPrevia('supervisor', [
      lead({ id: 'pendiente', nombre_completo: 'LEAD SIN REPARTIR', vendedor_id: null, monto_estimado: 100_000 }),
      lead({ id: 'ajeno', nombre_completo: 'LEAD DE OTRO EQUIPO', vendedor_id: 'v-ajeno', monto_estimado: 200_000 }),
    ])
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'semana' } })
    expect(screen.queryByText('LEAD SIN REPARTIR')).not.toBeInTheDocument()
    expect(screen.queryByText('LEAD DE OTRO EQUIPO')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('2')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 3,000')).toBeInTheDocument()
    expect(within(chipDe('Activos')).getByText('2')).toBeInTheDocument()
    expect(screen.queryByRole('option', { name: 'Sin asignar' })).not.toBeInTheDocument()
    expect(screen.getByText(/Recepción de los analistas de tu equipo/)).toBeInTheDocument()
  })

  it('al pasar de pendientes a un rango selecciona todos los analistas del equipo', () => {
    montarVistaPrevia('supervisor', [lead({ id: 'pendiente', nombre_completo: 'LEAD SIN REPARTIR', vendedor_id: null })])
    fireEvent.change(screen.getByLabelText('Filtrar por analista'), { target: { value: 'sin_asignar' } })
    expect(screen.getByText('LEAD SIN REPARTIR')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'hoy' } })
    expect(screen.getByLabelText('Filtrar por analista')).toHaveValue('todos')
    expect(screen.queryByText('LEAD SIN REPARTIR')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'todas' } })
    expect(screen.getByRole('option', { name: 'Sin asignar' })).toBeInTheDocument()
    expect(screen.getByText('LEAD SIN REPARTIR')).toBeInTheDocument()
  })

  it('rango manual: incluye ambos días y no presenta cifras anteriores si queda inválido', () => {
    const hoy = montarVistaPrevia()
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'rango' } })
    fireEvent.change(screen.getByLabelText('Fecha inicial de recepción'), { target: { value: hoy } })
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Fecha final de recepción'), { target: { value: desplazarFechaDerivaciones(hoy, -1) } })
    expect(screen.getByRole('alert')).toHaveTextContent('Completa ambas fechas')
    expect(within(chipDe('Total leads')).getByText('—')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('sin coincidencias deja todos los componentes en cero', () => {
    montarVistaPrevia()
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'hoy' } })
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'convertido' } })
    expect(screen.getByText('Sin resultados')).toBeInTheDocument()
    for (const etiqueta of ['Total leads', 'Activos', 'Convertidos']) {
      expect(within(chipDe(etiqueta)).getByText('0')).toBeInTheDocument()
    }
  })
})

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    telefono: '999888777',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 12000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    vendedor_nombre: 'ANA TORRES',
    creado_en: new Date().toISOString(),
    activo: true,
    ...over,
  }
}

function montar(leads: Lead[], estadoCierres: CierreEstado[] = []) {
  YO = { id: 'v-1', rol: 'vendedor', demo: false }
  LEADS = leads
  ESTADO_CIERRES = estadoCierres
  render(<Cartera />)
}

/** El mini-KPI completo (Card del StatStrip) a partir de su etiqueta. */
function chipDe(label: string): HTMLElement {
  const chip = screen.getByText(label).closest('[data-slot="card"]')
  if (!(chip instanceof HTMLElement)) throw new Error(`Sin chip "${label}"`)
  return chip
}

describe('Cartera · chip de capital', () => {
  it('en sesión real las etapas filtran tanto los indicadores como el listado', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    LEADS = [lead(), lead({ id: 'l-conv', nombre_completo: 'LEAD CONVERTIDO', etapa: 'convertido' })]
    ESTADO_CIERRES = []
    render(<Cartera />)
    expect(within(chipDe('Convertidos')).getByText('1')).toBeInTheDocument()
    expect(screen.getByText(/Los filtros actualizan juntos/)).toBeInTheDocument()

    fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar por etapa' }), { target: { value: 'nuevo' } })

    expect(screen.queryByText('LEAD CONVERTIDO')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Convertidos')).getByText('0')).toBeInTheDocument()
  })

  it('con la cartera en dólares la cifra principal es USD, no "S/ 0"', () => {
    montar([lead({ monto_estimado: 30000, moneda: 'USD' })])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('US$ 30,000')).toBeInTheDocument()
    expect(within(chip).getByText('USD')).toBeInTheDocument()
    expect(within(chip).queryByText('S/ 0')).not.toBeInTheDocument()
  })

  it('con las dos monedas muestra las dos y NUNCA las suma', () => {
    montar([
      lead({ monto_estimado: 12000, moneda: 'PEN' }),
      lead({ id: 'lead-2', nombre_completo: 'JUAN PEREZ', monto_estimado: 30000, moneda: 'USD' }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(chip).getByText('PEN · +US$ 30k')).toBeInTheDocument()
    // 42k = la suma prohibida (PEN+USD): no puede existir en el chip.
    expect(within(chip).queryByText(/42/)).not.toBeInTheDocument()
  })

  it('el capital EXCLUYE descartados y convertidos (solo lo que sigue en juego)', () => {
    montar([
      lead({ monto_estimado: 12000 }),
      lead({ id: 'l-desc', nombre_completo: 'LEAD DESCARTADO', etapa: 'descartado', monto_estimado: 50000 }),
      lead({ id: 'l-conv', nombre_completo: 'LEAD CONVERTIDO', etapa: 'convertido', monto_estimado: 80000 }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    // 142,000 = el total viejo (los tres sumados): ya no puede aparecer.
    expect(within(chip).queryByText('S/ 142,000')).not.toBeInTheDocument()
    // El chip dice lo que MIDE; "Capital total" prometía todo el capital.
    expect(screen.queryByText('Capital total')).not.toBeInTheDocument()
    // Los conteos siguen contando TODO el ámbito (lo acotado es el capital).
    expect(within(chipDe('Total leads')).getByText('3')).toBeInTheDocument()
    expect(within(chipDe('Activos')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Convertidos')).getByText('1')).toBeInTheDocument()
  })

  it('un lead inactivo (activo=false) tampoco suma capital', () => {
    montar([
      lead({ monto_estimado: 12000 }),
      lead({ id: 'l-off', nombre_completo: 'LEAD INACTIVO', activo: false, monto_estimado: 99000 }),
    ])

    const chip = chipDe('Capital en juego')
    expect(within(chip).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(chip).queryByText('S/ 111,000')).not.toBeInTheDocument()
  })
})

describe('Cartera · leads recibidos del analista', () => {
  it('sustituye el panel separado por un filtro integrado en sesión real', () => {
    montar([lead()])
    expect(screen.getByRole('combobox', { name: 'Filtrar por fecha de recepción' })).toHaveValue('todas')
    expect(screen.queryByRole('region', { name: 'Leads recibidos por período' })).not.toBeInTheDocument()
  })

  it('no expone el conteo propio del analista a Gerencia', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    LEADS = [lead()]
    render(<Cartera />)

    expect(screen.queryByRole('region', { name: 'Leads recibidos por período' })).not.toBeInTheDocument()
  })
})

describe('Cartera · marca de cierre anulado', () => {
  const CONVERTIDO = () => lead({
    id: 'l-conv', nombre_completo: 'PEDRO CONVERTIDO', etapa: 'convertido',
  })

  /** La fila del lead: los asertos van AHÍ y no en la pantalla entera, que
   *  repite «Convertido» en el filtro de etapas y en los mini-KPI. */
  const filaDe = (nombre: string): HTMLElement => {
    const fila = screen.getByText(nombre).closest('tr')
    if (!(fila instanceof HTMLElement)) throw new Error(`Sin fila "${nombre}"`)
    return fila
  }

  it('un convertido con el cierre anulado lo lleva a la vista', () => {
    montar([CONVERTIDO()], [{
      lead_id: 'l-conv', canal: 'avance',
      anulado_en: '2026-08-14T15:00:00.000Z', motivo: 'Mala práctica',
    }])

    const fila = filaDe('PEDRO CONVERTIDO')
    // «CIERRE ANULADO», no «ANULADO»: aquí lo que se lista son LEADS, y el lead
    // no está anulado — sigue convertido y el cliente sigue siendo cliente. Las
    // dos marcas conviven a propósito.
    expect(within(fila).getByText('CIERRE ANULADO')).toBeInTheDocument()
    expect(within(fila).getByText('Convertido')).toBeInTheDocument()
  })

  // ⚠️ GATE DE REALIDAD. Al 2026-08-14 producción no tiene NI UNA anulación, así
  // que este es el estado en el que la pantalla se ve de verdad hoy. Si el chip
  // apareciera por defecto, todas las carteras del país dirían que sus cierres
  // están anulados — y el caso de arriba, con el fixture lleno, pasaría igual.
  it('sin ninguna anulación, la cartera se ve exactamente como antes', () => {
    montar([CONVERTIDO()])

    const fila = filaDe('PEDRO CONVERTIDO')
    expect(within(fila).getByText('Convertido')).toBeInTheDocument()
    expect(within(fila).queryByText('CIERRE ANULADO')).not.toBeInTheDocument()
  })

  it('un cierre en cooperativa SIN anular tampoco se marca', () => {
    montar([CONVERTIDO()], [{
      lead_id: 'l-conv', canal: 'cooperativa', anulado_en: null, motivo: null,
    }])

    expect(within(filaDe('PEDRO CONVERTIDO')).queryByText('CIERRE ANULADO'))
      .not.toBeInTheDocument()
  })
})
