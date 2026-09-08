import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {crearCopiaSql} from './copia-sql-local.mjs';
import {entorno,sql as originalSql,literal as q,leer} from './banco-local.mjs';
assert.equal(entorno,'avancecorp-f4-reconstruccion');
const baseOrigen=originalSql("select to_regclass('crm.inversion_solicitudes') is null")==='t'?'postgres':leer('respaldo-pre-f4.json').nombre;
const copia=crearCopiaSql('corpus_fdos',{baseOrigen}),{sql}=copia,pruebas=[];
assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"),'t','El corpus parte del respaldo anterior a F4');
const semilla=readFileSync(new URL('../siembra-banco-f2.sql',import.meta.url),'utf8');
const oraculo=readFileSync(new URL('../oraculo-f2-idempotencia.sql',import.meta.url),'utf8');
const {archivo}=JSON.parse(readFileSync(new URL('./ultima-migracion.json',import.meta.url),'utf8'));
const candidata=readFileSync(new URL(`../../migrations/${archivo}`,import.meta.url),'utf8');
const hash=x=>createHash('sha256').update(x).digest('hex');
const fuenteFoto=`select private.idem_hash(jsonb_build_object(
 'contratos',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
 'cuotas',(select jsonb_agg(to_jsonb(c) order by id) from public.cronograma_pagos c),
 'cierres',(select jsonb_agg(jsonb_build_object('id',id,'lead',lead_id,'coop',cooperativa,'monto',monto,'moneda',moneda,
 'doc',documento,'fecha',creado_en,'vendedor',vendedor_id,'anulado',anulado_en) order by id) from crm.cierres_externos),
 'capital',(select jsonb_agg(to_jsonb(k) order by to_jsonb(k)::text) from private.capital_episodios('-infinity','infinity',true,'{}') k)))`;
const original=originalSql(fuenteFoto);
function caso(nombre,fn){fn();pruebas.push({nombre,conforme:true});console.log('PASS: '+nombre);}
try{
 sql("update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura')");
 caso('Inventario nuevo de funciones rechaza instalación sin dejar tablas F4',()=>{
  sql("create function private.f4_consumidor_no_clasificado() returns bigint language sql as $$ select count(*) from crm.cierres_externos $$",{admin:true});
  assert.throws(()=>sql(candidata,{admin:true}),/cambió el inventario de consumidores/);
  assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"),'t');
  sql('drop function private.f4_consumidor_no_clasificado()',{admin:true});
 });
 caso('Vista consumidora nueva rechaza instalación sin modificar historia',()=>{
  sql('create view private.f4_vista_no_clasificada as select id from crm.cierres_externos',{admin:true});
  assert.throws(()=>sql(candidata,{admin:true}),/vista o política consumidora sin clasificar/);
  assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"),'t');
  sql('drop view private.f4_vista_no_clasificada',{admin:true});
 });
 sql(semilla);
 const resultadoF2=JSON.parse(sql('select private.backfill_multiempresa_ejecutar()'));
 caso('Corpus original y pipeline F2 completos con clases A, B, C y E',()=>{
  assert(resultadoF2.A>=4);assert(resultadoF2.B>=1);assert(resultadoF2.C>=2);assert(resultadoF2.E>=4);
  for(const [perfil,clase] of [['a0000000-0000-0000-0000-000000000001','A'],['a0000000-0000-0000-0000-000000000002','A'],
   ['a0000000-0000-0000-0000-000000000003','A'],['e0000000-0000-0000-0000-000000000001','E'],['e0000000-0000-0000-0000-000000000002','E'],
   ['e0000000-0000-0000-0000-000000000003','E']]) assert.equal(sql(`select clase from crm.backfill_multiempresa_mapa where fuente='perfil' and fila_id=${q(perfil)}`),clase);
 });
 caso('Oráculo F2 original: segunda pasada no cambia mapa, auditoría ni conteos',()=>{sql(oraculo);});
 // Añadir fuentes contractuales históricas a cada clase del corpus: copia de
 // fila ficticia previa, F3/F4 apagadas; no se presenta como un alta API moderna.
 const base=leer('operaciones-base.json');
 const contratoBase=typeof base.contratos.inicial==='object'?base.contratos.inicial.id:base.contratos.inicial;
 const perfiles=['a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000003',
 'e0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000003'];
 const contratos=perfiles.map(perfil=>({id:randomUUID(),perfil}));
 for(const c of contratos)sql(`insert into public.contratos(id,cliente_id,numero_contrato,capital,moneda,tasa_anual,modalidad,
  tipo_interes,fecha_inicio,fecha_vencimiento,categoria,analista_cierre_id,creado_por)
  select ${q(c.id)},${q(c.perfil)},${q('F2-HIST-'+c.id)},capital,moneda,tasa_anual,modalidad,tipo_interes,
  fecha_inicio,fecha_vencimiento,categoria,analista_cierre_id,creado_por from public.contratos where id=${q(contratoBase)}`);
 const antes=sql(fuenteFoto),mapaAntes=sql("select private.idem_hash(jsonb_agg(to_jsonb(m) order by id)) from crm.backfill_multiempresa_mapa m");
 caso('Candidata completa se instala sobre salidas F2 sin tocar fuentes ni mapa',()=>{
  sql(candidata,{admin:true});assert.equal(sql(fuenteFoto),antes);
  assert.equal(sql("select private.idem_hash(jsonb_agg(to_jsonb(m) order by id)) from crm.backfill_multiempresa_mapa m"),mapaAntes);
 });
 sql("update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas'");
 const censo=(tipo,id)=>JSON.parse(sql(`select private.inversion_historica_estado(${q(tipo)},${q(id)})`));
 caso('Cierre original F2 resuelto mantiene exactamente inversión y principal',()=>{
  const id='c1e50000-0000-0000-0000-00000000000b',foto=sql(`select jsonb_build_object('i',to_jsonb(i),'t',to_jsonb(t)) from crm.inversiones i
    join crm.inversion_titulares t on t.inversion_id=i.id where i.cierre_externo_id=${q(id)} and t.rol='principal'`);
  const e=censo('cierre',id);assert.equal(e.estado,'resuelto');
  sql(`select private.inversion_historica_aplicar(${q(randomUUID())},${q(JSON.stringify([e]))})`);
  assert.equal(sql(`select jsonb_build_object('i',to_jsonb(i),'t',to_jsonb(t)) from crm.inversiones i join crm.inversion_titulares t
    on t.inversion_id=i.id where i.cierre_externo_id=${q(id)} and t.rol='principal'`),foto);
 });
 caso('Demo excluido por F2 también queda excluido del censo F4',()=>{
  assert.equal(censo('cierre','a112aead-184a-4979-9041-943978fadae4').estado,'excluido_demo');
  assert.equal(sql("select count(*) from crm.inversiones where cierre_externo_id='a112aead-184a-4979-9041-943978fadae4'"),'0');
 });
 caso('Documentos faltantes, inválidos y multirrol siguen en revisión sin inventar identidad',()=>{
  for(const c of contratos.slice(3)) assert.equal(censo('contrato',c.id).estado,'revision');
 });
 caso('DNI, CE y pasaporte resueltos por F2 se vinculan mediante lote F4',()=>{
  const fuentes=contratos.slice(0,3).map(c=>{const e=censo('contrato',c.id);assert.equal(e.estado,'pendiente');return e});
  sql(`select private.inversion_historica_aplicar(${q(randomUUID())},${q(JSON.stringify(fuentes))})`);
  for(const c of contratos.slice(0,3))assert.equal(censo('contrato',c.id).estado,'resuelto');
 });
 caso('Lead duplicado conserva un canónico y su puente histórico, discrepante sigue clase E',()=>{
  assert.equal(sql("select count(*) from crm.inversionista_leads where lead_id in ('1ead0000-0000-0000-0000-0000000000c1','1ead0000-0000-0000-0000-0000000000c2') and rol='canonico'"),'1');
  assert.equal(sql("select clase from crm.backfill_multiempresa_mapa where fuente='lead' and fila_id='1ead0000-0000-0000-0000-0000000000e1'"),'E');
 });
 caso('F4 rechaza una repetición global F2 antes de cualquier escritura',()=>{
  assert.throws(()=>sql("\\set VERBOSITY verbose\nselect private.backfill_multiempresa_ejecutar()"),/55000/);
 });
 caso('Lotes F4 conservan mapa y toda la foto económica del corpus',()=>{
  assert.equal(sql(fuenteFoto),antes);assert.equal(sql("select private.idem_hash(jsonb_agg(to_jsonb(m) order by id)) from crm.backfill_multiempresa_mapa m"),mapaAntes);
 });
 writeFileSync(new URL(`../evidencia-f4/corpus-f2-${copia.id}.json`,import.meta.url),JSON.stringify({entorno,baseCopia:copia.nombre,
  terminadoEn:new Date().toISOString(),pruebas,resultadoF2,sha256Semilla:hash(semilla),sha256OraculoF2:hash(oraculo),sha256Candidata:hash(candidata),
  bancoOriginalSinCambios:true,limites:['Corpus original sintético completo; no contiene registros productivos.','F2 se ejecuta globalmente sólo en la copia PRE-F4; después se usan lotes F4 acotados.','Fuentes contractuales adicionales son fixtures históricas SQL explícitas, sin PDF nuevo.'],
 },null,2)+'\n',{flag:'wx'});
}finally{assert.equal(originalSql(fuenteFoto),original);}
console.log(`Corpus F2: ${pruebas.length} grupos conformes.`);
