// Iteraciones aditivas del banco sintético; la reconstrucción usa la candidata completa.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';
const opciones={
  cotitulares:{modulo:'10-cotitulares-neutrales.sql',antes:'candidata-antes-cotitular-neutral.sql',cambios:['crm.crear_contrato_con_cuenta_pdf_v2']},
  correcciones:{modulo:'11-correccion-solicitud.sql',antes:'candidata-antes-correccion.sql',cambios:['private.inversion_solicitud_resultado','crm.preparar_inversion_fn','crm.confirmar_inversion_fn','private.f4_fuente_inmutable']},
};
const opcion=opciones[process.argv[2]]; assert(opcion,'Indica cotitulares o correcciones');
const antes=funcionesDelSql(readFileSync(`/private/tmp/avancecorp-f4-bank/${opcion.antes}`,'utf8'));
const modulo=readFileSync(new URL(opcion.modulo,import.meta.url),'utf8');
const {archivo}=JSON.parse(readFileSync(new URL('./ultima-migracion.json',import.meta.url),'utf8'));
assert(/^\d{14}_crm_f4_.*\.sql$/.test(archivo));
const candidata=readFileSync(new URL(`../../migrations/${archivo}`,import.meta.url),'utf8');
assert(candidata.includes(modulo));
const nuevas=funcionesDelSql(candidata), delModulo=funcionesDelSql(modulo);
for(const f of antes) if(!opcion.cambios.includes(f.nombre)) assert.equal(nuevas.find(n=>n.nombre===f.nombre)?.body,f.body,`Cambio no autorizado: ${f.nombre}`);
const reemplazos=nuevas.filter(f=>opcion.cambios.includes(f.nombre));
sql(`begin;set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
do $guard$ begin
  if private.inversiones_escritura_bajo_candado() then raise exception 'F4 debe estar apagada'; end if;
  ${antes.map(f=>`if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname=${q(f.nombre)} and p.prosrc=${q(f.body)})<>1
    then raise exception 'Deriva previa: ${f.nombre}'; end if;`).join('\n')}
end;$guard$;
${process.argv[2]==='correcciones'?"alter table crm.inversion_solicitudes add column revision_datos integer not null default 0 check(revision_datos>=0);":''}
${modulo}
${nuevas.filter(f=>!antes.some(a=>a.nombre===f.nombre)&&!delModulo.some(m=>m.nombre===f.nombre)).map(f=>f.definicion).join('\n')}
${reemplazos.filter(f=>!delModulo.some(m=>m.nombre===f.nombre)).map(f=>f.definicion).join('\n')}
${process.argv[2]==='correcciones'?"revoke all on function crm.confirmar_inversion_revisada_fn(uuid,integer) from public,anon,authenticated,service_role;grant execute on function crm.confirmar_inversion_revisada_fn(uuid,integer) to authenticated;":''}
notify pgrst,'reload schema';commit;`);
writeFileSync(new URL(`../evidencia-f4/ampliacion-${process.argv[2]}-${randomUUID()}.json`,import.meta.url),JSON.stringify({
  entorno:'avancecorp-f4-bank',aplicadoEn:new Date().toISOString(),produccionModificada:false,
  funcionesPreviasComprobadas:antes.length,reemplazadas:reemplazos.map(f=>f.nombre),
  sha256Modulo:createHash('sha256').update(modulo).digest('hex'),sha256Candidata:createHash('sha256').update(candidata).digest('hex'),
},null,2)+'\n',{flag:'wx'});
console.log(`Ampliación ${process.argv[2]} aplicada en el banco sintético bajo guardas.`);
