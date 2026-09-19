import { useEffect, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import type { Lead } from '@/lib/tipos'
import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, validarDocumento, type TipoDocumento } from '@/lib/documento'
import { limpiarIntentosInversion } from '@/lib/inversion-solicitud'
import { mensajeDeError, type CondicionesTasaLead } from '@/data/crm-api'
import { prepararPersonaLeadInversion, obtenerContextoConversionInversion } from '@/data/inversion-solicitud-api'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { InversionNueva } from './inversion-nueva'

/** Adaptación de identidad; los campos y el guardado de la inversión pertenecen
 * exclusivamente a InversionNueva, igual que al entrar desde Cartera. */
export function InversionDesdeLead({l, condicionesTasa, onClose}: {
  l: Lead; condicionesTasa?: CondicionesTasaLead | undefined; onClose: () => void
}) {
  const {yo} = useAuth()
  const {recargar} = useCRMData()
  const [tipo, setTipo] = useState<TipoDocumento>('DNI')
  const [documento, setDocumento] = useState(l.dni ?? '')
  const [nombre, setNombre] = useState(l.nombre_completo)
  const [preparada, setPersona] = useState<Awaited<ReturnType<typeof prepararPersonaLeadInversion>> | null>(null)
  const confirmada = useQuery({queryKey: ['crm','conversion-confirmada',yo?.id,l.id],
    queryFn: ({signal}) => obtenerContextoConversionInversion(l.id, undefined, signal),
    enabled: l.etapa === 'convertido', retry: false, staleTime: 0, gcTime: 0})
  const persona = preparada ?? (confirmada.data?.solicitud_id ? {
    inversionista_id: confirmada.data.persona.inversionista_id, solicitud_id: confirmada.data.solicitud_id,
  } : null)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const enviando = useRef(false)
  const montado = useRef(true)
  useEffect(() => {montado.current = true; return () => {montado.current = false}}, [])
  if (!yo) return null
  if (persona) return <InversionNueva key={`${yo.id}:${l.id}:${persona.inversionista_id}`} actor={yo.id}
    persona={persona.inversionista_id} origenLead={{id: l.id, solicitudId: persona.solicitud_id, condiciones: condicionesTasa,
      monto: l.monto_estimado ?? null, moneda: l.moneda, tipoDocumento: confirmada.data?.documento_tipo ?? tipo}}
    onCerrar={onClose} onConfirmada={() => {void recargar()}}
    onRevocado={() => {limpiarIntentosInversion(yo.id, persona.inversionista_id, l.id); onClose()}} />
  const cerrar = () => {if (!enviando.current) onClose()}
  if (l.etapa === 'convertido') return <Dialog open onClose={cerrar} ariaLabel="Inversión del lead">
    <DialogHeader><DialogTitle>Inversión del lead</DialogTitle></DialogHeader>
    <DialogBody>{confirmada.isError ? <PanelError mensaje={mensajeDeError(confirmada.error, 'No se pudo consultar la inversión.')}
      onReintentar={() => void confirmada.refetch()} reintentando={confirmada.isFetching} /> : confirmada.isPending ? <PanelCargando />
      : <p>Esta conversión se registró con el flujo anterior. Consulta su inversión en Cartera.</p>}</DialogBody>
    <DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter>
  </Dialog>
  return <Dialog open onClose={cerrar} ariaLabel="Convertir a cliente">
    <DialogHeader><DialogTitle>Registrar la inversión del lead</DialogTitle></DialogHeader>
    <form onSubmit={e => {
      e.preventDefault()
      if (enviando.current) return
      const doc = validarDocumento(tipo, documento)
      if (!doc.ok) {setError(doc.error); return}
      if (nombre.trim().length < 2) {setError('Completa el nombre de la persona.'); return}
      enviando.current = true; setOcupado(true); setError(null)
      void prepararPersonaLeadInversion(l.id, tipo, doc.valor, nombre.trim()).then(r => {
        if (r.lead_id !== l.id) throw new Error('No se pudo verificar el lead de esta inversión.')
        if (montado.current) setPersona(r)
      }).catch(e => {if (montado.current) setError(mensajeDeError(e, 'No se pudo verificar la identidad.'))})
        .finally(() => {enviando.current = false; if (montado.current) setOcupado(false)})
    }}>
      <DialogBody className="space-y-4">
        <p className="text-sm text-muted-foreground">Confirma la identidad para abrir Nueva inversión. El lead se convertirá en cliente al confirmar su inversión.</p>
        <div className="space-y-1"><Label htmlFor="conversion-nombre">Nombre completo</Label>
          <Input id="conversion-nombre" required maxLength={180} value={nombre} disabled={ocupado} onChange={e => setNombre(e.target.value)} /></div>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1"><Label htmlFor="conversion-tipo">Tipo de documento</Label>
            <Select id="conversion-tipo" value={tipo} disabled={ocupado} onChange={e => setTipo(e.target.value as TipoDocumento)}>
              {TIPOS_DOCUMENTO_K.map(k => <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>)}
            </Select></div>
          <div className="space-y-1"><Label htmlFor="conversion-documento">Documento</Label>
            <Input id="conversion-documento" required maxLength={12} inputMode={TIPOS_DOCUMENTO[tipo].inputmode}
              value={documento} disabled={ocupado} onChange={e => setDocumento(e.target.value)} /></div>
        </div>
        {error && <p role="alert" className="text-sm text-destructive-text">{error}</p>}
      </DialogBody>
      <DialogFooter><Button type="button" variant="outline" onClick={cerrar} disabled={ocupado}>Cancelar</Button>
        <Button type="submit" disabled={ocupado}>{ocupado ? 'Verificando…' : 'Continuar a Nueva inversión'}</Button></DialogFooter>
    </form>
  </Dialog>
}
