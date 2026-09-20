// Gestión Diaria — wrapper que enruta por rol (mismo molde que screens/hoy.tsx).
// Fase 1 (19/09/2026): las tres vistas comparten la sección «Registro» del día;
// el analista ve el suyo, el supervisor su equipo y gerencia todo, con día a
// elegir y exportación. «Mi día», «Mi equipo hoy» y el pulso llegan en las
// fases 3–5 del plan (docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md).
import { useState, type JSX } from 'react'
import { useAuth } from '@/lib/auth-context'
import { useAhora } from '@/lib/ahora'
import { fechaLima } from '@/lib/agenda-derivada'
import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
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
  const diaValido = /^\d{4}-\d{2}-\d{2}$/.test(dia) && dia <= hoy ? dia : hoy

  if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />

  switch (yo.rol) {
    case 'vendedor':
      return (
        <div className="mx-auto w-full max-w-[1640px] space-y-6">
          <Cabecera pregunta="¿Qué hice hoy?" detalle="Tu registro de actividad de hoy, con el texto íntegro de cada gestión. La cola del día y el marcador llegan en la siguiente entrega." />
          <RegistroActividad dia={hoy} analistaIds={[yo.id]} mostrarAnalista={false} permitirExportar={false} />
        </div>
      )
    case 'supervisor':
      return (
        <div className="mx-auto w-full max-w-[1640px] space-y-6">
          <Cabecera pregunta="¿Qué está pasando hoy en mi equipo?" detalle="El registro de actividad de tu equipo, con el texto íntegro de cada llamada. Las alertas y la tabla del equipo llegan en la siguiente entrega." />
          <RegistroActividad dia={hoy} analistaIds={null} mostrarAnalista permitirExportar={false} />
        </div>
      )
    case 'gerencia':
      return (
        <div className="mx-auto w-full max-w-[1640px] space-y-6">
          <Cabecera pregunta="¿Qué está pasando hoy?" detalle="El registro de actividad de toda la operación, por equipo y por analista, exportable. El pulso del día llega en la siguiente entrega.">
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
