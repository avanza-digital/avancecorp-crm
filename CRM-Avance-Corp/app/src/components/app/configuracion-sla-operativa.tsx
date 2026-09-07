import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/lib/auth-context'
import { ETAPA_INFO } from '@/lib/tipos'
import { minutosLegibles } from '@/lib/sla-versionado'
import { fechaSla } from '@/lib/sla-operacion'
import { mensajeDeError } from '@/data/crm-api'
import { useCambiarModoSla, useConfiguracionSlaV2, usePublicarReglasSlaAprobadas } from '@/data/sla-operacion-queries'

const MOTIVOS_INICIALIZACION: Record<string, string> = {
  politica_futura: 'Hay una política programada. Revisa su vigencia antes de publicar las reglas operativas.',
  ya_publicadas: 'Las reglas ya están publicadas. Actualiza para comprobar su vigencia.',
  sin_permiso: 'Gerencia puede publicar las reglas operativas aprobadas.',
}

export function ConfiguracionSlaOperativa() {
  const { yo } = useAuth()
  const consulta = useConfiguracionSlaV2()
  const cambiar = useCambiarModoSla()
  const publicar = usePublicarReglasSlaAprobadas()
  const [errorCambio, setErrorCambio] = useState<string | null>(null)
  const [confirmacion, setConfirmacion] = useState<string | null>(null)
  if (yo?.demo) return null
  const data = consulta.error ? undefined : consulta.data
  const activo = data?.control.modo === 'activo'
  const inicializacion = data?.inicializacion_aprobada
  const reglas = data?.vigente.operacion ?? (inicializacion?.disponible ? inicializacion.config.etapas : null)
  async function cambiarModo() {
    if (!data || cambiar.isPending) return
    setErrorCambio(null); setConfirmacion(null)
    try {
      const resultado = await cambiar.mutateAsync({ revision: data.control.revision, modo: activo ? 'legado' : 'activo' })
      setConfirmacion(resultado.modo === 'activo' ? 'Seguimiento operativo activado.' : 'Vista y reglas operativas desactivadas. Se conserva el historial.')
    } catch (error) { setErrorCambio(mensajeDeError(error, 'No se confirmó el cambio de modo. Actualiza para comprobarlo.')) }
  }
  async function publicarAprobadas() {
    if (!data || publicar.isPending) return
    setErrorCambio(null); setConfirmacion(null)
    try {
      const resultado = await publicar.mutateAsync(data.expected_version)
      setConfirmacion(`Reglas aprobadas publicadas en la política v${resultado.expected_version}. Ya puedes activar el seguimiento operativo.`)
    } catch (error) { setErrorCambio(mensajeDeError(error, 'No se confirmó la publicación. Actualiza para comprobarla.')) }
  }
  return <Card><CardContent className="space-y-4 p-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 className="text-base font-bold">Seguimiento y compromisos</h2>
        {data && <p className="mt-1 text-xs text-muted-foreground">{activo ? 'Activo' : data.control.modo === 'observacion' ? 'En observación' : 'Desactivado'} · Política v{data.vigente.base.version}{data.control.primera_activacion_en ? ` · Primera activación: ${fechaSla(data.control.primera_activacion_en)}` : ''}</p>}</div>
      <Button variant="outline" size="sm" disabled={consulta.isFetching || cambiar.isPending || publicar.isPending} onClick={() => void consulta.refetch()}>Actualizar reglas</Button>
    </div>
    {consulta.error ? <p role="alert" className="text-sm text-destructive">No se pudo confirmar la configuración del seguimiento.</p>
      : !data ? <p role="status" className="text-sm">Consultando reglas de seguimiento…</p>
      : <>
        {!data.vigente.operacion && inicializacion?.disponible && <div className="space-y-1 text-sm">
          <p className="font-semibold">Reglas aprobadas listas para publicar</p>
          <p className="text-xs text-muted-foreground">Primera gestión: {minutosLegibles(inicializacion.config.primera_gestion_minutos)} · Primer contacto: {minutosLegibles(inicializacion.config.primer_contacto_minutos)}. Estos plazos actuales se conservan al publicar.</p>
        </div>}
        {reglas ? <div className="grid gap-3 md:grid-cols-2">
          {reglas.map((regla) => <section key={regla.etapa} className="space-y-2 rounded-lg border p-3">
            <h3 className="text-sm font-bold">{ETAPA_INFO[regla.etapa].label}</h3>
            <dl className="space-y-1 text-xs">
              {'maximo_minutos' in regla && typeof regla.maximo_minutos === 'number' && <div className="flex justify-between gap-2"><dt>Plazo base de etapa</dt><dd>{minutosLegibles(regla.maximo_minutos)}</dd></div>}
              <div className="flex justify-between gap-2"><dt>Seguimiento cada</dt><dd>{minutosLegibles(regla.seguimiento_minutos)}</dd></div>
              <div className="flex justify-between gap-2"><dt>Margen del compromiso</dt><dd>{regla.pausa_habilitada ? minutosLegibles(regla.pausa_margen_minutos) : 'Sin cobertura'}</dd></div>
              <div className="flex justify-between gap-2"><dt>Prórrogas por conversación</dt><dd>{regla.prorroga_max ? `${regla.prorroga_max} de ${minutosLegibles(regla.prorroga_minutos)}` : 'No aplican'}</dd></div>
              <div className="flex justify-between gap-2"><dt>Máximo adicional al plazo base</dt><dd>{minutosLegibles(regla.tope_extra_minutos)}</dd></div>
            </dl>
          </section>)}
        </div> : <p className="text-sm">{MOTIVOS_INICIALIZACION[inicializacion?.motivo ?? ''] ?? 'La política vigente todavía no tiene reglas de seguimiento publicadas.'}</p>}
        <p className="text-xs text-muted-foreground">La revisión comercial pide una decisión a Supervisor o Gerencia. No descarta ni reasigna automáticamente. Los episodios anteriores conservan su plazo original.</p>
        {data.puede_editar && <div className="flex flex-wrap items-center gap-3 border-t pt-3">
          {!data.vigente.operacion && inicializacion?.disponible && <Button size="sm" disabled={publicar.isPending || cambiar.isPending} onClick={() => void publicarAprobadas()}>
            {publicar.isPending ? 'Publicando…' : 'Publicar reglas aprobadas'}
          </Button>}
          <Button size="sm" variant={activo ? 'outline' : 'default'} disabled={cambiar.isPending || publicar.isPending || (!activo && !data.vigente.operacion)} onClick={() => void cambiarModo()}>
            {cambiar.isPending ? 'Confirmando…' : activo ? 'Desactivar seguimiento operativo' : 'Activar seguimiento operativo'}
          </Button>
          <p className="text-xs text-muted-foreground">El cambio aplica a todo el equipo y conserva el historial.</p>
        </div>}
      </>}
    {errorCambio && <p role="alert" className="text-sm text-destructive">{errorCambio}</p>}
    {confirmacion && <p role="status" className="text-sm">{confirmacion}</p>}
  </CardContent></Card>
}
