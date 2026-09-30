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
/** Simula el payload ausente (cargando o RPC caída): el resumen no llega. */
let RESUMEN_CAIDO = false
/** Simula la consulta de una combinación de filtros nueva, aún en vuelo. */
let CARGANDO = false
/** Simula que la consulta de una combinación nueva FALLA (RPC caída tras el clic). */
let FALLO = false
/** Consulta de gerencia abierta desde Rendimiento (null = entrada normal). */
let CONSULTA_GERENCIA: { consulta: { gestionAnalista: { id: string; nombre: string } | null }; setConsulta: () => void } | null = null
const ABRIR_LEAD = vi.fn()

beforeEach(() => {
  ABRIR_LEAD.mockClear()
  RESUMEN_CAIDO = false
  CARGANDO = false
  FALLO = false
  CONSULTA_GERENCIA = null
})

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true,
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
vi.mock('@/components/gerencia/use-consulta-gerencia', () => ({ useConsultaGerencia: () => CONSULTA_GERENCIA }))

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
      resumen: RESUMEN_CAIDO || CARGANDO || FALLO ? undefined : resumenCarteraDesdeAmbito(filtrarCarteraLocal(leads, { ...filtros, recepcionDemo: filtros.recepcion ?? null }), [], Date.now(), Boolean(filtros.recepcion)),
      hayMas: false,
      cargando: CARGANDO,
      cargandoMas: false,
      error: FALLO ? new Error('RPC caída') : null,
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
    expect(pildorasEtapa().map((b) => b.textContent)).toEqual(['Contactado 1'])
    fireEvent.click(screen.getByRole('row', { name: 'Abrir ficha de LEAD DE AYER' }))
    expect(ABRIR_LEAD).toHaveBeenCalledWith('ayer')
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(within(chipDe('Total leads')).getByText('3')).toBeInTheDocument()
    expect(screen.getByText('LEAD ANTERIOR')).toBeInTheDocument()
  })

  it('el origen recorta filas, total, capital y distribución, y se limpia con los demás filtros', () => {
    montarVistaPrevia('vendedor', [
      lead({ id: 'web', nombre_completo: 'LEAD DE WEB', origen: 'web', etapa: 'contactado', monto_estimado: 8000 }),
    ])
    expect(within(chipDe('Total leads')).getByText('4')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por origen'), { target: { value: 'web' } })
    expect(screen.getByText('LEAD DE WEB')).toBeInTheDocument()
    expect(screen.queryByText('LEAD DE HOY')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Activos')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 8,000')).toBeInTheDocument()
    expect(pildorasEtapa().map((b) => b.textContent)).toEqual(['Contactado 1'])
    // Compone con la etapa: el lead web está contactado, así que «nuevo» vacía todo.
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'nuevo' } })
    expect(within(chipDe('Total leads')).getByText('0')).toBeInTheDocument()
    expect(screen.getByText(/otro origen/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(within(chipDe('Total leads')).getByText('4')).toBeInTheDocument()
    expect((screen.getByLabelText('Filtrar por origen') as HTMLSelectElement).value).toBe('todos')
  })

  it('la procedencia se ve en cada fila (con el autor resuelto por el equipo) y su filtro recorta la misma base', () => {
    montarVistaPrevia('supervisor', [
      lead({ id: 'manual', nombre_completo: 'LEAD A MANO', origen: 'landing', procedencia: 'manual', cargado_por: 'v-1', monto_estimado: 7000 }),
      lead({ id: 'puente', nombre_completo: 'LEAD DEL PUENTE', origen: 'landing', procedencia: 'sistema', cargado_por: null, monto_estimado: 500 }),
    ])
    const filaManual = screen.getByRole('row', { name: /LEAD A MANO/ })
    expect(within(filaManual).getByText('Manual')).toBeInTheDocument()
    expect(within(filaManual).getByText(/registrado por ANA TORRES/)).toBeInTheDocument()
    // El lector de pantalla recibe la procedencia como descripción de la fila,
    // sin cambiar el nombre accesible «Abrir ficha de …».
    expect(filaManual).toHaveAccessibleName('Abrir ficha de LEAD A MANO')
    expect(filaManual).toHaveAccessibleDescription('Registro manual, por ANA TORRES')
    const filaPuente = screen.getByRole('row', { name: /LEAD DEL PUENTE/ })
    expect(within(filaPuente).getByText('Sistema')).toBeInTheDocument()
    expect(within(filaPuente).queryByText(/registrado por/)).not.toBeInTheDocument()
    expect(filaPuente).toHaveAccessibleDescription('Del sistema')
    // Los leads sin sello (servidor anterior) no llevan chip ni descripción: nada inventado.
    const filaSinSello = screen.getByRole('row', { name: /LEAD DE HOY/ })
    expect(within(filaSinSello).queryByText(/Manual|Sistema/)).not.toBeInTheDocument()
    expect(filaSinSello).not.toHaveAttribute('aria-describedby')

    fireEvent.change(screen.getByLabelText('Filtrar por procedencia'), { target: { value: 'manual' } })
    expect(screen.getByText('LEAD A MANO')).toBeInTheDocument()
    expect(screen.queryByText('LEAD DEL PUENTE')).not.toBeInTheDocument()
    expect(screen.queryByText('LEAD DE HOY')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 7,000')).toBeInTheDocument()
    // Compone con el origen: LANDING a mano existe; LANDING del puente, con este filtro, no.
    fireEvent.change(screen.getByLabelText('Filtrar por origen'), { target: { value: 'landing' } })
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Filtrar por procedencia'), { target: { value: 'sistema' } })
    expect(screen.getByText('LEAD DEL PUENTE')).toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(within(chipDe('Total leads')).getByText('5')).toBeInTheDocument()
    expect((screen.getByLabelText('Filtrar por procedencia') as HTMLSelectElement).value).toBe('todas')
  })

  it('muestra cuántos fueron reasignados y conserva Sistema/Manual junto a la nueva marca', () => {
    montarVistaPrevia('supervisor', [
      lead({ id: 'transferido', nombre_completo: 'LEAD TRANSFERIDO', procedencia: 'manual',
        cargado_por: 'v-1', reasignado: true, vendedor_id: 'v-2' }),
      lead({ id: 'primera-entrega', nombre_completo: 'LEAD PRIMERA ENTREGA',
        procedencia: 'sistema', reasignado: false, vendedor_id: 'v-2' }),
    ])
    const boton = screen.getByRole('button', { name: 'Filtrar reasignados: 1' })
    expect(boton).toHaveAttribute('aria-pressed', 'false')
    const fila = screen.getByRole('row', { name: /LEAD TRANSFERIDO/ })
    expect(within(fila).getByText('Manual')).toBeInTheDocument()
    expect(within(fila).getByText('Reasignado')).toBeInTheDocument()
    expect(fila).toHaveAccessibleDescription('Registro manual, por ANA TORRES; Reasignado')
    expect(within(screen.getByRole('row', { name: /LEAD PRIMERA ENTREGA/ })).getByText('Sistema')).toBeInTheDocument()
    fireEvent.click(boton)
    expect(screen.queryByText('LEAD PRIMERA ENTREGA')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Filtrar reasignados: 1' })).toHaveAttribute('aria-pressed', 'true')
    fireEvent.change(screen.getByLabelText('Filtrar por procedencia'), { target: { value: 'sistema' } })
    expect(within(chipDe('Total leads')).getByText('0')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(within(chipDe('Total leads')).getByText('5')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Filtrar reasignados: 1' })).toHaveAttribute('aria-pressed', 'false')
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

/** El mini-KPI completo de la franja de cabecera a partir de su etiqueta. */
function chipDe(label: string): HTMLElement {
  const chip = screen.getByText(label).closest('[data-kpi]')
  if (!(chip instanceof HTMLElement)) throw new Error(`Sin chip "${label}"`)
  return chip
}

/** Las pastillas de etapa (la distribución que filtra). */
function pildorasEtapa(): HTMLElement[] {
  return within(screen.getByRole('group', { name: 'Distribución por etapa' })).queryAllByRole('button')
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

  it('en sesión real el origen filtra indicadores y listado a la vez', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    LEADS = [lead(), lead({ id: 'l-ref', nombre_completo: 'LEAD REFERIDO', origen: 'referido', monto_estimado: 500 })]
    ESTADO_CIERRES = []
    render(<Cartera />)
    expect(within(chipDe('Total leads')).getByText('2')).toBeInTheDocument()

    fireEvent.change(screen.getByRole('combobox', { name: 'Filtrar por origen' }), { target: { value: 'referido' } })

    expect(screen.queryByText('ROSA QUISPE')).not.toBeInTheDocument()
    expect(screen.getByText('LEAD REFERIDO')).toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('S/ 500')).toBeInTheDocument()
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

describe('Cartera · franja: las cifras filtran y el capital convertido', () => {
  const NUEVO = () => lead({ id: 'l-nuevo', nombre_completo: 'LEAD NUEVO', monto_estimado: 12000 })
  const CONV_PEN = () => lead({ id: 'l-conv-pen', nombre_completo: 'CONVERTIDO SOLES', etapa: 'convertido', monto_estimado: 80000 })
  const CONV_USD = () => lead({ id: 'l-conv-usd', nombre_completo: 'CONVERTIDO DOLARES', etapa: 'convertido', monto_estimado: 30000, moneda: 'USD' })
  const etapaElegida = () => (screen.getByLabelText('Filtrar por etapa') as HTMLSelectElement).value
  const textos = () => pildorasEtapa().map((b) => b.textContent)

  // ⚠️ GATE DE REALIDAD: sin payload (cargando o RPC caída) nada se inventa ni se abre.
  it('ESTADO DE PRODUCCIÓN (sin resumen): «—» en todo, sin pastillas y nada que abrir', () => {
    RESUMEN_CAIDO = true
    montar([NUEVO(), CONV_PEN()])
    for (const etiqueta of ['Total leads', 'Capital en juego', 'Activos', 'Convertidos']) {
      expect(within(chipDe(etiqueta)).getByText('—')).toBeInTheDocument()
    }
    expect(within(chipDe('Capital en juego')).getByText('sin dato')).toBeInTheDocument()
    expect(pildorasEtapa()).toHaveLength(0)
    expect(chipDe('Convertidos')).toHaveAttribute('aria-disabled', 'true')
    expect(screen.queryByText(/^Convertido:/)).not.toBeInTheDocument()
  })

  it('sin resumen y con la etapa «convertido» ya elegida, la tarjeta sigue permitiendo SOLTAR el filtro', () => {
    RESUMEN_CAIDO = true
    montar([NUEVO(), CONV_PEN()])
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'convertido' } })
    expect(within(chipDe('Capital convertido')).getByText('—')).toBeInTheDocument()
    // Excepción a propósito: sin cifras no se ABRE nada, pero lo ya abierto se puede cerrar.
    expect(chipDe('Convertidos')).not.toHaveAttribute('aria-disabled')
    expect(chipDe('Convertidos')).toHaveAttribute('aria-pressed', 'true')
    fireEvent.click(chipDe('Convertidos'))
    expect(etapaElegida()).toBe('todas')
    expect(chipDe('Convertidos')).toHaveAttribute('aria-disabled', 'true')
  })

  it('la ayuda de la franja llega al lector de pantalla como descripción del resumen', () => {
    montar([NUEVO()])
    expect(screen.getByRole('region', { name: 'Resumen de la cartera' }))
      .toHaveAccessibleDescription('Los filtros actualizan juntos el listado, los indicadores y la distribución por etapa.')
    // Las cifras que filtran explican qué hacen, sin cambiar lo que se lee en pantalla.
    expect(chipDe('Total leads')).toHaveAccessibleName(/^Total leads 1 .*todas las etapas/)
    expect(chipDe('Convertidos')).toHaveAccessibleName(/^Convertidos 0 .*filtra la tabla por los convertidos/)
  })

  it('la línea «Convertido: …» del capital en juego también abre su lista', () => {
    montar([NUEVO(), CONV_PEN(), CONV_USD()])
    // Espejo del selector E2E (gerencia-operativa.spec): la PRIMERA card que
    // contiene «convertidos» (sin distinguir mayúsculas) debe ser la tarjeta
    // «Convertidos», no el capital, que va antes en el DOM.
    const primera = [...document.querySelectorAll('[data-slot="card"]')].find((c) => /convertidos/i.test(c.textContent ?? ''))
    expect(primera).toBe(chipDe('Convertidos').closest('[data-slot="card"]'))
    const linea = within(chipDe('Capital en juego')).getByRole('button', { name: /^Convertido: S\/ 80,000 · US\$ 30,000/ })
    fireEvent.click(linea)
    expect(etapaElegida()).toBe('convertido')
    expect(screen.getByText('CONVERTIDO SOLES')).toBeInTheDocument()
    expect(screen.queryByText('LEAD NUEVO')).not.toBeInTheDocument()
  })

  // ⚠️ GATE DE REALIDAD: una cartera sin convertidos es lo normal para un analista nuevo.
  it('ESTADO DE PRODUCCIÓN (sin convertidos): sin línea de convertido y «Capital convertido» honesto en cero', () => {
    montar([NUEVO()])
    const enJuego = chipDe('Capital en juego')
    expect(within(enJuego).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(enJuego).queryByText(/Convertido:/)).not.toBeInTheDocument()
    expect(within(chipDe('Convertidos')).getByText('0')).toBeInTheDocument()
    expect(chipDe('Convertidos')).toHaveAttribute('aria-disabled', 'true')
    expect(textos()).toEqual(['Nuevo 1'])

    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'convertido' } })
    const convertido = chipDe('Capital convertido')
    expect(within(convertido).getByText('S/ 0')).toBeInTheDocument()
    expect(within(convertido).getByText('Monto estimado de 0 convertidos')).toBeInTheDocument()
    // La etapa activa se queda aunque dé cero, para poder soltarla.
    expect(chipDe('Convertidos')).not.toHaveAttribute('aria-disabled')
    expect(chipDe('Convertidos')).toHaveAttribute('aria-pressed', 'true')
    expect(textos()).toEqual(['Convertido 0'])
    fireEvent.click(pildorasEtapa()[0]!)
    expect(etapaElegida()).toBe('todas')
  })

  it('la tarjeta «Convertidos» filtra y el capital pasa a «Capital convertido»; otro clic lo suelta', () => {
    montar([NUEVO(), CONV_PEN()])
    expect(within(chipDe('Capital en juego')).getByText('S/ 12,000')).toBeInTheDocument()
    expect(within(chipDe('Capital en juego')).getByText('Convertido: S/ 80,000')).toBeInTheDocument()
    expect(chipDe('Total leads')).toHaveAttribute('aria-pressed', 'true')

    fireEvent.click(chipDe('Convertidos'))
    expect(etapaElegida()).toBe('convertido')
    expect(chipDe('Convertidos')).toHaveAttribute('aria-pressed', 'true')
    expect(chipDe('Total leads')).toHaveAttribute('aria-pressed', 'false')
    const capital = chipDe('Capital convertido')
    expect(within(capital).getByText('S/ 80,000')).toBeInTheDocument()
    expect(within(capital).getByText('Monto estimado de 1 convertido')).toBeInTheDocument()
    expect(screen.queryByText('Capital en juego')).not.toBeInTheDocument()
    // «Confirmado» es el capital de CONTRATOS del mes: aquí no se promete.
    expect(screen.queryByText(/Capital confirmado/)).not.toBeInTheDocument()
    expect(screen.getByText('CONVERTIDO SOLES')).toBeInTheDocument()
    expect(screen.queryByText('LEAD NUEVO')).not.toBeInTheDocument()

    fireEvent.click(chipDe('Convertidos'))
    expect(etapaElegida()).toBe('todas')
    expect(chipDe('Capital en juego')).toBeInTheDocument()
    expect(screen.getByText('LEAD NUEVO')).toBeInTheDocument()
  })

  it('las etapas filtran con un clic y se sueltan con otro; «Total leads» limpia SOLO la etapa', () => {
    montar([
      NUEVO(),
      lead({ id: 'l-ref', nombre_completo: 'LEAD REFERIDO', origen: 'referido', etapa: 'contactado', monto_estimado: 500 }),
      CONV_PEN(),
    ])
    expect(textos()).toEqual(['Nuevo 1', 'Contactado 1', 'Convertido 1'])
    const contactado = () => screen.getByRole('button', { name: 'Contactado 1' })
    fireEvent.click(contactado())
    expect(etapaElegida()).toBe('contactado')
    expect(contactado()).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByText('LEAD REFERIDO')).toBeInTheDocument()
    expect(screen.queryByText('LEAD NUEVO')).not.toBeInTheDocument()
    fireEvent.click(contactado())
    expect(etapaElegida()).toBe('todas')

    fireEvent.change(screen.getByLabelText('Filtrar por origen'), { target: { value: 'referido' } })
    expect(textos()).toEqual(['Contactado 1'])
    fireEvent.click(contactado())
    fireEvent.click(chipDe('Total leads'))
    expect(etapaElegida()).toBe('todas')
    expect((screen.getByLabelText('Filtrar por origen') as HTMLSelectElement).value).toBe('referido')

    fireEvent.click(contactado())
    fireEvent.click(screen.getByRole('button', { name: 'Limpiar filtros' }))
    expect(etapaElegida()).toBe('todas')
    expect((screen.getByLabelText('Filtrar por origen') as HTMLSelectElement).value).toBe('todos')
    expect(textos()).toEqual(['Nuevo 1', 'Contactado 1', 'Convertido 1'])
  })

  it.each([
    ['solo soles', [CONV_PEN()], 'S/ 80,000', 'Monto estimado de 1 convertido', 'Convertido: S/ 80,000'],
    ['solo dólares', [CONV_USD()], 'US$ 30,000', 'Monto estimado de 1 convertido', 'Convertido: US$ 30,000'],
    ['las dos monedas', [CONV_PEN(), CONV_USD()], 'S/ 80,000', 'Monto estimado de 2 convertidos · +US$ 30k', 'Convertido: S/ 80,000 · US$ 30,000'],
  ])('%s: cada moneda por su lado, NUNCA sumadas', (_, convertidos, valor, sub, linea) => {
    montar([NUEVO(), ...convertidos])
    expect(within(chipDe('Capital en juego')).getByText(linea)).toBeInTheDocument()
    fireEvent.click(chipDe('Convertidos'))
    const capital = chipDe('Capital convertido')
    expect(within(capital).getByText(valor)).toBeInTheDocument()
    expect(within(capital).getByText(sub)).toBeInTheDocument()
    // 110,000 = S/ 80,000 + US$ 30,000: la suma prohibida.
    expect(within(capital).queryByText(/110/)).not.toBeInTheDocument()
  })

  it('con la etapa «descartado» el capital lo dice claro: los descartados no suman', () => {
    montar([NUEVO(), lead({ id: 'l-desc', nombre_completo: 'LEAD DESCARTADO', etapa: 'descartado', monto_estimado: 5000 })])
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'descartado' } })
    const capital = chipDe('Capital en juego')
    expect(within(capital).getByText('S/ 0')).toBeInTheDocument()
    expect(within(capital).getByText('Los descartados no suman capital')).toBeInTheDocument()
  })

  it('rango de fechas inválido: la franja no enseña pastillas ni cifras', () => {
    montar([NUEVO(), CONV_PEN()])
    const hoy = fechaLima(Date.now())
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'rango' } })
    fireEvent.change(screen.getByLabelText('Fecha inicial de recepción'), { target: { value: hoy } })
    fireEvent.change(screen.getByLabelText('Fecha final de recepción'), { target: { value: desplazarFechaDerivaciones(hoy, -1) } })
    expect(screen.getByRole('alert')).toHaveTextContent('Completa ambas fechas')
    expect(pildorasEtapa()).toHaveLength(0)
    expect(within(chipDe('Capital en juego')).getByText('—')).toBeInTheDocument()
    expect(chipDe('Convertidos')).toHaveAttribute('aria-disabled', 'true')
  })

  it('supervisor con rango de fechas: el aviso de recepción sigue igual al filtrar por etapa', () => {
    YO = { id: 's-1', rol: 'supervisor', demo: true }
    const recibido = `${fechaLima(Date.now())}T12:00:00-05:00`
    LEADS = [
      lead({ id: 'a', nombre_completo: 'LEAD A', tenencia_desde: recibido }),
      lead({ id: 'b', nombre_completo: 'LEAD B', etapa: 'contactado', vendedor_id: 'v-2', tenencia_desde: recibido }),
    ]
    ESTADO_CIERRES = []
    render(<Cartera />)
    fireEvent.change(screen.getByLabelText('Filtrar por fecha de recepción'), { target: { value: 'hoy' } })
    expect(screen.getByText(/Recepción de los analistas de tu equipo/)).toBeInTheDocument()
    expect(textos()).toEqual(['Nuevo 1', 'Contactado 1'])
    fireEvent.click(screen.getByRole('button', { name: 'Contactado 1' }))
    expect(screen.getByText('LEAD B')).toBeInTheDocument()
    expect(screen.queryByText('LEAD A')).not.toBeInTheDocument()
    expect(within(chipDe('Total leads')).getByText('1')).toBeInTheDocument()
    expect(screen.getByText(/Recepción de los analistas de tu equipo/)).toBeInTheDocument()
  })

  it('gerencia desde Rendimiento: conserva la consulta del analista y las cifras filtran dentro de ella', () => {
    YO = { id: 'g-1', rol: 'gerencia', demo: false }
    CONSULTA_GERENCIA = { consulta: { gestionAnalista: { id: 'v-2', nombre: 'LUIS PEREZ' } }, setConsulta: vi.fn() }
    LEADS = [
      NUEVO(),
      lead({ id: 'l-luis', nombre_completo: 'LEAD DE LUIS', vendedor_id: 'v-2', etapa: 'convertido', monto_estimado: 9000 }),
      lead({ id: 'l-luis-2', nombre_completo: 'OTRO DE LUIS', vendedor_id: 'v-2', monto_estimado: 3000 }),
    ]
    ESTADO_CIERRES = []
    render(<Cartera />)
    const consulta = screen.getByRole('region', { name: 'Consulta desde Rendimiento' })
    expect(consulta).toHaveTextContent('Leads de LUIS PEREZ')
    expect(within(consulta).getByRole('link', { name: 'Volver a Rendimiento' })).toBeInTheDocument()
    expect(screen.getByLabelText('Filtrar por analista')).toHaveValue('v-2')
    expect(screen.queryByText('LEAD NUEVO')).not.toBeInTheDocument()

    fireEvent.click(chipDe('Convertidos'))
    expect(screen.getByText('LEAD DE LUIS')).toBeInTheDocument()
    expect(screen.queryByText('OTRO DE LUIS')).not.toBeInTheDocument()
    expect(within(chipDe('Capital convertido')).getByText('S/ 9,000')).toBeInTheDocument()
    expect(screen.getByLabelText('Filtrar por analista')).toHaveValue('v-2')
    expect(screen.queryByText(/Cambiaste el filtro del listado/)).not.toBeInTheDocument()
  })

  // Foco (revisor-a11y, 28/09): en sesión real la etapa nueva es una consulta
  // nueva y el resumen llega TARDE. El control pulsado no puede desaparecer
  // con el foco dentro.
  it('al pulsar una etapa, mientras llega la consulta, la pastilla sigue ahí con el foco y sin cifra vieja', () => {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [NUEVO(), lead({ id: 'l-cont', nombre_completo: 'LEAD CONTACTADO', etapa: 'contactado', monto_estimado: 700 })]
    ESTADO_CIERRES = []
    const { rerender } = render(<Cartera />)
    const contactado = screen.getByRole('button', { name: 'Contactado 1' })
    contactado.focus()
    CARGANDO = true
    fireEvent.click(contactado)

    const pulsada = screen.getByRole('button', { name: /^Contactado/ })
    expect(pulsada).toHaveFocus()
    expect(pulsada).toHaveAttribute('aria-pressed', 'true')
    expect(pulsada).toHaveAttribute('aria-disabled', 'true')
    expect(within(pulsada).getByText('cargando')).toBeInTheDocument()
    expect(within(pulsada).queryByText('1')).not.toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Distribución por etapa' })).toHaveAttribute('aria-busy', 'true')
    // Sin resumen «Total leads» sigue enfocable y, con una etapa elegida,
    // sirve para soltarla: lo abierto se puede cerrar.
    expect(chipDe('Total leads')).not.toBeDisabled()
    expect(chipDe('Total leads')).not.toHaveAttribute('aria-disabled')
    // Una pastilla en espera no cambia el filtro.
    fireEvent.click(screen.getByRole('button', { name: /^Nuevo/ }))
    expect(etapaElegida()).toBe('contactado')

    CARGANDO = false
    rerender(<Cartera />)
    expect(screen.getByRole('button', { name: 'Contactado 1' })).toHaveFocus()
    expect(textos()).toEqual(['Contactado 1'])
    expect(screen.getByRole('group', { name: 'Distribución por etapa' })).not.toHaveAttribute('aria-busy')
  })

  it('soltar una etapa que se queda en cero lleva el foco a «Total leads»', () => {
    montar([NUEVO()])
    fireEvent.change(screen.getByLabelText('Filtrar por etapa'), { target: { value: 'convertido' } })
    const pildora = screen.getByRole('button', { name: 'Convertido 0' })
    pildora.focus()
    fireEvent.click(pildora)
    expect(etapaElegida()).toBe('todas')
    expect(screen.queryByRole('button', { name: /^Convertido 0/ })).not.toBeInTheDocument()
    expect(chipDe('Total leads')).toHaveFocus()
    expect(chipDe('Total leads')).toHaveAttribute('aria-pressed', 'true')
  })

  it('abrir la línea «Convertido: …» deja el foco en la tarjeta «Convertidos», ya pulsada', () => {
    montar([NUEVO(), CONV_PEN()])
    const linea = within(chipDe('Capital en juego')).getByRole('button', { name: /^Convertido: S\/ 80,000/ })
    linea.focus()
    fireEvent.click(linea)
    expect(chipDe('Convertidos')).toHaveFocus()
    expect(chipDe('Convertidos')).toHaveAttribute('aria-pressed', 'true')
  })

  it('una tarjeta en cero no abre nada aunque se pulse', () => {
    montar([NUEVO()])
    fireEvent.click(chipDe('Convertidos'))
    expect(etapaElegida()).toBe('todas')
    expect(screen.getByText('LEAD NUEVO')).toBeInTheDocument()
  })

  it('si la consulta de la etapa pulsada FALLA, la pastilla sigue ahí con el foco y se puede soltar', () => {
    YO = { id: 'v-1', rol: 'vendedor', demo: false }
    LEADS = [NUEVO(), lead({ id: 'l-cont', nombre_completo: 'LEAD CONTACTADO', etapa: 'contactado', monto_estimado: 700 })]
    ESTADO_CIERRES = []
    const { rerender } = render(<Cartera />)
    const contactado = screen.getByRole('button', { name: 'Contactado 1' })
    contactado.focus()
    FALLO = true
    fireEvent.click(contactado)
    rerender(<Cartera />)

    const pulsada = screen.getByRole('button', { name: /^Contactado/ })
    expect(pulsada).toHaveFocus()
    expect(within(pulsada).getByText('sin dato')).toBeInTheDocument()
    expect(pulsada).not.toHaveAttribute('aria-disabled')
    expect(screen.getByRole('group', { name: 'Distribución por etapa' })).not.toHaveAttribute('aria-busy')
    // «Total leads» también suelta la etapa aunque no haya cifras.
    expect(chipDe('Total leads')).not.toHaveAttribute('aria-disabled')
    fireEvent.click(pulsada)
    expect(etapaElegida()).toBe('todas')
  })
})
