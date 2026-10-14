import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {carpeta,sql} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
const leer=n=>readFileSync(new URL(n,import.meta.url),'utf8');
const interior=s=>s.replace('\nbegin;\n','\n').split('\ncommit;')[0];
const f7=interior(leer('../../../migrations/20261014001044_crm_f7_redeclarar_huella_metricas_cartera.sql'));
const sla=interior(leer('../../../migrations/20261014001346_crm_sla_agrupar_tareas_por_lead.sql'));
const previa=`alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion set huella_md5='0b4ede547cf7079be1e56073311453b3' where firma='crm.metricas_cartera_fn(date)';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;`;
const pruebas=[];
function probar(nombre,consulta,error){
 try{sql(`begin; ${consulta} rollback;`);assert.ok(!error,'Mutante sobrevivió: '+nombre);}
 catch(e){if(!error||!e.message.includes(error))throw e;}
 pruebas.push(nombre);console.log('PASS: '+nombre);
}
probar('F7 repara solo huella y mantiene candado',previa+f7);
probar('F7 rechaza repetición',f7,'alguien ya la toco');
probar('F7 rechaza ACL abierta',previa+'grant execute on function crm.metricas_cartera_fn(date) to anon;'+f7,'SE REABRIO');
probar('F7 rechaza atributos',previa+'alter function crm.metricas_cartera_fn(date) security invoker;'+f7,'DEFINICION completa');
probar('F7 rechaza otra pieza',previa+`alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion set huella_md5=repeat('0',32) where firma=(select firma from private.f7_piezas_en_observacion
 where firma<>'crm.metricas_cartera_fn(date)' and estado in('observacion','cerrada_permanente') limit 1);
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;`+f7,'pieza(s) MAS');
probar('F7 rechaza vigilante verde',previa+"create or replace function private.assert_f7_piezas_cerradas() returns text language plpgsql as $f$ begin return 'OK'; end $f$;"+f7,'ya esta VERDE');
probar('F7 rechaza causa distinta',previa+"create or replace function private.assert_f7_piezas_cerradas() returns text language plpgsql as $f$ begin raise exception 'F7: causa distinta sintética'; end $f$;"+f7,'rojo por OTRA causa');
probar('SLA rechaza repetición',sla,'definición previa distinta');
probar('SLA rechaza ACL abierta',leer('../sla-anterior.sql')+'grant execute on function private.sla_operacion_leads(uuid[],boolean,uuid[],timestamptz) to anon;'+sla,'propietario o ACL previos distintos');
probar('SLA reversa exacta y reaplicación',leer('../reversa-sla.sql').replace('begin;\n','').split('\ncommit;')[0]+sla);
for(const archivo of ['casos-limite.sql','oraculo.sql','rpc-paridad.sql']){
 let consulta=leer('../'+archivo);
 // El transporte fija URL y usuario de cwkiejoaqadcnaieghnf. Este servicio
 // administrado usa postgres como nombre, a diferencia del banco Docker.
 consulta=consulta.replaceAll("current_database() !~ '^crm_incidencias_'","current_database() <> 'postgres'");
 assert.ok(consulta.trimEnd().endsWith('rollback;'));
 const salida=sql(consulta);writeFileSync(`${carpeta}/${archivo}.log`,salida,{mode:0o600});
 pruebas.push(archivo);console.log('PASS: '+archivo);
}
writeFileSync(`${carpeta}/sql-resultados.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),pruebas},null,2),{mode:0o600});
console.log(`PASS: ${pruebas.length} bloques SQL remotos; todo rollback.`);
