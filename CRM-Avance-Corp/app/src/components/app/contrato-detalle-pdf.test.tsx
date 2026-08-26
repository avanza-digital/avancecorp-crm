import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Dialog } from '@/components/ui/dialog'
import type { ContratoRow } from '@/lib/clientes-tipos'
import type { ContratoPdfDatos } from '@/lib/contrato-pdf'

const toast = vi.hoisted(() => ({ error: vi.fn() }))
const archivoPdf = vi.hoisted(() => ({
  abrir: vi.fn(),
  archivar: vi.fn(),
  archivarDemo: vi.fn(),
  consultar: vi.fn(),
  obtener: vi.fn(),
  descargar: vi.fn(),
  ver: vi.fn(),
}))
const consultas = vi.hoisted(() => ({
  contrato: null as ContratoRow | null,
}))

vi.mock('sonner', () => ({ toast }))
vi.mock('@/lib/contrato-pdf-archivo', () => ({
  abrirVentanaContratoPdf: archivoPdf.abrir,
  archivarContratoPdfConfirmado: archivoPdf.archivar,
  consultarEstadoContratoPdf: archivoPdf.consultar,
  ContratoPdfNoSelladoError: class ContratoPdfNoSelladoError extends Error {},
  etiquetaEstadoContratoPdf: (estado: string) => estado,
  obtenerContratoPdfArchivado: archivoPdf.obtener,
  descargarArchivoContratoPdf: archivoPdf.descargar,
  verArchivoContratoPdf: archivoPdf.ver,
}))
vi.mock('@/lib/contrato-pdf-demo-loader', () => ({
  archivarContratoPdfDemoHabilitado: archivoPdf.archivarDemo,
}))

vi.mock('@/data/crm-queries', () => {
  const q = (data: unknown) => ({
    data,
    isError: false,
    isSuccess: true,
    error: null,
    refetch: vi.fn(),
  })
  return {
    useContrato: () => q(consultas.contrato),
    useCronograma: () => q([]),
    useTitulares: () => q([]),
  }
})

const contrato: ContratoRow = {
  id: 'dc-ct-a',
  numero_contrato: '2026-01-000901',
  cliente_id: 'dc-cli-1',
  cliente_nombre: 'ROSA MERCEDES AGUILAR VENTURA',
  capital: 30_000,
  moneda: 'PEN',
  tasa_anual: 12,
  modalidad: 'mensual',
  tipo_interes: 'simple',
  categoria: 'nuevo',
  estado: 'activo',
  fecha_inicio: '2026-01-15',
  fecha_vencimiento: '2027-01-15',
  notas_internas: null,
  creado_por: 'd-v1',
  creado_en: '2026-01-15T12:00:00.000Z',
  revision_contrato: '2026-08-25T15:00:00.000Z',
  producto_condicion_id: 'cond-1',
  producto_id: 'prod-1',
  producto_codigo: 'DEMO-RENTA-PEN',
  producto_version_id: 'version-1',
  producto_version: 1,
  producto_nombre: 'Renta Demo Soles',
  producto_version_estado: 'publicada',
}

const pdfDatos: ContratoPdfDatos = {
  contrato: {
    numero: contrato.numero_contrato,
    capital: contrato.capital,
    moneda: contrato.moneda,
    porcentaje: contrato.tasa_anual,
    fechaInicio: contrato.fecha_inicio,
    fechaVencimiento: contrato.fecha_vencimiento,
  },
  titular: {
    nombreCompleto: 'ROSA MERCEDES AGUILAR VENTURA',
    tipoDocumento: 'DNI',
    documento: '46801357',
    domicilio: 'Av. Demo 123, San Isidro, Lima',
    correo: 'rosa.aguilar@correo.pe',
  },
  analista: {
    nombreCompleto: 'VENDEDOR UNO',
    documento: '10000001',
    celular: '+51 987 654 321',
    correo: 'vendedor.uno@avancecorp.pe',
  },
}

const archivo = {
  contratoId: contrato.id,
  storagePath: `${contrato.id}/contrato.pdf`,
  nombreArchivo: 'Contrato-2026-01-000901-ROSA.pdf',
  sha256: 'a'.repeat(64),
  bytes: 16,
  blob: new Blob(['%PDF-1.7\ndemo'], { type: 'application/pdf' }),
}

const { ContratoDetalle } = await import('./contrato-detalle')

function diferida<T>() {
  let resolver!: (valor: T) => void
  let rechazar!: (error: unknown) => void
  const promesa = new Promise<T>((resolve, reject) => {
    resolver = resolve
    rechazar = reject
  })
  return { promesa, resolver, rechazar }
}

describe('ContratoDetalle — PDF archivado', () => {
  beforeEach(() => {
    consultas.contrato = null
    toast.error.mockReset()
    archivoPdf.archivar.mockReset().mockResolvedValue(archivo)
    archivoPdf.archivarDemo.mockReset().mockResolvedValue(archivo)
    archivoPdf.consultar.mockReset().mockResolvedValue({ estado: 'sellado' })
    archivoPdf.obtener.mockReset().mockResolvedValue(archivo)
    archivoPdf.descargar.mockReset()
    archivoPdf.ver.mockReset()
    archivoPdf.abrir.mockReset().mockReturnValue({ close: vi.fn() })
  })

  it('en demo archiva una vez y descarga el objeto inmutable, no regenera directo', async () => {
    const user = userEvent.setup()
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle
          contratoId={contrato.id}
          datos={{ contrato, cuotas: [], titulares: [], pdfDatos }}
          onCerrar={() => undefined}
        />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Descargar contrato PDF' }))

    expect(archivoPdf.archivarDemo).toHaveBeenCalledWith(contrato.id, pdfDatos)
    expect(archivoPdf.descargar).toHaveBeenCalledWith(archivo)
    expect(archivoPdf.obtener).not.toHaveBeenCalled()
  })

  it('en real recupera el archivo privado por Edge y nunca usa el generador demo', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Ver contrato PDF' }))

    expect(archivoPdf.obtener).toHaveBeenCalledWith(contrato.id)
    expect(archivoPdf.abrir).toHaveBeenCalledOnce()
    expect(archivoPdf.ver).toHaveBeenCalledWith(archivo, expect.anything())
    expect(archivoPdf.archivar).not.toHaveBeenCalled()
    expect(archivoPdf.archivarDemo).not.toHaveBeenCalled()
  })

  it('muestra en Mi cartera el estado durable devuelto por el servidor', async () => {
    consultas.contrato = contrato
    archivoPdf.consultar.mockResolvedValue({ estado: 'error_reintentable' })
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    expect(await screen.findByText(/Estado del documento:/)).toHaveTextContent('error_reintentable')
    expect(screen.getByText('Vigente')).toBeInTheDocument()
    expect(screen.getByText('Nueva inversión')).toBeInTheDocument()
    expect(archivoPdf.consultar).toHaveBeenCalledWith(contrato.id)
  })

  it('descarta la respuesta diferida de A después de cambiar el mismo diálogo a B', async () => {
    const contratoB = {
      ...contrato,
      id: 'dc-ct-b',
      numero_contrato: '2026-01-000902',
    }
    const estadoA = diferida<{ estado: string }>()
    const estadoB = diferida<{ estado: string }>()
    archivoPdf.consultar.mockImplementation((contratoId: string) =>
      contratoId === contrato.id ? estadoA.promesa : estadoB.promesa,
    )
    consultas.contrato = contrato
    const vista = (contratoId: string) => (
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contratoId} onCerrar={() => undefined} />
      </Dialog>
    )
    const { rerender } = render(vista(contrato.id))

    consultas.contrato = contratoB
    rerender(vista(contratoB.id))
    expect(screen.getByText('Consultando el estado del documento…')).toBeInTheDocument()

    await act(async () => {
      estadoB.resolver({ estado: 'sellado' })
      await estadoB.promesa
    })
    expect(screen.getByText(/Estado del documento:/)).toHaveTextContent('sellado')

    await act(async () => {
      estadoA.resolver({ estado: 'integridad_bloqueada' })
      await estadoA.promesa
    })
    expect(screen.getByText(/Estado del documento:/)).toHaveTextContent('sellado')
    expect(screen.queryByText(/integridad_bloqueada/)).not.toBeInTheDocument()
  })

  it('un status diferido no degrada a pendiente el sellado confirmado por ensure', async () => {
    const user = userEvent.setup()
    const status = diferida<{ estado: string }>()
    consultas.contrato = contrato
    archivoPdf.consultar.mockReturnValue(status.promesa)
    archivoPdf.obtener.mockResolvedValue(null)
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Descargar contrato PDF' }))
    await waitFor(() => expect(archivoPdf.descargar).toHaveBeenCalledWith(archivo))
    expect(screen.getByText(/Estado del documento:/)).toHaveTextContent('sellado')

    await act(async () => {
      status.resolver({ estado: 'pendiente' })
      await status.promesa
    })
    expect(screen.getByText(/Estado del documento:/)).toHaveTextContent('sellado')
  })

  it('si el alta quedó pendiente, pide al servidor asegurar el mismo job sin crear otro contrato', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    archivoPdf.obtener.mockResolvedValue(null)
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Descargar contrato PDF' }))

    expect(archivoPdf.archivar).toHaveBeenCalledWith(contrato.id)
    expect(archivoPdf.descargar).toHaveBeenCalledWith(archivo)
  })

  it('si la recuperación falla, informa y deja el botón disponible para reintentar', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    archivoPdf.obtener.mockResolvedValue(null)
    archivoPdf.archivar.mockRejectedValue(new Error('No se pudo archivar el PDF confirmado.'))
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined)
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    const boton = screen.getByRole('button', { name: 'Descargar contrato PDF' })
    await user.click(boton)

    expect(toast.error).toHaveBeenCalledWith('No pudimos descargar el documento del contrato. Intenta nuevamente.')
    expect(boton).toBeEnabled()
    consoleError.mockRestore()
  })

  it('si el navegador bloquea la pestaña, avisa antes de llamar a la Edge', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    archivoPdf.abrir.mockImplementation(() => {
      throw new Error('El navegador bloqueó la ventana del contrato PDF.')
    })
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Ver contrato PDF' }))

    expect(toast.error).toHaveBeenCalledWith('No pudimos abrir el documento del contrato. Intenta nuevamente.')
    expect(archivoPdf.obtener).not.toHaveBeenCalled()
  })
})
