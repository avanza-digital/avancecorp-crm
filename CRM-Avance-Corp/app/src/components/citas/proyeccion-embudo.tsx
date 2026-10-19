// Embudo tipo Excel de una cabecera de la Proyección: ordenar, elegir valores
// (analistas, personas o moneda) y acotar Mín/Máx. Se cierra con Esc, al pulsar
// fuera o al salir el foco; al cerrarse con Esc el foco vuelve al embudo.
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { ArrowDownWideNarrow, ArrowUpNarrowWide, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { money, numero } from '@/lib/format'
import { normalizar } from './modelo'
import type { Moneda, OpcionEmbudo, OrdenProyeccion, RangoColumna } from './proyeccion'

export interface CambioEmbudo {
  seleccion?: string[] | undefined
  monedas?: Moneda[] | undefined
  rango?: RangoColumna | undefined
}

interface PropsEmbudo {
  titulo: string
  /** texto: ordena A–Z; el resto, de menor a mayor. */
  tipo: 'texto' | 'num' | 'monto' | 'personas'
  ancla: HTMLElement
  orden: OrdenProyeccion['direccion'] | null
  opciones?: OpcionEmbudo[] | undefined
  seleccion?: readonly string[] | undefined
  monedas?: { opciones: Record<Moneda, { citas: number; monto: number }>; seleccion?: readonly Moneda[] | undefined } | undefined
  rango?: RangoColumna | undefined
  conRango: boolean
  buscarComo: string
  onOrdenar: (direccion: OrdenProyeccion['direccion']) => void
  onAplicar: (cambio: CambioEmbudo) => void
  onBorrar: () => void
  onCerrar: () => void
}

const citasTexto = (n: number) => `${numero(n)} ${n === 1 ? 'cita' : 'citas'}`
const numeroOVacio = (texto: string) => texto.trim() === '' || !Number.isFinite(Number(texto)) ? undefined : Number(texto)

export function EmbudoColumna({ titulo, tipo, ancla, orden, opciones, seleccion, monedas, rango, conRango, buscarComo, onOrdenar, onAplicar, onBorrar, onCerrar }: PropsEmbudo) {
  const caja = useRef<HTMLDivElement>(null)
  const busca = useRef<HTMLInputElement>(null)
  const primero = useRef<HTMLButtonElement>(null)
  const [posicion, setPosicion] = useState({ left: 8, top: 8, maxHeight: 480 })
  const [marcados, setMarcados] = useState(() => new Set(seleccion ?? opciones?.map(o => o.id) ?? []))
  const [monedasMarcadas, setMonedasMarcadas] = useState(() => new Set<Moneda>(monedas?.seleccion ?? ['PEN', 'USD']))
  const [texto, setTexto] = useState('')
  const [min, setMin] = useState(rango?.min?.toString() ?? '')
  const [max, setMax] = useState(rango?.max?.toString() ?? '')
  const visibles = (opciones ?? []).filter(o => normalizar(o.nombre).includes(normalizar(texto)))
  const todosVisibles = visibles.length > 0 && visibles.every(o => marcados.has(o.id))

  useLayoutEffect(() => {
    const r = ancla.getBoundingClientRect()
    const top = Math.min(r.bottom + 4, Math.max(8, window.innerHeight - 220))
    setPosicion({ left: Math.max(8, Math.min(r.left, window.innerWidth - 288)), top, maxHeight: window.innerHeight - top - 8 })
  }, [ancla])
  useEffect(() => {
    const menu = caja.current
    ;(busca.current ?? primero.current)?.focus()
    const fuera = (evento: PointerEvent) => {
      const destino = evento.target as Node | null
      if (destino && !menu?.contains(destino) && !ancla.contains(destino)) onCerrar()
    }
    const teclado = (evento: KeyboardEvent) => {
      // El menú vive al final del documento: Tab en sus extremos lo cierra y
      // devuelve el foco al embudo, para seguir por la cabecera.
      const focables = menu ? [...menu.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled)')]
        .sort((a, b) => a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1) : []
      const extremo = evento.shiftKey ? focables[0] : focables.at(-1)
      if (evento.key !== 'Escape' && !(evento.key === 'Tab' && document.activeElement === extremo)) return
      evento.preventDefault()
      evento.stopPropagation()
      onCerrar()
      ancla.focus()
    }
    // El foco que sale del menú (Tab) lo cierra, salvo que vuelva al propio embudo.
    const salir = (evento: FocusEvent) => {
      const destino = evento.relatedTarget as Node | null
      if (destino && !menu?.contains(destino) && destino !== ancla) onCerrar()
    }
    document.addEventListener('pointerdown', fuera)
    menu?.addEventListener('keydown', teclado)
    menu?.addEventListener('focusout', salir)
    return () => {
      document.removeEventListener('pointerdown', fuera)
      menu?.removeEventListener('keydown', teclado)
      menu?.removeEventListener('focusout', salir)
    }
  }, [ancla, onCerrar])

  function cerrarConFoco() { onCerrar(); ancla.focus() }
  function alternar(id: string) {
    setMarcados(actual => { const siguiente = new Set(actual); if (siguiente.has(id)) siguiente.delete(id); else siguiente.add(id); return siguiente })
  }
  function alternarTodos() {
    setMarcados(actual => { const siguiente = new Set(actual); for (const o of visibles) if (todosVisibles) siguiente.delete(o.id); else siguiente.add(o.id); return siguiente })
  }
  function alternarMoneda(moneda: Moneda) {
    setMonedasMarcadas(actual => { const siguiente = new Set(actual); if (siguiente.has(moneda)) siguiente.delete(moneda); else siguiente.add(moneda); return siguiente })
  }
  function aplicar() {
    const limites = { min: numeroOVacio(min), max: numeroOVacio(max) }
    onAplicar({
      // Solo cuentan las opciones que existen ahora: un id viejo no deja un filtro fantasma.
      seleccion: opciones && opciones.some(o => !marcados.has(o.id)) ? opciones.map(o => o.id).filter(id => marcados.has(id)) : undefined,
      monedas: monedas && monedasMarcadas.size !== 2 ? [...monedasMarcadas] : undefined,
      rango: conRango && (limites.min !== undefined || limites.max !== undefined) ? limites : undefined,
    })
    cerrarConFoco()
  }
  const texto1 = tipo === 'texto' ? 'Ordenar de A a Z' : 'Ordenar de menor a mayor'
  const texto2 = tipo === 'texto' ? 'Ordenar de Z a A' : 'Ordenar de mayor a menor'

  return createPortal(
    <div ref={caja} role="dialog" aria-label={`Filtrar ${titulo}`} className="pc-menu citas-crm-dialogo" style={posicion}>
      <p className="pc-menu-titulo" aria-hidden>{titulo}</p>
      <button ref={primero} type="button" className="pc-menu-item" aria-pressed={orden === 'asc'} onClick={() => { onOrdenar('asc'); cerrarConFoco() }}><ArrowUpNarrowWide aria-hidden />{texto1}</button>
      <button type="button" className="pc-menu-item" aria-pressed={orden === 'desc'} onClick={() => { onOrdenar('desc'); cerrarConFoco() }}><ArrowDownWideNarrow aria-hidden />{texto2}</button>
      <hr />
      {/* Enter en un campo aplica, como el botón. */}
      <form noValidate onSubmit={evento => { evento.preventDefault(); aplicar() }}>
      {opciones && <>
        <div className="pc-menu-busca"><div className="relative"><Search aria-hidden className="pointer-events-none absolute top-2.5 left-3 size-4 text-muted-foreground" />
          <Input ref={busca} type="search" className="h-9 pl-9" aria-label={`Buscar ${buscarComo}`} placeholder={`Buscar ${buscarComo}`} value={texto} onChange={e => setTexto(e.target.value)} /></div></div>
        <div className="pc-menu-lista" role="group" aria-label={titulo}>
          <label className="pc-op"><input ref={casilla => { if (casilla) casilla.indeterminate = !todosVisibles && visibles.some(o => marcados.has(o.id)) }} type="checkbox" aria-label="Seleccionar todo" checked={todosVisibles} onChange={alternarTodos} disabled={!visibles.length} /><span>(Seleccionar todo)</span><small>{visibles.length}</small></label>
          {visibles.map(o => <label key={o.id} className="pc-op"><input type="checkbox" aria-label={`${o.nombre} · ${citasTexto(o.citas)}`} checked={marcados.has(o.id)} onChange={() => alternar(o.id)} /><span>{o.nombre}</span><small>{numero(o.citas)}</small></label>)}
        </div>
      </>}
      {monedas && <><div className="pc-menu-lista" role="group" aria-label="Moneda">
        {(['PEN', 'USD'] as const).map(moneda => <label key={moneda} className="pc-op"><input type="checkbox" aria-label={`${moneda === 'PEN' ? 'Soles' : 'Dólares'} · ${money(monedas.opciones[moneda].monto, moneda)} · ${citasTexto(monedas.opciones[moneda].citas)}`} checked={monedasMarcadas.has(moneda)} onChange={() => alternarMoneda(moneda)} />
          <span>{moneda === 'PEN' ? 'Soles' : 'Dólares'} · {money(monedas.opciones[moneda].monto, moneda)}</span><small>{numero(monedas.opciones[moneda].citas)}</small></label>)}
      </div><hr /></>}
      {conRango && <div className="pc-rango">
        <label>Mín<Input type="number" inputMode="decimal" className="h-9" value={min} onChange={e => setMin(e.target.value)} /></label>
        <label>Máx<Input type="number" inputMode="decimal" className="h-9" value={max} onChange={e => setMax(e.target.value)} /></label>
      </div>}
      <div className="pc-menu-pie">
        <Button type="button" variant="outline" size="sm" onClick={() => { onBorrar(); cerrarConFoco() }}>Borrar</Button>
        <Button type="submit" size="sm">Aplicar</Button>
      </div>
      </form>
    </div>,
    document.body,
  )
}
