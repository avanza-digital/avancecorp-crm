import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';

const manifiesto = JSON.parse(readFileSync(new URL('./ultima-migracion.json', import.meta.url), 'utf8'));
const contenido = readFileSync(new URL(`../../migrations/${manifiesto.archivo}`, import.meta.url), 'utf8');
const funciones = funcionesDelSql(contenido);
assert.deepEqual(funciones.map(f => f.nombre).sort(), manifiesto.funciones);
const originales = ['base-funciones.json', 'base-funciones-adicionales.json'].flatMap(n =>
  JSON.parse(readFileSync(new URL(n, import.meta.url), 'utf8')));
const nuevas = funciones.filter(f => !originales.some(o => o.nombre === f.nombre));
assert.equal(nuevas.length, 17);
const vivas = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'body',p.prosrc,'owner',pg_get_userbyid(p.proowner),'securityDefiner',p.prosecdef,'config',p.proconfig,
  'anon',has_function_privilege('anon',p.oid,'EXECUTE'),
  'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
  'service_role',has_function_privilege('service_role',p.oid,'EXECUTE')))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${funciones.map(f => q(f.nombre)).join(',')}])`));
assert.equal(vivas.length, funciones.length);
const ejecutablesUsuario = new Set(['crm.preparar_inversion_fn', 'crm.confirmar_inversion_fn',
  'crm.acceso_inversion_fn',
  'crm.revisar_solicitud_inversion_fn',
  'private.f4_comprobante_autorizado', 'private.f4_comprobante_visible']);
for (const fn of funciones) {
  const viva = vivas.find(v => v.nombre === fn.nombre);
  assert.equal(viva.body, fn.body, `El cuerpo instalado difiere: ${fn.nombre}`);
  const original = originales.find(f => f.nombre === fn.nombre);
  assert.equal(viva.owner, original?.owner ?? 'postgres');
  if (!original) {
    assert.equal(viva.securityDefiner, !['private.inversion_datos_portal','private.f4_alineacion_perfil_permitida'].includes(fn.nombre));
    assert(viva.config.includes('search_path=""'), `search_path fijo ausente: ${fn.nombre}`);
    assert.equal(viva.anon, false);
    assert.equal(viva.service_role, false);
    assert.equal(viva.authenticated, ejecutablesUsuario.has(fn.nombre));
  }
}
for (const tabla of ['inversion_solicitudes', 'inversion_ajustes_mes_cerrado', 'inversion_eventos','inversion_solicitud_revisiones']) {
  assert.equal(sql(`select relrowsecurity from pg_class where oid=${q(`crm.${tabla}`)}::regclass`), 't');
  for (const rol of ['anon', 'authenticated', 'service_role']) {
    assert.equal(sql(`select has_table_privilege(${q(rol)},${q(`crm.${tabla}`)},'SELECT,INSERT,UPDATE,DELETE')`), 'f');
  }
}
assert.equal(sql(`select count(*) from crm.inversiones i where
  ((i.contrato_id is not null)::integer+(i.cierre_externo_id is not null)::integer)<>1
  or not exists(select 1 from crm.inversion_titulares t where t.inversion_id=i.id and t.rol='principal' and t.inversionista_id=i.inversionista_id)`), '0');
const cantidades = JSON.parse(sql(`select jsonb_build_object('auth',(select count(*) from auth.users),
  'personas',(select count(*) from crm.inversionistas),'leads',(select count(*) from crm.leads),
  'contratos',(select count(*) from public.contratos),'cierres',(select count(*) from crm.cierres_externos),
  'inversiones',(select count(*) from crm.inversiones),'solicitudes',(select count(*) from crm.inversion_solicitudes),
  'pdfPendientes',(select count(*) from private.contrato_pdf_jobs where estado='pendiente'))`));
const verificadoEn = new Date().toISOString();
const archivo = `estructura-${verificadoEn.replaceAll(':', '-')}.json`;
writeFileSync(new URL(`../evidencia-f4/${archivo}`, import.meta.url), JSON.stringify({
  entorno: 'avancecorp-f4-bank', verificadoEn, funcionesComprobadas: funciones.length,
  funcionesNuevas: nuevas.length, cuerposIgualesACandidata: true, propietariosConservados: true,
  rlsYGrantsDeLasCuatroTablas: true, ejecutablesUsuario: [...ejecutablesUsuario],
  fuenteYPrincipalCoherentes: true, cantidades,
  banderas: JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags')),
  sha256Candidata: createHash('sha256').update(contenido).digest('hex'),
  limite: 'Comprobación estructural acotada: no sustituye las pruebas de comportamiento, los permisos dinámicos ni el gate G4.',
}, null, 2) + '\n', { flag: 'wx' });
console.log(`Estructura F4: ${funciones.length} cuerpos iguales a la candidata, ${nuevas.length} funciones nuevas con grants previstos y cuatro tablas cerradas al acceso directo.`);
console.log(`Evidencia nueva, sin sobrescribir capturas anteriores: ${archivo}`);
