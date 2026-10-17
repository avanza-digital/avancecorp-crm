import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'

// Destino fijo propio, sin parámetros de conexión ni destinos remotos.
let total = 0
for (const archivo of ['prueba.sql', 'prueba-legado.sql']) {
const sql = readFileSync(new URL(archivo, import.meta.url), 'utf8')
assert.ok(sql.trimEnd().endsWith('rollback;'), 'El banco debe terminar en rollback')
const resultado = spawnSync('docker', ['exec', '-i', 'avancecorp-tc-20261016',
  'psql', '-X', '-q', '-U', 'supabase_admin', '-d', 'tc_venta', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
{ input: sql, encoding: 'utf8', timeout: 120_000, maxBuffer: 2 * 1024 * 1024 })
if (resultado.error) throw resultado.error
if (resultado.status !== 0) {
  process.stderr.write(resultado.stderr ?? '')
  process.exit(resultado.status ?? 1)
}
const mensajes = (resultado.stderr ?? '').split('\n').filter((s) => s.includes('PASS:'))
for (const mensaje of mensajes) process.stdout.write(`${mensaje}\n`)
total += mensajes.length
}
console.log(`PASS: ${total} aserciones SQL de dominio/legado; transacciones revertidas`)
