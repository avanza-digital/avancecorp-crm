import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { CalendarDays, ChartNoAxesCombined, ChevronLeft, ChevronRight, CircleHelp, Download, List, SearchX, X } from 'lucide-react'
import { BrandLockup } from '@/components/app/brand'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'
import { Sheet, SheetBody, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { money, fmtFecha } from '@/lib/format'
import { cn } from '@/lib/utils'
import { ESTADOS, EQUIPO, errorFiltros, ordenar, csv, type EstadoCita } from '../../../prototypes/citas-assets/model.mjs'
import { CITAS_CRM as CITAS, consultaInicial as defaults, consultarCitas as filtrar, rangoConsulta, type CitaConLead as CitaEjemplo, type ConsultaCitas as FiltrosCitas } from './datos'
import { Filtros } from './filtros'
import { Agenda, Bandeja, Estado } from './vistas'
import { Resultados, DetalleLeads } from './resultados'
import { nombreAnalista, siguientePaso, contextoCita } from './presentacion'

type VistaCitas = 'bandeja' | 'agenda' | 'resultados'
const VISTAS = [
  { id: 'bandeja', titulo: 'Bandeja comercial', icono: List },
  { id: 'agenda', titulo: 'Agenda', icono: CalendarDays },
  { id: 'resultados', titulo: 'Resultados', icono: ChartNoAxesCombined },
] as const
const ATAJOS: (EstadoCita | '')[] = ['', 'vencida', 'programada', 'realizada', 'no_show']
const POR_PAGINA = 8

function Guia({ abierta, onCerrar }: { abierta: boolean; onCerrar: () => void }) {
  return <Sheet open={abierta} onClose={onCerrar} className="citas-crm-dialogo w-[560px]">
    <SheetHeader><div className="flex items-center justify-between gap-3"><SheetTitle>Cómo usar Citas</SheetTitle><Button variant="ghost" size="icon" onClick={onCerrar} aria-label="Cerrar guía"><X aria-hidden /></Button></div><p className="text-sm text-muted-foreground-strong">De la consulta del equipo al detalle de una cita.</p></SheetHeader>
    <SheetBody className="space-y-6 text-sm leading-relaxed">
      <section><h3 className="font-semibold">1. Define a quién y cuándo quieres revisar</h3><p className="mt-1 text-muted-foreground-strong">Elige supervisor, analista, mes y semana. Cada mes tiene cuatro tramos: 1–7, 8–14, 15–21 y 22 hasta el último día. También puedes buscar por nombre, teléfono o código. La consulta se actualiza al cambiar cada filtro.</p></section>
      <section><h3 className="font-semibold">2. Empieza por lo que necesita atención</h3><p className="mt-1 text-muted-foreground-strong">En «Bandeja comercial», pulsa «Sin resultado» para encontrar citas vencidas cuyo resultado no se registró. «Programadas» muestra las que todavía están por realizar en el período.</p></section>
      <section><h3 className="font-semibold">3. Combina los filtros</h3><p className="mt-1 text-muted-foreground-strong">Abre «Más filtros» para elegir varios estados, modalidad, origen, resultado y seguimiento. Para filtrar un importe, selecciona primero soles o dólares.</p></section>
      <section><h3 className="font-semibold">4. Cambia de vista según la tarea</h3><ul className="mt-2 list-disc space-y-2 pl-5 text-muted-foreground-strong"><li><strong>Bandeja comercial:</strong> revisa responsable, estado y siguiente paso. «Pendientes primero» deja las vencidas arriba.</li><li><strong>Agenda:</strong> revisa citas por día y hora. Siempre usa orden cronológico.</li><li><strong>Resultados:</strong> empieza por el recorrido de quienes no asistieron. Pulsa una etapa para ver sus personas y abre un nombre para consultar el historial, las fechas y el depósito. Debajo, compara citas por lead y cumplimiento de cada analista: meta 3 = 100%, objetivo 3.75 = 125%. La flecha junto al analista abre sus leads. «Columnas» muestra también leads con 2+ citas, realizadas y supervisor.</li></ul><p className="mt-2 text-muted-foreground-strong">Las tres vistas conservan tus filtros y consultan el mismo conjunto de citas. Los filtros seleccionan las citas de origen; el seguimiento puede encontrar depósitos posteriores fuera del mes o semana, hasta el corte del ejemplo. Cada etapa cuenta leads únicos y parte de la anterior. El porcentaje final usa como base quienes faltaron al inicio; un depósito anterior a la asistencia no entra en este flujo.</p></section>
      <section><h3 className="font-semibold">5. Abre la ficha</h3><p className="mt-1 text-muted-foreground-strong">Pulsa el nombre del prospecto o «Detalle». La ficha lateral muestra fecha, responsable, monto estimado, resultado, notas y siguiente paso. «Ubicar en agenda» abre esa cita. «Citas de…» abre todas las citas de ese analista en el mes de la ficha. Estas dos acciones restablecen los demás filtros para que el destino sea visible.</p></section>
      <section><h3 className="font-semibold">6. Limpia o exporta la consulta</h3><p className="mt-1 text-muted-foreground-strong">La × de cada etiqueta quita ese filtro. «Restablecer consulta» vuelve al mes completo. «Exportar citas» descarga todas las coincidencias, incluidas las de otras páginas. El CSV contiene el detalle de las citas; el promedio por lead y el seguimiento se consultan en Resultados.</p></section>
      <Card className="space-y-2 p-4"><h3 className="font-semibold">Un ejemplo para probar ahora</h3><p>Elige <strong>Claudia Ríos</strong> y pulsa <strong>Sin resultado</strong>: aparecerán tres citas. Cambia a Agenda y después a Resultados; seguirás viendo esas mismas tres citas.</p></Card>
      <p className="rounded-lg bg-muted p-3 text-xs text-muted-foreground-strong">Esta adaptación usa 40 citas ficticias con corte al 7 de septiembre de 2026, 13:00 Lima. Permite consultar y exportar el ejemplo. El registro, la reprogramación y los datos reales se conectarán en la integración del módulo.</p>
    </SheetBody>
    <SheetFooter><Button className="w-full" onClick={onCerrar}>Entendido, volver a las citas</Button></SheetFooter>
  </Sheet>
}

function Ficha({ cita, onCerrar, onAnalista, onAgenda }: { cita: CitaEjemplo | null; onCerrar: () => void; onAnalista: (cita: CitaEjemplo) => void; onAgenda: (cita: CitaEjemplo) => void }) {
  return <Sheet open={Boolean(cita)} onClose={onCerrar} className="citas-crm-dialogo w-[500px]">
    <SheetHeader><div className="flex items-start justify-between gap-3"><div><p className="mb-1 text-xs text-muted-foreground-strong">Detalle de cita · {cita?.id}</p><SheetTitle>{cita?.nombre ?? 'Detalle de cita'}</SheetTitle></div><Button variant="ghost" size="icon" aria-label="Cerrar detalle" onClick={onCerrar}><X aria-hidden /></Button></div></SheetHeader>
    {cita && <><SheetBody className="space-y-6"><Estado cita={cita} /><dl className="grid grid-cols-2 gap-x-4 gap-y-5 text-sm">{[
      ['Fecha prevista', fmtFecha(cita.fecha)], ['Hora de Lima', cita.hora], ['Analista', nombreAnalista(cita.analista)], ['Supervisor', cita.supervisor],
      ['Modalidad', cita.modalidad], ['Origen', cita.origen], ['Monto estimado', money(cita.monto, cita.moneda)], ['Teléfono de ejemplo', cita.telefono],
    ].map(([etiqueta, valor]) => <div key={etiqueta}><dt className="text-xs text-muted-foreground-strong">{etiqueta}</dt><dd className="mt-1 font-semibold">{valor}</dd></div>)}</dl>
      <section className="rounded-xl border border-border bg-muted/40 p-4"><h3 className="text-sm font-semibold">Siguiente paso: {siguientePaso(cita)}</h3><p className="mt-2 text-sm text-muted-foreground-strong">{contextoCita(cita)}</p></section>
      <section><h3 className="text-sm font-semibold">Resultado registrado</h3><p className="mt-2 text-sm text-muted-foreground-strong">{cita.resultado}</p></section>
      <section><h3 className="text-sm font-semibold">Contexto de la cita</h3><p className="mt-2 text-sm leading-relaxed text-muted-foreground-strong">{cita.nota}</p></section>
      <p className="text-xs text-muted-foreground-strong">Información ficticia para probar la propuesta. Ninguna acción modifica una cita real.</p>
    </SheetBody><SheetFooter className="flex-wrap"><Button variant="outline" className="flex-1" onClick={() => onAnalista(cita)}>Citas de {nombreAnalista(cita.analista).split(' ')[0]}</Button><Button variant="accent" className="flex-1" onClick={() => onAgenda(cita)}><CalendarDays aria-hidden />Ubicar en agenda</Button></SheetFooter></>}
  </Sheet>
}

export function PropuestaCitasCRM() {
  const [filtros, setFiltros] = useState<FiltrosCitas>(defaults)
  const [vista, setVista] = useState<VistaCitas>('resultados')
  const [pagina, setPagina] = useState(1)
  const [detalle, setDetalle] = useState<CitaEjemplo | null>(null)
  const [desglose, setDesglose] = useState<string | null>(null)
  const [leadAbierto, setLeadAbierto] = useState<string | null>(null)
  const [guia, setGuia] = useState(false)
  const [anuncio, setAnuncio] = useState('')
  const [exportacion, setExportacion] = useState('')
  const pestañas = useRef<Partial<Record<VistaCitas, HTMLButtonElement | null>>>({})
  const error = errorFiltros(filtros)
  const citas = filtrar(filtros)
  const sinEstado = filtrar({ ...filtros, estados: [] })
  const paginas = Math.max(1, Math.ceil(citas.length / POR_PAGINA))
  const paginaActual = Math.min(pagina, paginas)
  const visibles = ordenar(citas, filtros.sort).slice((paginaActual - 1) * POR_PAGINA, paginaActual * POR_PAGINA)
  const [desde, hasta] = rangoConsulta(filtros)
  const textoConteo = error ? 'Revisa los filtros para consultar las citas.' : citas.length + ' de ' + CITAS.length + ' citas del ejemplo' + (vista === 'agenda' ? ' · orden cronológico · hora de Lima' : ' · según tus filtros')

  useEffect(() => {
    const temporizador = window.setTimeout(() => setAnuncio(textoConteo), 250)
    return () => window.clearTimeout(temporizador)
  }, [textoConteo])

  function cambiar(cambios: Partial<FiltrosCitas>) {
    setFiltros(previos => {
      const siguientes = { ...previos, ...cambios }
      if (Object.hasOwn(cambios, 'equipo') && siguientes.equipo && EQUIPO.find(p => p.id === siguientes.analista)?.supervisor !== siguientes.equipo) siguientes.analista = ''
      if (Object.hasOwn(cambios, 'moneda') && cambios.moneda !== previos.moneda) siguientes.min = siguientes.max = ''
      return siguientes
    })
    setPagina(1)
    setExportacion('')
    setLeadAbierto(null)
  }
  function restablecer() { setFiltros(defaults()); setPagina(1); setExportacion(''); setLeadAbierto(null) }
  function cambiarVista(destino: VistaCitas) { setVista(destino); setLeadAbierto(null) }
  function enfocarVista(destino: VistaCitas) {
    requestAnimationFrame(() => requestAnimationFrame(() => pestañas.current[destino]?.focus()))
  }
  function verAnalista(id: string) { cambiar({ analista: id }); setDetalle(null); cambiarVista('bandeja'); enfocarVista('bandeja') }
  function verAnalistaDeFicha(cita: CitaEjemplo) { setFiltros({ ...defaults(), mes: cita.fecha.slice(0, 7), analista: cita.analista }); setPagina(1); setExportacion(''); setDetalle(null); cambiarVista('bandeja'); enfocarVista('bandeja') }
  function verLead(leadId: string, analista: string) { cambiar({ leadId, analista }); setDesglose(null); cambiarVista('bandeja'); enfocarVista('bandeja') }
  function verAgenda(cita: CitaEjemplo) { setFiltros({ ...defaults(), mes: cita.fecha.slice(0, 7), q: cita.id }); setPagina(1); setExportacion(''); setDetalle(null); cambiarVista('agenda'); enfocarVista('agenda') }
  function abrirCitaDelRecorrido(cita: CitaEjemplo) {
    setLeadAbierto(null)
    // Termina el retorno de foco del inspector antes de abrir la ficha de cita.
    requestAnimationFrame(() => requestAnimationFrame(() => setDetalle(cita)))
  }
  function tecladoVista(evento: KeyboardEvent<HTMLDivElement>) {
    if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(evento.key)) return
    evento.preventDefault()
    const actual = VISTAS.findIndex(item => item.id === vista)
    const indice = evento.key === 'Home' ? 0 : evento.key === 'End' ? VISTAS.length - 1 : (actual + (evento.key === 'ArrowRight' ? 1 : -1) + VISTAS.length) % VISTAS.length
    const destino = VISTAS[indice]!.id
    cambiarVista(destino)
    pestañas.current[destino]?.focus()
  }
  function exportar() {
    if (error || !citas.length) return
    try {
      const url = URL.createObjectURL(new Blob([csv(ordenar(citas, filtros.sort))], { type: 'text/csv;charset=utf-8;' }))
      const enlace = document.createElement('a')
      enlace.href = url
      enlace.download = 'citas-ejemplo-gerencia.csv'
      try { document.body.append(enlace); enlace.click() }
      finally { enlace.remove(); window.setTimeout(() => URL.revokeObjectURL(url), 1000) }
      setExportacion('Se descargó el CSV con ' + citas.length + (citas.length === 1 ? ' cita' : ' citas') + ' de tu consulta.')
    } catch { setExportacion('No se pudo descargar el archivo. Vuelve a intentarlo.') }
  }

  return <div className="citas-crm flex bg-card text-foreground">
    <a href="#consulta-citas" className="sr-only z-50 focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:rounded-lg focus:bg-white focus:p-3 focus:text-accent">Ir a la consulta de citas</a>
    <aside className="citas-rail sticky top-0 hidden h-screen w-[208px] shrink-0 flex-col border-r border-sidebar-border p-4 text-sidebar-foreground xl:flex" aria-label="Gerencia comercial">
      <BrandLockup tone="dark" subtitle="CRM Comercial" />
      <p className="mt-10 px-3 text-xs text-sidebar-foreground">Gerencia comercial</p>
      <a href="#consulta-citas" aria-current="page" className="ac-nav-item is-active mt-3 flex items-center gap-3 rounded-lg bg-sidebar-primary px-3 py-3 text-sm font-semibold text-white"><CalendarDays aria-hidden className="size-[18px]" />Citas</a>
    </aside>
    <div className="min-w-0 flex-1">
      <header className="citas-cabecera">
        <div><h1 className="text-2xl font-bold tracking-tight text-primary">Citas del equipo</h1>
          <p className="citas-nota">Origen: {fmtFecha(desde)}–{fmtFecha(hasta)} · Seguimiento al 7 sep. 2026, 13:00 Lima</p>
        </div>
        <div className="flex items-center gap-2">
          <span className="citas-ejemplo">Ejemplo · datos ficticios</span>
          <Button variant="ghost" size="icon" aria-label="Cómo usar Citas" title="Cómo usar Citas" onClick={() => setGuia(true)}><CircleHelp aria-hidden /></Button>
          <Button variant="ghost" size="icon" aria-label="Exportar citas" title="Exportar citas" disabled={Boolean(error) || !citas.length} onClick={exportar}><Download aria-hidden /></Button>
        </div>
      </header>
      <main id="consulta-citas" tabIndex={-1} className={cn('citas-contenido outline-none', leadAbierto && 'citas-con-ficha')}>
        <Filtros filtros={filtros} onCambiar={cambiar} onRestablecer={restablecer} />
        <div className="citas-vistas" role="tablist" tabIndex={-1} aria-label="Cómo ver las citas" onKeyDown={tecladoVista}>
          {VISTAS.map(item => <Button key={item.id} id={'citas-tab-' + item.id} ref={elemento => { pestañas.current[item.id] = elemento }}
            role="tab" aria-controls="citas-panel" aria-selected={vista === item.id} tabIndex={vista === item.id ? 0 : -1}
            variant="ghost" className={cn('citas-pestana', vista === item.id && 'citas-pestana-activa')} onClick={() => cambiarVista(item.id)}>
            <item.icono aria-hidden />{item.titulo}
          </Button>)}
        </div>
        <section aria-label="Resultados de la consulta">
          <div className={vista === 'resultados' ? 'sr-only' : 'flex flex-wrap items-center justify-between gap-3 py-4'}>
            <div><h2 className="text-base font-semibold">{vista === 'agenda' ? 'Agenda por día' : vista === 'resultados' ? 'Resultados por analista' : 'Todas las citas de tu consulta'}</h2>
              <p className="citas-nota" data-testid="conteo-citas">{textoConteo}</p>
            </div>
            {vista === 'bandeja' && <label className="flex items-center gap-2 whitespace-nowrap text-xs text-muted-foreground-strong">Ordenar por<Select value={filtros.sort} onChange={e => cambiar({ sort: e.target.value })}><option value="prioridad">Pendientes primero</option><option value="fecha">Más antiguas primero</option><option value="reciente">Más recientes primero</option><option value="nombre">Prospecto A–Z</option></Select></label>}
          </div>
          {vista !== 'resultados' && <div className="flex flex-wrap items-center gap-2 pb-4" role="group" aria-label="Consultas rápidas por estado">
            <span className="mr-1 text-xs text-muted-foreground-strong">Ver por estado</span>{ATAJOS.map(estado => {
              const seleccionado = estado ? filtros.estados.includes(estado) : !filtros.estados.length
              const cantidad = estado ? sinEstado.filter(cita => cita.estado === estado).length : sinEstado.length
              return <Button key={estado} variant={seleccionado ? 'secondary' : 'outline'} size="sm" aria-pressed={seleccionado} onClick={() => cambiar({ estados: estado ? [estado] : [] })}>
                {estado ? ESTADOS[estado].short : 'Todas'} <span className="tabular-nums">{error ? '—' : cantidad}</span>
              </Button>
            })}
          </div>}
          <div id="citas-panel" role="tabpanel" aria-labelledby={'citas-tab-' + vista} tabIndex={0} className="outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent">
            {error || citas.length === 0 ? <div className="space-y-3 px-4 py-12 text-center">
              <SearchX aria-hidden className="mx-auto size-7 text-muted-foreground" /><h3 className="font-semibold">{error ? 'Revisa los filtros de la consulta' : 'No hay citas con esta combinación'}</h3>
              <p className="text-sm text-muted-foreground-strong">{error || 'Quita algún filtro o elige otro período.'}</p><Button variant="outline" onClick={restablecer}>Limpiar filtros</Button>
            </div> : vista === 'bandeja' ? <Bandeja citas={visibles} onDetalle={setDetalle} /> : vista === 'agenda' ? <Agenda citas={citas} onDetalle={setDetalle} />
              : <Resultados citas={citas} onAnalista={verAnalista} onDesglose={id => { setLeadAbierto(null); setDesglose(id) }} onDetalle={abrirCitaDelRecorrido} leadAbierto={leadAbierto} onLead={setLeadAbierto} />}
          </div>
          {vista === 'bandeja' && !error && citas.length > 0 && <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border py-3">
            <p className="text-xs text-muted-foreground-strong">Mostrando {(paginaActual - 1) * POR_PAGINA + 1}–{Math.min(paginaActual * POR_PAGINA, citas.length)} de {citas.length} citas</p>
            <div className="flex items-center gap-3"><Button variant="outline" size="icon" aria-label="Página anterior" disabled={paginaActual === 1} onClick={() => setPagina(paginaActual - 1)}><ChevronLeft aria-hidden /></Button><span className="text-xs">{paginaActual} de {paginas}</span><Button variant="outline" size="icon" aria-label="Página siguiente" disabled={paginaActual === paginas} onClick={() => setPagina(paginaActual + 1)}><ChevronRight aria-hidden /></Button></div>
          </div>}
        </section>
        <p role="status" aria-live="polite" className={exportacion ? 'citas-nota py-2' : 'sr-only'}>{exportacion || anuncio}</p>
      </main>
    </div>
    <Ficha cita={detalle} onCerrar={() => setDetalle(null)} onAnalista={verAnalistaDeFicha} onAgenda={verAgenda} />
    <DetalleLeads analista={desglose} citas={citas} onCerrar={() => setDesglose(null)} onLead={verLead} />
    <Guia abierta={guia} onCerrar={() => setGuia(false)} />
  </div>
}
