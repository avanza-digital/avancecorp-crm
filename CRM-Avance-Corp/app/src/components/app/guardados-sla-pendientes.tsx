import { useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { Button } from '@/components/ui/button'
import { confirmarPendienteSla, listarPendientesSla, suscribirPendientesSla } from '@/data/sla-operacion-comandos'
import { mensajeDeError } from '@/data/crm-api'
import { slaOperacionKeys } from '@/data/sla-operacion-queries'

const NOMBRES: Record<string, string> = {
  registrar_actividad_v2: 'Contacto', cerrar_tarea_v2: 'Cierre de tarea',
  cerrar_reunion_v2: 'Cierre de cita', reprogramar_reunion_v2: 'Reprogramación de cita',
  reprogramar_tarea_v2: 'Reprogramación de tarea', cerrar_reunion_v3: 'Cierre de cita',
  registrar_llamada_v3: 'Resultado de llamada',
  registrar_llamada_v4: 'Resultado de llamada',
}

/** El núcleo conserva el envío original; este panel solo pide su confirmación
 * explícita. Nunca vuelve a calcular el siguiente paso después de una recarga. */
export function GuardadosSlaPendientes() {
  const { yo } = useAuth()
  const { recargar } = useCRMData()
  const cliente = useQueryClient()
  const actor = yo && !yo.demo && ['vendedor', 'supervisor', 'gerencia'].includes(yo.rol) ? yo.id : null
  const actorActual = useRef(actor)
  actorActual.current = actor
  const [pendientes, setPendientes] = useState(() => listarPendientesSla(actor))
  const [ocupado, setOcupado] = useState<string | null>(null)
  const [mensaje, setMensaje] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pagina, setPagina] = useState(0)
  useEffect(() => {
    const actualizar = () => setPendientes(listarPendientesSla(actor))
    const cancelar = suscribirPendientesSla(actualizar)
    actualizar(); setMensaje(null); setError(null); setPagina(0)
    return cancelar
  }, [actor])
  async function verificar(operacion: string) {
    if (!actor || ocupado) return
    setOcupado(operacion); setError(null); setMensaje(null)
    try {
      await confirmarPendienteSla(actor, operacion)
      if (actorActual.current !== actor) return
      const cargado = await recargar()
      await cliente.invalidateQueries({ queryKey: slaOperacionKeys.raiz() })
      if (actorActual.current === actor) setMensaje(cargado ? 'Guardado confirmado y vista actualizada.' : 'Guardado confirmado. Actualiza la vista para consultar los datos más recientes.')
    } catch (causa) {
      if (actorActual.current === actor) setError(mensajeDeError(causa, 'No se pudo confirmar el guardado. Reintenta.'))
    } finally {
      if (actorActual.current === actor) {
        setOcupado(null); setPendientes(listarPendientesSla(actor))
      }
    }
  }
  if (!actor || (!pendientes.length && !mensaje && !error)) return null
  const ultimaPagina = Math.max(0, Math.ceil(pendientes.length / 5) - 1)
  const paginaVisible = Math.min(pagina, ultimaPagina)
  const visibles = pendientes.slice(paginaVisible * 5, paginaVisible * 5 + 5)
  return <section aria-label="Guardados por confirmar" className="space-y-2 rounded-xl border border-amber-300/70 p-3">
    <h3 className="text-sm font-semibold">Guardados por confirmar</h3>
    {pendientes.length > 0 && <p className="text-xs text-muted-foreground">Comprueba el resultado del envío original antes de registrar otro cambio.</p>}
    {visibles.map((pendiente, indice) => <div key={pendiente.operacion} className="flex flex-wrap items-center justify-between gap-2 text-xs">
      <p>{NOMBRES[pendiente.comando] ?? 'Gestión'} · Operación {paginaVisible * 5 + indice + 1}</p>
      <Button size="xs" variant="outline" disabled={pendiente.enCurso || ocupado !== null} onClick={() => void verificar(pendiente.operacion)}>
        {pendiente.enCurso || ocupado === pendiente.operacion ? 'Confirmando…' : 'Verificar guardado'}
      </Button>
    </div>)}
    {pendientes.length > 5 && <nav aria-label="Paginación de guardados por confirmar" className="flex flex-wrap items-center justify-between gap-2 text-xs">
      <Button size="xs" variant="outline" disabled={paginaVisible === 0} onClick={() => setPagina(paginaVisible - 1)}>Anteriores</Button>
      <span>Página {paginaVisible + 1} de {ultimaPagina + 1} · {pendientes.length} guardados</span>
      <Button size="xs" variant="outline" disabled={paginaVisible === ultimaPagina} onClick={() => setPagina(paginaVisible + 1)}>Siguientes</Button>
    </nav>}
    {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    {mensaje && <p role="status" className="text-xs">{mensaje}</p>}
  </section>
}
