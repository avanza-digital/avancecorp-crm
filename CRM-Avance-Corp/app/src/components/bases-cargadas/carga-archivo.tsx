// «Cargar base» → «Subir archivo» (F5). Cuatro pasos en una sola vista (horizontal antes que vertical):
//  1. el archivo (.xlsx o .csv, hasta 5000 filas): se lee en ESTE navegador; el lector de Excel se descarga solo ahora;
//  2. las columnas: el CRM reconoce nombre, teléfono, DNI, distrito, comentario y capital por su encabezado (se pueden
//     cambiar);
//  3. la vista previa: cada fila validada COMO EL SERVIDOR (nombre y celular peruano obligatorios, DNI de 8 dígitos,
//     capital > 0); las inválidas y las repetidas en el archivo no se envían y salen en el informe;
//  4. el nombre de la base (y, Gerencia, su supervisor dueño, E11).
// Al confirmar: `crear_base` + lotes de 100 con `cargar_base_lote`, cada uno con su id de operación fijo (repetirlo es
// seguro), barra de progreso, reintento solo ante «otra carga en curso» y «Reintentar» ante un corte. Al final, el
// informe por veredicto con «Descargar informe». El servidor decide cada fila; la vista previa solo avisa antes.
import { useEffect, useId, useMemo, useRef, useState, type ChangeEvent, type DragEvent } from 'react'
import { FileSpreadsheet, RotateCcw, Upload } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Pastilla } from '@/components/base-gestion/filtros-base'
import { Paginacion } from '@/components/common/paginacion'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import { paginar } from '@/lib/paginacion'
import { telefonoLegible } from '@/lib/recordatorios-disponibilidad'
import {
  CAMPOS_ARCHIVO,
  CAMPOS_OBLIGATORIOS,
  MAPEO_VACIO,
  MAX_FILAS_BASE,
  ROTULO_CAMPO,
  VEREDICTO_SIN_ENVIAR,
  detectarColumnas,
  errorNombreBase,
  etiquetaMotivoFila,
  filaEnvio,
  nombreDesdeArchivo,
  partirEnLotes,
  prepararFilas,
  resultadosLocales,
  type CampoArchivo,
  type FilaPreparada,
  type MapeoColumnas,
  type TablaArchivo,
} from '@/lib/bases-cargadas'
import { ErrorArchivoBase, leerArchivoBase } from '@/lib/bases-cargadas-archivo'
import { CODIGO_NO_DISPONIBLE, CODIGO_RED } from '@/data/bases-cargadas-api'
import { AVANCE_INICIAL, ejecutarCarga, type AvanceCarga, type PlanCarga } from '@/data/bases-cargadas-carga'
import { useInvalidarBases, type PuertasBases } from '@/data/bases-cargadas-queries'
import type { CrmApiError } from '@/data/crm-api'
import type { Miembro } from '@/lib/tipos'
import { InformeCarga } from './informe-carga'
import { CELDA_COMPACTA, ENCABEZADO_COMPACTO, ROTULO } from './piezas-bases'

type Fase = 'preparando' | 'cargando' | 'pausada' | 'terminada'
type Errores = { nombre?: string | undefined; supervisor?: string | undefined; envio?: string | undefined }
type FiltroVista = 'todas' | 'validas' | 'invalidas' | 'repetidas'

const esperar = (ms: number) => new Promise<void>((resolver) => { setTimeout(resolver, ms) })

/** «A», «B»… «AA»: la letra de la columna, como en Excel. */
function letraColumna(i: number): string {
  let n = i + 1
  let letra = ''
  while (n > 0) { const r = (n - 1) % 26; letra = String.fromCharCode(65 + r) + letra; n = Math.floor((n - 1) / 26) }
  return letra
}

/** Las filas que la carga no llegó a enviar (si se terminó a medias). */
function sinEnviar(plan: PlanCarga, avance: AvanceCarga) {
  return plan.lotes.slice(avance.lotesHechos).flatMap((l) => l.filas.map((f) => ({ fila: f.fila, veredicto: VEREDICTO_SIN_ENVIAR, motivo: null })))
}

export function CargaArchivo({ puertas, esGerencia, supervisores, onVerBase, onEnCurso }: {
  puertas: PuertasBases
  esGerencia: boolean
  /** Los supervisores activos que Gerencia puede elegir como dueño (E11). */
  supervisores: readonly Miembro[]
  onVerBase: (baseId: string) => void
  /** Avisa si hay una carga corriendo (la hoja lateral no se cierra a medias). */
  onEnCurso: (enCurso: boolean) => void
}) {
  const id = useId()
  const invalidar = useInvalidarBases()
  const [archivo, setArchivo] = useState<File | null>(null)
  const [tabla, setTabla] = useState<TablaArchivo | null>(null)
  const [leyendo, setLeyendo] = useState(false)
  const [errorArchivo, setErrorArchivo] = useState<string | null>(null)
  const [mapeo, setMapeo] = useState<MapeoColumnas>(MAPEO_VACIO)
  const [nombre, setNombre] = useState('')
  const [supervisorId, setSupervisorId] = useState('')
  const [errores, setErrores] = useState<Errores>({})
  const [filtroVista, setFiltroVista] = useState<FiltroVista>('todas')
  const [pagina, setPagina] = useState(0)
  const [fase, setFase] = useState<Fase>('preparando')
  const [plan, setPlan] = useState<PlanCarga | null>(null)
  const [avance, setAvance] = useState<AvanceCarga>(AVANCE_INICIAL)
  const [errorCarga, setErrorCarga] = useState<CrmApiError | null>(null)
  const [terminadaAMedias, setTerminadaAMedias] = useState(false)
  const corriendo = useRef(false)
  const entrada = useRef<HTMLInputElement>(null)
  const tituloProgreso = useRef<HTMLHeadingElement>(null)

  const preparacion = useMemo(() => (tabla ? prepararFilas(tabla, mapeo) : null), [tabla, mapeo])
  const faltan = CAMPOS_OBLIGATORIOS.filter((c) => mapeo[c] === null)

  // La hoja lateral no se cierra con una carga corriendo; al salir de la pestaña del navegador, se avisa.
  useEffect(() => {
    onEnCurso(fase === 'cargando')
    if (fase !== 'cargando') return
    const avisar = (e: BeforeUnloadEvent) => { e.preventDefault() }
    window.addEventListener('beforeunload', avisar)
    return () => window.removeEventListener('beforeunload', avisar)
  }, [fase, onEnCurso])
  useEffect(() => () => onEnCurso(false), [onEnCurso])

  async function elegirArchivo(elegido: File | null | undefined) {
    if (!elegido || leyendo) return
    setLeyendo(true); setErrorArchivo(null)
    try {
      const leida = await leerArchivoBase(elegido)
      setArchivo(elegido); setTabla(leida); setMapeo(detectarColumnas(leida.encabezados))
      setNombre((n) => n || nombreDesdeArchivo(elegido.name)); setFiltroVista('todas'); setPagina(0); setErrores({})
    } catch (causa: unknown) {
      setErrorArchivo(causa instanceof ErrorArchivoBase ? causa.message : 'No se pudo leer el archivo. Revisa que sea un .xlsx o .csv.')
    } finally {
      setLeyendo(false)
      if (entrada.current) entrada.current.value = ''
    }
  }

  async function correr(p: PlanCarga, desde: AvanceCarga) {
    if (corriendo.current) return
    corriendo.current = true
    setFase('cargando'); setErrorCarga(null)
    requestAnimationFrame(() => tituloProgreso.current?.focus())
    try {
      const fin = await ejecutarCarga(p, desde, {
        crearBase: puertas.fuente.crearBase, cargarBaseLote: puertas.fuente.cargarBaseLote, esperar, alAvanzar: setAvance,
      })
      setAvance(fin.avance)
      if (fin.avance.baseId) void invalidar()
      if (fin.tipo === 'completa') { setFase('terminada'); return }
      // Una regla del servidor al CREAR la base (nombre repetido, sin permiso): se vuelve al formulario a corregir.
      if (fin.avance.baseId === null && fin.error.code !== CODIGO_RED) {
        setPlan(null); setFase('preparando')
        setErrores(fin.error.code === CODIGO_NO_DISPONIBLE || fin.error.code === 'SIN_PERMISO' ? { envio: fin.error.message } : { nombre: fin.error.message })
        return
      }
      setErrorCarga(fin.error); setFase('pausada')
    } finally {
      corriendo.current = false
    }
  }

  function cargar() {
    if (!preparacion || !archivo) return
    const nuevos: Errores = {}
    const eNombre = errorNombreBase(nombre)
    if (eNombre) nuevos.nombre = eNombre
    if (esGerencia && !supervisorId) nuevos.supervisor = 'Elige el supervisor dueño de la base: sus contactos quedan en su bandeja.'
    if (faltan.length > 0) nuevos.envio = `Falta elegir la columna de ${faltan.map((c) => ROTULO_CAMPO[c]).join(' y ')}.`
    else if (preparacion.validas.length === 0) nuevos.envio = 'Ninguna fila es válida: revisa las columnas elegidas.'
    setErrores(nuevos)
    if (Object.keys(nuevos).length > 0) return
    const nuevoPlan: PlanCarga = {
      crear: { operacionId: crypto.randomUUID(), nombre: nombre.trim(), supervisorId: esGerencia ? supervisorId : null, archivoNombre: archivo.name.slice(0, 255) },
      lotes: partirEnLotes(preparacion.validas.map(filaEnvio)).map((filas) => ({ operacionId: crypto.randomUUID(), filas })),
    }
    setPlan(nuevoPlan); setAvance(AVANCE_INICIAL); setTerminadaAMedias(false)
    void correr(nuevoPlan, AVANCE_INICIAL)
  }

  function reiniciar() {
    setArchivo(null); setTabla(null); setMapeo(MAPEO_VACIO); setNombre(''); setSupervisorId(''); setErrores({})
    setPlan(null); setAvance(AVANCE_INICIAL); setErrorCarga(null); setFase('preparando'); setTerminadaAMedias(false)
  }

  // ── Cargando, pausada o terminada ───────────────────────────────────────────────────────────────────────────
  if (fase !== 'preparando' && plan && preparacion && archivo) {
    const totalFilas = plan.lotes.reduce((s, l) => s + l.filas.length, 0)
    const pct = totalFilas === 0 ? 100 : Math.round((avance.filasHechas / totalFilas) * 100)
    // Lo que se ANUNCIA (cada cuarto del camino, el reintento y el final); el texto visible dice el detalle exacto.
    const hito = Math.min(4, Math.floor(pct / 25))
    const anuncio = fase === 'terminada' ? `Carga terminada: ${avance.filasHechas} de ${totalFilas} filas enviadas.`
      : fase === 'pausada' ? 'La carga se detuvo.'
        : avance.reintento > 0 ? `La base estaba ocupada: reintento ${avance.reintento}.`
          : `Cargando: ${hito * 25} %.`
    const resultados = [...resultadosLocales(preparacion), ...avance.resultados, ...(terminadaAMedias ? sinEnviar(plan, avance) : [])]
    return (
      <div className="space-y-4">
        <div className="space-y-2 rounded-lg border border-border bg-card p-4">
          <h3 ref={tituloProgreso} tabIndex={-1} className={cn('rounded text-[15px] font-bold text-primary', FOCO)}>
            {fase === 'terminada' ? (terminadaAMedias ? `Carga detenida: «${plan.crear.nombre}»` : `Carga terminada: «${plan.crear.nombre}»`) : `Cargando «${plan.crear.nombre}»`}
          </h3>
          <div role="progressbar" aria-label="Avance de la carga" aria-valuemin={0} aria-valuemax={totalFilas} aria-valuenow={avance.filasHechas} aria-valuetext={`${avance.filasHechas} de ${totalFilas} filas`} className="h-2 w-full overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-accent transition-[width] duration-300" style={{ width: `${pct}%` }} />
          </div>
          <p className="text-sm tabular-nums text-[var(--muted-foreground-strong)]">
            Lote {Math.min(avance.lotesHechos + (fase === 'cargando' ? 1 : 0), plan.lotes.length)} de {plan.lotes.length} · {avance.filasHechas.toLocaleString('es-PE')} de {totalFilas.toLocaleString('es-PE')} filas
            {fase === 'cargando' && avance.reintento > 0 && ` · la base estaba ocupada, reintentando (${avance.reintento})…`}
          </p>
          <p role="status" className="sr-only">{anuncio}</p>
          {fase === 'pausada' && errorCarga && (
            <div className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/40 bg-destructive/[0.04] px-3 py-2.5">
              <p role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{errorCarga.message}</p>
              <Button type="button" size="sm" className="pointer-coarse:h-11" onClick={() => void correr(plan, avance)}>
                <RotateCcw aria-hidden /> Reintentar
              </Button>
              {avance.baseId && (
                <Button type="button" variant="outline" size="sm" className="pointer-coarse:h-11" onClick={() => { setTerminadaAMedias(true); setFase('terminada') }}>
                  Terminar aquí y ver el informe
                </Button>
              )}
            </div>
          )}
          {fase === 'cargando' && <p className="text-[13px] text-[var(--muted-foreground-strong)]">No cierres esta ventana hasta que termine. Si la conexión se corta, podrás reintentar sin cargar nada dos veces.</p>}
        </div>
        {(fase === 'terminada' || (fase === 'pausada' && avance.resultados.length > 0)) && (
          <InformeCarga resultados={resultados} nombreBase={plan.crear.nombre} archivoNombre={archivo.name} />
        )}
        {fase === 'terminada' && (
          <div className="flex flex-wrap justify-end gap-2">
            <Button type="button" variant="outline" className="h-9 pointer-coarse:h-11" onClick={reiniciar}>Cargar otro archivo</Button>
            {avance.baseId && <Button type="button" className="h-9 pointer-coarse:h-11" onClick={() => onVerBase(avance.baseId as string)}>Ver la base y repartir</Button>}
          </div>
        )}
      </div>
    )
  }

  // ── Preparar: archivo, columnas, vista previa y nombre ─────────────────────────────────────────────────────────
  const vistas: Record<FiltroVista, FilaPreparada[]> = {
    todas: preparacion?.filas ?? [],
    validas: preparacion?.validas ?? [],
    invalidas: preparacion?.filas.filter((f) => f.error !== null && f.error !== 'en_archivo') ?? [],
    repetidas: preparacion?.filas.filter((f) => f.error === 'en_archivo') ?? [],
  }
  const paginado = paginar(vistas[filtroVista], pagina)
  const alternarVista = (v: FiltroVista) => { setFiltroVista((f) => (f === v ? 'todas' : v)); setPagina(0) }
  const soltar = (e: DragEvent<HTMLDivElement>) => { e.preventDefault(); void elegirArchivo(e.dataTransfer.files[0]) }
  const encabezado = (i: number) => `${letraColumna(i)} · ${tabla?.encabezados[i] || 'Sin título'}`

  return (
    <div className="space-y-5">
      {/* 1 · El archivo */}
      <section aria-labelledby={`${id}-paso1`} className="space-y-2">
        <h3 id={`${id}-paso1`} className={ROTULO}>1 · Archivo</h3>
        <div onDragOver={(e) => e.preventDefault()} onDrop={soltar} className="flex flex-wrap items-center gap-3 rounded-lg border border-dashed border-[var(--border-strong)] bg-muted/40 px-4 py-3">
          <Upload className="size-5 shrink-0 text-[var(--muted-foreground-strong)]" aria-hidden />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold text-foreground">{archivo ? 'Archivo elegido: puedes cambiarlo' : 'Elige o suelta aquí el archivo'}</p>
            <p id={`${id}-archivo-ayuda`} className="text-[13px] text-[var(--muted-foreground-strong)]">
              .xlsx o .csv, con una fila de encabezados y hasta {MAX_FILAS_BASE.toLocaleString('es-PE')} contactos. Obligatorios: nombre y celular.
            </p>
          </div>
          {/* El control nativo dice «Choose File» en un navegador en inglés: se oculta a la vista (sigue siendo el control
              que recibe el foco y el lector anuncia) y un rótulo en español hace de botón; el foco se ve en el rótulo. */}
          <input
            ref={entrada}
            id={`${id}-archivo-control`}
            type="file"
            accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv"
            aria-label={archivo ? 'Cambiar el archivo' : 'Elegir el archivo'}
            aria-describedby={`${id}-archivo-ayuda${errorArchivo ? ` ${id}-archivo-error` : ''}`}
            aria-invalid={errorArchivo ? true : undefined}
            onChange={(e: ChangeEvent<HTMLInputElement>) => void elegirArchivo(e.target.files?.[0])}
            className="peer sr-only"
          />
          <label
            htmlFor={`${id}-archivo-control`}
            className="inline-flex h-10 cursor-pointer items-center gap-2 rounded-lg bg-primary px-4 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary-press peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-ring pointer-coarse:h-11"
          >
            <FileSpreadsheet className="size-4" aria-hidden /> {archivo ? 'Cambiar archivo' : 'Elegir archivo'}
          </label>
        </div>
        <p role="status" className="text-sm text-[var(--muted-foreground-strong)]">
          {leyendo ? 'Leyendo el archivo…' : archivo && tabla ? `${archivo.name} · ${tabla.filas.length.toLocaleString('es-PE')} filas con datos` : ''}
        </p>
        {errorArchivo && <p id={`${id}-archivo-error`} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{errorArchivo}</p>}
      </section>

      {tabla && preparacion && (
        <>
          {/* 2 · Las columnas: en una fila (horizontal), de dos en dos en el celular */}
          <section aria-labelledby={`${id}-paso2`} className="space-y-2">
            <h3 id={`${id}-paso2`} className={ROTULO}>2 · Columnas</h3>
            <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-4 lg:grid-cols-8">
              {CAMPOS_ARCHIVO.map((campo: CampoArchivo) => {
                const obligatorio = CAMPOS_OBLIGATORIOS.includes(campo)
                const falta = obligatorio && mapeo[campo] === null
                return (
                  <div key={campo} className="flex min-w-0 flex-col gap-1">
                    <label htmlFor={`${id}-col-${campo}`} className="text-[13px] font-semibold text-foreground">
                      {ROTULO_CAMPO[campo]}{obligatorio && <span aria-hidden className="text-[var(--destructive-text)]"> *</span>}
                      {obligatorio && <span className="sr-only"> (obligatorio)</span>}
                    </label>
                    <Select
                      id={`${id}-col-${campo}`}
                      value={mapeo[campo] === null ? '' : String(mapeo[campo])}
                      aria-invalid={falta || undefined}
                      onChange={(e) => { setMapeo((m) => ({ ...m, [campo]: e.target.value === '' ? null : Number(e.target.value) })); setPagina(0) }}
                      className={cn('pointer-coarse:h-11', falta && 'border-[var(--destructive-text)]')}
                    >
                      <option value="">— No está —</option>
                      {tabla.encabezados.map((_, i) => <option key={i} value={i}>{encabezado(i)}</option>)}
                    </Select>
                  </div>
                )
              })}
            </div>
          </section>

          {/* 3 · Vista previa */}
          <section aria-labelledby={`${id}-paso3`} className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h3 id={`${id}-paso3`} className={ROTULO}>3 · Vista previa</h3>
              <div role="group" aria-label="Filas de la vista previa" className="flex flex-wrap gap-2">
                <Pastilla etiqueta="Se enviarán" valor={preparacion.validas.length} presionada={filtroVista === 'validas'} pista="ver solo esas" onAbrir={preparacion.validas.length > 0 ? () => alternarVista('validas') : undefined} />
                <Pastilla etiqueta="Inválidas" valor={preparacion.invalidas} urgente={preparacion.invalidas > 0} presionada={filtroVista === 'invalidas'} pista="ver solo esas" onAbrir={preparacion.invalidas > 0 ? () => alternarVista('invalidas') : undefined} />
                <Pastilla etiqueta="Repetidas en el archivo" valor={preparacion.repetidas} presionada={filtroVista === 'repetidas'} pista="ver solo esas" onAbrir={preparacion.repetidas > 0 ? () => alternarVista('repetidas') : undefined} />
              </div>
            </div>
            <div className="ac-scroll max-h-[18rem] overflow-auto rounded-lg border border-[var(--border-strong)] bg-card">
              <table className="min-w-full border-separate border-spacing-0">
                <caption className="sr-only">Vista previa del archivo: cada fila con lo que se enviaría o por qué no se envía.</caption>
                <thead>
                  <tr>
                    {['Fila', 'Nombre', 'Teléfono', 'DNI', 'Distrito', 'Capital', 'Estado'].map((c, i) => (
                      <th key={c} scope="col" className={cn(ENCABEZADO_COMPACTO, i === 0 ? 'w-16 text-right' : 'text-left')}>{c}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {paginado.visibles.map((f) => (
                    <tr key={f.fila} className={f.error ? 'bg-destructive/[0.03]' : undefined}>
                      <td className={cn(CELDA_COMPACTA, 'text-right text-[13px] tabular-nums text-[var(--muted-foreground-strong)]')}>{f.fila}</td>
                      <th scope="row" className={cn(CELDA_COMPACTA, 'max-w-56 truncate text-left font-semibold')} title={f.nombre}>{f.nombre || '—'}</th>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{f.telefono && !f.error?.startsWith('telefono') ? telefonoLegible(f.telefono) : f.telefonoLeido || '—'}</td>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{f.dni || '—'}</td>
                      <td className={cn(CELDA_COMPACTA, 'max-w-40 truncate')}>{f.distrito || '—'}</td>
                      <td className={cn(CELDA_COMPACTA, 'tabular-nums')}>{f.capital && !f.error?.startsWith('capital') ? `${f.moneda === 'USD' ? 'US$' : 'S/'} ${Number(f.capital).toLocaleString('es-PE')}` : f.capital || 'Sin capital'}</td>
                      <td className={cn(CELDA_COMPACTA, f.error ? 'font-semibold text-[var(--destructive-text)]' : 'text-primary')}>
                        {f.error ? etiquetaMotivoFila(f.error === 'en_archivo' ? 'repetida' : 'invalida', f.error) : 'Se envía'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Paginacion paginaActual={paginado.paginaActual} paginas={paginado.paginas} total={vistas[filtroVista].length} onCambio={setPagina} ariaLabel="Páginas de la vista previa" />
            <p className="text-[13px] text-[var(--muted-foreground-strong)]">
              Esta revisión es una ayuda: al cargar, el servidor vuelve a validar y salta a quien ya existe en el CRM (lead, cliente o «No contactar»). Nunca crea un duplicado.
            </p>
          </section>

          {/* 4 · Nombre (y supervisor dueño) */}
          <section aria-labelledby={`${id}-paso4`} className="space-y-2">
            <h3 id={`${id}-paso4`} className={ROTULO}>4 · La base</h3>
            <div className="flex flex-wrap items-start gap-3">
              <div className="flex w-full flex-col gap-1 sm:w-80">
                <label htmlFor={`${id}-nombre`} className="text-[13px] font-semibold text-foreground">Nombre de la base</label>
                <Input
                  id={`${id}-nombre`}
                  value={nombre}
                  maxLength={80}
                  onChange={(e) => { setNombre(e.target.value); setErrores((x) => ({ ...x, nombre: undefined })) }}
                  aria-invalid={errores.nombre ? true : undefined}
                  aria-describedby={errores.nombre ? `${id}-nombre-error` : undefined}
                  placeholder="Por ejemplo: Feria 2025"
                  className="h-10"
                />
                {errores.nombre && <p id={`${id}-nombre-error`} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{errores.nombre}</p>}
              </div>
              {esGerencia && (
                <div className="flex w-full flex-col gap-1 sm:w-72">
                  <label htmlFor={`${id}-supervisor`} className="text-[13px] font-semibold text-foreground">Supervisor dueño</label>
                  <Select
                    id={`${id}-supervisor`}
                    value={supervisorId}
                    onChange={(e) => { setSupervisorId(e.target.value); setErrores((x) => ({ ...x, supervisor: undefined })) }}
                    aria-invalid={errores.supervisor ? true : undefined}
                    aria-describedby={errores.supervisor ? `${id}-supervisor-error` : undefined}
                    className="h-10"
                  >
                    <option value="">Elige un supervisor</option>
                    {supervisores.map((s) => <option key={s.perfil_id} value={s.perfil_id}>{s.nombre_completo}</option>)}
                  </Select>
                  {errores.supervisor && <p id={`${id}-supervisor-error`} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{errores.supervisor}</p>}
                </div>
              )}
              <div className="flex flex-col gap-1 sm:mt-6">
                <Button type="button" className="h-10 pointer-coarse:h-11" aria-describedby={errores.envio ? `${id}-envio-error` : undefined} onClick={cargar}>
                  <FileSpreadsheet aria-hidden /> Cargar {preparacion.validas.length.toLocaleString('es-PE')} {preparacion.validas.length === 1 ? 'contacto' : 'contactos'}
                </Button>
              </div>
            </div>
            {errores.envio && <p id={`${id}-envio-error`} role="alert" className="text-sm font-medium text-[var(--destructive-text)]">{errores.envio}</p>}
            <p className="text-[13px] text-[var(--muted-foreground-strong)]">
              Los contactos entran dormidos y sin repartir a la bandeja del supervisor dueño. Después se reparten desde la base.
            </p>
          </section>
        </>
      )}
    </div>
  )
}
