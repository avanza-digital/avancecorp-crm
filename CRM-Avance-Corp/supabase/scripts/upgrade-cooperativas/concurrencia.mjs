import assert from 'node:assert/strict'
import {spawn} from 'node:child_process'
import {readFileSync} from 'node:fs'
import {randomUUID} from 'node:crypto'
import {contenedor,db,sql,q,ejecutar} from './banco.mjs'

// Fixtures propias, creadas por las RPC reales. Solo esta copia local conserva
// los datos para las conexiones simultáneas. No acepta destinos externos.
if(sql("select count(*) from crm.cierres_externos where referencia_externa='APORTE SINTETICO'")==='0') {
  const ensayo=readFileSync(new URL('./test.sql',import.meta.url),'utf8')
  assert.match(ensayo,/\nrollback;\s*$/)
  sql(ensayo.replace(/\nrollback;\s*$/,'\ncommit;'))
}
const origen=JSON.parse(sql(`select to_jsonb(x) from (
  select c.id,c.inversionista_id,c.vendedor_id actor,c.cooperativa empresa,c.moneda,
    (select perfil_id from crm.equipo where private.rol_crm(perfil_id)='gerencia' limit 1) gerente,
    (statement_timestamp() at time zone 'America/Lima')::date fecha,
    ((statement_timestamp() at time zone 'America/Lima')::date+interval '12 months')::date vence
  from crm.cierres_externos c where referencia_externa='APORTE SINTETICO' and cooperativa='qorilazo'
    and anulado_en is null order by creado_en desc limit 1) x;`))
const datos=(id)=>({inversionista_id:origen.inversionista_id,empresa:origen.empresa,moneda:origen.moneda,monto:75,
  fecha_comercial:origen.fecha,vence_en:origen.vence,plazo_meses:12,tasa_anual:18,
  numero_transaccion:`RACE-${id}`,referencia:'UPGRADE CONCURRENCIA',evidencia:{ruta:`${origen.inversionista_id}/${id}/comprobante.pdf`}})
const claims=actor=>`set local request.jwt.claim.sub=${q(actor)}; set local role authenticated;`
const call=(actor,consulta)=>JSON.parse(sql(`begin;${claims(actor)}select ${consulta};commit;`))
const preparar=(id,fuente,d)=>call(origen.actor,`crm.preparar_upgrade_fn(${q(id)},${q(fuente)},${q(JSON.stringify(d))})`)
const comprobante=d=>sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(d.evidencia.ruta)},'{"size":128,"mimetype":"application/pdf"}');`)

function sesion(actor,consulta,retener=false) {
  let stdout='',stderr='',ready,failReady
  const lista=new Promise((resolve,reject)=>{ready=resolve;failReady=reject})
  const proceso=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'])
  const terminada=new Promise((resolve,reject)=>{
    proceso.on('error',e=>{failReady(e);reject(e)})
    proceso.on('close',code=>{if(!stdout.includes('READY'))ready();resolve({code,stdout,stderr})})
  })
  proceso.stdout.on('data',b=>{stdout+=b;if(stdout.includes('READY'))ready()})
  proceso.stderr.on('data',b=>{stderr+=b})
  proceso.stdin.end(`\\set VERBOSITY verbose
    begin;set local statement_timeout='10s';${claims(actor)}select ${consulta};
    ${retener?"select 'READY';select pg_sleep(0.6);":''}commit;`)
  return {lista,terminada}
}
async function carrera(primera,segunda) {
  const a=sesion(primera.actor,primera.sql,true)
  await a.lista
  const b=sesion(segunda.actor,segunda.sql)
  const [r1,r2]=await Promise.all([a.terminada,b.terminada])
  assert.equal(r1.code,0,r1.stderr)
  return r2
}

const clave=randomUUID(),d=datos(clave)
let rival=await carrera(
  {actor:origen.actor,sql:`crm.preparar_upgrade_fn(${q(clave)},${q(origen.id)},${q(JSON.stringify(d))})`},
  {actor:origen.actor,sql:`crm.preparar_reinversion_fn(${q(clave)},${q(origen.id)},${q(JSON.stringify(d))})`})
assert.notEqual(rival.code,0)
assert.match(rival.stderr,/P0409|PT409/)
assert.equal(sql(`select tipo from crm.inversion_solicitud_origenes where solicitud_id=${q(clave)}`),'upgrade')
assert.equal(preparar(clave,origen.id,d).upgrade_origen_id,origen.id)
console.log('PASS: dos preparaciones simultáneas con tipos distintos conservan un único upgrade')

comprobante(d)
const confirmar=`crm.confirmar_inversion_revisada_fn(${q(clave)},0)`
rival=await carrera({actor:origen.actor,sql:confirmar},{actor:origen.actor,sql:confirmar})
if(rival.code!==0)assert.match(rival.stderr,/PT409/)
const resultado=call(origen.actor,confirmar)
assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=upper(${q(d.numero_transaccion)})`),'1')
assert.equal(sql(`select count(*) from crm.inversionista_gestiones where tipo='upgrade' and metadata->>'solicitud_id'=${q(clave)}`),'1')
console.log('PASS: dos confirmaciones simultáneas producen una inversión y un evento')

const pendiente=randomUUID(),d2=datos(pendiente),fuente=resultado.fuente.cierre_id
preparar(pendiente,fuente,d2);comprobante(d2)
rival=await carrera(
  {actor:origen.gerente,sql:`crm.anular_cierre_externo(${q(fuente)},'Anulación sintética concurrente')`},
  {actor:origen.actor,sql:`crm.confirmar_inversion_revisada_fn(${q(pendiente)},0)`})
assert.notEqual(rival.code,0)
assert.match(rival.stderr,/P0409|PT409/)
assert.equal(sql(`select estado from crm.inversion_solicitudes where id=${q(pendiente)}`),'preparada')
assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=upper(${q(d2.numero_transaccion)})`),'0')
console.log('PASS: anulación concurrente bloquea confirmar sin dejar un aporte parcial')

const revertir=ejecutar(readFileSync(new URL('./reversa.sql',import.meta.url),'utf8'))
assert.notEqual(revertir.status,0)
assert.match(revertir.stderr,/Hay upgrades registrados/)
assert.equal(sql(`select tipo from crm.inversion_solicitud_origenes where solicitud_id=${q(clave)}`),'upgrade')
console.log('PASS: reversa rechaza eliminar la clasificación cuando ya existen upgrades')
