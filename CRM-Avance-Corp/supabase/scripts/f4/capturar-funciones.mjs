import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { sql, literal } from './banco-local.mjs';

const destino = new URL('./base-funciones.json', import.meta.url);
const nombres = [
  'private.capital_episodios','private.cierre_anulado','private.leads_before_update',
  'private.metricas_conversiones_implementacion','crm.cierres_estado_fn','crm.cierres_externos_fn',
  'crm.anular_cierre_avance','crm.anular_cierre_externo','crm.corregir_cierre_externo',
  'crm.enlazar_lead_inversionista_fn','crm.altas_nuevas_por_analista_fn','crm.convertir_lead_externo',
  'public.crear_contrato','crm.crear_contrato_con_cuenta','crm.crear_contrato_con_cuenta_pdf_v2',
];
const filas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object(
  'nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'md5',md5(pg_get_functiondef(p.oid)),'definicion',pg_get_functiondef(p.oid),
  'owner',pg_get_userbyid(p.proowner),'acl',p.proacl))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${nombres.map(literal).join(',')}])`));
assert.equal(filas.length,nombres.length,'Cada puerta debe tener una firma inequívoca');
if (existsSync(destino)) {
  const anterior=JSON.parse(readFileSync(destino,'utf8'));
  assert(filas.every(f => anterior.some(a => a.firma===f.firma && a.md5===f.md5)),
    'La base cambió. No sobrescribir la captura original con funciones F4.');
} else {
  writeFileSync(destino,`${JSON.stringify(filas.sort((a,b)=>a.nombre.localeCompare(b.nombre)),null,2)}\n`);
}
console.log(`${filas.length} definiciones y huellas originales capturadas, sin datos de personas.`);
