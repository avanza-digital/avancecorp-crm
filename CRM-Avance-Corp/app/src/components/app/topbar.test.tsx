// Tests del buscador del topbar: que PROMETA solo lo que busca. Prometía «lead o
// cliente» y solo miraba leads, así que un cliente de la propia cartera salía
// como «Sin resultados» (el CRM negando a alguien que sí existe). Aquí se fija
// el contrato: textos de leads, vacío acotado y la pantalla REAL del cliente
// nombrada con el rótulo que ese rol ve en su menú.
// Contextos mockeados a mano (sin red): el topbar solo consume `yo`, el ámbito y
// las acciones de paneles.
import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AlertaCRM } from '@/lib/alertas'
import type { Rol } from '@/lib/roles'
import type { Lead } from '@/lib/tipos'
import type { Vista } from '@/lib/router'

let YO: { id: string; nombre_completo: string; rol: Rol; demo: boolean } | null = null
let LEADS: Lead[] = []
let ALERTAS: AlertaCRM[] = []
let CARGANDO_ALERTAS = false
let ERRORES_ALERTAS: string[] = []
const abrirLead = vi.fn()
const abrirNuevoLead = vi.fn()

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: LEADS, vendedores: [], esGlobal: false } }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead }),
}))
vi.mock('@/lib/alertas-context', () => ({
  useAlertasCRM: () => ({
    alertas: ALERTAS,
    rol: YO?.rol ?? null,
    cargando: CARGANDO_ALERTAS,
    errores: ERRORES_ALERTAS,
    generadoEn: null,
    reintentar: vi.fn(),
  }),
}))

const { Topbar } = await import('./topbar')

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'JUAN PEREZ ROJAS',
    telefono: '+51999888777',
    correo: null,
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 50_000,
    moneda: 'PEN',
    categoria_interes: null,
    vendedor_id: 'u-v1',
    vendedor_nombre: 'Vendedor Real',
    asignado_supervisor_id: null,
    creado_en: '2026-07-01T00:00:00.000Z',
    activo: true,
    dni: null,
    distrito: null,
    nota: null,
    motivo_descarte: null,
    ...over,
  }
}

function montar({
  rol = 'vendedor' as Rol,
  vista = 'hoy' as Vista,
  leads = [lead()],
  alertas = [],
  demo = true,
}: { rol?: Rol; vista?: Vista; leads?: Lead[]; alertas?: AlertaCRM[]; demo?: boolean } = {}) {
  // demo:true = el gate FUNCIONES_LEADS_APROBADAS deja ver el buscador sin
  // depender de la bandera de config (que cambia con la aprobación de Miguel).
  // `demo: false` es el mundo REAL de producción, y es donde vivía el bug de la
  // campana: TODAS las pruebas de aquí corrían en demo, así que ninguna podía
  // verlo.
  YO = { id: 'u-v1', nombre_completo: 'Vendedor Real', rol, demo }
  LEADS = leads
  ALERTAS = alertas
  CARGANDO_ALERTAS = false
  ERRORES_ALERTAS = []
  return render(<Topbar vista={vista} />)
}

function alerta(over: Partial<AlertaCRM> = {}): AlertaCRM {
  return {
    id: 'tarea_vencida:lead-1',
    tipo: 'tarea_vencida',
    severidad: 'critica',
    alcance: 'personal',
    titulo: 'Tarea vencida',
    detalle: 'La llamada venció hace 1 día.',
    responsableId: 'u-v1',
    responsable: 'Vendedor Real',
    valor: 24,
    destino: { vista: 'agenda', leadId: 'lead-1', etiqueta: 'Abrir en Agenda' },
    ...over,
  }
}

const campoBusqueda = () =>
  screen.getByRole('combobox', { name: 'Buscar lead por nombre, teléfono o DNI' })

describe('Topbar — buscador', () => {
  it('promete SOLO leads: ni el placeholder ni el aria-label hablan de clientes', () => {
    montar()
    const campo = campoBusqueda()
    expect(campo).toHaveAttribute('placeholder', 'Buscar lead…')
    expect(campo.getAttribute('placeholder')).not.toMatch(/cliente/i)
    expect(campo.getAttribute('aria-label')).not.toMatch(/cliente/i)
  })

  it('encuentra un lead del ámbito por nombre y al elegirlo abre su ficha', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(campoBusqueda(), 'perez')
    await user.click(await screen.findByRole('button', { name: /JUAN PEREZ ROJAS/ }))
    expect(abrirLead).toHaveBeenCalledWith('lead-1')
  })

  it('sin coincidencias: acota el vacío a los leads y nombra la pantalla del cliente', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(campoBusqueda(), 'zzz')
    // "Sin resultados" a secas se leía como "esa persona no existe".
    expect(screen.getByText(/Sin resultados en tus leads para «zzz»/)).toBeInTheDocument()
    // Al vendedor su menú le rotula la cartera "Mi cartera": así se le nombra.
    expect(screen.getByText(/Búscalo en «Mi cartera», en el menú lateral/)).toBeInTheDocument()
  })

  it('quien supervisa lee el rótulo de SU menú («Cartera»)', async () => {
    const user = userEvent.setup()
    montar({ rol: 'supervisor' })
    await user.type(campoBusqueda(), 'zzz')
    expect(screen.getByText(/Búscalo en «Cartera», en el menú lateral/)).toBeInTheDocument()
  })

  it('a quien NO tiene cartera (coordinador) no se le manda a una pantalla que no ve', async () => {
    const user = userEvent.setup()
    montar({ rol: 'coordinador' })
    await user.type(campoBusqueda(), 'zzz')
    expect(screen.getByText(/Sin resultados en tus leads/)).toBeInTheDocument()
    expect(screen.queryByText(/menú lateral/)).not.toBeInTheDocument()
  })

  it('el título de la cartera usa el MISMO rótulo por rol que el resto del CRM', () => {
    const { unmount } = montar({ vista: 'mi-cartera' })
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Mi cartera')
    unmount()
    montar({ rol: 'gerencia', vista: 'mi-cartera' })
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Cartera')
  })
})

describe('Topbar — pendientes por responsabilidad', () => {
  it('presenta la ruta con título, conteo real y estado actual', () => {
    montar({ rol: 'gerencia', vista: 'alertas', leads: [], alertas: [alerta()] })

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Pendientes')
    expect(screen.getByText('Acciones y señales que requieren tu atención')).toBeVisible()
    const enlace = screen.getByRole('link', { name: 'Abrir pendientes: 1 activo' })
    expect(enlace).toHaveAttribute('href', '#/alertas')
    expect(enlace).toHaveAttribute('aria-current', 'page')
    expect(enlace).toHaveTextContent('1')
  })

  it.each(['vendedor', 'supervisor', 'gerencia'] as const)(
    'habilita la campana real para %s',
    (rol) => {
      montar({ rol, vista: 'hoy', leads: [] })

      expect(screen.getByRole('link', { name: 'Abrir pendientes' })).toHaveAttribute(
        'href',
        '#/alertas',
      )
    },
  )

  // ── El bug de la campana muerta (2026-08-09) ──────────────────────────────
  // La campana se PINTABA con `can(rol,'verAlertas')` —que vendedor y supervisor
  // tienen— mientras el router exige ADEMÁS el gate de leads. En producción, con
  // `FUNCIONES_LEADS_APROBADAS = false`, el clic intentaba ir a #/alertas,
  // `sanearVista` devolvía al usuario a su landing con `replaceState` (que no
  // redispara hashchange) y no ocurría NADA: ni error, ni cambio de pantalla.
  // Un enlace muerto, encima con burbuja roja. Estas dos pruebas son las que
  // faltaban: las demás corren en demo, un mundo donde el gate está abierto.
  it.each(['vendedor', 'supervisor'] as const)(
    'sesión REAL con el gate de leads cerrado: %s NO ve la campana (no la vería funcionar)',
    (rol) => {
      montar({ rol, vista: 'mi-cartera', leads: [], demo: false })

      expect(screen.queryByRole('link', { name: /Abrir pendientes/ })).not.toBeInTheDocument()
    },
  )

  it('sesión REAL: gerencia SÍ conserva la campana (su vista de alertas no depende del gate)', () => {
    montar({ rol: 'gerencia', vista: 'hoy', leads: [], demo: false })

    expect(screen.getByRole('link', { name: 'Abrir pendientes' })).toHaveAttribute('href', '#/alertas')
  })

  it.each(['directorio', 'coordinador'] as const)(
    'no muestra una bandeja sin responsabilidad definida a %s',
    (rol) => {
      montar({ rol, vista: 'hoy', leads: [] })

      expect(screen.queryByRole('link', { name: /Abrir pendientes/ })).not.toBeInTheDocument()
    },
  )

  it('limita visualmente el conteo sin perder el total accesible', () => {
    montar({
      rol: 'supervisor',
      alertas: Array.from({ length: 105 }, (_, indice) => alerta({ id: `alerta-${indice}` })),
    })

    const enlace = screen.getByRole('link', { name: 'Abrir pendientes: 105 activos' })
    expect(enlace).toHaveTextContent('99+')
  })
})

// ── Fase 1 del plan «lead libre»: la puerta de la verificación por contacto ──
// Mutante que debe morir aquí: quitar el gate puedeEscribir del atajo (el
// directorio podría abrir el alta) o aflojar esPosibleTelefono a «cualquier
// texto» (el atajo saldría al buscar un nombre).
describe('Topbar — atajo «Verificar disponibilidad»', () => {
  it('con un teléfono tecleado y sin resultados, ofrece verificar y abre el alta precargada', async () => {
    const user = userEvent.setup()
    montar({ leads: [] })
    await user.type(campoBusqueda(), '987 654 321')

    const atajo = screen.getByRole('button', { name: /Verificar disponibilidad/ })
    await user.click(atajo)
    expect(abrirNuevoLead).toHaveBeenCalledWith(undefined, '987 654 321')
  })

  it('no aparece para texto que no parece teléfono', async () => {
    const user = userEvent.setup()
    montar({ leads: [] })
    await user.type(campoBusqueda(), 'juan perez')
    expect(screen.queryByRole('button', { name: /Verificar disponibilidad/ })).not.toBeInTheDocument()
  })

  it('el directorio mira pero no verifica: sin atajo aunque teclee un teléfono', async () => {
    const user = userEvent.setup()
    montar({ leads: [], rol: 'directorio' })
    await user.type(campoBusqueda(), '987654321')
    expect(screen.queryByRole('button', { name: /Verificar disponibilidad/ })).not.toBeInTheDocument()
  })

  // Honestidad 2026-08-17 (hallazgo de Miguel): un DNI pasa el «parece teléfono»
  // (≥6 dígitos), el atajo abría el alta con el DNI en el campo TELÉFONO y el
  // precheck jamás corría — ese silencio se leía como «libre». Mutante que debe
  // morir aquí: quitar el gate normalizarTelefono y ofrecer el botón siempre.
  it('un DNI (8 dígitos) NO ofrece verificar: dice que la verificación es por celular', async () => {
    const user = userEvent.setup()
    montar({ leads: [] })
    await user.type(campoBusqueda(), '46736918')

    expect(screen.queryByRole('button', { name: /Verificar disponibilidad/ })).not.toBeInTheDocument()
    expect(screen.getByText(/se verifica con el celular/i)).toBeInTheDocument()
  })

  it('el directorio no ve ni el atajo ni la explicación: no verifica', async () => {
    const user = userEvent.setup()
    montar({ leads: [], rol: 'directorio' })
    await user.type(campoBusqueda(), '46736918')

    expect(screen.queryByRole('button', { name: /Verificar disponibilidad/ })).not.toBeInTheDocument()
    expect(screen.queryByText(/se verifica con el celular/i)).not.toBeInTheDocument()
  })
})
