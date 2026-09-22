// La publicación OFF debe convivir con el SLA operativo vigente. Inicializa
// las reglas sintéticas por la puerta oficial, ensaya y restituye el modo.
// NO activa cortes de Gestión Diaria ni modifica la copia anterior/producción.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { carpeta, sql, http } from './banco.mjs';
import { USER_BY_KEY } from '../../fixtures.mjs';

assert.deepEqual(process.argv.slice(2),['--solo-banco-autorizado']);
assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
const antes=JSON.parse(sql('select to_jsonb(c) from crm.sla_operacion_control c where id'));
assert.equal(antes.modo,'legado','No modificar un estado de prueba distinto al esperado');
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const login=await http('/auth/v1/token?grant_type=password',{body:{email:USER_BY_KEY.gerencia.email,password}});
assert.equal(login.status,200);
const token=login.data.access_token;
let estado='FAIL';
try {
  if(sql('select count(*) from private.sla_politica_operativa(statement_timestamp())')==='0') {
    const r=await http('/rest/v1/rpc/publicar_reglas_sla_aprobadas_v2',{token,
      body:{p_expected_version:Number(sql('select max(version) from crm.sla_politicas'))}});
    assert.equal(r.status,200,'Publicación oficial de cuatro reglas sintéticas');
  }
  const r=await http('/rest/v1/rpc/cambiar_modo_sla_operacion',{token,
    body:{p_expected_revision:antes.revision,p_modo:'activo'}});
  assert.equal(r.status,200,'Activación del SLA del banco, NO de cortes');
  assert.equal(r.data.modo,'activo');
  const hijo=spawn(process.execPath,[fileURLToPath(new URL('./navegador.mjs',import.meta.url)),
    '--solo-banco-autorizado','--registrar-seguimiento'],{stdio:'inherit'});
  const exit=await new Promise(resolve=>hijo.on('close',resolve));
  assert.equal(exit,0,'Recorrido real con SLA activo');
  estado='PASS';
} finally {
  const actual=JSON.parse(sql('select to_jsonb(c) from crm.sla_operacion_control c where id'));
  if(actual.modo!==antes.modo) {
    const r=await http('/rest/v1/rpc/cambiar_modo_sla_operacion',{token,
      body:{p_expected_revision:actual.revision,p_modo:antes.modo}});
    assert.equal(r.status,200,'Restituir modo SLA original por su puerta oficial');
  }
  assert.equal(sql('select modo from crm.sla_operacion_control where id'),antes.modo);
  assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
  writeFileSync(`${carpeta}/sla-activo.json`,JSON.stringify({estado,modoInicial:antes.modo,modoFinal:antes.modo,
    historiaConservada:true,cortesActivos:false},null,2)+'\n',{mode:0o600});
}
console.log('PASS: interfaz y seguimiento con SLA activo; modo original restituido y cortes OFF');
