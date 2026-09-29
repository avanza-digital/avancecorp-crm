import { beforeEach, describe, expect, it, vi } from 'vitest'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, render as renderBase, screen, waitFor } from '@testing-library/react'
import type { ReactElement, ReactNode } from 'react'
import userEvent from '@testing-library/user-event'
import { Dialog } from '@/components/ui/dialog'
import type { ContratoRow } from '@/lib/clientes-tipos'
import type { ContratoPdfDatos } from '@/lib/contrato-pdf'

const toast = vi.hoisted(() => ({ error: vi.fn() }))
const archivoPdf = vi.hoisted(() => ({
  abrir: vi.fn(),
  anexo: vi.fn(),
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
// `esContratoRegimenAnterior` y la fecha de la frontera se dejan REALES: son
// lógica pura y deciden si el detalle ofrece o no fabricar el documento.
vi.mock('@/lib/contrato-pdf-archivo', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/contrato-pdf-archivo')>()),
  abrirVentanaContratoPdf: archivoPdf.abrir,
  archivarContratoPdfConfirmado: archivoPdf.archivar,
  consultarEstadoContratoPdf: archivoPdf.consultar,
  ContratoPdfNoSelladoError: class ContratoPdfNoSelladoError extends Error {},
  etiquetaEstadoContratoPdf: (estado: string) => estado,
  imprimirAnexoCronograma: archivoPdf.anexo,
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
    // P-055 Fase 3: sin atribución, el bloque de "analista de la venta" no se
    // pinta; estas pruebas son del PDF y no lo necesitan.
    useAtribucionContrato: () => q(null),
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
  // Firmado ya en el régimen documental nuevo: solo ahí existe el documento que
  // esta suite ejercita. Un contrato anterior al 19/08 no ofrece ni genera nada
  // — eso lo fija la prueba del final del archivo.
  fecha_inicio: '2026-08-19',
  fecha_vencimiento: '2027-08-19',
  fecha_cierre_comercial: '2026-08-19',
  notas_internas: null,
  creado_por: 'd-v1',
  creado_en: '2026-08-19T12:00:00.000Z',
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
    nombreCompleto: 'ANALISTA UNO',
    documento: '10000001',
    celular: '+51 987 654 321',
    correo: 'analista.uno@avancecorp.pe',
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

const anexo = {
  contratoId: contrato.id,
  contratoRevision: 1,
  template: 'anexo-cronograma-v1',
  nombreArchivo: 'Anexo-2026-01-000901-ROSA.pdf',
  sha256: 'b'.repeat(64),
  bytes: 17,
  blob: new Blob(['%PDF-1.7\nanexo'], { type: 'application/pdf' }),
}

const { ContratoDetalle } = await import('./contrato-detalle')

function render(elemento: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })

  return renderBase(elemento, {
    wrapper: ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    ),
  })
}

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
    archivoPdf.anexo.mockReset().mockResolvedValue(anexo)
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

    expect(await screen.findByText(/Estado documental:/)).toHaveTextContent('error_reintentable')
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
    expect(screen.getByText('Consultando el estado documental…')).toBeInTheDocument()

    await act(async () => {
      estadoB.resolver({ estado: 'sellado' })
      await estadoB.promesa
    })
    expect(screen.getByText(/Estado documental:/)).toHaveTextContent('sellado')

    await act(async () => {
      estadoA.resolver({ estado: 'integridad_bloqueada' })
      await estadoA.promesa
    })
    expect(screen.getByText(/Estado documental:/)).toHaveTextContent('sellado')
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
    expect(screen.getByText(/Estado documental:/)).toHaveTextContent('sellado')

    await act(async () => {
      status.resolver({ estado: 'pendiente' })
      await status.promesa
    })
    expect(screen.getByText(/Estado documental:/)).toHaveTextContent('sellado')
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

    expect(toast.error).toHaveBeenCalledWith('No se pudo archivar el PDF confirmado.')
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

    expect(toast.error).toHaveBeenCalledWith('El navegador bloqueó la ventana del contrato PDF.')
    expect(archivoPdf.obtener).not.toHaveBeenCalled()
  })
  // ── Anexo de cronograma: documento aparte que el analista imprime (28/09) ──
  it('imprime el anexo de cronograma en una pestaña reservada en el clic, sin tocar el contrato', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    const ventana = { close: vi.fn() }
    archivoPdf.abrir.mockReturnValue(ventana)
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' }))

    await waitFor(() => expect(archivoPdf.ver).toHaveBeenCalledWith(anexo, ventana))
    expect(archivoPdf.abrir).toHaveBeenCalledWith(
      'Preparando anexo de cronograma…',
      'Preparando el anexo de cronograma desde el contrato sellado…',
      'anexo de cronograma',
    )
    expect(archivoPdf.anexo).toHaveBeenCalledWith(contrato.id)
    expect(archivoPdf.obtener).not.toHaveBeenCalled()
    expect(archivoPdf.archivar).not.toHaveBeenCalled()
    expect(ventana.close).not.toHaveBeenCalled()
    expect(toast.error).not.toHaveBeenCalled()
  })

  it('si el contrato no tiene PDF sellado, cierra la pestaña y muestra el aviso del servidor', async () => {
    const user = userEvent.setup()
    consultas.contrato = contrato
    const ventana = { close: vi.fn() }
    archivoPdf.abrir.mockReturnValue(ventana)
    archivoPdf.anexo.mockRejectedValue(
      new Error('El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF'),
    )
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle contratoId={contrato.id} onCerrar={() => undefined} />
      </Dialog>,
    )

    await user.click(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' }))

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(
        'El contrato todavía no tiene su PDF sellado; genera primero el contrato PDF',
      ),
    )
    expect(ventana.close).toHaveBeenCalled()
    expect(archivoPdf.ver).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeEnabled()
  })

  it('en modo demo no ofrece el anexo (no hay contrato sellado del que sacarlo)', () => {
    consultas.contrato = contrato
    render(
      <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
        <ContratoDetalle
          contratoId={contrato.id}
          datos={{ contrato, cuotas: [], titulares: [], pdfDatos }}
          onCerrar={() => undefined}
        />
      </Dialog>,
    )

    expect(screen.getByRole('button', { name: 'Ver contrato PDF' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Imprimir anexo de cronograma' })).toBeNull()
  })

  // ── El régimen documental anterior (2026-08-20) ────────────────────────────
  // «Ver contrato PDF» no muestra: si no hay documento, lo FABRICA. En un
  // contrato firmado antes del 19/08 eso acuñaba un segundo contrato para una
  // operación ya firmada — así nacieron los 21 documentos del 18 y 19 de agosto.
  describe('contrato del formato anterior', () => {
    const antiguo: ContratoRow = {
      ...contrato,
      id: 'dc-ct-viejo',
      // Un solo día antes de la frontera: si alguien afloja la regla, cae aquí.
      fecha_inicio: '2026-08-18',
      fecha_vencimiento: '2027-08-18',
    }

    it('no ofrece generar el documento y explica por qué', async () => {
      consultas.contrato = antiguo
      archivoPdf.consultar.mockResolvedValue({ estado: 'sin_reserva' })
      render(
        <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
          <ContratoDetalle contratoId={antiguo.id} onCerrar={() => undefined} />
        </Dialog>,
      )

      expect(await screen.findByText(/su contrato es el del formato anterior/)).toBeInTheDocument()
      expect(screen.queryByRole('button', { name: 'Ver contrato PDF' })).not.toBeInTheDocument()
      expect(screen.queryByRole('button', { name: 'Descargar contrato PDF' })).not.toBeInTheDocument()
      expect(archivoPdf.obtener).not.toHaveBeenCalled()
      expect(archivoPdf.archivar).not.toHaveBeenCalled()
    })

    it('un plazo que empieza en 2027 pero registrado en julio sigue siendo del formato anterior', async () => {
      // Caso REAL de producción (2026-08-20): los contratos 2026-01-000891 y
      // 000892 se cargaron el 1 de julio con el plazo empezando el 1 de julio de
      // 2027. `fecha_inicio` es el inicio del PLAZO, no la firma: mirándola sola,
      // la pantalla ofrecería fabricar un contrato del formato nuevo a una
      // operación firmada en julio, cuando ese documento ni existía.
      consultas.contrato = {
        ...contrato,
        id: 'dc-ct-plazo-futuro',
        fecha_inicio: '2027-07-01',
        fecha_vencimiento: '2028-07-01',
        creado_en: '2026-07-01T18:04:08.000Z',
      }
      archivoPdf.consultar.mockResolvedValue({ estado: 'sin_reserva' })
      render(
        <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
          <ContratoDetalle contratoId="dc-ct-plazo-futuro" onCerrar={() => undefined} />
        </Dialog>,
      )

      expect(await screen.findByText(/su contrato es el del formato anterior/)).toBeInTheDocument()
      expect(screen.queryByRole('button', { name: 'Ver contrato PDF' })).not.toBeInTheDocument()
      expect(archivoPdf.archivar).not.toHaveBeenCalled()
    })

    it('si YA se le emitió uno, se sigue pudiendo ver y descargar', async () => {
      // Los 21 ya emitidos se quedan como están: esta regla impide que nazcan
      // más, no esconde los que hay.
      consultas.contrato = antiguo
      archivoPdf.consultar.mockResolvedValue({ estado: 'sellado' })
      render(
        <Dialog open onClose={() => undefined} ariaLabel="Detalle del contrato">
          <ContratoDetalle contratoId={antiguo.id} onCerrar={() => undefined} />
        </Dialog>,
      )

      expect(await screen.findByRole('button', { name: 'Descargar contrato PDF' })).toBeInTheDocument()
      expect(screen.getByRole('button', { name: 'Ver contrato PDF' })).toBeInTheDocument()
    })
  })
})
