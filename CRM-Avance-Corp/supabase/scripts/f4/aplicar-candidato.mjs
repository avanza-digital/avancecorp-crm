// Solo instalación inicial en el banco sintético validado por banco-local.mjs.
// No registra historia de migraciones ni acepta otra base.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql, leer } from './banco-local.mjs';

assert(leer('operaciones-base.json').completo, 'Completa los antecedentes sintéticos');
assert(leer('paridad-antes.json').capital.length > 0, 'Captura primero una referencia no vacía');
const { archivo } = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
assert(/^\d{14}_crm_f4_.*\.sql$/.test(archivo));
const contenido = readFileSync(new URL(`../../migrations/${archivo}`, import.meta.url), 'utf8');
assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"), 't', 'F4 ya existe; no reinstalar sobre datos');
sql(contenido, { admin: true });
assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is not null"), 't');
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
writeFileSync(new URL('../evidencia-f4/2026-09-07-instalacion-local.json', import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', aplicadoEn: new Date().toISOString(), archivo,
  sha256: createHash('sha256').update(contenido).digest('hex'),
  banderaInversiones: false, transaccionConfirmada: true, produccionModificada: false,
}, null, 2) + '\n');
console.log('Candidata F4 instalada íntegramente en el banco local; bandera aún apagada.');
