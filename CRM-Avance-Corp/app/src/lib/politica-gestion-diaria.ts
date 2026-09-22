import * as v from 'valibot'

const Cantidad = v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(500))
const Porcentaje = v.pipe(v.number(), v.minValue(0), v.maxValue(100))
const Hora = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/))
const Instante = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s))))
const Version = v.pipe(v.number(), v.integer(), v.minValue(1))

export const PoliticaGestionDiariaSchema = v.pipe(v.strictObject({
  cortes_activos: v.boolean(),
  corte_1_hora: Hora,
  corte_1_minimo: Cantidad,
  corte_2_hora: Hora,
  corte_2_incremento_pct: v.pipe(v.number(), v.minValue(0), v.maxValue(1000)),
  corte_2_piso: Cantidad,
  corte_2_techo: Cantidad,
  sabado_minimo: Cantidad,
  bien_min_pct: Porcentaje,
  atencion_min_pct: Porcentaje,
  minimo_llamadas_utiles: Cantidad,
  tasa_baja_diferencia_pp: v.pipe(v.nullable(Porcentaje),
    v.check((valor) => valor === null, 'La alerta de tasa muy baja permanece apagada hasta F5')),
}), v.check((p) => p.corte_1_hora > '09:00' && p.corte_1_hora < '13:00'
  && p.corte_2_hora > p.corte_1_hora && p.corte_2_hora < '18:00'
  && p.corte_2_techo >= p.corte_2_piso && p.bien_min_pct > p.atencion_min_pct,
'Revisa las horas de la jornada, el piso/techo y los umbrales de contacto'))
export type PoliticaGestionDiaria = v.InferOutput<typeof PoliticaGestionDiariaSchema>

const RevisionSchema = v.strictObject({
  version: Version,
  vigente_desde: v.union([v.literal('-infinity'), Instante]),
  creado_en: Instante,
  creado_por: v.nullable(v.pipe(v.string(), v.uuid())),
  motivo: v.string(),
  configuracion: PoliticaGestionDiariaSchema,
})
export const ConfiguracionGestionDiariaSchema = v.pipe(v.strictObject({
  version: v.literal(1),
  dia: v.pipe(v.string(), v.isoDate()),
  zona: v.literal('America/Lima'),
  puede_editar: v.boolean(),
  expected_version: Version,
  vigente: RevisionSchema,
  revisiones_pendientes: v.array(RevisionSchema),
  historial: v.pipe(v.array(RevisionSchema), v.minLength(1)),
  control_avisos: v.strictObject({
    version: Version,
    habilitados: v.boolean(),
    motivo: v.string(),
    creado_por: v.nullable(v.pipe(v.string(), v.uuid())),
    creado_en: Instante,
  }),
}), v.check((r) => r.expected_version === Math.max(...r.historial.map((p) => p.version))
  && r.vigente.version <= r.expected_version
  && r.revisiones_pendientes.every((p) => p.version <= r.expected_version)
  && new Set(r.historial.map((p) => p.version)).size === r.historial.length,
'El historial de configuración no corresponde a su versión'))
export type ConfiguracionGestionDiaria = v.InferOutput<typeof ConfiguracionGestionDiariaSchema>

/** Ejemplo explicativo; los resultados reales siempre los calcula el servidor. */
export function ejemploSegundoCorte(base: number, p: PoliticaGestionDiaria) {
  const sinLimites = Math.ceil(base * (1 + p.corte_2_incremento_pct / 100))
  return { sinLimites, objetivo: Math.min(p.corte_2_techo, Math.max(p.corte_2_piso, sinLimites)) }
}

/** Una revisión programada se corrige con otra versión, nunca editando la anterior. */
export function ultimaRevision(config: ConfiguracionGestionDiaria) {
  return config.historial.find((p) => p.version === config.expected_version)!
}

/** Convierte medianoche Lima sin depender del huso ni del reloj del equipo. */
export function jornadaLimaIso(dia: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) throw new Error('Jornada inválida')
  const nominal = Date.parse(`${dia}T00:00:00Z`)
  if (!Number.isFinite(nominal) || new Date(nominal).toISOString().slice(0, 10) !== dia) throw new Error('Jornada inválida')
  const formato = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Lima',
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' })
  let instante = nominal
  for (let intento = 0; intento < 3; intento += 1) {
    const p = Object.fromEntries(formato.formatToParts(instante).map((parte) => [parte.type, parte.value]))
    const representado = Date.parse(`${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}Z`)
    if (representado === nominal) return new Date(instante).toISOString()
    instante += nominal - representado
  }
  throw new Error('No se pudo resolver el inicio de la jornada Lima')
}

export function desplazarJornada(dia: string, dias: number): string {
  return new Date(Date.parse(`${dia}T12:00:00Z`) + dias * 86_400_000).toISOString().slice(0, 10)
}
