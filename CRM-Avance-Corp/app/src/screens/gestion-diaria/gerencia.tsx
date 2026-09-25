import { useCallback, useEffect, useId, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
import { FileText, Info, RefreshCw } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso, diaPulsoValido, desplazarDia, type MetricasPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
import { hashDe, leerHash } from '@/lib/router'
import { CrmApiError } from '@/data/crm-api'
import { usePulsoGerencia, useHabitosGerencia, useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
import { EspacioPulsoGerencia } from '@/components/gestion-diaria/espacio-pulso-gerencia'
import { ErrorConsultaGerencia } from '@/components/gestion-diaria/error-consulta-gerencia'
import { usePanelGerencia } from '@/components/gestion-diaria/use-panel-gerencia'
import { ReporteHabitos } from '@/components/gestion-diaria/reporte-habitos'
import { PanelCargando } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Dialog, DialogHeader, DialogTitle, DialogBody } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Tabs } from '@/components/ui/tabs'
import './supervisor.css'
import './gerencia.css'

const METRICAS: { campo: keyof MetricasPulso; titulo: string; porcentaje?: boolean }[] = [
  { campo: 'llamadas', titulo: 'Llamadas' }, { campo: 'utiles', titulo: 'Llamadas útiles' },
  { campo: 'contestadas', titulo: 'Contestadas' }, { campo: 'tasa_contacto', titulo: 'Tasa de contacto', porcentaje: true },
  { campo: 'sin_actividad', titulo: 'Analistas sin actividad' }, { campo: 'leads_unicos', titulo: 'Leads distintos' },
  { campo: 'llamadas_por_lead', titulo: 'Llamadas por lead' }, { campo: 'citas_agendadas', titulo: 'Citas agendadas' },
]
const PESTANAS = [{ valor: 'pulso', etiqueta: 'Pulso diario' }, { valor: 'habitos', etiqueta: 'Hábitos del equipo' }] as const
const SIN_PERMISO = new CrmApiError('Permiso de gerencia revocado', '42501')
const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
const fotoRuta = () => window.location.hash
const memoria = (actor: string) => `avancecorp:gestion-diaria:f5:dia:${actor}`
function diaRecordado(actor: string, hoy: string) {
  try { const dia = sessionStorage.getItem(memoria(actor)); return dia && diaPulsoValido(dia, hoy) ? dia : null } catch { return null }
}

export function GestionDiariaGerencia({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode }) {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  if (yo?.rol !== 'gerencia' || yo.demo) return <p role="alert">El pulso completo requiere una sesión de gerencia.</p>
  return <VistaGerencia key={yo.id} actor={yo.id} hoy={hoy} accesoSeguimiento={accesoSeguimiento} />
}

function VistaGerencia({ actor, hoy, accesoSeguimiento }: { actor: string; hoy: string; accesoSeguimiento?: ReactNode }) {
  const [elegido, setElegido] = useState(() => diaRecordado(actor, hoy))
  const dia = elegido && diaPulsoValido(elegido, hoy) ? elegido : hoy
  const entrada = useRef<HTMLInputElement>(null)
  const pantalla = useRef<HTMLElement>(null)
  const { estrecho } = usePanelGerencia(pantalla)
  const [avisoFecha, setAvisoFecha] = useState('')
  const [pestana, setPestana] = useState<'pulso' | 'habitos'>('pulso')
  const [dias, setDias] = useState<7 | 14 | 30>(14)
  const [actualizacion, setActualizacion] = useState(0)
  const [general, setGeneral] = useState(false)
  const [revocada, setRevocada] = useState(false)
  const revocar = useCallback(() => setRevocada(true), [])
  const [panelOculto, setPanelOculto] = useState<string | null>(null)
  const botonRegistro = useRef<HTMLButtonElement>(null)
  useSyncExternalStore(suscribirRuta, fotoRuta)
  const detalleRuta = leerHash().detalleGestion
  const ruta = detalleRuta?.tipo === 'cola' ? undefined : detalleRuta
  const rutaEnfocada = useRef<string | null>(null)
  useEffect(() => { if (!ruta) rutaEnfocada.current = null }, [ruta])
  const activa = ruta ? 'pulso' : pestana
  const pulso = usePulsoGerencia(dia)
  const habitos = useHabitosGerencia(dia, dias, activa === 'habitos')
  const detalle = useDetallePulso(dia, Boolean(ruta) && pulso.datos !== null)
  // Una denegación en cualquier consulta retira toda la vista, aunque se cambie
  // de pestaña o se deshabilite después esa consulta. Revalidar sesión inicia
  // consultas nuevas, sin reutilizar la memoria paginada anterior.
  const sinPermiso = revocada || [pulso.error, detalle.error, habitos.error].some((e) => e instanceof CrmApiError && e.code === '42501')
  if (sinPermiso && !revocada) setRevocada(true)
  const error = sinPermiso ? SIN_PERMISO : activa === 'habitos' ? habitos.error : pulso.error
  const consulta = activa === 'habitos' ? habitos : pulso
  const id = useId()
  useEffect(() => { if (entrada.current) entrada.current.value = dia }, [dia])
  const cambiarDia = (nuevo: string) => {
    if (!diaPulsoValido(nuevo, hoy)) {
      setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.')
      if (entrada.current) entrada.current.value = dia
      return
    }
    setElegido(nuevo === hoy ? null : nuevo); setAvisoFecha(''); setGeneral(false)
    try { if (nuevo === hoy) sessionStorage.removeItem(memoria(actor)); else sessionStorage.setItem(memoria(actor), nuevo) } catch { /* Sesión sin almacenamiento: selección en memoria. */ }
  }
  const actualizar = async () => { await consulta.recargar(); if (ruta && !sinPermiso) await detalle.recargar(); setActualizacion((n) => n + 1) }
  return <section ref={pantalla} className="gd-pulso" data-estrecho={estrecho} aria-label="Toda la operación">
    <header className="gp-cabecera">
      <div><h2>Toda la operación</h2><p>{dia === hoy ? 'Hoy' : 'Día consultado'} · Hora de Lima</p></div>
      <div className="gp-controles">
        <label htmlFor={`${id}-dia`}>Día</label><Input ref={entrada} id={`${id}-dia`} aria-label="Día de la operación" type="date" defaultValue={dia} min={desplazarDia(hoy, -365)} max={hoy} className="min-h-11 w-auto text-base" aria-describedby={avisoFecha ? `${id}-aviso` : undefined}
          onChange={() => setAvisoFecha('')}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); cambiarDia(e.currentTarget.value) } }} />
        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(entrada.current?.value ?? dia)}>Consultar</Button>
        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(hoy)} disabled={dia === hoy}>Hoy</Button>
        <Button variant="outline" size="icon" className="size-11" aria-label="Actualizar operación" onClick={() => void actualizar()} disabled={consulta.enVuelo || sinPermiso}><RefreshCw aria-hidden /></Button>
      </div>
      <div className="gp-acciones">
        <Button ref={botonRegistro} variant="outline" className="min-h-11 text-base" onClick={() => { setPestana('pulso'); setGeneral(true) }} aria-pressed={general} disabled={Boolean(pulso.error || sinPermiso || !pulso.datos)}><FileText aria-hidden />Registro general</Button>
        {accesoSeguimiento}
      </div>
    </header>
    {avisoFecha && <p role="alert" id={`${id}-aviso`}>{avisoFecha}</p>}
    <Tabs etiqueta="Vistas de gerencia" className="gp-vistas" tamano="grande" pestanas={PESTANAS} valor={activa} onCambio={(valor) => {
      setPestana(valor); setGeneral(false); if (ruta) window.location.hash = hashDe('gestion-diaria')
    }}>
      {activa === 'habitos' && <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className="min-h-11 text-base" value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>}
      {error ? <ErrorConsultaGerencia error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando filas={6} />
        : activa === 'habitos' ? habitos.datos && <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} equipos={pulso.datos?.equipos ?? []} estrecho={estrecho} alAbrirAnalista={() => setPestana('pulso')} />
          : pulso.datos && <>
            <ResumenPulso datos={pulso.datos} />
            <EspacioPulsoGerencia key={dia} datos={pulso.datos} ruta={ruta} consulta={detalle} actualizacion={actualizacion} estrecho={estrecho}
              general={general} abrirGeneral={() => setGeneral(true)} cerrarGeneral={() => setGeneral(false)} rutaEnfocada={rutaEnfocada} oculto={panelOculto} setOculto={setPanelOculto} origenGeneral={botonRegistro} sinPermiso={revocar} />
            <p className="gp-pendientes">Organigrama actual · Pendientes al {fechaLima(Date.parse(pulso.datos.pendientes_al))}, {horaLimaDe(pulso.datos.pendientes_al)} · <strong>{pulso.datos.vencidas_global} tareas vencidas</strong> en total.</p>
          </>}
    </Tabs>
  </section>
}

function ResumenPulso({ datos: d }: { datos: PulsoGerencia }) {
  const [info, setInfo] = useState(false)
  return <section className="gp-resumen" aria-label="Indicadores de la operación">
    <dl className="gp-indicadores">{METRICAS.map((m) => <div key={m.campo}><dt>{m.titulo}</dt><dd>{cifraPulso(d.actual[m.campo], m.porcentaje)}</dd>
      <p>Anterior: <span>{cifraPulso(d.ayer.metricas[m.campo], m.porcentaje)}</span></p><p>{m.campo === 'tasa_contacto' || m.campo === 'llamadas_por_lead' ? 'Referencia' : 'Promedio'}: <span>{cifraPulso(d.referencia.media[m.campo], m.porcentaje)}</span></p>
    </div>)}</dl>
    <div className="gp-referencia"><p>Anterior: {d.ayer.dia} completo · Promedio: {d.referencia.cantidad} de 7 días con actividad.{d.dia === fechaLima(Date.parse(d.generado_en)) && ' Hoy en curso; referencias de jornadas completas.'}</p>
      <Button variant="ghost" className="min-h-11 text-base" onClick={() => setInfo(true)}><Info aria-hidden />Definiciones</Button></div>
    <Dialog open={info} onClose={() => setInfo(false)} className="gp-definiciones">
      <DialogHeader><DialogTitle>Fechas y definiciones del pulso</DialogTitle></DialogHeader>
      <DialogBody><div className="space-y-4 text-base">
        <p>Personas y equipos corresponden al organigrama actual.</p>
        <p>Referencia: {d.referencia.dias.length ? d.referencia.dias.join(' · ') : `Sin jornadas con actividad desde ${d.referencia.busqueda_desde}.`}</p>
        <p>Los recuentos muestran el promedio diario. La tasa de referencia reúne contestadas y útiles de {d.referencia.dias_con_tasa} días; llamadas por lead divide las llamadas por los leads distintos de cada día sumados.</p>
        <p>Sin actividad significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p>
        <p>Dispersión: mínimo y máximo individual con al menos {d.minimo_llamadas_utiles} llamadas útiles. Al ordenar, se compara la amplitud entre esos extremos.</p>
        <p>Los leads distintos se deduplican en toda la operación; no se suman entre equipos.</p>
        <p>Las tareas y el primer intento vencido se consultan en el momento actual, incluso al elegir un día pasado.</p>
        <Button variant="outline" className="min-h-11 text-base" onClick={() => setInfo(false)}>Cerrar definiciones</Button>
      </div></DialogBody>
    </Dialog>
  </section>
}
