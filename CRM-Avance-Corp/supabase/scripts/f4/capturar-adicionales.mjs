import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { banco, sql, literal as q } from './banco-local.mjs';

const nombres = ['crm.contrato_eliminacion_preparar', 'public.proteger_campos_inmutables'];
const destino = new URL('./base-funciones-adicionales.json', import.meta.url);
const fuentes = JSON.parse(readFileSync(join(banco, 'functions-prod.json'), 'utf8'));
const existentes = existsSync(destino) ? JSON.parse(readFileSync(destino, 'utf8')) : [];
for (const nombre of nombres) {
  if (existentes.some(f => f.nombre === nombre)) continue;
  const filas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object(
    'nombre',n.nspname||'.'||p.proname,'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
    'md5',md5(pg_get_functiondef(p.oid)),'definicion',pg_get_functiondef(p.oid),'body',p.prosrc,
    'owner',pg_get_userbyid(p.proowner),'acl',p.proacl)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname=${q(nombre)}`));
  assert.equal(filas.length, 1);
  const f = filas[0];
  const original = fuentes.find(x => `${x.schema}.${x.nombre}` === nombre);
  assert(original, 'Falta el original del volcado de solo esquema');
  assert.equal(f.body, original.body, 'La función del banco ya no coincide con el cuerpo original de producción');
  delete f.body;
  existentes.push(f);
}
writeFileSync(destino, JSON.stringify(existentes, null, 2) + '\n');
console.log(`${existentes.length} puerta adicional anclada al original, sin datos personales.`);
