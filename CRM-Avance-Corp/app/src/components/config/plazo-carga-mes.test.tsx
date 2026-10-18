// La tarjeta «Plazo de carga» de Hoy · Gerencia. Corren la tarjeta, el diálogo,
// los ganchos de TanStack y la traducción de `crm-api` REALES; solo se
// sustituyen el cliente de Supabase (que responde según la función pedida) y la
// sesión.
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { StoreDataContext } from '@/lib/store-context'
import type { StoreDataApi } from '@/lib/store'

type Respuesta = { data: unknown; error: { code: string; message: string; details: null; hint: null } | null }

const mock = vi.hoisted(() => ({
  rpc: vi.fn<(nombre: string, args?: Record<string, unknown>) => unknown>(),
  yo: { id: 'g-1', nombre_completo: 'GERENTE REAL', rol: 'gerencia', demo: false, puede_contratar: true } as {
    id: string
    nombre_completo: string
    rol: string
    demo: boolean
    puede_contratar: boolean
  },
}))

// El builder de supabase-js: `.abortSignal()` devuelve la misma promesa.
vi.mock('@/lib/supabase', () => ({
  sb: {
    schema: () => ({
      rpc: (...args: [string, Record<string, unknown>?]) => {
        const promesa = Promise.resolve(mock.rpc(...args))
        return Object.assign(promesa, { abortSignal: () => promesa })
      },
    }),
  },
}))
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: mock.yo }) }))

const { PlazoCargaMesPanel } = await import('./plazo-carga-mes')
const { crmQueryKeys } = await import('@/data/crm-queries')

const HOY = '2026-10-14'
const MOTIVO = 'Los analistas aún cargan ventas de setiembre'

function mes(over: Record<string, unknown> = {}) {
  return {
    mes: '2026-09', mes_nombre: 'setiembre 2026', sellado: false,
    plazo_base_ultimo_dia: '2026-10-10', plazo_ultimo_dia: '2026-10-10', ampliado: false,
    decision: null, reabrible: false, motivo_no_reabrible: null, ultima_reapertura: null,
    ...over,
  }
}
const OCTUBRE = mes({ mes: '2026-10', mes_nombre: 'octubre 2026', plazo_base_ultimo_dia: '2026-11-10', plazo_ultimo_dia: '2026-11-10' })
/** ESTADO DE PRODUCCIÓN el 14/10: setiembre reabierto por script, sin decisión y con el plazo base vencido; octubre en curso. */
const PRODUCCION = [mes(), OCTUBRE]

function plazos(meses: unknown[]) {
  return { version: 1, generado_en: '2026-10-14T15:00:00.123456+00:00', hoy: HOY, zona: 'America/Lima', meses }
}
function ok(data: unknown): Respuesta {
  return { data, error: null }
}
function rechazo(code: string, message: string): Respuesta {
  return { data: null, error: { code, message, details: null, hint: null } }
}

let mesesServidor: unknown[] = PRODUCCION
let respuestaFijar: (args: Record<string, unknown>) => Respuesta = () => ok(null)

beforeEach(() => {
  vi.spyOn(console, 'error').mockImplementation(() => {})
  mock.yo = { id: 'g-1', nombre_completo: 'GERENTE REAL', rol: 'gerencia', demo: false, puede_contratar: true }
  mesesServidor = PRODUCCION
  respuestaFijar = () => ok(null)
  mock.rpc.mockReset()
  mock.rpc.mockImplementation((nombre, args) => {
    if (nombre === 'plazos_carga_mes_fn') return ok(plazos(mesesServidor))
    if (nombre === 'fijar_plazo_carga_mes') return respuestaFijar(args ?? {})
    return rechazo('PGRST202', `no simulada: ${nombre}`)
  })
})

function montar() {
  const recargar = vi.fn(async () => true)
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const invalidar = vi.spyOn(qc, 'invalidateQueries')
  const vista = render(
    <QueryClientProvider client={qc}>
      <StoreDataContext.Provider value={{ recargar } as unknown as StoreDataApi}>
        <PlazoCargaMesPanel />
      </StoreDataContext.Provider>
    </QueryClientProvider>,
  )
  return { ...vista, recargar, invalidar, user: userEvent.setup() }
}

async function tarjeta(): Promise<HTMLElement> {
  const region = await screen.findByRole('region', { name: 'Plazo de carga' })
  await within(region).findByRole('list', { name: 'Plazo de carga por mes' })
  return region
}

function fila(region: HTMLElement, nombre: RegExp): HTMLElement {
  const encontrada = within(region).getAllByRole('listitem').find((item) => nombre.test(item.textContent ?? ''))
  if (!encontrada) throw new Error(`no hay fila ${nombre}`)
  return encontrada
}

function llamadasA(nombre: string) {
  return mock.rpc.mock.calls.filter(([fn]) => fn === nombre)
}

describe('quién la ve', () => {
  it('Gerencia ve la tarjeta y la consulta sale una vez, sin argumentos', async () => {
    montar()
    await tarjeta()
    expect(llamadasA('plazos_carga_mes_fn')).toEqual([['plazos_carga_mes_fn']])
  })

  it.each(['supervisor', 'vendedor', 'coordinador', 'directorio'])('%s ni consulta ni ve la tarjeta (la puerta es solo de Gerencia)', async (rol) => {
    mock.yo = { ...mock.yo, rol }
    const { container } = montar()
    await new Promise((r) => setTimeout(r, 0))
    expect(container).toBeEmptyDOMElement()
    expect(mock.rpc).not.toHaveBeenCalled()
  })

  it('en DEMO no consulta ni pinta: el demo es hermético y esto es la maquinaria real', async () => {
    mock.yo = { ...mock.yo, demo: true }
    const { container } = montar()
    await new Promise((r) => setTimeout(r, 0))
    expect(container).toBeEmptyDOMElement()
    expect(mock.rpc).not.toHaveBeenCalled()
  })
})

describe('lo que dice cada mes', () => {
  it('ESTADO DE PRODUCCIÓN: setiembre vencido y abierto, octubre en curso; los dos se pueden ampliar', async () => {
    montar()
    const region = await tarjeta()

    const setiembre = fila(region, /^Setiembre 2026/)
    expect(setiembre).toHaveTextContent('Setiembre 2026 · el plazo de carga venció el 10 oct. 2026')
    // Sin esta línea, «abierto» se lee como «todo cuenta» y no es así.
    expect(setiembre).toHaveTextContent('Sigue abierto: lo que se cargue ahora suma capital, pero su conversión queda fuera de plazo.')
    expect(setiembre).not.toHaveTextContent('se puede cargar hasta el 10 oct.')
    expect(fila(region, /^Octubre 2026/)).toHaveTextContent('Octubre 2026 · se puede cargar hasta el 10 nov. 2026')

    expect(within(region).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' })).toHaveTextContent('Ampliar plazo')
    expect(within(region).getByRole('button', { name: 'Ampliar plazo de octubre 2026' })).toBeInTheDocument()
    expect(within(region).queryByRole('button', { name: /Reabrir/ })).not.toBeInTheDocument()
  })

  it('un mes ampliado dice hasta cuándo, quién lo amplió, cuándo y por qué', async () => {
    mesesServidor = [mes({
      plazo_ultimo_dia: '2026-10-20',
      ampliado: true,
      decision: { ultimo_dia: '2026-10-20', motivo: MOTIVO, decidido_por: 'MIGUEL BRICEÑO', decidido_en: '2026-10-14T10:05:00-05:00' },
    }), OCTUBRE]
    montar()
    const setiembre = fila(await tarjeta(), /^Setiembre 2026/)

    expect(setiembre).toHaveTextContent('Setiembre 2026 · se puede cargar hasta el 20 oct.')
    expect(setiembre).toHaveTextContent(`Ampliado por MIGUEL BRICEÑO el 14 oct. 2026 · «${MOTIVO}»`)
    expect(setiembre).not.toHaveTextContent('Sigue abierto')
  })

  it('sellado y reabrible: «Reabrir setiembre»; sellado y no reabrible: el motivo en una línea y ningún botón', async () => {
    mesesServidor = [
      mes({ mes: '2026-08', mes_nombre: 'agosto 2026', sellado: true, plazo_base_ultimo_dia: '2026-09-10', plazo_ultimo_dia: '2026-09-10',
        motivo_no_reabrible: 'Solo se reabre el último mes cerrado, y setiembre 2026 ya está cerrado' }),
      mes({ sellado: true, reabrible: true }),
      OCTUBRE,
    ]
    montar()
    const region = await tarjeta()

    const agosto = fila(region, /^Agosto 2026/)
    expect(agosto).toHaveTextContent('Agosto 2026 · cerrado · se pudo cargar hasta el 10 set. 2026')
    expect(agosto).toHaveTextContent('Solo se reabre el último mes cerrado, y setiembre 2026 ya está cerrado')
    expect(within(agosto).queryByRole('button')).not.toBeInTheDocument()

    const setiembre = fila(region, /^Setiembre 2026/)
    expect(setiembre).toHaveTextContent('Setiembre 2026 · cerrado · se pudo cargar hasta el 10 oct. 2026')
    expect(within(setiembre).getByRole('button', { name: 'Reabrir setiembre' })).toBeInTheDocument()
  })
})

describe('ampliar el plazo', () => {
  it('valida fecha y motivo, manda los argumentos exactos, refresca la tarjeta y deja el resumen', async () => {
    respuestaFijar = (args) => {
      mesesServidor = [mes({
        plazo_ultimo_dia: args.p_ultimo_dia, ampliado: true,
        decision: { ultimo_dia: args.p_ultimo_dia, motivo: args.p_motivo, decidido_por: 'GERENTE REAL', decidido_en: '2026-10-14T10:05:00-05:00' },
      }), OCTUBRE]
      return ok({
        ok: true, mes: '2026-09', ultimo_dia: args.p_ultimo_dia, plazo_hasta: '2026-10-21T05:00:00+00:00',
        reabierto: false, reapertura_id: null, acreditaciones_reevaluadas: 12, conflictos_identidad: 1, ventas_devueltas: [],
      })
    }
    const { user, invalidar, recargar } = montar()
    const region = await tarjeta()

    await user.click(within(region).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Ampliar el plazo de setiembre 2026' })
    const guardar = within(dialogo).getByRole('button', { name: 'Guardar plazo' })
    const fecha = within(dialogo).getByLabelText('Último día para cargar')
    expect(dialogo).toHaveTextContent('Hoy: Setiembre 2026 · el plazo de carga venció el 10 oct. 2026.')
    // El foco entra a la fecha: es lo primero que hay que decidir.
    expect(fecha).toHaveFocus()
    expect(fecha).toHaveAttribute('min', HOY)
    expect(guardar).toBeDisabled()

    // Antes de hoy: se marca, se dice (también al lector de pantalla) y no deja guardar.
    fireEvent.change(fecha, { target: { value: '2026-10-13' } })
    expect(fecha).toHaveAttribute('aria-invalid', 'true')
    expect(fecha).toHaveAccessibleDescription('Elige un día desde el 14 oct. 2026.')
    expect(within(dialogo).getByRole('status')).toHaveTextContent('Elige un día desde el 14 oct. 2026.')

    fireEvent.change(fecha, { target: { value: '2026-10-20' } })
    expect(fecha).not.toHaveAttribute('aria-invalid')
    expect(within(dialogo).getByRole('status')).toBeEmptyDOMElement()
    const motivo = within(dialogo).getByLabelText('Motivo')
    await user.type(motivo, 'abcd')
    expect(within(dialogo).getByText('4 de 300 caracteres · mínimo 5')).toBeInTheDocument()
    expect(guardar).toBeDisabled()
    fireEvent.change(motivo, { target: { value: 'x'.repeat(301) } })
    expect(motivo).toHaveAttribute('aria-invalid', 'true')
    expect(guardar).toBeDisabled()
    fireEvent.change(motivo, { target: { value: `  ${MOTIVO}  ` } })
    expect(guardar).toBeEnabled()

    await user.click(guardar)

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(llamadasA('fijar_plazo_carga_mes')).toEqual([
      ['fijar_plazo_carga_mes', { p_periodo: '2026-09-01', p_ultimo_dia: '2026-10-20', p_motivo: MOTIVO }],
    ])
    // El resumen llega DESPUÉS de cerrar el modal (con él abierto, el fondo está oculto al lector).
    const aviso = within(region).getByRole('status')
    await waitFor(() => expect(aviso).toHaveTextContent('Setiembre 2026: se puede cargar hasta el 20 oct. 2026.'))
    expect(aviso).toHaveTextContent('Se volvieron a revisar 12 conversiones con el plazo nuevo.')
    expect(aviso).toHaveTextContent('1 conversión se quedó como estaba: esa persona ya tenía otra conversión acreditada.')
    // Solo texto en la región viva: el botón de cerrar no se lee con el anuncio.
    expect(within(aviso).queryByRole('button')).not.toBeInTheDocument()
    // La tarjeta ya enseña lo que quedó (la lectura se volvió a pedir antes de cerrar).
    const setiembre = fila(region, /^Setiembre 2026/)
    expect(setiembre).toHaveTextContent('Setiembre 2026 · se puede cargar hasta el 20 oct.')
    expect(setiembre).toHaveTextContent('Ampliado por GERENTE REAL el 14 oct. 2026')
    expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.plazosCargaMes() })
    expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.cierreMesEstado() })
    // Ampliar no mueve ventas entre meses: el store no se recarga.
    expect(recargar).not.toHaveBeenCalled()
    // El foco vuelve al botón que abrió el diálogo.
    await waitFor(() => expect(within(region).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' })).toHaveFocus())

    await user.click(within(region).getByRole('button', { name: 'Cerrar el aviso del plazo' }))
    expect(within(region).getByRole('status')).toBeEmptyDOMElement()
    // El botón enfocado se fue con el aviso: el foco no cae a <body>, lo recoge el título.
    expect(within(region).getByRole('heading', { name: 'Plazo de carga' })).toHaveFocus()
  })

  it('una fecha lejana (el 2926 del 15/10) se avisa con el año y no se guarda sin confirmarla', async () => {
    const { user } = montar()
    const region = await tarjeta()
    await user.click(within(region).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Ampliar el plazo de setiembre 2026' })
    const guardar = within(dialogo).getByRole('button', { name: 'Guardar plazo' })
    const fecha = within(dialogo).getByLabelText('Último día para cargar')
    fireEvent.change(within(dialogo).getByLabelText('Motivo'), { target: { value: MOTIVO } })

    fireEvent.change(fecha, { target: { value: '2926-10-20' } })
    // El aviso no se lleva el foco: sigue en la fecha.
    expect(fecha).toHaveFocus()
    const aviso = 'El 20 oct. 2926 queda a más de dos meses: hasta ese día setiembre no se cierra, y los meses siguientes tampoco. Revisa el año.'
    expect(within(dialogo).getByText(aviso)).toBeInTheDocument()
    expect(fecha).toHaveAccessibleDescription(expect.stringContaining(aviso))
    expect(within(dialogo).getByRole('status')).toHaveTextContent('La fecha queda a más de dos meses: confírmala para poder guardar.')
    const confirma = within(dialogo).getByRole('checkbox', { name: 'Sí, el 20 oct. 2926 es correcto' })
    expect(confirma).not.toBeChecked()
    expect(confirma).toHaveAttribute('aria-required', 'true')
    expect(guardar).toBeDisabled()

    await user.click(confirma)
    expect(guardar).toBeEnabled()
    expect(within(dialogo).getByRole('status')).toBeEmptyDOMElement()

    // Otra fecha lejana: la confirmación era de la anterior y se borra.
    fireEvent.change(fecha, { target: { value: '2927-10-20' } })
    expect(within(dialogo).getByRole('checkbox', { name: 'Sí, el 20 oct. 2927 es correcto' })).not.toBeChecked()
    expect(guardar).toBeDisabled()

    // Una fecha cercana no pide nada.
    fireEvent.change(fecha, { target: { value: '2026-10-20' } })
    expect(within(dialogo).queryByRole('checkbox')).not.toBeInTheDocument()
    expect(fecha).not.toHaveAccessibleDescription(expect.stringContaining('queda a más de dos meses'))
    expect(within(dialogo).getByRole('status')).toBeEmptyDOMElement()
    expect(guardar).toBeEnabled()
    expect(llamadasA('fijar_plazo_carga_mes')).toEqual([])
  })

  it('el mes en curso no se puede fijar antes de su plazo normal: el mínimo es el 10 nov.', async () => {
    const { user } = montar()
    const region = await tarjeta()
    await user.click(within(region).getByRole('button', { name: 'Ampliar plazo de octubre 2026' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Ampliar el plazo de octubre 2026' })
    expect(within(dialogo).getByLabelText('Último día para cargar')).toHaveAttribute('min', '2026-11-10')
    expect(dialogo).toHaveTextContent('Desde el 10 nov. 2026. Ese día todavía se puede cargar.')
  })

  it('un rechazo del servidor se muestra tal cual y el diálogo sigue abierto con lo escrito', async () => {
    respuestaFijar = () => rechazo('22023', 'El último día de carga no puede ser anterior a hoy (14/10/2026)')
    const { user } = montar()
    const region = await tarjeta()
    await user.click(within(region).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Ampliar el plazo de setiembre 2026' })
    fireEvent.change(within(dialogo).getByLabelText('Último día para cargar'), { target: { value: '2026-10-20' } })
    fireEvent.change(within(dialogo).getByLabelText('Motivo'), { target: { value: MOTIVO } })

    await user.click(within(dialogo).getByRole('button', { name: 'Guardar plazo' }))

    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('El último día de carga no puede ser anterior a hoy (14/10/2026)')
    expect(screen.getByRole('dialog', { name: 'Ampliar el plazo de setiembre 2026' })).toBeInTheDocument()
    expect(within(dialogo).getByLabelText('Motivo')).toHaveValue(MOTIVO)
  })
})

describe('reabrir un mes sellado', () => {
  it('una fecha lejana también se confirma al reabrir, y el anuncio nombra el botón que hay', async () => {
    mesesServidor = [mes({ sellado: true, reabrible: true }), OCTUBRE]
    const { user } = montar()
    const region = await tarjeta()
    await user.click(within(fila(region, /^Setiembre 2026/)).getByRole('button', { name: 'Reabrir setiembre' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Reabrir setiembre 2026' })
    const reabrir = within(dialogo).getByRole('button', { name: 'Reabrir setiembre' })
    fireEvent.change(within(dialogo).getByLabelText('Motivo'), { target: { value: MOTIVO } })
    fireEvent.change(within(dialogo).getByLabelText('Último día para cargar'), { target: { value: '2926-10-20' } })
    expect(within(dialogo).getByRole('status')).toHaveTextContent('La fecha queda a más de dos meses: confírmala para poder reabrir.')
    expect(reabrir).toBeDisabled()
    await user.click(within(dialogo).getByRole('checkbox', { name: 'Sí, el 20 oct. 2926 es correcto' }))
    expect(reabrir).toBeEnabled()
    expect(llamadasA('fijar_plazo_carga_mes')).toEqual([])
  })

  it('avisa que se retira el cierre, reabre, cuenta las ventas devueltas y recarga el store', async () => {
    mesesServidor = [mes({ sellado: true, reabrible: true }), OCTUBRE]
    respuestaFijar = (args) => {
      mesesServidor = [mes({
        plazo_ultimo_dia: args.p_ultimo_dia, ampliado: true,
        decision: { ultimo_dia: args.p_ultimo_dia, motivo: args.p_motivo, decidido_por: 'GERENTE REAL', decidido_en: '2026-10-14T10:05:00-05:00' },
        ultima_reapertura: { reabierto_en: '2026-10-14T10:05:00-05:00', decidido_por: 'GERENTE REAL' },
      }), OCTUBRE]
      return ok({
        ok: true, mes: '2026-09', ultimo_dia: args.p_ultimo_dia, plazo_hasta: '2026-10-21T05:00:00+00:00',
        reabierto: true, reapertura_id: '55555555-5555-4555-8555-555555555555', acreditaciones_reevaluadas: 3, conflictos_identidad: 0,
        ventas_devueltas: [{ cooperativa: 'qorilazo', monto: '20000.00', moneda: 'PEN', fecha_comercial: '2026-09-15', imputada_antes_a: '2026-10-13' }],
      })
    }
    const { user, recargar } = montar()
    const region = await tarjeta()

    await user.click(within(fila(region, /^Setiembre 2026/)).getByRole('button', { name: 'Reabrir setiembre' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Reabrir setiembre 2026' })
    expect(dialogo).toHaveTextContent('Se retira el cierre de setiembre; se vuelve a sellar solo al vencer este plazo.')
    fireEvent.change(within(dialogo).getByLabelText('Último día para cargar'), { target: { value: '2026-10-20' } })
    fireEvent.change(within(dialogo).getByLabelText('Motivo'), { target: { value: MOTIVO } })

    await user.click(within(dialogo).getByRole('button', { name: 'Reabrir setiembre' }))

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(llamadasA('fijar_plazo_carga_mes')).toEqual([
      ['fijar_plazo_carga_mes', { p_periodo: '2026-09-01', p_ultimo_dia: '2026-10-20', p_motivo: MOTIVO }],
    ])
    const aviso = within(region).getByRole('status')
    await waitFor(() => expect(aviso).toHaveTextContent('Setiembre 2026 reabierto: se puede cargar hasta el 20 oct. 2026.'))
    expect(aviso).toHaveTextContent('Venta devuelta a setiembre: COOPAC Qorilazo · S/ 20,000 · del 15 set. 2026 (estaba contada el 13 oct. 2026).')
    const setiembre = fila(region, /^Setiembre 2026/)
    expect(setiembre).toHaveTextContent('Reabierto por GERENTE REAL el 14 oct. 2026 · ampliado por GERENTE REAL el 14 oct. 2026')
    expect(within(setiembre).getByRole('button', { name: 'Ampliar plazo de setiembre 2026' })).toBeInTheDocument()
    // Las ventas devueltas salen del mes en curso, cuyo cumplimiento vive en el store.
    expect(recargar).toHaveBeenCalledTimes(1)
  })

  it('si el servidor se niega a reabrir, su motivo se lee en el diálogo', async () => {
    mesesServidor = [mes({ sellado: true, reabrible: true }), OCTUBRE]
    respuestaFijar = () => rechazo('P0409', 'El cierre de setiembre 2026 ya descontó deudas de meses anteriores: reabrirlo perdería ese descuento. Revisar con soporte')
    const { user, recargar } = montar()
    const region = await tarjeta()
    await user.click(within(region).getByRole('button', { name: 'Reabrir setiembre' }))
    const dialogo = await screen.findByRole('dialog', { name: 'Reabrir setiembre 2026' })
    fireEvent.change(within(dialogo).getByLabelText('Último día para cargar'), { target: { value: '2026-10-20' } })
    fireEvent.change(within(dialogo).getByLabelText('Motivo'), { target: { value: MOTIVO } })

    await user.click(within(dialogo).getByRole('button', { name: 'Reabrir setiembre' }))

    expect(await within(dialogo).findByRole('alert')).toHaveTextContent('El cierre de setiembre 2026 ya descontó deudas de meses anteriores: reabrirlo perdería ese descuento. Revisar con soporte')
    expect(recargar).not.toHaveBeenCalled()
  })
})

describe('cuando la lectura no llega', () => {
  it('sin la función en el servidor (front antes que la migración) la tarjeta no existe todavía', async () => {
    mock.rpc.mockImplementation(() => rechazo('PGRST202', 'Could not find the function crm.plazos_carga_mes_fn'))
    const { container } = montar()
    await waitFor(() => expect(mock.rpc).toHaveBeenCalled())
    await waitFor(() => expect(container).toBeEmptyDOMElement())
  })

  it('un fallo se dice con su botón de reintentar; reintentar trae el plazo y el foco no cae a <body>', async () => {
    let caido = true
    mock.rpc.mockImplementation((nombre) => {
      if (nombre !== 'plazos_carga_mes_fn') return rechazo('PGRST202', 'no simulada')
      return caido ? rechazo('XX000', 'internal error') : ok(plazos(PRODUCCION))
    })
    const { user } = montar()
    const region = await screen.findByRole('region', { name: 'Plazo de carga' })
    const mensaje = await within(region).findByText('No se pudo leer el plazo de carga.')
    // Solo el mensaje es vivo: el botón no se lee con el anuncio.
    expect(mensaje).toHaveAttribute('role', 'status')
    expect(within(mensaje).queryByRole('button')).not.toBeInTheDocument()

    caido = false
    // Hoy de Gerencia tiene otros «Reintentar»: el nombre dice cuál es este.
    await user.click(within(region).getByRole('button', { name: 'Reintentar la carga del plazo de carga' }))

    expect(await within(region).findByRole('list', { name: 'Plazo de carga por mes' })).toBeInTheDocument()
    expect(within(region).queryByText('No se pudo leer el plazo de carga.')).not.toBeInTheDocument()
    // El botón enfocado se desmontó al volver a pedir: el foco lo recoge el título.
    expect(within(region).getByRole('heading', { name: 'Plazo de carga' })).toHaveFocus()
  })
})
