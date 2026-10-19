/** Cómo se lee el rango de la Proyección: por semanas o por días. */
export type VistaProyeccionEnlace = 'semanas' | 'dias'

/** Contexto de lectura del Resumen; nunca concede permisos sobre un equipo. */
export type ConsultaCitasEnlace = (
  | { dia: string; mes?: never; semana?: never; desde?: never; hasta?: never; vista?: never }
  | { mes: string; dia?: never; semana?: string; desde?: never; hasta?: never; vista?: never }
  | { desde: string; hasta: string; vista?: VistaProyeccionEnlace; dia?: never; mes?: never; semana?: never }
) & { equipo?: string }

/** El rango de la Proyección; el tope de meses lo aplica la pantalla, no el enlace. */
export type ConsultaProyeccionEnlace = Extract<ConsultaCitasEnlace, { desde: string }>

const VISTAS_PROYECCION: readonly string[] = ['semanas', 'dias'] satisfies VistaProyeccionEnlace[]
const EQUIPO_CITAS = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|d-[a-z0-9-]{1,60}|sin_supervisor)$/i

export function esConsultaProyeccion(consulta: ConsultaCitasEnlace | undefined): consulta is ConsultaProyeccionEnlace {
  return consulta?.desde !== undefined
}

export function mesConsultaCitas(consulta: ConsultaCitasEnlace): string {
  if (esConsultaProyeccion(consulta)) return consulta.hasta.slice(0, 7)
  return consulta.dia ? consulta.dia.slice(0, 7) : consulta.mes!
}

export function diaCitasValido(dia: string): boolean {
  const instante = Date.parse(`${dia}T12:00:00Z`)
  return /^\d{4}-\d{2}-\d{2}$/.test(dia) && Number.isFinite(instante)
    && new Date(instante).toISOString().startsWith(dia)
}

export function consultaCitasValida(consulta: ConsultaCitasEnlace | undefined): consulta is ConsultaCitasEnlace {
  if (!consulta) return false
  // Una variante nunca arrastra campos de otra: el enlace solo significa una cosa.
  const periodoValido = esConsultaProyeccion(consulta)
    ? consulta.dia === undefined && consulta.mes === undefined && consulta.semana === undefined
      && diaCitasValido(consulta.desde) && diaCitasValido(consulta.hasta) && consulta.desde <= consulta.hasta
      && (consulta.vista === undefined || VISTAS_PROYECCION.includes(consulta.vista))
    : consulta.hasta === undefined && consulta.vista === undefined && (consulta.dia ? diaCitasValido(consulta.dia)
      : !!consulta.mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(consulta.mes)
        && (consulta.semana === undefined || /^[1-4]$/.test(consulta.semana)))
  return periodoValido && (consulta.equipo === undefined || EQUIPO_CITAS.test(consulta.equipo))
}
