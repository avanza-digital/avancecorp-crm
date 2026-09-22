import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useAvisosCortes } from '@/data/gestion-diaria-seguimiento-queries'
import { presentarCorte } from '@/data/gestion-diaria-seguimiento-api'
import { CrmApiError } from '@/data/crm-api'
import { useAuth } from './auth-context'
import { GestionDiariaAvisosContext, puedeInterrumpirConCorte, type AvisosGestionDiaria } from './gestion-diaria-avisos-context'
import { tituloCorte, horaCorte, type AvisoCorte } from './gestion-diaria-avisos'
import { hashDe } from './router'
import { Dialog, DialogBody, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { AccionesCorte } from '@/components/gestion-diaria/acciones-corte'

export function GestionDiariaAvisosProvider({ children }: { children: ReactNode }) {
  const { yo } = useAuth()
  const { consulta, accion, datos, habilitada } = useAvisosCortes()
  const [popup, setPopup] = useState<AvisoCorte | null>(null)
  const [errorPresentacion, setErrorPresentacion] = useState<unknown>(null)
  const [registroPedido, setRegistroPedido] = useState<AvisosGestionDiaria['registroPedido']>(null)
  const solicitudes = useRef(new Map<string, string>())
  const procesadas = useRef(new Set<string>())
  // Una petición puede llegar al servidor mientras el usuario abre un editor.
  // Retener su clave permite recuperar esa misma entrega, aun si el siguiente
  // GET ya dice puede_presentar=false por haber quedado reservada aquí.
  const reserva = useRef<string | null>(null)
  const escribiendo = useRef(0)
  const ocupado = useRef(false)
  const llegada = useRef({ actualizado: 0, reloj: 0 })
  if (llegada.current.actualizado !== consulta.dataUpdatedAt) {
    llegada.current = { actualizado: consulta.dataUpdatedAt, reloj: performance.now() }
  }
  const ultimo = useRef({ datos, popup, habilitada, accion, consulta })
  ultimo.current = { datos, popup, habilitada, accion, consulta }
  const solicitud = useCallback((clave: string) => {
    const id = solicitudes.current.get(clave) ?? crypto.randomUUID()
    solicitudes.current.set(clave, id)
    return id
  }, [])
  const actuar = useCallback(async (aviso: AvisoCorte, tipo: 'reconocer' | 'posponer') => {
    if (ocupado.current) throw new CrmApiError('Espera a que termine la acción en curso.', 'ACCION_EN_CURSO')
    ocupado.current = true
    try {
      await accion.mutateAsync({ alertaId: aviso.id, accion: tipo, solicitudId: solicitud(`${tipo}:${aviso.id}`) })
    } finally { ocupado.current = false }
  }, [accion, solicitud])
  const abrirRegistro = useCallback((aviso: AvisoCorte, analista: string) => {
    if (!datos || !aviso.miembros.some((m) => m.analista_id === analista)) return
    setPopup(null)
    setRegistroPedido({ actor: datos.supervisor_id, dia: datos.dia, analista, secuencia: performance.now() })
    window.location.hash = hashDe('gestion-diaria')
  }, [datos])
  const consumirRegistro = useCallback(() => setRegistroPedido(null), [])
  const recargar = useCallback(() => {
    if (habilitada) void consulta.refetch().then((r) => { if (!r.error) setErrorPresentacion(null) })
  }, [consulta, habilitada])
  useEffect(() => {
    if (consulta.dataUpdatedAt && !consulta.error) setErrorPresentacion(null)
  }, [consulta.dataUpdatedAt, consulta.error])

  useEffect(() => {
    if (!habilitada) return
    let viva = true
    let enVuelo = false
    let reintentarDesde = 0
    const interaccion = () => { escribiendo.current = performance.now() }
    document.addEventListener('input', interaccion, true)
    document.addEventListener('keydown', interaccion, true)
    const intentar = async () => {
      const actual = ultimo.current
      const transcurrido = performance.now() - llegada.current.reloj
      const reloj = actual.datos ? Date.parse(actual.datos.generado_en) + transcurrido : null
      if (viva && actual.popup && (reloj === null || transcurrido > 90_000
        || reloj >= Date.parse(actual.popup.fin_jornada))) {
        setPopup(null)
        return
      }
      if (!viva || enVuelo || actual.popup || actual.accion.isPending || !actual.datos || !actual.habilitada
        || performance.now() < reintentarDesde || performance.now() - escribiendo.current < 1500
        || !puedeInterrumpirConCorte(document)) return
      if (transcurrido > 90_000 || reloj === null) return
      const aviso = actual.datos.alertas.find((a) => actual.datos!.avisos_habilitados && a.estado === 'pendiente'
        && (a.puede_presentar || reserva.current === `${a.id}:${a.entrega}`) && Date.parse(a.fin_jornada) > reloj
        && !procesadas.current.has(`${a.id}:${a.entrega}`))
      if (!aviso) return
      enVuelo = true
      const clave = `${aviso.id}:${aviso.entrega}`
      reserva.current = clave
      try {
        const confirmado = await presentarCorte(aviso.id, solicitud(`presentar:${clave}`))
        if (!viva) return
        if (!confirmado) { procesadas.current.add(clave); reserva.current = null }
        const respuesta = await ultimo.current.consulta.refetch()
        if (!viva || respuesta.error) return
        // Si se abrió un editor mientras viajaba la petición, conserva el UUID
        // para revalidar la misma entrega cuando el usuario termine.
        if (!puedeInterrumpirConCorte(document) || performance.now() - escribiendo.current < 1500) return
        const fresco = respuesta.data
        if (!fresco || fresco.supervisor_id !== actual.datos.supervisor_id || fresco.dia !== actual.datos.dia) return
        procesadas.current.add(clave)
        reserva.current = null
        setErrorPresentacion(null)
        const revalidado = fresco.alertas.find((a) => a.id === confirmado?.id && a.estado === 'pendiente')
        if (confirmado && revalidado && fresco.avisos_habilitados
          && Date.parse(fresco.generado_en) < Date.parse(revalidado.fin_jornada)) setPopup(revalidado)
      } catch (error) {
        if (viva) { setErrorPresentacion(error); reintentarDesde = performance.now() + 30_000 }
      } finally { enVuelo = false }
    }
    const temporizador = window.setInterval(() => { void intentar() }, 1000)
    return () => {
      viva = false
      window.clearInterval(temporizador)
      document.removeEventListener('input', interaccion, true)
      document.removeEventListener('keydown', interaccion, true)
    }
  }, [habilitada, yo?.id, solicitud])

  // Un refresco confirmado puede retirar miembros, reconocer desde otro equipo
  // o apagar el canal. Nunca mantiene a la vista una foto anterior revocada.
  const avisoActual = datos?.alertas.find((a) => a.id === popup?.id)
  const visible = popup && habilitada && datos?.avisos_habilitados && avisoActual?.estado === 'pendiente'
    ? avisoActual : null
  useEffect(() => { if (popup && !visible) setPopup(null) }, [popup, visible])
  const valor = useMemo<AvisosGestionDiaria>(() => ({ datos,
    cargando: habilitada && consulta.isPending, error: habilitada ? consulta.error : null,
    errorPresentacion: habilitada ? errorPresentacion : null,
    ocupada: accion.isPending, recargar, actuar, registroPedido, abrirRegistro, consumirRegistro,
  }), [datos, habilitada, consulta.isPending, consulta.error, errorPresentacion, accion.isPending,
    recargar, actuar, registroPedido, abrirRegistro, consumirRegistro])
  return <GestionDiariaAvisosContext.Provider value={valor}>
    {children}
    {visible && <Dialog open onClose={() => setPopup(null)} ariaLabel={tituloCorte(visible)} className="w-[720px]">
      <DialogHeader>
        <DialogTitle className="text-xl">{tituloCorte(visible)}</DialogTitle>
        <DialogDescription className="text-base">{datos!.dia} · Corte de las {horaCorte(visible.corte_en)}, Lima. {visible.miembros.length} analistas por revisar.</DialogDescription>
      </DialogHeader>
      <DialogBody className="space-y-4 text-base">
        <p>Estas personas quedaron por debajo del mínimo. Reconocer o posponer el aviso conserva el resultado del corte.</p>
        {datos?.contexto && <p>Han registrado llamadas {datos.contexto.con_llamadas} de {datos.contexto.analistas} analistas hoy. No se infiere asistencia ni feriados.</p>}
        <ul className="divide-y divide-border">{visible.miembros.map((m) => <li key={m.analista_id} className="flex flex-wrap items-center justify-between gap-3 py-3">
          <div><strong>{m.nombre}</strong><p>{m.llamadas} llamadas al corte · mínimo {m.objetivo}</p>
            {datos?.contexto && <p>{(() => {
              const primera = datos.contexto.equipo.find((e) => e.analista_id === m.analista_id)?.primera_llamada_en
              return primera ? `Primera llamada de hoy: ${horaCorte(primera)} Lima.` : 'Sin llamadas registradas hoy.'
            })()}</p>}</div>
          <Button variant="outline" className="h-auto min-h-11 max-w-full whitespace-normal text-base" onClick={() => abrirRegistro(visible, m.analista_id)}>Ver registro de {m.nombre}</Button>
        </li>)}</ul>
        <AccionesCorte aviso={visible} alConfirmar={() => setPopup(null)} />
        <p className="text-[var(--muted-foreground-strong)]">{visible.puede_posponer ? 'Puedes posponer una sola vez por una hora.' : 'Este aviso ya no admite aplazamiento.'} No habrá reaviso al terminar la jornada ni al día siguiente. La lista conserva el pendiente.</p>
      </DialogBody>
      <DialogFooter><Button variant="outline" className="min-h-11 text-base" onClick={() => setPopup(null)}>Cerrar sin reconocer</Button></DialogFooter>
    </Dialog>}
  </GestionDiariaAvisosContext.Provider>
}
