import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Search, Users2, RefreshCw } from 'lucide-react'
import { toast } from 'sonner'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'
import { Sheet } from '@/components/ui/sheet'
import { PanelCargando, PanelError } from '@/components/common/estado-panel'
import { Paginacion } from '@/components/common/paginacion'
import { SectionHead } from '@/components/common/section-head'
import { InversionistaFicha, ResumenEmpresas } from '@/components/app/inversionista-ficha'
import { InversionNueva, type OperacionInversion } from '@/components/app/inversion-nueva'
import { useCRMData } from '@/lib/store-context'
import { EMPRESAS_INVERSION, EMPRESA_NOMBRE, FILTROS_INVERSIONISTAS_INICIALES, type FiltrosInversionistas, type InversionFuente } from '@/lib/inversionistas'
import { limpiarIntentosInversion } from '@/lib/inversion-solicitud'
import { inversionistasKeys, useInversionistas } from '@/data/inversionistas-queries'
import { CrmApiError, mensajeDeError } from '@/data/crm-api'
import { descargarDocumentoInversionista } from '@/data/inversionistas-api'
import { archivarContratoPdfConfirmado } from '@/lib/contrato-pdf-archivo'

export function CarteraInversionistas({actor, permiteInversion, gestionAvance}: {
  actor: string; permiteInversion: boolean; gestionAvance: ReactNode
}) {
  const {equipo} = useCRMData()
  const qc = useQueryClient()
  const [filtros, setFiltros] = useState<FiltrosInversionistas>(FILTROS_INVERSIONISTAS_INICIALES)
  const [busqueda, setBusqueda] = useState('')
  const [seleccion, setSeleccion] = useState<string | null>(null)
  const [nueva, setNueva] = useState<{persona: string; operacion?: OperacionInversion} | null>(null)
  const [gestion, setGestion] = useState(false)
  const [aviso, setAviso] = useState('')
  const [descargando, setDescargando] = useState(false)
  const documento = useRef<AbortController | null>(null)
  const titulo = useRef<HTMLHeadingElement>(null)
  const q = useInversionistas(actor, filtros)
  const datos = q.isFetchedAfterMount && q.isSuccess ? q.data : null
  const filtro = (c: Partial<FiltrosInversionistas>) => setFiltros(f => ({...f, ...c, pagina: 1}))
  useEffect(() => {
    const t = setTimeout(() => setFiltros(f => f.texto === busqueda ? f : {...f, texto: busqueda, pagina: 1}), 300)
    return () => clearTimeout(t)
  }, [busqueda])
  useEffect(() => () => {documento.current?.abort()}, [actor, seleccion, nueva])
  const revocar = () => {
    documento.current?.abort(); setDescargando(false); setSeleccion(null); setNueva(null)
    limpiarIntentosInversion(actor, nueva?.persona ?? seleccion ?? undefined)
    setAviso('El acceso cambió. La cartera se volverá a consultar.')
    // Cancelar impide que una respuesta antigua vuelva a poblar la ficha.
    void qc.cancelQueries({queryKey: inversionistasKeys.actor(actor)}).then(() => {
      qc.removeQueries({queryKey: [...inversionistasKeys.actor(actor), 'persona']})
      qc.removeQueries({queryKey: [...inversionistasKeys.actor(actor), 'lista']})
      void qc.invalidateQueries({queryKey: inversionistasKeys.actor(actor)})
    })
    titulo.current?.focus()
  }
  const revocarRef = useRef(revocar); revocarRef.current = revocar
  useEffect(() => {
    if (q.error instanceof CrmApiError && q.error.code === '42501') revocarRef.current()
  }, [q.error])
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
    } finally {if (!abort.signal.aborted) setDescargando(false)}
  }
  if (gestion) return <div className="space-y-4">
    <Button variant="outline" onClick={() => setGestion(false)}>Volver a la cartera multiempresa</Button>
    <p className="text-sm text-muted-foreground">Consulta cronogramas y gestiona los clientes y contratos Avance existentes.</p>
    {gestionAvance}
  </div>
  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h2 ref={titulo} tabIndex={-1} className="text-xl font-bold tracking-tight outline-none">Cartera de inversionistas</h2>
        <p className="mt-1 text-sm text-muted-foreground">Una ficha por persona, con sus inversiones en cada empresa.</p></div>
      <Button variant="outline" size="sm" onClick={() => {setSeleccion(null); setNueva(null); setGestion(true)}}>Gestión Avance</Button>
    </div>
    {aviso && <p role="status" className="rounded-lg bg-muted p-3 text-sm">{aviso}</p>}
    <Card>
      <SectionHead icon={Users2} title="Inversionistas" right={<Button variant="ghost" size="sm" aria-label="Actualizar cartera"
        disabled={q.isFetching} onClick={() => void q.refetch()}><RefreshCw aria-hidden /></Button>} />
      <div className="grid gap-3 px-5 pb-4 sm:grid-cols-2 xl:grid-cols-[2fr_1fr_1fr_auto]">
        <div className="min-w-0 space-y-1"><Label htmlFor="f5-buscar">Buscar persona</Label><div className="relative">
          <Search aria-hidden className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" />
          <Input id="f5-buscar" type="search" placeholder="Nombre, documento, contacto o empresa" className="pl-9" maxLength={120}
            value={busqueda} onChange={e => setBusqueda(e.target.value)} /></div></div>
        <div className="space-y-1"><Label htmlFor="f5-empresa">Empresa</Label><Select id="f5-empresa" value={filtros.empresa} onChange={e => filtro({empresa: e.target.value as FiltrosInversionistas['empresa']})}>
          <option value="">Todas las empresas</option>{EMPRESAS_INVERSION.map(e => <option value={e} key={e}>{EMPRESA_NOMBRE[e]}</option>)}</Select></div>
        <div className="space-y-1"><Label htmlFor="f5-responsable">Responsable actual</Label><Select id="f5-responsable" value={filtros.responsable} onChange={e => filtro({responsable: e.target.value})}>
          <option value="">Todos los visibles</option><option value="sin_responsable">Sin responsable</option>
          {equipo.filter(e => e.activo).map(e => <option key={e.perfil_id} value={e.perfil_id}>{e.nombre_completo}</option>)}</Select></div>
        <div className="space-y-1"><Label htmlFor="f5-tamano">Por página</Label><Select id="f5-tamano" value={filtros.tamano} onChange={e => filtro({tamano: Number(e.target.value) as FiltrosInversionistas['tamano']})}>
          {[10,25,50].map(n => <option key={n} value={n}>{n}</option>)}</Select></div>
      </div>
      {q.isError ? <PanelError mensaje={mensajeDeError(q.error, 'No pudimos cargar la cartera.')} onReintentar={() => void q.refetch()} reintentando={q.isFetching} />
        : !datos ? <PanelCargando filas={6} /> : <>
          <div className="border-t border-border px-5 py-4"><ResumenEmpresas totales={datos.totales} /></div>
          <p role="status" className="border-t border-border px-5 py-3 text-xs text-muted-foreground">{datos.total} {datos.total === 1 ? 'persona' : 'personas'} · página {datos.pagina}</p>
          {datos.filas.length === 0 ? <div className="space-y-3 px-5 py-8 text-center">
            <p className="text-sm">{datos.total === 0 ? 'No hay personas que coincidan con estos filtros.' : 'Esta página ya no tiene resultados.'}</p>
            <Button variant="outline" onClick={() => {setBusqueda(''); setFiltros(FILTROS_INVERSIONISTAS_INICIALES)}}>Restablecer filtros</Button>
          </div> : <ul className="divide-y divide-border border-y border-border">{datos.filas.map(p => <li key={p.inversionista_id}>
            <button type="button" className="grid min-h-20 w-full gap-2 px-5 py-4 text-left transition-colors hover:bg-muted/50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ring sm:grid-cols-[2fr_1fr_1fr]"
              onClick={() => {setAviso(''); setDescargando(false); setSeleccion(p.inversionista_id)}} aria-label={`Abrir ficha de ${p.nombre}`}>
              <span className="min-w-0"><span className="block text-sm font-semibold [overflow-wrap:anywhere]">{p.nombre}</span>
                <span className="block text-xs text-muted-foreground">{p.documento_tipo} {p.documento || 'Documento pendiente'}</span></span>
              <span className="flex flex-wrap items-center gap-1">{p.empresas.map(e => <Badge key={e}>{EMPRESA_NOMBRE[e]}</Badge>)}</span>
              <span className="text-xs text-muted-foreground [overflow-wrap:anywhere]">{p.responsable_nombre || 'Sin responsable'}{p.no_contactar && <span className="block text-warning-text">No contactar</span>}</span>
            </button>
          </li>)}</ul>}
          <div className="px-5 py-3"><Paginacion paginaActual={filtros.pagina - 1} paginas={Math.max(1, Math.ceil(datos.total / filtros.tamano))} total={datos.total}
            onCambio={n => setFiltros(f => ({...f, pagina: n + 1}))} mostrarSiempre ariaLabel="Paginación de inversionistas" /></div>
        </>}
    </Card>
    {seleccion && !nueva && <Sheet open onClose={() => {documento.current?.abort(); setDescargando(false); setSeleccion(null)}} ariaLabel="Ficha del inversionista" className="w-[760px]">
      {descargando && <p role="status" className="px-5 pt-3 text-sm">Comprobando acceso y descargando documento…</p>}
      <InversionistaFicha key={seleccion} actor={actor} inversionistaId={seleccion} onCerrar={() => setSeleccion(null)} onRevocado={revocar}
        onNuevaInversion={permiteInversion ? f => setNueva({persona: f.persona.inversionista_id}) : undefined}
        onOperacion={permiteInversion ? op => setNueva({persona: seleccion, operacion: op}) : undefined}
        onDocumento={(i, id) => void abrirDocumento(i, id)} onRecuperarPdf={i => void abrirDocumento(i, i.fuente_id, true)} />
    </Sheet>}
    {nueva && <InversionNueva key={nueva.persona} actor={actor} persona={nueva.persona} operacion={nueva.operacion}
      onCerrar={() => {setNueva(null); setSeleccion(nueva.persona)}} onRevocado={revocar}
      onConfirmada={() => {void qc.invalidateQueries({queryKey: inversionistasKeys.actor(actor)})}} />}
  </div>
}
