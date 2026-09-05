// La sección «En cooperativas» de Mi cartera y el bloque «Por empresa» de los
// reportes. Lo que estas pruebas defienden:
//   · la sección NO existe para quien no tiene cierres (la mayoría);
//   · los mini-totales salen del SERVIDOR, no de sumar filas truncadas;
//   · la degradación nunca es muda (error → aviso con Reintentar);
//   · en el desglose, Avance = capital del cumplimiento − coops, clampado.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { StoreDataContext } from '@/lib/store-context'
import type { CierreExternoDemo, StoreDataApi } from '@/lib/store'
import { periodoLima, type CumplimientoVendedor } from '@/lib/objetivos'

const { consultaCierres, anularMut } = vi.hoisted(() => ({
  consultaCierres: vi.fn(),
  anularMut: { mutateAsync: vi.fn() },
}))

vi.mock('@/data/crm-queries', () => ({
  useCierresExternos: consultaCierres,
  useAnularCierreExterno: () => anularMut,
}))

// El rol decide quién ve «Anular» en la revisión del mes.
const { rolActual } = vi.hoisted(() => ({ rolActual: { valor: 'gerencia' as string } }))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: { rol: rolActual.valor } }),
}))

const { SeccionEnCooperativas, DesglosePorEmpresa } = await import('./cierres-externos-seccion')

function q(data: unknown, error: Error | null = null) {
  return {
    data,
    isPending: false,
    isError: error != null,
    error,
    isFetching: false,
    refetch: vi.fn(),
  }
}

function montar(
  ui: React.ReactNode,
  cierresDemo: CierreExternoDemo[] = [],
  anularCierreExterno = vi.fn(() => ({ ok: true as const })),
  recargar = vi.fn().mockResolvedValue(true),
) {
  const api = {
    cierresExternos: cierresDemo,
    anularCierreExterno,
    recargar,
  } as unknown as StoreDataApi
  const utils = render(
    <StoreDataContext.Provider value={api}>{ui}</StoreDataContext.Provider>,
  )
  return { ...utils, recargar }
}

/**
 * El mes de HOY, del mismo reloj que usa el componente para filtrar las filas
 * demo (`periodoLima(Date.now())`). Con una fecha fija («2026-08-12») este
 * fichero estaba verde solo durante agosto de 2026: el 1 de septiembre el
 * cierre demo caía fuera del mes y los casos se ponían rojos por CALENDARIO,
 * no por una regresión del producto.
 */
const MES_ACTUAL = periodoLima(Date.now()).slice(0, 7)

/** Foto demo completa: el default sano al que cada caso le cambia lo suyo. */
function cierreDemo(extra: Partial<CierreExternoDemo> = {}): CierreExternoDemo {
  return {
    cierreId: 'demo-cx-l-9',
    leadId: 'l-9',
    cooperativa: 'prodelco',
    monto: 8000,
    moneda: 'PEN',
    nombre: 'Demo Prodelco',
    telefono: '999111222',
    numeroTransaccion: 'OP-DEMO-1',
    creadoEn: `${MES_ACTUAL}-12T00:00:00.000Z`,
    vendedorId: 'v-demo',
    vendedorNombre: 'Analista Demo',
    anuladoEn: null,
    motivoAnulacion: null,
    ...extra,
  }
}

const CIERRE_REAL = {
  cierre_id: 'c-1',
  lead_id: 'l-1',
  cooperativa: 'qorilazo' as const,
  monto: 10000,
  moneda: 'PEN' as const,
  nombre_completo: 'Cliente Qorilazo Uno',
  documento_tipo: 'DNI' as const,
  documento: '41000001',
  telefono: '+51941001101',
  numero_transaccion: 'OP-77-2026',
  referencia_externa: 'QOR-2026-001',
  vence_en: '2027-09-01',
  nota: 'primera inversion',
  vendedor_id: 'v-a',
  vendedor_nombre: 'Ana Analista',
  creado_en: '2026-08-12T00:00:00.000Z',
  anulado_en: null,
  motivo_anulacion: null,
}

const PAYLOAD_REAL = {
  version: 1 as const,
  periodo: '2026-08-01',
  alcance: 'propio' as const,
  cierres: [CIERRE_REAL],
  cierres_total: 3,
  cierres_mes: [CIERRE_REAL],
  cierres_mes_total: 1,
  // Distintos de la suma de filas A PROPÓSITO: prueban que los totales vienen
  // del servidor (la lista de arriba está truncada: 1 fila de 3).
  totales: [{ cooperativa: 'qorilazo' as const, moneda: 'PEN' as const, capital: 21500, cierres: 3 }],
  por_empresa: [
    { vendedor_id: 'v-a', vendedor_nombre: 'Ana Analista', cooperativa: 'qorilazo' as const, moneda: 'PEN' as const, capital: 3500, cierres: 2 },
  ],
}

describe('SeccionEnCooperativas', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    consultaCierres.mockReturnValue(q(undefined))
  })

  it('sin cierres NO existe: ni título ni caja vacía', () => {
    consultaCierres.mockReturnValue(q({ ...PAYLOAD_REAL, cierres: [], cierres_total: 0, totales: [] }))
    montar(<SeccionEnCooperativas demo={false} />)
    expect(screen.queryByText('En cooperativas')).not.toBeInTheDocument()
  })

  it('real: filas con chip + totales DEL SERVIDOR aunque la lista venga truncada', () => {
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<SeccionEnCooperativas demo={false} />)

    const seccion = screen.getByRole('region', { name: 'En cooperativas' })
    expect(within(seccion).getByText('Cliente Qorilazo Uno')).toBeInTheDocument()
    expect(within(seccion).getAllByText('QORILAZO').length).toBeGreaterThan(0)
    // El total es 21.500 (servidor), NO 10.000 (la única fila visible).
    expect(within(seccion).getByText(/21,500/)).toBeInTheDocument()
    // Y se dice que la lista está recortada.
    expect(within(seccion).getByText(/Mostrando los 1 más recientes de 3/)).toBeInTheDocument()
  })

  it('la mini-ficha abre con documento, referencia y la explicación sin-portal', async () => {
    const user = userEvent.setup()
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<SeccionEnCooperativas demo={false} />)

    // El nombre accesible lleva el nombre de la fila (hallazgo M1 a11y).
    await user.click(screen.getByRole('button', { name: 'Ver detalle — Cliente Qorilazo Uno' }))
    const ficha = await screen.findByRole('dialog')
    expect(within(ficha).getByText('DNI 41000001')).toBeInTheDocument()
    expect(within(ficha).getByText('QOR-2026-001')).toBeInTheDocument()
    expect(within(ficha).getByText(/no tiene cuenta en el portal/)).toBeInTheDocument()
  })

  it('si la carga real falla, avisa con Reintentar — nunca un hueco mudo', () => {
    consultaCierres.mockReturnValue(q(undefined, new Error('red caída')))
    montar(<SeccionEnCooperativas demo={false} />)
    expect(screen.getByText(/No se pudieron cargar los cierres/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
  })

  it('demo: deriva del store local y suma sus propios totales', () => {
    montar(<SeccionEnCooperativas demo />, [cierreDemo()])
    const seccion = screen.getByRole('region', { name: 'En cooperativas' })
    expect(within(seccion).getByText('Demo Prodelco')).toBeInTheDocument()
    expect(within(seccion).getAllByText('PRODELCO').length).toBeGreaterThan(0)
    expect(within(seccion).getAllByText(/8,000/).length).toBeGreaterThan(0)
  })

  it('un cierre ANULADO se sigue viendo, marcado, y SIGUE sumando al total', () => {
    // ATR-4: anular sanciona la conversión, no el dinero. La fila se ve,
    // marcada con su chip y su motivo, y su capital SE CONSERVA en el total.
    montar(<SeccionEnCooperativas demo />, [
      cierreDemo({ cierreId: 'demo-cx-vivo', leadId: 'l-vivo', nombre: 'Cierre Vivo', monto: 5000 }),
      cierreDemo({
        cierreId: 'demo-cx-anulado',
        leadId: 'l-anulado',
        nombre: 'Cierre Falso',
        monto: 9000,
        anuladoEn: `${MES_ACTUAL}-12T10:00:00.000Z`,
        motivoAnulacion: 'El depósito no existe',
      }),
    ])
    const seccion = screen.getByRole('region', { name: 'En cooperativas' })
    expect(within(seccion).getByText('Cierre Falso')).toBeInTheDocument()
    expect(within(seccion).getByText('ANULADO')).toBeInTheDocument()
    // El total es 14.000 (vivo + anulado): el capital del anulado SE CONSERVA
    // (ATR-4). Si volviera a excluirse, daría 5.000 y este assert lo cazaría.
    expect(within(seccion).getAllByText(/14,000/).length).toBeGreaterThan(0)
  })

  it('la mini-ficha muestra el N.° de operación y, si está anulado, su motivo', async () => {
    const user = userEvent.setup()
    montar(<SeccionEnCooperativas demo />, [
      cierreDemo({
        nombre: 'Cierre Falso',
        numeroTransaccion: 'OP-INVENTADA',
        anuladoEn: `${MES_ACTUAL}-12T10:00:00.000Z`,
        motivoAnulacion: 'El depósito no existe en el estado de cuenta',
      }),
    ])
    await user.click(screen.getByRole('button', { name: 'Ver detalle — Cierre Falso' }))
    const ficha = await screen.findByRole('dialog')
    expect(within(ficha).getByText('OP-INVENTADA')).toBeInTheDocument()
    expect(within(ficha).getByText(/El depósito no existe en el estado de cuenta/)).toBeInTheDocument()
    expect(within(ficha).getByText(/ya no cuenta en la conversión\. El capital se conserva/)).toBeInTheDocument()
  })
})

describe('DesglosePorEmpresa', () => {
  const CUMPLIMIENTO_A: CumplimientoVendedor = {
    vendedorId: 'v-a',
    nombre: 'Ana Analista',
    supervisorId: 's-1',
    supervisorNombre: 'Súper Uno',
    conversionObjetivo: 50,
    conversionReal: null,
    convertidos: 3,
    resueltos: 4,
    numerador: 3,
    detalles: [
      {
        categoria: 'nuevo',
        moneda: 'PEN',
        capitalObjetivo: 50000,
        contratosObjetivo: 5,
        capitalReal: 13500,
        capitalCumplimientoPct: 27,
        contratosReal: 3,
        contratosCumplimientoPct: 60,
      },
    ],
  }

  beforeEach(() => {
    vi.clearAllMocks()
    consultaCierres.mockReturnValue(q(undefined))
  })

  it('sin cierres en coops este mes el bloque entero se oculta', () => {
    consultaCierres.mockReturnValue(q({ ...PAYLOAD_REAL, por_empresa: [] }))
    montar(<DesglosePorEmpresa demo={false} porVendedor={{ 'v-a': CUMPLIMIENTO_A }} />)
    expect(screen.queryByText('Por empresa')).not.toBeInTheDocument()
  })

  it('Avance = capital del cumplimiento − coops, y cada coop con su chip', () => {
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<DesglosePorEmpresa demo={false} porVendedor={{ 'v-a': CUMPLIMIENTO_A }} />)

    expect(screen.getByText('Por empresa')).toBeInTheDocument()
    expect(screen.getByText('Ana Analista')).toBeInTheDocument()
    // 13.500 del cumplimiento − 3.500 en qorilazo = 10.000 de Avance.
    expect(screen.getByText(/10,000/)).toBeInTheDocument()
    expect(screen.getByText('QORILAZO')).toBeInTheDocument()
    expect(screen.getByText(/3,500/)).toBeInTheDocument()
    expect(screen.getByText('2 cierres')).toBeInTheDocument()
  })

  it('sin la foto del cumplimiento muestra Avance no disponible, nunca cero', () => {
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<DesglosePorEmpresa demo={false} porVendedor={null} />)
    expect(screen.getByRole('status')).toHaveTextContent('Capital de Avance no disponible')
    const avance = screen.getByText('Avance Corp').parentElement!
    expect(avance).toHaveTextContent('—')
    expect(avance).not.toHaveTextContent('S/')
    expect(screen.getByText('QORILAZO')).toBeInTheDocument()
    expect(screen.queryByText(/-3,500/)).not.toBeInTheDocument()
  })

  it('consulta cooperativas con el mismo mes recibido del reporte histórico', () => {
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<DesglosePorEmpresa demo={false} periodo="2026-08-01" porVendedor={{ 'v-a': CUMPLIMIENTO_A }} />)
    expect(consultaCierres).toHaveBeenLastCalledWith(true, '2026-08-01')
    expect(screen.getByText(/Mes de cierre: 2026-08/)).toBeInTheDocument()
  })

  it('una fila de cumplimiento ausente tampoco se convierte en capital cero', () => {
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
    montar(<DesglosePorEmpresa demo={false} porVendedor={{}} />)
    expect(screen.getByRole('status')).toHaveTextContent('falta su foto de cumplimiento')
    expect(screen.getByText('Avance Corp').parentElement).toHaveTextContent('—')
    expect(screen.getByText(/3,500/)).toBeInTheDocument()
  })

  it('demo respeta el mes Lima y conserva el capital de cooperativas anuladas', () => {
    montar(<DesglosePorEmpresa demo periodo="2026-08-01" porVendedor={null} />, [
      cierreDemo({ creadoEn: '2026-09-01T02:00:00Z', monto: 8000, anuladoEn: '2026-09-02T12:00:00Z' }),
      cierreDemo({ cierreId: 'otro-mes', creadoEn: '2026-09-01T05:00:00Z', monto: 7777 }),
    ])
    expect(screen.getByText(/8,000/)).toBeInTheDocument()
    expect(screen.queryByText(/7,777/)).not.toBeInTheDocument()
    expect(screen.getByText('1 cierre')).toBeInTheDocument()
  })
})

// La revisión existe porque la cooperativa no le manda nada al CRM: el número
// que escribe el analista vale lo que valga el control humano de atrás. Estas
// pruebas defienden que ese control tenga los datos a mano y que anular —que no
// se deshace— nunca sea un clic suelto.
describe('RevisionDelMes (dentro de «Por empresa»)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    rolActual.valor = 'gerencia'
    consultaCierres.mockReturnValue(q(PAYLOAD_REAL))
  })

  async function abrirRevision() {
    const user = userEvent.setup()
    montar(<DesglosePorEmpresa demo={false} porVendedor={null} />)
    await user.click(screen.getByRole('button', { name: 'Ver cierres del mes' }))
    return { user, dialogo: await screen.findByRole('dialog') }
  }

  it('lista los cierres del mes con su N.° de operación a la vista', async () => {
    const { dialogo } = await abrirRevision()
    expect(within(dialogo).getByText('Cliente Qorilazo Uno')).toBeInTheDocument()
    expect(within(dialogo).getByText('OP-77-2026')).toBeInTheDocument()
    // El nombre del analista comparte párrafo con la fecha del cierre.
    expect(within(dialogo).getByText(/Ana Analista/)).toBeInTheDocument()
  })

  it('un supervisor NO ve el botón de anular: la anulación es de gerencia', async () => {
    rolActual.valor = 'supervisor'
    const { dialogo } = await abrirRevision()
    expect(within(dialogo).getByText('Cliente Qorilazo Uno')).toBeInTheDocument()
    expect(
      within(dialogo).queryByRole('button', { name: /^Anular el cierre de/ }),
    ).not.toBeInTheDocument()
  })

  it('anular exige motivo y avisa de que no se deshace', async () => {
    const { user } = await abrirRevision()
    await user.click(
      screen.getByRole('button', { name: 'Anular el cierre de Cliente Qorilazo Uno' }),
    )
    expect(await screen.findByText(/No se puede deshacer/)).toBeInTheDocument()
    // Sin motivo no viaja nada.
    await user.click(screen.getByRole('button', { name: 'Anular cierre' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Escribe el motivo')
    expect(anularMut.mutateAsync).not.toHaveBeenCalled()
  })

  it('con motivo, anula mandando el cierre y su razón, y REFRESCA el cumplimiento', async () => {
    anularMut.mutateAsync.mockResolvedValueOnce({ cierreId: 'c-1' })
    const user = userEvent.setup()
    const { recargar } = montar(<DesglosePorEmpresa demo={false} porVendedor={null} />)
    await user.click(screen.getByRole('button', { name: 'Ver cierres del mes' }))
    await user.click(
      await screen.findByRole('button', { name: 'Anular el cierre de Cliente Qorilazo Uno' }),
    )
    await user.type(
      await screen.findByLabelText('Motivo de la anulación'),
      'El depósito no existe',
    )
    await user.click(screen.getByRole('button', { name: 'Anular cierre' }))
    expect(anularMut.mutateAsync).toHaveBeenCalledWith({
      cierreId: 'c-1',
      motivo: 'El depósito no existe',
    })
    // El cumplimiento de metas NO vive en TanStack: sin este refresco el
    // desglose restaba coops frescas de un cumplimiento viejo y pintaba el
    // dinero recién anulado como capital de Avance.
    expect(recargar).toHaveBeenCalled()
  })

  it('un cierre ya anulado no ofrece anular otra vez', async () => {
    consultaCierres.mockReturnValue(q({
      ...PAYLOAD_REAL,
      cierres_mes: [{
        ...CIERRE_REAL,
        anulado_en: '2026-08-12T10:00:00.000Z',
        motivo_anulacion: 'Cierre inventado',
      }],
    }))
    const { dialogo } = await abrirRevision()
    expect(within(dialogo).getByText('ANULADO')).toBeInTheDocument()
    expect(within(dialogo).getByText(/Anulado: Cierre inventado/)).toBeInTheDocument()
    expect(
      within(dialogo).queryByRole('button', { name: /^Anular el cierre de/ }),
    ).not.toBeInTheDocument()
  })

  it('demo: anula contra el store y jamás llama a la RPC', async () => {
    const anularDemo = vi.fn(() => ({ ok: true as const }))
    const user = userEvent.setup()
    montar(
      <DesglosePorEmpresa demo porVendedor={null} />,
      [cierreDemo({ cierreId: 'demo-cx-l-9' })],
      anularDemo,
    )
    await user.click(screen.getByRole('button', { name: 'Ver cierres del mes' }))
    await user.click(
      await screen.findByRole('button', { name: 'Anular el cierre de Demo Prodelco' }),
    )
    await user.type(await screen.findByLabelText('Motivo de la anulación'), 'prueba demo')
    await user.click(screen.getByRole('button', { name: 'Anular cierre' }))
    expect(anularDemo).toHaveBeenCalledWith('demo-cx-l-9', 'prueba demo')
    expect(anularMut.mutateAsync).not.toHaveBeenCalled()
  })
})
