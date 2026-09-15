import assert from 'node:assert/strict';
import test from 'node:test';
import { errorResponsabilidadConversion } from './preflight.mjs';

test('rechaza un lead parqueado antes de crear cliente', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: null }, 'analista-1'),
    'Asigna el lead a un analista antes de convertirlo',
  );
});

test('rechaza a un analista (vendedor) que no es el responsable del lead', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: 'analista-1' }, 'otro-analista-1'),
    'La conversión la realiza el analista responsable; reasígnate el lead primero',
  );
});

// El ámbito del supervisor (su equipo) ya lo garantizó la RLS `leads_select`
// al leer el lead en index.ts (misma vendedor_ids_visibles que usan las RPC de
// conversión) — esta función solo decide el rol, no vuelve a filtrar ámbito.
test('acepta a un supervisor sobre un lead de un analista de su equipo', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: 'analista-1' }, 'supervisor-1', 'supervisor'),
    null,
  );
});

test('acepta al analista que ya es dueño del lead', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: 'analista-1' }, 'analista-1'),
    null,
  );
});

test('acepta a Gerencia sobre un lead que conserva analista responsable', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: 'analista-1' }, 'gerencia-1', 'gerencia'),
    null,
  );
});

test('Gerencia tampoco convierte un lead sin analista responsable', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: null }, 'gerencia-1', 'gerencia'),
    'Asigna el lead a un analista antes de convertirlo',
  );
});
