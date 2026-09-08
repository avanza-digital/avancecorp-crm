import { entorno } from './banco-local.mjs';
// Carreras con las RPC reales de F3, exclusivamente en una copia SQL sintética.
import assert from 'node:assert/strict';
import { randomInt, randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql as sqlOriginal, leer, literal as q } from './banco-local.mjs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { cargarHistoricosPrueba } from './cargar-historicos-prueba.mjs';

const tablas = ['public.contratos','public.cronograma_pagos','public.perfiles','public.documentos',
  'public.contrato_titulares','crm.cierres_externos','crm.leads','crm.inversionistas',
  'crm.inversionista_identificadores','crm.inversionista_responsables','crm.inversionista_fusiones',
  'crm.inversionista_operaciones','crm.backfill_multiempresa_mapa','crm.inversiones',
  'crm.inversion_titulares','crm.inversion_solicitudes','crm.inversion_backfill_lotes',
  'private.contrato_pdf_jobs','private.contrato_pdfs','crm.multiempresa_flags'];
const foto = `select jsonb_object_agg(tabla,huella) from (${tablas.map(t=>
  `select ${q(t)} tabla,private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) huella from ${t} t`
).join(' union all ')}) x`;
const dinero = `select jsonb_build_object(
  'contratos',(select private.idem_hash(jsonb_agg(to_jsonb(t) order by id)) from public.contratos t),
  'cierres',(select private.idem_hash(jsonb_agg(to_jsonb(t)-'inversionista_id' order by id)) from crm.cierres_externos t),
  'cuotas',(select private.idem_hash(jsonb_agg(to_jsonb(t) order by id)) from public.cronograma_pagos t),
  'pdf',(select private.idem_hash(jsonb_agg(to_jsonb(t) order by id)) from private.contrato_pdf_jobs t),
  'sellos',(select private.idem_hash(jsonb_agg(to_jsonb(t) order by contrato_id)) from private.contrato_pdfs t),
  'capital',(select private.idem_hash(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text))
    from private.capital_episodios('-infinity','infinity',true,'{}') t))`;
const antes = sqlOriginal(foto);
const copia = crearCopiaSql('historicos_identidad');
const {sql,abrirSesion,esperar} = copia;
assert.equal(sql(foto),antes);
assert.equal(cargarHistoricosPrueba(sql).instalado,true,'Se prueba el bloque instalado, sin reemplazarlo');
const dineroAntes = sql(dinero);
const usuarios = leer('fixtures.json').usuarios;
const claims = `set role authenticated; set request.jwt.claims=${q(JSON.stringify({sub:usuarios.gerencia.id,role:'authenticated'}))};`;
const comoGerencia = sentencia => sql(`${claims} ${sentencia}`);
const censo = (tipo,id) => JSON.parse(sql(`select private.inversion_historica_estado(${q(tipo)},${q(id)})`));
const aplicar = (lote,vista) => `select private.inversion_historica_aplicar(${q(lote)},${q(JSON.stringify([vista]))}::jsonb);`;
const contrato = numero => sql(`select id from public.contratos where numero_contrato=${q(numero)}`);
const cierre = nombre => sql(`select id from crm.cierres_externos where numero_transaccion=${q(nombre)}`);
const huellasF3 = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid))) order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm'
  and p.proname in ('corregir_documento_inversionista_fn','fusion_previsualizar_fn','fusionar_inversionistas_fn','reasignar_responsable_relacion_fn')`));
const sesiones = new Set(), pruebas = [];
const abrir = nombre => {const s=abrirSesion(nombre);sesiones.add(s);return s;};
const terminar = async (s,fin='commit;') => {const r=await s.cerrar(fin);sesiones.delete(s);return r;};
const ok = r => {assert.equal(r.codigo,0,r.error);return r;};
async function retener(nombre,sentencia) {
  const s=abrir(nombre);
  s.enviar(`begin; set local lock_timeout='5s'; ${sentencia}; select 'OPERACION_HECHA';`);
  await esperar(()=>s.salida().includes('OPERACION_HECHA'),'La primera operación no completó dentro de su transacción');
  return s;
}
async function observar(nombre) {
  await esperar(()=>sql(`select count(*) from pg_stat_activity where datname=current_database()
    and application_name=${q(nombre)} and wait_event='advisory'`)==='1','No se observó la espera del candado de identidad');
}
function nuevoDocumento() {
  let d;
  do {d=`96${String(randomInt(1_000_000)).padStart(6,'0')}`;}
  while(sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(d)}`)!=='0');
  return d;
}
function correccion(persona) {
  const previo=sql(`select id from crm.inversionista_identificadores where inversionista_id=${q(persona)}
    and estado='vigente' and verificado order by (tipo_documento='DNI') desc,id limit 1`);
  return `select crm.corregir_documento_inversionista_fn(${q(persona)},'DNI',${q(nuevoDocumento())},
    'Corrección sintética concurrente con enlace histórico',${q(previo)});`;
}
function crearCanonica() {
  const id=randomUUID();
  sql(`insert into crm.inversionistas(id,creado_por) values(${q(id)},${q(usuarios.gerencia.id)})`);
  comoGerencia(`select crm.corregir_documento_inversionista_fn(${q(id)},'DNI',${q(nuevoDocumento())},'Verificación de ficha sintética del ensayo',null);`);
  comoGerencia(`select crm.reasignar_responsable_relacion_fn(${q(id)},${q(usuarios.vendedor.id)},'Responsable de ficha sintética del ensayo');`);
  return id;
}
function fusion(perdedora,canonica) {
  const p=JSON.parse(comoGerencia(`select crm.fusion_previsualizar_fn(${q(perdedora)},${q(canonica)})`));
  assert.equal(p.viable,true,JSON.stringify(p.bloqueos));
  return `select crm.fusionar_inversionistas_fn(${q(perdedora)},${q(canonica)},'Fusión sintética concurrente con enlace histórico',${q(p.hash)});`;
}
function exigirResuelto(tipo,id,persona) {
  const x=censo(tipo,id);
  assert.equal(x.estado,'resuelto'); assert.equal(x.persona,persona);
  assert.equal(sql(`select count(*) from crm.inversiones where ${tipo==='contrato'?'contrato_id':'cierre_externo_id'}=${q(id)}`),'1');
  assert.equal(sql(`select count(*) from crm.inversion_titulares where inversion_id=${q(x.inversion)} and rol='principal' and inversionista_id=${q(persona)}`),'1');
  assert.equal(sql(dinero),dineroAntes,'La operación de identidad no debe alterar dinero, PDF ni atribución histórica');
  return x;
}
async function identidadPrimero(nombre,tipo,id,cambio,personaFinal) {
  const vista=censo(tipo,id), lote=randomUUID();
  const identidad=await retener('f4_hi_identidad',`${claims} ${cambio}`);
  const loteSesion=abrir('f4_hi_lote');loteSesion.enviar(aplicar(lote,vista));
  await observar('f4_hi_lote');ok(await terminar(identidad));
  const r=await terminar(loteSesion);
  assert.notEqual(r.codigo,0);assert.match(r.error,/previsualización histórica cambió/);
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(lote)}`),'0');
  sql(aplicar(lote,censo(tipo,id)));
  exigirResuelto(tipo,id,personaFinal);
  pruebas.push({nombre,esperaObservada:true,mapaObsoletoRechazado:true,recensoRecuperable:true});
  console.log(`PASS: ${nombre}`);
}
async function lotePrimero(nombre,tipo,id,cambio,personaFinal,{rehacer}={}) {
  const lote=randomUUID(),vista=censo(tipo,id);
  const mantenimiento=await retener('f4_hi_lote',aplicar(lote,vista));
  const identidad=abrir('f4_hi_identidad');identidad.enviar(`${claims} ${cambio}`);
  await observar('f4_hi_identidad');ok(await terminar(mantenimiento));
  const r=await terminar(identidad);
  if(rehacer) {
    assert.notEqual(r.codigo,0);assert.match(r.error,/previsualización caducó/);
    comoGerencia(rehacer());
  } else ok(r);
  const x=exigirResuelto(tipo,id,personaFinal);
  const replay=JSON.parse(sql(aplicar(lote,vista)));
  assert.equal(replay.fuentes[0].inversion,x.inversion,'La relectura del acta no crea otra inversión');
  pruebas.push({nombre,esperaObservada:true,unaInversion:true,previsualizacionFusionRenovada:!!rehacer});
  console.log(`PASS: ${nombre}`);
}
try {
  const id1=contrato('F4-BASE-INICIAL'),p1=censo('contrato',id1).persona;
  await identidadPrimero('Corrección primero: lote exige recenso y conserva dinero/PDF','contrato',id1,correccion(p1),p1);
  const id2=contrato('F4-BASE-UPGRADE-MISMO-MES');
  await lotePrimero('Lote primero: corrección posterior conserva inversión y documento contractual','contrato',id2,correccion(p1),p1);

  const id3=cierre('F4-BASE-prodelco'),p3=censo('cierre',id3).persona,c3=crearCanonica();
  await identidadPrimero('Fusión primero: recenso enlaza solo la identidad canónica','cierre',id3,fusion(p3,c3),c3);
  const id4=cierre('F4-BASE-qorilazo'),p4=censo('cierre',id4).persona,c4=crearCanonica();
  await lotePrimero('Lote primero: fusión exige otra previsualización y conserva la misma inversión','cierre',id4,fusion(p4,c4),c4,{rehacer:()=>fusion(p4,c4)});

  const id5=contrato('F4-BASE-UPGRADE-ELEGIBLE');
  const reasignar=responsable=>`select crm.reasignar_responsable_relacion_fn(${q(p1)},${q(responsable)},'Reasignación sintética concurrente con enlace histórico');`;
  await identidadPrimero('Reasignación primero: censo obsoleto rechazado sin cambiar atribución histórica','contrato',id5,reasignar(usuarios.ajeno.id),p1);
  const id6=contrato('F4-BASE-UPGRADE-ADICIONAL');
  await lotePrimero('Lote primero: reasignación posterior conserva la atribución original','contrato',id6,reasignar(usuarios.vendedor.id),p1);
} finally {
  for(const s of sesiones) await terminar(s,'rollback;');
  assert.equal(sqlOriginal(foto),antes,'El banco original debe permanecer intacto');
}
const sha=x=>createHash('sha256').update(x).digest('hex');
writeFileSync(new URL(`../evidencia-f4/historicos-identidad-${copia.id}.json`,import.meta.url),JSON.stringify({
  entorno,baseCopia:copia.nombre,ejecucion:copia.id,terminadoEn:new Date().toISOString(),pruebas,
  bancoOriginalSinCambios:true,funcionesF3SinModificar:huellasF3,huellasOriginales:JSON.parse(antes),
  sha256Oraculo:sha(readFileSync(new URL(import.meta.url))),
  limites:['RPC SQL reales con rol y claims ficticios; no es una prueba HTTP ni duplica Storage/cron/replicación.',
    'No cubre todavía todos los escritores administrativos ni constituye reconstrucción del corpus F2. G4 abierto.'],
},null,2)+'\n',{flag:'wx'});
console.log(`Históricos e identidad: ${pruebas.length} carreras conformes; copia ${copia.nombre}.`);
