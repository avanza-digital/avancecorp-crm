// Readback de un ensayo local interrumpido; nunca transforma su FAIL original en PASS.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {leer,sql,literal as q,http,sesion,entorno} from './banco-local.mjs';
const id=process.argv[2];assert(/^[a-f0-9-]{36}$/.test(id),'UUID de ensayo local requerido');
const previo=leer(`pdf-real-${id}-interrumpido.json`);assert.equal(previo.ejecucion,id);assert(previo.error);
const f=leer('fixtures.json'),token=await sesion(f.usuarios.gerencia,f.password),contratos=[];
for(const c of previo.contratos){
 const jobs=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('id',id,'estado',estado,'snapshot_sha',encode(extensions.digest(snapshot::text,'sha256'),'hex'),'storage_path',storage_path)) from private.contrato_pdf_jobs where contrato_id=${q(c.id)}`));
 assert.equal(jobs.length,1);const job=jobs[0];assert.equal(job.id,c.inicial.id);assert.equal(job.snapshot_sha,c.inicial.snapshot_sha);assert.equal(job.storage_path,c.inicial.storage_path);assert.equal(job.estado,'sellado');
 assert.equal(sql(`select count(*) from private.contrato_pdfs where contrato_id=${q(c.id)}`),'1');
 assert.equal(sql(`select count(*) from crm.inversiones where contrato_id=${q(c.id)} and id=${q(c.inversionId)}`),'1');
 assert.equal(sql(`select count(*) from storage.objects where bucket_id='contratos-generados' and name=${q(job.storage_path)}`),'1');
 const r=await http('/functions/v1/crm-contrato-pdf-v2',{token,body:{action:'ensure',contratoId:c.id}});assert.equal(r.status,200,JSON.stringify(r.data));
 assert.equal(r.data.pdf.estado,'sellado');
 const bytes=await http(`/storage/v1/object/contratos-generados/${job.storage_path}`,{admin:true,method:'GET',binary:true});assert.equal(bytes.ok,true);
 const sha256=createHash('sha256').update(bytes.data).digest('hex');assert.equal(sha256,r.data.pdf.sha256);assert.equal(bytes.data.length,r.data.pdf.bytes);
 contratos.push({etiqueta:c.etiqueta,jobOriginalConservado:true,snapshotOriginalConservado:true,fuenteInversionPdfYObjetoUnicos:true,estado:job.estado,sha256,bytes:bytes.data.length});
}
writeFileSync(new URL(`../evidencia-f4/pdf-recuperacion-${id}.json`,import.meta.url),JSON.stringify({entorno,ejecucion:id,verificadoEn:new Date().toISOString(),
 ensayoOriginal:{estado:'FAIL',gruposTerminados:previo.pruebas.length,error:previo.error},recuperacion:{estado:'PASS',contratos},
 procedimiento:'Tras vencer leases reales se reinició únicamente el runtime local con política per_worker predeterminada. Los dos ensure pendientes devolvieron 200; este readback verifica los diez trabajos y sus bytes.',
 limites:['No se cambió el renderer, la plantilla, los recursos, el presupuesto CPU, el reloj, los leases ni estados SQL.','Una recuperación y una regresión completa posterior no certifican rendimiento productivo ni determinan la causa raíz de WORKER_LIMIT.'],
 sha256Oraculo:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),},null,2)+'\n',{flag:'wx'});
console.log(`Readback PDF: ${contratos.length} trabajos originales sellados, una fuente y un objeto cada uno; bytes conformes.`);
