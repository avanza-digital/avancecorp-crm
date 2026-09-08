import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { banco, sql, leer } from './banco-local.mjs';

const original = JSON.parse(readFileSync('/private/tmp/f4-baseline-prod-20260907.json', 'utf8'));
const funciones = JSON.parse(sql(`select jsonb_agg(jsonb_build_object(
  'schema',n.nspname,'nombre',p.proname,'md5',md5(pg_get_functiondef(p.oid))))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('crm','private','public') and p.prokind='f'`));
const paridad = original.funciones.map(f => ({
  firma: f.firma, md5: f.md5,
  coincide: funciones.some(local => local.schema === f.schema && local.nombre === f.nombre && local.md5 === f.md5),
}));
assert(paridad.every(f => f.coincide), `Funciones distintas: ${JSON.stringify(paridad.filter(f => !f.coincide))}`);
const f = leer('fixtures.json');
const censo = JSON.parse(sql(`select jsonb_build_object(
  'auth', (select count(*) from auth.users),
  'perfiles', (select count(*) from public.perfiles),
  'identidades', (select count(*) from crm.inversionistas),
  'contratos', (select count(*) from public.contratos),
  'cierres_externos', (select count(*) from crm.cierres_externos),
  'inversiones', (select count(*) from crm.inversiones))`));
assert.equal(censo.auth, Object.keys(f.usuarios).length);
assert.equal(censo.perfiles, Object.keys(f.usuarios).length);
assert.equal(censo.contratos + censo.cierres_externos + censo.inversiones, 0);
const evidencia = {
  capturado_en: new Date().toISOString(),
  estado: 'banco_preparado_motor_f4_pendiente',
  banco: 'Docker local avancecorp-f4-bank, API 56321, Postgres 56322',
  produccion: { id: 'dctqcbznekcyxhjujuci', acceso: 'solo lectura, esquema sin datos' },
  version_postgresql: '17.6', version_cli: '2.117.0',
  esquema_sha256: createHash('sha256').update(readFileSync(join(banco, 'schema-prod.sql'))).digest('hex'),
  censo_sintetico: censo,
  funciones_verificadas: paridad,
  comprobaciones: [
    'Restauración de esquema y propietarios completada',
    'Creación mediante Auth API y login real con usuario ficticio',
    'RPC CRM por HTTP con JWT de usuario ficticio',
    'Semilla reejecutada sin recrear filas',
  ],
  limitaciones: [
    'El motor de nuevas inversiones F4 todavía no está construido',
    'Esta evidencia no aprueba G4 ni una activación productiva',
    'Endor no disponible: revisión del paquete de pruebas sin verificar',
  ],
};
writeFileSync(join(dirname(fileURLToPath(import.meta.url)), '../evidencia-f4/2026-09-07-banco-local.json'),
  `${JSON.stringify(evidencia, null, 2)}\n`);
console.log(`Base F4: ${paridad.length} funciones iguales; ${censo.auth} Auth ficticios; cero inversiones de prueba todavía.`);
