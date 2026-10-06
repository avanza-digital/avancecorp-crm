/** Contexto de lectura del Resumen; nunca concede permisos sobre un equipo. */
export type ConsultaCitasEnlace = (
  | { dia: string; mes?: never; semana?: never }
  | { mes: string; dia?: never; semana?: string }
) & { equipo?: string }

export function mesConsultaCitas(consulta: ConsultaCitasEnlace): string {
  return consulta.dia ? consulta.dia.slice(0, 7) : consulta.mes!
}

export function diaCitasValido(dia: string): boolean {
  const instante = Date.parse(`${dia}T12:00:00Z`)
  return /^\d{4}-\d{2}-\d{2}$/.test(dia) && Number.isFinite(instante)
    && new Date(instante).toISOString().startsWith(dia)
}

export function consultaCitasValida(consulta: ConsultaCitasEnlace | undefined): consulta is ConsultaCitasEnlace {
  const periodoValido = consulta?.dia ? diaCitasValido(consulta.dia)
    : !!consulta?.mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(consulta.mes)
      && (consulta.semana === undefined || /^[1-4]$/.test(consulta.semana))
  return !!consulta && periodoValido && (consulta.equipo === undefined
    || /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|d-[a-z0-9-]{1,60}|sin_supervisor)$/i.test(consulta.equipo))
}
