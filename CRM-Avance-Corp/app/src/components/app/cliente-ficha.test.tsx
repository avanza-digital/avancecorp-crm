// Ficha comercial del cliente. Estos tests usan React Query REAL y mockean
// únicamente la frontera HTTP: fijan que el contacto y las cuentas nunca se
// presenten desde caché, que los errores degraden solo su sección y que la demo
// haga cero red.
// Las cuentas salen de la RPC del ledger (listarCuentasBancariasCliente), NO de
// las columnas embebidas del perfil: ese fue el bug de 2026-08-11 (una cuenta
// registrada al crear un contrato no aparecía en la ficha).
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sheet } from '@/components/ui/sheet'
import { crmQueryKeys } from '@/data/crm-queries'
import type {
  ClienteDetalle as ClienteDetalleDatos,
  ClienteFichaComercial,
  CuentaBancariaSeleccionable,
  OperacionCartera,
} from '@/lib/clientes-tipos'
import type { ContratoRow } from '@/lib/clientes-tipos'
import type { GrupoCartera } from '@/lib/cartera-vista'
import type { Tarea } from '@/lib/tipos'
import type { ClienteFichaProps } from './cliente-ficha'
import * as crmApi from '@/data/crm-api'

const store = vi.hoisted(() => ({
  tareasDeCliente: vi.fn((): Tarea[] => []),
}))

vi.mock('@/lib/store-context', () => ({
  useCRMData: () => store,
}))

vi.mock('@/data/crm-api', async (importActual) => {
  const actual = await importActual<typeof import('@/data/crm-api')>()
  return {
    ...actual,
    obtenerClienteFichaComercial: vi.fn(),
    listarCuentasBancariasCliente: vi.fn(),
    listarActividadesCliente: vi.fn(),
  }
})

const { ClienteFicha } = await import('./cliente-ficha')
const obtenerFichaComercial = vi.mocked(crmApi.obtenerClienteFichaComercial)
const listarCuentas = vi.mocked(crmApi.listarCuentasBancariasCliente)
const listarActividades = vi.mocked(crmApi.listarActividadesCliente)

function detalleBase(over: Partial<ClienteDetalleDatos> = {}): ClienteDetalleDatos {
  return {
    id: 'cli-1',
    nombre_completo: 'CLIENTE PORTAL UNO',
    nombres: 'CLIENTE',
    apellidos: 'PORTAL UNO',
    tipo_documento: 'DNI',
    dni: '45781234',
    correo: 'cliente1@correo.pe',
    telefono: '999111222',
    domicilio: 'Av. Javier Prado Este 123, San Isidro, Lima',
    asesor_perfil_id: 'yo',
    creado_por: 'yo',
    creado_en: '2026-07-15T12:00:00.000Z',
    banca_visible: true,
    cuentas_bancarias_visibles: true,
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    banco_usd: 'Interbank',
    tipo_cuenta_usd: 'corriente',
    numero_cuenta_usd: '2003001234567',
    cci_usd: '00320030012345678901',
    titular_distinto_usd: true,
    beneficiario_nombre_usd: 'JUANA PÉREZ DEMO',
    beneficiario_dni_usd: '87654321',
    ...over,
  }
}

/** La sesión real recibe solo identidad y contacto; domicilio y banca no cruzan esta frontera. */
function fichaComercialBase(over: Partial<ClienteFichaComercial> = {}): ClienteFichaComercial {
  const detalle = detalleBase()
  return {
    id: detalle.id,
    nombres: detalle.nombres,
    apellidos: detalle.apellidos,
    nombre_completo: detalle.nombre_completo,
    tipo_documento: detalle.tipo_documento,
    dni: detalle.dni,
    correo: detalle.correo,
    telefono: detalle.telefono,
    asesor_perfil_id: detalle.asesor_perfil_id,
    activo: true,
    creado_en: detalle.creado_en,
    ...over,
  }
}

function cuentaRpc(over: Partial<CuentaBancariaSeleccionable> = {}): CuentaBancariaSeleccionable {
  return {
    cuenta_id: 'cta-pen-1',
    moneda: 'PEN',
    banco: 'BCP',
    tipo_cuenta: 'ahorros',
    numero_cuenta: '19112345678901',
    cci: '00219112345678901234',
    titular_distinto: false,
    beneficiario_nombre: null,
    beneficiario_dni: null,
    origen: 'perfil',
    es_cuenta_perfil: false,
    creada_en: '2026-08-04T22:51:09.000Z',
    ...over,
  }
}

/** Responde la RPC por moneda (la ficha pide PEN y USD en paralelo). */
function cuentasPorMoneda(pen: CuentaBancariaSeleccionable[], usd: CuentaBancariaSeleccionable[]) {
  listarCuentas.mockImplementation(async (_clienteId, moneda) => (moneda === 'USD' ? usd : pen))
}

function clienteQuery(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { retry: false, networkMode: 'offlineFirst' },
    },
  })
}

function grupoBase(nombre = 'CLIENTE PORTAL UNO'): GrupoCartera {
  return {
    cliente: {
      id: 'cli-1',
      nombres: 'CLIENTE',
      apellidos: 'PORTAL UNO',
      nombre_completo: nombre,
      tipo_documento: 'DNI',
      dni: '45781234',
      correo: 'cliente1@correo.pe',
      telefono: '999111222',
      asesor_perfil_id: 'yo',
      creado_por: 'yo',
      activo: true,
      creado_en: '2026-07-15T12:00:00.000Z',
    },
    contratos: [],
    capitalActivoPen: 0,
    capitalActivoUsd: 0,
    contratosActivos: 0,
    tieneCapital: false,
    proximoVencimiento: null,
  }
}

function contratoBase(over: Partial<ContratoRow> = {}): ContratoRow {
  return {
    id: 'contrato-1',
    numero_contrato: '2026-01-000321',
    cliente_id: 'cli-1',
    cliente_nombre: 'CLIENTE PORTAL UNO',
    capital: 25000,
    moneda: 'PEN',
    tasa_anual: 12,
    modalidad: 'mensual',
    tipo_interes: 'simple',
    categoria: 'nuevo',
    estado: 'activo',
    fecha_inicio: '2025-08-25',
    fecha_vencimiento: '2026-08-25',
    notas_internas: null,
    creado_por: 'yo',
    creado_en: '2025-08-25T15:00:00.000Z',
    producto_condicion_id: 'condicion-1',
    producto_id: 'producto-1',
    producto_codigo: 'INVERSION-12M',
    producto_version_id: 'version-1',
    producto_version: 1,
    producto_nombre: 'Inversión 12 meses',
    producto_version_estado: 'publicada',
    ...over,
  }
}

function tareaClienteBase(over: Partial<Tarea> = {}): Tarea {
  return {
    id: 'tarea-cliente-1',
    lead_id: null,
    perfil_id: 'cli-1',
    vendedor_id: 'yo',
    titulo: 'Llamar para revisar la renovación',
    tipo: 'llamada',
    estado: 'pendiente',
    vence_en: '2026-08-26T15:00:00.000Z',
    activo: true,
    creado_en: '2026-08-25T15:00:00.000Z',
    reprogramaciones: 0,
    ...over,
  }
}

function montar({
  queryClient = clienteQuery(),
  datos,
  grupo,
  props,
}: {
  queryClient?: QueryClient
  datos?: ClienteDetalleDatos
  grupo?: GrupoCartera
  props?: Partial<Omit<ClienteFichaProps, 'grupo' | 'analistaNombre' | 'datos' | 'onCerrar'>>
} = {}) {
  const onCerrar = vi.fn()
  const grupoFinal = grupo ?? grupoBase(datos?.nombre_completo)
  render(
    <QueryClientProvider client={queryClient}>
      <Sheet open onClose={() => undefined} ariaLabel="Ficha del cliente">
        <ClienteFicha
          grupo={grupoFinal}
          analistaNombre="ANALISTA"
          onCerrar={onCerrar}
          {...(datos === undefined ? {} : { datos })}
          {...props}
        />
      </Sheet>
    </QueryClientProvider>,
  )
  return { onCerrar, queryClient }
}

beforeEach(() => {
  obtenerFichaComercial.mockReset()
  listarCuentas.mockReset()
  listarActividades.mockReset()
  listarCuentas.mockResolvedValue([])
  listarActividades.mockResolvedValue([])
  store.tareasDeCliente.mockReset().mockReturnValue([])
})

describe('ClienteFicha — frescura y presentación', () => {
  it('resume la continuidad comercial y permite pasar del contexto a las acciones existentes', async () => {
    const user = userEvent.setup()
    const onGestionar = vi.fn()
    const onNuevoContrato = vi.fn()
    const onUpgrade = vi.fn()
    const onDetalleContrato = vi.fn()
    const onRenovarContrato = vi.fn()
    const contrato = contratoBase()
    const grupo: GrupoCartera = {
      ...grupoBase(),
      contratos: [
        contrato,
        contratoBase({ id: 'contrato-usd', numero_contrato: '2026-01-000654', moneda: 'USD', capital: 10000 }),
      ],
      capitalActivoPen: 25000,
      capitalActivoUsd: 10000,
      contratosActivos: 2,
      tieneCapital: true,
      proximoVencimiento: '2026-08-25',
    }
    store.tareasDeCliente.mockReturnValue([tareaClienteBase()])

    montar({
      datos: detalleBase(),
      grupo,
      props: {
        onGestionar,
        onNuevoContrato,
        onUpgrade,
        onDetalleContrato,
        onRenovarContrato,
      },
    })

    const continuidad = screen.getByRole('region', { name: 'Continuidad comercial del cliente' })
    expect(within(continuidad).getByText('S/ 25,000')).toBeInTheDocument()
    expect(within(continuidad).getByText('US$ 10,000')).toBeInTheDocument()
    expect(within(continuidad).getByText('Renovación pendiente')).toBeInTheDocument()
    expect(within(continuidad).getByText('El siguiente paso para mantener activa la relación')).toBeInTheDocument()
    expect(within(continuidad).getByText('Llamar para revisar la renovación')).toBeInTheDocument()
    expect(screen.getByText('Inversiones y contratos')).toBeInTheDocument()
    expect(screen.getByText('2026-01-000321', { exact: false })).toBeInTheDocument()

    for (const nombreAccion of [
      'Aumentar inversión',
      'Registrar nueva inversión',
      'Ver contrato 2026-01-000321',
      'Renovar inversión del contrato 2026-01-000321',
      'Agendar seguimiento',
    ]) {
      const control = screen.getByRole('button', { name: nombreAccion })
      expect(control).toHaveClass(nombreAccion === 'Agendar seguimiento' ? 'min-h-11' : 'min-h-10')
      expect(control).not.toHaveClass('md:min-h-6')
      expect(control).not.toHaveClass('md:min-h-9')
    }
    expect(screen.getByRole('button', { name: 'Cerrar ficha' })).toHaveClass('size-10')
    expect(screen.getByRole('button', { name: 'Cerrar ficha' })).not.toHaveClass('sm:size-8')
    expect(screen.getByRole('button', { name: /^Cerrar$/ })).toHaveClass('min-h-11')
    expect(screen.getByRole('button', { name: /^Cerrar$/ })).not.toHaveClass('md:min-h-9')

    await user.click(screen.getByRole('button', { name: 'Agendar seguimiento' }))
    await user.click(screen.getByRole('button', { name: 'Aumentar inversión' }))
    await user.click(screen.getByRole('button', { name: 'Registrar nueva inversión' }))
    await user.click(screen.getByRole('button', { name: 'Ver contrato 2026-01-000321' }))
    await user.click(screen.getByRole('button', { name: 'Renovar inversión del contrato 2026-01-000321' }))

    expect(onGestionar).toHaveBeenCalledTimes(1)
    expect(onUpgrade).toHaveBeenCalledTimes(1)
    expect(onNuevoContrato).toHaveBeenCalledTimes(1)
    expect(onDetalleContrato).toHaveBeenCalledWith(contrato)
    expect(onRenovarContrato).toHaveBeenCalledWith(contrato)
  })

  it('explica un bloqueo comercial, deshabilita sus acciones y las enlaza al motivo accesible', () => {
    montar({
      datos: detalleBase(),
      props: {
        operable: false,
        motivoNoOperable: 'Asigna un analista activo antes de continuar.',
        onGestionar: vi.fn(),
        onNuevoContrato: vi.fn(),
      },
    })

    const motivo = screen.getByText('Asigna un analista activo antes de continuar.')
    expect(motivo.id).not.toBe('')

    const nuevaInversion = screen.getByRole('button', { name: 'Registrar primera inversión' })
    const agendar = screen.getByRole('button', { name: 'Agendar seguimiento' })
    expect(nuevaInversion).toBeDisabled()
    expect(agendar).toBeDisabled()
    expect(nuevaInversion).toHaveAttribute('aria-describedby', motivo.id)
    expect(agendar).toHaveAttribute('aria-describedby', motivo.id)
  })

  it('mantiene el lenguaje visible en términos comerciales para el analista', () => {
    montar({ datos: detalleBase(), props: { onGestionar: vi.fn() } })
    const texto = screen.getByRole('dialog', { name: 'CLIENTE PORTAL UNO' }).textContent ?? ''
    expect(texto).toMatch(/Capital vigente/)
    expect(texto).toMatch(/Siguiente contacto/)
    expect(texto).toMatch(/Inversiones y contratos/)
    expect(texto).toMatch(/Cuentas para recibir pagos/)
    expect(texto).toMatch(/Historial de gestiones/)
    expect(texto).toMatch(/Agendar seguimiento/)
    expect(texto).not.toMatch(/\b(?:vendedor|asesor)\b/i)
    expect(texto).not.toMatch(/perfil_id|RPC|persistencia|scope|query|payload|endpoint|PostgREST/i)
  })

  it('ofrece contacto solo después de confirmar el detalle fresco y nunca usa los datos de la lista cacheada', async () => {
    let resolver!: (detalle: ClienteFichaComercial) => void
    obtenerFichaComercial.mockReturnValue(
      new Promise((resolve) => {
        resolver = resolve
      }),
    )
    listarCuentas.mockImplementation(() => new Promise(() => undefined))

    montar({
      grupo: {
        ...grupoBase('NOMBRE DE LA LISTA'),
        cliente: {
          ...grupoBase('NOMBRE DE LA LISTA').cliente,
          nombre_completo: 'NOMBRE DE LA LISTA',
          telefono: '911111111',
          correo: 'viejo@correo.pe',
        },
      },
    })

    expect(screen.queryByRole('link', { name: /Llamar a/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /WhatsApp/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /correo/i })).not.toBeInTheDocument()

    await act(async () => {
      resolver(
        fichaComercialBase({
          nombre_completo: 'CONTACTO CONFIRMADO',
          telefono: '988 777 666',
          correo: 'fresco@correo.pe',
        }),
      )
    })

    const llamar = await screen.findByRole('link', { name: 'Llamar a CONTACTO CONFIRMADO' })
    const whatsapp = screen.getByRole('link', { name: 'Abrir WhatsApp de CONTACTO CONFIRMADO' })
    const correo = screen.getByRole('link', { name: 'Escribir correo a CONTACTO CONFIRMADO' })
    expect(llamar).toHaveAttribute('href', 'tel:988777666')
    expect(whatsapp).toHaveAttribute('href', 'https://wa.me/988777666')
    expect(correo).toHaveAttribute('href', 'mailto:fresco@correo.pe')
    for (const enlace of [llamar, whatsapp, correo]) {
      expect(enlace).toHaveClass('h-10')
      expect(enlace).not.toHaveClass('md:h-8')
    }
    expect(screen.queryByRole('link', { name: 'Llamar a NOMBRE DE LA LISTA' })).not.toBeInTheDocument()
  })

  it('un error de validación oculta capital, contratos y seguimiento hasta recuperar el acceso', async () => {
    const contrato = contratoBase()
    const grupo: GrupoCartera = {
      ...grupoBase(),
      contratos: [contrato],
      capitalActivoPen: contrato.capital,
      contratosActivos: 1,
      tieneCapital: true,
      proximoVencimiento: contrato.fecha_vencimiento,
    }
    store.tareasDeCliente.mockReturnValue([tareaClienteBase({ titulo: 'Confirmar decisión de renovación' })])
    obtenerFichaComercial.mockRejectedValue(
      new crmApi.CrmApiError('No se pudo actualizar la información del cliente.', 'SIN_RED'),
    )

    montar({ grupo })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo actualizar la información del cliente.')
    expect(screen.queryByRole('region', { name: 'Continuidad comercial del cliente' })).not.toBeInTheDocument()
    expect(screen.queryByText('S/ 25,000')).not.toBeInTheDocument()
    expect(screen.queryByText('Confirmar decisión de renovación')).not.toBeInTheDocument()
    expect(screen.queryByText('2026-01-000321', { exact: false })).not.toBeInTheDocument()
    expect(screen.queryByText('Inversión 12 meses')).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Llamar a/ })).not.toBeInTheDocument()
  })

  it('avisa al contenedor y no ofrece reintento cuando el cliente ya no pertenece a la cartera', async () => {
    const onAccesoRevocado = vi.fn()
    obtenerFichaComercial.mockRejectedValue(
      new crmApi.CrmApiError('No encontramos este cliente en tu cartera.', 'NO_ENCONTRADO'),
    )

    montar({ props: { onAccesoRevocado } })

    expect(await screen.findByRole('alert')).toHaveTextContent('No encontramos este cliente en tu cartera.')
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Continuidad comercial del cliente' })).not.toBeInTheDocument()
    await waitFor(() => expect(onAccesoRevocado).toHaveBeenCalledOnce())
    expect(onAccesoRevocado).toHaveBeenCalledWith('cli-1')
  })

  it('trata un permiso revocado como salida inmediata de la cartera', async () => {
    const onAccesoRevocado = vi.fn()
    obtenerFichaComercial.mockRejectedValue(new crmApi.CrmApiError('Tu acceso cambió.', '42501'))

    montar({ props: { onAccesoRevocado } })

    expect(await screen.findByRole('alert')).toHaveTextContent('Tu acceso cambió.')
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    await waitFor(() => expect(onAccesoRevocado).toHaveBeenCalledWith('cli-1'))
  })

  it('espera la cartera actualizada si el servidor confirma otro analista', async () => {
    const onAsignacionDesactualizada = vi.fn()
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase({ asesor_perfil_id: 'analista-nuevo' }))

    montar({ props: { onAsignacionDesactualizada } })

    expect(await screen.findByRole('status')).toHaveTextContent('Estamos actualizando la asignación de este cliente.')
    expect(screen.queryByRole('region', { name: 'Continuidad comercial del cliente' })).not.toBeInTheDocument()
    await waitFor(() => expect(onAsignacionDesactualizada).toHaveBeenCalledWith('cli-1'))
  })

  it('focoInicial lleva el teclado a Siguiente contacto', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    montar({
      props: { focoInicial: 'siguiente-contacto' },
    })

    const siguienteContacto = await screen.findByRole('region', { name: 'Siguiente contacto' })
    await waitFor(() => expect(siguienteContacto).toHaveFocus())
  })

  it('focoInicial devuelve el teclado al contrato exacto desde el que se abrió otra vista', async () => {
    const contrato = contratoBase()
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    montar({
      grupo: {
        ...grupoBase(),
        contratos: [contrato],
        capitalActivoPen: contrato.capital,
        contratosActivos: 1,
        tieneCapital: true,
        proximoVencimiento: contrato.fecha_vencimiento,
      },
      props: {
        focoInicial: { tipo: 'contrato', contratoId: contrato.id },
        onDetalleContrato: vi.fn(),
      },
    })

    const verContrato = await screen.findByRole('button', { name: 'Ver contrato 2026-01-000321' })
    await waitFor(() => expect(verContrato).toHaveFocus())
  })

  it('si el contrato ya no está disponible, focoInicial vuelve al bloque de inversiones', async () => {
    montar({
      datos: detalleBase(),
      props: { focoInicial: { tipo: 'contrato', contratoId: 'contrato-ya-no-visible' } },
    })

    const inversiones = screen.getByRole('region', { name: 'Inversiones y contratos' })
    await waitFor(() => expect(inversiones).toHaveFocus())
  })

  it('muestra identidad sin domicilio y las cuentas que autoriza su consulta específica', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    cuentasPorMoneda(
      [cuentaRpc()],
      [
        cuentaRpc({
          cuenta_id: 'cta-usd-1',
          moneda: 'USD',
          banco: 'Interbank',
          tipo_cuenta: 'corriente',
          numero_cuenta: '2003001234567',
          cci: '00320030012345678901',
          titular_distinto: true,
          beneficiario_nombre: 'JUANA PÉREZ DEMO',
          beneficiario_dni: '87654321',
          origen: 'contrato',
        }),
      ],
    )
    montar()

    expect(screen.getByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    expect(await screen.findByText('cliente1@correo.pe')).toBeInTheDocument()
    expect(screen.getByText('999111222')).toBeInTheDocument()
    expect(screen.queryByText('Domicilio legal')).not.toBeInTheDocument()
    expect(screen.queryByText('Av. Javier Prado Este 123, San Isidro, Lima')).not.toBeInTheDocument()

    const pen = await screen.findByRole('region', { name: 'Cuenta para recibir pagos en soles' })
    expect(within(pen).getByText('BCP')).toBeInTheDocument()
    expect(within(pen).getByText('19112345678901')).toBeInTheDocument()
    expect(within(pen).getByText('00219112345678901234')).toBeInTheDocument()

    const usd = screen.getByRole('region', { name: 'Cuenta para recibir pagos en dólares' })
    expect(within(usd).getByText('Interbank')).toBeInTheDocument()
    expect(within(usd).getByText('JUANA PÉREZ DEMO')).toBeInTheDocument()
    expect(within(usd).getByText('87654321')).toBeInTheDocument()
  })

  it('ESTADO DE PRODUCCIÓN: cliente legacy sin nombres separados y cuenta USD registrada al crear un contrato', async () => {
    // Réplica exacta del caso ORMESINDA JULCA (2026-08-11): nombres/apellidos
    // NULL, casillas USD del perfil vacías, y la cuenta USD SOLO en el ledger
    // (origen 'contrato'). Antes: «—» en nombres y «No registró una cuenta».
    obtenerFichaComercial.mockResolvedValue(
      fichaComercialBase({
        nombre_completo: 'ORMESINDA JULCA',
        nombres: null,
        apellidos: null,
      }),
    )
    cuentasPorMoneda(
      [cuentaRpc()],
      [
        cuentaRpc({
          cuenta_id: 'cta-usd-bbva',
          moneda: 'USD',
          banco: 'BBVA',
          tipo_cuenta: 'corriente',
          numero_cuenta: '72728282828282',
          cci: '27273827282828282828',
          origen: 'contrato',
          creada_en: '2026-08-11T19:36:47.000Z',
        }),
      ],
    )
    montar()

    const usd = await screen.findByRole('region', { name: 'Cuenta para recibir pagos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(within(usd).getByText('72728282828282')).toBeInTheDocument()
    expect(within(usd).getByText('Registrada el')).toBeInTheDocument()
    expect(within(usd).queryByText('No registró una cuenta en esta moneda.')).not.toBeInTheDocument()

    expect(screen.getByText('Nombres y apellidos')).toBeInTheDocument()
    // El nombre aparece en el título del diálogo Y en datos personales.
    expect(screen.getAllByText('ORMESINDA JULCA').length).toBeGreaterThanOrEqual(2)
    expect(screen.queryByText('Nombres')).not.toBeInTheDocument()
    expect(screen.queryByText('Apellidos')).not.toBeInTheDocument()
  })

  it('varias cuentas activas de la misma moneda se listan todas', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    cuentasPorMoneda(
      [],
      [
        cuentaRpc({ cuenta_id: 'cta-usd-1', moneda: 'USD', banco: 'BBVA', numero_cuenta: '72728282828282' }),
        cuentaRpc({ cuenta_id: 'cta-usd-2', moneda: 'USD', banco: 'Scotiabank', numero_cuenta: '9887766554433' }),
      ],
    )
    montar()

    const usd = await screen.findByRole('region', { name: 'Cuentas para recibir pagos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(within(usd).getByText('Scotiabank')).toBeInTheDocument()
  })

  it('no pinta una cuenta cacheada mientras la revalidación de esta apertura sigue pendiente', async () => {
    let resolver!: (detalle: ClienteFichaComercial) => void
    obtenerFichaComercial.mockReturnValue(
      new Promise((resolve) => {
        resolver = resolve
      }),
    )
    // La RPC de cuentas también queda en vuelo: su caché envenenada tampoco
    // debe pintarse jamás.
    listarCuentas.mockImplementation(() => new Promise(() => undefined))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteFichaComercial('cli-1'),
      fichaComercialBase({ nombre_completo: 'COPIA CACHEADA' }),
    )
    queryClient.setQueryData(
      crmQueryKeys.clienteDetalle('cli-1'),
      detalleBase({ nombre_completo: 'DETALLE SENSIBLE CACHEADO', domicilio: 'DOMICILIO SENSIBLE CACHEADO' }),
    )
    queryClient.setQueryData(crmQueryKeys.cuentasBancarias('cli-1', 'PEN'), [
      cuentaRpc({ cci: 'CCI-CACHE-VIEJO' as string }),
    ])

    montar({ queryClient })
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(screen.queryByText('DETALLE SENSIBLE CACHEADO')).not.toBeInTheDocument()
    expect(screen.queryByText('DOMICILIO SENSIBLE CACHEADO')).not.toBeInTheDocument()
    expect(screen.queryByText('CCI-CACHE-VIEJO')).not.toBeInTheDocument()

    resolver(fichaComercialBase({ nombre_completo: 'COPIA FRESCA' }))
    expect(await screen.findByText('COPIA FRESCA')).toBeInTheDocument()
    // El detalle confirmó, pero las cuentas siguen en vuelo: sección en espera,
    // nunca la copia envenenada.
    expect(screen.queryByText('CCI-CACHE-VIEJO')).not.toBeInTheDocument()
  })

  it('si falla la revalidación, muestra un error y nunca revela la ficha cacheada', async () => {
    obtenerFichaComercial.mockRejectedValue(
      new crmApi.CrmApiError('No se pudo actualizar la información comercial.', 'SIN_RED'),
    )
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteFichaComercial('cli-1'),
      fichaComercialBase({ nombre_completo: 'COPIA CACHEADA' }),
    )

    montar({ queryClient })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo actualizar la información comercial.')
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
  })

  it('un fallo de actualización conserva la última ficha confirmada y lo explica', async () => {
    obtenerFichaComercial
      .mockResolvedValueOnce(fichaComercialBase({ nombre_completo: 'CLIENTE CONFIRMADO' }))
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo refrescar la ficha.', 'SIN_RED'))
    const { queryClient } = montar()
    expect(await screen.findByText('CLIENTE CONFIRMADO')).toBeInTheDocument()

    await act(async () => {
      await queryClient.refetchQueries({ queryKey: crmQueryKeys.clienteFichaComercial('cli-1'), exact: true })
    })

    expect(await screen.findByRole('status')).toHaveTextContent(
      'No pudimos actualizar la ficha. Estás viendo la última información confirmada.',
    )
    expect(screen.getByText('CLIENTE CONFIRMADO')).toBeInTheDocument()
  })

  it('Reintentar mantiene oculto lo viejo y habilita la ficha solo al recibir una copia nueva', async () => {
    const user = userEvent.setup()
    obtenerFichaComercial
      .mockRejectedValueOnce(new crmApi.CrmApiError('Sin conexión.', 'SIN_RED'))
      .mockResolvedValueOnce(fichaComercialBase({ nombre_completo: 'CLIENTE ACTUALIZADO' }))
    const queryClient = clienteQuery()
    queryClient.setQueryData(
      crmQueryKeys.clienteFichaComercial('cli-1'),
      fichaComercialBase({ nombre_completo: 'COPIA CACHEADA' }),
    )
    montar({ queryClient })

    await user.click(await screen.findByRole('button', { name: 'Reintentar' }))

    expect(await screen.findByText('CLIENTE ACTUALIZADO')).toBeInTheDocument()
    expect(screen.queryByText('COPIA CACHEADA')).not.toBeInTheDocument()
    expect(obtenerFichaComercial).toHaveBeenCalledTimes(2)
    await waitFor(() => expect(screen.getByRole('region', { name: 'Información del cliente' })).toHaveFocus())
  })

  it('un fallo de refetch bancario posterior oculta las cuentas ya confirmadas', async () => {
    // El requisito espejo del de la ficha, para la sección bancaria: cuentas
    // confirmadas → refetch que falla → nada de CCI viejo a la vista.
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    cuentasPorMoneda([cuentaRpc()], [])
    const { queryClient } = montar()
    expect(await screen.findByText('00219112345678901234')).toBeInTheDocument()

    listarCuentas.mockRejectedValue(
      new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'SIN_RED'),
    )
    await act(async () => {
      await queryClient.refetchQueries({ queryKey: crmQueryKeys.cuentasBancarias('cli-1', 'PEN'), exact: true })
    })

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'No se pudieron cargar las cuentas bancarias del cliente.',
    )
    expect(screen.queryByText('00219112345678901234')).not.toBeInTheDocument()
    // La identidad, confirmada por su propia consulta, sigue a la vista.
    expect(screen.getByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
  })

  it('si fallan las cuentas, la identidad sigue visible y la sección bancaria reintenta por su cuenta', async () => {
    const user = userEvent.setup()
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarCuentas
      .mockRejectedValueOnce(
        new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'),
      )
      .mockRejectedValueOnce(
        new crmApi.CrmApiError('No se pudieron cargar las cuentas bancarias del cliente.', 'POSTGREST_ERROR'),
      )
      .mockImplementation(async (_clienteId, moneda) =>
        moneda === 'USD' ? [cuentaRpc({ cuenta_id: 'cta-usd-1', moneda: 'USD', banco: 'BBVA' })] : [],
      )
    montar()

    // La identidad NO se bloquea por el fallo bancario (hay lectores válidos de
    // la ficha a los que el gate de cartera de la RPC puede negar).
    expect(await screen.findByRole('region', { name: 'Información del cliente' })).toBeInTheDocument()
    expect(screen.getByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('No se pudieron cargar las cuentas bancarias del cliente.')

    await user.click(within(alerta).getByRole('button', { name: 'Reintentar' }))

    const usd = await screen.findByRole('region', { name: 'Cuenta para recibir pagos en dólares' })
    expect(within(usd).getByText('BBVA')).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('region', { name: 'Cuentas para recibir pagos' })).toHaveFocus())
  })

  it('sin permiso bancario no consulta cuentas ni muestra esa sección', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    const queryClient = clienteQuery()
    queryClient.setQueryData(crmQueryKeys.cuentasBancarias('cli-1', 'PEN'), [
      cuentaRpc({ numero_cuenta: 'CUENTA-SENSIBLE-CACHEADA' }),
    ])

    montar({ queryClient, props: { puedeVerCuentas: false } })

    expect(await screen.findByText('cliente1@correo.pe')).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Cuentas para recibir pagos' })).not.toBeInTheDocument()
    expect(screen.queryByText('CUENTA-SENSIBLE-CACHEADA')).not.toBeInTheDocument()
    await waitFor(() => expect(listarCuentas).not.toHaveBeenCalled())
  })

  it('Directorio conserva identidad y datos, pero no expone acciones externas de contacto', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    montar({ props: { puedeVerCuentas: false, puedeContactar: false } })

    expect(await screen.findByRole('region', { name: 'Información del cliente' })).toBeInTheDocument()
    expect(screen.getByText('CLIENTE PORTAL UNO')).toBeInTheDocument()
    expect(screen.getByText('cliente1@correo.pe')).toBeInTheDocument()
    expect(screen.getByText('999111222')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Llamar a/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /WhatsApp/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Escribir correo/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Cuentas para recibir pagos' })).not.toBeInTheDocument()
  })

  it('la ficha demo mantiene su marca y permite dos líneas para un nombre largo', () => {
    const nombre = 'BRUNO ALEXIS FONSECA IPARRAGUIRRE'
    montar({
      datos: detalleBase({ nombre_completo: nombre }),
      grupo: grupoBase(nombre),
      props: { demo: true },
    })

    expect(screen.getByText('Vista demo')).toBeVisible()
    const titulo = screen.getByRole('heading', { level: 2, name: nombre })
    expect(titulo).toHaveClass('line-clamp-2')
    expect(titulo).not.toHaveClass('truncate')
  })

  it('al reintentar el historial devuelve el teclado a esa sección', async () => {
    const user = userEvent.setup()
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarActividades
      .mockRejectedValueOnce(new crmApi.CrmApiError('No se pudo cargar el historial comercial.', 'SIN_RED'))
      .mockResolvedValueOnce([])
    montar()

    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent('No pudimos actualizar las conversaciones. Los demás movimientos siguen visibles.')
    await user.click(within(alerta).getByRole('button', { name: 'Reintentar' }))

    expect(await screen.findByText('Aún no hay gestiones registradas.', { exact: false })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('region', { name: 'Historial de gestiones' })).toHaveFocus())
  })

  it('ordena conversaciones, reasignaciones, renovaciones y aumentos en un solo historial', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarActividades.mockResolvedValue([
      {
        id: 'actividad-reasignacion',
        cliente_id: 'cli-1',
        vendedor_id: null,
        tarea_id: null,
        tipo: 'reasignacion',
        detalle: 'Cliente reasignado a ASESOR.',
        creado_por: null,
        creado_en: '2026-08-25T16:00:00.000Z',
      },
      {
        id: 'actividad-llamada',
        cliente_id: 'cli-1',
        vendedor_id: 'yo',
        tarea_id: null,
        tipo: 'llamada_realizada',
        detalle: 'Confirmó que revisará la propuesta.',
        creado_por: 'yo',
        creado_en: '2026-08-25T14:00:00.000Z',
      },
    ])
    const operaciones: OperacionCartera[] = [
      {
        id: 'op-renovacion',
        cliente_id: 'cli-1',
        vendedor_id: 'yo',
        tipo: 'renovacion',
        contrato_origen_id: 'contrato-anterior',
        contrato_nuevo_id: 'contrato-1',
        fecha_operacion: '2026-08-25',
        periodo: '2026-08-01',
        moneda: 'PEN',
        capital_renovado: 20_000,
        capital_adicional: 5_000,
        elegible_conversion: true,
        desglose_completo: true,
        fuente: 'flujo_cartera',
        creado_por: 'yo',
        creado_en: '2026-08-25T15:00:00.000Z',
      },
    ]

    montar({ props: { operaciones } })

    const historial = await screen.findByRole('region', { name: 'Historial de gestiones' })
    let eventos: Array<string | null> = []
    await waitFor(() => {
      eventos = within(historial)
        .getAllByRole('listitem')
        .map((item) => item.textContent)
      expect(eventos).toHaveLength(3)
    })
    expect(eventos).toHaveLength(3)
    expect(eventos[0]).toContain('Asignación actualizada')
    expect(eventos[1]).toContain('Renovación registrada')
    expect(eventos[1]).toContain('Capital renovado: S/ 20,000')
    expect(eventos[1]).toContain('Aporte adicional: S/ 5,000')
    expect(eventos[2]).toContain('Llamada contestada')
  })

  it('en una renovación anterior sin desglose explica la limitación y no inventa montos', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    const operaciones: OperacionCartera[] = [
      {
        id: 'op-renovacion-anterior',
        cliente_id: 'cli-1',
        vendedor_id: 'yo',
        tipo: 'renovacion',
        contrato_origen_id: null,
        contrato_nuevo_id: 'contrato-1',
        fecha_operacion: '2026-08-01',
        periodo: '2026-08-01',
        moneda: 'PEN',
        // Aunque una fuente antigua trajera cifras parciales, la bandera manda:
        // no deben presentarse como un desglose confirmado.
        capital_renovado: 20_000,
        capital_adicional: 5_000,
        elegible_conversion: true,
        desglose_completo: false,
        fuente: 'backfill_agosto_2026',
        creado_por: 'yo',
        creado_en: '2026-08-01T15:00:00.000Z',
      },
    ]

    montar({ props: { operaciones } })

    const historial = await screen.findByRole('region', { name: 'Historial de gestiones' })
    expect(
      within(historial).getByText('Renovación anterior. El detalle de los montos no está disponible.'),
    ).toBeInTheDocument()
    expect(within(historial).queryByText(/Capital renovado:/)).not.toBeInTheDocument()
    expect(within(historial).queryByText(/Aporte adicional:/)).not.toBeInTheDocument()
    expect(within(historial).queryByText(/S\/ 20,000|S\/ 5,000/)).not.toBeInTheDocument()
  })

  it('mantiene las gestiones visibles mientras confirma los movimientos de inversión', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarActividades.mockResolvedValue([
      {
        id: 'actividad-disponible',
        cliente_id: 'cli-1',
        vendedor_id: 'yo',
        tarea_id: null,
        tipo: 'llamada_realizada',
        detalle: 'El cliente pidió una propuesta actualizada.',
        creado_por: 'yo',
        creado_en: '2026-08-25T14:00:00.000Z',
      },
    ])

    montar({ props: { movimientosInversionPendientes: true } })

    expect(await screen.findByText('El cliente pidió una propuesta actualizada.')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Actualizando el historial del cliente…')
    expect(screen.queryByText('Aún no hay gestiones registradas.', { exact: false })).not.toBeInTheDocument()
  })

  it('separa los avisos de conversaciones y movimientos cuando ambas fuentes fallan', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarActividades.mockRejectedValue(new crmApi.CrmApiError('No se pudo cargar el historial comercial.', 'SIN_RED'))

    montar({
      props: {
        movimientosInversionDesactualizados: { reintentar: vi.fn() },
      },
    })

    let alertas: HTMLElement[] = []
    await waitFor(() => {
      alertas = screen.getAllByRole('alert')
      expect(alertas).toHaveLength(2)
    })
    expect(alertas[0]).toHaveTextContent('No pudimos actualizar las conversaciones.')
    expect(alertas[1]).toHaveTextContent('No pudimos mostrar las renovaciones y aumentos en este momento.')
    expect(screen.queryByText('Aún no hay gestiones registradas.', { exact: false })).not.toBeInTheDocument()
  })

  it('avisa si no puede confirmar renovaciones y aumentos sin ocultar las conversaciones', async () => {
    const user = userEvent.setup()
    const reintentar = vi.fn()
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    listarActividades.mockResolvedValue([
      {
        id: 'actividad-1',
        cliente_id: 'cli-1',
        vendedor_id: 'yo',
        tarea_id: null,
        tipo: 'nota',
        detalle: 'Cliente interesado en renovar.',
        creado_por: 'yo',
        creado_en: '2026-08-25T14:00:00.000Z',
      },
    ])

    montar({ props: { movimientosInversionDesactualizados: { reintentar } } })

    expect(await screen.findByText('Cliente interesado en renovar.')).toBeInTheDocument()
    const alerta = screen.getByRole('alert')
    expect(alerta).toHaveTextContent('No pudimos mostrar las renovaciones y aumentos en este momento.')
    expect(screen.queryByText('Aún no hay gestiones registradas.', { exact: false })).not.toBeInTheDocument()
    await user.click(within(alerta).getByRole('button', { name: 'Reintentar' }))
    expect(reintentar).toHaveBeenCalledOnce()
  })

  it('explica por separado cuando no existe una cuenta PEN ni USD', async () => {
    obtenerFichaComercial.mockResolvedValue(fichaComercialBase())
    cuentasPorMoneda([], [])
    montar()

    await screen.findByText('CLIENTE PORTAL UNO')
    const pen = await screen.findByRole('region', { name: 'Cuenta para recibir pagos en soles' })
    const usd = screen.getByRole('region', { name: 'Cuenta para recibir pagos en dólares' })
    expect(within(pen).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
    expect(within(usd).getByText('No registró una cuenta en esta moneda.')).toBeInTheDocument()
  })

  it('con datos demo pinta de inmediato (cuentas embebidas incluidas), no llama a la API y permite cerrar', async () => {
    const user = userEvent.setup()
    const { onCerrar } = montar({ datos: detalleBase({ nombre_completo: 'CLIENTE FICTICIO DEMO' }) })

    expect(screen.getByText('CLIENTE FICTICIO DEMO')).toBeInTheDocument()
    // En demo las cuentas salen de las casillas embebidas del fixture.
    const pen = screen.getByRole('region', { name: 'Cuenta para recibir pagos en soles' })
    expect(within(pen).getByText('BCP')).toBeInTheDocument()
    const usd = screen.getByRole('region', { name: 'Cuenta para recibir pagos en dólares' })
    expect(within(usd).getByText('Interbank')).toBeInTheDocument()
    await waitFor(() => expect(obtenerFichaComercial).not.toHaveBeenCalled())
    expect(listarCuentas).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Cerrar' }))
    expect(onCerrar).toHaveBeenCalledOnce()
  })
})
