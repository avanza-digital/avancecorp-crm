// Configuración › Celulares (F4-c, 07/10/2026): gerencia asigna, rota y cierra los celulares que capturan llamadas y
// ve su salud. Solo pantalla sobre cinco puertas que ya existen (nucleo 20261001160219, salud desde la undécima
// 20261006150254): sin migración. Prototipo aprobado por Jhosep el 06/10; decisiones D2–D8 en F4C-F4D-PLAN-CORTO.md.
// La clave se ve UNA sola vez: vive en el estado del diálogo y se suelta al cerrarlo; nunca pasa por toast, URL,
// almacenamiento, caché ni registros.
import { useMemo, useRef, useState, type FormEvent } from 'react'
import { Activity, Check, Copy, History, KeyRound, Plus, RefreshCw, Smartphone, X } from 'lucide-react'
import { toast } from 'sonner'
import { ConfiguracionShell } from '@/components/config/configuracion-shell'
import { PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { RadioGroup } from '@/components/ui/radio-group'
import { Select } from '@/components/ui/select'
import { CrmApiError } from '@/data/crm-api'
import { useCatalogoUsuariosAdministrables } from '@/data/crm-config-queries'
import { useCelulares, type FuenteCelulares } from '@/data/use-celulares'
import {
  ETIQUETA_CELULAR, MOTIVOS_CIERRE, VERSION_MACRO_VIGENTE, etiquetaMotivoCierre, fechaCortaLima, presentarSalud,
  resumenVigentes, type CelularSalud, type MotivoCierre, type TonoSalud,
} from '@/lib/celulares'
import type { UsuarioAdministrable } from '@/lib/usuarios-config'
import { cn } from '@/lib/utils'

const COLOR_TONO: Record<TonoSalud, string> = {
  bien: 'var(--accent)',
  aviso: 'var(--warning-text)',
  quieto: 'var(--muted-foreground-strong)',
  mal: 'var(--destructive-text)',
}
const AVISO = 'rounded-lg bg-warning/10 px-3 py-2 text-xs font-semibold leading-relaxed text-[var(--warning-text)]'
const ERROR = 'rounded-lg bg-destructive/[0.08] px-3 py-2 text-xs font-semibold leading-relaxed text-[var(--destructive-text)]'
const TH = 'px-3 py-2.5 text-left text-[10px] font-extrabold uppercase tracking-[0.1em] text-muted-foreground'
const TD = 'px-3 py-3 align-top text-[13px]'

type Dialogo =
  | { tipo: 'asignar' }
  | { tipo: 'clave'; etiqueta: string; credencial: string }
  | { tipo: 'rotar'; celular: CelularSalud }
  | { tipo: 'cerrar'; celular: CelularSalud }
  | null

/** Los códigos del servidor que la pantalla sabe decir; el resto cae en el texto por defecto. */
function textoDeError(e: unknown, porDefecto: string): string {
  if (e instanceof CrmApiError) {
    if (e.code === '42501') return 'No tienes permiso para esa acción.'
    if (e.code === '22023' || e.code === '23505' || e.code === 'CELULARES_CONTRACT' || e.code === 'EN_CURSO') return e.message
  }
  return porDefecto
}

const operaCelular = (u: UsuarioAdministrable) => u.activo_crm === true && (u.rol_crm === 'vendedor' || u.rol_crm === 'supervisor')
const ROL_CORTO: Record<string, string> = { vendedor: 'Analista', supervisor: 'Supervisión' }

export function ConfigCelulares() {
  const fuente = useCelulares()
  const catalogo = useCatalogoUsuariosAdministrables()
  const porId = useMemo(() => new Map((catalogo.data ?? []).map((u) => [u.perfil_id, u])), [catalogo.data])
  // null = sin catálogo: se confía en el servidor (rotar sigue y, si corresponde, él lo niega con su texto).
  const activo = (analistaId: string): boolean | null => (catalogo.data ? operaCelular(porId.get(analistaId) ?? ({} as UsuarioAdministrable)) : null)
  const candidatos = useMemo(() => (catalogo.data ?? []).filter(operaCelular)
    .sort((a, b) => a.nombre_completo.localeCompare(b.nombre_completo, 'es')), [catalogo.data])
  const vigentes = useMemo(() => [...(fuente?.vigentes ?? [])]
    .sort((a, b) => a.etiqueta.localeCompare(b.etiqueta, 'es', { numeric: true })), [fuente?.vigentes])
  const historial = useMemo(() => (fuente?.asignaciones ?? []).filter((a) => a.vigente_hasta !== null)
    .sort((a, b) => (b.vigente_hasta ?? '').localeCompare(a.vigente_hasta ?? '')), [fuente?.asignaciones])
  const [dialogo, setDialogo] = useState<Dialogo>(null)
  const [reintentando, setReintentando] = useState(false)

  if (!fuente) return null
  if (!fuente.habilitado) {
    // Por URL directa antes de aplicar la base: ninguna puerta se llama; se explica y listo.
    return (
      <ConfiguracionShell icono={Smartphone} titulo="Celulares" soloLectura={false}
        descripcion="Cada celular que captura llamadas tiene una etiqueta (C1, C2…), un analista y una clave que solo vive en ese celular.">
        <Card><CardContent className="pt-4">
          <PanelVacio icono={Smartphone} titulo="Todavía no está activa"
            detalle="La integración del celular espera su base en producción. Cuando esté aplicada, aquí se asignan los celulares y se ve su salud." />
        </CardContent></Card>
      </ConfiguracionShell>
    )
  }
  const resumen = resumenVigentes(vigentes, activo)
  const hayAviso = vigentes.some((c) => activo(c.analista_id) === false || c.estado_latido !== 'al_dia')
  const abrirClave = (etiqueta: string, credencial: string) => setDialogo({ tipo: 'clave', etiqueta, credencial })

  return (
    <ConfiguracionShell
      icono={Smartphone}
      titulo="Celulares"
      descripcion="Cada celular que captura llamadas tiene una etiqueta (C1, C2…), un analista y una clave que solo vive en ese celular. Desde aquí se asigna, se cambia la clave y se cierra. La salud es lo que declara el celular: el latido prueba que habla, no que capture llamadas."
      soloLectura={false}
      estado={{
        etiqueta: resumen.etiqueta,
        detalle: fuente.demo ? `${resumen.detalle} · Demo: nada se guarda.` : resumen.detalle,
        color: hayAviso ? 'var(--warning-text)' : 'var(--accent)',
      }}
      acciones={
        <Button size="sm" onClick={() => setDialogo({ tipo: 'asignar' })} disabled={fuente.ocupado}>
          <Plus aria-hidden /> Asignar celular
        </Button>
      }
    >
      <Card>
        <CardHeader className="border-b border-border/70 pb-3">
          <CardTitle className="flex items-center gap-2"><Activity className="size-4 text-accent" aria-hidden /> Celulares vigentes</CardTitle>
          <p className="mt-1 text-xs text-muted-foreground">«Al día» = mandó su latido en las últimas 7 horas. Sin horas exactas: la hora del latido delataba la última llamada.</p>
        </CardHeader>
        {fuente.estado.error ? (
          <CardContent className="pt-4">
            <PanelError mensaje="No se pudo consultar la salud de los celulares." reintentando={reintentando}
              onReintentar={() => { setReintentando(true); fuente.estado.reintentar(); setTimeout(() => setReintentando(false), 800) }} />
          </CardContent>
        ) : fuente.estado.cargando ? (
          <CardContent className="py-10 text-center text-sm text-muted-foreground" role="status">Consultando los celulares…</CardContent>
        ) : vigentes.length === 0 ? (
          <CardContent className="pt-4">
            <PanelVacio icono={Smartphone} titulo="Ningún celular asignado" detalle="Asigna el primero: la clave se muestra una sola vez.">
              <Button size="sm" onClick={() => setDialogo({ tipo: 'asignar' })}>Asignar celular</Button>
            </PanelVacio>
          </CardContent>
        ) : (
          <div className="ac-scroll overflow-x-auto px-2 pb-2">
            <table className="w-full min-w-[860px] border-collapse" aria-label="Celulares vigentes y su salud">
              <thead>
                <tr className="border-b border-border">
                  <th scope="col" className={TH}>Celular</th>
                  <th scope="col" className={TH}>Analista</th>
                  <th scope="col" className={TH}>Salud</th>
                  <th scope="col" className={TH}>Macro</th>
                  <th scope="col" className={cn(TH, 'text-right')}>En cola</th>
                  <th scope="col" className={TH}>Desde</th>
                  <th scope="col" className={TH}><span className="sr-only">Acciones</span></th>
                </tr>
              </thead>
              <tbody>
                {vigentes.map((c) => {
                  const s = presentarSalud(c, activo(c.analista_id))
                  const usuario = porId.get(c.analista_id)
                  return (
                    <tr key={c.asignacion_id} className="border-b border-border/60 last:border-b-0">
                      <td className={TD}><span className="text-sm font-extrabold text-primary">{c.etiqueta}</span></td>
                      <td className={TD}>
                        <div className="font-bold text-foreground">{c.analista_nombre ?? usuario?.nombre_completo ?? 'Sin nombre'}</div>
                        <div className="mt-0.5 text-[11px] text-muted-foreground">{usuario?.rol_crm ? ROL_CORTO[usuario.rol_crm] ?? usuario.rol_crm : activo(c.analista_id) === false ? 'De baja' : '—'}</div>
                      </td>
                      <td className={TD}>
                        <div className="flex flex-wrap items-center gap-1.5">
                          <Badge variant="outline" dot color={COLOR_TONO[s.principal.tono]}>{s.principal.texto}</Badge>
                          {s.extras.map((x) => <Badge key={x.texto} variant="outline" color={COLOR_TONO[x.tono]}>{x.texto}</Badge>)}
                        </div>
                        {s.pista && <p className="mt-1.5 text-[11px] text-muted-foreground">{s.pista}</p>}
                      </td>
                      <td className={TD}><span className="font-mono text-xs font-semibold">{s.macroTexto}</span></td>
                      <td className={cn(TD, 'text-right tabular-nums', s.colaAviso ? 'font-extrabold text-[var(--warning-text)]' : 'font-bold')}>{s.colaTexto}</td>
                      <td className={cn(TD, 'whitespace-nowrap text-xs font-semibold text-[var(--muted-foreground-strong)]')}>{fechaCortaLima(c.vigente_desde)}</td>
                      <td className={cn(TD, 'whitespace-nowrap text-right')}>
                        <Button variant="ghost" size="xs" disabled={!s.rotable || fuente.ocupado} aria-label={`Rotar la clave de ${c.etiqueta}`}
                          onClick={() => setDialogo({ tipo: 'rotar', celular: c })}>
                          <RefreshCw className="size-3.5" aria-hidden /> Rotar clave
                        </Button>
                        <Button variant="ghost" size="xs" disabled={fuente.ocupado} aria-label={`Cerrar ${c.etiqueta}`}
                          onClick={() => setDialogo({ tipo: 'cerrar', celular: c })}>
                          <X className="size-3.5" aria-hidden /> Cerrar
                        </Button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card>
        <CardHeader className="border-b border-border/70 pb-3">
          <CardTitle className="flex items-center gap-2"><History className="size-4 text-accent" aria-hidden /> Historial de cierres</CardTitle>
          <p className="mt-1 text-xs text-muted-foreground">Cada rotación cierra la asignación anterior y abre una nueva con la misma etiqueta.</p>
        </CardHeader>
        {historial.length === 0 ? (
          <CardContent className="py-6 text-center text-xs text-muted-foreground">Todavía no hay cierres.</CardContent>
        ) : (
          <div className="ac-scroll overflow-x-auto px-2 pb-2">
            <table className="w-full min-w-[640px] border-collapse" aria-label="Historial de cierres de celulares">
              <thead>
                <tr className="border-b border-border">
                  <th scope="col" className={TH}>Celular</th>
                  <th scope="col" className={TH}>Analista</th>
                  <th scope="col" className={TH}>Vigencia</th>
                  <th scope="col" className={TH}>Motivo del cierre</th>
                </tr>
              </thead>
              <tbody>
                {historial.map((a) => (
                  <tr key={a.asignacion_id} className="border-b border-border/60 last:border-b-0">
                    <td className={TD}><span className="font-extrabold text-primary">{a.etiqueta}</span></td>
                    <td className={cn(TD, 'font-semibold')}>{a.analista_nombre ?? porId.get(a.analista_id)?.nombre_completo ?? 'Sin nombre'}</td>
                    <td className={cn(TD, 'whitespace-nowrap text-[var(--muted-foreground-strong)]')}>{fechaCortaLima(a.vigente_desde)} → {a.vigente_hasta ? fechaCortaLima(a.vigente_hasta) : '—'}</td>
                    <td className={cn(TD, 'text-[var(--muted-foreground-strong)]')}>{etiquetaMotivoCierre(a.motivo_cierre)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {dialogo?.tipo === 'asignar' && (
        <DialogoAsignar fuente={fuente} candidatos={candidatos} catalogoListo={!catalogo.isPending} vigentes={vigentes}
          cerrar={() => setDialogo(null)} alAsignar={abrirClave}
          rotarEnVez={(etiqueta) => { const c = vigentes.find((x) => x.etiqueta === etiqueta); if (c) setDialogo({ tipo: 'rotar', celular: c }) }} />
      )}
      {dialogo?.tipo === 'clave' && (
        <DialogoClave etiqueta={dialogo.etiqueta} credencial={dialogo.credencial}
          cerrar={() => { setDialogo(null); toast.success(`Listo. Cuando ${dialogo.etiqueta} mande su primer latido, aquí dirá «Al día».`) }} />
      )}
      {dialogo?.tipo === 'rotar' && (
        <DialogoRotar fuente={fuente} celular={dialogo.celular} cerrar={() => setDialogo(null)} alRotar={abrirClave} />
      )}
      {dialogo?.tipo === 'cerrar' && (
        <DialogoCerrar fuente={fuente} celular={dialogo.celular} cerrar={() => setDialogo(null)} />
      )}
    </ConfiguracionShell>
  )
}

function DialogoAsignar({ fuente, candidatos, catalogoListo, vigentes, cerrar, alAsignar, rotarEnVez }: {
  fuente: FuenteCelulares
  candidatos: readonly UsuarioAdministrable[]
  catalogoListo: boolean
  vigentes: readonly CelularSalud[]
  cerrar: () => void
  alAsignar: (etiqueta: string, credencial: string) => void
  rotarEnVez: (etiqueta: string) => void
}) {
  const [etiqueta, setEtiqueta] = useState('')
  const [analistaId, setAnalistaId] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [conflicto, setConflicto] = useState<string | null>(null)
  const campoEtiqueta = useRef<HTMLInputElement>(null)
  const idError = 'celular-asignar-error'
  const enviar = async (evento: FormEvent) => {
    evento.preventDefault()
    if (fuente.ocupado) return
    const et = etiqueta.trim().toUpperCase()
    setConflicto(null)
    if (!ETIQUETA_CELULAR.test(et)) { setError('La etiqueta es una C seguida de 1 a 3 dígitos: C1, C2 … C999.'); return }
    if (!analistaId) { setError('Elige a la persona que usará el celular.'); return }
    setError(null)
    try {
      const c = await fuente.asignar(et, analistaId)
      alAsignar(c.etiqueta, c.credencial)
    } catch (e) {
      setError(textoDeError(e, 'No se pudo asignar el celular. Inténtalo de nuevo.'))
      if (e instanceof CrmApiError && e.code === '23505' && vigentes.some((v) => v.etiqueta === et)) setConflicto(et)
    }
  }
  return (
    <Dialog open onClose={() => { if (!fuente.ocupado) cerrar() }} ariaLabel="Asignar un celular" focoInicial={campoEtiqueta}>
      <form onSubmit={(e) => { void enviar(e) }} noValidate>
        <DialogHeader>
          <DialogTitle>Asignar un celular</DialogTitle>
          <DialogDescription>La clave se muestra una sola vez, al asignar. Ten el celular a la mano para pegarla en MacroDroid.</DialogDescription>
        </DialogHeader>
        <DialogBody className="space-y-4">
          <div>
            <Label htmlFor="celular-etiqueta">Etiqueta del celular</Label>
            <Input ref={campoEtiqueta} id="celular-etiqueta" value={etiqueta} maxLength={4} autoComplete="off" placeholder="C2"
              aria-describedby={error ? idError : 'celular-etiqueta-ayuda'} aria-invalid={error ? true : undefined}
              onChange={(e) => { setEtiqueta(e.target.value.toUpperCase()); setError(null); setConflicto(null) }}
              className="mt-1.5 h-11 text-base font-bold uppercase" />
            <p id="celular-etiqueta-ayuda" className="mt-1.5 text-[11px] leading-relaxed text-muted-foreground">Una C seguida de 1 a 3 dígitos: C1, C2 … C999. Es el nombre que verás en la salud y en cada llamada.</p>
          </div>
          <div>
            <Label htmlFor="celular-analista">Analista que lo usará</Label>
            <Select id="celular-analista" value={analistaId} onChange={(e) => { setAnalistaId(e.target.value); setError(null) }} className="mt-1.5 h-11 font-semibold"
              aria-describedby="celular-analista-ayuda" disabled={!catalogoListo}>
              <option value="">{catalogoListo ? 'Elige a la persona…' : 'Consultando a las personas…'}</option>
              {candidatos.map((u) => <option key={u.perfil_id} value={u.perfil_id}>{u.nombre_completo} · {ROL_CORTO[u.rol_crm ?? ''] ?? u.rol_crm}</option>)}
            </Select>
            <p id="celular-analista-ayuda" className="mt-1.5 text-[11px] leading-relaxed text-muted-foreground">Solo analistas y supervisores activos en el CRM. Las llamadas de este celular se unen a las gestiones de esta persona.</p>
          </div>
          {error && (
            <div id={idError} role="alert" className={ERROR}>
              <p>{error}</p>
              {conflicto && <div className="mt-2"><Button type="button" variant="outline" size="xs" onClick={() => rotarEnVez(conflicto)}>Rotar la clave de {conflicto}</Button></div>}
            </div>
          )}
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={cerrar} disabled={fuente.ocupado}>Cancelar</Button>
          <Button type="submit" disabled={fuente.ocupado}>{fuente.ocupado ? 'Asignando…' : 'Asignar y ver la clave'}</Button>
        </DialogFooter>
      </form>
    </Dialog>
  )
}

/** La clave, una sola vez. Esc y el clic fuera no cierran: solo «Ya la copié al celular» (decisión D4). */
function DialogoClave({ etiqueta, credencial, cerrar }: { etiqueta: string; credencial: string; cerrar: () => void }) {
  const [copiado, setCopiado] = useState<'no' | 'si' | 'fallo'>('no')
  const botonCerrar = useRef<HTMLButtonElement>(null)
  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(credencial)
      setCopiado('si')
    } catch {
      // Sin portapapeles (permiso o navegador): el campo queda para seleccionar y copiar a mano.
      setCopiado('fallo')
    }
  }
  return (
    <Dialog open onClose={() => {}} ariaLabel={`Clave de ${etiqueta}, se ve una sola vez`} focoInicial={botonCerrar}>
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2"><KeyRound className="size-4 text-accent" aria-hidden /> Clave de {etiqueta} · se ve una sola vez</DialogTitle>
        <DialogDescription>Pégala en el celular ahora. Al cerrar esta ventana no se puede volver a ver: si se pierde, se rota y sale una nueva.</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-4">
        <div className="flex items-center gap-2">
          <input readOnly value={credencial} aria-label={`Clave del celular ${etiqueta}`} onFocus={(e) => e.currentTarget.select()}
            className="min-w-0 flex-1 rounded-lg border border-border bg-muted/40 px-2.5 py-2 font-mono text-[11px] text-[var(--muted-foreground-strong)]" />
          <Button type="button" size="sm" onClick={() => { void copiar() }} aria-label="Copiar la clave">
            {copiado === 'si' ? <Check className="size-4" aria-hidden /> : <Copy className="size-4" aria-hidden />}
            {copiado === 'si' ? 'Copiada' : 'Copiar'}
          </Button>
        </div>
        {copiado === 'fallo' && <p role="alert" className={ERROR}>No se pudo copiar sola. Selecciona el texto del campo y cópialo a mano.</p>}
        <ol className="list-decimal space-y-1 pl-5 text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
          <li>En el celular, abre MacroDroid → <b>Variables</b> → <span className="font-mono">clave_celular</span> y pega la clave.</li>
          <li>Revisa que <span className="font-mono">url_llamadas</span> sea la de producción y vacía <span className="font-mono">cola_llamadas</span> y <span className="font-mono">errores_llamadas</span>.</li>
          <li>Pon <span className="font-mono">ultimo_latido</span> en 0. En menos de 5 minutos esta tarjeta dirá «Al día» con <span className="font-mono">{VERSION_MACRO_VIGENTE}</span>.</li>
        </ol>
        <p className={AVISO}>Esta ventana solo se cierra con el botón de abajo. Esc o un clic fuera no la cierran, para que la clave no se pierda a medio camino.</p>
      </DialogBody>
      <DialogFooter>
        <Button ref={botonCerrar} type="button" onClick={cerrar}>Ya la copié al celular</Button>
      </DialogFooter>
    </Dialog>
  )
}

function DialogoRotar({ fuente, celular, cerrar, alRotar }: {
  fuente: FuenteCelulares
  celular: CelularSalud
  cerrar: () => void
  alRotar: (etiqueta: string, credencial: string) => void
}) {
  const [error, setError] = useState<string | null>(null)
  const cola = celular.eventos_en_cola ?? 0
  const confirmar = async () => {
    if (fuente.ocupado) return
    setError(null)
    try {
      const c = await fuente.rotar(celular.etiqueta)
      alRotar(c.etiqueta, c.credencial)
    } catch (e) {
      setError(textoDeError(e, 'No se pudo rotar la clave. Inténtalo de nuevo.'))
    }
  }
  return (
    <Dialog open onClose={() => { if (!fuente.ocupado) cerrar() }} ariaLabel={`Rotar la clave de ${celular.etiqueta}`}>
      <DialogHeader>
        <DialogTitle>Rotar la clave de {celular.etiqueta}</DialogTitle>
        <DialogDescription>{celular.analista_nombre ?? 'El analista'} sigue con el celular. Solo cambia la clave.</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-3 text-sm">
        <p>La clave actual deja de valer al instante: con ella el celular recibirá «No autorizado» y avisará en la barra de notificaciones. Los avisos que ya estén en su cola esperan hasta que pegues la nueva.</p>
        <p className="rounded-lg bg-accent/[0.08] px-3 py-2 text-xs font-semibold text-primary">En cola ahora: {cola === 1 ? '1 aviso' : `${cola} avisos`}. Cuando pegues la clave nueva, el celular los enviará solo.</p>
        {error && <p role="alert" className={ERROR}>{error}</p>}
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" onClick={cerrar} disabled={fuente.ocupado}>Cancelar</Button>
        <Button onClick={() => { void confirmar() }} disabled={fuente.ocupado}>{fuente.ocupado ? 'Rotando…' : 'Rotar y ver la nueva clave'}</Button>
      </DialogFooter>
    </Dialog>
  )
}

function DialogoCerrar({ fuente, celular, cerrar }: { fuente: FuenteCelulares; celular: CelularSalud; cerrar: () => void }) {
  const [motivo, setMotivo] = useState<MotivoCierre | null>(null)
  const [error, setError] = useState<string | null>(null)
  const cola = celular.eventos_en_cola ?? 0
  const confirmar = async () => {
    if (fuente.ocupado) return
    if (!motivo) { setError('Elige el motivo del cierre.'); return }
    setError(null)
    try {
      await fuente.cerrar(celular.asignacion_id, motivo)
      cerrar()
      toast.success(`${celular.etiqueta} cerrado. Su clave ya no vale: el celular recibirá «No autorizado».`)
    } catch (e) {
      setError(textoDeError(e, 'No se pudo cerrar la asignación. Actualiza la lista antes de reintentarlo.'))
    }
  }
  return (
    <Dialog open onClose={() => { if (!fuente.ocupado) cerrar() }} ariaLabel={`Cerrar ${celular.etiqueta}`}>
      <DialogHeader>
        <DialogTitle>Cerrar {celular.etiqueta}</DialogTitle>
        <DialogDescription>{celular.analista_nombre ?? 'El analista'} deja de capturar llamadas con este celular.</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-4 text-sm">
        <p>La clave deja de valer al instante. Las llamadas ya guardadas se conservan; los avisos pendientes se quedan en el celular y no entran.</p>
        {cola > 0 && <p className={AVISO}>Este celular tiene {cola === 1 ? '1 aviso' : `${cola} avisos`} sin enviar. Si esas llamadas importan, pídele al analista que toque «Enviar cola» antes de cerrar.</p>}
        <RadioGroup leyenda="Motivo" obligatorio valor={motivo} onCambio={(v) => { setMotivo(v); setError(null) }}
          opciones={MOTIVOS_CIERRE.map((m) => ({ valor: m.clave, etiqueta: m.etiqueta, detalle: m.detalle }))}
          invalido={Boolean(error)} descripcion={error ?? undefined} />
      </DialogBody>
      <DialogFooter>
        <Button variant="outline" onClick={cerrar} disabled={fuente.ocupado}>Cancelar</Button>
        <Button variant="destructive" onClick={() => { void confirmar() }} disabled={fuente.ocupado}>{fuente.ocupado ? 'Cerrando…' : 'Cerrar asignación'}</Button>
      </DialogFooter>
    </Dialog>
  )
}
