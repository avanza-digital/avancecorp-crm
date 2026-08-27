import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Lead, Miembro } from '@/lib/tipos'
import type { ReporteDerivacionesEquipo } from '@/lib/reporte-derivaciones-equipo'

const SUPERVISOR = '00000000-0000-4000-8000-000000000010'
const ANA = '00000000-0000-4000-8000-000000000011'
const BRUNO = '00000000-0000-4000-8000-000000000012'
const LEAD_BANDEJA = '00000000-0000-4000-8000-000000000013'
const LEAD_HOY = '00000000-0000-4000-8000-000000000014'

const RECARGAR = vi.fn(async () => true)
const CONSULTAR_REPORTE = vi.fn()
const GUARDAR = vi.fn(async () => ({
  version: 1 as const,
  derivados: 1,
  lead_ids: [LEAD_BANDEJA],
}))
const DEVOLVER = vi.fn(async () => ({
  version: 1 as const,
  lead_id: LEAD_HOY,
  devuelto_a_bandeja: true as const,
}))

const ASESORES: Miembro[] = [
  {
    perfil_id: ANA,
    nombre_completo: 'Ana Paredes',
    rol_crm: 'vendedor',
    supervisor_id: SUPERVISOR,
    activo: true,
  },
  {
    perfil_id: BRUNO,
    nombre_completo: 'Bruno Ríos',
    rol_crm: 'vendedor',
    supervisor_id: SUPERVISOR,
    activo: true,
  },
]

const REPORTE: ReporteDerivacionesEquipo = {
  version: 1,
  generado_en: '2026-08-20T18:00:00+00:00',
  periodo: {
    desde: '2026-08-19',
    hasta: '2026-08-19',
    dias: 1,
    zona: 'America/Lima',
  },
  asesores: [
    {
      asesor_id: ANA,
      asesor_nombre: 'Ana Paredes',
      derivados: 2,
      capital_pen: 120000,
      capital_usd: 0,
      sin_primer_contacto: 1,
      contactados: 1,
      contactabilidad_pct: 50,
      repartido_hoy: 0,
    },
    {
      asesor_id: BRUNO,
      asesor_nombre: 'Bruno Ríos',
      derivados: 1,
      capital_pen: 80000,
      capital_usd: 0,
      sin_primer_contacto: 0,
      contactados: 1,
      contactabilidad_pct: 100,
      repartido_hoy: 0,
    },
  ],
  movimientos_hoy: [
    {
      lead_id: LEAD_HOY,
      asesor_id: ANA,
      asesor_nombre: 'Ana Paredes',
      nombre_completo: 'Lead guardado hoy',
      monto_estimado: 35000,
      moneda: 'PEN',
      derivado_en: '2026-08-20T17:30:00+00:00',
      reversible: true,
    },
  ],
}

const LEAD_EN_BANDEJA = {
  id: LEAD_BANDEJA,
  nombre_completo: 'Lead por repartir',
  origen: 'web',
  monto_estimado: 50000,
  moneda: 'PEN',
  creado_en: '2026-08-20T16:00:00+00:00',
  actualizado_en: '2026-08-20T16:00:00+00:00',
  etapa: 'nuevo',
  activo: true,
  vendedor_id: null,
  asignado_supervisor_id: SUPERVISOR,
} as Lead

let LEADS_AMBITO: Lead[] = [LEAD_EN_BANDEJA]

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({
    yo: {
      id: SUPERVISOR,
      nombre_completo: 'Supervisora Uno',
      rol: 'supervisor',
      demo: false,
      puede_contratar: false,
    },
  }),
}))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    ambito: { leads: LEADS_AMBITO, vendedores: ASESORES, esGlobal: false },
    recargar: RECARGAR,
  }),
}))
vi.mock('@/data/crm-queries', () => ({
  useReporteDerivacionesEquipo: (activo: boolean, desde: string, hasta: string) => {
    CONSULTAR_REPORTE(activo, desde, hasta)
    return {
      data: REPORTE,
      isPending: false,
      isFetching: false,
      error: null,
      refetch: vi.fn(),
    }
  },
  useDerivarLeadsEquipo: () => ({ isPending: false, mutateAsync: GUARDAR }),
  useRevertirDerivacionEquipo: () => ({ isPending: false, mutateAsync: DEVOLVER }),
}))
vi.mock('@/data/crm-api', () => ({
  mensajeDeError: (_error: unknown, fallback: string) => fallback,
}))
vi.mock('@/lib/ahora', () => ({
  useAhora: () => Date.parse('2026-08-20T12:00:00-05:00'),
}))
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/tipo-cambio')>()),
  useTipoCambio: () => ({ tc: null, recargar: vi.fn() }),
}))
vi.mock('@/components/common/animated-value', () => ({
  AnimatedValue: ({ value }: { value: string }) => <>{value}</>,
}))

const { Derivaciones } = await import('./derivaciones')

beforeEach(() => {
  LEADS_AMBITO = [LEAD_EN_BANDEJA]
  RECARGAR.mockClear()
  CONSULTAR_REPORTE.mockClear()
  GUARDAR.mockClear()
  DEVOLVER.mockClear()
})

describe('Derivaciones — módulo independiente de Supervisión', () => {
  it('actualiza Hoy como borrador y guarda el lote completo', async () => {
    render(<Derivaciones />)

    fireEvent.change(screen.getByRole('combobox', { name: /Derivar Lead por repartir/i }), {
      target: { value: ANA },
    })

    expect(screen.getByText('Hoy 1 · borrador')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Guardar 1 derivación' }))

    await waitFor(() => {
      expect(GUARDAR).toHaveBeenCalledWith([{ leadId: LEAD_BANDEJA, asesorId: ANA }])
    })
    expect(RECARGAR).toHaveBeenCalled()
  })

  it('permite cambiar o quitar el asesor antes de guardar', () => {
    render(<Derivaciones />)
    const selector = screen.getByRole('combobox', {
      name: /Derivar Lead por repartir/i,
    })
    const tarjetas = screen.getByRole('list', {
      name: 'Derivaciones por asesor de mi equipo',
    })

    fireEvent.change(selector, { target: { value: ANA } })
    let tarjetaAna = within(tarjetas).getByText('Ana Paredes').closest('li')
    if (!tarjetaAna) throw new Error('No se encontró la tarjeta de Ana')
    expect(within(tarjetaAna).getByText('Hoy 1 · borrador')).toBeInTheDocument()

    fireEvent.change(selector, { target: { value: BRUNO } })
    tarjetaAna = within(tarjetas).getByText('Ana Paredes').closest('li')
    const tarjetaBruno = within(tarjetas).getByText('Bruno Ríos').closest('li')
    if (!tarjetaAna || !tarjetaBruno) throw new Error('No se encontraron las tarjetas del equipo')
    expect(within(tarjetaAna).getByText('Hoy 0')).toBeInTheDocument()
    expect(within(tarjetaBruno).getByText('Hoy 1 · borrador')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Quitar' }))
    expect(screen.getByText('Aún no hay leads en el borrador')).toBeInTheDocument()
    expect(GUARDAR).not.toHaveBeenCalled()
  })

  it('pagina Derivar hoy y conserva el borrador al cambiar de página', () => {
    LEADS_AMBITO = Array.from({ length: 6 }, (_, indice) => ({
      ...LEAD_EN_BANDEJA,
      id: `lead-por-derivar-${indice + 1}`,
      nombre_completo: `Lead por derivar ${indice + 1}`,
    }))

    render(<Derivaciones />)

    const lista = screen.getByRole('list', { name: 'Leads por derivar hoy' })
    expect(within(lista).getAllByRole('listitem')).toHaveLength(5)
    expect(screen.getByText('Página 1 de 2 · 6 registros')).toBeInTheDocument()
    expect(within(lista).queryByText('Lead por derivar 6')).not.toBeInTheDocument()

    fireEvent.change(
      within(lista).getByRole('combobox', { name: 'Derivar Lead por derivar 1 a un asesor' }),
      { target: { value: ANA } },
    )
    const paginacion = screen.getByRole('navigation', {
      name: 'Paginación de leads por derivar hoy',
    })
    fireEvent.click(within(paginacion).getByRole('button', { name: 'Siguiente' }))

    expect(within(lista).getAllByRole('listitem')).toHaveLength(1)
    expect(within(lista).getByText('Lead por derivar 6')).toBeInTheDocument()
    expect(screen.getByText('1 lead listo para derivar')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Anterior' }))
    expect(
      within(lista).getByRole('combobox', { name: 'Derivar Lead por derivar 1 a un asesor' }),
    ).toHaveValue(ANA)
  })

  it('envía al reporte el rango elegido y todas las tarjetas comparten el filtro', async () => {
    render(<Derivaciones />)

    expect(CONSULTAR_REPORTE).toHaveBeenCalledWith(true, '2026-08-19', '2026-08-19')

    fireEvent.click(screen.getByRole('button', { name: 'Últimos 7 días' }))
    await waitFor(() => {
      expect(CONSULTAR_REPORTE).toHaveBeenCalledWith(true, '2026-08-13', '2026-08-19')
    })

    fireEvent.click(screen.getByRole('button', { name: 'Rango' }))
    fireEvent.change(
      screen.getByLabelText('Fecha inicial del reporte de derivaciones'),
      { target: { value: '2026-08-01' } },
    )
    fireEvent.change(
      screen.getByLabelText('Fecha final del reporte de derivaciones'),
      { target: { value: '2026-08-10' } },
    )

    await waitFor(() => {
      expect(CONSULTAR_REPORTE).toHaveBeenCalledWith(true, '2026-08-01', '2026-08-10')
    })
  })

  it('permite devolver una derivación guardada mientras siga reversible', async () => {
    render(<Derivaciones />)

    fireEvent.click(screen.getByRole('button', { name: 'Devolver' }))

    await waitFor(() => expect(DEVOLVER).toHaveBeenCalledWith(LEAD_HOY))
    expect(RECARGAR).toHaveBeenCalled()
  })

  it('pagina Guardadas hoy sin alargar la pantalla ni crear otro scroll', async () => {
    const movimientosOriginales = REPORTE.movimientos_hoy
    const movimientoBase = movimientosOriginales[0]
    if (!movimientoBase) throw new Error('Falta el movimiento base de la prueba')
    REPORTE.movimientos_hoy = Array.from({ length: 6 }, (_, indice) => ({
      ...movimientoBase,
      lead_id: `lead-guardado-${indice + 1}`,
      nombre_completo: `Lead guardado ${indice + 1}`,
      derivado_en: `2026-08-20T17:${30 + indice}:00+00:00`,
    }))

    try {
      render(<Derivaciones />)

      const lista = screen.getByRole('list', { name: 'Derivaciones guardadas hoy' })
      expect(within(lista).getAllByRole('listitem')).toHaveLength(5)
      expect(screen.getByText('Página 1 de 2 · 6 registros')).toBeInTheDocument()
      expect(within(lista).queryByText('Lead guardado 6')).not.toBeInTheDocument()

      fireEvent.click(screen.getByRole('button', { name: 'Siguiente' }))

      expect(screen.getByText('Página 2 de 2 · 6 registros')).toBeInTheDocument()
      expect(within(lista).getAllByRole('listitem')).toHaveLength(1)
      expect(within(lista).getByText('Lead guardado 6')).toBeInTheDocument()
      fireEvent.click(within(lista).getByRole('button', { name: 'Devolver' }))
      await waitFor(() => expect(DEVOLVER).toHaveBeenCalledWith('lead-guardado-6'))
    } finally {
      REPORTE.movimientos_hoy = movimientosOriginales
    }
  })
})
