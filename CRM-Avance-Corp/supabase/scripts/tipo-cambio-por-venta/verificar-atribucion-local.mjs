import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'

let migracion = readFileSync(new URL('../../migrations/20261016201516_crm_capital_operaciones_compartidas.sql', import.meta.url), 'utf8')
assert.equal(migracion.split('\nbegin;').length, 2)
assert.ok(migracion.trimEnd().endsWith('commit;'))
migracion = migracion.replace('\nbegin;', '').replace(/commit;\s*$/, '')
assert.ok(!/^\s*commit;/m.test(migracion))
const prueba = readFileSync(new URL('prueba-atribucion.sql', import.meta.url), 'utf8')
assert.equal(prueba.split('-- @MIGRACION_OPERACIONES@').length, 2)
assert.ok(prueba.trimEnd().endsWith('rollback;'))
const resultado = spawnSync('docker', ['exec', '-i', 'avancecorp-tc-20261016',
  'psql', '-X', '-q', '-U', 'supabase_admin', '-d', 'tc_venta', '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
  input: prueba.replace('-- @MIGRACION_OPERACIONES@', () => migracion), encoding: 'utf8', timeout: 120_000,
  maxBuffer: 2 * 1024 * 1024,
})
if (resultado.error) throw resultado.error
if (resultado.status !== 0) { process.stderr.write(resultado.stderr ?? ''); process.exit(resultado.status ?? 1) }
const mensajes = (resultado.stderr ?? '').split('\n').filter((s) => s.includes('PASS:'))
for (const mensaje of mensajes) console.log(mensaje)
console.log(`PASS: ${mensajes.length} aserciones de atribución y comparación; rollback completo`)
