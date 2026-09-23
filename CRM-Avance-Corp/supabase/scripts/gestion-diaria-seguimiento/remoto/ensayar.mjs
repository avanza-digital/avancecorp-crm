// Mismos contratos SQL versionados; transacción revertida y destino fijo.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {carpeta,sql} from './banco.mjs';
assert.deepEqual(process.argv.slice(2),['--solo-rama-autorizada']);
assert.equal(sql("select to_regclass('crm.gestion_diaria_entregas') is not null"),'t');
const pruebas=['test-mutantes.sql','test-seguimiento.sql','test-alertas-equipo.sql'];
const cuerpo=pruebas.map(f=>readFileSync(new URL('../'+f,import.meta.url),'utf8')).join('\n');
const gates=`select private.assert_gestion_diaria(); select private.assert_sla_nucleo();
 select private.assert_sla_operacion(); select private.assert_sla_comandos();
 select private.assert_sla_avisos(); select private.assert_analitica_leads_citas();`;
const resultado=sql(`begin; ${gates}\n${cuerpo}\nrollback;`);
const despues=sql(gates);
writeFileSync(`${carpeta}/ensayo-sql.log`,resultado+'\n'+despues+'\n',{mode:0o600});
writeFileSync(`${carpeta}/ensayo-sql.json`,JSON.stringify({estado:'PASS',fecha:new Date().toISOString(),pruebas,
 limites:'24 mutantes remotos. BYPASSRLS exige superusuario: probado localmente, no ejecutado en hosted.'},null,2)+'\n',{mode:0o600});
console.log(resultado.split('\n').filter(l=>l.startsWith('PASS:')).join('\n'));
