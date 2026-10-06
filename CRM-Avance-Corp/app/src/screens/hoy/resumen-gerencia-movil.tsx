import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { ArrowUpRight, CalendarDays, ChevronRight, Clock3, FileClock, Target, Wallet } from 'lucide-react'
import { Dialog, DialogBody, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { useSolicitudesTasa } from '@/data/crm-queries'
import { rotuloTipoCambio, type CapitalUnificado } from '@/lib/capital-unificado'
import { escribirHash, hashDe, leerHash } from '@/lib/router'
import { money, primerNombre } from '@/lib/format'
import { useDatosCitasGerencia } from './use-datos-citas-gerencia'
import { resumirCitasDia } from './resumen-gerencia-movil-modelo'
import { SolicitudesTasaGerenciaPanel } from './solicitudes-tasa-gerencia'
import { PendientesGerenciaMovil } from './pendientes-gerencia-movil'
import './resumen-gerencia-movil.css'

interface Props {
  dia: string
  mes: string
  capital: CapitalUnificado
  meta: CapitalUnificado
  fuenteTc: string
  cargando: boolean
  error: string | null
  onReintentar: () => void
  onActualizar: () => void
  onMetas: () => void
  onCompleto: () => void
  aviso: ReactNode
}

function EstadoConsulta({ cargando, error, onReintentar }: { cargando: boolean; error: string | null; onReintentar: () => void }) {
  if (error) return <div role="alert" className="grm-error"><p>{error}</p><Button variant="outline" size="sm" onClick={onReintentar}>Reintentar</Button></div>
  return cargando ? <p role="status" className="grm-estado">Cargando…</p> : null
}

export function ResumenGerenciaMovil({ dia, mes, capital, meta, fuenteTc, cargando, error, onReintentar, onActualizar, onMetas, onCompleto, aviso }: Props) {
  const { yo, datos, citas, consulta, equipo } = useDatosCitasGerencia(dia.slice(0, 7))
  const nombre = primerNombre(yo?.nombre_completo)
  const real = Boolean(yo && !yo.demo)
  const solicitudes = useSolicitudesTasa(['pendiente'], real, 45_000)
  const [bandeja, setBandeja] = useState(() => Boolean(leerHash().solicitudTasaId))
  const [enLinea, setEnLinea] = useState(() => navigator.onLine)
  const resumen = useMemo(() => resumirCitasDia(citas, dia, equipo), [citas, dia, equipo])
  const errorCitas = real && consulta.isError ? 'No se pudieron actualizar las citas.' : null
  const citasDisponibles = datos != null && !errorCitas
  const pendientes = real && solicitudes.data != null && !solicitudes.isError
    ? solicitudes.data.filter(s => s.puede_resolver).length : null
  const finanzasDisponibles = !cargando && !error && capital.total !== null
  const sinTc = ((capital.usd ?? 0) > 0 || (meta.usd ?? 0) > 0) && capital.tc === null
  const progreso = finanzasDisponibles && !sinTc && meta.total != null && meta.total > 0
    ? capital.total! / meta.total * 100 : null
  const enlaceCitas = (id?: string) => hashDe('reuniones', null, undefined, undefined, undefined, undefined, { dia, ...(id ? { equipo: id } : {}) })
  // Los listeners permanecen estables aunque los lectores cambien su resultado.
  const refrescar = useRef(() => {})
  useEffect(() => {
    refrescar.current = () => {
      if (!real) return
      onActualizar()
      // Citas y solicitudes ya se revalidan con sus propios intervalos/foco.
    }
  }, [real, onActualizar])
  useEffect(() => {
    let ultima = 0
    const actualizar = () => {
      setEnLinea(navigator.onLine)
      if (document.visibilityState !== 'visible' || !navigator.onLine || Date.now() - ultima < 1_000) return
      ultima = Date.now()
      refrescar.current()
    }
    const recibirEnlace = () => { if (leerHash().solicitudTasaId) setBandeja(true) }
    const temporizador = window.setInterval(actualizar, 60_000)
    window.addEventListener('focus', actualizar)
    window.addEventListener('online', actualizar)
    window.addEventListener('offline', actualizar)
    window.addEventListener('hashchange', recibirEnlace)
    document.addEventListener('visibilitychange', actualizar)
    return () => {
      window.clearInterval(temporizador)
      window.removeEventListener('focus', actualizar)
      window.removeEventListener('online', actualizar)
      window.removeEventListener('offline', actualizar)
      window.removeEventListener('hashchange', recibirEnlace)
      document.removeEventListener('visibilitychange', actualizar)
    }
  }, [])
  const cerrarBandeja = () => {
    setBandeja(false)
    if (leerHash().solicitudTasaId) escribirHash('hoy', null, true)
  }

  return <div className="gerencia-inteligencia grm-resumen" data-testid="resumen-gerencia-movil">
    {yo?.demo && <div className="grm-preview-note">Modo demo · datos de ejemplo</div>}
    {!enLinea && <p role="status" className="grm-preview-note">Sin conexión · los datos pueden estar desactualizados.</p>}
    <header className="grm-intro">
      <p>{new Intl.DateTimeFormat('es-PE', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Lima' }).format(new Date(`${dia}T12:00:00Z`)).toLocaleUpperCase('es-PE')}</p>
      <h2 id="grm-titulo" tabIndex={-1}>Bienvenido{nombre ? `, ${nombre}` : ''}</h2><span>Tu equipo, de un vistazo.</span>
    </header>
    {aviso}
    <section aria-label="Indicadores principales" className="grm-indicadores">
      <button type="button" className="grm-capital" onClick={onMetas}>
        <span className="grm-card-label"><Wallet size={17} aria-hidden />Capital confirmado<ArrowUpRight size={17} aria-hidden /></span>
        <strong>{finanzasDisponibles ? money(capital.total!) : '—'}</strong>
        <span className="grm-capital-foot">{mes} · a la fecha <span>{sinTc ? 'Solo soles · falta TC' : 'En soles'}</span></span>
        {finanzasDisponibles && ((capital.usd ?? 0) > 0 || (meta.usd ?? 0) > 0) && <span className="grm-tc">{capital.tc === null ? `${money(capital.usd ?? 0, 'USD')} sin convertir` : rotuloTipoCambio(capital.tc, fuenteTc)}</span>}
      </button>
      <button type="button" className="grm-meta" onClick={onMetas}>
        <span className="grm-meta-heading"><span><Target size={17} aria-hidden />Meta de capital</span><strong>{progreso === null ? '—' : `${progreso.toLocaleString('es-PE', { maximumFractionDigits: 1 })}%`}</strong></span>
        <span className="grm-progress" aria-hidden><span style={{ width: `${Math.min(100, Math.max(0, progreso ?? 0))}%` }} /></span>
        <span className="grm-meta-foot">{!finanzasDisponibles ? 'Meta no disponible' : sinTc ? 'Falta el tipo de cambio para comparar' : meta.total === 0 ? 'Sin meta de capital configurada' : `Objetivo: ${meta.total === null ? '—' : money(meta.total)}`}<ChevronRight size={15} aria-hidden /></span>
      </button>
      <EstadoConsulta cargando={cargando} error={error} onReintentar={onReintentar} />
      {sinTc && !cargando && !error && <EstadoConsulta cargando={false} error="Tipo de cambio no disponible. Los dólares no se incluyen en el total." onReintentar={onReintentar} />}
      <div className="grm-two-cards">
        <a href={enlaceCitas()} className="grm-small-card">
          <span className="grm-small-label"><CalendarDays size={17} aria-hidden />Citas de hoy</span>
          <span className="grm-small-value">{citasDisponibles ? resumen.total : '—'}<ChevronRight size={17} aria-hidden /></span>
          <span className="grm-small-foot">{citasDisponibles ? `${resumen.realizadas} realizadas · todos los estados` : 'Consulta pendiente'}</span>
        </a>
        <button type="button" className="grm-small-card grm-pendientes" onClick={() => setBandeja(true)}>
          <span className="grm-small-label"><FileClock size={17} aria-hidden />Solicitudes</span>
          <span className="grm-small-value">{pendientes ?? '—'}<ChevronRight size={17} aria-hidden /></span>
          <span className="grm-small-foot">{real ? 'Tasas pendientes de tu revisión' : 'Sin solicitudes en modo demo'}</span>
        </button>
      </div>
      <EstadoConsulta cargando={real && solicitudes.isPending} error={real && solicitudes.isError ? 'No se pudieron actualizar las solicitudes.' : null} onReintentar={() => { void solicitudes.refetch() }} />
    </section>
    {pendientes !== null && pendientes > 0 && <section className="grm-atencion" aria-labelledby="grm-atencion-title">
      <div className="grm-section-heading"><h3 id="grm-atencion-title">Necesita tu atención</h3><span>{pendientes}</span></div>
      <button type="button" className="grm-action" onClick={() => setBandeja(true)}><span className="grm-action-icon"><Clock3 size={19} aria-hidden /></span><span><strong>{pendientes} {pendientes === 1 ? 'tasa por revisar' : 'tasas por revisar'}</strong><small>Abrir la bandeja de solicitudes.</small></span><ChevronRight size={18} aria-hidden /></button>
    </section>}
    <section className="grm-equipos" aria-labelledby="grm-equipos-title">
      <div className="grm-section-heading"><h3 id="grm-equipos-title">Citas por equipo</h3><span className="grm-hoy">Hoy</span></div>
      <EstadoConsulta cargando={real && consulta.isPending} error={errorCitas} onReintentar={() => { void consulta.refetch() }} />
      {citasDisponibles && <div className="grm-equipos-lista">{resumen.equipos.map(grupo => <a key={grupo.id} href={enlaceCitas(grupo.id)} className="grm-equipo" aria-label={`${grupo.nombre}: ${grupo.total} ${grupo.total === 1 ? 'cita' : 'citas'} de hoy. Ir a Citas`}><span>{grupo.nombre}</span><strong>{grupo.total}</strong><ChevronRight size={16} aria-hidden /></a>)}{resumen.equipos.length === 0 && <p className="grm-estado">Sin equipos ni citas para hoy.</p>}</div>}
      <p className="grm-estado">Citas de leads · hora de Lima.</p>
    </section>
    <PendientesGerenciaMovil />
    <button type="button" onClick={onCompleto} className="grm-full">Abrir el resumen completo<ArrowUpRight size={16} aria-hidden /></button>
    <Dialog open={bandeja} onClose={cerrarBandeja} className="grm-dialog">
      <DialogHeader><DialogTitle>Solicitudes de tasa</DialogTitle></DialogHeader>
      <DialogBody>{real ? <SolicitudesTasaGerenciaPanel /> : <p>Las solicitudes y sus decisiones están disponibles al iniciar sesión con tu cuenta.</p>}</DialogBody>
      <DialogFooter><Button variant="outline" onClick={cerrarBandeja}>Volver al resumen</Button></DialogFooter>
    </Dialog>
  </div>
}
