// Iteración aditiva del banco ficticio. No aplica fuentes ni registra migraciones.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sql, literal as q } from './banco-local.mjs';
import { funcionesDelSql } from './leer-funciones-sql.mjs';
import { cargarHistoricosPrueba } from './cargar-historicos-prueba.mjs';

const anterior=readFileSync('/private/tmp/avancecorp-f4-bank/candidata-antes-historicos.sql','utf8');
const manifiesto=JSON.parse(readFileSync(new URL('ultima-migracion.json',import.meta.url),'utf8'));
const candidata=readFileSync(new URL(`../../migrations/${manifiesto.archivo}`,import.meta.url),'utf8');
const previas=funcionesDelSql(anterior),actuales=funcionesDelSql(candidata);
assert.equal(previas.length,34); assert.equal(actuales.length,37);
for(const f of previas) assert.equal(actuales.find(a=>a.nombre===f.nombre)?.body,f.body,`Cambio fuera de históricos: ${f.nombre}`);
const carga=cargarHistoricosPrueba(sql);
assert.equal(carga.instalado,false,'El bloque histórico ya está instalado');
const vivas=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('nombre',n.nspname||'.'||p.proname,
  'firma',format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
  'body',p.prosrc,'md5',md5(pg_get_functiondef(p.oid))))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname||'.'||p.proname=any(array[${previas.map(f=>q(f.nombre)).join(',')}])`));
assert.equal(vivas.length,previas.length);
for(const f of previas) assert.equal(vivas.find(v=>v.nombre===f.nombre).body,f.body);
sql(`begin;
  set local lock_timeout='5s';
  select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'));
  select pg_advisory_xact_lock(hashtext('crm_flag_inversiones_escritura'));
  do $guard$ begin
    if (select activo from crm.multiempresa_flags where nombre='inversiones_escritura') then
      raise exception 'Apaga el escritor del banco antes de iterar'; end if;
    ${vivas.map(f=>`if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Cambió una función desde la captura'; end if;`).join('\n')}
  end; $guard$;
  ${carga.preparacion}
  notify pgrst,'reload schema';
  commit;`);
const instante=new Date().toISOString();
const sha=x=>createHash('sha256').update(x).digest('hex');
writeFileSync(new URL(`../evidencia-f4/iteracion-historicos-${instante.replaceAll(':','-')}.json`,import.meta.url),JSON.stringify({
  entorno:'avancecorp-f4-bank',instaladoEn:instante,sha256Anterior:sha(anterior),sha256Candidata:sha(candidata),
  funcionesPreviasConservadas:34,funcionesNuevas:3,tablaNueva:'crm.inversion_backfill_lotes',
  lotesAplicados:0,escritorApagado:true,produccionModificada:false,
},null,2)+'\n',{flag:'wx'});
console.log('Históricos instalados en banco F4: tres funciones y acta auditada; ningún lote aplicado.');
