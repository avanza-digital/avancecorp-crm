// Rentabilidad R3 — Configuración → Política de rentabilidad.
//
// La tasa anual de un contrato la decide la POLÍTICA (servidor, private.resolver_tasa):
// primera inversión = tasa base; renovación y upgrade heredan la del contrato origen;
// subir la tasa exige la autorización de Gerencia (bandeja). Esta pantalla muestra la
// política vigente, su historial versionado e inmutable, y permite a Gerencia publicar
// una revisión nueva (crm.publicar_politica_rentabilidad_fn, control optimista por versión).
// El modo siempre es «observación» hasta que R4 encienda el candado del servidor.
import { lazy, Suspense, useEffect, useMemo, useRef, useState, type JSX } from 'react'
import { Check, Lock, Percent, RefreshCw, Save, ShieldCheck, Unlock } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { useAuth } from '@/lib/auth-context'
import { cn } from '@/lib/utils'
import { fechaHora } from '@/lib/format'
import { parseMonto } from '@/lib/numero'
import { detalleModoPolitica, etiquetaModoPolitica, tasaTxt } from '@/lib/rentabilidad'
import { usePoliticaRentabilidad, usePublicarPoliticaRentabilidad } from '@/data/crm-queries'

const HistorialDecisionesTasaGerencia = lazy(() => import('@/components/app/historial-decisiones-tasa-gerencia').then((m) => ({ default: m.HistorialDecisionesTasaGerencia })))

interface Borrador {
  tasaBaseNueva: string
  topeTecnico: string
  vigenciaSolicitudDias: string
  /** R4: el interruptor del candado del servidor. */
  modo: 'observacion' | 'enforcement'
  nota: string
}

function validar(b: Borrador): string | null {
  const tasa = parseMonto(b.tasaBaseNueva)
  const tope = parseMonto(b.topeTecnico)
  const dias = Number.parseInt(b.vigenciaSolicitudDias, 10)
  if (tasa == null || tasa <= 0 || tasa > 50) return 'La tasa base debe estar entre 0 y 50%.'
  if (tope == null || tope <= 0 || tope > 50) return 'El tope técnico debe estar entre 0 y 50%.'
  if (tope < tasa) return 'El tope técnico no puede ser menor que la tasa base.'
  if (!Number.isInteger(dias) || dias < 1 || dias > 30) return 'La vigencia de una solicitud va de 1 a 30 días.'
  if (b.nota.trim().length > 500) return 'La nota no puede superar 500 caracteres.'
  return null
}

export function ConfigRentabilidad(): JSX.Element {
  const { yo } = useAuth()
  const esDemo = yo?.demo === true
  const consulta = usePoliticaRentabilidad(!esDemo)
  const publicar = usePublicarPoliticaRentabilidad()
  const [borrador, setBorrador] = useState<Borrador | null>(null)
  const [confirmando, setConfirmando] = useState(false)
  const [historialActivo, setHistorialActivo] = useState<'politica' | 'decisiones'>('politica')
  // Tras publicar, Radix devuelve el foco a «Publicar nueva versión», que pasa a deshabilitado (→ body): se posa en «Reglas vigentes».
  const reglasRef = useRef<HTMLDivElement>(null)

  const vigente = consulta.data?.vigente ?? null
  const puedeVerDecisiones = yo?.rol === 'gerencia' && !esDemo
  useEffect(() => {
    if (vigente) {
      setBorrador({
        tasaBaseNueva: String(vigente.tasa_base_nueva),
        topeTecnico: String(vigente.tope_tecnico),
        vigenciaSolicitudDias: String(vigente.vigencia_solicitud_dias),
        modo: vigente.modo === 'enforcement' ? 'enforcement' : 'observacion',
        nota: '',
      })
    }
  }, [vigente])

  const editable = Boolean(consulta.data?.puede_publicar) && !esDemo
  const modoVigente: 'observacion' | 'enforcement' = vigente?.modo === 'enforcement' ? 'enforcement' : 'observacion'
  const modoCambia = Boolean(borrador && editable && vigente && borrador.modo !== modoVigente)
  const avisoCandado = borrador?.modo === 'enforcement'
    ? 'Al publicar, cualquier alta o corrección con una tasa fuera de la política se rechazará al guardar. Mira la tarjeta «Rentabilidad: margen cedido» del Resumen durante las primeras horas.'
    : 'Al publicar, el candado del servidor queda apagado: se volverá a medir sin bloquear, y cualquiera podrá cerrar a la tasa que escriba.'
  const mensajeVivo = esDemo
    ? 'En demo no hay política de rentabilidad que consultar: solo existe sobre datos reales.'
    : consulta.isPending
      ? 'Cargando la política vigente…'
      : consulta.isError
        ? 'No se pudo cargar la política de rentabilidad.'
        : !vigente
          ? ''
          : modoCambia
            ? `Elegido «${etiquetaModoPolitica(borrador!.modo)}». ${avisoCandado}`
            : `Política de rentabilidad versión ${vigente.version}, modo ${etiquetaModoPolitica(modoVigente)}.`
  const dirty = useMemo(() => {
    if (!vigente || !borrador) return false
    return parseMonto(borrador.tasaBaseNueva) !== vigente.tasa_base_nueva
      || parseMonto(borrador.topeTecnico) !== vigente.tope_tecnico
      || Number.parseInt(borrador.vigenciaSolicitudDias, 10) !== vigente.vigencia_solicitud_dias
      || borrador.modo !== (vigente.modo === 'enforcement' ? 'enforcement' : 'observacion')   // R4: el modo cuenta como cambio
  }, [borrador, vigente])

  const preparar = () => {
    if (!borrador) return
    const error = validar(borrador)
    if (error) { toast.error(error); return }
    setConfirmando(true)
  }
  const confirmar = async () => {
    if (!borrador || !consulta.data) return
    try {
      const nueva = await publicar.mutateAsync({
        expectedVersion: consulta.data.expected_version,
        tasaBaseNueva: parseMonto(borrador.tasaBaseNueva) ?? 0,
        topeTecnico: parseMonto(borrador.topeTecnico) ?? 50,
        vigenciaSolicitudDias: Number.parseInt(borrador.vigenciaSolicitudDias, 10),
        modo: borrador.modo,
        nota: borrador.nota.trim() || null,
      })
      setConfirmando(false)
      toast.success(nueva.modo === 'enforcement'
        ? `Candado activo desde la v${nueva.version}: el servidor ya rechaza cualquier tasa fuera de la política.`
        : `Política de rentabilidad v${nueva.version} publicada: base ${tasaTxt(nueva.tasa_base_nueva)}.`)
      window.setTimeout(() => reglasRef.current?.focus(), 80)
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'No se pudo publicar la política.')
    }
  }

  return (
    <ConfiguracionShell
      icono={Percent}
      titulo="Política de rentabilidad"
      descripcion="La tasa de cada contrato la fija esta política: la base para una primera inversión y la heredada del contrato origen en renovaciones y upgrades. Subirla exige la autorización de Gerencia."
      soloLectura={!editable}
      estado={vigente ? {
        etiqueta: `Versión ${vigente.version}`,
        detalle: `Vigente desde ${fechaHora(vigente.vigente_desde)} · ${etiquetaModoPolitica(vigente.modo)}`,
      } : undefined}
      acciones={editable ? (
        <Button size="sm" onClick={preparar} disabled={!dirty || publicar.isPending}>
          <Save aria-hidden /> Publicar nueva versión
        </Button>
      ) : undefined}
    >
      {/* Región viva ÚNICA y persistente. `role="status"` se relee ENTERA en cada cambio, así que en vez de acumular
          frases lleva UN mensaje con precedencia: si hay un modo elegido distinto del vigente, eso es lo que importa;
          si no, el estado. Así, al deshacer la elección no queda anunciada una confirmación que ya no aplica. */}
      <p role="status" className="sr-only">{mensajeVivo}</p>
      {esDemo && (
        <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">En demo no hay política de rentabilidad que consultar: solo existe sobre datos reales.</CardContent></Card>
      )}
      {!esDemo && consulta.isPending && (
        <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">Cargando la política vigente…</CardContent></Card>
      )}
      {!esDemo && consulta.isError && (
        <Card><CardContent className="flex flex-col items-center gap-3 py-10 text-center">
          <p className="text-sm font-semibold text-destructive">No se pudo cargar la política de rentabilidad.</p>
          <Button variant="outline" size="sm" onClick={() => void consulta.refetch()}><RefreshCw aria-hidden /> Reintentar</Button>
        </CardContent></Card>
      )}

      {borrador && vigente && consulta.data && (
        <Card>
          <CardHeader className="border-b border-border/70 pb-3">
            <div ref={reglasRef} tabIndex={-1} className="flex flex-wrap items-center justify-between gap-3 outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">
              <div>
                <CardTitle>Reglas vigentes</CardTitle>
                <p className="mt-1 text-xs text-muted-foreground">Renovación y upgrade heredan siempre la tasa del contrato origen. Nunca se autoriza por debajo de la base.</p>
              </div>
              {/* --warning-text: el ámbar puro da 3,2:1 en texto pequeño (index.css lo documenta). */}
              <Badge color={vigente.modo === 'observacion' ? 'var(--warning-text)' : 'var(--chart-1)'} variant="outline">
                {vigente.modo === 'observacion' ? 'Observación: mide, no bloquea' : 'Candado activo: el servidor rechaza'}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-5 pt-5">
            <div className="grid gap-4 md:grid-cols-3">
              <div className="space-y-1.5">
                <Label htmlFor="pr-tasa">Tasa base · primera inversión (%)</Label>
                <Input id="pr-tasa" inputMode="decimal" value={borrador.tasaBaseNueva} onChange={(e) => setBorrador({ ...borrador, tasaBaseNueva: e.target.value })} readOnly={!editable} aria-readonly={!editable || undefined} className={cn(!editable && 'bg-muted/40 font-bold tabular-nums')} aria-describedby="pr-tasa-ayuda" />
                <p id="pr-tasa-ayuda" className="text-xs text-muted-foreground">También para un cliente existente que abre una inversión nueva (D1).</p>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="pr-tope">Tope técnico (%)</Label>
                <Input id="pr-tope" inputMode="decimal" value={borrador.topeTecnico} onChange={(e) => setBorrador({ ...borrador, topeTecnico: e.target.value })} readOnly={!editable} aria-readonly={!editable || undefined} className={cn(!editable && 'bg-muted/40 font-bold tabular-nums')} aria-describedby="pr-tope-ayuda" />
                <p id="pr-tope-ayuda" className="text-xs text-muted-foreground">Nadie puede pedir por encima. El tope comercial lo pone Gerencia en cada solicitud.</p>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="pr-dias">Vigencia de una solicitud (días)</Label>
                <Input id="pr-dias" inputMode="numeric" value={borrador.vigenciaSolicitudDias} onChange={(e) => setBorrador({ ...borrador, vigenciaSolicitudDias: e.target.value })} readOnly={!editable} aria-readonly={!editable || undefined} className={cn(!editable && 'bg-muted/40 font-bold tabular-nums')} aria-describedby="pr-dias-ayuda" />
                <p id="pr-dias-ayuda" className="text-xs text-muted-foreground">Una autorización sin usar caduca sola.</p>
              </div>
            </div>
            {/* R4 · EL INTERRUPTOR. Es lo único de esta pantalla que cambia lo que puede hacer un analista HOY, así que
                se explica en palabras de negocio y se confirma en el diálogo antes de publicar. */}
            <div className="rounded-xl border border-border bg-muted/20 p-3">
              {/* El grupo va NOMBRADO (role=group + aria-labelledby): no se confía en que cada lector lea el subárbol,
                  que es el patrón que el proyecto ya fijó en la tarjeta de observación y en el drawer de leads. */}
              <h4 id="pr-candado-titulo" className="text-sm font-bold text-foreground">Candado de la tasa en el servidor</h4>
              <p id="pr-candado-ayuda" className="mt-1 text-xs text-muted-foreground">
                Con el candado activo, ningún camino (CRM, portal, integración) puede registrar un contrato con una tasa
                distinta a la que decide esta política, salvo con una autorización vigente tuya para ese mismo contrato.
                Apagarlo es publicar otra versión: los contratos ya registrados no cambian.
              </p>
              <div role="group" aria-labelledby="pr-candado-titulo" aria-describedby="pr-candado-ayuda" className="mt-2.5 flex flex-col gap-2 sm:flex-row">
                {(['observacion', 'enforcement'] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    // aria-disabled y no disabled: sin permiso, un supervisor tiene que poder LEER qué modo está
                    // elegido (misma decisión que los campos de arriba, readOnly en vez de apagados). El clic se
                    // guarda en el handler, porque aria-disabled no lo bloquea.
                    aria-disabled={!editable || undefined}
                    // El nombre accesible es SOLO el título: la explicación va como descripción, para que el lector no
                    // relea 128 caracteres cada vez que se pulsa.
                    aria-labelledby={`pr-modo-${m}`}
                    aria-describedby={`pr-modo-${m}-det`}
                    aria-pressed={borrador.modo === m}
                    onClick={() => { if (editable) setBorrador({ ...borrador, modo: m }) }}
                    className={cn(
                      'flex min-h-11 flex-1 items-start gap-2 rounded-lg border px-3 py-2 text-left transition-colors',
                      'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40',
                      borrador.modo === m ? 'border-primary bg-primary/10 ring-2 ring-primary/40' : 'border-border bg-background hover:bg-muted/40',
                      !editable && 'cursor-not-allowed',
                    )}
                  >
                    {m === 'enforcement' ? <Lock className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden /> : <Unlock className="mt-0.5 size-4 shrink-0 text-muted-foreground-strong" aria-hidden />}
                    <span className="min-w-0">
                      <span id={`pr-modo-${m}`} className="flex items-center gap-1 text-xs font-bold text-foreground">
                        {etiquetaModoPolitica(m)}
                        {/* El estado no se distingue solo por color: el elegido lleva su marca. */}
                        {borrador.modo === m && <Check className="size-3 text-primary" aria-hidden />}
                      </span>
                      {/* -strong: el gris normal a 11 px sobre estos fondos no llega a 4,5:1 (index.css lo documenta). */}
                      <span id={`pr-modo-${m}-det`} className="mt-0.5 block text-[11px] text-muted-foreground-strong">{detalleModoPolitica(m)}</span>
                    </span>
                  </button>
                ))}
              </div>
              {/* El aviso se VE en las dos direcciones (encender y apagar), igual que se anuncia en las dos. */}
              {modoCambia && (
                <p className="mt-2 text-[11px] font-semibold text-warning-text">{avisoCandado}</p>
              )}
            </div>
            {editable && (
              <div className="space-y-1.5">
                <Label htmlFor="pr-nota">Nota de la revisión (opcional)</Label>
                <Textarea id="pr-nota" rows={2} value={borrador.nota} onChange={(e) => setBorrador({ ...borrador, nota: e.target.value })} placeholder="Por qué cambia la política" />
                {!dirty && <p className="text-[11px] text-muted-foreground">Cambia algún valor para poder publicar una versión nueva.</p>}
              </div>
            )}
            {consulta.data.observacion_activa_desde && (
              <p className="text-xs text-muted-foreground">
                Observación activa desde {fechaHora(consulta.data.observacion_activa_desde)}: cada alta y corrección de tasa queda anotada frente a esta política. El candado del servidor llega en la fase R4.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {consulta.data && (consulta.data.historial.length > 0 || puedeVerDecisiones) && (
        <Card>
          <CardHeader className="border-b border-border/70 pb-3">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2"><ShieldCheck className="size-4 text-accent" aria-hidden /> Historial de rentabilidad</CardTitle>
                <p className="mt-1 text-xs text-muted-foreground">Cambios generales y decisiones de tasa permanecen separados, pero se consultan en el mismo lugar.</p>
              </div>
              {puedeVerDecisiones && (
                <div role="tablist" aria-label="Tipo de historial de rentabilidad" className="flex rounded-lg border border-border bg-muted/30 p-1">
                  <button type="button" role="tab" aria-selected={historialActivo === 'politica'} aria-controls="historial-politica-panel" onClick={() => setHistorialActivo('politica')} className={cn('min-h-8 rounded-md px-3 text-xs font-bold transition-colors', historialActivo === 'politica' ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground')}>Cambios de política</button>
                  <button type="button" role="tab" aria-selected={historialActivo === 'decisiones'} aria-controls="historial-decisiones-panel" onClick={() => setHistorialActivo('decisiones')} className={cn('min-h-8 rounded-md px-3 text-xs font-bold transition-colors', historialActivo === 'decisiones' ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground')}>Decisiones de tasa</button>
                </div>
              )}
            </div>
          </CardHeader>
          {historialActivo === 'politica' || !puedeVerDecisiones ? (
            <CardContent id="historial-politica-panel" role="tabpanel" className="pt-4">
              {consulta.data.historial.length > 0 ? (
                <>
                  {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
                  <ol role="list" className="divide-y divide-border/60" aria-label="Versiones de la política de rentabilidad">
                    {consulta.data.historial.map((p) => (
                      <li key={p.id} className="flex flex-wrap items-baseline justify-between gap-2 py-2 text-xs">
                        <div className="min-w-0">
                          <span className="font-bold text-foreground">v{p.version}</span>
                          <span className="text-muted-foreground"> · base {tasaTxt(p.tasa_base_nueva)} · tope {tasaTxt(p.tope_tecnico)} · {p.vigencia_solicitud_dias} días · {etiquetaModoPolitica(p.modo)}</span>
                          {p.nota && <p className="mt-0.5 truncate text-muted-foreground" title={p.nota}>{p.nota}</p>}
                        </div>
                        <span className="shrink-0 tabular-nums text-muted-foreground">{fechaHora(p.publicada_en)}{p.publicada_por_nombre ? ` · ${p.publicada_por_nombre}` : ''}{p.es_vigente ? ' · vigente' : ''}</span>
                      </li>
                    ))}
                  </ol>
                </>
              ) : <p className="py-5 text-center text-sm text-muted-foreground">Todavía no hay versiones anteriores de la política.</p>}
            </CardContent>
          ) : (
            <div id="historial-decisiones-panel" role="tabpanel">
              <Suspense fallback={<div className="px-5 py-8 text-center text-sm text-muted-foreground">Cargando historial de decisiones…</div>}>
                <HistorialDecisionesTasaGerencia />
              </Suspense>
            </div>
          )}
        </Card>
      )}

      {confirmando && borrador && consulta.data && (
        <Dialog open onClose={() => setConfirmando(false)}>
          <DialogHeader>
            <DialogTitle>Publicar la versión {consulta.data.expected_version + 1}</DialogTitle>
            <DialogDescription>
              Base {tasaTxt(parseMonto(borrador.tasaBaseNueva) ?? 0)} · tope {tasaTxt(parseMonto(borrador.topeTecnico) ?? 0)} · solicitudes vigentes {borrador.vigenciaSolicitudDias} días · {etiquetaModoPolitica(borrador.modo)}. Los contratos ya creados no cambian; desde ahora el formulario propondrá la base nueva.
              {borrador.modo === 'enforcement' && modoVigente !== 'enforcement' && ' Enciendes el candado del servidor: a partir de esta versión, una tasa fuera de la política sin autorización vigente se rechaza al guardar.'}
              {borrador.modo === 'observacion' && modoVigente === 'enforcement' && ' Apagas el candado: se volverá a medir sin bloquear.'}
            </DialogDescription>
          </DialogHeader>
          <DialogBody />
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={() => setConfirmando(false)} disabled={publicar.isPending}>Cancelar</Button>
            <Button size="sm" onClick={() => void confirmar()} disabled={publicar.isPending}><Save aria-hidden /> Publicar</Button>
          </DialogFooter>
        </Dialog>
      )}
    </ConfiguracionShell>
  )
}
