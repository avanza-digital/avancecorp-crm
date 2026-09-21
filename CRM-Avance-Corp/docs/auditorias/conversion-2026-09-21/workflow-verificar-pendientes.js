// Workflow de CONTINUACIÓN: verifica adversarialmente los hallazgos que la auditoría del
// 21/09 dejó sin contrastar (evidencia/hallazgos-pendientes-de-verificar.json).
// Uso desde Claude Code (Workflow tool), pasando el JSON como `args`:
//   Workflow({ scriptPath: "<esta ruta>", args: { hallazgos: <contenido del JSON>, severidades: ["P0","P1"] } })
// `severidades` es opcional (por defecto P0 y P1 → ~65 hallazgos × 3 lentes ≈ 195 agentes).
// Los scripts no leen disco: el JSON tiene que viajar en `args`. No usa Date.now() ni Math.random().
export const meta = {
  name: 'verificar-pendientes-conversion',
  description: 'Verificación adversarial (3 lentes) de los hallazgos pendientes de la auditoría de conversiones del 21/09',
  phases: [
    { title: 'Verificar', detail: '3 lentes por hallazgo: código, negocio, escenario real', model: 'opus' },
    { title: 'Completar', detail: 'crítico de completitud', model: 'opus' },
  ],
}

const REPO = '/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp'
const M = 'opus'

const CTX = `
CONTEXTO (léelo entero antes de abrir archivos)
Repo: ${REPO} (rutas relativas a esta carpeta salvo que empiecen por /). Portal hermano: ${REPO}/../public_html.
Eres un AUDITOR DE SOLO LECTURA: no edites, no crees archivos, no ejecutes migraciones ni SQL contra ninguna base. Usa Read/Grep/Glob (y el MCP codegraph vía ToolSearch si te sirve). Cada afirmación con archivo:línea y código citado literalmente.

OBJETIVO DEL DUEÑO (Miguel, gerencia): que el % de conversión y sus componentes que ve Gerencia sean verídicos, y que TODAS las pantallas de TODOS los roles beban de UN SOLO núcleo en el servidor. Ninguna pantalla ni RPC trae su propia fórmula. El front NUNCA divide ni recalcula; pinta el % servido; si una sonda falla avisa y oculta, jamás fabrica un 0. pct NULL (divisor 0) ≠ 0 %. >100 % legítimo, sin tope. Cada cifra responde al período visible; lo mensual se rotula mensual.

REGLA DE NEGOCIO VIGENTE (Miguel, 10/08, 26/08 y 04/09/2026):
- Núcleo: private.conversion_episodios emite filas 'recibido'|'cierre'|'operacion' con aporte_divisor/aporte_numerador. Los consumidores SUMAN aportes.
- Divisor = llegadas ÚNICAS automáticas Landing/Formulario por alta original (America/Lima), primer analista histórico. Referidos y altas manuales aportan 0 al divisor. Oficina/Otro fuera.
- Numerador = cierres del ledger crm.lead_asignaciones.resultado='convertido' (L/F ×1, Referido ×peso 0,15) + operaciones de cartera elegibles (1 por cliente/mes: renovación ×peso, upgrade ×1); anulados aportan 0; ajustes por anulación en mes sellado se descuentan en la lectura MENSUAL (private.conversion_con_ajuste), no en el núcleo.
- Foto mensual: crm.cerrar_periodo sella; crm.conversion_mensual_fn sirve la foto si cierre.cerrado.
- Cosecha («Resultados de los leads recibidos») y puntería (Distribución, D3) son lecturas legítimas distintas, con rótulo propio.

DEFINICIONES VIVAS (última migración que define cada función; el texto anterior está MUERTO):
private.conversion_episodios, private.conversion_mensual_por_vendedor, crm.conversion_mensual_sin_cartera_fn, crm.metricas_conversiones_equipo_fn, private.metricas_distribucion_leads_v3_core, crm.cerrar_periodo → supabase/migrations/20260904210831_crm_conversion_llegadas_unicas.sql
private.metricas_conversiones_implementacion → supabase/migrations/20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql (L2145+)
crm.metricas_conversiones_fn → 20260828003205 · crm.conversion_mensual_fn, crm.cumplimiento_metas_fn → 20260902202247 · crm.metricas_vendedores_fn → 20260828173154 · crm.metricas_distribucion_leads_v3_fn → 20260827090000 · private.metricas_reuniones_implementacion → 20260907194622 · private.citas_gerencia_consulta → 20260913225755 PARCHEADA EN SITIO por 20260914044939 y 20260915170018 · private.conversion_cierres → 20260912151320 · private.capital_episodios → 20260908211349 · public.metricas_directorio/directorio_ranking_analistas → 20260901180000 · public.dashboard_admin_metricas → 20260902201000 · private.conversion_con_ajuste → 20260815002100 · private.ajuste_pendiente_por_vendedor → 20260815002100.
Para cualquier otra función: grep -l "function <esquema>.<nombre>" supabase/migrations/*.sql | sort | tail -1.
`

const VERDICT = {
  type: 'object',
  properties: {
    refutado: { type: 'boolean' },
    confianza: { type: 'string', enum: ['alta', 'media', 'baja'] },
    razon: { type: 'string' },
    evidencia: { type: 'string' },
    severidad_ajustada: { type: 'string', enum: ['P0', 'P1', 'P2', 'P3'] },
  },
  required: ['refutado', 'confianza', 'razon', 'evidencia', 'severidad_ajustada'],
}

const LENTES = [
  { key: 'correctitud', prompt: 'LENTE CORRECTITUD DEL CÓDIGO: abre el archivo citado, lee ±80 líneas y las funciones/hook/RPC que invoca (sigue la cadena hasta el SQL vivo si hace falta). ¿Existe el código tal como se cita? ¿Hace lo que el hallazgo afirma? ¿Hay una guarda o eslabón posterior que lo neutraliza? Si no puedes CONFIRMAR con el archivo abierto, refutado=true.' },
  { key: 'negocio', prompt: 'LENTE NEGOCIO: con las reglas de Miguel del contexto, ¿esto es de verdad un problema para la veracidad de lo que ve Gerencia, o es un comportamiento DECIDIDO y ya rotulado correctamente en pantalla? Refuta si es decisión legítima con rótulo presente (compruébalo abriendo la pantalla). Ajusta la severidad al impacto real sobre gerencia.' },
  { key: 'impacto', prompt: 'LENTE ESCENARIO REAL: ¿puede materializarse en producción con datos reales de este negocio (~90 leads/mes por analista, referidos escasos, upgrades/renovaciones, reasignaciones, meses sin sellar, filtros de rango parcial y de origen)? Construye un escenario concreto con números. Busca si un test existente ya lo cubre (grep en app/src/**/*.test.ts(x) y supabase/scripts/test-*.sql). Si no hay escenario realista o está cubierto por un test que pasa, refutado=true.' },
]

const norm = s => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
const todos = (args && args.hallazgos) || []
const sevs = (args && args.severidades) || ['P0', 'P1']
const pendientes = todos.filter(h => sevs.includes(h.severidad))
log(`Hallazgos recibidos: ${todos.length} · a verificar (${sevs.join('/')}): ${pendientes.length}`)
if (pendientes.length === 0) return { error: 'args.hallazgos vacío o sin las severidades pedidas', recibidos: todos.length }

phase('Verificar')
const verificados = await pipeline(
  pendientes,
  h => parallel(LENTES.map(l => () => agent(
    `${CTX}\n\nERES UN VERIFICADOR ADVERSARIAL. Tu trabajo es intentar REFUTAR este hallazgo. Por defecto refutado=true si no puedes confirmarlo.\n\nHALLAZGO A REFUTAR:\n${JSON.stringify({ titulo: h.titulo, severidad: h.severidad, capa: h.capa, archivo: h.archivo, lineas: h.lineas, evidencia: h.evidencia, impacto_gerencia: h.impacto_gerencia, es_hipotesis: h.es_hipotesis, correccion_sugerida: h.correccion_sugerida, fuente: h.fuente }, null, 2)}\n\n${l.prompt}\n\nDevuelve refutado, confianza, razon (3-6 líneas), evidencia (código literal con archivo:línea que sostiene TU veredicto) y severidad_ajustada.`,
    { label: `verificar:${l.key}:${norm(h.titulo).slice(0, 28)}`, phase: 'Verificar', schema: VERDICT, model: M },
  ))).then(vs => {
    const votos = vs.filter(Boolean)
    const refutaciones = votos.filter(v => v.refutado).length
    const sobrevive = votos.length >= 2 && refutaciones < 2
    const sev = votos.filter(v => !v.refutado).map(v => v.severidad_ajustada).sort()[0] || h.severidad
    return { ...h, sobrevive, votos: votos.map((v, i) => ({ lente: LENTES[i] ? LENTES[i].key : '?', ...v })), severidad_final: sev }
  }),
)
const confirmados = verificados.filter(Boolean).filter(v => v.sobrevive)
const refutados = verificados.filter(Boolean).filter(v => !v.sobrevive)
log(`Confirmados: ${confirmados.length} · Refutados: ${refutados.length}`)

phase('Completar')
const critico = await agent(
  `${CTX}\n\nERES EL CRÍTICO DE COMPLETITUD. Te doy los hallazgos confirmados de la auditoría de conversiones. Di qué FALTA para afirmar «lo que ve gerencia es verídico y todo sale de un núcleo»: funciones SQL vivas que publican conversión/cierres/clientes y no aparecen (haz un grep real: grep -l -i "conversion\\|convertido" supabase/migrations/*.sql, aplica la regla de última definición), superficies sin trazar, comprobaciones que solo pueden hacerse contra PRODUCCIÓN (paridad M=R=V=D) y que ningún gate ejecuta. Verifica cada faltante abriendo el archivo.\n\nCONFIRMADOS:\n${confirmados.map(c => `- [${c.severidad_final}] ${c.titulo} (${c.archivo}:${c.lineas})`).join('\n')}`,
  { label: 'critico-completitud', phase: 'Completar', model: M, schema: {
    type: 'object', properties: {
      faltantes: { type: 'array', items: { type: 'object', properties: {
        tema: { type: 'string' }, prioridad: { type: 'string', enum: ['alta', 'media', 'baja'] },
        por_que_falta: { type: 'string' }, archivos: { type: 'string' }, como_cerrarlo: { type: 'string' } },
        required: ['tema', 'prioridad', 'por_que_falta', 'archivos', 'como_cerrarlo'] } },
      veredicto_global: { type: 'string' },
    }, required: ['faltantes', 'veredicto_global'] } },
)

return { confirmados, refutados, critico }
