import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1'
import { claveIdempotencia, plantillaEmail, redactarAviso } from './aviso.ts'

Deno.test('clave de idempotencia estable por solicitud', () => {
  assertEquals(claveIdempotencia('E7B1A000-0000-4000-8000-000000000001'), 'cambio-cuenta-pago/e7b1a000-0000-4000-8000-000000000001')
  assertEquals(claveIdempotencia('e7b1a000-0000-4000-8000-000000000001'), claveIdempotencia('E7B1A000-0000-4000-8000-000000000001'))
})

const base = {
  nombre_completo: 'PEREZ ROJAS ANA', nombres: 'ANA MARIA', banco_nuevo: 'Interbank',
  moneda: 'PEN', ultimos_nuevo: '1234', contratos: ['AC-001'],
  cambiado_en: '2026-09-26T21:00:00Z',
}

Deno.test('un contrato: nombre de pila, banco, moneda y cuenta tapada', () => {
  const { titulo, mensaje } = redactarAviso(base)
  assertEquals(titulo, 'Cambio de tu cuenta de pago')
  assertMatch(mensaje, /^Hola ANA, atendimos tu pedido: desde el 26 de septiembre de 2026, los pagos del contrato AC-001 se depositan en tu cuenta Interbank en soles terminada en ••••1234\./)
  assertMatch(mensaje, /Si tú no solicitaste este cambio, comunícate de inmediato/)
})

Deno.test('varios contratos se listan con «y»; dólares', () => {
  const { mensaje } = redactarAviso({ ...base, moneda: 'USD', contratos: ['A', 'B', 'C'] })
  assertMatch(mensaje, /de los contratos A, B y C se depositan en tu cuenta Interbank en dólares/)
})

Deno.test('cuenta de un tercero: dice a nombre de quién, sin «tu cuenta»', () => {
  const { mensaje } = redactarAviso({ ...base, titular_distinto: true, beneficiario_nombre: 'MARIA TERCERA' })
  assertMatch(mensaje, /se depositan en la cuenta Interbank en soles terminada en ••••1234, a nombre de MARIA TERCERA\./)
  assert(!mensaje.includes('tu cuenta'), mensaje)
})

Deno.test('nunca incluye el número completo, solo los 4 últimos', () => {
  const { mensaje } = redactarAviso({ ...base, ultimos_nuevo: '9876' })
  assert(!/\d{5,}/.test(mensaje.replace('AC-001', '')), mensaje)
})

Deno.test('la plantilla escapa HTML del nombre y del mensaje', () => {
  const html = plantillaEmail('<b>X</b>', 'Título', 'línea 1\nlínea <2>')
  assert(html.includes('&lt;b&gt;X&lt;/b&gt;'))
  assert(html.includes('línea 1<br>línea &lt;2&gt;'))
  assert(html.includes('CAMBIO DE CUENTA DE PAGO'))
})

Deno.test('la fecha del cambio se lee en hora de Lima', () => {
  // 03:00 UTC del 27/09 son las 22:00 del 26/09 en Lima.
  const { mensaje } = redactarAviso({ ...base, cambiado_en: '2026-09-27T03:00:00Z' })
  assertMatch(mensaje, /desde el 26 de septiembre de 2026,/)
})
