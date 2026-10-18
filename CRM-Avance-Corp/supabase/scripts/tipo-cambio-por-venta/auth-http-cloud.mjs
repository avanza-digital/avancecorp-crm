// Adaptador de la MISMA matriz local a la rama temporal aprobada. Sus datos
// permanecen exclusivamente en esa rama, que se elimina después del gate.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const ref = 'ezkprhnvgwpjxoybhkxs'
const ruta = process.env.CRM_TC_BRANCH_CREDENTIALS
assert.ok(ruta, 'Falta el archivo privado de credenciales de la rama aprobada')
const cred = JSON.parse(readFileSync(ruta, 'utf8'))
assert.equal(cred.SUPABASE_URL, `https://${ref}.supabase.co`)
const destino = new URL(cred.POSTGRES_URL)
assert.ok(destino.hostname.includes(ref) || destino.username.includes(ref))
const entorno = { ...process.env }
for (const clave of Object.keys(entorno).filter((c) => c.startsWith('PG'))) delete entorno[clave]
Object.assign(entorno, { PGHOST: destino.hostname, PGPORT: destino.port || '5432',
  PGDATABASE: destino.pathname.slice(1), PGUSER: decodeURIComponent(destino.username),
  PGPASSWORD: decodeURIComponent(destino.password), PGSSLMODE: 'require',
  PGCONNECT_TIMEOUT: '8', PGAPPNAME: 'tc_venta_cloud_gate' })
export const persona = (n) => `f1000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export const contrato = (n) => `f2000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export const servicio = cred.SUPABASE_SERVICE_ROLE_KEY
export const anonimo = cred.SUPABASE_ANON_KEY
export function sql(texto) {
  // Un solo mensaje SQL evita miles de viajes de red durante la preparación.
  const r = spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql',
    ['-XqAt', '-v', 'ON_ERROR_STOP=1', '-c', texto],
    { env: entorno, encoding: 'utf8', timeout: 120_000, maxBuffer: 5e6 })
  if (r.error) throw new Error(`SQL de rama: ${r.error.code}`)
  assert.equal(r.status, 0, r.stderr)
  return r.stdout.trim()
}
const cliente = `let s='';for await(const b of process.stdin)s+=b;
const p=JSON.parse(s);try{const r=await fetch(p.url,{method:p.method,headers:p.headers,
...(p.body===undefined?{}:{body:JSON.stringify(p.body)}),redirect:'error',signal:AbortSignal.timeout(25000)});
const t=await r.text();let data;try{data=JSON.parse(t)}catch{data=t}
process.stdout.write(JSON.stringify({status:r.status,ok:r.ok,data}));}
catch(e){process.stdout.write(JSON.stringify({status:0,ok:false,data:e.code??'conexion'}))}`
export function http(ruta, { auth = anonimo, body, method = 'POST', esquema = 'crm' } = {}) {
  assert.match(ruta, /^\/(auth|rest)\//)
  const authApi = ruta.startsWith('/auth/')
  const entrada = { url: cred.SUPABASE_URL + (authApi ? '/auth/v1/' : '/rest/v1/') + ruta.slice(6),
    method, body, headers: { apikey: anonimo, Authorization: `Bearer ${auth}`,
      'Content-Type': 'application/json',
      ...(!authApi ? { 'Accept-Profile': esquema, 'Content-Profile': esquema } : {}) } }
  const r = spawnSync(process.execPath, ['--input-type=module', '-e', cliente],
    { input: JSON.stringify(entrada), encoding: 'utf8', timeout: 30_000, maxBuffer: 3e6 })
  if (r.error) throw new Error(`HTTP de rama: ${r.error.code}`)
  assert.equal(r.status, 0, 'Falló el cliente HTTP de pruebas')
  return JSON.parse(r.stdout)
}
export const rpc = (nombre, body, auth) => http(`/rest/rpc/${nombre}`, { body, auth })
const password = 'SoloBranchTC2026!'
export async function login(n) {
  const r = http('/auth/token?grant_type=password', { body: {
    email: `tc-http-${n}@example.test`, password,
  } })
  assert.equal(r.status, 200, `Login ficticio ${n}: HTTP ${r.status}`)
  assert.equal(r.data.user.id, persona(n))
  return r.data.access_token
}
export async function preparar() {
  if (process.env.CRM_TC_CLOUD_REANUDAR === 'fixture-inicial') {
    // Solo permite retomar el punto anterior a la primera corrección/F4.
    const ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12]
    assert.equal(sql('select count(*) from auth.users;'), '11')
    for (const n of ids) assert.equal(sql(`select email from auth.users where id='${persona(n)}';`), `tc-http-${n}@example.test`)
    assert.equal(sql('select count(*) from public.contratos;'), '8')
    assert.equal(sql(`select fecha_cierre_comercial::text from public.contratos where id='${contrato(2)}';`), '2026-10-02')
    assert.equal(sql('select count(*) from crm.periodos_cerrados;'), '0')
    console.log('PASS: retoma únicamente la fixture inicial sintética verificada')
    return
  }
  assert.equal(sql('select count(*) from auth.users;'), '0', 'No reutilizar una rama con usuarios')
  assert.equal(sql('select count(*) from public.perfiles;'), '0')
  assert.equal(sql('select count(*) from public.contratos;'), '0')
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12]) {
    const r = http('/auth/admin/users', { auth: servicio, body: { id: persona(n),
      email: `tc-http-${n}@example.test`, password, email_confirm: true } })
    assert.equal(r.status, 200, `Alta ficticia ${n}: HTTP ${r.status}`)
    assert.equal(r.data.id, persona(n))
  }
  let fixture = readFileSync(new URL('prueba-atribucion.sql', import.meta.url), 'utf8')
    .split('-- @MIGRACION_OPERACIONES@')[0]
  fixture = fixture.replace("current_database()<>'tc_venta'", "current_database()<>'postgres'")
    .replace('set local session_replication_role=replica;', 'set local session_replication_role=replica;\ndelete from public.perfiles;')
  const escritores = readFileSync(new URL('prueba-escritores.sql', import.meta.url), 'utf8')
    .split('select private.materializar_capital_valoraciones_para')[0]
    .replace(/insert into auth\.users[\s\S]*?from generate_series\(1,7\) i;/, '')
  const metas = readFileSync(new URL('prueba-cortes.sql', import.meta.url), 'utf8')
    .split('create function pg_temp.evidencia')[0]
  sql(fixture + '\n' + escritores + '\n' + metas + '\n'
    + readFileSync(new URL('fixture-http.sql', import.meta.url), 'utf8') + '\ncommit;\ndiscard temp;')
  console.log(`PASS: rama aprobada ${ref}; once cuentas ficticias; Auth/PostgREST cloud reales`)
}
export function retirar() {
  sql('discard temp;')
  console.log('La limpieza final elimina la rama temporal completa; no se elimina ningún usuario productivo')
}
export function diagnostico() {
  console.error('Gate cloud fallido: evidencia limitada a cuentas ficticias de la rama aprobada')
}
