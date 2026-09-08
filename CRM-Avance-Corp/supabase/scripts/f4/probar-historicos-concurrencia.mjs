import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { literal as q, leer, sql as sqlOriginal } from './banco-local.mjs';
import { crearCopiaSql } from './copia-sql-local.mjs';
import { cargarHistoricosPrueba } from './cargar-historicos-prueba.mjs';

const foto = `select jsonb_object_agg(tabla,huella) from (
  select 'contratos' tabla,private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) huella from public.contratos t
  union all select 'cuotas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.cronograma_pagos t
  union all select 'cierres',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.cierres_externos t
  union all select 'personas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionistas t
  union all select 'identificadores',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionista_identificadores t
  union all select 'leads',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.leads t
  union all select 'documentos',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.documentos t
  union all select 'titularesDocumentales',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.contrato_titulares t
  union all select 'inversiones',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversiones t
  union all select 'titulares',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversion_titulares t
  union all select 'capital',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'))
    from private.capital_episodios('-infinity','infinity',true,'{}') t
  union all select 'perfiles',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.perfiles t
  union all select 'mapaF2',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.backfill_multiempresa_mapa t
  union all select 'pdf',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.contrato_id),'[]')) from private.contrato_pdfs t
) fotos`;
const original = sqlOriginal(foto);
const fuentes = foto => {
  const { inversiones, titulares, ...resto } = JSON.parse(foto);
  return resto;
};
const copia = crearCopiaSql('historicos');
const { sql, abrirSesion, esperar } = copia;
assert.equal(sql(foto), original, 'La copia debe conservar sus fuentes ficticias');
const definiciones = ['07-historicos.sql','08-historicos-lote.sql'].map(nombre => ({
  nombre, contenido: readFileSync(new URL(nombre, import.meta.url),'utf8'),
}));
const carga=cargarHistoricosPrueba(sql);
if (!carga.instalado) sql(`begin; ${carga.preparacion} commit;`);
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"),'f');
const mapaSql = `select jsonb_agg(private.inversion_historica_estado(tipo,id) order by tipo,id) from (
  select 'contrato'::text tipo,id from public.contratos where numero_contrato like 'F4-BASE-%'
  union all select 'cierre',id from crm.cierres_externos where numero_transaccion like 'F4-BASE-%'
) fuentes`;
const mapa = () => JSON.parse(sql(mapaSql));
const aplicar = (lote, censo) => `select private.inversion_historica_aplicar(${q(lote)},${q(JSON.stringify(censo))}::jsonb);`;
const actas = () => Number(sql('select count(*) from crm.inversion_backfill_lotes'));
const pruebas = [];
const vivas = new Set();
function sesion(nombre) {
  const s = abrirSesion(nombre); vivas.add(s); return s;
}
async function fin(s, texto = 'commit;') {
  const r = await s.cerrar(texto); vivas.delete(s); return r;
}
function ok(r) { assert.equal(r.codigo,0,r.error); return r; }
async function retener(nombre, sentencia) {
  const s = sesion(nombre);
  s.enviar(`begin; set local lock_timeout='3s'; ${sentencia}; select 'LISTO';`);
  await esperar(() => s.salida().includes('LISTO'),'El retenedor no obtuvo el candado');
  return s;
}
async function bloqueados(nombres) {
  await esperar(() => Number(sql(`select count(*) from pg_stat_activity where datname=current_database()
    and application_name=any(array[${nombres.map(q).join(',')}]) and wait_event='advisory'`))===nombres.length,
  'La concurrencia debe observarse dentro de PostgreSQL');
}
async function carrera(nombre, izquierda, derecha) {
  const puerta = await retener('f4_h_retencion',"select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'))");
  const a=sesion('f4_h_izquierda'), b=sesion('f4_h_derecha');
  a.enviar(izquierda); b.enviar(derecha);
  await bloqueados(['f4_h_izquierda','f4_h_derecha']);
  ok(await fin(puerta));
  const r = await Promise.all([fin(a),fin(b)]);
  pruebas.push({ nombre, procesosObservados:2 });
  return r;
}
try {
  const inicial=mapa(), censo=inicial.slice(0,3), lote=randomUUID(), n=actas();
  assert.equal(inicial.length,6);
  const r=await carrera('Mismo lote simultáneo: un acta y un resultado',aplicar(lote,censo),aplicar(lote,[...censo].reverse()));
  r.forEach(ok);
  assert.deepEqual(JSON.parse(r[0].salida),JSON.parse(r[1].salida));
  assert.equal(actas(),n+1);
  assert(mapa().filter(x=>censo.some(c=>c.id===x.id)).every(x=>x.estado==='resuelto'));
  assert.deepEqual(fuentes(sql(foto)),fuentes(original));
  console.log('PASS: Mismo lote concurrente sin duplicación');

  const restantes=inicial.slice(3), nSolapados=actas();
  const solapados=await carrera('Dos lotes diferentes sobre fuentes pendientes: uno gana y otro exige recenso',
    aplicar(randomUUID(),restantes),aplicar(randomUUID(),restantes));
  assert.equal(solapados.filter(r=>r.codigo===0).length,1);
  assert.match(solapados.find(r=>r.codigo!==0).error,/previsualización histórica cambió/);
  assert.equal(actas(),nSolapados+1);
  assert(mapa().every(x=>x.estado==='resuelto'));
  assert.deepEqual(fuentes(sql(foto)),fuentes(original));
  console.log('PASS: Lotes distintos sobre las mismas fuentes no duplican');

  const actual=mapa(), conflicto=randomUUID(), n2=actas();
  const respuestas=await carrera('Mismo lote con mapas distintos: una ganadora y un conflicto',
    aplicar(conflicto,actual),aplicar(conflicto,actual.slice(0,1)));
  assert.equal(respuestas.filter(x=>x.codigo===0).length,1);
  assert.match(respuestas.find(x=>x.codigo!==0).error,/otra previsualización/);
  assert.equal(actas(),n2+1);
  assert.deepEqual(fuentes(sql(foto)),fuentes(original));
  console.log('PASS: Mapas concurrentes distintos no se sobrescriben');

  // El escritor publicado se invoca con rol y claims de un usuario ficticio.
  // El lote ya retornó pero conserva su transacción: debe retener la puerta F4
  // hasta COMMIT, y después el escritor debe observar la bandera apagada.
  const solicitud=sql('select id from crm.inversion_solicitudes order by id limit 1');
  assert(solicitud,'Se requiere una solicitud real del banco');
  const operador=leer('fixtures.json').usuarios.gerencia.id;
  const mantenimiento=await retener('f4_h_lote_real',aplicar(randomUUID(),mapa()));
  const escritor=sesion('f4_h_confirmacion_real');
  escritor.enviar(`set request.jwt.claims=${q(JSON.stringify({sub:operador,role:'authenticated'}))};
    set role authenticated; select crm.confirmar_inversion_fn(${q(solicitud)});`);
  await bloqueados(['f4_h_confirmacion_real']);
  ok(await fin(mantenimiento));
  const denegada=await fin(escritor);
  assert.notEqual(denegada.codigo,0);
  assert.match(denegada.error,/El registro multiempresa todavía no está habilitado/);
  assert.deepEqual(fuentes(sql(foto)),fuentes(original));
  pruebas.push({nombre:'Confirmación real espera al commit del lote y luego observa F4 apagada',procesosObservados:1});
  console.log('PASS: Confirmación real serializada con mantenimiento');

  const contrato=actual.find(x=>x.tipo==='contrato').id;
  const retenedor=await retener('f4_h_fuente',`select id from public.contratos where id=${q(contrato)} for update`);
  const loteOcupado=randomUUID(), ocupado=sesion('f4_h_nowait');
  const inicio=Date.now();
  ocupado.enviar(aplicar(loteOcupado,mapa()));
  const rechazo=await fin(ocupado);
  assert.notEqual(rechazo.codigo,0); assert.match(rechazo.error,/could not obtain lock/);
  assert(Date.now()-inicio<5000,'La fuente ocupada debe rechazar sin esperar a otro candado');
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(loteOcupado)}`),'0');
  ok(await fin(retenedor,'rollback;'));
  sql(aplicar(loteOcupado,mapa()));
  pruebas.push({nombre:'Fuente retenida: rechazo NOWAIT sin acta, reintento recuperable',rechazoSinEfectos:true});
  console.log('PASS: Fuente ocupada y recuperación');

  // Una escritura de mantenimiento se confirma mientras la otra conexión espera
  // la bandera. Debe releer con READ COMMITTED, rechazar el mapa anterior y aceptar
  // exclusivamente el censo nuevo. La fixture modifica solo la copia descartable.
  const anterior=mapa(), fuente=anterior.find(x=>x.tipo==='cierre');
  const editor=await retener('f4_h_editor',"select pg_advisory_xact_lock(hashtext('crm_flag_resolver_en_puertas'))");
  const esperando=sesion('f4_h_deriva'), loteDeriva=randomUUID();
  esperando.enviar(aplicar(loteDeriva,anterior));
  await bloqueados(['f4_h_deriva']);
  editor.enviar(`set local crm.op_privilegiada='on'; update crm.cierres_externos
    set referencia_externa=referencia_externa||' ENSAYO DE DERIVA' where id=${q(fuente.id)};`);
  ok(await fin(editor));
  const deriva=await fin(esperando);
  assert.notEqual(deriva.codigo,0); assert.match(deriva.error,/previsualización histórica cambió/);
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(loteDeriva)}`),'0');
  sql(aplicar(loteDeriva,mapa()));
  pruebas.push({nombre:'Cambio confirmado mientras espera: mapa antiguo rechazado y recenso recuperable',procesosObservados:1});
  console.log('PASS: Deriva durante espera detectada');

  // Cortar la conexión tras obtener resultado pero antes de COMMIT: el resultado
  // mostrado por la función no es todavía una confirmación durable.
  const loteCorte=randomUUID(), corte=sesion('f4_h_corte');
  corte.enviar(`begin; ${aplicar(loteCorte,mapa())} select 'RESULTADO_SIN_COMMIT';`);
  await esperar(()=>corte.salida().includes('RESULTADO_SIN_COMMIT'),'No alcanzó el punto anterior al commit');
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(loteCorte)}`),'0');
  ok(await fin(corte,'')); // EOF sin COMMIT: PostgreSQL revierte al desconectar.
  assert.equal(sql(`select count(*) from crm.inversion_backfill_lotes where id=${q(loteCorte)}`),'0');
  const recuperado=sql(aplicar(loteCorte,mapa()));
  assert.equal(JSON.parse(recuperado).lote,loteCorte);
  pruebas.push({nombre:'Conexión cerrada antes del commit: sin acta parcial y recuperación',desconexionReal:true});
  console.log('PASS: Desconexión real antes del commit y recuperación');
} finally {
  for (const s of vivas) await fin(s,'rollback;');
  assert.equal(sqlOriginal(foto),original,'El banco original debe permanecer intacto');
}
const sha=x=>createHash('sha256').update(x).digest('hex');
const informe={entorno:'avancecorp-f4-bank',baseCopia:copia.nombre,ejecucion:copia.id,
  terminadoEn:new Date().toISOString(),pruebas,bancoOriginalSinCambios:true,
  definiciones:definiciones.map(d=>({nombre:d.nombre,sha256:sha(d.contenido)})),
  sha256Oraculo:sha(readFileSync(new URL(import.meta.url))),
  limites:['Copia SQL de datos sintéticos; no comprueba HTTP ni duplica el almacenamiento de archivos.',
    'No duplica pg_cron ni replicación; aún no demuestra ausencia de interferencias de todos los trabajos programados.',
    'La prueba conserva la instalación del banco original. G4 permanece abierto.']};
writeFileSync(new URL(`../evidencia-f4/historicos-concurrencia-${copia.id}.json`,import.meta.url),JSON.stringify(informe,null,2)+'\n',{flag:'wx'});
console.log(`Históricos: ${pruebas.length} grupos conformes; copia conservada en ${copia.nombre}.`);
