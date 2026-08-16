import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ConfiguracionMetas, DetalleMeta } from '@/lib/metas-versionadas'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  cierreEstado: {} as Record<string, unknown>,
  cierreHabilitada: undefined as boolean | undefined,
  yo: { id: '30000000-0000-4000-8000-000000000001', demo: false } as { id: string; demo: boolean },
  publicar: vi.fn(),
  recargar: vi.fn(),
  obtenerAnterior: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
  periodoConsultado: '',
}))

vi.mock('sonner', () => ({
  toast: { success: dobles.toastSuccess, error: dobles.toastError },
}))

// Publicar tiene que resincronizar el store: los paneles no leen de la consulta
// del editor, así que sin esto gerencia publicaba y sus pantallas seguían
// diciendo «Sin meta».
vi.mock('@/lib/store-context', () => ({ useCRMData: () => ({ recargar: dobles.recargar }) }))

vi.mock('@/data/crm-config-queries', () => ({
  useConfiguracionMetas: (periodo: string) => {
    dobles.periodoConsultado = periodo
    return dobles.consulta
  },
  usePublicarMetas: () => ({ mutateAsync: dobles.publicar, isPending: false }),
}))

// El estado del cierre de mes es advisory: el editor solo lee `data.ultimo_cerrado`.
vi.mock('@/data/crm-queries', () => ({
  useCierreMesEstado: (habilitada: boolean) => {
    dobles.cierreHabilitada = habilitada
    return dobles.cierreEstado
  },
}))

// Sesión real por defecto: la consulta del estado solo se apaga en demo.
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: dobles.yo }),
}))

vi.mock('@/data/crm-config-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-config-api')>()
  return {
    ...actual,
    obtenerConfiguracionMetas: (...args: unknown[]) => dobles.obtenerAnterior(...args),
  }
})

const { ConfigMetas } = await import('./config-metas')

const ID_VENDEDOR = '10000000-0000-4000-8000-000000000001'
const ID_SUPERVISOR = '20000000-0000-4000-8000-000000000001'

function detalles(capitalBase = 1_000): DetalleMeta[] {
  return [
    { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: capitalBase, contratos_objetivo: 1 },
    { categoria: 'nuevo', moneda: 'USD', capital_objetivo: 2_000, contratos_objetivo: 2 },
    { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: 3_000, contratos_objetivo: 3 },
    { categoria: 'renovacion', moneda: 'USD', capital_objetivo: 4_000, contratos_objetivo: 4 },
    { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: 5_000, contratos_objetivo: 5 },
    { categoria: 'upgrade', moneda: 'USD', capital_objetivo: 6_000, contratos_objetivo: 6 },
  ]
}

function configuracion(overrides: Partial<ConfiguracionMetas> = {}): ConfiguracionMetas {
  return {
    version: 1,
    periodo: '2026-08-01',
    revision: 4,
    publicada_en: '2026-08-02T15:00:00.000Z',
    publicada_por: '30000000-0000-4000-8000-000000000001',
    publicada_por_nombre: 'GERENCIA UNO',
    puede_editar: true,
    sin_supervisor: [],
    vendedores: [{
      vendedor_id: ID_VENDEDOR,
      nombre: 'ANA VENDEDORA',
      supervisor_id: ID_SUPERVISOR,
      supervisor_nombre: 'SUPERVISOR UNO',
      conversion_objetivo: 15,
      detalles: detalles(),
    }],
    ...overrides,
  }
}

function consultaCon(
  data: ConfiguracionMetas | undefined,
  overrides: Record<string, unknown> = {},
) {
  return {
    data,
    error: null,
    isPending: false,
    isError: false,
    isSuccess: Boolean(data),
    refetch: vi.fn(),
    ...overrides,
  }
}

/** El payload de `useCierreMesEstado` reducido a lo que el editor consume. */
function cierreEstadoCon(ultimoCerrado: {
  mes: string
  mes_nombre: string
  cerrado_en: string
  automatico: boolean
} | null) {
  return { data: { ultimo_cerrado: ultimoCerrado }, isError: false }
}

beforeEach(() => {
  vi.spyOn(Date, 'now').mockReturnValue(Date.UTC(2026, 7, 7, 18))
  dobles.consulta = consultaCon(configuracion())
  dobles.cierreEstado = cierreEstadoCon(null)
  dobles.cierreHabilitada = undefined
  dobles.yo = { id: '30000000-0000-4000-8000-000000000001', demo: false }
  dobles.publicar.mockReset().mockResolvedValue({})
  dobles.recargar.mockReset().mockResolvedValue(undefined)
  dobles.obtenerAnterior.mockReset().mockResolvedValue(configuracion({
    periodo: '2026-07-01',
    revision: 2,
    vendedores: [{
      vendedor_id: ID_VENDEDOR,
      nombre: 'ANA VENDEDORA',
      supervisor_id: ID_SUPERVISOR,
      supervisor_nombre: 'SUPERVISOR UNO',
      conversion_objetivo: 22,
      detalles: detalles(9_000),
    }],
  }))
})

describe('ConfigMetas', () => {
  it('representa carga, error seguro con reintento y roster vacío', async () => {
    dobles.consulta = consultaCon(undefined, { isPending: true })
    const carga = render(<ConfigMetas />)
    expect(screen.getByRole('status')).toHaveTextContent('Cargando las metas del período')
    carga.unmount()

    const refetch = vi.fn()
    dobles.consulta = consultaCon(undefined, {
      isError: true,
      error: new Error('detalle SQL privado'),
      refetch,
    })
    const error = render(<ConfigMetas />)
    expect(screen.getByText('No se pudieron cargar las metas.')).toBeInTheDocument()
    expect(screen.queryByText(/detalle SQL privado/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetch).toHaveBeenCalledOnce()
    error.unmount()

    dobles.consulta = consultaCon(configuracion({ vendedores: [], revision: 0, publicada_en: null }))
    render(<ConfigMetas />)
    expect(await screen.findByText('No hay vendedores activos en el roster de este período.')).toBeInTheDocument()
    expect(screen.getByText('Sin publicar')).toBeInTheDocument()
  })

  it('impone solo lectura desde el contrato del servidor', async () => {
    dobles.consulta = consultaCon(configuracion({ puede_editar: false }))
    render(<ConfigMetas />)

    expect(await screen.findByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    // `readOnly`, no `disabled`: al rol que solo audita hay que dejarle LEER el
    // importe con contraste y poder enfocarlo, no atenuarlo como si fuera
    // adorno. Lo que no puede es cambiarlo.
    const campo = screen.getByLabelText('Meta mensual total de ANA VENDEDORA')
    expect(campo).toHaveAttribute('readonly')
    expect(campo).toHaveAttribute('aria-readonly', 'true')
    fireEvent.change(campo, { target: { value: '999999' } })
    expect(dobles.publicar).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', { name: 'Publicar revisión' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Copiar mes anterior' })).not.toBeInTheDocument()
  })

  it('publica una sola meta total y normaliza las dimensiones internas', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    fireEvent.change(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '500000' },
    })

    expect(screen.getByRole('status')).toHaveTextContent('Hay cambios sin publicar')
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    expect(dobles.publicar).toHaveBeenCalledWith({
      periodo: '2026-08-01',
      expectedRevision: 4,
      metas: {
        [ID_VENDEDOR]: {
          // La conversión pactada VIAJA: hasta 2026-08-10 el editor la pisaba a
          // 0 en cada publicación, así que la meta de conversión era imposible
          // de fijar y los paneles decían «meta por definir» para siempre.
          conversion_objetivo: 15,
          detalles: [
            { categoria: 'nuevo', moneda: 'PEN', capital_objetivo: 500_000, contratos_objetivo: 0 },
            { categoria: 'nuevo', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'renovacion', moneda: 'PEN', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'renovacion', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'upgrade', moneda: 'PEN', capital_objetivo: 0, contratos_objetivo: 0 },
            { categoria: 'upgrade', moneda: 'USD', capital_objetivo: 0, contratos_objetivo: 0 },
          ],
        },
      },
    })
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Metas de agosto de 2026 publicadas.')
  })

  it('rechaza valores fuera del contrato antes de mutar', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    fireEvent.change(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '100000001' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    expect(dobles.toastError).toHaveBeenCalledWith(
      'La meta mensual de ANA VENDEDORA debe estar entre S/ 0 y S/ 100,000,000.',
    )
    expect(dobles.publicar).not.toHaveBeenCalled()
  })

  // ESTADO DE PRODUCCIÓN (2026-08-10): 16 analistas con supervisor y una
  // analista sin él. Ese único caso bloqueaba la publicación del mes ENTERO —
  // el editor ofrecía 16 metas y el servidor exigía 17 — y la pantalla no decía
  // nada. Aquí se fija lo contrario: se avisa de quién queda fuera Y se publica
  // igual el resto.
  it('señala a quien queda fuera de las metas sin bloquear la publicación', async () => {
    const user = userEvent.setup()
    dobles.consulta = consultaCon(configuracion({
      revision: 0,
      publicada_en: null,
      publicada_por: null,
      publicada_por_nombre: null,
      sin_supervisor: [
        {
          vendedor_id: '40000000-0000-4000-8000-000000000001',
          nombre: 'IVETT SIN JEFE',
          motivo: 'sin_supervisor',
        },
        {
          vendedor_id: '40000000-0000-4000-8000-000000000002',
          nombre: 'RUTH CON JEFE DE BAJA',
          motivo: 'supervisor_inactivo',
        },
      ],
    }))
    render(<ConfigMetas />)

    // Encabezado real, no un <p> en negrita: es el único bloque de la pantalla
    // que un lector de pantalla no encontraría navegando por encabezados.
    expect(await screen.findByRole('heading', { name: '2 analistas sin meta este mes' }))
      .toBeInTheDocument()
    // Cada motivo es un arreglo distinto y la pantalla no puede confundirlos.
    expect(screen.getByText(/IVETT SIN JEFE/)).toBeInTheDocument()
    expect(screen.getByText(/no tiene supervisor asignado/)).toBeInTheDocument()
    expect(screen.getByText(/RUTH CON JEFE DE BAJA/)).toBeInTheDocument()
    expect(screen.getByText(/su supervisor está dado de baja/)).toBeInTheDocument()
    // La consecuencia real, no solo el síntoma.
    expect(screen.getByText(/su producción no se atribuye/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Revisar jerarquía/ }))
      .toHaveAttribute('href', '#/config-usuarios')

    fireEvent.change(screen.getByLabelText('Meta mensual total de ANA VENDEDORA'), {
      target: { value: '80000' },
    })
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    const enviado = dobles.publicar.mock.calls[0]?.[0] as { metas: Record<string, unknown> }
    // Solo el roster: quien no tiene supervisor no cabe en crm.metas_vendedor.
    expect(Object.keys(enviado.metas)).toEqual([ID_VENDEDOR])
  })

  it('no menciona a nadie cuando el roster está completo', async () => {
    render(<ConfigMetas />)
    expect(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA')).toBeInTheDocument()
    expect(screen.queryByText(/sin meta este mes/)).not.toBeInTheDocument()
  })

  // Reporte de Miguel (2026-08-10): «no hay ni , ni . es dificil pues saber si
  // es 50 mil o 500 mil ademas de que hay un 0 que no se borra». Las dos cosas
  // salían del mismo sitio: un `type="number"` con `value` numérico.
  it('separa los miles mientras se escribe la meta', async () => {
    render(<ConfigMetas />)
    const campo = await screen.findByLabelText('Meta mensual total de ANA VENDEDORA')

    fireEvent.change(campo, { target: { value: '50000' } })
    expect(campo).toHaveValue('50,000')

    fireEvent.change(campo, { target: { value: '500000' } })
    expect(campo).toHaveValue('500,000')

    fireEvent.change(campo, { target: { value: '1500000' } })
    expect(campo).toHaveValue('1,500,000')
    // Y sigue siendo un NÚMERO por dentro: el subtotal del supervisor y el
    // total del equipo suman, no concatenan texto.
    expect(screen.getAllByText('S/ 1,500,000').length).toBeGreaterThanOrEqual(1)
  })

  // La pantalla mostraba una tarjeta por analista, con cabecera y dos textos
  // repetidos idénticos; con 17 analistas el mes no cabía en varias pantallas.
  it('agrupa a los analistas por supervisor con el subtotal de cada equipo', async () => {
    dobles.consulta = consultaCon(configuracion({
      vendedores: [
        {
          vendedor_id: ID_VENDEDOR,
          nombre: 'ANA VENDEDORA',
          supervisor_id: ID_SUPERVISOR,
          supervisor_nombre: 'SUPERVISOR UNO',
          conversion_objetivo: 0,
          detalles: detalles(10_000),
        },
        {
          vendedor_id: '10000000-0000-4000-8000-000000000002',
          nombre: 'BEA VENDEDORA',
          supervisor_id: ID_SUPERVISOR,
          supervisor_nombre: 'SUPERVISOR UNO',
          conversion_objetivo: 0,
          detalles: detalles(5_000),
        },
        {
          vendedor_id: '10000000-0000-4000-8000-000000000003',
          nombre: 'CARLA VENDEDORA',
          supervisor_id: '20000000-0000-4000-8000-000000000002',
          supervisor_nombre: 'SUPERVISOR DOS',
          conversion_objetivo: 0,
          detalles: detalles(7_000),
        },
      ],
    }))
    render(<ConfigMetas />)

    // Un encabezado por equipo, no uno por analista.
    expect(await screen.findByRole('heading', { name: 'SUPERVISOR UNO' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'SUPERVISOR DOS' })).toBeInTheDocument()

    // detalles(n) pone n en nuevo/PEN y deja 3.000 y 5.000 en las otras dos
    // dimensiones PEN, que `metaTotal` también suma: cada analista aporta
    // n + 8.000.
    expect(screen.getByText('S/ 31,000')).toBeInTheDocument() // 18.000 + 13.000
    expect(screen.getByText('S/ 15,000')).toBeInTheDocument() // 7.000 + 8.000

    // Y los campos siguen siendo uno por analista.
    expect(screen.getByLabelText('Meta mensual total de ANA VENDEDORA')).toBeInTheDocument()
    expect(screen.getByLabelText('Meta mensual total de CARLA VENDEDORA')).toBeInTheDocument()
  })

  it('deja borrar el campo sin que reaparezca un 0', async () => {
    render(<ConfigMetas />)
    const campo = await screen.findByLabelText('Meta mensual total de ANA VENDEDORA')

    fireEvent.change(campo, { target: { value: '80000' } })
    expect(campo).toHaveValue('80,000')

    fireEvent.change(campo, { target: { value: '' } })
    expect(campo).toHaveValue('')
    // El 0 imborrable venía de repintar Number('') tras cada borrado.
    expect(campo).not.toHaveValue('0')
  })

  // La RPC ordena por NOMBRE de supervisor, así que dos homónimos salen
  // adyacentes: agrupar por nombre los fundía en un equipo con el subtotal
  // equivocado, y en silencio. Se agrupa por `supervisor_id`.
  it('no funde a dos supervisores distintos que se llaman igual', async () => {
    dobles.consulta = consultaCon(configuracion({
      vendedores: [
        {
          vendedor_id: ID_VENDEDOR,
          nombre: 'ANA VENDEDORA',
          supervisor_id: '20000000-0000-4000-8000-00000000000a',
          supervisor_nombre: 'JORGE PEREZ',
          conversion_objetivo: 0,
          detalles: detalles(2_000),
        },
        {
          vendedor_id: '10000000-0000-4000-8000-000000000002',
          nombre: 'BEA VENDEDORA',
          supervisor_id: '20000000-0000-4000-8000-00000000000b',
          supervisor_nombre: 'JORGE PEREZ',
          conversion_objetivo: 0,
          detalles: detalles(4_000),
        },
      ],
    }))
    render(<ConfigMetas />)

    // Dos equipos, no uno: mismo nombre, personas distintas.
    expect(await screen.findAllByRole('heading', { name: 'JORGE PEREZ' })).toHaveLength(2)
    // Y cada subtotal es el suyo (n + 8.000), no la suma de los dos.
    expect(screen.getByText('S/ 10,000')).toBeInTheDocument()
    expect(screen.getByText('S/ 12,000')).toBeInTheDocument()
    // 22.000 aparece UNA vez y es el total de la empresa, no un subtotal
    // fundido: si los dos equipos se hubieran juntado, saldría dos veces.
    expect(screen.getAllByText('S/ 22,000')).toHaveLength(1)
  })

  // La conversión se pacta para la EMPRESA (decisión de Miguel, 2026-08-10):
  // un solo número aquí, y el detalle por analista en la pantalla de
  // Conversiones. El modelo la guarda por vendedor, así que el valor único se
  // replica en todos.
  it('pacta una sola conversión de empresa y la replica a cada analista', async () => {
    const user = userEvent.setup()
    dobles.consulta = consultaCon(configuracion({
      vendedores: [
        {
          vendedor_id: ID_VENDEDOR,
          nombre: 'ANA VENDEDORA',
          supervisor_id: ID_SUPERVISOR,
          supervisor_nombre: 'SUPERVISOR UNO',
          conversion_objetivo: 0,
          detalles: detalles(),
        },
        {
          vendedor_id: '10000000-0000-4000-8000-000000000002',
          nombre: 'BEA VENDEDORA',
          supervisor_id: ID_SUPERVISOR,
          supervisor_nombre: 'SUPERVISOR UNO',
          conversion_objetivo: 0,
          detalles: detalles(),
        },
      ],
    }))
    render(<ConfigMetas />)

    const campo = await screen.findByLabelText(/Meta de conversión de la empresa/)
    fireEvent.change(campo, { target: { value: '35' } })
    expect(campo).toHaveValue('35')

    // Cambiar SOLO la conversión ya deja el mes por publicar: antes la huella
    // de cambios ignoraba este campo y el botón se quedaba deshabilitado.
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))

    await waitFor(() => expect(dobles.publicar).toHaveBeenCalledOnce())
    const enviado = dobles.publicar.mock.calls[0]?.[0] as {
      metas: Record<string, { conversion_objetivo: number }>
    }
    expect(Object.values(enviado.metas).map((meta) => meta.conversion_objetivo))
      .toEqual([35, 35])
  })

  // Un `Math.min(100, …)` mudo cambiaba la intención por el máximo y dejaba
  // muerta la validación. Peor: al reutilizar el parser de importes, «12.5» se
  // convertía en «100» y «1.5» en «15» — error de un orden de magnitud.
  it('respeta los decimales de la conversión y avisa en vez de recortar', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)
    const campo = await screen.findByLabelText(/Meta de conversión de la empresa/)

    fireEvent.change(campo, { target: { value: '12.5' } })
    expect(campo).toHaveValue('12.5')

    fireEvent.change(campo, { target: { value: '350' } })
    expect(campo).toHaveValue('350')
    await user.click(screen.getByRole('button', { name: 'Publicar revisión' }))
    expect(dobles.toastError).toHaveBeenCalledWith('La meta de conversión debe estar entre 0 % y 100 %.')
    expect(dobles.publicar).not.toHaveBeenCalled()
  })

  it('copia el mes anterior sin publicarlo automáticamente', async () => {
    const user = userEvent.setup()
    render(<ConfigMetas />)

    await user.click(screen.getByRole('button', { name: 'Copiar mes anterior' }))

    await waitFor(() => expect(dobles.obtenerAnterior).toHaveBeenCalledWith(
      '2026-07-01',
    ))
    // Con separadores: lo copiado se lee igual que lo tecleado.
    expect(await screen.findByLabelText('Meta mensual total de ANA VENDEDORA'))
      .toHaveValue('17,000')
    expect(dobles.publicar).not.toHaveBeenCalled()
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Se copiaron las metas de julio de 2026.')
  })

  it('un mes sellado se marca cerrado y no deja publicar ni copiar', async () => {
    // El propio agosto quedó sellado (cierre tardío, el candado es suelo).
    dobles.cierreEstado = cierreEstadoCon({
      mes: '2026-08',
      mes_nombre: 'agosto',
      cerrado_en: '2026-09-10T14:25:00.000Z',
      automatico: true,
    })
    render(<ConfigMetas />)

    expect(await screen.findByText('agosto de 2026 ya está cerrado')).toBeInTheDocument()
    expect(screen.getByText(/por el ciclo automático/)).toBeInTheDocument()
    expect(screen.getByText(/se descuenta en el mes vivo/)).toBeInTheDocument()
    // «Copiar» no depende de `dirty`: si está deshabilitado, es por el sello.
    expect(screen.getByRole('button', { name: 'Copiar mes anterior' })).toBeDisabled()
    // Con el borrador SUCIO: si «Publicar» sigue apagado, lo apagó el sello,
    // no el `!dirty` — sin esto, quitar `mesCerrado` del botón pasaba en verde.
    fireEvent.change(screen.getByLabelText(/Meta de conversión de la empresa/), {
      target: { value: '33' },
    })
    expect(screen.getByRole('button', { name: 'Publicar revisión' })).toBeDisabled()
  })

  it('un mes ANTERIOR al último sellado también queda cerrado, sin fecha propia', async () => {
    // Mirando agosto con septiembre ya sellado: cerrado por arrastre — la fecha
    // del banner es del ÚLTIMO sello, no la suya, así que no se inventa.
    dobles.cierreEstado = cierreEstadoCon({
      mes: '2026-09',
      mes_nombre: 'septiembre',
      cerrado_en: '2026-10-10T14:25:00.000Z',
      automatico: true,
    })
    render(<ConfigMetas />)

    expect(await screen.findByText('agosto de 2026 ya está cerrado')).toBeInTheDocument()
    expect(screen.queryByText(/Se cerró el/)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Copiar mes anterior' })).toBeDisabled()
  })

  it('en DEMO la consulta del estado se apaga: el demo es hermético', () => {
    // Hallazgo de la auditoría F2: era la única consulta de la pantalla que
    // salía a la red en demo (fallaba en silencio y ensuciaba registrarError).
    dobles.yo = { id: '30000000-0000-4000-8000-000000000001', demo: true }
    render(<ConfigMetas />)

    expect(dobles.cierreHabilitada).toBe(false)
    expect(screen.queryByText(/ya está cerrado/)).not.toBeInTheDocument()
  })

  it('en sesión real la consulta del estado va encendida', () => {
    render(<ConfigMetas />)
    expect(dobles.cierreHabilitada).toBe(true)
  })

  it('si el estado del cierre no responde, el editor NO se cierra solo (fail-open)', async () => {
    // La consulta es advisory: sin ella no hay banner y los botones siguen —
    // el candado real es el trigger del servidor, que rechaza con su mensaje.
    dobles.cierreEstado = { data: undefined, isError: true }
    render(<ConfigMetas />)

    expect(await screen.findByRole('button', { name: 'Copiar mes anterior' })).toBeEnabled()
    expect(screen.queryByText(/ya está cerrado/)).not.toBeInTheDocument()
  })
})
