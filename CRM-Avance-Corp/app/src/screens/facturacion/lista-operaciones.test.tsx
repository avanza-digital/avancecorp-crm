import { useState } from 'react'
import userEvent from '@testing-library/user-event'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Toaster, toast } from 'sonner'
import { Dialog, DialogTitle } from '@/components/ui/dialog'
import type { ListaOperacionesFacturacion, ParametrosOperacionesFacturacion } from '@/data/crm-api'
import { operacion, oculta, respuesta } from '@/test/operaciones-facturacion'
import { ListaOperaciones } from './lista-operaciones'
import { mismosTotales, type NumeroAbierto } from './parametros-de-cifra'
const doble = vi.hoisted(() => ({
  data: undefined as ListaOperacionesFacturacion | undefined,
  isPending: false, isError: false, isFetching: false, isPlaceholderData: false,
  refetch: vi.fn(async () => ({ isError: false })), pedidos: [] as ParametrosOperacionesFacturacion[],
  detener: undefined as undefined | ((d: ListaOperacionesFacturacion) => boolean),
}))
vi.mock('@/data/crm-queries', () => ({ useListaOperacionesFacturacion: (_habilitada: boolean, params: ParametrosOperacionesFacturacion, detener: (d: ListaOperacionesFacturacion) => boolean) => {
  doble.pedidos.push(params); doble.detener = detener
  return { ...doble, error: doble.isError ? new Error('No se pudo cargar la lista de operaciones.') : null }
} }))
const abierto = (): NumeroAbierto => ({ titulo: 'Ana Prueba · lunes 5 de octubre · todas las operaciones',
  cifra: { dias: ['2026-10-05'], analistaId: 'ana', equipoId: 'sup', vista: 'TOTAL' },
  totales: respuesta([operacion, oculta]).totales, valor: 28500, metrica: 'capital', tasa: 3.5 })
const cerrar = vi.fn()
const actualizar = vi.fn(async () => {})
function pintar(extra: Partial<NumeroAbierto> = {}, origen: HTMLElement | null = null) {
  return render(<ListaOperaciones abierto={{ ...abierto(), ...extra }} origen={origen} focoRespaldo={() => null} onCerrar={cerrar} onActualizar={actualizar} />)
}
beforeEach(() => {
  doble.data = respuesta([operacion, oculta]); doble.isError = false; doble.isPending = false; doble.isFetching = false; doble.isPlaceholderData = false
  doble.pedidos = []; doble.refetch.mockReset(); doble.refetch.mockResolvedValue({ isError: false }); cerrar.mockClear(); actualizar.mockClear()
})
afterEach(() => vi.unstubAllGlobals())
describe('hoja lateral: los seis estados aprobados y realidad de producción', () => {
  it('normal: conserva las monedas, conversión, anulada, tabla y pista', () => {
    doble.data = respuesta([{ ...operacion, anulado: true }, oculta])
    pintar()
    const panel = screen.getByRole('region', { name: abierto().titulo })
    expect(panel).not.toHaveAttribute('aria-modal')
    expect(panel).toHaveTextContent('Cuadra. Pulsaste S/ 28,500')
    expect(panel).toHaveTextContent('US$ 1,000 × 3.5')
    expect(panel).toHaveTextContent('Anulada · cuenta igual')
    expect(within(panel).getByRole('table')).toBeVisible()
    expect(within(panel).getByRole('button', { name: /Desliza la tabla/ })).toBeVisible()
    for (const n of [25, 50, 100]) expect(screen.getByRole('button', { name: `${n} filas por página` })).toBeVisible()
  })
  it('otro equipo de un supervisor: cuenta el importe pero jamás enseña N.º ni cooperativa', () => {
    // La protección de presentación tampoco confía en campos extra de un doble defectuoso.
    doble.data = respuesta([{ ...oculta, n: 1, numero_contrato: 'SECRETO-001', cooperativa: 'Cooperativa privada' } as unknown as typeof oculta])
    pintar({ totales: doble.data.totales, valor: 3500 })
    expect(screen.getByRole('row', { name: /Cliente de otro equipo/ })).toHaveTextContent('US$ 1,000')
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('El cliente hoy lo atiende otro equipo')
    expect(screen.getByRole('region', { name: abierto().titulo })).not.toHaveTextContent(/SECRETO|privada/)
  })
  it('cero: un mes sin operaciones se abre y se explica', () => {
    doble.data = respuesta([])
    pintar({ valor: 0, totales: [] })
    expect(screen.getByText('Sin operaciones en este número')).toBeVisible()
    expect(screen.queryByRole('table')).toBeNull()
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('Cuadra.')
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('Mostrando 0–0 de 0')
  })
  it('promedio: abre toda su base y explica la división y el redondeo', () => {
    pintar({ valor: 14250, cuenta: { modo: 'promedio', divisor: 2 } })
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('Pulsaste S/ 14,250, un promedio: esta lista suma S/ 28,500 ÷ 2 días hábiles. Redondeado al sol.')
    expect(screen.queryByText(/Hay cifras nuevas/)).toBeNull()
  })
  it('porcentaje: abre la base anterior con su fórmula', () => {
    pintar({ valor: 100, cuenta: { modo: 'porcentaje', actual: 57000, cifraActual: abierto().cifra } })
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('Pulsaste 100 %')
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('(S/ 57,000 − S/ 28,500) ÷ S/ 28,500 × 100')
    expect(screen.getByRole('region', { name: abierto().titulo })).toHaveTextContent('Esta lista es la de antes')
  })
  it('cifras nuevas: no recarga sola; Actualizar pide la cifra y la lista', async () => {
    pintar({ valor: 25000, totales: respuesta().totales })
    expect(screen.getByText('Hay cifras nuevas ·')).toBeVisible()
    expect(actualizar).not.toHaveBeenCalled(); expect(doble.refetch).not.toHaveBeenCalled()
    expect(doble.detener?.(doble.data!)).toBe(true)
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    await waitFor(() => expect(doble.refetch).toHaveBeenCalledTimes(1))
    expect(actualizar).toHaveBeenCalledTimes(1)
  })
  it('celular: tarjetas, sin tabla duplicada, y la fila ajena sigue enmascarada', () => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q === '(max-width: 640px)' || q === '(max-width: 1279px)', addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    pintar()
    expect(screen.queryByRole('table')).toBeNull()
    expect(screen.getByRole('list')).toBeVisible()
    expect(screen.getAllByRole('listitem')).toHaveLength(2)
    expect(screen.getAllByRole('listitem')[1]).not.toHaveTextContent('2026-10-000001')
  })
  it('carga: no dice cero ni cuadra antes de recibir datos', () => {
    doble.isPending = true; doble.data = undefined
    pintar()
    expect(screen.getByText('Cargando operaciones…')).toBeVisible()
    expect(screen.queryByText(/Cuadra|Sin operaciones/)).toBeNull()
  })
  it('error del servidor: ofrece reintento y oculta incluso la respuesta previa', () => {
    doble.isError = true
    pintar()
    expect(within(screen.getByRole('region', { name: 'Operaciones de este número' })).getByText('No se pudo cargar la lista de operaciones.')).toBeVisible()
    expect(screen.queryByRole('table')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(doble.refetch).toHaveBeenCalledOnce()
  })
  it('foco al título, fondo usable y Esc vuelve al número pulsado', () => {
    const boton = document.createElement('button'); boton.textContent = 'Cifra'; document.body.append(boton); boton.focus()
    pintar({}, boton)
    expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
    boton.focus(); expect(boton).toHaveFocus()
    fireEvent.keyDown(boton, { key: 'Escape' })
    expect(cerrar).toHaveBeenCalledOnce(); expect(boton).toHaveFocus(); boton.remove()
  })
  it('paginación: cambia todos los argumentos de página sin modificar el ámbito', () => {
    doble.data = respuesta(Array.from({ length: 27 }, (_, i) => ({ ...operacion, n: i + 1 })))
    pintar({ totales: doble.data.totales, valor: 675000 })
    expect(screen.getByText('Mostrando 1–25 de 27')).toBeVisible()
    fireEvent.click(screen.getByRole('button', { name: 'Página siguiente' }))
    expect(doble.pedidos.at(-1)).toEqual({ p_desde: '2026-10-05', p_hasta: '2026-10-05', p_analistas: ['ana'], p_equipo: 'sup', p_pagina: 2, p_tamano: 25 })
    fireEvent.click(screen.getByRole('button', { name: '50 filas por página' }))
    expect(doble.pedidos.at(-1)).toMatchObject({ p_pagina: 1, p_tamano: 50 })
    expect(mismosTotales(doble.data.totales, abierto().totales)).toBe(false)
  })
  it('si actualizar la cifra falla, no declara que cuadre ni recarga solo la lista', async () => {
    actualizar.mockRejectedValueOnce(new Error('servidor caído'))
    pintar({ totales: [] })
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    expect((await screen.findAllByText('No se pudieron actualizar las cifras y la lista.')).some((n) => n.getAttribute('role') !== 'status')).toBe(true)
    expect(doble.refetch).not.toHaveBeenCalled()
  })
})


describe('accesibilidad de la lista', () => {
  it('un refresco de fondo mantiene habilitado y enfocado Página siguiente', () => {
    doble.data = respuesta(Array.from({ length: 27 }, (_, i) => ({ ...operacion, n: i + 1 })))
    const props = { abierto: { ...abierto(), totales: doble.data.totales }, origen: null,
      focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    const siguiente = screen.getByRole('button', { name: 'Página siguiente' })
    siguiente.focus()
    doble.isFetching = true
    vista.rerender(<ListaOperaciones {...props} />)
    expect(siguiente).toBeEnabled(); expect(siguiente).toHaveFocus()
    doble.isFetching = false; doble.data = { ...doble.data }
    vista.rerender(<ListaOperaciones {...props} />)
    expect(siguiente).toBeEnabled(); expect(siguiente).toHaveFocus()
  })

  it('mientras llega otra página sí deshabilita la paginación y conserva foco en la hoja', () => {
    doble.data = respuesta(Array.from({ length: 60 }, (_, i) => ({ ...operacion, n: i + 1 })))
    pintar({ totales: doble.data.totales })
    doble.isFetching = true; doble.isPlaceholderData = true
    fireEvent.click(screen.getByRole('button', { name: 'Página siguiente' }))
    expect(screen.getByRole('button', { name: 'Página siguiente' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Página anterior' })).toBeDisabled()
    expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
  })

  it.each(['isError', 'isFetching'] as const)('con foco en la malla, %s de fondo no lo mueve', (estado) => {
    const boton = document.createElement('button'); document.body.append(boton)
    const props = { abierto: abierto(), origen: boton, focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    boton.focus()
    doble[estado] = true
    vista.rerender(<ListaOperaciones {...props} />)
    expect(boton).toHaveFocus()
    doble[estado] = false; doble.data = { ...doble.data! }
    vista.rerender(<ListaOperaciones {...props} />)
    expect(boton).toHaveFocus()
    vista.unmount(); boton.remove()
  })

  it('pulsar el tamaño ya activo no deja un cambio de foco pendiente al refrescar', async () => {
    const props = { abierto: abierto(), origen: null, focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    const tamano = screen.getByRole('button', { name: '25 filas por página' })
    await userEvent.setup().click(tamano)
    expect(tamano).toHaveFocus()
    doble.isFetching = true
    vista.rerender(<ListaOperaciones {...props} />)
    expect(tamano).toHaveFocus()
    doble.isFetching = false; doble.data = { ...doble.data! }
    vista.rerender(<ListaOperaciones {...props} />)
    expect(tamano).toHaveFocus()
  })

  it.each(['input', 'textarea', 'select', 'contenteditable'] as const)('Esc respeta un %s del fondo y no cancela su evento', (tipo) => {
    const campo = document.createElement(tipo === 'contenteditable' ? 'div' : tipo)
    if (tipo === 'contenteditable') { campo.setAttribute('contenteditable', 'true'); campo.tabIndex = 0 }
    document.body.append(campo)
    const vista = pintar()
    campo.focus()
    const evento = new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
    campo.dispatchEvent(evento)
    expect(evento.defaultPrevented).toBe(false)
    expect(cerrar).not.toHaveBeenCalled(); expect(campo).toHaveFocus()
    vista.unmount(); campo.remove()
  })

  it('el cuerpo es una región etiquetada y alcanzable con teclado en escritorio', () => {
    pintar()
    expect(screen.getByRole('region', { name: abierto().titulo })).not.toHaveAttribute('aria-modal')
    expect(screen.getByRole('region', { name: 'Operaciones de este número' })).toHaveAttribute('tabindex', '0')
    expect(screen.getByRole('columnheader', { name: 'Número de fila' })).toBeVisible()
    expect(screen.getAllByRole('status')).toHaveLength(1)
  })

  it.each(['isPending', 'isError'] as const)('cambiar de página con %s conserva el foco y vuelve al título', (estado) => {
    doble.data = respuesta(Array.from({ length: 27 }, (_, i) => ({ ...operacion, n: i + 1 })))
    const props = { abierto: { ...abierto(), totales: doble.data.totales, valor: 675000 }, origen: null,
      focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    const siguiente = screen.getByRole('button', { name: 'Página siguiente' })
    siguiente.focus(); fireEvent.click(siguiente)
    expect(document.activeElement).not.toBe(document.body)
    doble[estado] = true; doble.data = undefined
    vista.rerender(<ListaOperaciones {...props} />)
    expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
    expect(document.activeElement).not.toBe(document.body)
  })

  it.each(['Escape', 'Cerrar'] as const)('si el origen desaparece, %s vuelve al respaldo', (accion) => {
    const boton = document.createElement('button'); document.body.append(boton)
    const respaldo = document.createElement('div'); respaldo.tabIndex = -1; document.body.append(respaldo)
    function Escenario() {
      const [visible, setVisible] = useState(true)
      return visible ? <ListaOperaciones abierto={abierto()} origen={boton} focoRespaldo={() => respaldo}
        onCerrar={() => setVisible(false)} onActualizar={actualizar} /> : null
    }
    render(<Escenario />)
    boton.remove()
    if (accion === 'Escape') fireEvent.keyDown(document.activeElement!, { key: 'Escape' })
    else fireEvent.click(screen.getByRole('button', { name: 'Cerrar detalle' }))
    expect(respaldo).toHaveFocus()
    expect(screen.queryByRole('region', { name: abierto().titulo })).toBeNull()
    respaldo.remove()
  })

  it('encuentra la gemela del origen antes de recurrir al respaldo', () => {
    const boton = document.createElement('button'); boton.dataset.focoClave = 'cifra-ana'; document.body.append(boton)
    pintar({}, boton)
    boton.remove()
    const gemela = document.createElement('button'); gemela.dataset.focoClave = 'cifra-ana'; document.body.append(gemela)
    fireEvent.keyDown(document.activeElement!, { key: 'Escape' })
    expect(gemela).toHaveFocus(); gemela.remove()
  })

  it('actualiza el único canal vivo cuando aparecen cifras nuevas', async () => {
    const props = { abierto: abierto(), origen: null, focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    const canal = screen.getByRole('status')
    expect(canal).toBeEmptyDOMElement()
    doble.data = respuesta([operacion])
    vista.rerender(<ListaOperaciones {...props} />)
    expect(screen.getByRole('status')).toBe(canal)
    await waitFor(() => expect(canal).toHaveTextContent('Hay cifras nuevas: la lista y el número pulsado ya no coinciden. Pulsa Actualizar'))
    expect(screen.getAllByRole('status')).toHaveLength(1)
    expect(screen.getByText('La cifra cambió.').closest('.lista-cuenta')?.querySelector('svg')).toBeNull()
  })

  it('un reintento exitoso enfoca el título', async () => {
    doble.isError = true
    const vista = pintar()
    const boton = screen.getByRole('button', { name: 'Reintentar' })
    boton.focus(); fireEvent.click(boton)
    await waitFor(() => expect(doble.refetch).toHaveBeenCalledOnce())
    doble.isError = false
    vista.rerender(<ListaOperaciones abierto={abierto()} origen={null} focoRespaldo={() => null} onCerrar={cerrar} onActualizar={actualizar} />)
    expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
  })

  it('conserva el fallo de actualización hasta conocer el resultado y anuncia el éxito', async () => {
    actualizar.mockRejectedValueOnce(new Error('fallo'))
    const props = { abierto: { ...abierto(), totales: [] }, origen: null, focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar' }))
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('No se pudieron actualizar'))
    let resolver!: () => void
    actualizar.mockImplementationOnce(() => new Promise<void>((resolve) => { resolver = resolve }))
    fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(screen.getByRole('status')).toHaveTextContent('No se pudieron actualizar')
    expect(screen.getAllByText('No se pudieron actualizar las cifras y la lista.')).toHaveLength(2)
    await act(async () => { resolver() })
    vista.rerender(<ListaOperaciones {...props} abierto={abierto()} />)
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Cifras actualizadas'))
    expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
  })

  it.each([390, 1100, 1279])('a %i px es modal, deja el fondo inerte, contiene Tab y Esc restaura el foco', async (ancho) => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q === '(max-width: 1279px)' || (ancho <= 640 && q === '(max-width: 640px)'), addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    const raiz = document.createElement('div'); raiz.id = 'app-content'; document.body.append(raiz)
    const boton = document.createElement('button'); boton.textContent = 'Origen'; raiz.append(boton)
    const host = document.createElement('div'); raiz.append(host)
    function Escenario() {
      const [visible, setVisible] = useState(true)
      return visible ? <ListaOperaciones abierto={abierto()} origen={boton} focoRespaldo={() => boton}
        onCerrar={() => setVisible(false)} onActualizar={actualizar} /> : null
    }
    const vista = render(<Escenario />, { container: host })
    expect(screen.getByRole('dialog', { name: abierto().titulo })).toHaveAttribute('aria-modal', 'true')
    expect(raiz.inert).toBe(true)
    expect(screen.getByRole('region', { name: 'Operaciones de este número' })).toHaveAttribute('tabindex', ancho <= 640 ? '-1' : '0')
    if (ancho > 640) expect(screen.getByRole('table')).toBeVisible()
    else expect(screen.getByRole('list')).not.toHaveAttribute('aria-label')
    const usuario = userEvent.setup()
    const ultimo = screen.getByRole('button', { name: '100 filas por página' })
    ultimo.focus(); await usuario.tab()
    expect(screen.getByRole('button', { name: 'Cerrar detalle' })).toHaveFocus()
    await usuario.tab({ shift: true }); expect(ultimo).toHaveFocus()
    boton.focus(); expect(screen.getByRole('heading', { name: abierto().titulo })).toHaveFocus()
    await usuario.keyboard('{Escape}')
    expect(raiz.inert).toBe(false); expect(boton).toHaveFocus()
    vista.unmount(); raiz.remove()
  })

  it('el scroll móvil de paginación enfoca la primera tarjeta y Shift+Tab retrocede sin envolver', async () => {
    vi.stubGlobal('matchMedia', () => ({ matches: true, addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    doble.data = respuesta(Array.from({ length: 27 }, (_, i) => ({ ...operacion, n: i + 1 })))
    pintar({ totales: doble.data.totales, valor: 675000 })
    const panel = screen.getByRole('dialog')
    const scroll = vi.fn(); panel.scrollTo = scroll
    fireEvent.click(screen.getByRole('button', { name: 'Página siguiente' }))
    expect(scroll).toHaveBeenCalledWith({ top: 0 })
    expect(screen.getAllByRole('listitem')[0]).toHaveFocus()
    await userEvent.setup().tab({ shift: true })
    expect(screen.getByRole('button', { name: 'Cerrar detalle' })).toHaveFocus()
  })

  it('al cruzar 1280 px conserva la sección, sus controles y la página, y retira el solape', () => {
    let ancho = 1280
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: ancho < 1280 && q === '(max-width: 1279px)', addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    doble.data = respuesta(Array.from({ length: 60 }, (_, i) => ({ ...operacion, n: i + 1 })))
    const raiz = document.createElement('div'); raiz.id = 'app-content'; document.body.append(raiz)
    const malla = document.createElement('div'); malla.className = 'facturacion-malla'; raiz.append(malla)
    const boton = document.createElement('button'); malla.append(boton)
    const props = { abierto: { ...abierto(), totales: doble.data.totales }, origen: boton,
      focoRespaldo: () => null, onCerrar: cerrar, onActualizar: actualizar }
    const vista = render(<ListaOperaciones {...props} />)
    const panel = screen.getByRole('region', { name: abierto().titulo })
    const control = screen.getByRole('button', { name: 'Cerrar detalle' })
    expect(panel.tagName).toBe('SECTION')
    expect(panel).not.toHaveAttribute('role'); expect(panel).not.toHaveAttribute('aria-modal')
    expect(malla.style.getPropertyValue('--lista-solape')).not.toBe('')
    fireEvent.click(screen.getByRole('button', { name: 'Página siguiente' }))
    ancho = 1100
    vista.rerender(<ListaOperaciones {...props} />)
    expect(screen.getByRole('dialog', { name: abierto().titulo })).toBe(panel)
    expect(screen.getByRole('button', { name: 'Cerrar detalle' })).toBe(control)
    expect(panel).toHaveTextContent('Mostrando 26–50 de 60')
    expect(raiz.inert).toBe(true)
    expect(malla.style.getPropertyValue('--lista-solape')).toBe('')
    ancho = 1280
    vista.rerender(<ListaOperaciones {...props} />)
    expect(screen.getByRole('region', { name: abierto().titulo })).toBe(panel)
    expect(panel).not.toHaveAttribute('role'); expect(panel).not.toHaveAttribute('aria-modal')
    expect(raiz.inert).toBe(false)
    vista.unmount(); raiz.remove()
  })

  it('Sonner sigue fuera del fondo inerte y su acción recibe foco y se puede pulsar', async () => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q === '(max-width: 1279px)', addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    const raiz = document.createElement('div'); raiz.id = 'root'; document.body.append(raiz)
    const accion = vi.fn()
    const vista = render(<><div id="app-content"><button>Fondo</button>
      <ListaOperaciones abierto={abierto()} origen={null} focoRespaldo={() => null} onCerrar={cerrar} onActualizar={actualizar} />
    </div><Toaster /></>, { container: raiz })
    act(() => { toast('Operación guardada', { duration: Infinity, action: { label: 'Deshacer', onClick: accion } }) })
    const deshacer = await screen.findByRole('button', { name: 'Deshacer' })
    expect(document.getElementById('app-content')?.inert).toBe(true)
    expect(raiz.inert).not.toBe(true)
    expect(deshacer.closest('[inert]')).toBeNull()
    deshacer.focus(); expect(deshacer).toHaveFocus()
    fireEvent.keyDown(deshacer, { key: 'Escape' }); expect(cerrar).not.toHaveBeenCalled()
    await userEvent.setup().click(deshacer)
    expect(accion).toHaveBeenCalledOnce()
    act(() => { toast.dismiss() })
    vista.unmount(); raiz.remove()
  })

  it.each([false, true])('Esc dentro de Radix cierra solo el diálogo superior (hoja modal: %s)', async (modal) => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: modal && q === '(max-width: 1279px)', addEventListener: vi.fn(), removeEventListener: vi.fn() }))
    function Escenario() {
      const [abierta, setAbierta] = useState(false)
      return <><ListaOperaciones abierto={abierto()} origen={null} focoRespaldo={() => null} onCerrar={cerrar} onActualizar={actualizar} />
        <button onClick={() => setAbierta(true)}>Abrir diálogo superior</button>
        <Dialog open={abierta} onClose={() => setAbierta(false)}>
          <DialogTitle>Confirmación superior</DialogTitle><button>Aceptar</button>
        </Dialog></>
    }
    render(<Escenario />)
    fireEvent.click(screen.getByRole('button', { name: 'Abrir diálogo superior' }))
    const superior = screen.getByRole('dialog', { name: 'Confirmación superior' })
    expect(within(superior).getByRole('button', { name: 'Aceptar' })).toHaveFocus()
    await userEvent.setup().keyboard('{Escape}')
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Confirmación superior' })).toBeNull())
    expect(cerrar).not.toHaveBeenCalled()
    expect(screen.getByRole(modal ? 'dialog' : 'region', { name: abierto().titulo })).toBeVisible()
  })
})
