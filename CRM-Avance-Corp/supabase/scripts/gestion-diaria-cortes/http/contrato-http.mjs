// Comparación de respuestas REALES antes/después del candidato y su reversa.
// Sólo elimina metadatos de instante y los dos campos aditivos documentados.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { carpeta, sql, http } from './banco.mjs';
import { USER_BY_KEY } from '../../fixtures.mjs';

const [modo,...otros]=process.argv.slice(2);
assert.ok(['--guardar-baseline','--comparar-instalado','--guardar-reversa','--comparar-revertido'].includes(modo)&&otros.length===0);
const instalada=sql("select to_regclass('crm.politica_gestion_diaria') is not null")==='t';
assert.equal(instalada,['--comparar-instalado','--guardar-reversa'].includes(modo));
if(instalada) assert.equal(sql('select count(*)=1 and bool_and(version=1 and not cortes_activos) from crm.politica_gestion_diaria'),'t');
const {password}=JSON.parse(readFileSync(`${carpeta}/credenciales-fixtures.json`,'utf8'));
const ids=JSON.parse(sql("select jsonb_object_agg(correo,id) from public.perfiles where correo like '%@demo.avancecorp.pe'"));
// Día ya terminado: ni el avance del reloj ni cruzar un corte falsean la comparación.
const dia='2026-09-20';
const respuestas={};
for(const key of ['sup1','sup2','gerencia','vend1']) {
  const user=USER_BY_KEY[key];
  const login=await http('/auth/v1/token?grant_type=password',{body:{email:user.email,password}});
  assert.equal(login.status,200,`Login real de ${key}`);
  assert.ok(login.data.user?.id===ids[user.email],'Auth y perfil deben pertenecer al mismo banco');
  const token=login.data.access_token;
  const pedidos=key==='vend1'
    ? [['analista',{p_dia:dia,p_analista_id:ids[user.email]}]]
    : [['equipo',{p_dia:dia,p_supervisor_id:ids[USER_BY_KEY[key==='gerencia'?'sup1':key].email]}],
      ['analista',{p_dia:dia,p_analista_id:ids[USER_BY_KEY[key==='sup2'?'vend3':'vend1'].email]}]];
  for(const [tipo,body] of pedidos) {
    const r=await http(`/rest/v1/rpc/gestion_diaria_${tipo}_fn`,{token,body});
    assert.equal(r.status,200,`${key}/${tipo} debe responder realmente`);
    assert.equal(r.data.dia,dia);
    if(tipo==='equipo') {
      assert.ok(r.data.equipo.length>=2,'No aceptar un equipo vacío como prueba');
      assert.equal('cortes' in r.data,instalada);
      if(instalada) assert.equal(r.data.cortes.estado,'desactivados');
    }
    assert.equal('politica_version' in r.data.umbrales,instalada);
    respuestas[`${key}/${tipo}`]=r.data;
  }
}
const normalizar=datos=>Object.fromEntries(Object.entries(datos).map(([key,original])=>{
  const d=structuredClone(original);
  assert.ok(Number.isFinite(Date.parse(d.generado_en)));
  // El contrato declara pendientes actuales incluso al consultar otro día.
  if('pendientes_al' in d) {
    assert.equal(d.pendientes_al,d.generado_en);
    delete d.pendientes_al;
  }
  delete d.generado_en;
  delete d.cortes;
  delete d.umbrales.politica_version;
  return [key,d];
}));
const grupo=['--guardar-baseline','--comparar-instalado'].includes(modo)?'instalacion':'reversa';
const archivo=`${carpeta}/contrato-${grupo}.json`;
if(modo.startsWith('--guardar')) {
  const contenido=JSON.stringify({dia,instalada,respuestas},null,2)+'\n';
  writeFileSync(`${carpeta}/contrato-${grupo}-${Date.now()}.json`,contenido,{mode:0o600,flag:'wx'});
  writeFileSync(archivo,contenido,{mode:0o600});
  console.log(`PASS: siete respuestas Auth/HTTP capturadas para ${grupo}, sin tokens`);
} else {
  const previo=JSON.parse(readFileSync(archivo,'utf8'));
  assert.equal(previo.dia,dia);
  assert.deepEqual(normalizar(respuestas),normalizar(previo.respuestas),'El candidato OFF/reversa alteró el contrato previo');
  writeFileSync(`${carpeta}/contrato-${grupo}-resultado.json`,JSON.stringify({estado:'PASS',dia,respuestas},null,2)+'\n',{mode:0o600});
  console.log(`PASS: siete respuestas Auth/HTTP preservan exactamente el contrato previo (${grupo})`);
}
