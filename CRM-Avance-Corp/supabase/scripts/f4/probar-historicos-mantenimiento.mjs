import { entorno } from './banco-local.mjs';
// Mantenimiento F2 concurrente: usa su helper original, sin reejecutar F2 global.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { sql as sqlOriginal, literal as q } from './banco-local.mjs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { cargarHistoricosPrueba } from './cargar-historicos-prueba.mjs';

const tablas=['public.contratos','public.cronograma_pagos','public.perfiles','crm.cierres_externos',
  'crm.leads','crm.inversionistas','crm.inversionista_identificadores','crm.backfill_multiempresa_mapa',
  'crm.inversiones','crm.inversion_titulares','crm.inversion_backfill_lotes','private.contrato_pdfs'];
const foto=`select jsonb_object_agg(tabla,huella) from (${tablas.map(t=>`select ${q(t)} tabla,
  private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')) huella from ${t} t`).join(' union all ')}) x`;
const original=sqlOriginal(foto),copia=crearCopiaSql('historicos_mapa');
const {sql,abrirSesion,esperar}=copia;
assert.equal(sql(foto),original);
assert.equal(cargarHistoricosPrueba(sql).instalado,true);
const fuentes=JSON.parse(sql(`select jsonb_agg(private.inversion_historica_estado('cierre',id) order by numero_transaccion)
  from crm.cierres_externos where numero_transaccion like 'F4-BASE-%'`));
assert.equal(fuentes.length,2);
const fuente=fuentes[0],otra=fuentes[1];
const censo=()=>JSON.parse(sql(`select private.inversion_historica_estado('cierre',${q(fuente.id)})`));
const aplicar=(id,vista)=>`select private.inversion_historica_aplicar(${q(id)},${q(JSON.stringify([vista]))}::jsonb);`;
const mapear=(persona)=>`select private.f2_mapear('cierre',${q(fuente.id)},${q(persona)},'B','Ensayo sintético del mantenimiento F2','alta');`;
const hashFuncion=sql("select md5(pg_get_functiondef('private.inversion_historica_aplicar(uuid,jsonb)'::regprocedure))");
const sesiones=new Set(),pruebas=[];
let pruebaActual='';
const abrir=nombre=>{const s=abrirSesion(nombre);s.enviar('\\set VERBOSITY verbose');sesiones.add(s);return s;};
const terminar=async(s,fin='commit;')=>{const r=await s.cerrar(fin);sesiones.delete(s);return r;};
const ok=r=>{assert.equal(r.codigo,0,r.error);return r;};
async function retener(nombre,sentencia){
  const s=abrir(nombre);s.enviar(`begin; set local lock_timeout='5s'; ${sentencia} select 'OPERACION_LISTA';`);
  await esperar(()=>s.salida().includes('OPERACION_LISTA'),'No completó el primer mantenimiento');return s;
}
try {
  pruebaActual='Mapa F2 insertado sin confirmar: lote NOWAIT rechaza y luego recupera';
  assert.equal(sql(`select count(*) from crm.backfill_multiempresa_mapa where fuente='cierre' and fila_id=${q(fuente.id)}`),'0');
  const escritor=await retener('f4_hm_f2',mapear(otra.persona));
  const lote=randomUUID(),loteSesion=abrir('f4_hm_lote');loteSesion.enviar(aplicar(lote,fuente));
  const r=await terminar(loteSesion);
  assert.notEqual(r.codigo,0,'El lote confirmó mientras el mapa F2 tenía una inserción en curso');
  assert.match(r.error,/55P03:.*relation \"crm\.backfill_multiempresa_mapa\"/);
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(lote)}`),'0');
  ok(await terminar(escritor,'rollback;'));
  sql(aplicar(lote,censo()));assert.equal(censo().estado,'resuelto');
  pruebas.push({nombre:pruebaActual,rechazoSinActa:true,recuperacion:true});console.log(`PASS: ${pruebaActual}`);

  pruebaActual='Lote primero: insertar mapa espera hasta el commit';
  const mantenimiento=await retener('f4_hm_lote',aplicar(randomUUID(),censo()));
  const f2=abrir('f4_hm_f2');f2.enviar(`begin; set local lock_timeout='5s'; ${mapear(fuente.persona)}`);
  await esperar(()=>sql("select count(*) from pg_stat_activity where datname=current_database() and application_name='f4_hm_f2' and wait_event='relation'")==='1',
    'F2 debe esperar por el conjunto de mapa, incluida una fila nueva');
  ok(await terminar(mantenimiento));ok(await terminar(f2));
  assert.equal(censo().estado,'resuelto');
  pruebas.push({nombre:pruebaActual,esperaObservada:true});console.log(`PASS: ${pruebaActual}`);

  pruebaActual='UPDATE de mapa existente sin confirmar también impide el lote';
  const actual=censo();
  const editor=await retener('f4_hm_f2',mapear(otra.persona));
  const segundo=randomUUID(),concurrente=abrir('f4_hm_lote');concurrente.enviar(aplicar(segundo,actual));
  const bloqueo=await terminar(concurrente);
  assert.notEqual(bloqueo.codigo,0);assert.match(bloqueo.error,/55P03:.*relation \"crm\.backfill_multiempresa_mapa\"/);
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(segundo)}`),'0');
  ok(await terminar(editor,'rollback;'));
  const fotoAntes=sql(foto);sql(aplicar(segundo,censo()));
  const quitarActas=txt=>{const {'crm.inversion_backfill_lotes':actas,...resto}=JSON.parse(txt);return resto;};
  assert.deepEqual(quitarActas(sql(foto)),quitarActas(fotoAntes));
  pruebas.push({nombre:pruebaActual,reintentoSinReescribirInversion:true});console.log(`PASS: ${pruebaActual}`);
  pruebaActual='DELETE del mapa sin confirmar rechaza sin acta';
  const borrar=await retener('f4_hm_f2',`delete from crm.backfill_multiempresa_mapa where fuente='cierre' and fila_id=${q(fuente.id)};`);
  const borradoId=randomUUID(),borradoSesion=abrir('f4_hm_lote');borradoSesion.enviar(aplicar(borradoId,censo()));
  const borrado=await terminar(borradoSesion);
  assert.match(borrado.error,/55P03:.*relation "crm\.backfill_multiempresa_mapa"/);
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(borradoId)}`),'0');
  ok(await terminar(borrar,'rollback;'));
  pruebas.push({nombre:pruebaActual,rechazoSinActa:true});console.log(`PASS: ${pruebaActual}`);

  // Forma de INSERT del ejecutor F2: fuente con persona ya asignada. No usa
  // el helper F4, de modo que no se introduce un candado que F2 no tendría.
  const insertarInversion=`insert into crm.inversiones(inversionista_id,empresa_id,cierre_externo_id,
    estado,fecha_comercial,es_primera_conversion,creado_por)
    select ce.inversionista_id,e.id,ce.id,'vigente',ce.fecha_comercial,true,ce.creado_por
    from crm.cierres_externos ce join crm.empresas e on e.clave=ce.cooperativa where ce.id=${q(otra.id)};`;
  const invertir=sql(`select id from crm.inversiones where cierre_externo_id=${q(fuente.id)}`);
  const casos=[
    {nombre:'INSERT de inversión sin confirmar',vista:otra,escritura:insertarInversion,relacion:'inversionistas'},
    {nombre:'INSERT de identificador sin confirmar',vista:fuente,escritura:`insert into crm.inversionista_identificadores
      (inversionista_id,tipo_documento,documento_normalizado,documento_original,estado,verificado,fuente)
      values(${q(fuente.persona)},'CE','987654321987','987654321987','vigente',true,'ensayo-F2');`,relacion:'inversionistas'},
    {nombre:'INSERT de cotitular sin confirmar',vista:fuente,escritura:`insert into crm.inversion_titulares(inversion_id,inversionista_id,rol)
      values(${q(invertir)},${q(otra.persona)},'cotitular');`,relacion:'inversiones'},
  ];
  for(const caso of casos){
    pruebaActual=caso.nombre+': FK impide que el lote confirme';
    const vista=JSON.parse(sql(`select private.inversion_historica_estado('cierre',${q(caso.vista.id)})`));
    const externo=await retener('f4_hm_f2',caso.escritura),id=randomUUID(),s=abrir('f4_hm_lote');
    s.enviar(aplicar(id,vista));const rechazo=await terminar(s);
    assert.notEqual(rechazo.codigo,0,'El lote debe rechazar ante la FK concurrente');
    assert.match(rechazo.error,new RegExp('55P03:.*relation "'+caso.relacion+'"'));
    assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(id)}`),'0');
    ok(await terminar(externo,'rollback;'));
    const recuperada=await retener('f4_hm_lote',aplicar(id,vista));ok(await terminar(recuperada,'rollback;'));
    pruebas.push({nombre:pruebaActual,relacionBloqueada:caso.relacion,rechazoSinActa:true,reintentoTrasRollback:true});
    console.log(`PASS: ${pruebaActual}`);
  }

  pruebaActual='Lote primero: INSERT legado espera y unicidad rechaza la segunda inversión';
  const vistaOtra=JSON.parse(sql(`select private.inversion_historica_estado('cierre',${q(otra.id)})`));
  const primero=await retener('f4_hm_lote',aplicar(randomUUID(),vistaOtra));
  const rival=abrir('f4_hm_f2');rival.enviar(`begin;set local lock_timeout='5s';${insertarInversion}`);
  await esperar(()=>sql("select count(*) from pg_stat_activity where datname=current_database() and application_name='f4_hm_f2' and wait_event='transactionid'")==='1','La segunda inversión debe esperar');
  ok(await terminar(primero));const perdedora=await terminar(rival);
  assert.match(perdedora.error,/23505:.*inversiones_cierre_uidx/);
  assert.equal(sql(`select count(*) from crm.inversiones where cierre_externo_id=${q(otra.id)}`),'1');
  pruebas.push({nombre:pruebaActual,esperaObservada:true,sqlstate:'23505',unaInversion:true});console.log(`PASS: ${pruebaActual}`);

} catch(error) {
  writeFileSync(new URL(`../evidencia-f4/historicos-mantenimiento-hallazgo-${copia.id}.json`,import.meta.url),JSON.stringify({
    entorno,baseCopia:copia.nombre,ejecucion:copia.id,prueba:pruebaActual,
    md5Funcion:hashFuncion,error:error.message,funcionBajoPrueba:'private.inversion_historica_aplicar(uuid,jsonb)',
    produccionModificada:false,resultado:'FAIL',
  },null,2)+'\n',{flag:'wx'});
  throw error;
} finally {
  for(const s of sesiones)await terminar(s,'rollback;');
  assert.equal(sqlOriginal(foto),original,'El banco original debe permanecer intacto');
}
writeFileSync(new URL(`../evidencia-f4/historicos-mantenimiento-${copia.id}.json`,import.meta.url),JSON.stringify({
  entorno,baseCopia:copia.nombre,ejecucion:copia.id,terminadoEn:new Date().toISOString(),pruebas,
  md5Funcion:hashFuncion,bancoOriginalSinCambios:true,
  sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),
  limite:'Cruces con el helper administrativo F2 de mapa e inserciones de sus tablas relacionadas; no autoriza reejecutar F2 global ni representa HTTP/Storage/cron.',
},null,2)+'\n',{flag:'wx'});
console.log(`Mantenimiento F2/F4: ${pruebas.length} grupos conformes.`);
