// Gestión Diaria — wrapper que enruta por rol (mismo molde que screens/hoy.tsx).
// Fase 1 (19/09/2026): las tres vistas comparten la sección «Registro» del día;
// el analista ve el suyo, el supervisor su equipo y gerencia todo, con día a
// elegir y exportación. «Mi día», «Mi equipo hoy» y el pulso llegan en las
// fases 4–5 del plan (docs/gestion-diaria/GESTION-DIARIA.md).
// Fase 3 (20/09/2026): el analista abre con «Mi día» — la cola completa, su
// marcador, sus compromisos y sus descartes — y conserva el registro debajo.
// Diseño (27/09/2026): el registro del propio analista («¿Qué hice hoy?») vive
// ahora DENTRO de «Mi día», en su pestaña «Mi actividad», y la navegación entre
// «Resumen del día» y «Seguimiento completo» sube a su cabecera (misma ruta y
// `aria-current` de siempre), como ya hacían supervisor y gerencia.
import { useState, useSyncExternalStore, type JSX, type ReactNode } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
import { GestionDiariaAnalista } from '@/screens/gestion-diaria/analista'
import { GestionDiariaSupervisor } from '@/screens/gestion-diaria/supervisor'
import { GestionDiariaGerencia } from '@/screens/gestion-diaria/gerencia'
import { PanelVacio } from '@/components/common/estado-panel'
import { Input } from '@/components/ui/input'
import { CalendarCheck2, ChevronRight } from 'lucide-react'
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
  const cabeceraIntegrada = (yo.rol === 'vendedor' || yo.rol === 'supervisor' || (yo.rol === 'gerencia' && !yo.demo)) && !cola
  const enlace = 'inline-flex min-h-11 items-center rounded-lg border px-4 py-2 text-base font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
  const accesoCola = <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} aria-current={cola ? 'page' : undefined} className={`${enlace} ${cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Seguimiento completo</a>
  const secciones = <nav aria-label="Secciones de Gestión Diaria" className="flex flex-wrap gap-3">
    <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
    {accesoCola}
  </nav>
  // El analista y el supervisor llevan a su cabecera un solo botón compacto, como
  // el «Mi Hoy completo ›» del diseño (27/09/2026): la cabecera no puede pesar
  // más que la pregunta. La vuelta al resumen sigue en la barra de secciones de
  // la cola, con su `aria-current`. Gerencia conserva su acceso hasta su plan.
  const integrada = yo.rol === 'vendedor' || yo.rol === 'supervisor'
    ? <nav aria-label="Secciones de Gestión Diaria"><a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} className="inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:border-border-strong hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring pointer-coarse:h-11">Seguimiento completo<ChevronRight aria-hidden className="size-4" /></a></nav>
    : <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav>
  return <div key={`${yo.id}:${yo.rol}:${yo.demo}`} className="mx-auto w-full max-w-[1640px] space-y-5">
    {!cabeceraIntegrada && secciones}
    {cola ? <>
      <p className="text-base text-[var(--muted-foreground-strong)]">Pendientes actuales de tu ámbito. La fecha del resumen no cambia esta cola.</p>
      <ColaSeguimiento />
    </> : <ResumenGestionDiaria accesoSeguimiento={cabeceraIntegrada ? integrada : undefined} />}
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
  const diaValido = /^\d{4}-\d{2}-\d{2}$/.test(dia) && dia <= hoy ? dia : hoy

  if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />

  switch (yo.rol) {
    case 'vendedor':
      // «Mi día»: cola, cifras, compromisos, descartes y su registro del día
      // (pestaña «Mi actividad»), todo dentro de la misma pantalla.
      return <GestionDiariaAnalista accesoSeguimiento={accesoSeguimiento} />
    case 'supervisor':
      return <GestionDiariaSupervisor accesoSeguimiento={accesoSeguimiento} />
    case 'gerencia':
      if (!yo.demo) return <GestionDiariaGerencia accesoSeguimiento={accesoSeguimiento} />
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
