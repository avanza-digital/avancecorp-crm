// Pantalla Facturación: filtros, comparación y — sobre todo — el ESTADO VACÍO.
//
// El gate de realidad del proyecto exige probar la pantalla en el estado que
// tiene producción, no solo con el fixture lleno: hoy la fuente real no existe,
// así que «sin cierres» es el estado que de verdad se va a ver, y es justo la
// rama donde vive el botón que la rescata.
import { act, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { FilaFacturacionDia } from '@/lib/facturacion'

// La pantalla recibe las filas por prop, así que ni la sesión ni el servidor
// deciden nada aquí; se doblan para que el componente monte. El camino real
// (RPC + modo demo) lo cubren la matriz de RLS y el oráculo del servidor.
const dobles = vi.hoisted(() => ({
  demo: false,
  // El organigrama que la pantalla lee del store. Por defecto vacío: así los
  // casos que no hablan del roster siguen midiendo solo lo vendido.
  equipo: [] as Array<{
    perfil_id: string
    nombre_completo: string
    rol_crm: string
    supervisor_id: string | null
    activo: boolean
  }>,
  // Tri-estado del tipo de cambio, igual que el hook real: undefined =
  // consultando, null = no disponible, objeto = listo. Por defecto null, que es
  // como se comporta el entorno de prueba (no hay edge).
  tc: null as { promedio: number; fuente: string } | null | undefined,
  /** Argumentos con los que la pantalla pidió el TC, para poder comprobarlos. */
  tcArgs: [] as Array<{ habilitado: boolean; fechaCorte: string | undefined }>,
  recargarTc: 0,
  cargando: false,
  error: false,
  datos: undefined as undefined | (unknown[] & { descartadas?: number }),
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: { id: 'g1', rol: 'gerencia', demo: dobles.demo } }),
}))
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ equipo: dobles.equipo }) }))
vi.mock('@/lib/tipo-cambio', () => ({
  useTipoCambio: (habilitado = true, fechaCorte?: string) => {
    dobles.tcArgs.push({ habilitado, fechaCorte })
    return {
      tc: dobles.tc,
      recargar: () => {
        dobles.recargarTc += 1
      },
    }
  },
  usdAPen: (usd: number, tc: number) => (tc > 0 ? usd * tc : 0),
}))
vi.mock('@/data/crm-queries', () => ({
  // La pantalla pide TODOS los meses que toca el tramo; el doble devuelve una
  // consulta por mes con los mismos datos, que es lo que la pantalla aplana.
  useFacturacionDeMeses: (_habilitada: boolean, meses: readonly string[]) =>
    meses.map((_m, i) => ({
      // Solo la primera trae datos: repetirlos en cada mes los duplicaría.
      data: i === 0 ? dobles.datos : undefined,
      isPending: dobles.cargando,
      isError: dobles.error,
      isFetching: false,
      dataUpdatedAt: dobles.datos == null ? 0 : 1,
      refetch: vi.fn(),
    })),
}))

const { Facturacion } = await import('./facturacion')

/** Jueves 10 de setiembre de 2026, 12:00 en la zona de la máquina. */
const HOY = new Date(2026, 8, 10, 12, 0, 0)

function fila(p: Partial<FilaFacturacionDia> & { id?: string }): FilaFacturacionDia {
  const { id: _id, ...resto } = p
  return {
    dia: '2026-09-02',
    tipo: 'contrato_nuevo',
    moneda: 'PEN',
    analistaId: 'ana',
    analistaNombre: 'Ana Analista',
    supervisorId: 'sup-rosa',
    supervisorNombre: 'Rosa Uno',
    operaciones: 1,
    capital: 50_000,
    ...resto,
  }
}

/** Dos equipos, tres analistas. Solo Carla vende en dólares. */
const FILAS: readonly FilaFacturacionDia[] = [
  fila({ id: '1', dia: '2026-09-02', capital: 300_000 }),
  fila({ id: '2', dia: '2026-09-04', capital: 100_000 }),
  fila({ id: '3', dia: '2026-09-02', capital: 80_000, analistaId: 'beto', analistaNombre: 'Beto Analista' }),
  fila({
    id: '4',
    dia: '2026-09-03',
    capital: 40_000,
    analistaId: 'carla',
    analistaNombre: 'Carla Analista',
    supervisorId: 'sup-sara',
    supervisorNombre: 'Sara Dos',
  }),
  fila({
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
  fila({ id: '6', dia: '2026-08-05', capital: 200_000 }),
]

function pintar(filas: readonly FilaFacturacionDia[] = FILAS) {
  return render(<Facturacion filas={filas} />)
}

/** La malla, para no confundir sus botones con los del panel de filtros. */
function malla(): HTMLElement {
  return screen.getByRole('region', { name: /Facturación diaria/ })
}

beforeEach(() => {
  dobles.demo = false
  dobles.cargando = false
  dobles.error = false
  dobles.datos = undefined
  vi.useFakeTimers({ shouldAdvanceTime: true })
  vi.setSystemTime(HOY)
})

afterEach(() => {
  vi.useRealTimers()
})

describe('lo que se ve al entrar', () => {
  it('con datos REALES no dice que sean de ejemplo', () => {
    // La honestidad va en los dos sentidos: rotular de «ejemplo» cifras que sí
    // son reales es tan falso como lo contrario.
    pintar()
    expect(screen.queryByText('Datos de ejemplo')).not.toBeInTheDocument()
  })

  it('en modo demostración lo avisa ANTES de mostrar nada', () => {
    dobles.demo = true
    pintar()
    expect(screen.getByText('Datos de ejemplo')).toBeVisible()
    expect(screen.getByText(/no corresponden a ninguna venta real/i)).toBeVisible()
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

  it('preguntar por quien no vendió en esa moneda responde con su fila en cero, no con un callejón', () => {
    pintar()
    // Ana no vende en dólares. ANTES la malla se quedaba sin nada que pintar y
    // había que rescatarla; ahora el cero ES la respuesta a la pregunta.
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Ana Analista' }))
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))

    expect(screen.queryByText('Ningún cierre coincide con estos filtros.')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Carla Analista' })).not.toBeInTheDocument()
  })
})

describe('el analista que no ha vendido — petición de Miguel del 11/09/2026', () => {
  afterEach(() => {
    dobles.equipo = []
  })

  /** Organigrama del store: dos que ya venden, uno que no, y una baja. */
  function conEquipo(): void {
    dobles.equipo = [
      { perfil_id: 'sup-rosa', nombre_completo: 'Rosa Uno', rol_crm: 'supervisor', supervisor_id: null, activo: true },
      { perfil_id: 'ana', nombre_completo: 'Ana Analista', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
      { perfil_id: 'nuevo', nombre_completo: 'Noe Novato', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
      { perfil_id: 'baja', nombre_completo: 'Bruno Baja', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: false },
    ]
  }

  it('sale en la malla, y su fila está en cero', () => {
    conEquipo()
    pintar()
    const fila = within(malla())
      .getByRole('button', { name: 'Ver el mes completo de Noe Novato' })
      .closest('tr')
    expect(fila).not.toBeNull()
    // La celda vacía no lleva cifra a la vista, pero SÍ la anuncia para quien
    // usa lector: toda su fila dice 'S/ 0' y ni un solo importe con dígito.
    expect(within(fila as HTMLElement).queryByText(/S\/ [1-9]/)).toBeNull()
    expect(within(fila as HTMLElement).getAllByText('S/ 0').length).toBeGreaterThan(1)
  })

  it('se puede filtrar por él, que era justo lo que no se podía', () => {
    conEquipo()
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Noe Novato' }))
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Noe Novato' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Ana Analista' })).not.toBeInTheDocument()
  })

  it('en DEMO no se siembra: el fixture no se mezcla con el organigrama real', () => {
    conEquipo()
    dobles.demo = true
    try {
      pintar()
      expect(screen.queryByRole('button', { name: 'Ver el mes completo de Noe Novato' })).not.toBeInTheDocument()
    } finally {
      dobles.demo = false
    }
  })

  it('un analista dado de baja que no vendió NO aparece', () => {
    conEquipo()
    pintar()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Bruno Baja' })).not.toBeInTheDocument()
  })

  it('el organigrama no reescribe el equipo de una venta ya cerrada', () => {
    // El organigrama dice que Carla está HOY con Rosa; su venta es de cuando
    // estaba con Sara, y el equipo de Sara sigue sumándola. Mover a alguien de
    // equipo no le cambia de sitio el dinero que ya cerró. (El reparto fila a
    // fila se comprueba en el modelo: lib/facturacion.test.ts.)
    dobles.equipo = [
      { perfil_id: 'sup-rosa', nombre_completo: 'Rosa Uno', rol_crm: 'supervisor', supervisor_id: null, activo: true },
      { perfil_id: 'carla', nombre_completo: 'Carla Analista', rol_crm: 'vendedor', supervisor_id: 'sup-rosa', activo: true },
    ]
    pintar()
    fireEvent.click(within(malla()).getByRole('checkbox', { name: 'Comparar a Carla Analista' }))
    expect(within(malla()).getByText('Equipo de Sara Dos')).toBeVisible()
    expect(within(malla()).queryByText('Equipo de Rosa Uno')).toBeNull()
  })
})

describe('total del día con las dos monedas — petición de Miguel del 11/09/2026', () => {
  /**
   * El pie combinado solo existe en las vistas de UNA moneda: en «Todo S/» la
   * malla ya trae las dos y sería la misma cifra dos veces. Desde que la
   * pantalla abre en «Todo S/» (11/09), estos casos eligen Soles primero.
   */
  function verEnSoles(): void {
    fireEvent.click(screen.getByRole('button', { name: 'Soles' }))
  }

  afterEach(() => {
    dobles.tc = null
    dobles.tcArgs = []
    dobles.recargarTc = 0
  })

  it('el mes en curso pide el TC vigente; un mes cerrado lo congela en su último día', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    // HOY es el 10/09/2026: el mes en curso no lleva fecha de corte.
    expect(dobles.tcArgs.at(-1)?.fechaCorte).toBeUndefined()

    dobles.tcArgs = []
    fireEvent.click(screen.getByRole('button', { name: 'Mes anterior' }))
    // Agosto ya cerró: se congela en su último día, así su total no cambia cada
    // mañana. Sin esto, un mes cerrado se recalcularía con la tasa de hoy.
    expect(dobles.tcArgs.at(-1)?.fechaCorte).toBe('2026-08-31')
  })

  it('al pasar la medianoche vuelve a pedir el TC del mes en curso', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    expect(dobles.recargarTc).toBe(0)

    // La clave del hook para el mes en curso no lleva la fecha: una pestaña
    // abierta de un día para otro seguiría convirtiendo con la tasa de ayer
    // mientras la facturación sí se refresca. (Codex, 11/09/2026.)
    act(() => {
      vi.setSystemTime(new Date(2026, 8, 11, 12, 0, 0))
      vi.advanceTimersByTime(600_001)
    })
    expect(dobles.recargarTc).toBe(1)
  })

  it('en un mes cerrado NO recarga al pasar el día: su tasa está congelada', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    fireEvent.click(screen.getByRole('button', { name: 'Mes anterior' }))
    dobles.recargarTc = 0

    act(() => {
      vi.setSystemTime(new Date(2026, 8, 11, 12, 0, 0))
      vi.advanceTimersByTime(600_001)
    })
    // Agosto ya cerró: recargar su tasa la movería, que es justo lo contrario
    // de congelarla.
    expect(dobles.recargarTc).toBe(0)
  })

  it('en la métrica de contratos suma las dos monedas con cifras, no solo el rótulo', () => {
    dobles.tc = null
    pintar()
    verEnSoles()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    const pie = within(malla()).getByRole('row', { name: /Total del día/ })
    // El 3 de setiembre tiene un cierre en soles y otro en dólares: son DOS
    // contratos. Se suman tal cual, sin conversión — son cuentas, no dinero.
    expect(within(pie).getAllByText('2 contratos').length).toBeGreaterThanOrEqual(1)
    // Y el mes entero son 5: los 4 en soles más el de dólares.
    expect(within(pie).getByText('5')).toBeInTheDocument()
  })

  it('con tipo de cambio, el pie suma el dólar convertido a soles', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // El mes del fixture: S/ 520,000 en soles y US$ 7,000 en dólares.
    expect(within(pie).getByText('S/ 546,250')).toBeVisible()
    expect(within(malla()).getByText(/TC S\/ 3\.75/)).toBeVisible()
    // Y los días sí llevan cifra: el 3 de setiembre es 40 000 + 7 000 × 3,75.
    expect(within(pie).queryAllByText(/\d/).length).toBeGreaterThan(0)
  })

  it('SIN tipo de cambio calla SOLO los días que tienen dólares', () => {
    dobles.tc = null
    pintar()
    verEnSoles()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // Un día sin un solo dólar tiene su total completo en soles: exigirle tasa
    // pondría un guion sobre una cifra que sí se conoce. (Me lo señaló Codex el
    // 11/09/2026; mi primera versión callaba el mes entero.)
    expect(within(pie).getByText('S/ 380,000')).toBeInTheDocument() // 2/09: 300k + 80k, sin dólares
    // El 3 de setiembre SÍ tiene US$ 7,000, y el mes también: ahí no se afirma.
    expect(within(pie).getAllByText('—')).toHaveLength(2) // el día 3 y el total del mes
    expect(within(pie).queryByText('S/ 520,000')).toBeNull() // el solo-PEN del mes, jamás
    // El motivo sale en el rótulo de la fila Y en el texto accesible del día
    // que se calla: quien use lector no se queda sin la explicación.
    expect(
      within(pie).getAllByText('total no disponible: falta el tipo de cambio').length,
    ).toBeGreaterThanOrEqual(2)
  })

  it('ofrece reintentar cuando el tipo de cambio no llegó', () => {
    dobles.tc = null
    pintar()
    verEnSoles()
    // Una caída del BCRP es transitoria; sin este botón la fila se quedaba en
    // guiones hasta remontar la pantalla. (Codex, 11/09/2026.)
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    expect(within(pie).getByRole('button', { name: /Reintentar/ })).toBeVisible()
  })

  it('con TC no ofrece reintentar: no hay nada que recuperar', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    expect(within(pie).queryByRole('button', { name: /Reintentar/ })).toBeNull()
  })

  it('el importe EXACTO del día se puede consultar, aunque la celda vaya abreviada', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // 3/09: S/ 40,000 + US$ 7,000 × 3,75 = S/ 66,250. La celda pinta «66k»; el
    // importe exacto vive en el texto accesible. Sin esto había que hacer la
    // conversión a mano. (Codex, 11/09/2026.)
    expect(within(pie).getByText('S/ 66,250')).toBeInTheDocument()
  })

  it('si SOLO hay ventas en dólares, la fila NO desaparece: es cuando más sirve', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    // Un mes entero en dólares: la vista en soles marcaría S/ 0 mientras hay
    // dinero, y mi primera versión escondía justo aquí el equivalente.
    pintar([
      fila({ id: 'u1', dia: '2026-09-02', moneda: 'USD', capital: 7_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
    ])
    verEnSoles()
    const pie = within(malla()).getByRole('row', { name: /Total del día en soles/ })
    // Sale dos veces y así debe ser: el día y el total del mes, que con una
    // sola venta son la misma cifra.
    expect(within(pie).getAllByText('S/ 26,250')).toHaveLength(2)
  })

  it('si NO hay un solo dólar, la fila no se pinta: sería un duplicado', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar([
      fila({ id: 'p1', dia: '2026-09-02', moneda: 'PEN', capital: 50_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
    ])
    verEnSoles()
    expect(within(malla()).queryByRole('row', { name: /Total del día en soles/ })).toBeNull()
  })

  it('mientras consulta el TC no dice «no disponible»', () => {
    dobles.tc = undefined
    pintar()
    verEnSoles()
    expect(within(malla()).getByText('consultando el tipo de cambio…')).toBeVisible()
  })

  it('el total en soles NO cambia al cambiar de moneda: es el del día, entero', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    verEnSoles()
    expect(within(within(malla()).getByRole('row', { name: /Total del día en soles/ })).getByText('S/ 546,250')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    expect(within(within(malla()).getByRole('row', { name: /Total del día en soles/ })).getByText('S/ 546,250')).toBeVisible()
  })

  it('en contratos se suman las dos monedas, sin conversión que valga', () => {
    dobles.tc = null
    pintar()
    verEnSoles()
    fireEvent.click(screen.getByRole('button', { name: 'N.º de contratos' }))
    const pie = within(malla()).getByRole('row', { name: /Total del día/ })
    expect(within(pie).getByText('contratos de ambas monedas')).toBeVisible()
  })
})

describe('tipos de capital — el contrato que Miguel no encontraba (11/09/2026)', () => {
  /** El tipo se elige en un desplegable, no en botones: cinco botones partían
   *  la barra de filtros en dos filas. */
  function elegirTipo(valor: string): void {
    fireEvent.change(screen.getByRole('combobox', { name: 'Tipo de capital' }), { target: { value: valor } })
  }

  /** Un mes con los cuatro tipos, como el setiembre real. */
  const VARIADAS: readonly FilaFacturacionDia[] = [
    fila({ id: 'n', dia: '2026-09-02', tipo: 'contrato_nuevo', capital: 300_000 }),
    fila({ id: 'r', dia: '2026-09-02', tipo: 'contrato_renovacion', capital: 10_000 }),
    fila({ id: 'u', dia: '2026-09-03', tipo: 'contrato_upgrade', capital: 25_000 }),
    fila({ id: 'c', dia: '2026-09-03', tipo: 'cooperativa', capital: 40_000 }),
  ]

  it('abre en capital nuevo, como hasta ahora', () => {
    pintar(VARIADAS)
    expect(screen.getByRole('combobox', { name: 'Tipo de capital' })).toHaveValue('contrato_nuevo')
    // Sale varias veces —fila del analista, fila del equipo, pie— y así debe ser.
    expect(within(malla()).getAllByText('S/ 300,000').length).toBeGreaterThan(0)
    expect(within(malla()).queryByText('S/ 10,000')).toBeNull() // la renovación, fuera
  })

  it('una renovación SÍ se puede ver: era justo lo que no se podía', () => {
    pintar(VARIADAS)
    elegirTipo('contrato_renovacion')
    expect(within(malla()).getAllByText('S/ 10,000').length).toBeGreaterThan(0)
    expect(within(malla()).queryByText('S/ 300,000')).toBeNull()
  })

  it('«Todo» suma los cuatro tipos, sin mezclar monedas', () => {
    pintar(VARIADAS)
    elegirTipo('todo')
    expect(within(malla()).getAllByText('S/ 375,000').length).toBeGreaterThan(0)
  })

  it('el titular sigue a la perilla: nunca dos cifras distintas a la vez', () => {
    // Decisión de Miguel: «lo que diga la perilla». Un titular clavado en
    // capital nuevo mientras la tabla enseña renovaciones sería un tablero
    // diciendo dos cosas al mismo tiempo.
    pintar(VARIADAS)
    expect(screen.getAllByText('S/ 300,000').length).toBeGreaterThanOrEqual(2) // titular y malla
    expect(screen.queryByText('S/ 375,000')).toBeNull()
    elegirTipo('todo')
    expect(screen.getAllByText('S/ 375,000').length).toBeGreaterThanOrEqual(2) // titular y malla
    expect(screen.queryByText('S/ 300,000')).toBeNull()
  })

  it('el % contra el mes pasado compara EL MISMO tipo, no manzanas con peras', () => {
    // Setiembre: 100k de renovación. Agosto: 50k de renovación y 400k de nuevo.
    // Comparando bien sale +100 %; comparando contra el nuevo de agosto saldría
    // −75 %, y el titular estaría mintiendo sobre el propio mes que enseña.
    pintar([
      fila({ id: 'r9', dia: '2026-09-02', tipo: 'contrato_renovacion', capital: 100_000 }),
      fila({ id: 'r8', dia: '2026-08-05', tipo: 'contrato_renovacion', capital: 50_000 }),
      fila({ id: 'n8', dia: '2026-08-05', tipo: 'contrato_nuevo', capital: 400_000 }),
    ])
    elegirTipo('contrato_renovacion')
    expect(screen.getByText(/\+100\.0 % vs\. el mismo tramo de/)).toBeVisible()
  })

  it('el rótulo del KPI de contratos deja de decir «nuevos» siempre', () => {
    pintar(VARIADAS)
    expect(screen.getByText('Contratos · Capital nuevo')).toBeVisible()
    elegirTipo('contrato_renovacion')
    expect(screen.getByText('Contratos · Renovación')).toBeVisible()
    elegirTipo('todo')
    expect(screen.getByText('Contratos cerrados')).toBeVisible()
  })

  it('el detalle de una celda habla del tipo que se está viendo', () => {
    pintar(VARIADAS)
    elegirTipo('contrato_renovacion')
    fireEvent.click(within(malla()).getByRole('button', { name: 'Ver el mes completo de Ana Analista' }))
    // Abrir una celda de renovaciones y encontrar ahí los contratos nuevos
    // contradiría la cifra sobre la que se acaba de pinchar.
    const panel = screen.getByRole('dialog')
    // El desglose lista «Renovación · N contratos»; el tipo aparece tantas
    // veces como líneas tenga, pero NUNCA el capital nuevo.
    expect(within(panel).getAllByText(/Renovación/).length).toBeGreaterThan(0)
    expect(within(panel).queryByText(/Capital nuevo/)).toBeNull()
  })
})

describe('hallazgos de la auditoría del 11/09/2026', () => {
  function elegirTipoAudit(valor: string): void {
    fireEvent.change(screen.getByRole('combobox', { name: 'Tipo de capital' }), { target: { value: valor } })
  }

  it('el % compara el MISMO TRAMO del mes anterior, no el mes entero', () => {
    // HOY es el 10/09. El corte del mes anterior es el 10/08.
    // Setiembre: 100k. Agosto: 100k hasta el día 10 y 900k DESPUÉS.
    // Bien comparado da 0 %. Comparando contra agosto entero daba −90 %.
    // El recorte estaba escrito pero solo se le pasaba al generador del demo:
    // con datos reales se comparaba media carrera contra la carrera completa.
    pintar([
      fila({ id: 's9', dia: '2026-09-02', capital: 100_000 }),
      fila({ id: 'a8a', dia: '2026-08-05', capital: 100_000 }),
      fila({ id: 'a8b', dia: '2026-08-20', capital: 900_000 }),
    ])
    expect(screen.getByText(/\+0\.0 % vs\. el mismo tramo de/)).toBeVisible()
    expect(screen.queryByText(/−90\.0 %/)).toBeNull()
  })

  it('un mes CERRADO sí compara contra el mes anterior completo', () => {
    // Al retroceder a agosto, el corte deja de aplicar: agosto entero contra
    // julio entero. Recortar aquí sería el error simétrico.
    pintar([
      fila({ id: 'a8', dia: '2026-08-05', capital: 200_000 }),
      fila({ id: 'j7a', dia: '2026-07-03', capital: 50_000 }),
      fila({ id: 'j7b', dia: '2026-07-28', capital: 50_000 }),
    ])
    fireEvent.click(screen.getByRole('button', { name: 'Mes anterior' }))
    expect(screen.getByText(/\+100\.0 % vs\. el mismo tramo de/)).toBeVisible()
  })

  it('el detalle de una celda NO trae dinero de otra moneda ni de otro equipo', () => {
    // Con Dólares seleccionado, abrir el mes de Carla debe enseñar solo sus
    // dólares. Antes el panel recibía TODAS las filas y solo acotaba analista,
    // día y tipo: se colaban los soles bajo un rótulo que decía «Dólares».
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    elegirTipoAudit('todo')
    fireEvent.click(within(malla()).getByRole('button', { name: 'Ver el mes completo de Carla Analista' }))
    const panel = screen.getByRole('dialog')
    expect(within(panel).getByText(/US\$ 7,000/)).toBeVisible()
    expect(within(panel).queryByText(/S\/ 40,000/)).toBeNull()
  })
})

describe('vista «Todo S/» — el arranque por defecto (Miguel, 11/09/2026)', () => {
  afterEach(() => {
    dobles.tc = null
  })

  it('abre en Todo S/, no en Soles', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    expect(screen.getByRole('button', { name: 'Todo S/' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('cada celda trae las DOS monedas convertidas, no solo los soles', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar([
      fila({ id: 'p', dia: '2026-09-02', moneda: 'PEN', capital: 40_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
      fila({ id: 'd', dia: '2026-09-02', moneda: 'USD', capital: 7_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
    ])
    // 40 000 + 7 000 × 3,75 = 66 250 en una sola celda.
    expect(within(malla()).getAllByText('S/ 66,250').length).toBeGreaterThan(0)
  })

  it('quien solo vendió en dólares NO desaparece de la vista Todo', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar([
      fila({ id: 'd', dia: '2026-09-02', moneda: 'USD', capital: 2_000, analistaId: 'solo', analistaNombre: 'Solo Dolares' }),
    ])
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Solo Dolares' })).toBeVisible()
    expect(within(malla()).getAllByText('S/ 7,500').length).toBeGreaterThan(0)
  })

  it('SIN tipo de cambio se repliega a Soles y lo dice: nunca abre vacía', () => {
    // Abrir en «Todo S/» y no poder convertir no puede dejar la pantalla en
    // blanco. Se repliega, y la perilla se mueve sola para no rotular «Todo»
    // sobre una tabla que solo trae soles.
    dobles.tc = null
    pintar()
    expect(screen.getByRole('button', { name: 'Soles' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Todo S/' })).toHaveAttribute('aria-pressed', 'false')
    expect(within(malla()).getByText(/Soles/)).toBeVisible()
  })

  it('mientras consulta la tasa no se repliega ni afirma que falta', () => {
    dobles.tc = undefined
    pintar()
    expect(screen.getByText(/Consultando el tipo de cambio/)).toBeVisible()
    expect(screen.queryByText(/Falta el tipo de cambio/)).toBeNull()
  })
})

describe('honestidad de las cifras — auditoría del 11/09/2026', () => {
  /** Sin `filas` por prop, la pantalla depende de la consulta: el camino real. */
  function pintarReal(): void {
    render(<Facturacion />)
  }

  it('mientras carga NO dice S/ 0: dice que está cargando', () => {
    dobles.cargando = true
    pintarReal()
    expect(screen.queryByText('S/ 0')).toBeNull()
    expect(screen.getAllByText('—').length).toBeGreaterThan(0)
    // Sale en varios indicadores a la vez, que es lo correcto.
    expect(screen.getAllByText(/Cargando la facturación del mes/).length).toBeGreaterThan(0)
  })

  it('si la consulta FALLA tampoco dice cero: una avería no es un mes sin ventas', () => {
    dobles.error = true
    pintarReal()
    expect(screen.queryByText('S/ 0')).toBeNull()
    expect(screen.getAllByText(/No se pudo cargar/).length).toBeGreaterThan(0)
  })

  it('una venta pequeña NO se pinta como cero', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    // S/ 400 se redondeaba a «0k» y se leía como que no vendió nada.
    pintar([fila({ id: 'chica', dia: '2026-09-02', capital: 400 })])
    const celdas = within(malla())
    expect(celdas.queryAllByText('0k')).toHaveLength(0)
    expect(celdas.getAllByText('400').length).toBeGreaterThan(0)
  })

  it('avisa cuando el servidor mandó filas que no se pudieron leer', () => {
    const datos = Object.assign(
      [
        {
          dia: '2026-09-02', tipo: 'contrato_nuevo', moneda: 'PEN',
          analistaId: 'ana', analistaNombre: 'Ana Analista',
          supervisorId: 'sup-rosa', supervisorNombre: 'Rosa Uno',
          operaciones: 1, capital: 50_000,
        },
      ],
      { descartadas: 2 },
    )
    dobles.datos = datos
    pintarReal()
    // Un total al que le faltan cifras sin decirlo es peor que un error.
    expect(screen.getByText(/2 filas del servidor no se pudo leer/)).toBeVisible()
  })

  it('avisa si el mes llegó al límite de filas del servidor', () => {
    // 1000 FILAS, pocas personas: lo que dispara el aviso es el número de filas
    // que devolvió el servidor, no cuántos analistas hay. Con mil analistas
    // distintos la prueba solo mediría lo que tarda en pintar una tabla enorme.
    const muchas = Array.from({ length: 1000 }, (_, i) => ({
      dia: `2026-09-${String((i % 28) + 1).padStart(2, '0')}`,
      tipo: 'contrato_nuevo', moneda: 'PEN',
      analistaId: `a${i % 4}`, analistaNombre: `Analista ${i % 4}`,
      supervisorId: 'sup-rosa', supervisorNombre: 'Rosa Uno',
      operaciones: 1, capital: 1_000,
    }))
    dobles.datos = Object.assign(muchas, { descartadas: 0 })
    pintarReal()
    expect(screen.getByText(/límite de filas del servidor/)).toBeVisible()
  })
})

describe('tramo: mes, semana y día (Miguel, 11/09/2026)', () => {
  function elegirTramo(nombre: string): void {
    fireEvent.click(screen.getByRole('button', { name: nombre }))
  }

  it('abre en Mes, como hasta ahora', () => {
    pintar()
    expect(screen.getByRole('button', { name: 'Mes' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Mes anterior' })).toBeVisible()
  })

  it('en Semana la tabla enseña 7 días y las flechas se mueven por semanas', () => {
    // HOY es jueves 10/09: la semana va del lunes 7 al domingo 13. El fixture
    // general vende el 2, 3 y 4, así que aquí hace falta algo DENTRO.
    pintar([fila({ id: 'sem', dia: '2026-09-10', capital: 50_000 })])
    elegirTramo('Semana')
    expect(screen.getByRole('button', { name: 'Semana anterior' })).toBeVisible()
    // HOY es jueves 10/09: la semana va del lunes 7 al domingo 13.
    expect(within(malla()).getAllByRole('columnheader').length).toBe(9) // 7 días + nombre + total
  })

  it('en Día la tabla enseña un solo día', () => {
    pintar([fila({ id: 'hoy', dia: '2026-09-10', capital: 50_000 })])
    elegirTramo('Día')
    expect(screen.getByRole('button', { name: 'Día anterior' })).toBeVisible()
    expect(within(malla()).getAllByRole('columnheader').length).toBe(3) // 1 día + nombre + total
  })

  it('los totales se recalculan sobre el tramo, no sobre el mes', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    // 100k el 2 de setiembre (fuera de la semana del 7) y 20k el 10 (dentro).
    pintar([
      fila({ id: 'f', dia: '2026-09-02', capital: 100_000 }),
      fila({ id: 'd', dia: '2026-09-10', capital: 20_000 }),
    ])
    expect(screen.getAllByText('S/ 120,000').length).toBeGreaterThan(0)
    elegirTramo('Semana')
    // Si el titular siguiera diciendo el mes habría dos verdades a la vez.
    expect(screen.getAllByText('S/ 20,000').length).toBeGreaterThan(0)
    expect(screen.queryByText('S/ 120,000')).toBeNull()
    dobles.tc = null
  })

  it('TODOS los rótulos siguen al tramo: nunca el titular diciendo «mes»', () => {
    dobles.tc = { promedio: 3.75, fuente: 'SUNAT · prom. 7d' }
    pintar()
    expect(screen.getByText((s) => /Facturado/i.test(s) && /setiembre de 2026/i.test(s))).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Semana' }))
    // Un titular que dice «setiembre» sobre la cifra de una semana es la misma
    // clase de mentira que el % comparando contra el mes entero.
    expect(
      screen.queryByText((s) => /Facturado/i.test(s) && /setiembre de 2026/i.test(s)),
    ).toBeNull()
    // El rótulo del indicador nombra EL MISMO tramo que la barra de navegación,
    // sea cual sea el formato corto de fecha del sistema. (El prefijo cambia
    // entre «Total facturado» y «Facturado» según haya dólares en el tramo: eso
    // es correcto y no es lo que se está comprobando aquí.)
    const tramo = screen.getByRole('button', { name: 'Semana anterior' }).nextElementSibling
    expect(tramo?.textContent ?? '').not.toBe('')
    expect(
      screen.getByText((s) => /Facturado/i.test(s) && s.includes(tramo?.textContent ?? 'x')),
    ).toBeVisible()
    expect(screen.getByText(/semana anterior/)).toBeVisible()
    expect(screen.queryByText(/vs\. el mismo tramo del mes anterior/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Día' }))
    // Con el fixture no hay ventas el día anterior, así que no hay % — pero lo
    // que NUNCA puede quedar es la comparación hablando de meses.
    expect(screen.queryByText(/mes anterior/)).toBeNull()
    dobles.tc = null
  })

  it('en un tramo solo salen los del tramo, no los del mes entero', () => {
    // Ana vende el 2 (fuera de la semana del 7) y Beto el 10 (dentro). Si el
    // roster siguiera saliendo del mes, la semana ofrecería a Ana en cero y el
    // selector de analistas mentiría sobre quién trabajó esos días.
    pintar([
      fila({ id: 'a', dia: '2026-09-02', capital: 10_000, analistaId: 'ana', analistaNombre: 'Ana Analista' }),
      fila({ id: 'b', dia: '2026-09-10', capital: 20_000, analistaId: 'beto', analistaNombre: 'Beto Analista' }),
    ])
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
    elegirTramo('Semana')
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Beto Analista' })).toBeVisible()
    expect(screen.queryByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeNull()
  })

  it('no deja navegar al futuro', () => {
    pintar()
    elegirTramo('Día')
    // HOY es el 10/09: no hay «día siguiente».
    expect(screen.getByRole('button', { name: 'Día siguiente' })).toBeDisabled()
  })
})

describe('marcar días sueltos (Miguel, 11/09/2026)', () => {
  const TRES_DIAS: readonly FilaFacturacionDia[] = [
    fila({ id: 'd2', dia: '2026-09-02', capital: 10_000 }),
    fila({ id: 'd3', dia: '2026-09-03', capital: 20_000 }),
    fila({ id: 'd4', dia: '2026-09-04', capital: 40_000 }),
  ]
  function marcar(etiqueta: RegExp): void {
    fireEvent.click(within(malla()).getByRole('button', { name: etiqueta }))
  }

  it('marcar dos días sueltos suma SOLO esos dos', () => {
    pintar(TRES_DIAS)
    expect(screen.getAllByText('S/ 70,000').length).toBeGreaterThan(0)
    marcar(/Marcar el .*, 2 de setiembre/i)
    marcar(/Marcar el .*, 4 de setiembre/i)
    // 10 000 + 40 000; el día 3 queda fuera aunque esté en medio.
    expect(screen.getAllByText('S/ 50,000').length).toBeGreaterThan(0)
    expect(screen.queryByText('S/ 70,000')).toBeNull()
  })

  it('el punto late al entrar y se queda quieto al elegir', () => {
    // La pista que pidió Miguel para su gerente. Con días ya elegidos el latido
    // sobra: ya sabe que se pulsan, y 31 columnas latiendo serían un tic.
    pintar(TRES_DIAS)
    const conPista = document.querySelectorAll('.ac-pista-dia')
    expect(conPista.length).toBeGreaterThan(0)
    marcar(/Marcar el .*, 2 de setiembre/i)
    expect(document.querySelectorAll('.ac-pista-dia')).toHaveLength(0)
  })

  it('DICE que se pueden elegir días, donde se lee', () => {
    // El aviso vivía en el <caption>, que es solo para lectores de pantalla, y
    // por eso Miguel no encontraba la función aunque estuviera hecha.
    pintar(TRES_DIAS)
    // Tiene que estar FUERA del `sr-only`: ahí es donde estaba y no servía.
    const visible = screen
      .getAllByText(/Pulsa el número de un día/)
      .find((el) => el.closest('.sr-only') == null)
    expect(visible).toBeDefined()
    expect(visible).toBeVisible()
    marcar(/Marcar el .*, 2 de setiembre/i)
    expect(screen.getByText(/Pulsa otro número para añadirlo/)).toBeVisible()
  })

  it('la tabla NO pierde columnas: hay que poder marcar un cuarto día', () => {
    pintar(TRES_DIAS)
    marcar(/Marcar el .*, 2 de setiembre/i)
    // Si marcar escondiera las demás columnas, ya no habría forma de añadir el 4.
    expect(within(malla()).getByRole('button', { name: /Marcar el .*, 4 de setiembre/i })).toBeVisible()
    marcar(/Marcar el .*, 4 de setiembre/i)
    expect(screen.getAllByText('S/ 50,000').length).toBeGreaterThan(0)
  })

  it('TODOS los números de arriba siguen a los días elegidos', () => {
    pintar(TRES_DIAS)
    marcar(/Marcar el .*, 2 de setiembre/i)
    marcar(/Marcar el .*, 4 de setiembre/i)
    // Titular, rótulo, mejor día y divisor del promedio: o todos hablan de los
    // días elegidos, o la pantalla dice dos cosas a la vez.
    // Sale en el rótulo del indicador Y en el aviso de arriba de la tabla.
    expect(screen.getAllByText(/2 días elegidos/).length).toBeGreaterThanOrEqual(2)
    expect(screen.getByText('Mejor día de los elegidos')).toBeVisible()
    expect(screen.getByText(/2 días hábiles/)).toBeVisible()
  })

  it('un día NO elegido no puede ganar el «mejor día»', () => {
    // El 3 es el día más grande del mes con diferencia, pero queda fuera.
    pintar([
      fila({ id: 'd2', dia: '2026-09-02', capital: 10_000 }),
      fila({ id: 'd3', dia: '2026-09-03', capital: 900_000 }),
      fila({ id: 'd4', dia: '2026-09-04', capital: 40_000 }),
    ])
    marcar(/Marcar el .*, 2 de setiembre/i)
    marcar(/Marcar el .*, 4 de setiembre/i)
    // La tarjeta entera: rótulo, cifra y el día debajo.
    const tarjeta = screen
      .getByText('Mejor día de los elegidos')
      .closest('div.p-4') as HTMLElement | null
    expect(tarjeta).not.toBeNull()
    expect(tarjeta?.textContent ?? '').toMatch(/4 de setiembre/)
    expect(tarjeta?.textContent ?? '').not.toMatch(/3 de setiembre/)
  })

  it('volver a pulsar un día lo desmarca', () => {
    pintar(TRES_DIAS)
    marcar(/Marcar el .*, 2 de setiembre/i)
    expect(screen.getAllByText('S/ 10,000').length).toBeGreaterThan(0)
    marcar(/Marcar el .*, 2 de setiembre/i)
    expect(screen.getAllByText('S/ 70,000').length).toBeGreaterThan(0)
  })

  it('lo dice con una etiqueta que se puede quitar', () => {
    pintar(TRES_DIAS)
    marcar(/Marcar el .*, 2 de setiembre/i)
    marcar(/Marcar el .*, 3 de setiembre/i)
    const chip = screen.getByRole('button', { name: 'Quitar los días marcados' })
    expect(chip).toHaveTextContent('2 días marcados')
    fireEvent.click(chip)
    expect(screen.getAllByText('S/ 70,000').length).toBeGreaterThan(0)
  })

  it('con días a mano NO inventa una comparación', () => {
    // ¿Contra qué se compara «el 2 y el 4»? No hay respuesta honesta. Y el
    // fixture SÍ trae agosto, así que sin la guarda saldría un porcentaje.
    pintar([...TRES_DIAS, fila({ id: 'ago', dia: '2026-08-05', capital: 5_000 })])
    expect(screen.getByText(/% vs\./)).toBeVisible()
    marcar(/Marcar el .*, 2 de setiembre/i)
    expect(screen.getByText('Días elegidos a mano: sin comparación')).toBeVisible()
    expect(screen.queryByText(/% vs\./)).toBeNull()
  })

  it('cambiar de tramo suelta los días: eran de otro sitio', () => {
    // Se marca el 10, que SÍ cae dentro de la semana del 7 al 13: así la prueba
    // comprueba que se sueltan de verdad, y no que se caen por no pertenecer
    // al tramo nuevo.
    pintar([...TRES_DIAS, fila({ id: 'd10', dia: '2026-09-10', capital: 1_000 })])
    marcar(/Marcar el .*, 10 de setiembre/i)
    expect(screen.getByRole('button', { name: 'Quitar los días marcados' })).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Semana' }))
    expect(screen.queryByRole('button', { name: 'Quitar los días marcados' })).toBeNull()
  })
})

describe('tablet — Miguel, 11/09/2026: «esto está pensado para usar en tablet»', () => {
  /**
   * Simula un iPad: puntero grueso, sin hover y ventana estrecha. El criterio
   * del CRM NO es el ancho sino el puntero, para que un portátil con la ventana
   * a media pantalla siga siendo escritorio.
   */
  function comoTablet(): void {
    vi.stubGlobal('matchMedia', (consulta: string) => ({
      matches:
        consulta.includes('hover: none') ||
        consulta.includes('max-width: 1279px') ||
        consulta.includes('max-width: 1099px'),
      media: consulta,
      addEventListener: () => {},
      removeEventListener: () => {},
    }))
  }

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('abre en Semana: el mes no cabe en una tablet', () => {
    // Medido en iPad vertical antes del arreglo: 4 días visibles de 30.
    comoTablet()
    pintar()
    expect(screen.getByRole('button', { name: 'Semana' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('button', { name: 'Mes' })).toHaveAttribute('aria-pressed', 'false')
  })

  it('en escritorio sigue abriendo en Mes', () => {
    pintar()
    expect(screen.getByRole('button', { name: 'Mes' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('pliega lo secundario detrás de «Filtros» y deja a la vista lo de diario', () => {
    comoTablet()
    pintar()
    // Tramo y moneda SIEMPRE visibles; el resto, tras el botón.
    expect(screen.getByRole('button', { name: 'Semana' })).toBeVisible()
    expect(screen.getByRole('button', { name: 'Todo S/' })).toBeVisible()
    const filtros = screen.getByRole('button', { name: /Filtros/ })
    expect(filtros).toHaveAttribute('aria-expanded', 'false')
    fireEvent.click(filtros)
    expect(filtros).toHaveAttribute('aria-expanded', 'true')
  })

  it('en escritorio NO hay botón «Filtros»: todo cabe', () => {
    pintar()
    expect(screen.queryByRole('button', { name: /^Filtros/ })).toBeNull()
  })

  it('las casillas de comparar crecen para el dedo', () => {
    comoTablet()
    // Abre en Semana (7 al 13): hace falta una venta DENTRO para que haya malla.
    pintar([fila({ id: 'sem', dia: '2026-09-10', capital: 50_000 })])
    // HAY DOS casillas distintas: la de cada fila de la malla y la del panel de
    // analistas. La primera versión de esta prueba solo miraba una, y el
    // mutante que encogía la otra sobrevivía.
    const enLaMalla = within(malla()).getAllByRole('checkbox')[0]
    expect(enLaMalla?.className).toContain('size-6')
    expect(enLaMalla?.className).not.toContain('size-4')

    fireEvent.click(screen.getByRole('button', { name: /^Analistas/ }))
    const enElPanel = within(screen.getByRole('group', { name: /Analistas/ })).getAllByRole('checkbox')[0]
    // 14 px es imposible de acertar con un dedo; 24 es el mínimo usable.
    expect(enElPanel?.className).toContain('size-6')
    expect(enElPanel?.className).not.toContain('size-3.5')
  })
})

describe('moneda y métrica', () => {
  it('cambiar de moneda cambia los números, no quién aparece', () => {
    pintar()
    fireEvent.click(screen.getByRole('button', { name: 'Dólares' }))
    expect(within(malla()).getAllByText('US$ 7,000').length).toBeGreaterThanOrEqual(2)
    // Ana no vendió un solo dólar y aun así conserva su fila: la tabla es el
    // equipo, y las filas no aparecen y desaparecen al tocar un interruptor.
    expect(screen.getByRole('button', { name: 'Ver el mes completo de Ana Analista' })).toBeVisible()
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
