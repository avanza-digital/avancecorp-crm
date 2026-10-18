// Auth y PostgREST reales, sin gateway/mocks, en el namespace SIN RED del banco.
// Las contraseñas son de prueba. No lee credenciales ni datos de otros bancos.
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { createHmac, randomBytes } from 'node:crypto'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

const contenedor = 'avancecorp-tc-20261016'
const db = `tc_venta_http_${process.pid}`
const rolAuth = `tc_http_auth_${process.pid}`
const rolRest = `tc_http_rest_${process.pid}`
const secreto = randomBytes(40).toString('hex')
const claveDb = randomBytes(24).toString('hex')
const claveUsuario = 'SoloLocalTC2026!'
const etiqueta = `tc-venta-http-${process.pid}`
const servicios = []
let creada = false
let rolesCreados = false
export const persona = n => `f1000000-0000-4000-8000-${String(n).padStart(12, '0')}`
export const contrato = n => `f2000000-0000-4000-8000-${String(n).padStart(12, '0')}`
function docker(args, opciones = {}) {
  const r = spawnSync('docker', args, { encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024, ...opciones })
  if (r.status !== 0) throw new Error(`Docker ${args[0]}: ${r.error?.code ?? r.status}; ${r.stderr?.slice(-1800) ?? ''}`)
  return r.stdout.trim()
}
export function sql(texto, base = db) {
  assert.ok([db, 'postgres'].includes(base))
  return docker(['exec', '-i', contenedor, 'psql', '-XqAt', '-U', 'supabase_admin', '-d', base,
    '-v', 'ON_ERROR_STOP=1', '-f', '-'], { input: texto, timeout: 120_000 })
}
function token(rol) {
  const cod = objeto => Buffer.from(JSON.stringify(objeto)).toString('base64url')
  const datos = `${cod({ alg: 'HS256', typ: 'JWT' })}.${cod({ role: rol, aud: 'authenticated',
    iss: 'tc-venta-local', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600 })}`
  return `${datos}.${createHmac('sha256', secreto).update(datos).digest('base64url')}`
}
export const servicio = token('service_role')
export const anonimo = token('anon')
const cliente = `${etiqueta}-cliente`
const consultar = `let entrada='';for await(const b of process.stdin)entrada+=b;
const p=JSON.parse(entrada);try{const r=await fetch(p.url,{method:p.method,headers:p.headers,
 ...(p.body===undefined?{}:{body:JSON.stringify(p.body)}),redirect:'error',signal:AbortSignal.timeout(20000)});
const t=await r.text();let data;try{data=JSON.parse(t)}catch{data=t}
process.stdout.write(JSON.stringify({status:r.status,ok:r.ok,data}));}catch(e){process.stdout.write(JSON.stringify({status:0,ok:false,data:e.code??'conexion'}))}`
export function http(ruta, { auth = anonimo, body, method = 'POST', esquema = 'crm' } = {}) {
  assert.match(ruta, /^\/(auth|rest)\//)
  const authApi = ruta.startsWith('/auth/')
  const path = ruta.slice(5)
  const url = `http://127.0.0.1:${authApi ? 9999 : 3000}${path}`
  return JSON.parse(docker(['exec', '-i', cliente, 'node', '--input-type=module', '-e', consultar], {
    input: JSON.stringify({ url, method, body, headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json',
      ...(!authApi ? { 'Accept-Profile': esquema, 'Content-Profile': esquema } : {}) } }),
  }))
}
export const rpc = (nombre, body, auth) => http(`/rest/rpc/${nombre}`, { body, auth })
export async function login(n) {
  const r = http('/auth/token?grant_type=password', { body: { email: `tc-http-${n}@example.test`, password: claveUsuario } })
  assert.equal(r.status, 200, `Login real ${n}: ${JSON.stringify(r.data)}`)
  assert.equal(r.data.user.id, persona(n))
  assert.equal(r.data.user.role, 'authenticated')
  return r.data.access_token
}
function iniciar(nombre, imagen, variables, comando) {
  const args = ['run', '-d', '--pull=never', '--name', nombre, '--label', `avancecorp.task=${etiqueta}`,
    '--network', `container:${contenedor}`, '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges=true']
  // Variables por entorno; nunca se imprimen conexiones ni JWT.
  for (const k of Object.keys(variables)) args.push('-e', k)
  args.push(imagen, ...comando)
  docker(args, { env: { ...process.env, ...variables } })
  servicios.push(nombre)
}
async function esperar(ruta) {
  for (let i=0;i<40;i++) {
    if (http(ruta, { method: 'GET' }).status === 200) return
    await new Promise(resolve => setTimeout(resolve, 250))
  }
  throw new Error(`No respondió ${ruta}`)
}
export async function preparar() {
  const banco = JSON.parse(docker(['inspect', contenedor]))[0]
  assert.equal(banco.HostConfig.NetworkMode, 'none')
  assert.deepEqual(banco.HostConfig.PortBindings ?? {}, {})
  assert.equal(sql("select count(*) from auth.users;", 'postgres'), '0')
  sql(`create database ${db} template tc_venta;`, 'postgres')
  creada = true
  sql(`begin; create role ${rolAuth} login inherit password '${claveDb}' in role supabase_auth_admin;
    alter role ${rolAuth} set search_path=auth;
    create role ${rolRest} login noinherit password '${claveDb}' in role authenticator; commit;`, 'postgres')
  rolesCreados = true
  const versiones = JSON.parse(readFileSync(new URL('auth-migraciones.json', import.meta.url), 'utf8')).versiones
  assert.ok(versiones.every(x => /^(00|\d{14})$/.test(x)))
  sql(`insert into auth.schema_migrations(version) values ${versiones.map(x=>`('${x}')`).join(',')};`)
  iniciar(cliente, 'mcr.microsoft.com/playwright:v1.61.1-noble', {}, ['node', '-e', 'setInterval(()=>{},1000)'])
  iniciar(`${etiqueta}-auth`, 'public.ecr.aws/supabase/gotrue:v2.196.0', {
    GOTRUE_DB_DRIVER: 'postgres', GOTRUE_DB_DATABASE_URL: `postgres://${rolAuth}:${claveDb}@127.0.0.1:5432/${db}?sslmode=disable`,
    GOTRUE_DB_NAMESPACE: 'auth', GOTRUE_JWT_SECRET: secreto, GOTRUE_JWT_AUD: 'authenticated', GOTRUE_JWT_EXP: '3600',
    GOTRUE_JWT_DEFAULT_GROUP_NAME: 'authenticated', GOTRUE_JWT_ADMIN_ROLES: 'service_role',
    GOTRUE_API_HOST: '127.0.0.1', GOTRUE_API_PORT: '9999', API_EXTERNAL_URL: 'http://127.0.0.1:9999',
    GOTRUE_SITE_URL: 'http://127.0.0.1:9999', GOTRUE_DISABLE_SIGNUP: 'true', GOTRUE_EXTERNAL_EMAIL_ENABLED: 'true',
    GOTRUE_SMTP_HOST: '127.0.0.1', GOTRUE_SMTP_PORT: '1',
  }, ['auth', 'serve'])
  await esperar('/auth/health')
  for (const n of [1,2,3,4,5,6,7,8,9,11,12]) {
    const r = http('/auth/admin/users', { auth: servicio, body: { id: persona(n), email: `tc-http-${n}@example.test`, password: claveUsuario, email_confirm: true } })
    assert.equal(r.status, 200, `Alta Auth ${n}: ${JSON.stringify(r.data)}`)
    assert.equal(r.data.id, persona(n))
  }
  let fixture = readFileSync(new URL('prueba-atribucion.sql', import.meta.url), 'utf8').split('-- @MIGRACION_OPERACIONES@')[0]
  fixture = fixture.replace("current_database()<>'tc_venta'", `current_database()<>'${db}'`)
    .replace('set local session_replication_role=replica;', 'set local session_replication_role=replica;\ndelete from public.perfiles;')
  const escritores = readFileSync(new URL('prueba-escritores.sql', import.meta.url), 'utf8')
    .split('select private.materializar_capital_valoraciones_para')[0]
    .replace(/insert into auth\.users[\s\S]*?from generate_series\(1,7\) i;/, '')
  const metas = readFileSync(new URL('prueba-cortes.sql', import.meta.url), 'utf8').split('create function pg_temp.evidencia')[0]
  sql(fixture + '\n' + nombres.map(cuerpoMigracion).join('\n') + '\n' + escritores + '\n' + metas + '\n' +
    readFileSync(new URL('fixture-http.sql', import.meta.url), 'utf8') + '\ncommit;')
  iniciar(`${etiqueta}-rest`, 'public.ecr.aws/supabase/postgrest:v16.2', {
    PGRST_DB_URI: `postgres://${rolRest}:${claveDb}@127.0.0.1:5432/${db}?sslmode=disable`,
    PGRST_DB_SCHEMAS: 'crm,public', PGRST_DB_ANON_ROLE: 'anon', PGRST_JWT_SECRET: secreto,
    PGRST_SERVER_HOST: '127.0.0.1', PGRST_SERVER_PORT: '3000', PGRST_LOG_LEVEL: 'error',
  }, [])
  await esperar('/rest/')
  const publico = sql("select md5(string_agg(pg_get_functiondef(oid),E'\\n' order by oid)) from pg_proc where pronamespace='public'::regnamespace and prokind='f';")
  console.log(`PASS: Auth/PostgREST reales; namespace sin red/puertos; public ${publico}`)
}
export function retirar() {
  for (const s of servicios.reverse()) {
    const datos = JSON.parse(docker(['inspect', s]))[0]
    assert.equal(datos.Config.Labels?.['avancecorp.task'], etiqueta)
    docker(['rm', '-f', s])
  }
  if (creada) sql(`drop database ${db} with(force);`, 'postgres')
  if (rolesCreados) sql(`drop role ${rolAuth},${rolRest};`, 'postgres')
}
export function diagnostico() {
  for (const s of servicios.filter(s => !s.endsWith('-cliente'))) {
    const lineas = docker(['logs', '--tail', '25', s]).split('\n')
    for (const linea of lineas) {
      try { const d=JSON.parse(linea); if (d.error) console.error(s, String(d.error).replace(/postgres(?:ql)?:\/\/[^@\s]+@/g,'postgres://[local]@')) } catch { /* No imprimir cuerpos HTTP ni credenciales. */ }
    }
  }
}
