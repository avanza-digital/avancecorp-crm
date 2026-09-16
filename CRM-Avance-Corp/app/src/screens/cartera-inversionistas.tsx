import { abrirInversionista, escribirHash, leerHash } from '@/lib/router'
import { VencimientosPostventa } from '@/components/app/postventa-vencimientos'
import { postventaKeys } from '@/data/postventa-queries'
import { useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Users2, RefreshCw, ChevronDown } from 'lucide-react'
import { toast } from 'sonner'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { Sheet } from '@/components/ui/sheet'
import { Dialog } from '@/components/ui/dialog'
import { ClienteForm } from '@/components/app/cliente-form'
import { refrescarGestionInversionista } from '@/data/gestion-inversionista'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { InversionistaFicha, ResumenEmpresas } from '@/components/app/inversionista-ficha'
import { InversionNueva, type OperacionInversion } from '@/components/app/inversion-nueva'
import { FiltrosCarteraInversionistas } from '@/components/app/cartera-inversionistas-filtros'
import { fechaLima } from '@/lib/agenda-derivada'
import { fmtFecha, money } from '@/lib/format'
import { EMPRESA_NOMBRE, FILTROS_INVERSIONISTAS_INICIALES, type CarteraInversionistas as DatosCartera, type FiltrosInversionistas, type InversionFuente } from '@/lib/inversionistas'
import { limpiarIntentosInversion, leerIntentoInversion } from '@/lib/inversion-solicitud'
import { inversionistasKeys, useInversionistas } from '@/data/inversionistas-queries'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { descargarDocumentoInversionista } from '@/data/inversionistas-api'
import { archivarContratoPdfConfirmado, ContratoEliminacionError, eliminarContratoConPdf } from '@/lib/contrato-pdf-archivo'
import { useAuth } from '@/lib/auth-context'
import { can, puedeEliminarContratos } from '@/lib/roles'
import { crmQueryKeys } from '@/data/crm-queries'

export function CarteraInversionistas({actor, permiteInversion}: {
  actor: string; permiteInversion: boolean
}) {
  const {yo} = useAuth()
  const permiteEliminar = yo?.id === actor && !yo.demo && puedeEliminarContratos(yo)
  const qc = useQueryClient()
  const [alta, setAlta] = useState(false)
  const altaEnCurso = useRef(false)
  const puedeAlta = yo?.id===actor && !yo.demo && permiteInversion && can(yo.rol,'altaDirectaCliente') && yo.puede_contratar
  const [filtros, setFiltros] = useState<FiltrosInversionistas>(() => ({...FILTROS_INVERSIONISTAS_INICIALES, mes:fechaLima(Date.now()).slice(0,7)}))
  const [busqueda, setBusqueda] = useState('')
  const [resumenAbierto, setResumenAbierto] = useState(false)
  const [seleccion, setSeleccion] = useState<string | null>(() => leerHash().inversionistaId ?? null)
  const [volverAInversiones, setVolverAInversiones] = useState(false)
  useEffect(() => {
    const cambiar = () => {setVolverAInversiones(false); setSeleccion(leerHash().inversionistaId ?? null)}
    window.addEventListener('hashchange', cambiar)
    return () => window.removeEventListener('hashchange', cambiar)
  }, [])
  const seleccionar = (id: string | null) => {
    setVolverAInversiones(false)
    setSeleccion(id)
    if (id) abrirInversionista(id)
    else escribirHash('mi-cartera')
  }
  const [nueva, setNueva] = useState<{persona: string; operacion?: OperacionInversion} | null>(null)
  const [aviso, setAviso] = useState('')
  const [descargando, setDescargando] = useState(false)
  const documento = useRef<AbortController | null>(null)
  const titulo = useRef<HTMLHeadingElement>(null)
  const q = useInversionistas(actor, filtros)
  const claveLista = JSON.stringify([actor, filtros])
  const [listaConfirmada, setListaConfirmada] = useState<{actor: string; clave: string; datos: DatosCartera} | null>(null)
  useEffect(() => {
    if (q.isFetchedAfterMount && q.isSuccess) setListaConfirmada({actor, clave: claveLista, datos: q.data})
  }, [actor, claveLista, q.data, q.isFetchedAfterMount, q.isSuccess])
  const accesoRevocado = q.error instanceof CrmApiError && q.error.code === '42501'
  useEffect(() => {if (accesoRevocado) setListaConfirmada(null)}, [accesoRevocado])
  const datos = accesoRevocado ? null : q.isFetchedAfterMount && q.isSuccess ? q.data
    : q.isError && listaConfirmada?.clave === claveLista ? listaConfirmada.datos : null
  const catalogo = accesoRevocado ? null : datos ?? (listaConfirmada?.actor === actor ? listaConfirmada.datos : null)
  const limpiar = () => {setBusqueda(''); setFiltros(FILTROS_INVERSIONISTAS_INICIALES)}
  const filtro = (c: Partial<FiltrosInversionistas>) => setFiltros(f => ({...f, ...c, pagina: 1}))
  useEffect(() => {
    const t = setTimeout(() => setFiltros(f => f.texto === busqueda ? f : {...f, texto: busqueda, pagina: 1}), 300)
    return () => clearTimeout(t)
  }, [busqueda])
  useEffect(() => () => {documento.current?.abort()}, [actor, seleccion, nueva])
  const revocar = () => {
    const persona = nueva?.persona ?? seleccion ?? undefined
    let referencia: string | undefined
    try {if (persona) referencia = leerIntentoInversion(actor, persona)?.clave}
    catch { /* No recuperar ni mostrar contenido ilegible. */ }
    documento.current?.abort(); setDescargando(false); seleccionar(null); setNueva(null)
    limpiarIntentosInversion(actor, persona)
    setAviso(`El acceso cambió. La cartera se volverá a consultar.${referencia ? ` Referencia de la solicitud pendiente: ${referencia}.` : ''}`)
    // Cancelar impide que una respuesta antigua vuelva a poblar la ficha.
    void qc.cancelQueries({queryKey: inversionistasKeys.actor(actor)}).then(() => {
      qc.removeQueries({queryKey: [...inversionistasKeys.actor(actor), 'persona']})
      qc.removeQueries({queryKey: [...inversionistasKeys.actor(actor), 'lista']})
      void qc.invalidateQueries({queryKey: inversionistasKeys.actor(actor)})
    })
    void qc.cancelQueries({queryKey: postventaKeys.actor(actor)}).then(() => qc.removeQueries({queryKey: postventaKeys.actor(actor)}))
    titulo.current?.focus()
  }
  const revocarRef = useRef(revocar); revocarRef.current = revocar
  const revocacionLista = useRef<string | null>(null)
  useEffect(() => {
    if (q.isSuccess) revocacionLista.current = null
    if (accesoRevocado && revocacionLista.current !== claveLista) {
      revocacionLista.current = claveLista
      revocarRef.current()
    }
  }, [accesoRevocado, claveLista, q.isSuccess])
  async function abrirDocumento(i: InversionFuente, id: string, recuperar = false) {
    if (!seleccion || descargando) return
    const abort = new AbortController(); documento.current?.abort(); documento.current = abort
    setDescargando(true)
    try {
      if (recuperar) {
        await archivarContratoPdfConfirmado(i.fuente_id)
        if (abort.signal.aborted) return
        void qc.invalidateQueries({queryKey: [...inversionistasKeys.actor(actor), 'persona', seleccion]})
      }
      await descargarDocumentoInversionista(seleccion, i.fuente_id, id, abort.signal)
    }
    catch (e) {
      if (abort.signal.aborted) return
      if (e instanceof CrmApiError && e.code === '42501') revocar()
      else toast.error(mensajeDeError(e, 'No se pudo descargar el documento.'))
    } finally {if (documento.current === abort) setDescargando(false)}
  }
  async function eliminarContrato(i: InversionFuente) {
    if (!permiteEliminar || i.empresa !== 'avance' || !i.contrato) throw new ContratoEliminacionError('No tienes permiso para eliminar este contrato.')
    const {auditoriaId} = await eliminarContratoConPdf(i.fuente_id)
    await Promise.all([
      qc.invalidateQueries({queryKey: inversionistasKeys.actor(actor)}),
      qc.invalidateQueries({queryKey: crmQueryKeys.contratos()}),
      qc.invalidateQueries({queryKey: crmQueryKeys.metricas()}),
      qc.invalidateQueries({queryKey: crmQueryKeys.leads()}),
      qc.invalidateQueries({queryKey: postventaKeys.actor(actor)}),
    ])
    toast.success(`Contrato ${i.numero || ''} eliminado. Copia de auditoría: ${auditoriaId}.`)
  }
  return <div className="@container/cartera mx-auto max-w-[1440px] space-y-3">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 ref={titulo} tabIndex={-1} className="text-xl font-bold tracking-tight outline-none">Cartera de inversionistas</h2>
        <p className="mt-1 text-sm text-muted-foreground">{catalogo?.solo_avance ? 'Una ficha por persona, con sus inversiones Avance.' : 'Una ficha por persona, con sus inversiones en cada empresa.'}</p></div>
      <div className="flex items-center gap-2"><Button variant="ghost" size="sm" aria-label="Actualizar cartera"
        disabled={q.isFetching} onClick={() => void q.refetch()}><RefreshCw aria-hidden /></Button>
        {puedeAlta && <Button size="sm" onClick={()=>setAlta(true)}>Nuevo cliente</Button>}
        </div>
    </div>
    {aviso && <p role="status" className="rounded-lg bg-muted p-3 text-sm">{aviso}</p>}
    <Card className="overflow-hidden">
      <FiltrosCarteraInversionistas filtros={filtros} busqueda={busqueda} catalogo={catalogo}
        verResponsable={yo?.rol !== 'vendedor'} onBusqueda={setBusqueda} onCambio={filtro} onLimpiar={limpiar} />
      {q.isError && <PanelError mensaje={datos ? 'No pudimos actualizar la cartera. Se muestran los últimos datos confirmados.' : mensajeDeError(q.error, 'No pudimos cargar la cartera.')}
        onReintentar={() => void q.refetch()} reintentando={q.isFetching} />}
      {!datos ? !q.isError && <PanelCargando filas={6} /> : <>
          {datos.totales.length > 0 && <div aria-label="Capital de las inversiones filtradas" className="border-t border-border bg-muted/30 px-4 py-2 @lg/cartera:py-3">
            <Button variant="ghost" size="sm" className="min-h-10 w-full whitespace-normal px-0 text-left @lg/cartera:hidden"
              aria-expanded={resumenAbierto} aria-controls="f5-resumen" onClick={() => setResumenAbierto(v => !v)}>
              Capital por empresa y moneda <ChevronDown aria-hidden className={resumenAbierto ? 'rotate-180' : ''} /></Button>
            <div id="f5-resumen" className={resumenAbierto ? 'pb-2' : 'hidden @lg/cartera:block'}>
              <ResumenEmpresas totales={datos.totales} compacto registrado /></div></div>}
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-4 py-2">
            <p role="status" className="text-xs text-muted-foreground">{datos.total} {datos.total === 1 ? 'persona' : 'personas'} · página {datos.pagina}
              {datos.sin_inversiones_total > 0 && ` · ${datos.sin_inversiones_total} sin inversiones${datos.solo_avance ? ' Avance' : ''}`}</p>
            <div className="flex items-center gap-2"><Label htmlFor="f5-tamano" className="whitespace-nowrap text-xs">Por página</Label>
              <div className="w-20"><Select id="f5-tamano" className="h-9" value={filtros.tamano} onChange={e => filtro({tamano:Number(e.target.value) as FiltrosInversionistas['tamano']})}>
                {[10,25,50].map(n => <option key={n} value={n}>{n}</option>)}</Select></div></div>
          </div>
          {datos.filas.length === 0 ? <PanelVacio icono={Users2}
            titulo={datos.total === 0 ? 'No hay personas que coincidan con estos filtros.' : 'Esta página ya no tiene resultados.'}>
            <Button variant="outline" size="sm" className="mt-2 min-h-10" onClick={limpiar}>Ver toda la cartera</Button>
          </PanelVacio> : <>
            <div aria-hidden className="hidden grid-cols-[2fr_1.5fr_1fr_1fr] gap-4 border-t border-border bg-muted/40 px-4 py-2 text-xs font-medium text-muted-foreground-strong @4xl/cartera:grid">
              <span>Cliente · todas sus empresas</span><span>Capital registrado · filtros</span><span>Último cierre · filtros</span><span>Responsable actual</span>
            </div>
            <ul className="divide-y divide-border border-y border-border">{datos.filas.map(p => <li key={p.inversionista_id}>
              <button type="button" className="grid min-h-16 w-full gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring @lg/cartera:grid-cols-2 @4xl/cartera:grid-cols-[2fr_1.5fr_1fr_1fr] @4xl/cartera:gap-4"
                onClick={() => {setAviso(''); setDescargando(false); seleccionar(p.inversionista_id)}} aria-label={`Abrir ficha de ${p.nombre}`}
                aria-describedby={`documento-${p.inversionista_id} capital-${p.inversionista_id} fecha-${p.inversionista_id} responsable-${p.inversionista_id}`}>
                <span className="min-w-0"><span className="block text-sm font-semibold [overflow-wrap:anywhere]">{p.nombre}</span>
                  <span id={`documento-${p.inversionista_id}`} className="block text-xs text-muted-foreground">{p.documento_tipo} {p.documento || 'Documento pendiente'}</span>
                  <span className="mt-1 flex flex-wrap gap-1">{p.empresas.map(e => <Badge key={e}>{EMPRESA_NOMBRE[e]}</Badge>)}</span></span>
                <span id={`capital-${p.inversionista_id}`} className="min-w-0 space-y-1 text-xs">
                  <span className="sr-only">Capital registrado según los filtros:</span>{' '}
                  {p.resumen.length === 0 ? <span className="text-muted-foreground">Sin inversiones{datos.solo_avance ? ' Avance' : ''}</span> : p.resumen.map(t =>
                    <span key={`${t.empresa}:${t.moneda}`} className="flex flex-wrap items-baseline justify-between gap-x-2">
                      <span className="text-muted-foreground">{EMPRESA_NOMBRE[t.empresa]} · {t.moneda}</span>{' '}
                      <span className="font-semibold tabular-nums">{money(t.capital_registrado,t.moneda)}</span>
                    </span>)}
                </span>
                <span id={`fecha-${p.inversionista_id}`} className="text-xs text-muted-foreground"><span className="@4xl/cartera:sr-only">Último cierre:</span>{' '}{p.ultima_fecha_comercial ? fmtFecha(p.ultima_fecha_comercial) : 'Sin cierre'}</span>
                <span id={`responsable-${p.inversionista_id}`} className="min-w-0 text-xs text-muted-foreground [overflow-wrap:anywhere]"><span className="sr-only">Responsable actual:</span>{' '}{p.responsable_nombre || 'Sin responsable'}{p.no_contactar && <span className="block text-warning-text"><span className="sr-only">. </span>No contactar</span>}</span>
              </button>
            </li>)}</ul>
          </>}
          <div className="px-4 py-2"><Paginacion paginaActual={filtros.pagina - 1} paginas={Math.max(1, Math.ceil(datos.total / filtros.tamano))} total={datos.total}
            onCambio={n => setFiltros(f => ({...f, pagina: n + 1}))} mostrarSiempre ariaLabel="Paginación de inversionistas" /></div>
        </>}
    </Card>
    <VencimientosPostventa key={filtros.empresa} actor={actor} empresa={filtros.empresa} onAbrir={seleccionar} />
    {seleccion && !nueva && <Sheet open onClose={() => {documento.current?.abort(); setDescargando(false); seleccionar(null)}} ariaLabel="Ficha del inversionista" className="w-[620px] max-w-full">
      {descargando && <p role="status" className="px-5 pt-3 text-sm">Comprobando acceso y descargando documento…</p>}
      <InversionistaFicha key={seleccion} actor={actor} inversionistaId={seleccion} onCerrar={() => seleccionar(null)} onRevocado={revocar}
        enfocarInversiones={volverAInversiones}
        onNuevaInversion={permiteInversion ? f => setNueva({persona: f.persona.inversionista_id}) : undefined}
        onOperacion={permiteInversion ? op => setNueva({persona: seleccion, operacion: op}) : undefined}
        onEliminar={permiteEliminar ? eliminarContrato : undefined}
        onDocumento={(i, id) => void abrirDocumento(i, id)} onRecuperarPdf={i => void abrirDocumento(i, i.fuente_id, true)} />
    </Sheet>}
    {nueva && <InversionNueva key={nueva.persona} actor={actor} persona={nueva.persona} operacion={nueva.operacion}
      onCerrar={() => {setVolverAInversiones(true); setNueva(null); setSeleccion(nueva.persona)}} onRevocado={revocar}
      onConfirmada={() => {void qc.invalidateQueries({queryKey: inversionistasKeys.actor(actor)})}} />}
    {alta && puedeAlta && <Dialog open ariaLabel="Nuevo cliente" onClose={()=>{if(!altaEnCurso.current)setAlta(false)}}>
      <ClienteForm modo="crear" onCerrar={()=>{if(!altaEnCurso.current)setAlta(false)}}
        onEnviandoCambio={valor=>{altaEnCurso.current=valor}}
        onListo={()=>{altaEnCurso.current=false;setAlta(false);limpiar();void refrescarGestionInversionista(qc,actor);toast.success('Cliente creado. Ya puedes abrir su ficha y registrar la primera inversión.')}} />
    </Dialog>}
  </div>
}
