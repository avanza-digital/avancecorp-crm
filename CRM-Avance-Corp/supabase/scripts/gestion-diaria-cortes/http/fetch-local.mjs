// Preload de los procesos seed/RLS: cualquier fetch fuera del API propio falla
// antes de abrir la conexión. No es un firewall del sistema ni lo pretende.
import assert from 'node:assert/strict';
const original = globalThis.fetch;
export function destinoPermitido(input) {
  const u = new URL(input instanceof Request ? input.url : input);
  return u.origin === 'http://127.0.0.1:59321' && !u.username && !u.password;
}
globalThis.fetch = (input, opciones = {}) => {
  assert.ok(destinoPermitido(input), 'HTTP fuera del banco local bloqueado');
  return original(input, { ...opciones, redirect: 'error' });
};
