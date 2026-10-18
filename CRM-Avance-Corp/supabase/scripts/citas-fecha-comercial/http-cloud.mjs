// Matriz HTTP sobre la rama exclusiva de publicación; nunca apunta a producción.
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'

const ref = 'wtmbakkjaihlflpfoxkm'
assert.ok(process.env.CITAS_BRANCH_CREDENTIALS, 'Faltan credenciales privadas del banco autorizado')
const cred = JSON.parse(readFileSync(process.env.CITAS_BRANCH_CREDENTIALS, 'utf8'))
assert.equal(cred.SUPABASE_URL, `https://${ref}.supabase.co`)
const pruebas = []
const id = n => `92000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const password = 'SoloBancoCitas2026!'
async function http(ruta, { token = cred.SUPABASE_ANON_KEY, body, method = 'POST' } = {}) {
  assert.match(ruta, /^\/(auth|rest)\/v1\//)
  const r = await fetch(cred.SUPABASE_URL + ruta, {
    method, redirect: 'error', signal: AbortSignal.timeout(30_000),
    headers: { apikey: cred.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json', ...(ruta.startsWith('/rest/')
        ? { 'Accept-Profile': 'crm', 'Content-Profile': 'crm' } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })
  return { status: r.status, data: await r.json() }
}
function comprobar(ok, nombre) {
  assert.ok(ok, nombre)
  pruebas.push(nombre)
  console.log('PASS:', nombre)
}
const sesiones = new Map()
for (let n = 1; n <= 7; n++) {
  const email = `citas-publicacion-${n}@example.test`
  if (!process.argv.includes('--reanudar')) {
    const alta = await http('/auth/v1/admin/users', { token: cred.SUPABASE_SERVICE_ROLE_KEY,
      body: { id: id(n), email, password, email_confirm: true } })
    comprobar(alta.status === 200 && alta.data.id === id(n), `Cuenta sintética ${n} en rama propia`)
  }
  const login = await http('/auth/v1/token?grant_type=password', { body: { email, password } })
  comprobar(login.status === 200 && login.data.user?.id === id(n), `Sesión Auth real ${n}`)
  sesiones.set(n, login.data.access_token)
}
for (const rpc of ['citas_gerencia_consulta_fn', 'citas_gerencia_consulta_v2_fn']) {
  for (const mes of ['09', '10']) {
    const body = { p_desde: `2026-${mes}-01`, p_hasta: `2026-${mes}-${mes === '09' ? '30' : '31'}` }
    for (const n of [1, 2, 4]) {
      const r = await http(`/rest/v1/rpc/${rpc}`, { token: sesiones.get(n), body })
      comprobar(r.status === 200 && r.data.criterio_depositos === 'fecha_comercial', `${rpc} ${mes}: lectura comercial rol ${n}`)
      if (process.env.CITAS_VALORADO === '1' && rpc.endsWith('_v2_fn') && mes === '10') {
        comprobar(Boolean(r.data.gestion.valoracion?.corte_id), `${rpc} ${mes}: consulta por corte valorado rol ${n}`)
        comprobar(r.data.gestion.capital.every(k => k.equivalente_pen === k.monto && k.tasa === 1
          && k.fecha_comercial === '2026-10-01'), `${rpc} ${mes}: conserva importes PEN por operación rol ${n}`)
      }
      const cierres = r.data.gestion.conversiones
      if (n === 1) {
        comprobar(r.data.testigo.comercial.clientes_periodo === (mes === '09' ? 4 : 1), `${rpc} ${mes}: testigo comercial concilia`)
        comprobar(r.data.testigo.clientes_periodo === (mes === '09' ? 0 : 5), `${rpc} ${mes}: testigo anterior compatible`)
      } else {
        comprobar(!('testigo' in r.data), `${rpc} ${mes}: supervisor ${n} sin total global`)
        const permitidos = n === 2 ? mes === '09' ? [201, 202, 203, 205, 206] : [202, 205, 206]
          : mes === '09' ? [204] : []
        comprobar(cierres.length === permitidos.length && cierres.every(c => permitidos.some(lead => c.lead_id === id(lead))
          && (c.analista_id === id(n === 2 ? 3 : 5) || (c.analista_id === null && c.fecha_comercial === null))),
        `${rpc} ${mes}: supervisor ${n} conserva su ámbito, incluido su lead sin venta acreditada`)
      }
      comprobar(cierres.every(c => Object.hasOwn(c, 'fecha_comercial') && c.convertido_en.startsWith('2026-10-06')),
        `${rpc} ${mes}: fecha comercial y registro separados, rol ${n}`)
      const fechas = new Map([[201, '2026-09-01'], [202, '2026-09-05'], [203, '2026-09-14'],
        [204, '2026-09-21'], [205, '2026-10-01'], [206, null]].map(([lead, fecha]) => [id(lead), fecha]))
      comprobar([...cierres, ...r.data.conversiones].every(c => fechas.has(c.lead_id) && c.fecha_comercial === fechas.get(c.lead_id)),
        `${rpc} ${mes}: fechas exactas y ausencia de fecha en fuentes no acreditadas, rol ${n}`)
      if (process.env.CITAS_EVIDENCIA) writeFileSync(`${process.env.CITAS_EVIDENCIA}/cloud-${rpc}-${mes}-${n}.json`, JSON.stringify(r.data))
    }
    for (const n of [3, 6, 7]) {
      const r = await http(`/rest/v1/rpc/${rpc}`, { token: sesiones.get(n), body })
      comprobar([401, 403].includes(r.status), `${rpc} ${mes}: acceso denegado rol ${n}`)
    }
    const anon = await http(`/rest/v1/rpc/${rpc}`, { body })
    comprobar([401, 403].includes(anon.status), `${rpc} ${mes}: anónimo denegado`)
  }
}
if (process.env.CITAS_EVIDENCIA) writeFileSync(`${process.env.CITAS_EVIDENCIA}/rls-cloud.json`,
  JSON.stringify({ resultado: 'PASS', rama: ref, aserciones: pruebas.length, pruebas }, null, 2))
console.log(`PASS: ${pruebas.length} aserciones Auth/PostgREST; cuentas y datos solo en rama temporal`)
