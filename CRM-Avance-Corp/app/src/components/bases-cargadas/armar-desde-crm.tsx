// «Cargar base» → «Armar desde el CRM» (F5, E1/E12 de Miguel): una base con descartados que YA están en el CRM. Usa la
// misma lista y los mismos filtros de «Gestión de la base» (F4: analista anterior, mes, motivo, etapa máxima y último
// resultado): se ve el conteo, se le pone nombre y se arma con `crm.armar_base_crm`. Lo que tiene seguimiento activo (B6:
// un intento de los últimos 7 días o una rellamada agendada) sale en gris y no se envía; el servidor vuelve a decidir y
// devuelve los incluidos y los excluidos con su motivo («ocupado» = otro proceso lo tenía: reintenta).
import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { Layers, RotateCcw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { BarraFiltros, Pastilla } from '@/components/base-gestion/filtros-base'
import { EtapaMaximaChip, MesDelLead } from '@/components/base-gestion/piezas-base'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { useBaseGestionEquipo } from '@/data/crm-queries'
import { ErrorBases, type ArmarBaseEntrada } from '@/data/bases-cargadas-api'
import { useArmarBase, type PuertasBases } from '@/data/bases-cargadas-queries'
import { CrmApiError } from '@/data/crm-api'
import { fechaLima } from '@/lib/agenda-derivada'
import { paginar } from '@/lib/paginacion'
import { cn } from '@/lib/utils'
import {
  SIN_FILTROS,
  demoBaseEquipo,
  esVetada,
  etiquetaAnalista,
  etiquetaMotivoDescarte,
  etiquetaUltimoResultado,
  filtrarBase,
  hayFiltros,
  mesesDeLaBase,
  opcionesFiltro,
  type DimensionFiltro,
  type FiltrosBase,
} from '@/lib/base-gestion'
import {
  MAX_LEADS_ARMAR,
  enGestionHasta,
  errorNombreBase,
  etiquetaMotivoExcluido,
  excluidosPorMotivo,
  type RespuestaArmarBase,
} from '@/lib/bases-cargadas'
import type { Miembro } from '@/lib/tipos'
import { AvisoReintentar, CELDA_COMPACTA, ENCABEZADO_COMPACTO, ROTULO } from './piezas-bases'

const diaMes = (ms: number) => { const [, mes, dia] = fechaLima(ms).split('-'); return `${dia}/${mes}` }

function ListaExcluidos({ porMotivo }: { porMotivo: Readonly<Record<string, readonly number[]>> }) {
  const lista = excluidosPorMotivo(porMotivo)
  if (lista.length === 0) return null
  return (
    <ul className="space-y-1 text-sm">
      {lista.map(({ motivo, n }) => (
        <li key={motivo} className="flex items-baseline gap-2">
          <strong className="w-12 text-right tabular-nums text-foreground">{n}</strong>
          <span className={motivo === 'ocupado' ? 'font-semibold text-[var(--warning-text)]' : 'text-[var(--muted-foreground-strong)]'}>{etiquetaMotivoExcluido(motivo)}</span>
        </li>
      ))}
    </ul>
  )
}

export function ArmarDesdeCrm({ puertas, esGerencia, supervisores, onVerBase }: {
  puertas: PuertasBases
  esGerencia: boolean
  supervisores: readonly Miembro[]
  onVerBase: (baseId: string) => void
}) {
  const id = useId()
  const { yo } = useAuth()
  const { leads, equipo } = useCRMData()
  const ahora = useAhora()
  const real = puertas.modo === 'real'
  const lista = useBaseGestionEquipo(real && puertas.activa, false)
  const demo = useMemo(() => (real ? null : demoBaseEquipo(leads, equipo, yo, ahora)), [real, leads, equipo, yo, ahora])
  const armar = useArmarBase(puertas)
  const [supervisorId, setSupervisorId] = useState('')
  const [filtros, setFiltros] = useState<FiltrosBase>(SIN_FILTROS)
  const [pagina, setPagina] = useState(0)
  const [nombre, setNombre] = useState('')
  const [error, setError] = useState<{ tipo: 'nombre' | 'supervisor' | 'envio'; texto: string; porMotivo?: Record<string, number[]> } | null>(null)
  const [resultado, setResultado] = useState<{ respuesta: RespuestaArmarBase; nombre: string } | null>(null)
  const envio = useRef<{ id: string; firma: string } | null>(null)
  const primerFiltro = useRef<HTMLSelectElement>(null)
  const tituloResultado = useRef<HTMLHeadingElement>(null)
  const campoNombre = useRef<HTMLInputElement>(null)
  const volverAlNombre = useRef(false)
  // El éxito se ANUNCIA llevando el foco a su título; «Armar otra» lo devuelve al nombre (o al primer filtro).
  useEffect(() => {
    if (resultado) { tituloResultado.current?.focus(); return }
    if (!volverAlNombre.current) return
    volverAlNombre.current = false
    ;(campoNombre.current ?? primerFiltro.current)?.focus()
  }, [resultado])

  // Los candidatos: los descartados vivos del ámbito, sin «No contactar» ni otra base. Gerencia arma para UN supervisor:
  // solo los leads de sus analistas (la bandeja de cada supervisor no se distingue en esta lista).
  const candidatos = useMemo(() => {
    const filas = real ? lista.data?.filas ?? [] : demo?.filas ?? []
    const vivos = filas.filter((f) => !esVetada(f) && f.base_id == null)
    if (!esGerencia) return vivos
    if (!supervisorId) return []
    const delEquipo = new Set(equipo.filter((m) => m.supervisor_id === supervisorId).map((m) => m.perfil_id))
    return vivos.filter((f) => f.vendedor_id !== null && delEquipo.has(f.vendedor_id))
  }, [real, lista.data, demo, esGerencia, supervisorId, equipo])

  if (resultado) {
    const r = resultado.respuesta
    return (
      <section aria-labelledby={`${id}-resultado`} className="space-y-3">
        <h3 ref={tituloResultado} id={`${id}-resultado`} tabIndex={-1} className={cn('rounded text-[15px] font-bold text-primary', FOCO)}>Base «{resultado.nombre}» armada</h3>
        <div className="flex flex-wrap gap-2">
          <Pastilla etiqueta="Incluidos" valor={r.incluidos} />
          <Pastilla etiqueta="Quedaron fuera" valor={r.excluidos} />
        </div>
        {r.excluidos > 0 && (
          <div className="space-y-1">
            <p className={ROTULO}>Por qué quedaron fuera</p>
            <ListaExcluidos porMotivo={r.excluidos_por_motivo} />
            {(r.excluidos_por_motivo.ocupado?.length ?? 0) > 0 && (
              <p className="text-[13px] text-[var(--muted-foreground-strong)]">Los «ocupados» los tenía otro proceso en ese momento: vuelve a armar con ellos en un rato.</p>
            )}
          </div>
        )}
        <div className="flex flex-wrap justify-end gap-2">
          <Button type="button" variant="outline" className="h-9 pointer-coarse:h-11" onClick={() => { volverAlNombre.current = true; setResultado(null); setNombre(''); envio.current = null }}>Armar otra</Button>
          <Button type="button" className="h-9 pointer-coarse:h-11" onClick={() => onVerBase(r.base_id)}>Ver la base y repartir</Button>
        </div>
      </section>
    )
  }

  const cargando = real && lista.isPending
  const visibles = filtrarBase(candidatos, filtros)
  const entran = visibles.filter((f) => enGestionHasta(f, ahora) === null)
  const enGestion = visibles.filter((f) => enGestionHasta(f, ahora) !== null)
  const orden = [...entran, ...enGestion]
  const paginado = paginar(orden, pagina)
  const opciones = opcionesFiltro(candidatos, filtros)
  const conMes = mesesDeLaBase(candidatos).length > 0
  const demasiados = entran.length > MAX_LEADS_ARMAR
  const cambiarFiltro = (d: DimensionFiltro, valor: string) => { setFiltros((f) => ({ ...f, [d]: valor })); setPagina(0) }

  async function confirmar() {
    if (armar.isPending) return
    const eNombre = errorNombreBase(nombre)
    if (esGerencia && !supervisorId) { setError({ tipo: 'supervisor', texto: 'Elige el supervisor dueño de la base.' }); return }
    if (eNombre) { setError({ tipo: 'nombre', texto: eNombre }); return }
    if (entran.length === 0) { setError({ tipo: 'envio', texto: 'Ningún lead de la lista puede entrar a una base. Cambia los filtros.' }); return }
    if (demasiados) { setError({ tipo: 'envio', texto: `Una base armada lleva hasta ${MAX_LEADS_ARMAR.toLocaleString('es-PE')} leads: acota los filtros.` }); return }
    setError(null)
    const leadIds = entran.map((f) => f.lead_id)
    const firma = JSON.stringify([nombre.trim(), supervisorId, leadIds])
    // El mismo pedido reusa su id (un reintento tras un corte devuelve la misma respuesta); otro pedido, uno nuevo.
    if (envio.current?.firma !== firma) envio.current = { id: crypto.randomUUID(), firma }
    const entrada: ArmarBaseEntrada = { operacionId: envio.current.id, nombre: nombre.trim(), supervisorId: esGerencia ? supervisorId : null, leadIds }
    try {
      const respuesta = await armar.mutateAsync(entrada)
      setResultado({ respuesta, nombre: nombre.trim() })
      envio.current = null
    } catch (causa: unknown) {
      if (causa instanceof ErrorBases && causa.code === 'SIN_ELEGIBLES') {
        setError({ tipo: 'envio', texto: 'Ningún lead de la lista es elegible: no se creó la base.', porMotivo: causa.detalle as Record<string, number[]> })
      } else if (causa instanceof CrmApiError && causa.code === 'NOMBRE_REPETIDO') {
        setError({ tipo: 'nombre', texto: causa.message })
        campoNombre.current?.focus()
      } else {
        setError({ tipo: 'envio', texto: causa instanceof CrmApiError ? causa.message : 'No se pudo armar la base. Vuelve a intentarlo.' })
      }
    }
  }

  return (
    <div className="space-y-4">
      {esGerencia && (
        <div className="flex w-full flex-col gap-1 sm:w-72">
          <label htmlFor={`${id}-supervisor`} className="text-[13px] font-semibold text-foreground">Supervisor dueño</label>
          <Select
            id={`${id}-supervisor`}
            value={supervisorId}
            onChange={(e) => { setSupervisorId(e.target.value); setFiltros(SIN_FILTROS); setPagina(0); setError(null) }}
            aria-invalid={error?.tipo === 'supervisor' || undefined}
            aria-describedby={error?.tipo === 'supervisor' ? `${id}-error` : `${id}-supervisor-ayuda`}
            className="h-10"
          >
            <option value="">Elige un supervisor</option>
            {supervisores.map((s) => <option key={s.perfil_id} value={s.perfil_id}>{s.nombre_completo}</option>)}
          </Select>
          <p id={`${id}-supervisor-ayuda`} className="text-[13px] text-[var(--muted-foreground-strong)]">Se arma con los descartados de sus analistas.</p>
        </div>
      )}

      {cargando ? (
        <div className="rounded-lg border border-border bg-card pt-4"><PanelCargando filas={4} /></div>
      ) : real && lista.isError && lista.data === undefined ? (
        <AvisoReintentar mensaje="No se pudo cargar la lista de descartados." reintentando={lista.isFetching} onReintentar={() => void lista.refetch()} />
      ) : esGerencia && !supervisorId ? null : candidatos.length === 0 ? (
        <div className="rounded-lg border border-border bg-card">
          <PanelVacio icono={Layers} titulo="No hay descartados para armar una base" detalle="Los descartados con «No contactar» o que ya están en otra base no se ofrecen." />
        </div>
      ) : (
        <>
          <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
            <div className="flex flex-wrap gap-2">
              <Pastilla etiqueta="Entrarían" valor={entran.length} />
              <Pastilla etiqueta="En gestión (quedan fuera)" valor={enGestion.length} />
            </div>
            <BarraFiltros
              conAnalista
              conMes={conMes}
              opciones={opciones}
              filtros={filtros}
              onCambiar={cambiarFiltro}
              onQuitar={() => { setFiltros(SIN_FILTROS); setPagina(0); primerFiltro.current?.focus() }}
              mostrados={visibles.length}
              total={candidatos.length}
              primerFiltro={primerFiltro}
              etiqueta="Filtrar los descartados"
            />
          </div>
          {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La lista no tiene controles: se desplaza con el teclado desde aquí. */}
          <div tabIndex={0} role="region" aria-label="Descartes que entrarían a la base" className={cn('ac-scroll max-h-[18rem] overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
            <table className="min-w-full border-separate border-spacing-0">
              <caption className="sr-only">Descartados que entrarían a la base{hayFiltros(filtros) ? ', con los filtros elegidos' : ''}; los que tienen seguimiento activo, al final y en gris.</caption>
              <thead>
                <tr>
                  {['#', 'Lead', 'Analista anterior', 'Mes', 'Motivo del descarte', 'Etapa máxima', 'Último resultado', 'Estado'].map((c, i) => (
                    <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, i === 0 ? 'w-12 text-center' : 'text-left')}>{c}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {paginado.visibles.map((f, i) => {
                  const hasta = enGestionHasta(f, ahora)
                  return (
                    <tr key={f.lead_id} className={hasta ? 'bg-muted/60 text-[var(--muted-foreground-strong)]' : 'hover:bg-accent/5'}>
                      <td className={cn(CELDA_COMPACTA, 'text-center text-[13px] tabular-nums text-[var(--muted-foreground-strong)]')}>{paginado.paginaActual * 50 + i + 1}</td>
                      <th scope="row" className={cn(CELDA_COMPACTA, 'max-w-56 truncate text-left font-semibold')} title={f.nombre_completo}>{f.nombre_completo}</th>
                      <td className={CELDA_COMPACTA}>{etiquetaAnalista(f)}</td>
                      <td className={CELDA_COMPACTA}><MesDelLead fila={f} /></td>
                      <td className={CELDA_COMPACTA}>{etiquetaMotivoDescarte(f.motivo_descarte)}</td>
                      <td className={CELDA_COMPACTA}><EtapaMaximaChip etapa={f.etapa_maxima} /></td>
                      <td className={CELDA_COMPACTA}>{etiquetaUltimoResultado(f.ultimo_resultado)}</td>
                      <td className={CELDA_COMPACTA}>{hasta ? `En gestión por ${etiquetaAnalista(f)}${hasta > ahora ? ` hasta el ${diaMes(hasta)}` : ''}` : 'Entra'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <Paginacion paginaActual={paginado.paginaActual} paginas={paginado.paginas} total={orden.length} onCambio={setPagina} ariaLabel="Páginas de los descartados" />
          <div className="flex flex-wrap items-start gap-3">
            <div className="flex w-full flex-col gap-1 sm:w-80">
              <label htmlFor={`${id}-nombre`} className="text-[13px] font-semibold text-foreground">Nombre de la base</label>
              <Input
                ref={campoNombre}
                id={`${id}-nombre`}
                value={nombre}
                maxLength={80}
                onChange={(e) => { setNombre(e.target.value); if (error?.tipo === 'nombre') setError(null) }}
                aria-invalid={error?.tipo === 'nombre' || undefined}
                aria-describedby={error?.tipo === 'nombre' ? `${id}-error` : undefined}
                placeholder="Por ejemplo: Descartes de julio"
                className="h-10"
              />
            </div>
            <Button type="button" className="h-10 pointer-coarse:h-11 sm:mt-6" aria-disabled={armar.isPending || undefined} aria-describedby={error?.tipo === 'envio' ? `${id}-error` : undefined} onClick={() => void confirmar()}>
              {armar.isPending ? 'Armando…' : <><Layers aria-hidden /> Armar base con {entran.length.toLocaleString('es-PE')} {entran.length === 1 ? 'lead' : 'leads'}</>}
            </Button>
          </div>
          {demasiados && <p className="text-sm font-medium text-[var(--destructive-text)]">Una base armada lleva hasta {MAX_LEADS_ARMAR.toLocaleString('es-PE')} leads: acota los filtros.</p>}
        </>
      )}
      {error && (
        <div id={`${id}-error`} role="alert" className="space-y-1">
          <p className="text-sm font-medium text-[var(--destructive-text)]">{error.texto}</p>
          {error.porMotivo && <ListaExcluidos porMotivo={error.porMotivo} />}
          {error.tipo === 'envio' && !error.porMotivo && (
            <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" aria-disabled={armar.isPending || undefined} onClick={() => void confirmar()}>
              <RotateCcw aria-hidden /> Reintentar
            </Button>
          )}
        </div>
      )}
    </div>
  )
}
