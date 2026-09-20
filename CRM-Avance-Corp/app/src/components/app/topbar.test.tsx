// Tests del buscador del topbar: que PROMETA solo lo que busca. Prometía «lead o
// cliente» y solo miraba leads, así que un cliente de la propia cartera salía
// como «Sin resultados» (el CRM negando a alguien que sí existe). Aquí se fija
// el contrato: textos de leads, vacío acotado y la pantalla REAL del cliente
// nombrada con el rótulo que ese rol ve en su menú.
// Contextos mockeados a mano (sin red): el topbar solo consume `yo`, el ámbito y
// las acciones de paneles.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { AlertaCRM } from '@/lib/alertas'
import { funcionesLeadsVisibles } from '@/lib/config'
import type { Rol } from '@/lib/roles'
import { vistaPermitida } from '@/lib/vistas'
import type { Lead } from '@/lib/tipos'
import type { Vista } from '@/lib/router'

let YO: { id: string; nombre_completo: string; rol: Rol; demo: boolean } | null = null
let LEADS: Lead[] = []
let ALERTAS: AlertaCRM[] = []
let CARGANDO_ALERTAS = false
let ERRORES_ALERTAS: string[] = []
const abrirLead = vi.fn()
const abrirNuevoLead = vi.fn()
// Fase 4a «sin topes»: el buscador de la sesión REAL pregunta al servidor por
// este hook; la demo lo deja apagado (habilitada=false) y filtra su foto local.
let BUSQUEDA: { data: Lead[] | undefined; isFetching: boolean; isPlaceholderData?: boolean; error: Error | null; refetch: ReturnType<typeof vi.fn> } = {
  data: undefined, isFetching: false, error: null, refetch: vi.fn(),
}
const useBusquedaGlobal = vi.fn((_texto: string | null, _habilitada: boolean) => BUSQUEDA)
vi.mock('@/data/crm-queries', () => ({ useBusquedaGlobal: (texto: string | null, habilitada: boolean) => useBusquedaGlobal(texto, habilitada) }))

vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: YO }) }))
vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({
    // Fase 4e: el store conoce lo que la pantalla muestra (aquí, sin efecto).
    conocerLeads: () => {}, asegurarLead: async () => true, ambito: { leads: LEADS, vendedores: [], esGlobal: false } }),
  usePanelesActions: () => ({ abrirLead, abrirNuevoLead }),
}))
vi.mock('@/lib/alertas-context', () => ({
  useAlertasCRM: () => ({
    alertas: ALERTAS,
    // Como el provider real (F4): la campana cuenta lo que PIDE acción.
    pendientes: ALERTAS.filter((fila) => fila.reconocimiento == null).length,
    rol: YO?.rol ?? null,
    cargando: CARGANDO_ALERTAS,
    errores: ERRORES_ALERTAS,
    generadoEn: null,
    reintentar: vi.fn(),
    reconocer: vi.fn(),
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
    vendedor_nombre: 'Analista Real',
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
  YO = { id: 'u-v1', nombre_completo: 'Analista Real', rol, demo }
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
    responsable: 'Analista Real',
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
    // Al analista su menú le rotula la cartera "Mi cartera": así se le nombra.
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
    expect(screen.getByText(/Sin resultados en tus leads/, { selector: 'p:not(.sr-only)' })).toBeInTheDocument()
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
  // La campana se PINTABA con `can(rol,'verAlertas')` —que analista y supervisor
  // tienen— mientras el router exige ADEMÁS el gate de leads. En producción, con
  // la llave cerrada, el clic intentaba ir a #/alertas, `sanearVista` devolvía al
  // usuario a su landing con `replaceState` (que no redispara hashchange) y no
  // ocurría NADA: ni error, ni cambio de pantalla. Un enlace muerto con burbuja
  // roja. Al abrirse la llave (2026-08-18) la campana de la fuerza de ventas ya
  // lleva a algún sitio, así que lo que se fija aquí es el ACOPLE —lo que faltaba
  // entonces y sobrevive a cualquier futuro giro de la llave—: se pinta si y solo
  // si el router deja abrir #/alertas para ese rol.
  it.each(['vendedor', 'supervisor'] as const)(
    'sesión REAL: la campana de %s se pinta Y el router le abre #/alertas (nunca un enlace muerto)',
    (rol) => {
      montar({ rol, vista: 'mi-cartera', leads: [], demo: false })

      const campana = screen.queryByRole('link', { name: /Abrir pendientes/ })
      const alcanzable = vistaPermitida('alertas', rol, funcionesLeadsVisibles(false, rol))
      expect(campana != null).toBe(alcanzable)
      // Y cuando se pinta, apunta a la bandeja de verdad (no a un ancla muerta).
      if (campana != null) expect(campana).toHaveAttribute('href', '#/alertas')
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

describe('Topbar — buscador en sesión REAL (Fase 4a «sin topes»)', () => {
  beforeEach(() => {
    BUSQUEDA = { data: undefined, isFetching: false, error: null, refetch: vi.fn() }
    useBusquedaGlobal.mockClear()
  })

  it('la demo no pregunta al servidor: el hook queda apagado y la foto local responde', async () => {
    const user = userEvent.setup()
    montar()
    await user.type(campoBusqueda(), 'perez')
    await screen.findByRole('button', { name: /JUAN PEREZ ROJAS/ })
    expect(useBusquedaGlobal).toHaveBeenLastCalledWith(null, false)
  })

  it('pide al servidor el texto asentado y pinta lo que responde, nunca la foto local', async () => {
    const user = userEvent.setup()
    BUSQUEDA.data = [lead({ id: 'srv-1', nombre_completo: 'JUANA DEL SERVIDOR' })]
    montar({ rol: 'gerencia', demo: false, leads: [lead({ id: 'local-1', nombre_completo: 'JUANA LOCAL NO SALE' })] })
    await user.type(campoBusqueda(), 'jua')
    await waitFor(() => expect(useBusquedaGlobal).toHaveBeenLastCalledWith('jua', true))
    await user.click(await screen.findByRole('button', { name: /JUANA DEL SERVIDOR/ }))
    expect(abrirLead).toHaveBeenCalledWith('srv-1')
    expect(screen.queryByText(/JUANA LOCAL NO SALE/)).not.toBeInTheDocument()
  })

  it('por debajo del mínimo no pide nada y lo explica', async () => {
    const user = userEvent.setup()
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'j')
    expect(await screen.findByText(/Escribe al menos 2 letras, o 3 dígitos/, { selector: 'p:not(.sr-only)' })).toBeInTheDocument()
    await waitFor(() => expect(useBusquedaGlobal).toHaveBeenLastCalledWith(null, true))
  })

  it('mientras el servidor responde, lo dice en vez de fingir «sin resultados»', async () => {
    const user = userEvent.setup()
    BUSQUEDA.isFetching = true
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'jua')
    expect(await screen.findByRole('status')).toHaveTextContent('Buscando en tus leads…')
    expect(screen.queryByText(/Sin resultados/)).not.toBeInTheDocument()
    expect(document.getElementById('topbar-busqueda-lista')).not.toBeNull()
  })

  it('anuncia el desenlace en la región viva: cuántos resultados o que no hubo', async () => {
    const user = userEvent.setup()
    BUSQUEDA.data = [lead({ id: 'srv-1', nombre_completo: 'JUANA DEL SERVIDOR' })]
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'jua')
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('1 resultado. Usa las flechas'))
    expect(campoBusqueda()).toHaveAttribute('aria-activedescendant', 'topbar-busqueda-op-srv-1')
    BUSQUEDA = { ...BUSQUEDA, data: [] }
    await user.type(campoBusqueda(), 'n')
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Sin resultados en tus leads.'))
  })

  it('con el error a la vista, Enter reintenta sin sacar el foco del buscador', async () => {
    const user = userEvent.setup()
    BUSQUEDA.error = new Error('No se pudo buscar en tus leads.')
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'jua')
    expect(await screen.findByRole('alert')).toHaveTextContent('Pulsa Enter para reintentar')
    await user.keyboard('{Enter}')
    expect(BUSQUEDA.refetch).toHaveBeenCalledTimes(1)
    await user.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(BUSQUEDA.refetch).toHaveBeenCalledTimes(2)
    expect(campoBusqueda()).toHaveFocus()
  })

  it('no deja elegir con Enter ni con las flechas un resultado de un texto anterior (Codex 20/09)', async () => {
    const user = userEvent.setup()
    // La consulta del texto nuevo aún no respondió: lo que hay es la lista del texto anterior.
    BUSQUEDA = { ...BUSQUEDA, data: [lead({ id: 'srv-vieja', nombre_completo: 'ANA DEL TEXTO ANTERIOR' })], isFetching: true, isPlaceholderData: true }
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'rosa')
    await waitFor(() => expect(useBusquedaGlobal).toHaveBeenLastCalledWith('rosa', true))
    expect(screen.queryByRole('option')).not.toBeInTheDocument()
    expect(campoBusqueda()).not.toHaveAttribute('aria-activedescendant')
    await user.keyboard('{ArrowDown}{Enter}')
    expect(abrirLead).not.toHaveBeenCalled()
    expect(screen.getByText('Buscando en tus leads…', { selector: 'p:not(.sr-only)' })).toBeInTheDocument()
  })

  it('con un solo carácter no reaparece la lista de la consulta anterior', async () => {
    const user = userEvent.setup()
    BUSQUEDA.data = [lead({ id: 'srv-1', nombre_completo: 'JUANA DEL SERVIDOR' })]
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'j')
    expect(screen.queryByRole('option')).not.toBeInTheDocument()
    await user.keyboard('{Enter}')
    expect(abrirLead).not.toHaveBeenCalled()
  })

  it('mientras reintenta, enseña «Buscando…» y no el error viejo', async () => {
    const user = userEvent.setup()
    BUSQUEDA.error = new Error('No se pudo buscar en tus leads.')
    BUSQUEDA.isFetching = true
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'jua')
    expect(await screen.findByText('Buscando en tus leads…', { selector: 'p:not(.sr-only)' })).toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('si el servidor falla, lo dice y ofrece reintentar', async () => {
    const user = userEvent.setup()
    BUSQUEDA.error = new Error('No se pudo buscar en tus leads.')
    montar({ rol: 'gerencia', demo: false, leads: [] })
    await user.type(campoBusqueda(), 'jua')
    expect(await screen.findByRole('alert')).toHaveTextContent('No se pudo buscar en tus leads.')
    await user.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(BUSQUEDA.refetch).toHaveBeenCalled()
  })
})
