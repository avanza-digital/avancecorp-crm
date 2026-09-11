import { Bell, CheckCircle2, ShieldCheck, Volume2, VolumeX, X, XCircle } from 'lucide-react'
import type { SolicitudTasa } from '@/data/crm-api'
import { useRespuestasTasa } from '@/lib/respuestas-tasa-context'
import { tituloRespuestaTasa } from '@/lib/respuestas-tasa'
import { fmtFecha, money } from '@/lib/format'
import { hashDe } from '@/lib/router'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

const tasa = (n: number) => `${n.toLocaleString('es-PE', { maximumFractionDigits: 2 })}%`

export function ConfiguracionRespuestasTasa({ soloActivacion = false }: { soloActivacion?: boolean }) {
  const a = useRespuestasTasa()
  if (!a.habilitado || (soloActivacion && (a.configurado || a.cargando))) return null
  return <section aria-label="Alertas de respuestas de tasa" className={`rounded-xl border border-accent/20 bg-accent/[0.04] p-4${soloActivacion ? ' mb-4' : ''}`}>
    <div className="flex items-start gap-3">
      <Bell className="mt-0.5 size-5 shrink-0 text-accent" aria-hidden />
      <div className="min-w-0 flex-1 space-y-2">
        <h3 className="text-sm font-bold text-primary">Respuestas de Gerencia en tu PC</h3>
        <p className="text-xs leading-relaxed text-muted-foreground">Recibe una alerta cuando Gerencia apruebe, rechace o autorice un tope para tu solicitud de tasa. Mantén el CRM abierto, aunque trabajes en otra ventana.</p>
        {!a.configurado ? <Button size="sm" disabled={a.ocupado} onClick={() => void a.activar()}>
          <Volume2 className="size-4" aria-hidden />{a.ocupado ? 'Activando…' : 'Activar alertas y sonido'}
        </Button> : <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="outline" disabled={a.ocupado} onClick={() => void a.cambiarSonido()} aria-pressed={a.sonido}>
            {a.sonido ? <Volume2 className="size-4" aria-hidden /> : <VolumeX className="size-4" aria-hidden />}
            {a.sonido ? 'Silenciar sonido' : 'Activar sonido'}
          </Button>
          <Button size="sm" variant="outline" disabled={a.ocupado} onClick={() => void a.cambiarEscritorio()} aria-pressed={a.escritorio}>
            {a.escritorio ? 'Desactivar aviso de escritorio' : 'Activar aviso de escritorio'}
          </Button>
          <Button size="sm" variant="ghost" disabled={a.ocupado} onClick={a.probar}>Probar alerta</Button>
        </div>}
        <p className="text-[11px] text-muted-foreground">El sonido respeta el volumen y los permisos de tu PC. Las respuestas sin leer se guardan en este navegador.</p>
        <p role="status" className={a.mensaje ? 'text-xs font-semibold text-primary' : 'sr-only'}>{a.mensaje}</p>
        {a.error && <p role="alert" className="text-xs text-destructive-text">{a.error}</p>}
      </div>
    </div>
  </section>
}

export function CampanaRespuestasTasa({ otrosPendientes, errorPendientes, cargandoPendientes }: { otrosPendientes: number; errorPendientes: boolean; cargandoPendientes: boolean }) {
  const a = useRespuestasTasa()
  const total = a.sinLeer + otrosPendientes
  return <button type="button" title="Abrir notificaciones" aria-label={`Abrir notificaciones: ${a.sinLeer} ${a.sinLeer === 1 ? 'respuesta' : 'respuestas'} de tasa sin leer${otrosPendientes ? ` y ${otrosPendientes} pendientes` : ''}`}
    onClick={a.abrirBandeja} className="relative inline-flex size-11 shrink-0 cursor-pointer items-center justify-center rounded-lg transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40 sm:size-9">
    <Bell className="size-4" aria-hidden />
    {total > 0 && <span className="absolute -right-1 -top-1 grid min-w-4 place-items-center rounded-full bg-destructive px-1 text-[9px] font-extrabold leading-4 text-destructive-foreground" aria-hidden>{total > 99 ? '99+' : total}</span>}
    {total === 0 && (a.error || errorPendientes) && <span className="absolute right-0.5 top-0.5 size-2 rounded-full bg-warning ring-2 ring-card" aria-hidden />}
    {total === 0 && !a.error && !errorPendientes && (a.cargando || cargandoPendientes) && <span className="absolute right-0.5 top-0.5 size-2 animate-pulse rounded-full bg-primary ring-2 ring-card motion-reduce:animate-none" aria-hidden />}
  </button>
}

function IconoRespuesta({ solicitud }: { solicitud: SolicitudTasa }) {
  const Icono = solicitud.tasa_maxima_autorizada == null ? XCircle
    : solicitud.tasa_maxima_autorizada === solicitud.tasa_solicitada ? CheckCircle2 : ShieldCheck
  return <Icono className={`mt-0.5 size-5 shrink-0 ${solicitud.tasa_maxima_autorizada == null ? 'text-destructive-text' : 'text-accent'}`} aria-hidden />
}

export function DialogoRespuestasTasa({ abierto, solicitudId, seleccionada, cerrar }: {
  abierto: boolean; solicitudId: string | null; seleccionada: SolicitudTasa | null; cerrar: () => void
}) {
  const a = useRespuestasTasa()
  const ordenadas = [...a.solicitudes].sort((x, y) => Number(a.esLeida(x)) - Number(a.esLeida(y)))
  return <Dialog open={abierto} onClose={cerrar} className="w-[600px]">
    <DialogHeader>
      <div className="flex items-center justify-between gap-3">
        <DialogTitle>{solicitudId ? 'Respuesta de Gerencia' : 'Notificaciones'}</DialogTitle>
        <Button size="icon" variant="ghost" onClick={cerrar} aria-label="Cerrar notificaciones"><X className="size-4" aria-hidden /></Button>
      </div>
      <p className="text-xs text-muted-foreground">{solicitudId ? 'Detalle de tu solicitud de tasa.' : `${a.sinLeer} respuestas de tasa sin leer en esta PC.`}</p>
    </DialogHeader>
    <DialogBody className="space-y-4">
      {a.error && <div role="alert" className="space-y-2 text-xs text-destructive-text"><p>{a.error}</p><Button size="sm" variant="outline" onClick={a.reintentar}>Reintentar</Button></div>}
      {a.cargando ? <p role="status" className="text-sm">Consultando respuestas…</p> : solicitudId ? (
        seleccionada ? <DetalleRespuesta solicitud={seleccionada} cerrar={cerrar} />
          : !a.error && <p className="text-sm text-muted-foreground">Esta respuesta ya no está en la bandeja reciente o no está disponible para tu cuenta. Revisa la ficha correspondiente.</p>
      ) : <>
        {ordenadas.length === 0 && !a.error && <p className="text-sm text-muted-foreground">Aún no tienes respuestas de Gerencia.</p>}
        <ul className="space-y-2" aria-label="Respuestas de tasa">
          {ordenadas.map(s => <li key={s.id} className={`rounded-xl border p-3 ${a.esLeida(s) ? 'border-border' : 'border-accent/30 bg-accent/[0.04]'}`}>
            <div className="flex items-start gap-3">
              <IconoRespuesta solicitud={s} />
              <div className="min-w-0 flex-1">
                <p className="text-xs font-bold text-primary">{tituloRespuestaTasa(s)}</p>
                <p className="mt-1 break-words text-sm font-semibold">{s.cliente_nombre}</p>
                <p className="mt-1 text-[11px] text-muted-foreground">{fmtFecha(s.resuelta_en!)} · {a.esLeida(s) ? 'Leída' : 'Sin leer'}</p>
                <Button size="sm" variant="ghost" className="mt-1" onClick={() => a.abrirSolicitud(s.id)}>Ver solicitud<span className="sr-only"> de {s.cliente_nombre}</span></Button>
              </div>
            </div>
          </li>)}
        </ul>
        <p className="text-[11px] text-muted-foreground">Incluye autorizaciones vigentes y respuestas cerradas de los últimos 7 días. La primera visita no anuncia respuestas antiguas.</p>
      </>}
    </DialogBody>
    <DialogFooter className="flex-wrap justify-between">
      <a href={hashDe('alertas')} onClick={cerrar} className="rounded text-xs font-semibold text-accent underline underline-offset-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">Ver otros pendientes</a>
      {!solicitudId && a.sinLeer > 0 && <Button size="sm" variant="outline" onClick={() => void a.marcarLeidas()}>Marcar respuestas como leídas</Button>}
    </DialogFooter>
  </Dialog>
}

function DetalleRespuesta({ solicitud: s, cerrar }: { solicitud: SolicitudTasa; cerrar: () => void }) {
  return <div className="space-y-4">
    <div className="flex items-start gap-3"><IconoRespuesta solicitud={s} /><div><h3 className="text-sm font-bold text-primary">{tituloRespuestaTasa(s)}</h3><p className="mt-1 break-words text-lg font-bold">{s.cliente_nombre}</p></div></div>
    <dl className="grid grid-cols-2 gap-3 rounded-xl bg-muted/50 p-3 text-xs">
      <div><dt className="text-muted-foreground">Tasa solicitada</dt><dd className="mt-1 font-bold">{tasa(s.tasa_solicitada)}</dd></div>
      <div><dt className="text-muted-foreground">Decisión de Gerencia</dt><dd className="mt-1 font-bold">{s.tasa_maxima_autorizada == null ? 'Rechazada' : `Autorizada hasta ${tasa(s.tasa_maxima_autorizada)}`}</dd></div>
      <div><dt className="text-muted-foreground">Capital</dt><dd className="mt-1 font-semibold">{money(s.capital, s.moneda)}</dd></div>
      <div><dt className="text-muted-foreground">Respondida el</dt><dd className="mt-1 font-semibold">{fmtFecha(s.resuelta_en!)}</dd></div>
    </dl>
    <div><p className="text-xs font-bold">Respuesta de Gerencia</p><p className="mt-1 whitespace-pre-wrap break-words text-sm">{s.motivo_resolucion || 'Gerencia no añadió un comentario.'}</p></div>
    {s.estado_efectivo === 'aprobada_con_tope' && <p className="text-xs text-muted-foreground">Revisa el tope y acéptalo o declínalo desde «Tus solicitudes de tasa» en Hoy.</p>}
    {!s.vigente && s.tasa_maxima_autorizada != null && <p className="text-xs text-muted-foreground">Esta autorización ya no está disponible para una nueva operación. Revisa su estado en la ficha.</p>}
    <a href={s.lead_id ? hashDe('cartera', s.lead_id) : hashDe('mi-cartera')} onClick={cerrar} className="inline-flex min-h-10 items-center rounded-lg bg-primary px-3 text-xs font-semibold text-primary-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40">{s.lead_id ? 'Ir a la ficha del lead' : 'Ir a mi cartera'}</a>
  </div>
}
