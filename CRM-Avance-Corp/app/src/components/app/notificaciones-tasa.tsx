import { useEffect, useState } from 'react'
import { Bell, BellOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/lib/auth-context'
import {
  activarPushTasa, consultarPushTasa, desactivarPushTasa, probarPushTasa,
  soportePushTasa, vincularCuentaPushTasa, type EstadoPushTasa,
} from '@/lib/notificaciones-tasa'

export function NotificacionesTasa({ soloActivacion = false }: { soloActivacion?: boolean }) {
  const { yo } = useAuth()
  const [estado, setEstado] = useState<EstadoPushTasa | null>(null)
  const [cargando, setCargando] = useState(true)
  const [ocupado, setOcupado] = useState(false)
  const [mensaje, setMensaje] = useState('')
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  const soporte = soportePushTasa()
  const real = yo?.rol === 'gerencia' && !yo.demo
  const cuentaId = yo?.id
  useEffect(() => {
    if (!real || !cuentaId || soporte !== 'disponible') { setCargando(false); return }
    let vigente = true
    vincularCuentaPushTasa(cuentaId)
    setCargando(true)
    setError('')
    void consultarPushTasa().then(resultado => { if (vigente) setEstado(resultado) })
      .catch(() => { if (vigente) setError('No pudimos consultar los avisos.') })
      .finally(() => { if (vigente) setCargando(false) })
    return () => { vigente = false }
  }, [real, cuentaId, soporte, revision])
  if (yo?.rol !== 'gerencia') return null
  const activo = estado?.dispositivo?.activo === true && 'Notification' in window && Notification.permission === 'granted'
  if (soloActivacion && (cargando || activo)) return null
  const accion = async (operacion: () => Promise<void>) => {
    setOcupado(true); setMensaje(''); setError('')
    try { await operacion() } catch (causa) { setError(causa instanceof Error ? causa.message : 'No pudimos completar el cambio.') }
    finally { setOcupado(false) }
  }
  return (
    <section aria-label="Notificaciones de solicitudes de tasa" className={`rounded-xl border border-primary/15 bg-primary/[0.03] p-4${soloActivacion ? ' mb-4' : ''}`}>
      <div className="flex items-start gap-3">
        <Bell className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden />
        <div className="min-w-0 flex-1 space-y-2">
          <h3 className="text-sm font-bold text-primary">Avisos en tu teléfono</h3>
          <p className="text-xs leading-relaxed text-muted-foreground">
            Recibe un aviso cuando llegue una solicitud de tasa, aunque tengas el CRM cerrado.
          </p>
          {yo.demo ? <p className="text-xs">Disponible al iniciar sesión con tu cuenta de Gerencia.</p>
            : soporte === 'instalar' ? <p className="text-xs">En iPhone, abre el CRM desde su icono en la pantalla de inicio. Si aún no aparece, en Safari toca Compartir → Añadir a pantalla de inicio.</p>
            : soporte === 'incompatible' ? <p className="text-xs">Este navegador no admite estos avisos. Usa un navegador actualizado; en iPhone necesitas iOS 16.4 o posterior.</p>
            : cargando ? <p className="text-xs" role="status">Comprobando este dispositivo…</p>
            : estado && !estado.configurado ? <p className="text-xs">Los avisos se están preparando. Vuelve a intentarlo más tarde.</p>
            : estado?.configurado ? (
              <div className="flex flex-wrap items-center gap-2">
                {activo ? <>
                  <span className="text-xs font-semibold text-primary">Activados en este dispositivo</span>
                  <Button size="sm" variant="outline" disabled={ocupado} onClick={() => void accion(async () => {
                    await probarPushTasa(estado.dispositivo!.id)
                    setMensaje('Aviso de prueba enviado. Revisa las notificaciones de tu teléfono.')
                  })}>Enviar prueba</Button>
                  <Button size="sm" variant="ghost" disabled={ocupado} onClick={() => void accion(async () => {
                    const resultado = await desactivarPushTasa(estado.dispositivo!.id)
                    setEstado({ ...estado, dispositivo: null })
                    setMensaje(resultado.pendiente
                      ? 'Avisos desactivados en este dispositivo. Confirmaremos la baja cuando vuelvas a entrar.'
                      : 'Avisos desactivados en este dispositivo.')
                  })}><BellOff className="size-4" aria-hidden /> Desactivar</Button>
                </> : <Button size="sm" disabled={ocupado} onClick={() => void accion(async () => {
                  const id = await activarPushTasa(yo.id, estado)
                  setEstado({ ...estado, dispositivo: { id, activo: true } })
                  setMensaje('Avisos activados. Puedes enviar una prueba para comprobarlos.')
                })}>{ocupado ? 'Activando…' : 'Activar notificaciones'}</Button>}
              </div>
            ) : null}
          {real && estado?.configurado && soporte === 'disponible' && 'Notification' in window && Notification.permission === 'denied'
            && <p className="text-xs">El permiso está bloqueado. Activa las notificaciones del CRM en los ajustes de tu teléfono o navegador y vuelve a abrir la aplicación.</p>}
          <p role="status" aria-atomic="true" className={mensaje ? 'text-xs font-semibold text-primary' : 'sr-only'}>{mensaje}</p>
          <p role="alert" aria-atomic="true" className={error ? 'text-xs text-destructive' : 'sr-only'}>{error}</p>
          {error && <Button size="sm" variant="outline" disabled={ocupado} onClick={() => setRevision(v => v + 1)}>Reintentar</Button>}
        </div>
      </div>
    </section>
  )
}
