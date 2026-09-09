import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { ArrowRight, ChevronLeft, ChevronRight, Copy, Lock, RefreshCw, Save, Target, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useConfiguracionMetas, usePublicarMetas } from '@/data/crm-config-queries'
import { useCierreMesEstado } from '@/data/crm-queries'
import { useAuth } from '@/lib/auth-context'
import { obtenerConfiguracionMetas, publicacionDesdeConfiguracion } from '@/data/crm-config-api'
import { mensajeDeError } from '@/data/crm-api'
import { useCRMData } from '@/lib/store-context'
import type { ConfiguracionMetas } from '@/lib/metas-versionadas'
import {
  digitosDeMonto, money, montoDesdeTexto, montoEditable, porcentajeDesdeTexto, porcentajeEditable,
} from '@/lib/format'
import { periodoLima } from '@/lib/objetivos'
import { cn } from '@/lib/utils'
import { useConsultaGerencia } from '@/components/gerencia/use-consulta-gerencia'

function desplazarPeriodo(periodo: string, meses: number): string {
  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))
  const fecha = new Date(Date.UTC(anio, mes - 1 + meses, 1))
  return `${fecha.getUTCFullYear()}-${String(fecha.getUTCMonth() + 1).padStart(2, '0')}-01`
}

function nombrePeriodo(periodo: string): string {
  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))
  return new Intl.DateTimeFormat('es-PE', { month: 'long', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(Date.UTC(anio, mes - 1, 1)))
}

function fechaPublicacion(valor: string | null): string {
  if (!valor) return 'Sin publicación todavía'
  return new Intl.DateTimeFormat('es-PE', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'America/Lima',
  }).format(new Date(valor))
}

function clonar(config: ConfiguracionMetas): ConfiguracionMetas {
  return {
    ...config,
    vendedores: config.vendedores.map((vendedor) => ({
      ...vendedor,
      detalles: vendedor.detalles.map((detalle) => ({ ...detalle })),
    })),
  }
}

function metaTotal(vendedor: ConfiguracionMetas['vendedores'][number]): number {
  return vendedor.detalles
    .filter((detalle) => detalle.moneda === 'PEN')
    .reduce((total, detalle) => total + detalle.capital_objetivo, 0)
}

/**
 * La base conserva seis dimensiones por compatibilidad histórica. La experiencia
 * operativa usa una sola meta: la guardamos en el slot canónico nuevo/PEN y
 * dejamos las demás dimensiones y objetivos auxiliares en cero.
 *
 * NO toca `conversion_objetivo`: hasta 2026-08-10 lo forzaba a 0 en cada
 * edición, de modo que la meta de conversión era imposible de fijar y los
 * paneles de gerencia y del analista enseñaban «meta por definir» para siempre.
 */
function fijarMetaTotal(
  vendedor: ConfiguracionMetas['vendedores'][number],
  total: number,
) {
  vendedor.detalles = vendedor.detalles.map((detalle) => ({
    ...detalle,
    capital_objetivo: detalle.categoria === 'nuevo' && detalle.moneda === 'PEN' ? total : 0,
    contratos_objetivo: 0,
  }))
}

/**
 * La conversión se pacta para la EMPRESA, no analista por analista: el detalle
 * individual vive en la pantalla de Conversiones. El modelo la guarda por
 * analista, así que el único valor se replica en todos — y `agregarObjetivos`,
 * que promedia los mayores que cero, devuelve exactamente ese número.
 */
function conversionEmpresa(config: ConfiguracionMetas): number {
  const fijadas = config.vendedores.map((v) => v.conversion_objetivo).filter((valor) => valor > 0)
  if (fijadas.length === 0) return 0
  return Math.round((fijadas.reduce((a, b) => a + b, 0) / fijadas.length) * 100) / 100
}

function fijarConversionEmpresa(config: ConfiguracionMetas, valor: number) {
  for (const vendedor of config.vendedores) vendedor.conversion_objetivo = valor
}

function validar(config: ConfiguracionMetas): string | null {
  for (const vendedor of config.vendedores) {
    const total = metaTotal(vendedor)
    if (!Number.isFinite(total) || total < 0 || total > 100_000_000) {
      return `La meta mensual de ${vendedor.nombre} debe estar entre S/ 0 y S/ 100,000,000.`
    }
  }
  const conversion = conversionEmpresa(config)
  if (!Number.isFinite(conversion) || conversion < 0 || conversion > 100) {
    return 'La meta de conversión debe estar entre 0 % y 100 %.'
  }
  return null
}

function MetaVendedor({
  vendedor,
  editable,
  onMetaTotal,
}: {
  vendedor: ConfiguracionMetas['vendedores'][number]
  editable: boolean
  onMetaTotal: (valor: number) => void
}) {
  const total = metaTotal(vendedor)
  // El campo guarda TEXTO, no el número. Con `value={total}` numérico, borrarlo
  // devolvía '' → Number('') → 0 → se repintaba un 0 imborrable; y con
  // `type="number"` el navegador prohíbe los separadores de miles, que es justo
  // lo que hace falta para no confundir 50 000 con 500 000.
  const [texto, setTexto] = useState(() => montoEditable(String(total || '')))
  const inputRef = useRef<HTMLInputElement>(null)
  const caretRef = useRef<number | null>(null)

  // El importe también cambia por fuera (copiar mes anterior, recarga). Se
  // resincroniza SOLO cuando difiere de lo escrito, para no pisar lo que el
  // usuario está tecleando ni resucitar el cero.
  useEffect(() => {
    if (montoDesdeTexto(texto) !== total) setTexto(montoEditable(String(total || '')))
  }, [total, texto])

  // Al insertar una coma el texto se desplaza y el cursor saltaría al final,
  // que es insoportable al corregir un dígito del medio. Se recoloca contando
  // DÍGITOS a la izquierda, no caracteres.
  useLayoutEffect(() => {
    const el = inputRef.current
    const objetivo = caretRef.current
    if (!el || objetivo === null) return
    caretRef.current = null
    let digitos = 0
    let pos = 0
    while (pos < el.value.length && digitos < objetivo) {
      if (/\d/.test(el.value[pos]!)) digitos += 1
      pos += 1
    }
    el.setSelectionRange(pos, pos)
  }, [texto])

  return (
    <li className="flex items-center justify-between gap-4 border-t border-border/60 px-4 py-2 first:border-t-0">
      {/* El nombre hace de etiqueta visible; el campo lleva su `aria-label`
          completo, que lo contiene como prefijo (2.5.3 Label in Name). */}
      <p className="min-w-0 flex-1 truncate text-sm font-semibold text-foreground">
        {vendedor.nombre}
      </p>
      <div className="relative w-40 shrink-0 sm:w-48">
        <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-xs font-extrabold text-primary">S/</span>
        <Input
          ref={inputRef}
          id={`meta-total-${vendedor.vendedor_id}`}
          aria-label={`Meta mensual total de ${vendedor.nombre}`}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          placeholder="0"
          value={texto}
          // `readOnly`, no `disabled`: a este rol el shell le promete que puede
          // AUDITAR la configuración, y el dato auditado es justo el importe —
          // `disabled:opacity-50` lo dejaba en 3.08:1, atenuado como si fuera
          // adorno. Así conserva contraste, foco y lectura del valor.
          readOnly={!editable}
          aria-readonly={!editable}
          onChange={(evento) => {
            const el = evento.currentTarget
            caretRef.current = digitosDeMonto(
              el.value.slice(0, el.selectionStart ?? el.value.length),
            ).length
            const limpio = montoEditable(el.value)
            setTexto(limpio)
            onMetaTotal(montoDesdeTexto(limpio))
          }}
          // `scroll-mb-20`: el aviso pegajoso de «cambios sin publicar» ocupa
          // la banda inferior, y al tabular entre 17 campos el navegador dejaba
          // el enfocado justo debajo, tapado entero (WCAG 2.4.11).
          className="h-9 scroll-mb-20 pl-9 text-right text-sm font-extrabold tabular-nums read-only:bg-muted/50 read-only:text-foreground/80"
        />
      </div>
    </li>
  )
}

/**
 * Cada bloque es un equipo, y su subtotal es lo que de verdad se le está
 * pidiendo a ese supervisor este mes.
 *
 * Se agrupa por `supervisor_id`, NO por nombre: la RPC ordena por
 * `supervisor_nombre`, así que dos supervisores homónimos salen adyacentes con
 * sus analistas intercalados, y un corte por nombre los fundiría en un grupo
 * con el subtotal equivocado. El Map conserva el orden de primera aparición,
 * que es el que ya trae el servidor.
 */
function agruparPorSupervisor(vendedores: ConfiguracionMetas['vendedores']) {
  const porId = new Map<string, {
    id: string
    supervisor: string
    filas: ConfiguracionMetas['vendedores']
  }>()
  for (const vendedor of vendedores) {
    const grupo = porId.get(vendedor.supervisor_id)
      ?? { id: vendedor.supervisor_id, supervisor: vendedor.supervisor_nombre, filas: [] }
    grupo.filas.push(vendedor)
    porId.set(vendedor.supervisor_id, grupo)
  }
  return [...porId.values()]
}

/** Cada motivo es un arreglo distinto; decir «sin supervisor» a los tres manda
 * a Gerencia a buscar un problema que no es. */
const MOTIVO_SIN_SUPERVISOR: Record<
  ConfiguracionMetas['sin_supervisor'][number]['motivo'], string
> = {
  sin_supervisor: 'no tiene supervisor asignado',
  supervisor_inactivo: 'su supervisor está dado de baja',
  supervisor_no_es_supervisor: 'quien figura como su supervisor ya no tiene ese rol',
}

/**
 * A quién NO se le puede fijar meta y por qué. Un analista fuera del roster no
 * cabe en la meta del mes —`crm.metas_vendedor.supervisor_id` es obligatorio— y
 * callarlo dejaría a alguien sin objetivo y sin producción atribuida hasta que
 * alguien se diera cuenta a fin de mes.
 */
function AnalistasFueraDeMetas({
  analistas,
}: {
  analistas: ConfiguracionMetas['sin_supervisor']
}) {
  if (analistas.length === 0) return null
  const plural = analistas.length !== 1
  return (
    <Card className="border-warning/40 bg-warning/[0.06]">
      <CardContent className="flex flex-col gap-3 py-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3">
          <TriangleAlert className="mt-0.5 size-5 shrink-0 text-warning" aria-hidden />
          <div>
            {/* Encabezado real: con 17 analistas la pantalla emite ~18 h3, y sin
                este el único bloque ausente de la navegación por encabezados
                sería justo el aviso que Gerencia no puede pasar por alto. */}
            <h3 id="analistas-sin-meta" className="text-sm font-extrabold text-foreground">
              {analistas.length} analista{plural ? 's' : ''} sin meta este mes
            </h3>
            <ul className="mt-1.5 space-y-1" aria-labelledby="analistas-sin-meta">
              {analistas.map((analista) => (
                // `text-foreground/70` y no `muted-foreground`: la tinta ámbar de
                // la card gana a `bg-card` en twMerge y deja el gris en 4.21:1.
                <li key={analista.vendedor_id} className="text-xs text-foreground/70">
                  <span className="font-semibold text-foreground">{analista.nombre}</span>
                  {` — ${MOTIVO_SIN_SUPERVISOR[analista.motivo]}.`}
                </li>
              ))}
            </ul>
            <p className="mt-2 text-xs text-foreground/70">
              Mientras siga así no {plural ? 'se les' : 'se le'} puede fijar meta y su
              producción no se atribuye en el cumplimiento del mes. La publicación del
              resto del equipo no se detiene.
            </p>
          </div>
        </div>
        <a
          href="#/config-usuarios"
          className="inline-flex h-9 shrink-0 items-center justify-center gap-2 rounded-md border border-border bg-card px-3 text-xs font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          Revisar jerarquía <ArrowRight className="size-4" aria-hidden />
        </a>
      </CardContent>
    </Card>
  )
}

export function ConfigMetas() {
  const memoriaGerencia = useConsultaGerencia()
  const [periodo, setPeriodo] = useState(() => memoriaGerencia?.consulta.administrarMetasPeriodo ?? periodoLima(Date.now()))
  const consulta = useConfiguracionMetas(periodo)
  const publicar = usePublicarMetas(periodo)
  // Los meses solo se sellan hacia adelante (guardia 2quater del servidor), así
  // que «≤ al último sellado» = «ya no se toca»; comparar 'YYYY-MM' como texto
  // es comparar fechas. Consulta ADVISORY y fail-open: si cae, el banner no
  // sale y publica quien quiera — el candado real es el trigger del servidor,
  // cuyo rechazo llega al toast como mensaje de negocio (REGLA_SERVIDOR).
  // Apagada en DEMO (hallazgo de la auditoría F2): el demo es hermético y esta
  // era la única consulta de la pantalla que salía a la red igual — fallaba en
  // silencio y ensuciaba registrarError en cada montaje.
  const { yo } = useAuth()
  const estadoCierre = useCierreMesEstado(yo?.demo !== true)
  const ultimoSellado = estadoCierre.data?.ultimo_cerrado ?? null
  const mesCerrado = ultimoSellado !== null && periodo.slice(0, 7) <= ultimoSellado.mes
  // Publicar invalida la consulta del EDITOR, pero los paneles («Hoy», el
  // resumen de gerencia) leen del store, que solo se puebla en el arranque:
  // sin esto, gerencia publicaba y sus propias pantallas seguían diciendo «Sin
  // meta» hasta que otra acción cualquiera disparaba una resincronización.
  const { recargar } = useCRMData()
  // El periodo vigente, legible desde un callback asíncrono sin depender de su
  // closure ni del momento en que React corra un updater.
  const periodoRef = useRef(periodo)
  periodoRef.current = periodo
  const [borrador, setBorrador] = useState<ConfiguracionMetas | null>(null)
  const [conversionTexto, setConversionTexto] = useState('')
  const [copiando, setCopiando] = useState(false)
  const [revisionAbierta, setRevisionAbierta] = useState(false)
  const [salidaPendiente, setSalidaPendiente] = useState(false)
  const [resultadoPublicacion, setResultadoPublicacion] = useState<string | null>(null)
  const [respuestaIncierta, setRespuestaIncierta] = useState(false)
  const [comprobando, setComprobando] = useState(false)

  useEffect(() => { setRevisionAbierta(false) }, [periodo, borrador, conversionTexto])

  useEffect(() => {
    if (!consulta.data) {
      setBorrador(null)
      setConversionTexto('')
      return
    }
    setBorrador(clonar(consulta.data))
    const guardada = conversionEmpresa(consulta.data)
    setConversionTexto(guardada > 0 ? String(guardada) : '')
  }, [consulta.data])

  const metaEquipo = useMemo(() => {
    return (borrador?.vendedores ?? []).reduce((total, vendedor) => total + metaTotal(vendedor), 0)
  }, [borrador])

  const editable = Boolean(borrador?.puede_editar)
  // La huella incluye la conversión: si no, cambiarla sola dejaba el botón de
  // publicar deshabilitado y el cambio se perdía sin avisar.
  const huella = (config: ConfiguracionMetas) => JSON.stringify(
    config.vendedores.map((vendedor) => [
      vendedor.vendedor_id, metaTotal(vendedor), vendedor.conversion_objetivo,
    ]),
  )
  const dirty = Boolean(consulta.data && borrador && huella(consulta.data) !== huella(borrador))

  const editarVendedor = (
    vendedorId: string,
    mutar: (vendedor: ConfiguracionMetas['vendedores'][number]) => void,
  ) => {
    setBorrador((actual) => {
      if (!actual) return actual
      const siguiente = clonar(actual)
      const vendedor = siguiente.vendedores.find((item) => item.vendedor_id === vendedorId)
      if (vendedor) mutar(vendedor)
      return siguiente
    })
  }

  const copiarAnterior = async () => {
    if (!borrador) return
    // El mes puede cambiar mientras se espera la respuesta: sin esta guardia, lo
    // copiado de julio acababa aplicándose —y publicándose— sobre septiembre.
    const periodoAlPulsar = periodo
    setCopiando(true)
    try {
      const anterior = await obtenerConfiguracionMetas(desplazarPeriodo(periodoAlPulsar, -1))
      const metasAnteriores = new Map(anterior.vendedores.map((vendedor) => [vendedor.vendedor_id, vendedor]))
      const conversionPrevia = conversionEmpresa(anterior)
      // Si el mes cambió mientras se esperaba, esto ya no va dirigido a la
      // pantalla que hay delante: ni se aplica ni se canta éxito.
      if (periodoRef.current !== periodoAlPulsar) return
      setBorrador((actual) => {
        if (!actual || actual.periodo !== periodoAlPulsar) return actual
        const siguiente = clonar(actual)
        for (const vendedor of siguiente.vendedores) {
          const previa = metasAnteriores.get(vendedor.vendedor_id)
          if (!previa) continue
          fijarMetaTotal(vendedor, metaTotal(previa))
        }
        // La conversión pactada también es parte del mes que se copia.
        fijarConversionEmpresa(siguiente, conversionPrevia)
        return siguiente
      })
      // Fuera del updater: un `setState` dentro se ejecuta dos veces en
      // StrictMode y el updater debe seguir siendo puro.
      setConversionTexto(conversionPrevia > 0 ? String(conversionPrevia) : '')
      toast.success(`Se copiaron las metas de ${nombrePeriodo(anterior.periodo)}.`)
    } catch (error) {
      toast.error(mensajeDeError(error, 'No se pudieron copiar las metas del mes anterior.'))
    } finally {
      setCopiando(false)
    }
  }

  const guardar = async (confirmado = false) => {
    if (!borrador || !editable || publicar.isPending || respuestaIncierta) return
    // Cinturón por si el botón quedó habilitado en una carrera (el mes se sella
    // entre la carga y el clic): mismo mensaje que daría el servidor.
    if (mesCerrado) {
      toast.error(`${nombrePeriodo(periodo)} ya está cerrado: las metas de un mes cerrado no se tocan.`)
      return
    }
    const normalizado = clonar(borrador)
    for (const vendedor of normalizado.vendedores) fijarMetaTotal(vendedor, metaTotal(vendedor))
    // Sin esto, quien entró al roster después de la última publicación viaja con
    // su 0 heredado —invisible para `conversionEmpresa`, que filtra los > 0— y
    // se queda sin meta de conversión él solo.
    fijarConversionEmpresa(normalizado, porcentajeDesdeTexto(conversionTexto))
    const error = validar(normalizado)
    if (error) {
      toast.error(error)
      return
    }
    if (!confirmado) { setRevisionAbierta(true); return }
    setRevisionAbierta(false)
    setResultadoPublicacion(null)
    try {
      await publicar.mutateAsync({
        periodo,
        expectedRevision: borrador.revision,
        metas: publicacionDesdeConfiguracion(normalizado),
      })
      const actualizado = await recargar()
      setResultadoPublicacion(`Metas de ${nombrePeriodo(periodo)} publicadas.${actualizado === false ? ' Falta actualizar los reportes: vuelve a consultarlos para comprobar su nueva lectura.' : ' La publicación fue confirmada.'}`)
      toast.success(`Metas de ${nombrePeriodo(periodo)} publicadas.`)
    } catch (fallo) {
      setRespuestaIncierta(true)
      setResultadoPublicacion('No se confirmó una nueva publicación. Comprueba la revisión publicada antes de decidir si necesitas repetirla.')
      toast.error(mensajeDeError(fallo, 'No se pudieron publicar las metas.'))
    }
  }

  const comprobarPublicacion = async () => {
    setComprobando(true)
    try {
      const respuesta = await consulta.refetch()
      if (respuesta.isError || !respuesta.data) {
        setResultadoPublicacion('No se pudo comprobar la revisión publicada. El resultado anterior continúa sin confirmar.')
        return
      }
      setRespuestaIncierta(false)
      setResultadoPublicacion(`Revisión ${respuesta.data.revision} consultada para ${nombrePeriodo(respuesta.data.periodo)}. Revisa sus valores antes de preparar otra publicación.`)
    } catch {
      setResultadoPublicacion('No se pudo comprobar la revisión publicada. El resultado anterior continúa sin confirmar.')
    } finally { setComprobando(false) }
  }

  const volverAConsulta = () => {
    memoriaGerencia?.setConsulta((actual) => ({ ...actual, administrarMetasPeriodo: null }))
    window.location.hash = '#/metas'
  }

  return (
    <ConfiguracionShell
      icono={Target}
      titulo="Metas mensuales"
      descripcion="Una sola meta mensual en soles por analista y una conversión objetivo para toda la empresa. Sin categorías ni cantidad de contratos."
      soloLectura={borrador ? !borrador.puede_editar : true}
      estado={borrador ? {
        etiqueta: borrador.revision > 0 ? `Revisión ${borrador.revision}` : 'Sin publicar',
        detalle: borrador.publicada_en
          ? `Publicada por ${borrador.publicada_por_nombre ?? 'usuario no disponible'} · ${fechaPublicacion(borrador.publicada_en)}`
          : 'El período todavía no tiene una revisión publicada.',
      } : undefined}
      acciones={editable ? (
        <>
          <Button variant="outline" size="sm" onClick={copiarAnterior} disabled={copiando || publicar.isPending || mesCerrado}>
            <Copy aria-hidden /> {copiando ? 'Copiando…' : 'Copiar mes anterior'}
          </Button>
          <Button size="sm" className="min-h-11" onClick={() => void guardar()} disabled={!dirty || publicar.isPending || mesCerrado || respuestaIncierta}>
            <Save aria-hidden /> {publicar.isPending ? 'Publicando…' : 'Publicar revisión'}
          </Button>
        </>
      ) : undefined}
    >
      {memoriaGerencia?.consulta.administrarMetasPeriodo && <section aria-label="Regreso a consulta de metas" className="space-y-3 rounded-xl border border-border bg-card p-4">
        <p className="text-sm">Administración centralizada. La consulta de Gerencia conserva su mes y punto de lectura al volver.</p>
        <Button variant="outline" className="min-h-11" onClick={() => dirty ? setSalidaPendiente(true) : volverAConsulta()} disabled={publicar.isPending}>Volver a consulta de metas</Button>
        {salidaPendiente && <div role="status" className="space-y-2"><p className="text-sm">Hay cambios sin publicar. Si vuelves ahora, se descartará este borrador.</p><div className="flex flex-wrap gap-2"><Button variant="outline" className="min-h-11" onClick={volverAConsulta}>Descartar borrador y volver</Button><Button className="min-h-11" onClick={() => setSalidaPendiente(false)}>Continuar editando</Button></div></div>}
      </section>}
      {revisionAbierta && borrador && <section aria-label="Revisar publicación de metas" className="space-y-3 rounded-xl border border-border bg-card p-4 sm:p-5">
        <h2 className="text-lg font-bold">Revisar publicación de metas</h2>
        <p className="text-sm">Mes: {nombrePeriodo(periodo)} · revisión actual: {borrador.revision}. La publicación incluye las metas de los {borrador.vendedores.length} analistas mostrados.</p>
        <p className="text-sm">Meta total: {money(metaEquipo, 'PEN')} · conversión objetivo: {conversionTexto || '0'}%.</p>
        <p className="text-xs text-muted-foreground">Confirma los importes y la conversión objetivo antes de publicar. Si el mes está cerrado, la edición sigue bloqueada.</p>
        <div className="flex flex-wrap gap-2"><Button className="min-h-11" onClick={() => void guardar(true)} disabled={publicar.isPending || mesCerrado}>Confirmar publicación</Button><Button className="min-h-11" variant="outline" onClick={() => setRevisionAbierta(false)}>Seguir editando</Button></div>
      </section>}
      {resultadoPublicacion && <section role="status" className="space-y-3 rounded-xl border border-border bg-card p-4"><p className="text-sm">{resultadoPublicacion}</p>{respuestaIncierta && <Button variant="outline" className="min-h-11" disabled={comprobando} onClick={() => void comprobarPublicacion()}>{comprobando ? 'Comprobando…' : 'Comprobar revisión publicada'}</Button>}</section>}
      <Card>
        <CardContent className="flex flex-col gap-4 py-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <Label htmlFor="periodo-metas">Período</Label>
            <div className="mt-1 flex items-center gap-2">
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Mes anterior"
                onClick={() => setPeriodo((actual) => desplazarPeriodo(actual, -1))}
              >
                <ChevronLeft aria-hidden />
              </Button>
              <Input
                id="periodo-metas"
                type="month"
                value={periodo.slice(0, 7)}
                onChange={(evento) => evento.target.value && setPeriodo(`${evento.target.value}-01`)}
                className="w-44 font-semibold capitalize"
              />
              <Button
                type="button"
                variant="outline"
                size="icon"
                aria-label="Mes siguiente"
                onClick={() => setPeriodo((actual) => desplazarPeriodo(actual, 1))}
              >
                <ChevronRight aria-hidden />
              </Button>
            </div>
          </div>
          {borrador && (
            <div className="flex flex-wrap items-end gap-3">
              {/* La conversión se pacta para la EMPRESA: un solo número, no
                  diecisiete. El detalle por analista vive en Conversiones. */}
              <div>
                <Label htmlFor="meta-conversion-empresa">Conversión objetivo</Label>
                <div className="relative mt-1.5 w-36">
                  <Input
                    id="meta-conversion-empresa"
                    aria-label="Meta de conversión de la empresa, en porcentaje"
                    type="text"
                    inputMode="numeric"
                    autoComplete="off"
                    placeholder="0"
                    value={conversionTexto}
                    readOnly={!editable}
                    aria-readonly={!editable}
                    onChange={(evento) => {
                      const limpio = porcentajeEditable(evento.target.value)
                      setConversionTexto(limpio)
                      setBorrador((actual) => {
                        if (!actual) return actual
                        const siguiente = clonar(actual)
                        fijarConversionEmpresa(siguiente, porcentajeDesdeTexto(limpio))
                        return siguiente
                      })
                    }}
                    className="h-10 pr-8 text-right font-extrabold tabular-nums read-only:bg-muted/50 read-only:text-foreground/80"
                  />
                  <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-sm font-extrabold text-primary">%</span>
                </div>
              </div>
              <div className="rounded-xl border border-accent/25 bg-accent/[0.06] px-4 py-3 text-right">
                <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-muted-foreground">Meta total del equipo</p>
                <p className="mt-1 text-lg font-extrabold tabular-nums text-primary">
                  S/ {metaEquipo.toLocaleString('es-PE', { maximumFractionDigits: 2 })}
                </p>
                <p className="mt-0.5 text-[10px] text-muted-foreground">{borrador.vendedores.length} analista{borrador.vendedores.length === 1 ? '' : 's'}</p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {mesCerrado && ultimoSellado && (
        // role="status": al navegar de mes hacia uno sellado, el banner entra
        // y los botones se apagan en silencio; esto lo anuncia sin interrumpir.
        <Card role="status" className="border-primary/25 bg-primary/[0.05]">
          <CardContent className="flex items-start gap-3 py-4">
            <Lock className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden />
            <div>
              {/* Solo la PRIMERA letra: `capitalize` pondría Mayúscula En Cada Palabra. */}
              <h3 className="text-sm font-extrabold text-foreground first-letter:uppercase">
                {nombrePeriodo(periodo)} ya está cerrado
              </h3>
              <p className="mt-1 text-xs text-foreground/70">
                {periodo.slice(0, 7) === ultimoSellado.mes && ultimoSellado.cerrado_en
                  ? `Se cerró el ${fechaPublicacion(ultimoSellado.cerrado_en)}${ultimoSellado.automatico ? ' por el ciclo automático' : ''}. `
                  : ''}
                Sus metas y sus cifras son definitivas: un mes cerrado no se reescribe.
                Lo que haya que corregir se descuenta en el mes vivo.
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {borrador && <AnalistasFueraDeMetas analistas={borrador.sin_supervisor} />}

      {consulta.isPending && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground" role="status">Cargando las metas del período…</CardContent></Card>
      )}

      {consulta.isError && (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
            <p className="text-sm font-semibold text-destructive">{mensajeDeError(consulta.error, 'No se pudieron cargar las metas.')}</p>
            <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}>
              <RefreshCw aria-hidden /> Reintentar
            </Button>
          </CardContent>
        </Card>
      )}

      {borrador && borrador.vendedores.length === 0 && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No hay analistas activos en el roster de este período.</CardContent></Card>
      )}

      {/* Una sola tarjeta con la lista entera: antes cada analista traía su
          propia Card con cabecera y dos textos repetidos —los mismos 17
          veces—, y el mes no cabía en varias pantallas de scroll. */}
      {borrador && borrador.vendedores.length > 0 && (
        <Card className="overflow-hidden">
          {/* Encabezado que cuelga la lista del módulo en vez de dejar a los
              equipos como hermanos del aviso de excluidos. Invisible: el
              rediseño existía para quitar chrome, no para añadirlo. */}
          <h3 className="sr-only">Metas por analista, agrupadas por supervisor</h3>
          {agruparPorSupervisor(borrador.vendedores).map((grupo, indice) => (
            // `role="group"` y no una `section` con nombre: los lectores
            // anuncian el equipo AL ENTRAR EL FOCO —que es como se rellenan 17
            // importes, tabulando— y además evita convertir cada supervisor en
            // un landmark más de la página.
            <section key={grupo.id} role="group" aria-labelledby={`equipo-${grupo.id}`}>
              <div className={cn(
                'flex items-baseline justify-between gap-3 border-b border-border/60 bg-muted/40 px-4 py-1.5',
                // El borde superior separa un equipo del anterior; en el
                // primero no hay nada que separar.
                indice > 0 && 'border-t',
              )}
              >
                <h4
                  id={`equipo-${grupo.id}`}
                  className="truncate text-[11px] font-extrabold uppercase tracking-[0.06em] text-muted-foreground"
                >
                  {grupo.supervisor}
                </h4>
                {/* El subtotal por equipo es lo que de verdad se le pide a ese
                    supervisor: sin él, la lista es solo una lista. */}
                <p className="shrink-0 text-xs font-extrabold tabular-nums text-primary">
                  {money(grupo.filas.reduce((suma, fila) => suma + metaTotal(fila), 0), 'PEN')}
                </p>
              </div>
              <ul aria-labelledby={`equipo-${grupo.id}`}>
                {grupo.filas.map((vendedor) => (
                  <MetaVendedor
                    key={vendedor.vendedor_id}
                    vendedor={vendedor}
                    editable={editable && !publicar.isPending}
                    onMetaTotal={(valor) => editarVendedor(
                      vendedor.vendedor_id,
                      (fila) => fijarMetaTotal(fila, valor),
                    )}
                  />
                ))}
              </ul>
            </section>
          ))}
        </Card>
      )}

      {dirty && editable && (
        <p className="sticky bottom-4 rounded-xl border border-warning/30 bg-card px-4 py-3 text-center text-xs font-semibold text-warning shadow-[var(--shadow-pop)]" role="status">
          Hay cambios sin publicar. Se crearán como una revisión nueva; el historial anterior no se modifica.
        </p>
      )}
    </ConfiguracionShell>
  )
}
