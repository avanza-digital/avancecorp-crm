import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const privado = JSON.parse(readFileSync('/private/tmp/formulario3-fase3-privado/branch.json', 'utf8'))
assert.equal(privado.SUPABASE_URL, 'https://bxkborlvpmuwttzjrjqn.supabase.co')
const pruebas = JSON.parse(readFileSync(new URL('./conversion-real.json', import.meta.url), 'utf8'))
assert.equal(pruebas.rama, 'bxkborlvpmuwttzjrjqn')
assert.equal(pruebas.objetos.length, 2)
const permitidos = new Set(pruebas.conversiones.map(c => c.resultado.inversionista_id + '/' + c.solicitud_id + '/comprobante.png'))
assert.ok(pruebas.objetos.every(ruta => permitidos.has(ruta)))
const cliente = createClient(privado.SUPABASE_URL, privado.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
const bucket = cliente.storage.from('f4-comprobantes')
const borrado = await bucket.remove(pruebas.objetos)
assert.equal(borrado.error, null, borrado.error?.message)
for (const ruta of pruebas.objetos) {
  const listado = await bucket.list(ruta.slice(0, ruta.lastIndexOf('/')))
  assert.equal(listado.error, null)
  assert.equal(listado.data.length, 0)
}
writeFileSync(new URL('./limpieza-storage.json', import.meta.url), JSON.stringify({ estado: 'PASS', rama: pruebas.rama, objetos_retirados: pruebas.objetos, comprobacion: 'API Storage confirma carpetas vacías' }, null, 2) + '\n')
console.log('PASS: retirados y verificados los dos comprobantes ficticios')
