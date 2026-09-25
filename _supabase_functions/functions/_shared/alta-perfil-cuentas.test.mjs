import test from 'node:test'
import assert from 'node:assert/strict'
import { clasificarAltaPerfilConCuentas, compensarAuthAltaRechazada } from './alta-perfil-cuentas.mjs'

const ID = '00000000-0000-4000-8000-000000000001'

function cliente(perfil, lecturaError = null, deleteError = null) {
  let borrados = 0
  return {
    from: (tabla) => {
      assert.equal(tabla, 'perfiles')
      return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: perfil, error: lecturaError }) }) }) }
    },
    auth: { admin: { deleteUser: async () => {
      borrados++
      return { error: deleteError }
    } } },
    borrados: () => borrados,
  }
}

test('respuesta confirmada devuelve el UUID sin hacer una lectura adicional', async () => {
  const admin = { from: () => { throw new Error('lectura inesperada') } }
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { data: ID, error: null }), 'confirmada')
})

test('respuesta perdida tras COMMIT confirma solo si el reintento idempotente responde con UUID', async () => {
  const admin = cliente({ id: ID })
  let reintentos = 0
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: 'PGRST000' } }, async () => {
    reintentos++
    return { data: ID, error: null }
  }), 'confirmada')
  assert.equal(reintentos, 1)
  assert.equal(admin.borrados(), 0)
})

test('perfil previo con cuenta distinta y P0409 no confirma ni compensa el Auth', async () => {
  const admin = cliente({ id: ID })
  let reintentos = 0
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: 'P0409' } }, async () => {
    reintentos++
    return { data: ID, error: null }
  }), 'incierta')
  assert.equal(reintentos, 0)
  assert.equal(admin.borrados(), 0)
})

test('un perfil existente no confirma un transporte incierto si el reintento falla', async () => {
  const admin = cliente({ id: ID })
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: 'PGRST000' } }, async () => ({
    data: null, error: { code: 'P0409' },
  })), 'incierta')
  assert.equal(admin.borrados(), 0)
})

test('error de red sin perfil confirmado queda incierto y nunca se compensa', async () => {
  const admin = cliente(null)
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: 'PGRST000' } }), 'incierta')
  assert.equal(admin.borrados(), 0)
})

test('rechazo SQL con ausencia confirmada permite compensar y verifica su resultado', async () => {
  const admin = cliente(null)
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: '23514' } }), 'rechazada')
  assert.equal(await compensarAuthAltaRechazada(admin, ID), true)
  assert.equal(admin.borrados(), 1)
  const falla = cliente(null, null, { message: 'delete failed' })
  assert.equal(await compensarAuthAltaRechazada(falla, ID), false)
})

test('fallo de lectura conserva el Auth aun con un SQLSTATE de rechazo', async () => {
  const admin = cliente(null, { code: 'PGRST000' })
  assert.equal(await clasificarAltaPerfilConCuentas(admin, ID, { error: { code: '23514' } }), 'incierta')
  assert.equal(admin.borrados(), 0)
})
