import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
for (const archivo of ['index.ts', 'handler.ts', 'transporte.ts']) {
  test(`la Edge publicada y la copia CRM coinciden: ${archivo}`, () => {
    const crm = readFileSync(new URL(`../../functions/crm-notificaciones-tasa/${archivo}`, import.meta.url))
    const espejo = readFileSync(new URL(`../../../../_supabase_functions/functions/crm-notificaciones-tasa/${archivo}`, import.meta.url))
    assert.deepEqual(espejo, crm)
  })
}
test('el manifiesto de la PWA apunta a iconos PNG reales del tamaño declarado', () => {
  const publico = new URL('../../../app/public/', import.meta.url)
  const manifiesto = JSON.parse(readFileSync(new URL('manifest.webmanifest', publico), 'utf8'))
  assert.equal(manifiesto.scope, '/')
  assert.equal(manifiesto.display, 'standalone')
  assert.ok(manifiesto.icons.length >= 2)
  for (const icono of manifiesto.icons) {
    const bytes = readFileSync(new URL(icono.src.replace(/^\//, ''), publico))
    assert.equal(bytes.subarray(1, 4).toString(), 'PNG')
    assert.equal(`${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`, icono.sizes)
  }
})
