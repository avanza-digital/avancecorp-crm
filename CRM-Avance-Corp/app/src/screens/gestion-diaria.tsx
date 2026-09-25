// Gestión Diaria — wrapper que enruta por rol (mismo molde que screens/hoy.tsx).
// Fase 1 (19/09/2026): las tres vistas comparten la sección «Registro» del día;
// el analista ve el suyo, el supervisor su equipo y gerencia todo, con día a
// elegir y exportación. «Mi día», «Mi equipo hoy» y el pulso llegan en las
// fases 4–5 del plan (docs/gestion-diaria/GESTION-DIARIA.md).
// Fase 3 (20/09/2026): el analista abre con «Mi día» — la cola completa, su
// marcador, sus compromisos y sus descartes — y conserva el registro debajo.
// Densidad (20/09/2026): el registro del propio analista («¿Qué hice hoy?») se
// pliega. Es memoria, no trabajo pendiente: releer el log propio no cambia a
// quién hay que llamar, y abierto duplicaba el largo de la pantalla.
import { useState, useSyncExternalStore, type JSX, type ReactNode } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
import { GestionDiariaAnalista } from '@/screens/gestion-diaria/analista'
import { GestionDiariaSupervisor } from '@/screens/gestion-diaria/supervisor'
import { GestionDiariaGerencia } from '@/screens/gestion-diaria/gerencia'
import { Plegable } from '@/components/gestion-diaria/plegable'
import { PanelVacio } from '@/components/common/estado-panel'
import { Input } from '@/components/ui/input'
import { CalendarCheck2 } from 'lucide-react'
import { ColaSeguimiento } from '@/components/app/cola-seguimiento'
import { hashDe, leerHash } from '@/lib/router'

const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
const fotoRuta = () => window.location.hash

/** Ambos accesos siguen vigentes hasta completar la observación productiva de F6. */
export function GestionDiaria(): JSX.Element {
  const { yo } = useAuth()
  useSyncExternalStore(suscribirRuta, fotoRuta)
  if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />
  if (yo.rol !== 'vendedor' && yo.rol !== 'supervisor' && yo.rol !== 'gerencia') {
    return <PanelVacio icono={CalendarCheck2} titulo="Gestión Diaria no está disponible para tu rol" detalle="Este módulo es para analistas, supervisores y gerencia." />
  }
  const cola = leerHash().detalleGestion?.tipo === 'cola'
  const cabeceraSupervisor = yo.rol === 'supervisor' && !cola
  const enlace = 'inline-flex min-h-11 items-center rounded-lg border px-4 py-2 text-base font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
  const accesoCola = <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} aria-current={cola ? 'page' : undefined} className={`${enlace} ${cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Seguimiento completo</a>
  return <div key={`${yo.id}:${yo.rol}:${yo.demo}`} className="mx-auto w-full max-w-[1640px] space-y-5">
    {!cabeceraSupervisor && <nav aria-label="Secciones de Gestión Diaria" className="flex flex-wrap gap-3">
      <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
      {accesoCola}
    </nav>}
    {cola ? <>
      <p className="text-base text-[var(--muted-foreground-strong)]">Pendientes actuales de tu ámbito. La fecha del resumen no cambia esta cola.</p>
      <ColaSeguimiento />
    </> : <ResumenGestionDiaria accesoSeguimiento={cabeceraSupervisor ? <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav> : undefined} />}
  </div>
}

function Cabecera({ pregunta, detalle, children }: { pregunta: string; detalle: string; children?: JSX.Element | undefined }) {
  return (
    <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h2 className="text-xl font-bold leading-tight text-primary">{pregunta}</h2>
        <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">{detalle}</p>
      </div>
      {children}
    </header>
  )
}

function ResumenGestionDiaria({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode }): JSX.Element {
  const { yo } = useAuth()
  const hoy = fechaLima(useAhora())
  const [dia, setDia] = useState(hoy)
  const [registroAbierto, setRegistroAbierto] = useState(false)
  const diaValido = /^\d{4}-\d{2}-\d{2}$/.test(dia) && dia <= hoy ? dia : hoy

  if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />

  switch (yo.rol) {
    case 'vendedor':
      // Fase 3: el analista entra a «Mi día» (cola, marcador, compromisos y
      // descartes). Su registro crudo sigue debajo, plegado.
      return (
        <div className="mx-auto w-full max-w-[1440px] space-y-6">
          <GestionDiariaAnalista />
          <Plegable titulo="¿Qué hice hoy?" resumen="tu registro del día" abierto={registroAbierto} onAbrir={setRegistroAbierto}>
            <RegistroActividad dia={hoy} analistaIds={[yo.id]} mostrarAnalista={false} permitirExportar={false} />
          </Plegable>
        </div>
      )
    case 'supervisor':
      return <GestionDiariaSupervisor accesoSeguimiento={accesoSeguimiento} />
    case 'gerencia':
      if (!yo.demo) return <GestionDiariaGerencia />
      return (
        <div className="mx-auto w-full max-w-[1640px] space-y-6">
          <Cabecera pregunta="¿Qué está pasando hoy?" detalle="Registro con datos ficticios del modo demo. El tablero completo y los hábitos consultan la operación desde una sesión real de gerencia.">
            <label className="flex items-center gap-2 text-xs font-semibold text-[var(--muted-foreground-strong)]">
              Día
              <Input type="date" value={dia} max={hoy} onChange={(e) => setDia(e.target.value)} className="w-auto" aria-label="Día del registro" />
            </label>
          </Cabecera>
          <RegistroActividad dia={diaValido} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar />
        </div>
      )
    default:
      // Directorio y coordinador no entran (vistas.ts lo impide); si llegan por
      // una sesión rara, se dice y no se fabrica nada.
      return <PanelVacio icono={CalendarCheck2} titulo="Gestión Diaria no está disponible para tu rol" detalle="Este módulo es para analistas, supervisores y gerencia." />
  }
}
