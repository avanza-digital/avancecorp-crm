import assert from 'node:assert/strict';
import test from 'node:test';
import { errorResponsabilidadConversion } from './preflight.mjs';

test('rechaza un lead parqueado antes de crear cliente', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: null }, 'analista-1'),
    'Asigna el lead a un analista antes de convertirlo',
  );
});

test('rechaza al supervisor/caller que no es el analista responsable', () => {
  assert.equal(
    errorResponsabilidadConversion({ vendedor_id: 'analista-1' }, 'supervisor-1'),
    'La conversión la realiza el analista responsable; reasígnate el lead primero',
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
