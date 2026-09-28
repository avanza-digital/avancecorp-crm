// Registro crudo de actividad (Gestión Diaria, Fase 1): UN solo componente
// para el analista (lo suyo), el supervisor (su equipo) y gerencia (todo, por
// equipo, exportable). Lee `crm.registro_actividad_fn` por cursor; el servidor
// decide el alcance (RLS) y el orden; aquí solo se filtra por pestaña, etapa,
// equipo y analista, y se presenta el texto ÍNTEGRO de cada gestión, que es lo
// que el supervisor tiene que poder leer para corregir a la persona el mismo día.
//
// Diferido a la Fase 2 respecto del plan (se declara aquí y en el acta): la
// acción «Nota de revisión» sobre una llamada contradictoria viaja con el
// resultado tipificado (`metadata.evento = 'revision'`); el «buscador» de
// analista es un desplegable (≤ 20 nombres); el CSV exporta las filas CARGADAS,
// no el día entero (el aviso lo dice con el número exacto).
import { useEffect, useEffectEvent, useId, useLayoutEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { ArrowUpRight, ClipboardList, Download, RefreshCw } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { ETAPA_INFO, ETAPAS, TERMINALES, type Etapa } from '@/lib/tipos'
import {
  ETIQUETA_CORTA, PESTANAS_REGISTRO, analistasDelEquipo, cursorSiguiente, filasCsvRegistro, horaDeItem, paginaVisible, tonoDeTipo,
  type CursorRegistro, type FiltrosRegistro, type PestanaRegistro, type RegistroItem,
} from '@/lib/gestion-diaria'
import { useRegistroActividadOperativo } from '@/data/gestion-diaria-queries'
import { CrmApiError } from '@/data/crm-api'
import { csvDe, descargarCsv } from '@/lib/exportar-csv'
import { Tabs } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { BOTON_CABECERA } from './estilos-gestion'

const LIMITE_PAGINA = 25
// Tokens de TEXTO: el chip `soft` pinta el color puro sobre un tinte al 12 %, y
// ahí `--warning` da ~3:1 (index.css). Misma escala que el chip de nivel de «Mi
// día», que ahora convive con este en la pantalla del analista.
const TONO: Record<'ok' | 'atencion' | 'neutro', string> = {
  ok: 'var(--primary)',
  atencion: 'var(--warning-text)',
  neutro: 'var(--muted-foreground-strong)',
}
const TODAS_LAS_ETAPAS = [...ETAPAS, ...TERMINALES]

interface Props {
  /** Día Lima (YYYY-MM-DD) que se lista. */
  dia: string
  /** null = todo lo que la RLS deje ver; el analista pasa su propio id. */
  analistaIds: readonly string[] | null
  /** Supervisor y gerencia: filtro por analista y columna de autor. */
  mostrarAnalista: boolean
  /** Solo gerencia: filtro por equipo (supervisor). */
  permitirEquipo?: boolean | undefined
  /** Solo gerencia: el CSV lleva el detalle íntegro (PII) y sale del CRM. */
  permitirExportar: boolean
  /** F4: el registro general abre Todo; el desglose horario abre Llamadas. */
  pestanaInicial?: PestanaRegistro
  /** Refresco externo: conserva filtros y vuelve a la primera página. */
  actualizacion?: number | undefined
  onSinPermiso?: (() => void) | undefined
  /** H3: comparte la primera página sin filtro con Últimas gestiones. */
  compartirPrimeraPagina?: boolean
  /**
   * «¿Qué hice hoy?» del analista (diseño del 27/09/2026): título corto,
   * filtros en pastilla y filas limpias, sin la descripción, el filtro de etapa
   * ni el «Actualizar» propio (la pantalla ya se refresca cada minuto).
   * Supervisor y gerencia conservan su versión hasta sus propios planes.
   */
  compacto?: boolean
  /**
   * Compacto dentro de la ficha del supervisor (27/09/2026): el título lo pone
   * la ficha y el foco de respaldo («Ver más» que se va, «Reintentar») va a él.
   * Gerencia usa esta misma versión (Miguel, 27/09: «como lo ve el supervisor»)
   * y conserva lo suyo en el mismo tamaño: filtro por equipo y CSV.
   */
  encabezadoExterno?: RefObject<HTMLHeadingElement | null> | undefined
}

export function RegistroActividad(props: Props) {
  const { yo } = useAuth()
  // La memoria paginada y los selectores no cruzan identidades, días ni ámbitos.
  const identidad = JSON.stringify([yo?.id, yo?.rol, yo?.demo, props.dia, props.analistaIds, props.pestanaInicial])
  return <RegistroDelAmbito key={identidad} {...props} />
}

function RegistroDelAmbito({ dia, analistaIds, mostrarAnalista, permitirEquipo = false, permitirExportar, pestanaInicial = 'llamadas', actualizacion = 0, onSinPermiso, compartirPrimeraPagina = false, compacto = false, encabezadoExterno }: Props) {
  const { yo } = useAuth()
  const ahora = useAhora()
  const { equipo, ambito } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const id = useId()
  const [pestana, setPestana] = useState<PestanaRegistro>(pestanaInicial)
  const [etapa, setEtapa] = useState<Etapa | null>(null)
  const [equipoSel, setEquipoSel] = useState<string | null>(null)
  const [analista, setAnalista] = useState<string | null>(null)
  // Paginación por cursor: las páginas ya vistas se acumulan; solo la primera
  // se refresca sola (las siguientes son keyset hacia atrás, estables).
  const [previas, setPrevias] = useState<RegistroItem[]>([])
  const [cursor, setCursor] = useState<CursorRegistro | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [reinicio, setReinicio] = useState(0)
  const propio = useRef<HTMLHeadingElement>(null)
  const encabezado = encabezadoExterno ?? propio

  const idsEquipo = useMemo(() => (equipoSel ? analistasDelEquipo(equipo, equipoSel) : null), [equipo, equipoSel])
  const filtros = useMemo<FiltrosRegistro>(() => ({
    dia,
    analistaIds: analista ? [analista] : idsEquipo ?? analistaIds,
    pestana,
    etapa,
  }), [analista, analistaIds, dia, etapa, idsEquipo, pestana])
  // Cualquier cambio de filtro o de día vuelve a la primera página EN EL MISMO
  // render (estado derivado): así la primera consulta con filtros nuevos ya sale
  // sin cursor viejo, y el aviso de exportación no sobrevive a otra vista.
  const claveFiltros = JSON.stringify([filtros, actualizacion])
  const [claveVista, setClaveVista] = useState(claveFiltros)
  if (claveVista !== claveFiltros) {
    setClaveVista(claveFiltros)
    setPrevias([])
    setCursor(null)
    setAviso(null)
  }
  const cursorVigente = claveVista === claveFiltros ? cursor : null
  const previasVigentes = claveVista === claveFiltros ? previas : []

  const { pagina, cargando, enVuelo, error, recargar } = useRegistroActividadOperativo(filtros, cursorVigente, LIMITE_PAGINA, true, compartirPrimeraPagina)
  const sinPermiso = error instanceof CrmApiError && error.code === '42501'
  const versionRecarga = `${actualizacion}:${reinicio}`
  const versionRecargada = useRef(versionRecarga)
  const recargarDesdeFuera = useEffectEvent(() => { void recargar() })
  const notificarRevocacion = useEffectEvent(() => { onSinPermiso?.() })
  useEffect(() => {
    if (versionRecargada.current === versionRecarga) return
    versionRecargada.current = versionRecarga
    recargarDesdeFuera()
  }, [versionRecarga])
  useEffect(() => {
    if (sinPermiso) notificarRevocacion()
  }, [sinPermiso])
  // Un fallo de red conserva páginas confirmadas; una revocación NO. Borrar
  // también la memoria evita que reaparezca al reintentar la página siguiente.
  if (sinPermiso && previas.length > 0) setPrevias([])
  const actual = pagina ? paginaVisible(pagina.items, LIMITE_PAGINA) : null
  const visibles = sinPermiso ? [] : actual ? [...previasVigentes, ...actual.items] : previasVigentes
  const hayMas = actual?.hayMas ?? false

  // Selector de analista: el ámbito VISIBLE del actor (el store lo recorta por
  // rol), acotado por el equipo elegido y por los ids que manda la pantalla.
  const analistas = useMemo(() => ambito.vendedores
    .filter((m) => m.activo && (idsEquipo === null || idsEquipo.includes(m.perfil_id)) && (analistaIds === null || analistaIds.includes(m.perfil_id)))
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')), [ambito.vendedores, analistaIds, idsEquipo])
  const supervisores = useMemo(() => equipo
    .filter((m) => m.activo && m.rol_crm === 'supervisor')
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')), [equipo])

  function verMas() {
    if (!actual || !hayMas || enVuelo) return
    const siguiente = cursorSiguiente(actual.items)
    if (!siguiente) return
    setPrevias((p) => [...p, ...actual.items])
    setCursor(siguiente)
  }
  function reiniciar() {
    setPrevias([]); setCursor(null); setAviso(null)
    if (compartirPrimeraPagina || cursorVigente === null) setReinicio(n => n + 1)
    encabezado.current?.focus()
  }
  function exportar() {
    const { cabecera, filas } = filasCsvRegistro(visibles)
    const ok = descargarCsv(`registro-actividad-${dia}${analista ? '-analista' : equipoSel ? '-equipo' : ''}.csv`, csvDe(cabecera, filas))
    setAviso(ok ? `Exportadas ${visibles.length} filas cargadas del ${dia}.` : 'No se pudo exportar. Vuelve a intentarlo.')
  }

  const corte = pagina ? new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(pagina.generado_en)) : null
  // El reloj de la APP (useAhora), no `new Date()`: con el reloj real esta
  // comparación cambiaba sola al pasar la medianoche de Lima y el rótulo «de
  // hoy» dejaba de coincidir con el día que se está listando.
  const esHoy = dia === fechaLima(ahora)
  const seRefresca = esHoy && cursorVigente === null

  const lista = (
    <>
      <p role="status" aria-live="polite" className="text-base text-[var(--muted-foreground-strong)]">
        {visibles.length} {visibles.length === 1 ? 'gestión' : 'gestiones'} cargadas{hayMas ? ' · hay más' : ''}{enVuelo ? ' · actualizando…' : ''}
      </p>
      <ol aria-label="Registro de actividad" aria-busy={enVuelo} className="divide-y divide-border rounded-xl border border-border bg-card">
        {visibles.map((item) => {
          const tono = tonoDeTipo(item.tipo)
          const etapaEntonces = item.etapa_en_ese_momento ? ETAPA_INFO[item.etapa_en_ese_momento as Etapa]?.label ?? item.etapa_en_ese_momento : null
          const etapaActual = ETAPA_INFO[item.lead_etapa as Etapa]?.label ?? item.lead_etapa
          const resultado = typeof item.metadata['resultado'] === 'string' ? (item.metadata['resultado'] as string) : null
          return (
            <li key={item.id} className="grid gap-x-4 gap-y-1 px-4 py-3 sm:grid-cols-[4.5rem_1fr]">
              <time dateTime={item.creado_en} className="text-base font-bold tabular-nums text-primary">{horaDeItem(item)}</time>
              <div className="min-w-0 space-y-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge className="text-base leading-normal" color={TONO[tono]} dot>{ETIQUETA_CORTA[item.tipo]}</Badge>
                  {resultado && <Badge className="text-base leading-normal" color="var(--primary)" variant="outline">{resultado.replaceAll('_', ' ')}</Badge>}
                  <button type="button" onClick={() => void abrirLead(item.lead_id)}
                    className="inline-flex min-h-11 items-center gap-1 rounded-md text-base font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">
                    {item.lead_nombre} <ArrowUpRight aria-hidden className="size-3.5" />
                  </button>
                  <span className="text-base text-[var(--muted-foreground-strong)]">
                    {etapaEntonces ? `${etapaEntonces} entonces · ` : ''}{etapaActual} ahora
                  </span>
                  {mostrarAnalista && <span className="text-base font-semibold text-[var(--muted-foreground-strong)]">· {item.autor_nombre}</span>}
                </div>
                {item.detalle
                  ? <p className="whitespace-pre-wrap break-words text-base leading-relaxed text-foreground">{item.detalle}</p>
                  : <p className="text-base italic text-[var(--muted-foreground-strong)]">Sin detalle escrito.</p>}
              </div>
            </li>
          )
        })}
      </ol>
      {error && visibles.length > 0 && (
        <p role="alert" className="text-base font-semibold text-[var(--warning-text)]">No se pudo traer la siguiente página. Se conservan las páginas ya consultadas; no confirman cambios posteriores.</p>
      )}
      {(hayMas || (error && visibles.length > 0)) && (
        <div className="flex justify-center">
          <Button variant="outline" className="min-h-11 text-base" disabled={enVuelo} onClick={error ? () => void recargar() : verMas}>{error ? 'Reintentar' : 'Ver más'}</Button>
        </div>
      )}
      {yo?.demo && <p className="text-base text-[var(--muted-foreground-strong)]">Datos de ejemplo: en la sesión real el registro sale del servidor.</p>}
    </>
  )

  // Mientras llega la página siguiente, `pagina` es null y `hayMas` se apaga:
  // el botón seguiría desmontándose con el foco dentro (revisión a11y, 27/09).
  const cargandoSiguiente = cursorVigente !== null && !pagina && !error
  const listaCompacta = (
    <>
      {/* Sin «actualizando…»: con el refresco de cada minuto el lector lo
          anunciaba dos veces por minuto. La lista ya lleva `aria-busy`. */}
      <p role="status" aria-live="polite" className="sr-only">
        {visibles.length} {visibles.length === 1 ? 'gestión' : 'gestiones'} cargadas{hayMas ? ' · hay más' : ''}
      </p>
      {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
      <ol role="list" aria-label="Registro de actividad" aria-busy={enVuelo}>
        {visibles.map((item) => {
          const tono = tonoDeTipo(item.tipo)
          const etapaEntonces = item.etapa_en_ese_momento ? ETAPA_INFO[item.etapa_en_ese_momento as Etapa]?.label ?? item.etapa_en_ese_momento : null
          const etapaActual = ETAPA_INFO[item.lead_etapa as Etapa]?.label ?? item.lead_etapa
          const resultado = typeof item.metadata['resultado'] === 'string' ? (item.metadata['resultado'] as string) : null
          return (
            <li key={item.id} className="flex gap-3 border-b border-muted py-2.5">
              <time dateTime={item.creado_en} className="w-10 shrink-0 pt-0.5 text-[13px] font-bold tabular-nums text-foreground/80">{horaDeItem(item)}</time>
              <div className="min-w-0 flex-1 space-y-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge className="min-h-[22px] py-0 text-[11.5px]" color={TONO[tono]}>{ETIQUETA_CORTA[item.tipo]}</Badge>
                  {resultado && <Badge className="min-h-[22px] py-0 text-[11.5px]" color="var(--primary)" variant="outline">{resultado.replaceAll('_', ' ')}</Badge>}
                  <button type="button" onClick={() => void abrirLead(item.lead_id)}
                    className="rounded-md text-left text-sm font-bold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">
                    {item.lead_nombre}
                  </button>
                  {mostrarAnalista && <span className="text-[12.5px] font-semibold text-[var(--muted-foreground-strong)]">· {item.autor_nombre}</span>}
                </div>
                {item.detalle && <p className="whitespace-pre-wrap break-words text-[13px] leading-snug text-foreground/80">{item.detalle}</p>}
                <p className="text-[11.5px] text-[var(--muted-foreground-strong)]">{etapaEntonces ? `${etapaEntonces} entonces · ` : ''}{etapaActual} ahora</p>
              </div>
            </li>
          )
        })}
      </ol>
      {error && visibles.length > 0 && (
        <p role="alert" className="text-[13px] font-semibold text-[var(--warning-text)]">No se pudo traer la siguiente página. Se conservan las ya consultadas.</p>
      )}
      {(hayMas || cargandoSiguiente || (error && visibles.length > 0)) && (
        <div className="flex justify-center pt-2">
          <BotonVerMasCompacto ocupado={enVuelo} error={Boolean(error)}
            onPulsar={error ? () => void recargar() : verMas}
            alSalirConFoco={() => encabezado.current?.focus({ preventScroll: true })} />
        </div>
      )}
    </>
  )

  const panel = sinPermiso ? (
    <div role="alert" className="space-y-2 rounded-xl border border-border bg-card p-6 text-base">
      <h4 className="font-semibold text-primary">Ya no tienes autorización para ver este registro</h4>
      <p>Revisa tu acceso con gerencia. No se muestran las páginas anteriores.</p>
    </div>
  ) : error && visibles.length === 0 ? (
    <div role="alert" className="space-y-3 rounded-xl border border-border bg-card p-6 text-base">
      <p className="font-semibold text-primary">No se pudo cargar el registro. Lo que ves no está confirmado.</p>
      <p>No significa que no haya actividad. Vuelve a intentarlo.</p>
      <Button variant="outline" className="min-h-11 text-base" disabled={enVuelo} onClick={reiniciar}>Reintentar</Button>
    </div>
  ) : !pagina && cargando && visibles.length === 0 ? (
    <PanelCargando filas={5} />
  ) : !pagina && visibles.length === 0 ? (
    <PanelVacio tamano="grande" icono={ClipboardList} titulo="Registro no disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
  ) : visibles.length === 0 ? (
    <PanelVacio tamano="grande" icono={ClipboardList} titulo={pestana === 'todo' && etapa === null ? (esHoy ? 'Todavía no hay actividad hoy' : 'Sin actividad ese día') : 'No hay actividad con estos filtros'}
      detalle={pestana === 'todo' && etapa === null ? 'Ninguna gestión registrada en el ámbito consultado.' : 'Prueba con la pestaña «Todo» u otra etapa. Esto no significa que no haya otras gestiones.'} />
  ) : compacto ? listaCompacta : lista

  const pastillas = (
    <Tabs variante="pastilla" etiqueta="Tipo de actividad" pestanas={PESTANAS_REGISTRO} valor={pestana} onCambio={setPestana}
      className="space-y-2 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold">
      {panel}
    </Tabs>
  )
  if (compacto && encabezadoExterno) {
    const rotulo = 'flex flex-wrap items-center gap-2 text-[13px] font-semibold text-[var(--muted-foreground-strong)]'
    return (
      <div className="space-y-2">
        {permitirEquipo && (
          <label htmlFor={`${id}-equipo`} className={rotulo}>Equipo
            <Select id={`${id}-equipo`} value={equipoSel ?? ''} onChange={(e) => { setEquipoSel(e.target.value || null); setAnalista(null) }} className="h-9 min-h-0 w-auto min-w-48 text-[13px]">
              <option value="">Todos los equipos</option>
              {supervisores.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
            </Select>
          </label>
        )}
        {mostrarAnalista && analistaIds?.length !== 1 && (
          <label htmlFor={`${id}-analista`} className={rotulo}>Analista
            <Select id={`${id}-analista`} value={analista ?? ''} onChange={(e) => setAnalista(e.target.value || null)} className="h-9 min-h-0 w-auto min-w-48 text-[13px]">
              <option value="">Todos los analistas</option>
              {analistas.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
            </Select>
          </label>
        )}
        {permitirExportar && (
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            {/* `aria-disabled` y no `disabled`: sin filas no se exporta, pero el foco no se pierde. */}
            <button type="button" className={BOTON_CABECERA} aria-disabled={visibles.length === 0} onClick={() => { if (visibles.length > 0) exportar() }}>
              <Download aria-hidden className="size-4" />Exportar CSV
            </button>
            {/* Montada siempre: una región que nace con su texto no se anuncia (a11y, 27/09). */}
            <p role="status" aria-live="polite" className="text-[12.5px] text-[var(--muted-foreground-strong)]">{sinPermiso ? '' : aviso ?? ''}</p>
          </div>
        )}
        {pastillas}
      </div>
    )
  }
  if (compacto) {
    return (
      <section aria-labelledby={`${id}-titulo`} className="space-y-2">
        <h3 ref={propio} tabIndex={-1} id={`${id}-titulo`} className="text-[15px] font-extrabold text-primary">
          ¿Qué hice hoy?
        </h3>
        {pastillas}
      </section>
    )
  }

  return (
    <section aria-labelledby={`${id}-titulo`} className="space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h3 ref={propio} tabIndex={-1} id={`${id}-titulo`} className="text-base font-bold text-primary">
            Registro de actividad {esHoy ? 'de hoy' : `del ${dia}`}
          </h3>
          <p className="max-w-3xl text-base text-[var(--muted-foreground-strong)]">
            Texto íntegro de cada gestión, tal como se registró. {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'}{seRefresca ? ' · se actualiza cada minuto' : cursorVigente ? ' · foto fija mientras paginas' : ''}.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" className="min-h-11 text-base" disabled={enVuelo} onClick={reiniciar}>
            <RefreshCw aria-hidden className={enVuelo ? 'motion-safe:animate-spin' : ''} /> Actualizar
          </Button>
          {permitirExportar && (
            <Button variant="outline" className="min-h-11 text-base" disabled={visibles.length === 0} onClick={exportar}>
              <Download aria-hidden /> Exportar CSV
            </Button>
          )}
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <label htmlFor={`${id}-etapa`} className="text-base font-semibold text-[var(--muted-foreground-strong)]">Etapa actual del lead
          <Select id={`${id}-etapa`} value={etapa ?? ''} onChange={(e) => setEtapa((e.target.value || null) as Etapa | null)} className="mt-1 min-h-11 min-w-48 text-base">
            <option value="">Todas las etapas</option>
            {TODAS_LAS_ETAPAS.map((e) => <option key={e.k} value={e.k}>{e.label}</option>)}
          </Select>
        </label>
        {permitirEquipo && (
          <label htmlFor={`${id}-equipo`} className="text-base font-semibold text-[var(--muted-foreground-strong)]">Equipo
            <Select id={`${id}-equipo`} value={equipoSel ?? ''} onChange={(e) => { setEquipoSel(e.target.value || null); setAnalista(null) }} className="mt-1 min-h-11 min-w-56 text-base">
              <option value="">Todos los equipos</option>
              {supervisores.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
            </Select>
          </label>
        )}
        {mostrarAnalista && analistaIds?.length !== 1 && (
          <label htmlFor={`${id}-analista`} className="text-base font-semibold text-[var(--muted-foreground-strong)]">Analista
            <Select id={`${id}-analista`} value={analista ?? ''} onChange={(e) => setAnalista(e.target.value || null)} className="mt-1 min-h-11 min-w-56 text-base">
              <option value="">Todos los analistas</option>
              {analistas.map((m) => <option key={m.perfil_id} value={m.perfil_id}>{m.nombre_completo}</option>)}
            </Select>
          </label>
        )}
      </div>

      <p role="status" aria-live="polite" className="text-base font-semibold text-[var(--muted-foreground-strong)]">{sinPermiso ? '' : aviso ?? ''}</p>

      <Tabs tamano="grande" className="[&_[role=tablist]]:grid [&_[role=tablist]]:grid-cols-2 lg:[&_[role=tablist]]:flex"
        etiqueta="Tipo de actividad" pestanas={PESTANAS_REGISTRO} valor={pestana} onCambio={setPestana}>
        {panel}
      </Tabs>
    </section>
  )
}

/**
 * «Ver más» de la versión compacta: `aria-disabled` y no `disabled` mientras
 * carga (el refresco de cada minuto no expulsa el foco), y si deja de hacer
 * falta con el foco DENTRO, lo entrega al título «¿Qué hice hoy?» en vez de
 * dejarlo caer al inicio de la página.
 */
function BotonVerMasCompacto({ ocupado, error, onPulsar, alSalirConFoco }: {
  ocupado: boolean
  error: boolean
  onPulsar: () => void
  alSalirConFoco: () => void
}) {
  const boton = useRef<HTMLButtonElement>(null)
  const salir = useRef(alSalirConFoco)
  salir.current = alSalirConFoco
  useLayoutEffect(() => {
    const nodo = boton.current
    // Al desmontarse el nodo todavía está en el documento: se sabe si tenía el foco.
    return () => { if (nodo !== null && document.activeElement === nodo) salir.current() }
  }, [])
  return (
    <button ref={boton} type="button" aria-disabled={ocupado} aria-busy={ocupado || undefined} onClick={() => { if (!ocupado) onPulsar() }}
      className="inline-flex h-9 cursor-pointer items-center rounded-[10px] px-3 text-[13px] font-bold text-[var(--accent-press)] transition-colors hover:bg-accent/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-50">
      {ocupado ? 'Cargando…' : error ? 'Reintentar' : 'Ver más'}
    </button>
  )
}
