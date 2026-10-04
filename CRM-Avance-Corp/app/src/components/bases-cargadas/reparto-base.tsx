// Repartir una base (F5, pedido de Miguel: «darle 40 a un analista y 30 a otro»), con `crm.repartir_base` (B9, todo o
// nada, hasta 500 contactos y 100 analistas por operación). Dos formas, en pestañas:
//  · Por cantidades: una casilla por analista, «En partes iguales» y el contador «70 de 85 por repartir». El servidor
//    elige los contactos sin repartir más antiguos y salta los que tienen seguimiento activo, veto o descanso; si no
//    alcanzan, no reparte NINGUNO y dice cuántos hay. Más de 500 no se envía: se dice y se reparte en varias veces.
//  · Por selección: los contactos de la base (`crm.contactos_de_base`), se marcan y «Asignar a…» un analista. Con
//    «Ver también los repartidos» se puede reasignar. Si uno no es elegible, el servidor no asigna ninguno y dice cuál y
//    por qué (`rechazados`).
// Cada envío lleva un id de operación fijo mientras no cambie lo que se manda (un doble clic o un reintento no reparten
// dos veces). Antes de la B9: «disponible pronto». Foco: si tras repartir o limpiar el control pulsado desaparece, el
// foco va al título «Repartir» o a la primera casilla, nunca a <body>.
import { useId, useRef, useState, type RefObject } from 'react'
import { toast } from 'sonner'
import { Equal, Send, UserCheck, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Tabs } from '@/components/ui/tabs'
import { Paginacion } from '@/components/common/paginacion'
import { PanelCargando } from '@/components/common/estado-panel'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { paginar, POR_PAGINA } from '@/lib/paginacion'
import { fmtFecha } from '@/lib/format'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import { CODIGO_NO_DISPONIBLE, ErrorBases } from '@/data/bases-cargadas-api'
import { CrmApiError } from '@/data/crm-api'
import { useContactosDeBase, useRepartirBase, type PuertasBases } from '@/data/bases-cargadas-queries'
import {
  ESTADOS_ASIGNABLES,
  MAX_REPARTO_CONTACTOS,
  cantidadDesdeTexto,
  errorTopeBloque,
  estadoContador,
  etiquetaEstadoContacto,
  etiquetaMotivoReparto,
  repartirEnPartesIguales,
  repartoEnBloque,
  repartoIndividual,
  resumenOmitidos,
  totalAsignado,
  type FilaSeguimientoBases,
  type RechazadoReparto,
  type RepartoBase,
  type RespuestaRepartir,
} from '@/lib/bases-cargadas'
import type { Miembro } from '@/lib/tipos'
import { AvisoReintentar, CELDA_COMPACTA, DisponiblePronto, ENCABEZADO_COMPACTO } from './piezas-bases'

type Forma = 'cantidades' | 'seleccion'
const FORMAS = [
  { valor: 'cantidades', etiqueta: 'Por cantidades' },
  { valor: 'seleccion', etiqueta: 'Por selección' },
] as const satisfies readonly { valor: Forma; etiqueta: string }[]

const PRONTO = { titulo: 'Repartir: disponible pronto', detalle: 'El reparto de bases llega con la próxima actualización del servidor. La base ya está cargada y lista.' }

type ResultadoEnvio = { ok: true; respuesta: RespuestaRepartir } | { ok: false; mensaje: string; rechazados: RechazadoReparto[] }

/** El envío de un reparto con su id de operación fijo mientras no cambie lo que se manda. */
function useEnvioReparto(puertas: PuertasBases, baseId: string) {
  const mutacion = useRepartirBase(puertas)
  const envio = useRef<{ id: string; firma: string } | null>(null)
  const [noDisponible, setNoDisponible] = useState(false)
  const enviar = async (reparto: RepartoBase): Promise<ResultadoEnvio> => {
    const firma = JSON.stringify(reparto)
    if (envio.current?.firma !== firma) envio.current = { id: crypto.randomUUID(), firma }
    try {
      const respuesta = await mutacion.mutateAsync({ operacionId: envio.current.id, baseId, reparto })
      envio.current = null
      return { ok: true, respuesta }
    } catch (causa: unknown) {
      if (causa instanceof CrmApiError && causa.code === CODIGO_NO_DISPONIBLE) setNoDisponible(true)
      const rechazados = causa instanceof ErrorBases && causa.code === 'RECHAZADOS' ? (causa.detalle as RechazadoReparto[]) : []
      return { ok: false, mensaje: causa instanceof CrmApiError ? causa.message : 'No se pudo repartir. Vuelve a intentarlo.', rechazados }
    }
  }
  return { enviar, enviando: mutacion.isPending, noDisponible }
}

/** «Repartidos 70: ANA 40 · LUIS 30. No se pudieron elegir 5: 3 · en gestión; 2 · ocupado.» */
function avisoRepartido(r: RespuestaRepartir, nombres: ReadonlyMap<string, string>): string {
  const detalle = r.por_analista.map((x) => `${nombres.get(x.analista_id) ?? 'Analista'} ${x.cantidad}`).join(' · ')
  const omitidos = resumenOmitidos(r.omitidos)
  return `Repartidos ${r.repartidos}${detalle ? `: ${detalle}` : ''}.${omitidos.total > 0 ? ` No se pudieron elegir ${omitidos.total}: ${omitidos.detalle}.` : ''}`
}

/** Tras un envío, si el control pulsado desapareció (el foco cayó en <body>), el foco va al título del reparto. */
function rescatarFoco(titulo: RefObject<HTMLElement | null>) {
  requestAnimationFrame(() => {
    const activo = document.activeElement
    if (!activo || activo === document.body || !activo.isConnected) titulo.current?.focus()
  })
}

export function RepartoBase({ puertas, base, analistas, tituloRef }: {
  puertas: PuertasBases
  base: FilaSeguimientoBases
  /** A quién se puede repartir (ya ordenado: el equipo del supervisor dueño primero). */
  analistas: readonly Miembro[]
  /** El título «Repartir · N sin repartir» (enfocable): adónde va el foco si el control pulsado desaparece. */
  tituloRef: RefObject<HTMLElement | null>
}) {
  const [forma, setForma] = useState<Forma>('cantidades')
  return (
    <Tabs etiqueta="Cómo repartir" pestanas={FORMAS} valor={forma} onCambio={setForma} variante="subrayado" panelEnfocable={false}>
      {analistas.length === 0 ? (
        <p className="text-sm text-[var(--muted-foreground-strong)]">No hay analistas activos a quien repartir.</p>
      ) : forma === 'cantidades'
        ? <PorCantidades puertas={puertas} base={base} analistas={analistas} tituloRef={tituloRef} />
        : <PorSeleccion puertas={puertas} base={base} analistas={analistas} tituloRef={tituloRef} />}
    </Tabs>
  )
}

function PorCantidades({ puertas, base, analistas, tituloRef }: { puertas: PuertasBases; base: FilaSeguimientoBases; analistas: readonly Miembro[]; tituloRef: RefObject<HTMLElement | null> }) {
  const id = useId()
  const { enviar, enviando, noDisponible } = useEnvioReparto(puertas, base.base_id)
  const [textos, setTextos] = useState<Record<string, string>>({})
  const [error, setError] = useState<string | null>(null)
  const primeraCasilla = useRef<HTMLInputElement>(null)
  const ids = analistas.map((a) => a.perfil_id)
  const numeros: Record<string, number> = Object.fromEntries(ids.map((a) => [a, cantidadDesdeTexto(textos[a] ?? '')]))
  const asignado = totalAsignado(numeros)
  const disponibles = base.sin_repartir
  const contador = estadoContador(asignado, disponibles)
  const invalido = contador.excede || contador.sobreTope
  const nombres = new Map(analistas.map((a) => [a.perfil_id, a.nombre_completo]))
  const idContador = `${id}-contador`
  const idError = `${id}-error`
  const describe = [idContador, error ? idError : null].filter(Boolean).join(' ')

  if (noDisponible) return <DisponiblePronto {...PRONTO} />
  if (disponibles === 0) {
    return <p className="text-sm text-[var(--muted-foreground-strong)]">No quedan contactos sin repartir. Para mover contactos de un analista a otro, usa «Recoger» en el seguimiento o el reparto por selección.</p>
  }
  const partesIguales = () => {
    // Hasta el tope por operación: con más disponibles se reparte en varias veces.
    const iguales = repartirEnPartesIguales(ids, Math.min(disponibles, MAX_REPARTO_CONTACTOS), numeros)
    setTextos(Object.fromEntries(Object.entries(iguales).map(([a, n]) => [a, n > 0 ? String(n) : ''])))
    setError(null)
  }
  const limpiar = () => {
    setTextos({}); setError(null)
    // «Limpiar» desaparece al vaciar: el foco va a la primera casilla.
    requestAnimationFrame(() => primeraCasilla.current?.focus())
  }
  const repartir = async () => {
    if (enviando) return
    const tope = errorTopeBloque(numeros, disponibles)
    if (tope || !contador.listo) { setError(tope ?? 'Escribe cuántos le das a cada analista.'); return }
    setError(null)
    const r = await enviar(repartoEnBloque(ids, numeros))
    if (r.ok) {
      toast.success(avisoRepartido(r.respuesta, nombres))
      setTextos({})
      rescatarFoco(tituloRef)
    } else setError(r.mensaje)
  }
  return (
    <div className="space-y-3">
      <div className="grid gap-2 sm:grid-cols-[repeat(auto-fill,minmax(17rem,1fr))]">
        {analistas.map((a, i) => (
          <div key={a.perfil_id} className="flex items-center justify-between gap-3 rounded-lg border border-border bg-card px-3 py-1.5">
            <label htmlFor={`${id}-${a.perfil_id}`} className="min-w-0 truncate text-sm font-semibold text-foreground" title={a.nombre_completo}>
              {a.nombre_completo}
              {a.supervisor_id !== base.supervisor_id && <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-[11px] font-bold text-[var(--muted-foreground-strong)]">Otro equipo</span>}
            </label>
            <Input
              ref={i === 0 ? primeraCasilla : undefined}
              id={`${id}-${a.perfil_id}`}
              inputMode="numeric"
              autoComplete="off"
              value={textos[a.perfil_id] ?? ''}
              placeholder="0"
              onChange={(e) => { setTextos((t) => ({ ...t, [a.perfil_id]: e.target.value.replace(/\D/g, '').slice(0, 5) })); setError(null) }}
              aria-invalid={invalido || undefined}
              aria-describedby={describe}
              className="h-9 w-20 text-right tabular-nums pointer-coarse:h-11"
            />
          </div>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-3">
        {/* El contador se ve al teclear; el lector solo oye cuando se pasa (o deja de pasarse), no cada tecla. */}
        <p id={idContador} className={cn('text-sm font-bold tabular-nums', invalido ? 'text-[var(--destructive-text)]' : 'text-foreground')}>
          {contador.texto}{contador.excede ? ` · te pasas por ${asignado - disponibles}` : contador.sobreTope ? ` · más de ${MAX_REPARTO_CONTACTOS} por vez` : ''}
        </p>
        <p role="status" className="sr-only">
          {contador.excede ? `Te pasas: hay ${disponibles} por repartir.` : contador.sobreTope ? `Un reparto mueve hasta ${MAX_REPARTO_CONTACTOS} contactos por vez.` : ''}
        </p>
        <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" onClick={partesIguales}>
          <Equal aria-hidden /> En partes iguales
        </Button>
        {asignado > 0 && (
          <Button type="button" variant="ghost" size="sm" className="pointer-coarse:h-11" onClick={limpiar}>
            <X aria-hidden /> Limpiar
          </Button>
        )}
        <Button type="button" size="sm" className="ml-auto pointer-coarse:h-11" aria-disabled={enviando || !contador.listo || undefined} aria-describedby={describe} onClick={() => void repartir()}>
          <Send aria-hidden /> {enviando ? 'Repartiendo…' : `Repartir ${asignado > 0 ? asignado : ''}`.trim()}
        </Button>
      </div>
      <p className="text-[13px] text-[var(--muted-foreground-strong)]">
        «En partes iguales» reparte entre los que ya tienen cantidad (o entre todos si ninguno tiene), hasta {MAX_REPARTO_CONTACTOS} por vez. El servidor da los contactos más antiguos de la base y salta los que tienen seguimiento activo, veto o descanso; si no alcanzan, no reparte ninguno.
      </p>
      {error && <p id={idError} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{error}</p>}
    </div>
  )
}

function PorSeleccion({ puertas, base, analistas, tituloRef }: { puertas: PuertasBases; base: FilaSeguimientoBases; analistas: readonly Miembro[]; tituloRef: RefObject<HTMLElement | null> }) {
  const id = useId()
  const [verRepartidos, setVerRepartidos] = useState(false)
  const contactos = useContactosDeBase(puertas, base.base_id, verRepartidos ? 'todos' : 'sin_repartir')
  const { enviar, enviando, noDisponible } = useEnvioReparto(puertas, base.base_id)
  const [elegidos, setElegidos] = useState<ReadonlySet<string>>(new Set())
  const [destino, setDestino] = useState('')
  const [pagina, setPagina] = useState(0)
  const [error, setError] = useState<{ texto: string; rechazados: RechazadoReparto[] } | null>(null)

  if (noDisponible || contactos.data === null) return <DisponiblePronto {...PRONTO} />
  if (contactos.isPending) return <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={4} /></div>
  if (contactos.isError && contactos.data === undefined) {
    return <AvisoReintentar mensaje="No se pudieron cargar los contactos de la base." reintentando={contactos.isFetching} onReintentar={() => void contactos.refetch()} />
  }
  const filas = contactos.data ?? []
  const paginado = paginar(filas, pagina)
  const asignablesPagina = paginado.visibles.filter((c) => ESTADOS_ASIGNABLES.has(c.estado))
  const todaLaPagina = asignablesPagina.length > 0 && asignablesPagina.every((c) => elegidos.has(c.lead_id))
  const nombreDe = new Map(filas.map((c) => [c.lead_id, c.nombre_completo]))
  const alternar = (leadId: string) => setElegidos((e) => { const n = new Set(e); if (n.has(leadId)) n.delete(leadId); else n.add(leadId); return n })
  const alternarPagina = () => setElegidos((e) => {
    const n = new Set(e)
    for (const c of asignablesPagina) { if (todaLaPagina) n.delete(c.lead_id); else n.add(c.lead_id) }
    return n
  })
  const nombres = new Map(analistas.map((a) => [a.perfil_id, a.nombre_completo]))
  const asignar = async () => {
    if (enviando) return
    if (elegidos.size === 0) { setError({ texto: 'Marca los contactos que quieres asignar.', rechazados: [] }); return }
    if (elegidos.size > MAX_REPARTO_CONTACTOS) { setError({ texto: `Se asignan hasta ${MAX_REPARTO_CONTACTOS} contactos por vez (marcaste ${elegidos.size}).`, rechazados: [] }); return }
    if (!destino) { setError({ texto: 'Elige a qué analista se los asignas.', rechazados: [] }); return }
    setError(null)
    const r = await enviar(repartoIndividual([...elegidos], destino))
    if (r.ok) {
      toast.success(avisoRepartido({ ...r.respuesta, por_analista: [{ analista_id: destino, cantidad: r.respuesta.repartidos }] }, nombres))
      setElegidos(new Set())
      rescatarFoco(tituloRef)
    } else setError({ texto: r.mensaje, rechazados: r.rechazados })
  }
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex min-h-9 cursor-pointer items-center gap-2 text-sm text-foreground pointer-coarse:min-h-11">
          <input type="checkbox" className="size-4 accent-[var(--accent)]" checked={verRepartidos} onChange={(e) => { setVerRepartidos(e.target.checked); setPagina(0) }} />
          Ver también los repartidos (para reasignar)
        </label>
        <div className="ml-auto flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <label htmlFor={`${id}-destino`} className="text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">Asignar a…</label>
            <Select id={`${id}-destino`} value={destino} onChange={(e) => { setDestino(e.target.value); setError(null) }} className="h-9 min-w-56 pointer-coarse:h-11">
              <option value="">Elige un analista</option>
              {analistas.map((a) => <option key={a.perfil_id} value={a.perfil_id}>{a.nombre_completo}</option>)}
            </Select>
          </div>
          <Button type="button" size="sm" className="h-9 pointer-coarse:h-11" aria-disabled={enviando || undefined} aria-describedby={error ? `${id}-error` : `${id}-elegidos`} onClick={() => void asignar()}>
            <UserCheck aria-hidden /> {enviando ? 'Asignando…' : `Asignar ${elegidos.size || ''}`.trim()}
          </Button>
        </div>
      </div>
      <p id={`${id}-elegidos`} role="status" className="text-sm tabular-nums text-[var(--muted-foreground-strong)]">
        {elegidos.size > 0 ? `${elegidos.size} ${elegidos.size === 1 ? 'contacto elegido' : 'contactos elegidos'}` : ''}
      </p>
      {error && (
        <div id={`${id}-error`} role="alert" className="space-y-1">
          <p className="text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>
          {error.rechazados.length > 0 && (
            <ul className="space-y-0.5 text-sm">
              {error.rechazados.map((x) => (
                <li key={x.lead_id}><strong className="font-semibold">{nombreDe.get(x.lead_id) ?? 'Contacto'}</strong>: {etiquetaMotivoReparto(x.motivo)}</li>
              ))}
            </ul>
          )}
        </div>
      )}
      {filas.length === 0 ? (
        <p className="text-sm text-[var(--muted-foreground-strong)]">{verRepartidos ? 'La base no tiene contactos.' : 'No quedan contactos sin repartir.'}</p>
      ) : (
        <>
          {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La lista se desplaza con el teclado. */}
          <div tabIndex={0} role="region" aria-label={`Contactos de ${base.nombre}`} className={cn('ac-scroll max-h-[22rem] overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
            <table className="min-w-full border-separate border-spacing-0">
              <caption className="sr-only">Contactos de {base.nombre}{verRepartidos ? ', con los repartidos' : ' sin repartir'}: márcalos y asígnalos a un analista.</caption>
              <thead>
                <tr>
                  <th scope="col" className={cn(ENCABEZADO_COMPACTO, 'w-10 text-center')}>
                    <label className="inline-flex cursor-pointer items-center justify-center pointer-coarse:size-11">
                      <input type="checkbox" aria-label="Elegir todos los de esta página" className="size-4 accent-[var(--accent)]" checked={todaLaPagina} disabled={asignablesPagina.length === 0} onChange={alternarPagina} />
                    </label>
                  </th>
                  {['#', 'Contacto', 'Teléfono', 'Distrito', 'Estado', 'Analista', 'En la base desde'].map((c, i) => (
                    <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, i === 0 ? 'w-12 text-center' : 'text-left')}>{c}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {paginado.visibles.map((c, i) => {
                  const asignable = ESTADOS_ASIGNABLES.has(c.estado)
                  return (
                    <tr key={c.lead_id} className={cn(elegidos.has(c.lead_id) ? 'bg-accent/[0.07]' : 'hover:bg-accent/5', !asignable && 'text-[var(--muted-foreground-strong)]')}>
                      <td className={cn(CELDA_COMPACTA, 'py-0 text-center')}>
                        {/* Objetivo táctil de 44 px en pantallas táctiles: la casilla vive dentro de su etiqueta. */}
                        <label className="inline-flex cursor-pointer items-center justify-center pointer-coarse:size-11">
                          <input
                            type="checkbox"
                            aria-label={`Elegir a ${c.nombre_completo}`}
                            className="size-4 accent-[var(--accent)]"
                            checked={elegidos.has(c.lead_id)}
                            disabled={!asignable}
                            onChange={() => alternar(c.lead_id)}
                          />
                        </label>
                      </td>
                      <td className={cn(CELDA_COMPACTA, 'text-center text-[13px] tabular-nums text-[var(--muted-foreground-strong)]')}>{paginado.paginaActual * POR_PAGINA + i + 1}</td>
                      <th scope="row" className={cn(CELDA_COMPACTA, 'max-w-56 truncate text-left font-semibold')} title={c.nombre_completo}>{c.nombre_completo}</th>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{c.telefono ? telefonoLegible(c.telefono) : '—'}</td>
                      <td className={cn(CELDA_COMPACTA, 'max-w-40 truncate')}>{c.distrito ?? '—'}</td>
                      <td className={CELDA_COMPACTA}>{etiquetaEstadoContacto(c.estado)}</td>
                      <td className={cn(CELDA_COMPACTA, 'max-w-48 truncate')}>{c.analista_nombre ?? 'Sin repartir'}</td>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{fmtFecha(c.agregado_en)}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <Paginacion paginaActual={paginado.paginaActual} paginas={paginado.paginas} total={filas.length} onCambio={setPagina} ariaLabel="Páginas de los contactos" />
        </>
      )}
    </div>
  )
}
