// Solo la iteración ACL del banco sintético. La reconstrucción usa la candidata.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';
const modulo=readFileSync(new URL('./09-cotitular-puerta.sql',import.meta.url),'utf8');
const {archivo}=JSON.parse(readFileSync(new URL('./ultima-migracion.json',import.meta.url),'utf8'));
assert(/^\d{14}_crm_f4_.*\.sql$/.test(archivo));
const candidata=readFileSync(new URL(`../../migrations/${archivo}`,import.meta.url),'utf8');
assert(candidata.includes(modulo),'Regenera la candidata antes de instalar esta iteración');
const funciones=funcionesDelSql(candidata);
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"),'f');
// Comparación bajo los mismos candados: esta iteración no sustituye cuerpos.
sql(`begin;set local lock_timeout='5s';
  select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
    if private.inversiones_escritura_bajo_candado() then raise exception 'El escritor está encendido'; end if;
    ${funciones.map(f=>`if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname||'.'||p.proname=${q(f.nombre)} and p.prosrc=${q(f.body)})<>1
      then raise exception 'Cuerpo candidato distinto: ${f.nombre}'; end if;`).join('\n')}
  end; $guard$;
  ${modulo}
  notify pgrst,'reload schema';commit;`);
const aplicadoEn=new Date().toISOString();
writeFileSync(new URL(`../evidencia-f4/cotitular-puerta-instalacion-${randomUUID()}.json`,import.meta.url),JSON.stringify({
  entorno:'avancecorp-f4-bank',aplicadoEn,cambioSoloAcl:true,produccionModificada:false,
  sha256Modulo:createHash('sha256').update(modulo).digest('hex'),
  sha256Candidata:createHash('sha256').update(candidata).digest('hex'),funcionesSinCambios:funciones.length,
},null,2)+'\n',{flag:'wx'});
console.log('Banco local: auxiliar de titulares cerrado a la API; cuerpos conservados.');
