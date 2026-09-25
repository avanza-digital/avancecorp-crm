/* oxlint-disable jsx-a11y/no-redundant-roles -- Los roles conservan la tabla en WebKit cuando el diseño móvil cambia display. */
import { useCallback, useEffect, useId, useRef, useState, useSyncExternalStore } from 'react'
import { RefreshCw } from 'lucide-react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { horaLimaDe } from '@/lib/gestion-diaria-analista'
import { cifraPulso, diaPulsoValido, desplazarDia, type MetricasPulso, type PulsoGerencia } from '@/lib/gestion-diaria-pulso'
import { filtrarOrdenarEquipo, presentarEquipo, type FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
import { hashDe, leerHash } from '@/lib/router'
import { CrmApiError } from '@/data/crm-api'
import { usePulsoGerencia, useHabitosGerencia, useDetallePulso } from '@/data/gestion-diaria-pulso-queries'
import { TablaEquipoDiaria } from '@/components/gestion-diaria/tabla-equipo-diaria'
import { DetalleAnalista } from '@/components/gestion-diaria/detalle-analista'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
import { ReporteHabitos } from '@/components/gestion-diaria/reporte-habitos'
import { PanelCargando } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
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
const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
const fotoRuta = () => window.location.hash
const memoria = (actor: string) => `avancecorp:gestion-diaria:f5:dia:${actor}`
function diaRecordado(actor: string, hoy: string) {
  try { const dia = sessionStorage.getItem(memoria(actor)); return dia && diaPulsoValido(dia, hoy) ? dia : null } catch { return null }
}

export function GestionDiariaGerencia() {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  if (yo?.rol !== 'gerencia' || yo.demo) return <p role="alert">El pulso completo requiere una sesión de gerencia.</p>
  return <VistaGerencia key={yo.id} actor={yo.id} hoy={hoy} />
}

function ErrorConsulta({ error, recargar, enVuelo }: { error: unknown; recargar: () => Promise<void>; enVuelo: boolean }) {
  const denegada = error instanceof CrmApiError && error.code === '42501'
  return <div role="alert" className="gp-panel space-y-3">
    <p>{denegada ? 'Tu sesión ya no tiene permiso para consultar esta información.' : 'No pudimos confirmar las cifras. Esto no significa que no haya actividad; los datos anteriores se han ocultado.'}</p>
    <Button variant="outline" className="min-h-11 text-base" onClick={() => void recargar()} disabled={enVuelo}>Reintentar</Button>
  </div>
}

function VistaGerencia({ actor, hoy }: { actor: string; hoy: string }) {
  const [elegido, setElegido] = useState(() => diaRecordado(actor, hoy))
  const dia = elegido && diaPulsoValido(elegido, hoy) ? elegido : hoy
  const entrada = useRef<HTMLInputElement>(null)
  const [avisoFecha, setAvisoFecha] = useState('')
  const [pestana, setPestana] = useState<'pulso' | 'habitos'>('pulso')
  const [dias, setDias] = useState<7 | 14 | 30>(14)
  const [actualizacion, setActualizacion] = useState(0)
  useSyncExternalStore(suscribirRuta, fotoRuta)
  const detalleRuta = leerHash().detalleGestion
  const ruta = detalleRuta?.tipo === 'cola' ? undefined : detalleRuta
  const claveRuta = ruta ? `${ruta.tipo}:${ruta.id}` : null
  const ultimaRutaEnfocada = useRef<string | null>(null)
  useEffect(() => { if (claveRuta === null) ultimaRutaEnfocada.current = null }, [claveRuta])
  const enfocarDetalle = useCallback((titulo: HTMLHeadingElement | null) => {
    if (titulo && ultimaRutaEnfocada.current !== claveRuta) {
      ultimaRutaEnfocada.current = claveRuta
      titulo.focus()
    }
  }, [claveRuta])
  const activa = ruta ? 'pulso' : pestana
  const pulso = usePulsoGerencia(dia)
  const habitos = useHabitosGerencia(dia, dias, activa === 'habitos')
  const detalle = useDetallePulso(dia, Boolean(ruta) && pulso.datos !== null)
  const denegadaDetalle = detalle.error instanceof CrmApiError && detalle.error.code === '42501'
  const error = activa === 'habitos' ? habitos.error : pulso.error ?? (denegadaDetalle ? detalle.error : null)
  const consulta = activa === 'habitos' ? habitos : denegadaDetalle ? detalle : pulso
  const id = useId()
  useEffect(() => { if (entrada.current) entrada.current.value = dia }, [dia])
  const cambiarDia = (nuevo: string) => {
    if (!diaPulsoValido(nuevo, hoy)) {
      setAvisoFecha('Elige una fecha válida entre hoy y los últimos 365 días.')
      if (entrada.current) entrada.current.value = dia
      return
    }
    setElegido(nuevo === hoy ? null : nuevo); setAvisoFecha('')
    try { if (nuevo === hoy) sessionStorage.removeItem(memoria(actor)); else sessionStorage.setItem(memoria(actor), nuevo) } catch { /* Sesión sin almacenamiento: selección en memoria. */ }
  }
  const actualizar = async () => { await consulta.recargar(); if (ruta && !denegadaDetalle) await detalle.recargar(); setActualizacion((n) => n + 1) }
  return <section className="gd-pulso" aria-label="Toda la operación">
    <header className="gp-cabecera">
      <div><h2>¿Qué está pasando en la operación?</h2><p>{dia === hoy ? 'Hoy' : 'Día consultado'} · {dia} · Hora de Lima</p></div>
      <div className="gp-controles">
        <label htmlFor={`${id}-dia`}>Día</label><Input ref={entrada} id={`${id}-dia`} aria-label="Día de la operación" type="date" defaultValue={dia} min={desplazarDia(hoy, -365)} max={hoy} className="min-h-11 w-auto text-base" aria-describedby={avisoFecha ? `${id}-aviso` : undefined}
          onChange={() => setAvisoFecha('')}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); cambiarDia(e.currentTarget.value) } }} />
        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(entrada.current?.value ?? dia)}>Consultar</Button>
        <Button variant="outline" className="min-h-11 text-base" onClick={() => cambiarDia(hoy)} disabled={dia === hoy}>Hoy</Button>
        <Button variant="outline" className="min-h-11 text-base" aria-label="Actualizar operación" onClick={() => void actualizar()} disabled={consulta.enVuelo}><RefreshCw aria-hidden />Actualizar</Button>
      </div>
    </header>
    {avisoFecha && <p role="alert" id={`${id}-aviso`}>{avisoFecha}</p>}
    <Tabs etiqueta="Vistas de gerencia" tamano="grande" pestanas={PESTANAS} valor={activa} onCambio={(valor) => {
      setPestana(valor); if (ruta) window.location.hash = hashDe('gestion-diaria')
    }}>
      {activa === 'habitos' && <div className="gp-periodo"><label htmlFor={`${id}-periodo`}>Período hasta {dia}</label><Select id={`${id}-periodo`} className="min-h-11 text-base" value={dias} onChange={(e) => setDias(Number(e.target.value) as 7 | 14 | 30)}>{[7, 14, 30].map((n) => <option key={n} value={n}>{n} días calendario</option>)}</Select></div>}
      {error ? <ErrorConsulta error={error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} /> : consulta.cargando ? <PanelCargando filas={6} />
        : activa === 'habitos' ? habitos.datos && <ReporteHabitos key={`${dia}:${dias}`} datos={habitos.datos} alAbrirAnalista={() => setPestana('pulso')} />
          : pulso.datos && <>
            <ResumenPulso datos={pulso.datos} />
            <section className="gp-panel" aria-label="Equipos de la operación">
              <h3 className="text-lg font-semibold text-primary">Equipos y atención actual</h3>
              <p className="my-3">Organigrama actual · Pendientes consultados el {fechaLima(Date.parse(pulso.datos.pendientes_al))} a las {horaLimaDe(pulso.datos.pendientes_al)}. {pulso.datos.vencidas_global} tareas vencidas en total.</p>
              <div className="gp-tabla-scroll"><table role="table" className="gp-tabla" aria-label="Resumen por supervisor"><thead role="rowgroup"><tr role="row"><th role="columnheader" scope="col">Equipo</th><th role="columnheader" scope="col">Llamadas</th><th role="columnheader" scope="col">Contacto</th><th role="columnheader" scope="col">Sin actividad</th><th role="columnheader" scope="col">Vencidas</th><th role="columnheader" scope="col">Primer intento vencido</th><th role="columnheader" scope="col">Dispersión de contacto</th></tr></thead>
                <tbody role="rowgroup">{pulso.datos.equipos.map((e) => <tr role="row" key={e.clave}>
                  <th role="rowheader" scope="row"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: e.clave })}>{e.nombre}</a><p>{e.metricas.analistas_activos} analistas activos</p></th>
                  <td role="cell" data-etiqueta="Llamadas">{e.metricas.llamadas}</td><td role="cell" data-etiqueta="Contacto">{cifraPulso(e.metricas.tasa_contacto, true)}<p>{e.metricas.contestadas}/{e.metricas.utiles} útiles</p></td>
                  <td role="cell" data-etiqueta="Sin actividad">{e.metricas.sin_actividad}</td><td role="cell" data-etiqueta="Vencidas" className={e.tareas_vencidas ? 'text-[var(--danger-text)] font-semibold' : ''}>{e.tareas_vencidas}</td>
                  <td role="cell" data-etiqueta="Primer intento vencido">{cifraPulso(e.primer_intento_vencido)}{e.primer_intento_vencido === null && <p>SLA no activo</p>}</td>
                  <td role="cell" data-etiqueta="Dispersión">{e.dispersion.personas ? <>{cifraPulso(e.dispersion.minimo, true)}–{cifraPulso(e.dispersion.maximo, true)}<p>{e.dispersion.personas} con muestra</p></> : 'Muestra insuficiente'}</td>
                </tr>)}</tbody></table></div>
              <p className="mt-3">Dispersión: mínimo y máximo individual con al menos {pulso.datos.minimo_llamadas_utiles} llamadas útiles. Los leads distintos se deduplican en toda la operación; no se suman entre equipos.</p>
            </section>
            {ruta && <DesglosePulso key={`${dia}:${ruta.tipo}:${ruta.id}`} datos={pulso.datos} tipo={ruta.tipo} seleccion={ruta.id} consulta={detalle} actualizacion={actualizacion} enfocar={enfocarDetalle} />}
            <section id="gp-registro-general" className="gp-panel" aria-label="Registro general de la operación">
              <h3 className="mb-3 text-lg font-semibold text-primary" tabIndex={-1}>Registro general del día</h3>
              <RegistroActividad dia={dia} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar pestanaInicial="todo" actualizacion={actualizacion} />
            </section>
          </>}
    </Tabs>
  </section>
}

function ResumenPulso({ datos: d }: { datos: PulsoGerencia }) {
  return <section className="space-y-4" aria-label="Indicadores de la operación">
    <div className="gp-nota"><p>Comparación con <strong>{d.ayer.dia} completo</strong> y promedio de <strong>{d.referencia.cantidad} de 7 días con actividad</strong> anteriores. Personas y equipos corresponden al organigrama actual.</p>
      {d.dia === fechaLima(Date.parse(d.generado_en)) && <p>Hoy está en curso; las referencias son jornadas completas.</p>}
      <details><summary>Ver fechas y definiciones</summary><p>{d.referencia.dias.length ? d.referencia.dias.join(' · ') : `Sin jornadas con actividad desde ${d.referencia.busqueda_desde}.`}</p><p>Los recuentos muestran el promedio diario. La tasa de referencia reúne contestadas y útiles de {d.referencia.dias_con_tasa} días; llamadas por lead divide las llamadas por los leads distintos de cada día sumados. Sin actividad significa sin llamadas, WhatsApp enviado, reunión realizada, nota ni conversión; no indica ausencia.</p></details>
    </div>
    <dl className="gp-indicadores">{METRICAS.map((m) => <div key={m.campo}><dt>{m.titulo}</dt><dd>{cifraPulso(d.actual[m.campo], m.porcentaje)}</dd>
      <p>Anterior: {cifraPulso(d.ayer.metricas[m.campo], m.porcentaje)}</p><p>{m.campo === 'tasa_contacto' || m.campo === 'llamadas_por_lead' ? 'Referencia' : 'Promedio'}: {cifraPulso(d.referencia.media[m.campo], m.porcentaje)}</p>
    </div>)}</dl>
  </section>
}

function DesglosePulso({ datos, tipo, seleccion, consulta, actualizacion, enfocar }: { datos: PulsoGerencia; tipo: 'equipo' | 'analista'; seleccion: string; consulta: ReturnType<typeof useDetallePulso>; actualizacion: number; enfocar: (titulo: HTMLHeadingElement | null) => void }) {
  const grupo = datos.equipos.find((e) => tipo === 'equipo' ? e.clave === seleccion : e.personas.some((p) => p.analista_id === seleccion))
  const persona = tipo === 'analista' ? grupo?.personas.find((p) => p.analista_id === seleccion) : null
  const personas = tipo === 'equipo' ? grupo?.personas ?? [] : persona ? [persona] : []
  const ids = personas.flatMap((p) => p.analista_id === null ? [] : [p.analista_id])
  const filas = consulta.datos ? presentarEquipo(consulta.datos).filter((f) => ids.includes(f.analista_id)) : []
  const [filtros, setFiltros] = useState<FiltrosEquipo>({ busqueda: '', soloProblemas: false, orden: 'atencion', ascendente: false })
  const [registro, setRegistro] = useState(tipo === 'analista')
  const titulo = useRef<HTMLHeadingElement>(null)
  const registroRef = useRef<HTMLDivElement>(null)
  const id = useId()
  const disponible = Boolean(grupo) && (tipo !== 'analista' || Boolean(persona))
  useEffect(() => { enfocar(titulo.current) }, [enfocar])
  const nombre = persona ? persona.nombre_completo ?? 'Autor no disponible' : grupo?.nombre ?? 'Detalle no disponible'
  return <section className="gp-panel space-y-4" aria-label="Detalle de la operación" id={id}>
    <nav aria-label="Ruta de la operación" className="gp-ruta"><a href={hashDe('gestion-diaria')}>Toda la operación</a>{tipo === 'analista' && grupo && <><span aria-hidden> / </span><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'equipo', id: grupo.clave })}>{grupo.nombre}</a></>}</nav>
    <h3 ref={titulo} tabIndex={-1} className="text-xl font-semibold text-primary">{nombre}</h3>
    {!disponible ? <p role="status">Este equipo o autor ya no aparece en el ámbito actual. Vuelve a toda la operación.</p> : consulta.error ? <ErrorConsulta error={consulta.error} recargar={consulta.recargar} enVuelo={consulta.enVuelo} />
      : consulta.cargando ? <PanelCargando /> : <>
        {tipo === 'equipo' && <>
          <Input type="search" aria-label="Buscar analista del equipo" placeholder="Buscar analista" className="min-h-11 text-base" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} />
          <div className="gd-equipo"><TablaEquipoDiaria filas={filtrarOrdenarEquipo(filas, filtros)} filtros={filtros} ordenar={(orden) => setFiltros((f) => ({ ...f, orden, ascendente: f.orden === orden ? !f.ascendente : true }))} seleccion={null}
            seleccionar={(f) => { window.location.hash = hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: f.analista_id }) }} panelId={id} irAlDetalle={() => titulo.current?.focus()} minimo={datos.minimo_llamadas_utiles} /></div>
          {personas.some((p) => !p.activo) && <div><h4 className="font-semibold">Otros autores de los registros</h4><ul>{personas.filter((p) => !p.activo).map((p) => <li key={p.analista_id ?? 'sin-autor'}>{p.analista_id
            ? <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'analista', id: p.analista_id })}>{p.nombre_completo ?? 'Autor no disponible'}</a> : 'Sin autor'}: {p.llamadas} llamadas · {p.citas_agendadas} citas agendadas</li>)}</ul></div>}
        </>}
        {tipo === 'analista' && filas[0] && <DetalleAnalista fila={filas[0]} dia={datos.dia} abrirLlamadas={() => { setRegistro(true); registroRef.current?.scrollIntoView({ block: 'start' }); registroRef.current?.focus() }} />}
        {tipo === 'analista' && persona && !persona.activo && <p>Autor fuera del organigrama comercial activo: {persona.llamadas} llamadas, {persona.utiles} útiles, {persona.contestadas} contestadas.</p>}
        {tipo === 'analista' && persona?.activo && !filas.length && <p role="status">El analista ya no aparece en la consulta actual del equipo. Actualiza la operación para confirmar su ámbito.</p>}
        {personas.some((p) => p.analista_id === null) && <p>Los registros sin autor se consultan en el registro general del día que aparece a continuación.</p>}
        {tipo === 'equipo' && <Button variant="outline" className="min-h-11 text-base" onClick={() => setRegistro((v) => !v)} aria-expanded={registro}>{registro ? 'Ocultar registro del equipo' : 'Ver registro del equipo'}</Button>}
        {registro && ids.length > 0 && <div ref={registroRef} tabIndex={-1} className="space-y-3"><h4 className="font-semibold">Registro de {nombre}</h4><RegistroActividad dia={datos.dia} analistaIds={ids} mostrarAnalista permitirExportar pestanaInicial="llamadas" actualizacion={actualizacion} /></div>}
      </>}
  </section>
}
