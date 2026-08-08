import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { CrmApiError } from '@/data/crm-api'
import type {
  ConfiguracionProductos,
  ProductoCondicion,
  ProductoInversion,
  ProductoVersion,
} from '@/lib/productos-inversion'

const dobles = vi.hoisted(() => ({
  consulta: {} as Record<string, unknown>,
  crearProducto: vi.fn(),
  crearVersion: vi.fn(),
  actualizarBorrador: vi.fn(),
  publicarVersion: vi.fn(),
  archivarProducto: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}))

vi.mock('sonner', () => ({
  toast: { success: dobles.toastSuccess, error: dobles.toastError },
}))

vi.mock('@/data/crm-config-queries', () => ({
  useConfiguracionProductos: () => dobles.consulta,
  useCrearProductoInversion: () => ({ mutateAsync: dobles.crearProducto, isPending: false }),
  useCrearVersionProducto: () => ({ mutateAsync: dobles.crearVersion, isPending: false }),
  useActualizarBorradorProducto: () => ({ mutateAsync: dobles.actualizarBorrador, isPending: false }),
  usePublicarVersionProducto: () => ({ mutateAsync: dobles.publicarVersion, isPending: false }),
  useArchivarProducto: () => ({ mutateAsync: dobles.archivarProducto, isPending: false }),
}))

const { ConfigProductos } = await import('./config-productos')

const ID_PRODUCTO = '10000000-0000-4000-8000-000000000001'
const ID_VERSION_BORRADOR = '20000000-0000-4000-8000-000000000001'
const ID_VERSION_PUBLICADA = '20000000-0000-4000-8000-000000000002'
const ID_VERSION_RETIRADA = '20000000-0000-4000-8000-000000000003'

function condicion(overrides: Partial<ProductoCondicion> = {}): ProductoCondicion {
  return {
    id: '30000000-0000-4000-8000-000000000001',
    orden: 1,
    categoria: 'nuevo',
    moneda: 'PEN',
    plazo_meses: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    capital_minimo: 1_000,
    capital_maximo: 10_000,
    tasa_referencia: 8,
    tasa_minima: 7,
    tasa_maxima: 9,
    activa: true,
    creado_en: '2026-08-01T10:00:00.000Z',
    retirada_en: null,
    ...overrides,
  }
}

function version(overrides: Partial<ProductoVersion> = {}): ProductoVersion {
  return {
    id: ID_VERSION_BORRADOR,
    numero_version: 3,
    estado: 'borrador',
    revision: 4,
    nombre: 'Renta flexible 2026',
    descripcion: 'Condiciones comerciales de la campaña vigente.',
    vigente_desde: '2026-01-01',
    vigente_hasta: null,
    creado_por: null,
    creado_en: '2026-08-01T10:00:00.000Z',
    actualizado_por: null,
    actualizado_en: '2026-08-01T10:00:00.000Z',
    publicada_por: null,
    publicada_por_nombre: null,
    publicada_en: null,
    retirada_por: null,
    retirada_en: null,
    condiciones: [condicion()],
    ...overrides,
  }
}

function producto(overrides: Partial<ProductoInversion> = {}): ProductoInversion {
  return {
    id: ID_PRODUCTO,
    codigo: 'RENTA-12',
    estado: 'activo',
    revision: 8,
    creado_por: null,
    creado_en: '2026-07-01T10:00:00.000Z',
    actualizado_por: null,
    actualizado_en: '2026-08-01T10:00:00.000Z',
    archivado_por: null,
    archivado_en: null,
    versiones: [version()],
    ...overrides,
  }
}

function configuracion(
  productos: ProductoInversion[],
  puedeAdministrar = true,
): ConfiguracionProductos {
  return {
    version: 1,
    generado_en: '2026-08-07T15:30:00.000Z',
    puede_administrar: puedeAdministrar,
    compatibilidad_altas_legacy: true,
    compatibilidad_revision: 2,
    productos,
  }
}

function consultaCon(
  data: ConfiguracionProductos | undefined,
  overrides: Record<string, unknown> = {},
) {
  return {
    data,
    error: null,
    isPending: false,
    isError: false,
    isFetching: false,
    refetch: vi.fn(),
    ...overrides,
  }
}

beforeEach(() => {
  dobles.consulta = consultaCon(configuracion([]))
  dobles.crearProducto.mockResolvedValue({})
  dobles.crearVersion.mockResolvedValue({})
  dobles.actualizarBorrador.mockResolvedValue({})
  dobles.publicarVersion.mockResolvedValue({})
  dobles.archivarProducto.mockResolvedValue({})
})

describe('ConfigProductos', () => {
  it('representa carga, error seguro con reintento y catálogo vacío', async () => {
    const { rerender } = render(<ConfigProductos />)

    expect(screen.getByText('El catálogo todavía está vacío')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Crear primer producto' })).toBeInTheDocument()

    dobles.consulta = consultaCon(undefined, { isPending: true })
    rerender(<ConfigProductos />)
    expect(screen.getByRole('status')).toHaveTextContent('Cargando el catálogo autorizado')

    const refetch = vi.fn()
    dobles.consulta = consultaCon(undefined, {
      isError: true,
      error: new Error('token-interno-que-no-debe-salir'),
      refetch,
    })
    rerender(<ConfigProductos />)

    expect(screen.getByRole('alert')).toHaveTextContent('No se pudo cargar el catálogo de productos.')
    expect(screen.queryByText(/token-interno/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(refetch).toHaveBeenCalledOnce()
  })

  it('muestra productos, versiones y condiciones sin exponer el cierre legacy', () => {
    const catalogo = producto({
      versiones: [
        version({
          condiciones: [
            condicion(),
            condicion({
              id: '30000000-0000-4000-8000-000000000002',
              orden: 2,
              categoria: 'renovacion',
              moneda: 'USD',
              modalidad: 'anual',
              tipo_interes: 'compuesto',
              activa: false,
              retirada_en: '2026-08-02T10:00:00.000Z',
            }),
          ],
        }),
        version({
          id: ID_VERSION_PUBLICADA,
          numero_version: 2,
          estado: 'publicada',
          revision: 2,
          publicada_en: '2026-07-01T15:00:00.000Z',
          publicada_por_nombre: 'Gerencia Uno',
          condiciones: [condicion({ id: '30000000-0000-4000-8000-000000000003' })],
        }),
        version({
          id: ID_VERSION_RETIRADA,
          numero_version: 1,
          estado: 'retirada',
          revision: 3,
          retirada_en: '2026-07-01T15:00:00.000Z',
          condiciones: [condicion({ id: '30000000-0000-4000-8000-000000000004' })],
        }),
      ],
    })
    dobles.consulta = consultaCon(configuracion([catalogo]))

    render(<ConfigProductos />)

    expect(screen.getByRole('heading', { name: 'RENTA-12' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /v3 · Renta flexible 2026/ })).toBeInTheDocument()
    expect(screen.getByText('Renovación · USD')).toBeInTheDocument()
    expect(screen.getByText('Reemplazada')).toBeInTheDocument()
    expect(screen.getAllByRole('table')).toHaveLength(3)
    expect(screen.getByRole('button', { name: 'Editar borrador' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Crear versión' })).not.toBeInTheDocument()
    expect(screen.queryByText(/compatibilidad|legacy/i)).not.toBeInTheDocument()
  })

  it('impone solo lectura desde el contrato del servidor', () => {
    dobles.consulta = consultaCon(configuracion([producto()], false))

    render(<ConfigProductos />)

    expect(screen.getByText(/Solo lectura: puedes auditar/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Nuevo producto' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Editar borrador' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Publicar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Archivar' })).not.toBeInTheDocument()
  })

  it('crea un producto con las combinaciones y rangos exactos del editor', async () => {
    const user = userEvent.setup()
    render(<ConfigProductos />)

    await user.click(screen.getByRole('button', { name: 'Nuevo producto' }))
    const dialogo = screen.getByRole('dialog', { name: 'Crear producto' })
    await user.type(within(dialogo).getByLabelText('Código'), 'fondo.usd')
    await user.type(within(dialogo).getByLabelText('Nombre de la versión'), 'Fondo dólar 24 meses')
    await user.selectOptions(within(dialogo).getByLabelText('Categoría'), 'renovacion')
    await user.selectOptions(within(dialogo).getByLabelText('Moneda'), 'USD')
    await user.clear(within(dialogo).getByLabelText('Plazo (meses)'))
    await user.type(within(dialogo).getByLabelText('Plazo (meses)'), '24')
    await user.selectOptions(within(dialogo).getByLabelText('Modalidad'), 'trimestral')
    await user.selectOptions(within(dialogo).getByLabelText('Tipo de interés'), 'compuesto')
    expect(within(dialogo).getByLabelText('Modalidad')).toHaveValue('anual')
    expect(within(dialogo).getByLabelText('Modalidad')).toBeDisabled()
    await user.clear(within(dialogo).getByLabelText('Capital mínimo'))
    await user.type(within(dialogo).getByLabelText('Capital mínimo'), '5000')
    await user.clear(within(dialogo).getByLabelText('Capital máximo'))
    await user.type(within(dialogo).getByLabelText('Capital máximo'), '50000')
    await user.clear(within(dialogo).getByLabelText('Tasa mínima (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa mínima (%)'), '4.5')
    await user.clear(within(dialogo).getByLabelText('Tasa de referencia (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa de referencia (%)'), '5')
    await user.clear(within(dialogo).getByLabelText('Tasa máxima (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa máxima (%)'), '5.5')
    await user.click(within(dialogo).getByRole('button', { name: 'Crear borrador' }))

    await waitFor(() => expect(dobles.crearProducto).toHaveBeenCalledOnce())
    expect(dobles.crearProducto).toHaveBeenCalledWith(expect.objectContaining({
      codigo: 'FONDO.USD',
      nombre: 'Fondo dólar 24 meses',
      descripcion: null,
      vigenteHasta: null,
      condiciones: [{
        categoria: 'renovacion',
        moneda: 'USD',
        plazo_meses: 24,
        modalidad: 'anual',
        tipo_interes: 'compuesto',
        capital_minimo: 5_000,
        capital_maximo: 50_000,
        tasa_minima: 4.5,
        tasa_referencia: 5,
        tasa_maxima: 5.5,
      }],
    }))
    expect(dobles.toastSuccess).toHaveBeenCalledWith('Producto FONDO.USD creado como borrador.')
  })

  it('bloquea código, nombre, fechas, plazo, capitales y tasas fuera del contrato', async () => {
    const user = userEvent.setup()
    render(<ConfigProductos />)
    await user.click(screen.getByRole('button', { name: 'Nuevo producto' }))
    const dialogo = screen.getByRole('dialog', { name: 'Crear producto' })
    const guardar = within(dialogo).getByRole('button', { name: 'Crear borrador' })

    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('El código debe tener entre 2 y 40 caracteres')

    await user.type(within(dialogo).getByLabelText('Código'), 'AB')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('El nombre debe tener entre 3 y 160 caracteres')

    await user.type(within(dialogo).getByLabelText('Nombre de la versión'), 'Producto válido')
    fireEvent.change(within(dialogo).getByLabelText('Vigente desde'), { target: { value: '2026-08-10' } })
    fireEvent.change(within(dialogo).getByLabelText('Vigente hasta (opcional)'), { target: { value: '2026-08-09' } })
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('La fecha final no puede ser anterior')

    fireEvent.change(within(dialogo).getByLabelText('Vigente hasta (opcional)'), { target: { value: '' } })
    await user.clear(within(dialogo).getByLabelText('Plazo (meses)'))
    await user.type(within(dialogo).getByLabelText('Plazo (meses)'), '601')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('entero entre 1 y 600 meses')

    await user.clear(within(dialogo).getByLabelText('Plazo (meses)'))
    await user.type(within(dialogo).getByLabelText('Plazo (meses)'), '12')
    await user.clear(within(dialogo).getByLabelText('Capital mínimo'))
    await user.type(within(dialogo).getByLabelText('Capital mínimo'), '99')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('entre 100 y 100,000,000')

    await user.clear(within(dialogo).getByLabelText('Capital mínimo'))
    await user.type(within(dialogo).getByLabelText('Capital mínimo'), '200')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('capital mínimo de la condición 1 no puede superar')

    await user.clear(within(dialogo).getByLabelText('Capital máximo'))
    await user.type(within(dialogo).getByLabelText('Capital máximo'), '500')
    await user.clear(within(dialogo).getByLabelText('Tasa mínima (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa mínima (%)'), '0')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('mayores que 0 y no superar 50%')

    await user.clear(within(dialogo).getByLabelText('Tasa mínima (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa mínima (%)'), '2')
    await user.clear(within(dialogo).getByLabelText('Tasa de referencia (%)'))
    await user.type(within(dialogo).getByLabelText('Tasa de referencia (%)'), '1')
    await user.click(guardar)
    expect(within(dialogo).getByRole('alert')).toHaveTextContent('mínima ≤ referencia ≤ máxima')
    expect(dobles.crearProducto).not.toHaveBeenCalled()
  })

  it('mantiene al menos una condición y permite agregar otra', async () => {
    const user = userEvent.setup()
    render(<ConfigProductos />)
    await user.click(screen.getByRole('button', { name: 'Nuevo producto' }))
    const dialogo = screen.getByRole('dialog', { name: 'Crear producto' })

    expect(within(dialogo).getByRole('button', { name: 'Eliminar condición 1' })).toBeDisabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Agregar condición' }))
    expect(within(dialogo).getByText('Condición 2 de 2')).toBeInTheDocument()
    expect(within(dialogo).getByRole('button', { name: 'Eliminar condición 1' })).toBeEnabled()
    await user.click(within(dialogo).getByRole('button', { name: 'Eliminar condición 2' }))
    expect(within(dialogo).queryByText('Condición 2 de 2')).not.toBeInTheDocument()
  })

  it('crea una versión copiando la publicada y usa la revisión del producto', async () => {
    const publicada = version({
      id: ID_VERSION_PUBLICADA,
      numero_version: 2,
      estado: 'publicada',
      revision: 3,
      publicada_en: '2026-07-01T15:00:00.000Z',
      condiciones: [condicion()],
    })
    const catalogo = producto({ versiones: [publicada] })
    dobles.consulta = consultaCon(configuracion([catalogo]))
    const user = userEvent.setup()
    render(<ConfigProductos />)

    await user.click(screen.getByRole('button', { name: 'Crear versión' }))
    const dialogo = screen.getByRole('dialog', { name: 'Crear versión de RENTA-12' })
    expect(within(dialogo).getByLabelText('Código')).toBeDisabled()
    expect(within(dialogo).getByLabelText('Nombre de la versión')).toHaveValue('Renta flexible 2026')
    await user.clear(within(dialogo).getByLabelText('Nombre de la versión'))
    await user.type(within(dialogo).getByLabelText('Nombre de la versión'), 'Renta flexible 2027')
    await user.click(within(dialogo).getByRole('button', { name: 'Crear borrador' }))

    await waitFor(() => expect(dobles.crearVersion).toHaveBeenCalledOnce())
    expect(dobles.crearVersion).toHaveBeenCalledWith(expect.objectContaining({
      productoId: ID_PRODUCTO,
      expectedRevision: 8,
      nombre: 'Renta flexible 2027',
      condiciones: [expect.objectContaining({ categoria: 'nuevo', capital_minimo: 1_000 })],
    }))
  })

  it('edita el borrador usando solo sus condiciones activas y la revisión de versión', async () => {
    const borrador = version({
      revision: 7,
      condiciones: [
        condicion({ activa: false, retirada_en: '2026-08-02T10:00:00.000Z' }),
        condicion({
          id: '30000000-0000-4000-8000-000000000002',
          orden: 2,
          categoria: 'upgrade',
          moneda: 'USD',
          capital_minimo: 2_000,
          capital_maximo: 20_000,
        }),
      ],
    })
    dobles.consulta = consultaCon(configuracion([producto({ versiones: [borrador] })]))
    const user = userEvent.setup()
    render(<ConfigProductos />)

    await user.click(screen.getByRole('button', { name: 'Editar borrador' }))
    const dialogo = screen.getByRole('dialog', { name: 'Editar RENTA-12 · v3' })
    expect(within(dialogo).getByText('Condición 1 de 1')).toBeInTheDocument()
    expect(within(dialogo).getByLabelText('Categoría')).toHaveValue('upgrade')
    await user.clear(within(dialogo).getByLabelText('Nombre de la versión'))
    await user.type(within(dialogo).getByLabelText('Nombre de la versión'), 'Borrador corregido')
    await user.click(within(dialogo).getByRole('button', { name: 'Guardar borrador' }))

    await waitFor(() => expect(dobles.actualizarBorrador).toHaveBeenCalledOnce())
    expect(dobles.actualizarBorrador).toHaveBeenCalledWith(expect.objectContaining({
      versionId: ID_VERSION_BORRADOR,
      expectedRevision: 7,
      nombre: 'Borrador corregido',
      condiciones: [expect.objectContaining({ categoria: 'upgrade', moneda: 'USD' })],
    }))
  })

  it('publica y archiva únicamente después de una confirmación explícita', async () => {
    dobles.consulta = consultaCon(configuracion([producto()]))
    const user = userEvent.setup()
    render(<ConfigProductos />)

    await user.click(screen.getByRole('button', { name: 'Publicar' }))
    expect(dobles.publicarVersion).not.toHaveBeenCalled()
    const dialogoPublicar = screen.getByRole('dialog', { name: '¿Publicar RENTA-12 · v3?' })
    expect(within(dialogoPublicar).getByText(/contratos históricos conservarán/)).toBeInTheDocument()
    await user.click(within(dialogoPublicar).getByRole('button', { name: 'Sí, publicar versión 3' }))
    await waitFor(() => expect(dobles.publicarVersion).toHaveBeenCalledWith({
      versionId: ID_VERSION_BORRADOR,
      expectedRevision: 4,
    }))

    await user.click(screen.getByRole('button', { name: 'Archivar' }))
    expect(dobles.archivarProducto).not.toHaveBeenCalled()
    const dialogoArchivar = screen.getByRole('dialog', { name: '¿Archivar RENTA-12?' })
    expect(within(dialogoArchivar).getByText(/versiones activas se retirarán/)).toBeInTheDocument()
    await user.click(within(dialogoArchivar).getByRole('button', { name: 'Sí, archivar RENTA-12' }))
    await waitFor(() => expect(dobles.archivarProducto).toHaveBeenCalledWith({
      productoId: ID_PRODUCTO,
      expectedRevision: 8,
    }))
  })

  it('muestra el conflicto traducido y no filtra errores inesperados en toast', async () => {
    dobles.consulta = consultaCon(configuracion([producto()]))
    dobles.publicarVersion.mockRejectedValueOnce(new CrmApiError(
      'La configuración cambió en otra sesión. Recarga antes de continuar.',
      'CONFLICTO_CONFIG',
    ))
    dobles.archivarProducto.mockRejectedValueOnce(new Error('detalle SQL privado'))
    const user = userEvent.setup()
    render(<ConfigProductos />)

    await user.click(screen.getByRole('button', { name: 'Publicar' }))
    await user.click(screen.getByRole('button', { name: 'Sí, publicar versión 3' }))
    await waitFor(() => expect(dobles.toastError).toHaveBeenCalledWith(
      'La configuración cambió en otra sesión. Recarga antes de continuar.',
    ))
    expect(screen.getByRole('dialog', { name: '¿Publicar RENTA-12 · v3?' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    await user.click(screen.getByRole('button', { name: 'Archivar' }))
    await user.click(screen.getByRole('button', { name: 'Sí, archivar RENTA-12' }))
    await waitFor(() => expect(dobles.toastError).toHaveBeenCalledWith('No se pudo archivar el producto.'))
    expect(dobles.toastError).not.toHaveBeenCalledWith(expect.stringContaining('detalle SQL privado'))
  })
})
