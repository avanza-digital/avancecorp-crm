// Sesiones Auth y PostgREST reales, exclusivamente en la rama temporal autorizada.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const ref = 'buacdmufspxktdfdllte'
assert.ok(process.env.CRM_CAPITAL_BRANCH_CREDENTIALS, 'Falta el archivo privado de la rama')
const cred = JSON.parse(readFileSync(process.env.CRM_CAPITAL_BRANCH_CREDENTIALS, 'utf8'))
assert.equal(cred.SUPABASE_URL, `https://${ref}.supabase.co`)
const destino = new URL(cred.POSTGRES_URL)
assert.ok(destino.hostname.includes(ref) || destino.username.endsWith(`.${ref}`))
assert.ok(!destino.href.includes('dctqcbznekcyxhjujuci'))
const entorno = { ...process.env }
for (const clave of Object.keys(entorno).filter(c => c.startsWith('PG'))) delete entorno[clave]
Object.assign(entorno, { PGHOST: destino.hostname, PGPORT: destino.port || '5432',
  PGDATABASE: destino.pathname.slice(1), PGUSER: decodeURIComponent(destino.username),
  PGPASSWORD: decodeURIComponent(destino.password), PGSSLMODE: 'require',
  PGCONNECT_TIMEOUT: '10', PGAPPNAME: 'capital_pendientes_http' })
function sql(texto) {
  const r = spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql', ['-XqAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
    { input: texto, env: entorno, encoding: 'utf8', timeout: 120_000, maxBuffer: 5e6 })
  assert.ifError(r.error)
  assert.equal(r.status, 0, r.stderr)
  return r.stdout.trim()
}
const id = n => `f3000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const email = n => `capital-pendientes-${n}@example.test`
const password = 'SoloBranchCapital2026!'
async function http(ruta, { auth = cred.SUPABASE_ANON_KEY, body, method = 'POST' } = {}) {
  assert.match(ruta, /^\/(auth|rest)\/v1\//)
  const r = await fetch(cred.SUPABASE_URL + ruta, { method, redirect: 'error', signal: AbortSignal.timeout(30_000),
    headers: { apikey: cred.SUPABASE_ANON_KEY, Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json',
      ...(ruta.startsWith('/rest/') ? { 'Accept-Profile': 'crm', 'Content-Profile': 'crm' } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) })
  const texto = await r.text()
  let data
  try { data = JSON.parse(texto) } catch { data = texto }
  return { status: r.status, data }
}
const rpc = (nombre, body, auth) => http(`/rest/v1/rpc/${nombre}`, { body, auth })
let comprobaciones = 0
function pasa(mensaje) { comprobaciones++; console.log(`PASS: ${mensaje}`) }
function exito(r) { assert.equal(r.status, 200, `HTTP ${r.status}: ${JSON.stringify(r.data)}`); return r.data }

assert.equal(sql('select count(*) from cron.job where active;'), '0', 'El banco no debe ejecutar cron')
if (process.env.CRM_CAPITAL_HTTP_REANUDAR === 'fixture-inicial') {
  assert.equal(sql('select count(*) from auth.users;'), '7')
  for (let n = 1; n <= 7; n++) assert.equal(sql(`select email from auth.users where id='${id(n)}';`), email(n))
  assert.equal(sql('select count(*) from public.contratos;'), '3')
  assert.equal(sql('select count(*) from crm.tipo_cambio_diario;'), '0')
} else {
  assert.equal(sql('select count(*) from auth.users;'), '0')
  assert.equal(sql('select count(*) from public.perfiles;'), '0')
  assert.equal(sql('select count(*) from public.contratos;'), '0')
  for (let n = 1; n <= 7; n++) {
    const r = await http('/auth/v1/admin/users', { auth: cred.SUPABASE_SERVICE_ROLE_KEY,
      body: { id: id(n), email: email(n), password, email_confirm: true } })
    assert.equal(exito(r).id, id(n))
  }
  let fixture = readFileSync(new URL('prueba.sql', import.meta.url), 'utf8')
    .split('-- El total del detalle incluye todas las páginas')[0]
  // La misma fixture SQL, después de crear las cuentas con la puerta oficial Auth.
  fixture = fixture.replace(/do \$\$ begin[\s\S]*?end \$\$;/, '')
    .replace(/insert into auth\.users[\s\S]*?from generate_series\(1,7\) n;/, 'delete from public.perfiles;')
  assert.ok(!fixture.includes('insert into auth.users'))
  sql(fixture + '\ncommit;\ndiscard temp;')
}
pasa('rama exclusiva vacía, siete cuentas sintéticas creadas con Auth oficial')
const sesiones = {}
for (const n of [1, 2, 3, 5, 6]) {
  const r = exito(await http('/auth/v1/token?grant_type=password', { body: { email: email(n), password } }))
  assert.equal(r.user.id, id(n))
  sesiones[n] = r.access_token
}
pasa('cinco sesiones reales de supervisor, analista, gerencia y equipo ajeno')
const args = { p_periodo: '2026-10-01', p_vendedor_id: id(2) }
const detalle = exito(await rpc('capital_operaciones_valoradas_v2_fn', args, sesiones[2]))
assert.equal(detalle.total_pen, 6000)
assert.equal(detalle.operaciones.length, 2)
assert.deepEqual(detalle.cobertura.pendientes, { cantidad: 1, pen: 0, usd: 20000 })
assert.deepEqual(detalle.cobertura.ventas_pendientes.map(v => [v.fuente_id, v.moneda, v.monto, v.fecha_comercial]),
  [[id(202), 'USD', 20000, '2026-10-23']])
pasa('analista: ambos PEN suman 6000; USD 20000 separado con fuente y fecha')
const { cobertura, ...anterior } = detalle
assert.deepEqual(exito(await rpc('capital_operaciones_valoradas_fn', args, sesiones[2])), anterior)
pasa('v1 mantiene exactamente su contrato de respuesta')
for (const n of [1, 3]) {
  assert.deepEqual(exito(await rpc('capital_operaciones_valoradas_v2_fn', args, sesiones[n])), detalle)
}
pasa('supervisor del equipo y gerencia pueden consultar el mismo analista')
for (const n of [5, 6]) {
  const r = await rpc('capital_operaciones_valoradas_v2_fn', args, sesiones[n])
  assert.equal(r.status, 403)
  assert.equal(r.data.code, '42501')
}
pasa('supervisor y analista ajenos reciben 403 sin datos del vendedor')
for (const auth of [cred.SUPABASE_ANON_KEY, cred.SUPABASE_SERVICE_ROLE_KEY]) {
  const r = await rpc('capital_operaciones_valoradas_v2_fn', args, auth)
  assert.ok([401, 403, 404].includes(r.status), `RPC cerrada: HTTP ${r.status}`)
  assert.ok(!r.data.operaciones && !r.data.cobertura)
}
pasa('anon y service_role no ejecutan la nueva puerta autenticada')
const global = await http('/rest/v1/capital_cortes_valorados?select=id&limit=1', { auth: sesiones[2], method: 'GET' })
assert.equal(global.status, 403)
pasa('el analista no puede leer directamente las fotos globales')
const metas = exito(await rpc('cumplimiento_metas_v2_fn', { p_periodo: '2026-10-01' }, sesiones[2]))
assert.equal(metas.capital_valoracion.personas[0].capital_valorado.equivalente_pen, 6000)
assert.equal(metas.capital_valoracion.cobertura.pendientes.usd, 20000)
pasa('metas HTTP mantiene 6000 PEN y el pendiente en su ámbito')
const cuadro = exito(await rpc('facturacion_diaria_v2_fn', { p_mes: '2026-10-01' }, sesiones[1]))
const lista = exito(await rpc('listar_operaciones_facturacion_v3_fn', {
  p_desde: '2026-10-23', p_hasta: '2026-10-23', p_cortes: { '2026-10-01': cuadro.corte_id },
}, sesiones[1]))
assert.equal(cuadro.filas.reduce((s, f) => s + f.capital_equivalente_pen, 0), 6000)
assert.equal(lista.totales_por_mes.reduce((s, f) => s + f.equivalente_pen, 0), 6000)
pasa('Facturación HTTP: lista y cuadro usan el mismo corte y suman 6000 PEN')

const prueba = readFileSync(new URL('prueba.sql', import.meta.url), 'utf8')
const tc = prueba.slice(prueba.indexOf('select private.consolidar_tc_venta('), prueba.indexOf("insert into cortes select 'valorado'"))
sql(tc)
const valorado = exito(await rpc('capital_operaciones_valoradas_v2_fn', args, sesiones[2]))
assert.notEqual(valorado.corte_id, detalle.corte_id)
assert.equal(valorado.total_pen, 74000)
assert.equal(valorado.operaciones.length, 3)
assert.deepEqual(valorado.cobertura.ventas_pendientes, [])
assert.equal(valorado.cobertura.pendientes.cantidad, 0)
pasa('tras TC, el analista recibe una revisión nueva con 74000 PEN y sin pendientes')
sql('select crm.reconciliar_capital_valoraciones_fn(200);')
assert.equal(exito(await rpc('capital_operaciones_valoradas_v2_fn', args, sesiones[2])).corte_id, valorado.corte_id)
pasa('otra corrida sin cambios conserva el mismo corte a través de PostgREST')
console.log(`PASS: ${comprobaciones} comprobaciones HTTP; datos exclusivamente sintéticos en ${ref}`)
console.log('Limpieza prevista: eliminar la rama temporal completa al terminar la verificación.')
