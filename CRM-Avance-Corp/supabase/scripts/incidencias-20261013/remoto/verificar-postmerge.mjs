import assert from 'node:assert/strict';
import{readFileSync,writeFileSync}from'node:fs';
const carpeta='/private/tmp/incidencias-banco-f7';
const json=f=>JSON.parse(readFileSync(`${carpeta}/${f}`));
const antes=json('produccion-catalogo-premerge.json').rows[0].estructura;
const despues=json('produccion-catalogo-postflight-mcp.json').rows[0].estructura;
const firma='private.sla_operacion_leads(uuid[],boolean,uuid[],timestamp with time zone)';
assert.equal(despues.funciones.find(f=>f.firma===firma).md5,'0abdf640b5f4f10ab2e85b6bd2494522');
despues.funciones.find(f=>f.firma===firma).md5='12749d608bb0a296f763e000f18c03de';
assert.deepEqual(despues,antes,'Cambió otro objeto del catálogo');
const a=json('produccion-extra-premerge.json').rows[0].extra,b=json('produccion-extra-postmerge.json').rows[0].extra;
assert.deepEqual(b.ledger,a.ledger);
assert.deepEqual(b.nuevas,[
 {version:'20261014013757',nombre:'crm_f7_redeclarar_huella_metricas_cartera',huella:'77b56b4f5ab30c4be790875daf7ac8ef'},
 {version:'20261014013830',nombre:'crm_sla_agrupar_tareas_por_lead',huella:'f75bdc4cbce3ceff71b2a919a0ff9878'}]);
for(const f of b.f7){const original=a.f7.find(x=>x.firma===f.firma);assert.ok(original);
 if(f.firma==='crm.metricas_cartera_fn(date)'){
  assert.equal(f.huella_md5,'869853c25e903fe2f79245b8176c09b9');assert.notEqual(f.nota,original.nota);
  f.huella_md5=original.huella_md5;f.nota=original.nota;
 }assert.deepEqual(f,original);
}assert.equal(b.f7.length,a.f7.length);
for(const k of ['esquemas','acl_columnas','default_acl','extensiones','publicaciones'])assert.deepEqual(b[k],a[k],k);
const final=json('postflight-final.json')[0].comprobacion;
assert.equal(final.estado,'PASS');assert.equal(final.piezas_f7,15);assert.equal(final.alertas_f7_abiertas,0);
const resultado={estado:'PASS',fecha:new Date().toISOString(),tablas:149,funciones:1085,
 deltaFunciones:[firma],deltaF7:['huella_md5','nota'],baseLedgerConservada:b.ledger,migraciones:b.nuevas};
writeFileSync(`${carpeta}/postmerge-catalogo.json`,JSON.stringify(resultado,null,2),{mode:0o600});console.log(JSON.stringify(resultado));
