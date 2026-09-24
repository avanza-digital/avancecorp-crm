import { useEffect, useRef, useState, type FormEvent, type RefObject } from 'react'
import { Search, UserCheck } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import {
  buscarClienteExistente, type BusquedaCliente, type CriterioBusqueda, type TipoDocumentoBusqueda,
} from '@/data/cliente-existente-api'
import { mensajeDeError } from '@/data/crm-api'
import { abrirInversionista } from '@/lib/router'
import { EMPRESA_NOMBRE, type EmpresaInversion } from '@/lib/inversionistas'
import { InversionNueva } from './inversion-nueva'

// Venta cruzada: buscar a un cliente por su documento o su teléfono (o desde un lead) y,
// si es de otra cartera, registrar su inversión nueva o su upgrade a nombre de quien vende.
// El responsable no cambia. Cada búsqueda queda registrada en el servidor.

const TIPOS_DOCUMENTO: {valor: TipoDocumentoBusqueda; etiqueta: string}[] = [
  {valor: 'DNI', etiqueta: 'DNI'}, {valor: 'CE', etiqueta: 'Carné de extranjería'}, {valor: 'PASAPORTE', etiqueta: 'Pasaporte'},
]
const TEXTO_ESTADO: Record<'no_encontrado' | 'ambiguo' | 'conflicto' | 'limite' | 'invalido', string> = {
  no_encontrado: 'No encontramos a un cliente con ese dato. Si es una persona nueva, regístrala como lead.',
  ambiguo: 'Ese teléfono lo comparten varios clientes. Búscalo por su documento.',
  conflicto: 'Los datos de este lead apuntan a personas distintas. Pide a Gerencia que revise su identidad.',
  limite: 'Hiciste muchas búsquedas en la última hora. Espera un momento antes de volver a buscar.',
  invalido: 'Revisa el dato: no tiene un formato válido de documento o de teléfono.',
}
const nombreEmpresa = (clave: string) => EMPRESA_NOMBRE[clave as EmpresaInversion] ?? clave

export function VentaCruzada({actor, inicial, resultadoInicial, documentoSugerido, puedeRegistrar, focoAlCerrar, onCerrar, onConfirmada}: {
  actor: string
  /** Búsqueda con la que abre (por ejemplo, lo escrito en el buscador de la Cartera). */
  inicial?: CriterioBusqueda | undefined
  /** Resultado ya obtenido (por ejemplo, el lead descartado que resultó ser cliente). */
  resultadoInicial?: BusquedaCliente | undefined
  /** Documento que se propone al «Buscar por documento» (el DNI del lead, si lo tiene). */
  documentoSugerido?: {tipo: TipoDocumentoBusqueda; numero: string} | undefined
  /** Vendedor o supervisor: registran la venta. Gerencia solo consulta. */
  puedeRegistrar: boolean
  /** A dónde vuelve el foco al cerrar cuando quien la abrió ya no existe (el banner del lead). */
  focoAlCerrar?: RefObject<HTMLElement | null> | undefined
  onCerrar: () => void
  onConfirmada?: (() => void) | undefined
}) {
  const [modo, setModo] = useState<'documento' | 'telefono'>(inicial?.tipo === 'telefono' ? 'telefono' : 'documento')
  const [tipoDocumento, setTipoDocumento] = useState<TipoDocumentoBusqueda>(inicial?.tipo === 'documento' ? inicial.tipoDocumento : 'DNI')
  const [numero, setNumero] = useState(inicial?.tipo === 'documento' ? inicial.numero : '')
  const [telefono, setTelefono] = useState(inicial?.tipo === 'telefono' ? inicial.telefono : '')
  const [resultado, setResultado] = useState<BusquedaCliente | null>(resultadoInicial ?? null)
  const [buscando, setBuscando] = useState(false)
  const [error, setError] = useState<{texto: string; campo: 'numero' | 'telefono' | null} | null>(null)
  const [nueva, setNueva] = useState<{busquedaId: string; persona: string} | null>(null)
  const confirmada = useRef(false)
  const enCurso = useRef(false)
  const numeroRef = useRef<HTMLInputElement>(null)
  const telefonoRef = useRef<HTMLInputElement>(null)
  const accionRef = useRef<HTMLButtonElement>(null)

  async function buscar(criterio: CriterioBusqueda) {
    if (enCurso.current) return
    // Se vacía antes de buscar: dos veredictos iguales seguidos también se anuncian.
    enCurso.current = true; setBuscando(true); setError(null); setResultado(null)
    try {setResultado(await buscarClienteExistente(criterio))}
    catch (e) {setError({texto: mensajeDeError(e, 'No se pudo buscar al cliente. Reintenta.'), campo: null})}
    finally {enCurso.current = false; setBuscando(false)}
  }
  // Abrir con un criterio (un lead, un documento ya escrito) busca al instante, una sola vez.
  const buscado = useRef(false)
  useEffect(() => {
    if (inicial && !resultadoInicial && !buscado.current) {buscado.current = true; void buscar(inicial)}
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const enviar = (e: FormEvent) => {
    e.preventDefault()
    // El diálogo vive en un portal, pero React propaga el submit por SU árbol: sin esto, el
    // formulario que lo contiene (el alta de un lead) también se enviaría.
    e.stopPropagation()
    if (modo === 'documento') {
      if (!numero.trim()) {setError({texto: 'Escribe el número de documento.', campo: 'numero'}); numeroRef.current?.focus(); return}
      void buscar({tipo: 'documento', tipoDocumento, numero: numero.trim()})
    } else {
      if (!telefono.trim()) {setError({texto: 'Escribe el teléfono.', campo: 'telefono'}); telefonoRef.current?.focus(); return}
      void buscar({tipo: 'telefono', telefono: telefono.trim()})
    }
  }
  // La búsqueda venció (2 h) o cambió el acceso mientras se registraba: se vuelve a buscar.
  const revocada = () => {
    setNueva(null); setResultado(null); setModo('documento')
    setError({texto: 'La búsqueda venció o cambió tu acceso. Vuelve a buscarlo por su documento.', campo: null})
    // Un fotograma más: el diálogo que se cierra devuelve antes el foco a su origen (que ya no existe).
    requestAnimationFrame(() => requestAnimationFrame(() => numeroRef.current?.focus()))
  }
  const errorDe = (campo: 'numero' | 'telefono') => error?.campo === campo
  const pedirDocumento = (tipo: TipoDocumentoBusqueda | null) => {
    const sugerido = documentoSugerido && (!tipo || documentoSugerido.tipo === tipo) ? documentoSugerido : null
    setModo('documento'); setTipoDocumento(sugerido?.tipo ?? tipo ?? 'DNI'); setNumero(sugerido?.numero ?? ''); setResultado(null)
    requestAnimationFrame(() => numeroRef.current?.focus())
  }

  // El foco empieza en lo que se va a usar: la acción de la tarjeta que ya llega hecha, o el campo.
  const focoInicial = resultadoInicial ? accionRef : modo === 'telefono' ? telefonoRef : numeroRef
  return <><Dialog open onClose={onCerrar} ariaLabel="Cliente de otra cartera" className="w-[620px]"
    focoAlCerrar={focoAlCerrar} focoInicial={focoInicial}>
    <DialogHeader><DialogTitle>Cliente de otra cartera</DialogTitle>
      <p className="text-sm text-muted-foreground">Búscalo por su documento para registrar su inversión. La venta queda a tu nombre y su responsable no cambia.</p>
    </DialogHeader>
    <DialogBody className="space-y-4">
      <form onSubmit={enviar} className="space-y-3" noValidate>
        <fieldset className="flex flex-wrap gap-2"><legend className="sr-only">Buscar por</legend>
          <Button type="button" size="sm" variant={modo === 'documento' ? 'default' : 'outline'} aria-pressed={modo === 'documento'}
            onClick={() => {setModo('documento'); setError(null)}}>Documento</Button>
          <Button type="button" size="sm" variant={modo === 'telefono' ? 'default' : 'outline'} aria-pressed={modo === 'telefono'}
            onClick={() => {setModo('telefono'); setError(null)}}>Teléfono</Button>
        </fieldset>
        {modo === 'documento' ? <div className="grid gap-3 sm:grid-cols-[180px_1fr]">
          <div className="space-y-1"><Label htmlFor="vc-tipo-documento">Tipo de documento</Label>
            <Select id="vc-tipo-documento" value={tipoDocumento} onChange={e => setTipoDocumento(e.target.value as TipoDocumentoBusqueda)}>
              {TIPOS_DOCUMENTO.map(t => <option key={t.valor} value={t.valor}>{t.etiqueta}</option>)}</Select></div>
          <div className="space-y-1"><Label htmlFor="vc-numero">Número</Label>
            <Input id="vc-numero" ref={numeroRef} value={numero} onChange={e => {setNumero(e.target.value); setError(null)}}
              inputMode={tipoDocumento === 'PASAPORTE' ? 'text' : 'numeric'} autoComplete="off" maxLength={20}
              aria-invalid={errorDe('numero') || undefined} aria-describedby={errorDe('numero') ? 'vc-error' : undefined} /></div>
        </div> : <div className="space-y-1"><Label htmlFor="vc-telefono">Teléfono</Label>
          <Input id="vc-telefono" ref={telefonoRef} type="tel" inputMode="tel" value={telefono} onChange={e => {setTelefono(e.target.value); setError(null)}}
            autoComplete="off" maxLength={20} aria-invalid={errorDe('telefono') || undefined}
            aria-describedby={errorDe('telefono') ? 'vc-telefono-ayuda vc-error' : 'vc-telefono-ayuda'} />
          <p id="vc-telefono-ayuda" className="text-sm text-muted-foreground">Por teléfono solo ves las iniciales; para registrar la inversión, búscalo después por su documento.</p></div>}
        {/* Sin `disabled` mientras busca: el control con el foco no debe desaparecer del orden de tabulación. */}
        <Button type="submit" aria-disabled={buscando || undefined}><Search aria-hidden />{buscando ? 'Buscando…' : 'Buscar'}</Button>
      </form>
      {error && <p id="vc-error" role="alert" className="rounded-xl border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive-text [overflow-wrap:anywhere]">{error.texto}</p>}
      <div aria-live="polite">{resultado && <ResultadoBusqueda resultado={resultado} puedeRegistrar={puedeRegistrar}
        refAccion={accionRef}
        onVerCliente={id => {abrirInversionista(id); onCerrar()}}
        onNuevaInversion={(busquedaId, persona) => setNueva({busquedaId, persona})}
        onPedirDocumento={pedirDocumento} />}</div>
    </DialogBody>
    <DialogFooter><Button variant="outline" onClick={onCerrar}>Cerrar</Button></DialogFooter>
  </Dialog>
  {/* Encima de la búsqueda, no en su lugar: al cerrarla sin confirmar, el foco vuelve a
      «Nueva inversión»; confirmada, se cierra todo. */}
  {nueva && <InversionNueva key={nueva.busquedaId} actor={actor} persona={nueva.persona}
    origenClienteExistente={{busquedaId: nueva.busquedaId}}
    onCerrar={() => {if (confirmada.current) onCerrar(); else setNueva(null)}}
    onRevocado={revocada}
    onConfirmada={() => {confirmada.current = true; onConfirmada?.()}} />}
  </>
}

/** La tarjeta «Esta persona ya es cliente», con lo mínimo que devuelve el servidor. */
export function ResultadoBusqueda({resultado, puedeRegistrar, refAccion, onVerCliente, onNuevaInversion, onPedirDocumento}: {
  resultado: BusquedaCliente; puedeRegistrar: boolean
  /** La acción principal de la tarjeta (la primera que se muestra), para darle el foco. */
  refAccion?: RefObject<HTMLButtonElement | null> | undefined
  onVerCliente: (inversionistaId: string) => void
  onNuevaInversion: (busquedaId: string, persona: string) => void
  onPedirDocumento: (tipo: TipoDocumentoBusqueda | null) => void
}) {
  if (resultado.estado !== 'encontrado' && resultado.estado !== 'no_operable') {
    return <p className="rounded-xl border border-border bg-muted/30 p-3 text-sm">{TEXTO_ESTADO[resultado.estado]}</p>
  }
  const {acciones} = resultado
  // Un motivo reservado no nombra a la persona: solo se dice por qué hoy no se puede.
  if (!('nombre' in resultado.cliente)) {
    return <p className="rounded-xl border border-border bg-muted/30 p-3 text-sm">{acciones.motivo_no_operable ?? 'Hoy no se puede registrar una inversión para esta persona.'}</p>
  }
  const c = resultado.cliente
  const verFicha = acciones.ver_ficha && c.inversionista_id
  const nuevaInversion = acciones.nueva_inversion && puedeRegistrar && c.inversionista_id
  const porDocumento = acciones.requiere_documento && puedeRegistrar
  return <section aria-labelledby="vc-cliente-titulo" className="space-y-3 rounded-xl border border-border p-4">
    <h3 id="vc-cliente-titulo" className="flex items-center gap-2 text-sm font-semibold"><UserCheck aria-hidden className="size-4" />
      {c.es_mi_cartera ? 'Este cliente es de tu cartera' : 'Esta persona ya es cliente'}</h3>
    <dl className="grid gap-2 text-sm sm:grid-cols-2 [overflow-wrap:anywhere]">
      <div className="sm:col-span-2"><dt className="text-muted-foreground">Cliente</dt><dd className="text-base font-semibold">{c.nombre ?? '—'}</dd></div>
      {c.documento_enmascarado && <div><dt className="text-muted-foreground">Documento</dt><dd>{c.documento_tipo} {c.documento_enmascarado}</dd></div>}
      <div><dt className="text-muted-foreground">Responsable</dt><dd>{c.responsable_nombre ?? 'Sin responsable'}</dd></div>
      {c.empresas.length > 0 && <div className="sm:col-span-2"><dt className="text-muted-foreground">Invierte en</dt>
        <dd className="mt-1 flex flex-wrap gap-1">{c.empresas.map(e => <Badge key={e} className="text-sm">{nombreEmpresa(e)}</Badge>)}</dd></div>}
    </dl>
    {resultado.estado === 'no_operable' && <p className="text-sm">{acciones.motivo_no_operable}</p>}
    {acciones.requiere_documento && <p className="text-sm">Para registrar su inversión, búscalo por su documento.</p>}
    <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
      {verFicha && <Button ref={refAccion} variant="outline" onClick={() => onVerCliente(c.inversionista_id!)}>Ver cliente</Button>}
      {nuevaInversion && <Button ref={verFicha ? undefined : refAccion}
        onClick={() => onNuevaInversion(resultado.busqueda_id, c.inversionista_id!)}>Nueva inversión</Button>}
      {porDocumento && <Button ref={verFicha || nuevaInversion ? undefined : refAccion} variant="outline"
        onClick={() => onPedirDocumento(c.documento_tipo)}>Buscar por documento</Button>}
    </div>
  </section>
}
