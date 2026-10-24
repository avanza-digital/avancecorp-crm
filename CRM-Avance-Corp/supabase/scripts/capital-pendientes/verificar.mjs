// Banco propio; jamás acepta una conexión productiva ni reutiliza una base con datos.
import assert from 'node:assert/strict'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const argumentos = new Set(process.argv.slice(2))
assert.ok([...argumentos].every((a) => ['--local', '--rama', '--fixtures', '--repetir-tras-http'].includes(a)))
assert.notEqual(argumentos.has('--local'), argumentos.has('--rama'), 'Elige --local o --rama')
const rama = 'buacdmufspxktdfdllte'
const local = argumentos.has('--local')
const entorno = { ...process.env }
for (const clave of Object.keys(entorno).filter((c) => c.startsWith('PG'))) delete entorno[clave]
let comando = 'docker'
let args = ['exec', '-i', 'avancecorp-capital-banco-20261023', 'psql', '-XqAt', '-U', 'supabase_admin', '-d', 'postgres']
if (!local) {
  assert.ok(process.env.CRM_CAPITAL_BRANCH_CREDENTIALS, 'Falta archivo privado de la rama autorizada')
  const credenciales = JSON.parse(readFileSync(process.env.CRM_CAPITAL_BRANCH_CREDENTIALS, 'utf8'))
  assert.equal(credenciales.SUPABASE_URL, `https://${rama}.supabase.co`)
  const destino = new URL(credenciales.POSTGRES_URL)
  assert.ok(destino.hostname.includes(rama) || destino.username.endsWith(`.${rama}`))
  assert.ok(!destino.href.includes('dctqcbznekcyxhjujuci'))
  Object.assign(entorno, { PGHOST: destino.hostname, PGPORT: destino.port || '5432', PGDATABASE: destino.pathname.slice(1),
    PGUSER: decodeURIComponent(destino.username), PGPASSWORD: decodeURIComponent(destino.password),
    PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '10', PGAPPNAME: 'capital_pendientes_pruebas' })
  comando = '/opt/homebrew/opt/postgresql@17/bin/psql'
  args = ['-XqAt']
}
let sql = readFileSync(new URL('prueba.sql', import.meta.url), 'utf8')
assert.ok(sql.trimEnd().endsWith('rollback;'))
if (argumentos.has('--repetir-tras-http')) {
  assert.ok(!local, 'La repetición tras HTTP solo aplica a la rama autorizada')
  sql = readFileSync(new URL('repetir-tras-http.sql', import.meta.url), 'utf8') + sql.replace(/^begin;$/m, '')
}
const resultado = spawnSync(comando, [...args, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
  input: sql, env: entorno, encoding: 'utf8', timeout: 180_000, maxBuffer: 10e6,
})
const carpeta = new URL(`../../../output/capital-pendientes/${local ? 'local' : 'rama'}/`, import.meta.url)
mkdirSync(carpeta, { recursive: true })
writeFileSync(new URL('prueba.log', carpeta), resultado.stderr ?? '')
assert.ifError(resultado.error)
assert.equal(resultado.status, 0, resultado.stderr)
const mensajes = resultado.stderr.split('\n').filter((l) => l.includes('PASS:'))
assert.ok(mensajes.length >= 26, 'Falta la evidencia de las aserciones ejecutadas')
for (let caso = 1; caso <= 5; caso++) assert.ok(mensajes.some((l) => l.includes(`TEST ${caso}:`)), `Falta el Test ${caso}`)
for (const mensaje of mensajes) console.log(mensaje)
console.log(`PASS: ${mensajes.length} aserciones; rollback completo; destino ${local ? 'Docker propio' : rama}`)
if (argumentos.has('--fixtures')) {
  const fixtures = resultado.stdout.split('\n').filter((l) => l.startsWith('{'))
    .map((l) => JSON.parse(l)).filter((r) => r.capital_fixture)
  assert.deepEqual(fixtures.map((r) => r.capital_fixture).sort(),
    ['activo', 'detalle-activo', 'detalle-pendiente', 'facturacion-pendiente', 'lista-pendiente', 'pendiente'])
  const destino = new URL('../../../app/test-fixtures/capital-pendientes/', import.meta.url)
  mkdirSync(destino, { recursive: true })
  for (const fixture of fixtures) writeFileSync(new URL(`${fixture.capital_fixture}.json`, destino), JSON.stringify(fixture.payload, null, 2) + '\n')
  console.log('PASS: seis fixtures sintéticos generados por las RPC nativas')
}
