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
import { useState, type JSX } from 'react'
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

export function GestionDiaria(): JSX.Element {
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
      return <GestionDiariaSupervisor />
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
