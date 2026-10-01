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
import { guardarConversionAbierta, leerConversionAbierta, limpiarConversionAbierta, limpiarIntentosInversion } from '@/lib/inversion-solicitud'
import { mensajeDeError, type CondicionesTasaLead } from '@/data/crm-api'
import { prepararPersonaLeadInversion, obtenerContextoConversionInversion } from '@/data/inversion-solicitud-api'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { InversionNueva } from './inversion-nueva'
import { useDocumentoLead, type DocumentoLead } from '@/data/documento-lead'

type Propiedades = { l: Lead; condicionesTasa?: CondicionesTasaLead | undefined; onClose: () => void }

export function InversionDesdeLead(props: Propiedades) {
  // El documento solo PRECARGA la identidad y se FIJA: con la primera respuesta
  // posterior a abrir o, antes, en cuanto hay persona. Preparar la identidad escribe
  // en el lead: al volver a la ventana la cartera se resincroniza, la consulta
  // cambia de clave (o de resultado) y, si de ella dependiera qué se pinta, el
  // wizard se desmontaría con todo lo ya escrito.
  const {yo} = useAuth()
  const [fijado, setFijado] = useState<DocumentoLead | null>(null)
  const documento = useDocumentoLead(props.l, fijado === null)
  const reciente = documento.isFetchedAfterMount && !documento.isError ? documento.data ?? null : null
  if (fijado === null && reciente) setFijado(reciente)
  // Hasta fijarlo vale la copia que la ficha ya tenía (el formulario abre sin
  // esperar) y la `key` deja que la respuesta del servidor la corrija esa vez;
  // por eso la identidad no se puede enviar todavía: no hay envío que desmontar.
  const inicial = fijado ?? (documento.isPending || documento.isError ? null : documento.data ?? null)
  // Cerrar a mano mientras carga también es cerrar: una retoma pendiente no se reabre sola.
  const cerrar = () => {if (yo) limpiarConversionAbierta(yo.id, props.l.id); props.onClose()}
  if (!inicial) return <Dialog open onClose={cerrar} ariaLabel="Convertir a cliente">
    <DialogHeader><DialogTitle>Documento del lead</DialogTitle></DialogHeader>
    <DialogBody>{documento.isError
      ? <div role="alert"><PanelError mensaje="No se pudo consultar el documento vinculado. Vuelve a intentarlo." onReintentar={() => void documento.refetch()} reintentando={documento.isFetching} /></div>
      : <><p role="status" className="sr-only">Consultando el documento del lead…</p><PanelCargando /></>}</DialogBody>
    <DialogFooter><Button variant="outline" onClick={cerrar}>Volver a la ficha</Button></DialogFooter>
  </Dialog>
  return <FormularioInversionDesdeLead key={`${inicial.tipo}:${inicial.numero}`} {...props} documentoInicial={inicial}
    documentoFijado={fijado !== null} alTenerPersona={() => setFijado(actual => actual ?? inicial)} />
}

/** Adaptación de identidad; los campos y el guardado de la inversión pertenecen
 * exclusivamente a InversionNueva, igual que al entrar desde Cartera. */
function FormularioInversionDesdeLead({l, condicionesTasa, onClose, documentoInicial, documentoFijado, alTenerPersona}: Propiedades & {
  documentoInicial: DocumentoLead; documentoFijado: boolean; alTenerPersona: () => void
}) {
  const {yo} = useAuth()
  const {recargar} = useCRMData()
  const [tipo, setTipo] = useState<TipoDocumento>(documentoInicial.tipo)
  const [documento, setDocumento] = useState(documentoInicial.numero ?? '')
  const reconocido = documentoInicial.inversionista_id !== null
  const [nombre, setNombre] = useState(l.nombre_completo)
  // Tras recargar la página con el wizard abierto se retoma sin volver a pedir la
  // identidad: InversionNueva la comprueba en el servidor al montarse y recupera
  // su solicitud del intento guardado, no de aquí.
  const [preparada, setPersona] = useState<{inversionista_id: string; solicitud_id: string | null} | null>(() => {
    const retomada = yo ? leerConversionAbierta(yo.id, l.id) : null
    return retomada ? {inversionista_id: retomada, solicitud_id: null} : null
  })
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
  // Con persona (recién preparada, retomada o ya confirmada) el wizard está abierto:
  // desde aquí ninguna respuesta tardía del documento puede remontarlo.
  const hayPersona = persona !== null
  const fijarDocumento = useRef(alTenerPersona)
  fijarDocumento.current = alTenerPersona
  useEffect(() => {if (hayPersona) fijarDocumento.current()}, [hayPersona])
  if (!yo) return null
  if (persona) return <InversionNueva key={`${yo.id}:${l.id}:${persona.inversionista_id}`} actor={yo.id}
    persona={persona.inversionista_id} origenLead={{id: l.id, solicitudId: persona.solicitud_id, condiciones: condicionesTasa,
      monto: l.monto_estimado ?? null, moneda: l.moneda, tipoDocumento: confirmada.data?.documento_tipo ?? tipo}}
    onCerrar={() => {limpiarConversionAbierta(yo.id, l.id); onClose()}}
    onConfirmada={() => {limpiarConversionAbierta(yo.id, l.id); void recargar()}}
    onRevocado={() => {limpiarConversionAbierta(yo.id, l.id); limpiarIntentosInversion(yo.id, persona.inversionista_id, l.id); onClose()}} />
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
      if (enviando.current || !documentoFijado) return
      const doc = validarDocumento(tipo, documento)
      if (!doc.ok) {setError(doc.error); return}
      if (nombre.trim().length < 2) {setError('Completa el nombre de la persona.'); return}
      enviando.current = true; setOcupado(true); setError(null)
      void prepararPersonaLeadInversion(l.id, tipo, doc.valor, nombre.trim()).then(r => {
        if (r.lead_id !== l.id) throw new Error('No se pudo verificar el lead de esta inversión.')
        if (montado.current) {guardarConversionAbierta(yo.id, l.id, r.inversionista_id); setPersona(r)}
      }).catch(e => {if (montado.current) setError(mensajeDeError(e, 'No se pudo verificar la identidad.'))})
        .finally(() => {enviando.current = false; if (montado.current) setOcupado(false)})
    }}>
      <DialogBody className="space-y-4">
        <p className="text-sm text-muted-foreground">Confirma la identidad para abrir Nueva inversión. El lead se convertirá en cliente al confirmar su inversión.</p>
        <div className="space-y-1"><Label htmlFor="conversion-nombre">Nombre completo</Label>
          <Input id="conversion-nombre" required maxLength={180} value={nombre} disabled={ocupado} onChange={e => setNombre(e.target.value)} /></div>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1"><Label htmlFor="conversion-tipo">Tipo de documento</Label>
            <Select id="conversion-tipo" value={tipo} disabled={ocupado || reconocido} onChange={e => setTipo(e.target.value as TipoDocumento)}>
              {TIPOS_DOCUMENTO_K.map(k => <option key={k} value={k}>{TIPOS_DOCUMENTO[k].etiqueta}</option>)}
            </Select></div>
          <div className="space-y-1"><Label htmlFor="conversion-documento">Documento</Label>
            <Input id="conversion-documento" required inputMode={TIPOS_DOCUMENTO[tipo].inputmode}
              value={documento} disabled={ocupado || reconocido} onChange={e => setDocumento(e.target.value)} /></div>
        </div>
        {reconocido && <p className="text-xs text-muted-foreground">Este documento ya está vinculado al lead. Para corregirlo, Administración debe usar «Editar» en su ficha antes de continuar.</p>}
        {error && <p role="alert" className="text-sm text-destructive-text">{error}</p>}
      </DialogBody>
      <DialogFooter><Button type="button" variant="outline" onClick={cerrar} disabled={ocupado}>Cancelar</Button>
        {!documentoFijado && <span id="conversion-comprobando" role="status" className="sr-only">Comprobando el documento con el servidor…</span>}
        <Button type="submit" disabled={ocupado || !documentoFijado} aria-describedby={documentoFijado ? undefined : 'conversion-comprobando'}>
          {ocupado ? 'Verificando…' : 'Continuar a Nueva inversión'}</Button></DialogFooter>
    </form>
  </Dialog>
}
