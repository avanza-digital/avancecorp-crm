import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { ArrowRight, Check, EyeOff, ListX, X } from 'lucide-react'
import { useListaOperacionesFacturacion } from '@/data/crm-queries'
import type { ListaOperacionesFacturacion, OperacionFacturacion } from '@/data/crm-api'
import { Pastilla } from '@/components/ui/pastilla'
import { CELDA, ENCABEZADO } from '@/components/ui/estilos-hoja'
import { PanelError } from '@/components/common/estado-panel'
import { money, numero } from '@/lib/format'
import { etiquetaDiaLargo } from '@/lib/facturacion'
import { useEsEstrecha, useMediaQuery } from '@/lib/media'
import { useValorDiferido } from '@/lib/use-valor-diferido'
import { listaCuadraConNumero, parametrosDeCifra, valorDeTotales, type NumeroAbierto } from './parametros-de-cifra'
import { cn } from '@/lib/utils'
import './lista-operaciones.css'

const TIPOS = { contrato_nuevo: 'Nuevo', contrato_upgrade: 'Upgrade', contrato_renovacion: 'Renovación', cooperativa: 'Cooperativa' }
const EXPLICACION_AJENA = 'El cliente hoy lo atiende otro equipo: ves el importe, no sus datos.'
// Los Dialog/Sheet de Radix se identifican por data-slot y no siempre llevan aria-modal.
const CAPA_EXTERNA = '[aria-modal="true"], [data-slot="dialog"], [data-slot="sheet"], [data-sonner-toaster]'
const nombreCliente = (f: OperacionFacturacion) => f.visible ? f.cliente_nombre ?? 'Cliente sin nombre' : 'Cliente de otro equipo'
const referencia = (f: OperacionFacturacion) => !f.visible ? '—' : (f.tipo === 'cooperativa' ? f.cooperativa : f.numero_contrato) ?? '—'

function Cliente({ fila }: { fila: OperacionFacturacion }) {
  return <div className="lista-cliente">
    <span className={cn('text-base font-semibold', !fila.visible && 'italic text-muted-foreground-strong')}>
      {!fila.visible && <EyeOff aria-hidden className="mr-1 inline size-4" />}{nombreCliente(fila)}
    </span>
    {fila.anulado && <span className="lista-anulada">Anulada · cuenta igual</span>}
  </div>
}

function Referencia({ fila, tarjeta = false }: { fila: OperacionFacturacion; tarjeta?: boolean }) {
  const texto = referencia(fila)
  return texto === '—' ? <><span aria-hidden>—</span><span className="sr-only">sin dato</span></>
    : <>{tarjeta && fila.tipo !== 'cooperativa' ? 'N.º ' : ''}{texto}</>
}

/** Inspector en escritorio amplio; modal lateral en ventana estrecha y tarjetas en celular. */
export function ListaOperaciones({ abierto, origen, focoRespaldo, onCerrar, onActualizar, ejemplo }: {
  abierto: NumeroAbierto
  origen: HTMLElement | null
  focoRespaldo: () => HTMLElement | null
  onCerrar: () => void
  onActualizar: () => Promise<void>
  ejemplo?: ((pagina: number, tamano: 25 | 50 | 100) => ListaOperacionesFacturacion) | undefined
}) {
  const [pagina, setPagina] = useState(1)
  const [tamano, setTamano] = useState<25 | 50 | 100>(25)
  const [actualizando, setActualizando] = useState(false)
  const [falloActualizacion, setFalloActualizacion] = useState(false)
  const [actualizadas, setActualizadas] = useState(false)
  const titulo = useRef<HTMLHeadingElement>(null)
  const panel = useRef<HTMLElement>(null)
  const cuerpo = useRef<HTMLDivElement>(null)
  const mostrando = useRef<HTMLParagraphElement>(null)
  const enfocarPagina = useRef(false)
  const id = useId()
  const celular = useMediaQuery('(max-width: 640px)')
  const esModal = useEsEstrecha()
  const parametros = parametrosDeCifra(abierto.cifra, pagina, tamano)
  const consulta = useListaOperacionesFacturacion(!ejemplo, parametros, (d) => !listaCuadraConNumero(abierto, d))
  const datos = ejemplo ? ejemplo(pagina, tamano) : consulta.data
  const error = !ejemplo && consulta.isError
  const cargando = !ejemplo && consulta.isPending
  const paginando = !ejemplo && consulta.isPlaceholderData
  const nuevas = datos != null && !listaCuadraConNumero(abierto, datos)
  const mensajeError = error ? consulta.error?.message ?? 'No se pudo cargar la lista de operaciones.' : ''
  const anuncio = useValorDiferido(falloActualizacion ? 'No se pudieron actualizar las cifras y la lista.'
    : mensajeError || (nuevas ? 'Hay cifras nuevas: la lista y el número pulsado ya no coinciden. Pulsa Actualizar'
      : actualizadas ? 'Cifras actualizadas' : ''), 250)
  const cerrar = useRef(onCerrar)
  const respaldo = useRef(focoRespaldo)
  const liberarFondo = useRef(() => {})
  const devolverFoco = useRef(() => {})
  cerrar.current = onCerrar
  respaldo.current = focoRespaldo
  const cerrarConFoco = () => {
    liberarFondo.current()
    cerrar.current()
    devolverFoco.current()
  }
  useLayoutEffect(() => {
    const nodoPanel = panel.current
    const clave = origen?.closest('[data-foco-clave]')?.getAttribute('data-foco-clave')
    devolverFoco.current = () => {
      const gemela = clave == null ? null : Array.from(document.querySelectorAll<HTMLElement>('[data-foco-clave]'))
        .find((nodo) => nodo.getAttribute('data-foco-clave') === clave)
      const destino = origen?.isConnected ? origen : gemela ?? respaldo.current()
      destino?.focus({ preventScroll: true })
    }
    titulo.current?.focus({ preventScroll: true })
    origen?.classList.add('facturacion-cifra-abierta')
    return () => {
      origen?.classList.remove('facturacion-cifra-abierta')
      liberarFondo.current()
      if (document.activeElement === document.body || nodoPanel?.contains(document.activeElement)) devolverFoco.current()
    }
  }, [origen])

  useEffect(() => {
    const region = origen?.closest<HTMLElement>('.facturacion-malla')
    if (!region || !origen || esModal) return
    const posicionAnterior = region.scrollLeft
    const medir = () => {
      const cajaRegion = region.getBoundingClientRect()
      const borde = Math.min(cajaRegion.right, panel.current?.getBoundingClientRect().left ?? Infinity) - 12
      region.style.setProperty('--lista-solape', `${Math.max(0, cajaRegion.right - borde)}px`)
      const caja = origen.getBoundingClientRect()
      if (caja.right > borde) region.scrollLeft += caja.right - borde
    }
    medir()
    const observador = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(medir)
    observador?.observe(region)
    window.addEventListener('resize', medir)
    return () => {
      observador?.disconnect()
      window.removeEventListener('resize', medir)
      region.style.removeProperty('--lista-solape')
      region.scrollLeft = posicionAnterior
    }
  }, [origen, esModal])

  useLayoutEffect(() => {
    if (!esModal) return
    // Sonner es hermano de este contenedor: sus avisos siguen anunciándose y operables.
    const raiz = document.getElementById('app-content')
    const eraInerte = raiz?.inert ?? false
    if (raiz) raiz.inert = true
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const liberar = () => {
      if (raiz) raiz.inert = eraInerte
      document.body.style.overflow = overflow
    }
    liberarFondo.current = liberar
    const contener = (e: FocusEvent) => {
      const destino = e.target
      if (destino instanceof Element && !panel.current?.contains(destino) && !destino.closest(CAPA_EXTERNA)) titulo.current?.focus()
    }
    document.addEventListener('focusin', contener)
    titulo.current?.focus({ preventScroll: true })
    liberarFondo.current = () => { document.removeEventListener('focusin', contener); liberar() }
    return () => { liberarFondo.current(); liberarFondo.current = () => {} }
  }, [esModal])

  useEffect(() => {
    const teclado = (e: KeyboardEvent) => {
      const destino = e.target instanceof Element ? e.target : null
      const capa = destino?.closest(CAPA_EXTERNA)
      if (capa && capa !== panel.current) return
      if (e.key === 'Escape' && !e.defaultPrevented) {
        if (!esModal && !panel.current?.contains(destino) && destino?.closest('input, textarea, select, [contenteditable]')) return
        e.preventDefault()
        liberarFondo.current()
        cerrar.current()
        devolverFoco.current()
      }
      if (e.key !== 'Tab' || !esModal || e.defaultPrevented) return
      const controles = Array.from(panel.current?.querySelectorAll<HTMLElement>(':is(button, a[href], input, select, textarea, [tabindex="0"]):not(:disabled)') ?? [])
        .filter((nodo) => !nodo.closest('[inert], [hidden]'))
      const primero = controles[0]
      const ultimo = controles.at(-1)
      const activo = document.activeElement
      if (e.shiftKey && (activo === primero || activo === titulo.current || !panel.current?.contains(activo))) {
        e.preventDefault(); (ultimo ?? titulo.current)?.focus()
      } else if (!e.shiftKey && activo === ultimo) {
        e.preventDefault(); (primero ?? titulo.current)?.focus()
      }
    }
    document.addEventListener('keydown', teclado)
    return () => document.removeEventListener('keydown', teclado)
  }, [esModal])

  useLayoutEffect(() => {
    const a = document.activeElement
    const focoEnHoja = a == null || a === document.body || !!panel.current?.contains(a)
    if (!focoEnHoja) { enfocarPagina.current = false; return }
    if (error || cargando || (enfocarPagina.current && consulta.isFetching)) titulo.current?.focus({ preventScroll: true })
    if (error) enfocarPagina.current = false
    if (enfocarPagina.current && datos && !cargando && !error && !consulta.isFetching) {
      if (celular) {
        const hoja = panel.current
        const primera = cuerpo.current?.querySelector<HTMLElement>('[role="listitem"]')
        const cabecera = hoja?.querySelector('.lista-titulo-fila')?.getBoundingClientRect().height ?? 0
        const hastaPrimera = primera && hoja ? primera.getBoundingClientRect().top - hoja.getBoundingClientRect().top + hoja.scrollTop - cabecera - 12 : 0
        hoja?.scrollTo?.({ top: Math.max(0, hastaPrimera) })
        const destino = primera ?? titulo.current
        destino?.focus({ preventScroll: true })
      } else {
        cuerpo.current?.scrollTo?.({ top: 0 })
        mostrando.current?.focus({ preventScroll: true })
      }
      enfocarPagina.current = false
    }
  }, [datos, cargando, error, consulta.isFetching, pagina, tamano, celular])

  const actualizar = async () => {
    titulo.current?.focus({ preventScroll: true })
    setActualizando(true)
    setActualizadas(false)
    try {
      await onActualizar()
      if (!ejemplo) {
        const resultado = await consulta.refetch()
        if (resultado.isError) throw resultado.error
      }
      setFalloActualizacion(false)
      setActualizadas(true)
      setPagina(1)
      enfocarPagina.current = false
      titulo.current?.focus({ preventScroll: true })
    } catch { setFalloActualizacion(true); titulo.current?.focus({ preventScroll: true }) }
    finally { setActualizando(false) }
  }
  const reintentar = async () => {
    titulo.current?.focus({ preventScroll: true })
    const resultado = await consulta.refetch()
    if (!resultado.isError) titulo.current?.focus({ preventScroll: true })
  }
  const ir = (n: number, t = tamano) => {
    if (n === pagina && t === tamano) return
    enfocarPagina.current = true
    setPagina(n); setTamano(t)
  }
  const moneda = abierto.cifra.vista === 'USD' ? 'USD' : 'PEN'
  const formato = (v: number) => abierto.metrica === 'capital' ? money(v, moneda) : `${numero(v, 1)} operaciones`
  const suma = datos ? valorDeTotales(datos.totales, abierto.cifra.vista, abierto.metrica, abierto.tasa) : 0
  const ajenas = datos?.filas.filter((f) => !f.visible).length ?? 0
  const ultimo = datos ? Math.min(datos.total, pagina * tamano) : 0
  const primero = datos?.filas.length ? (pagina - 1) * tamano + 1 : 0

  return createPortal(<section ref={panel} role={esModal ? 'dialog' : undefined} aria-modal={esModal ? true : undefined} aria-labelledby={id} className="lista-operaciones">
    <p role="status" className="sr-only">{anuncio}</p>
    <header className="lista-cabecera">
      <div className="lista-titulo-fila">
        <div className="min-w-0 flex-1"><p className="text-sm text-muted-foreground-strong">{ejemplo ? 'Operaciones de ejemplo' : 'Operaciones de este número'}</p>
          <h2 id={id} ref={titulo} tabIndex={-1} className="text-lg font-extrabold text-primary">{abierto.titulo}</h2></div>
        <button type="button" onClick={cerrarConFoco} aria-label="Cerrar detalle" title="Cerrar la lista (Esc)" className="lista-cerrar"><X aria-hidden /></button>
      </div>
      {!error && datos && <>
        <div className="lista-pastillas" role="group" aria-label="Subtotales de la lista">
          {datos.totales.map((t) => <Pastilla key={t.moneda} etiqueta={t.moneda === 'PEN' ? 'Soles' : 'Dólares'} valor={money(t.monto, t.moneda)} />)}
          <Pastilla etiqueta="Cantidad" valor={`${numero(datos.total)} ${datos.total === 1 ? 'operación' : 'operaciones'}`} />
        </div>
        <div className="lista-cuenta">
          {!nuevas && <Check aria-hidden className="mt-0.5 size-4 shrink-0 text-accent" />}
          <div>
            <p><strong>{nuevas ? 'La cifra cambió.' : 'Cuadra.'}</strong>{' '}
              {abierto.cuenta?.modo === 'promedio'
                ? `Pulsaste ${formato(abierto.valor)}, un promedio: esta lista suma ${formato(suma)} ÷ ${numero(abierto.cuenta.divisor)} días hábiles.${abierto.metrica === 'capital' ? ' Redondeado al sol.' : ''}`
                : `Pulsaste ${formato(abierto.valor)}: la lista ${abierto.metrica === 'capital' ? 'suma' : 'tiene'} ${formato(suma)}, en todas sus páginas.`}
            </p>
            {abierto.cifra.vista === 'TOTAL' && abierto.metrica === 'capital' && <p className="mt-1 text-muted-foreground-strong">
              {money(datos.totales.find((t) => t.moneda === 'PEN')?.monto ?? 0, 'PEN')} + {money(datos.totales.find((t) => t.moneda === 'USD')?.monto ?? 0, 'USD')}
              {abierto.tasa != null ? ` × ${numero(abierto.tasa, 4)} (tipo de cambio en soles).` : ' · todo en soles.'} Soles y dólares se muestran por separado.
            </p>}
          </div>
        </div>
      </>}
    </header>
    {nuevas && !error && <div className="lista-aviso lista-nuevas">
      <strong>Hay cifras nuevas · </strong><button type="button" aria-disabled={actualizando} onClick={() => { if (!actualizando) void actualizar() }} className="lista-actualizar">{actualizando ? 'Actualizando…' : 'Actualizar'}</button>
      <p>La lista y el número pulsado ya no coinciden. Actualizar vuelve a pedir ambos.</p>
    </div>}
    {falloActualizacion && <PanelError mensaje="No se pudieron actualizar las cifras y la lista." onReintentar={() => void actualizar()} reintentando={actualizando} />}
    {ajenas > 0 && !error && <p className="lista-aviso">{EXPLICACION_AJENA}</p>}
    {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Región desplazable: permite recorrer la tabla con el teclado, incluso sin botones entre sus filas. */}
    <div ref={cuerpo} role="region" aria-label="Operaciones de este número" tabIndex={celular ? -1 : 0} className="lista-cuerpo ac-scroll" aria-busy={cargando}>
      {error ? <PanelError mensaje={mensajeError} onReintentar={() => { void reintentar() }} reintentando={consulta.isFetching} />
        : cargando ? <p className="lista-vacio">Cargando operaciones…</p>
        : datos?.total === 0 ? <div className="lista-vacio"><ListX aria-hidden /><h3 className="text-base font-bold">Sin operaciones en este número</h3><p>No hay operaciones con los días y filtros de esta cifra.</p></div>
        : datos?.filas.length === 0 ? <div className="lista-vacio"><p>No hay operaciones en esta página.</p><button type="button" className="lista-volver" onClick={() => ir(1)}>Volver a la primera página</button></div>
        : datos && (celular ? <div role="list" className="lista-tarjetas">
          {datos.filas.map((f) => <div role="listitem" tabIndex={-1} key={f.n} className={cn('lista-tarjeta', !f.visible && 'lista-ajena')}>
            <div className="flex items-start gap-2"><span className="text-sm tabular-nums">{f.n}</span><div className="min-w-0 flex-1"><Cliente fila={f} /></div><strong className="text-base tabular-nums">{money(f.monto, f.moneda)}</strong></div>
            <p className="mt-2 text-sm">{etiquetaDiaLargo(f.fecha)} · {TIPOS[f.tipo]}</p>
            {f.visible && <p className="text-sm"><Referencia fila={f} tarjeta /></p>}
            <p className="mt-1 text-base">Analista {f.analista_nombre} · equipo de {f.supervisor_nombre}</p>
            {!f.visible && <p className="mt-2 text-sm text-muted-foreground-strong">{EXPLICACION_AJENA}</p>}
          </div>)}
        </div> : <table className="lista-tabla">
          <caption className="sr-only">Operaciones de este número, página {pagina}</caption>
          <thead><tr>{['#', 'Fecha', 'Tipo', 'Cliente', 'N.º de contrato / Cooperativa', 'Analista', 'Supervisor', 'Monto'].map((t, i) =>
            <th key={t} scope="col" className={cn(ENCABEZADO, `lista-col-${i}`)}>{t === '#' ? <><span aria-hidden>#</span><span className="sr-only">Número de fila</span></> : t}</th>)}</tr></thead>
          <tbody>{datos.filas.map((f) => <tr key={f.n} className={cn(!f.visible && 'lista-ajena')}>
            <td className={cn(CELDA, 'lista-col-0')}>{f.n}</td>
            <td className={cn(CELDA, 'lista-col-1')}>{numero(Number(f.fecha.slice(8)))} {new Date(`${f.fecha}T12:00:00`).toLocaleDateString('es-PE', { month: 'short' })}</td>
            <td className={CELDA}><span className={`lista-tipo lista-${f.tipo}`}>{TIPOS[f.tipo]}</span></td>
            <th scope="row" className={cn(CELDA, 'lista-col-3')}><Cliente fila={f} /></th>
            <td className={CELDA}><Referencia fila={f} /></td>
            <td className={cn(CELDA, 'lista-persona')}>{f.analista_nombre}</td>
            <td className={cn(CELDA, 'lista-persona')}>{f.supervisor_nombre}</td>
            <td className={cn(CELDA, 'lista-col-7')}>{money(f.monto, f.moneda)}</td>
          </tr>)}</tbody>
        </table>)}
    </div>
    {datos && !error && <footer className="lista-pie">
      <p ref={mostrando} tabIndex={-1} className="font-bold">Mostrando {numero(primero)}–{numero(ultimo)} de {numero(datos.total)}</p>
      {!celular && datos.total > 0 && <><button type="button" className="lista-pista" onClick={() => cuerpo.current?.scrollBy({ left: 300, behavior: 'auto' })}>Desliza la tabla: N.º, Analista y Supervisor <ArrowRight aria-hidden className="size-4" /></button><button type="button" className="lista-pista" onClick={() => cuerpo.current?.scrollTo({ left: 0, behavior: 'auto' })}>Volver a Fecha</button></>}
      <div role="group" aria-label="Filas por página" className="flex flex-wrap items-center gap-1"><span className="mr-1">Filas por página</span>{([25, 50, 100] as const).map((n) =>
        <button key={n} type="button" aria-pressed={tamano === n} aria-label={`${n} filas por página`} onClick={() => ir(1, n)} className="lista-tamano">{n}</button>)}</div>
      <div className="lista-paginas"><button type="button" disabled={pagina === 1 || paginando} onClick={() => ir(pagina - 1)}>Página anterior</button>
        <button type="button" disabled={pagina * tamano >= datos.total || paginando} onClick={() => ir(pagina + 1)}>Página siguiente</button></div>
    </footer>}
  </section>, document.body)
}
