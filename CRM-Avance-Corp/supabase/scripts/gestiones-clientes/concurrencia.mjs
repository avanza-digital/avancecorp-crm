// Dos conexiones independientes, únicamente al banco sintético sellado.
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import assert from 'node:assert/strict'
const db='gestiones_clientes_20261006', contenedor='supabase_db_crm-avance-corp-local'
const guardia=`do $$ begin if current_database()<>'${db}' or shobj_description((select oid from pg_database where datname=current_database()),'pg_database') is distinct from 'BANCO SINTETICO gestiones clientes 20261006 / sin produccion' then raise exception 'Banco incorrecto'; end if; end $$;`
const actor="set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002'; set local role authenticated;"
function sesion() {
  const child=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'])
  let out='',err='',marcar
  const listo=new Promise(resolve=>{marcar=resolve})
  child.stdout.on('data',b=>{out+=b; if(out.includes('CIERRE_GUARDADO')) marcar()})
  child.stderr.on('data',b=>{err+=b})
  const fin=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>{marcar();resolve({code,out,err})})})
  child.stdin.write(guardia+'\nset statement_timeout=30000;\n')
  return {child,listo,fin}
}
async function sql(texto) { const s=sesion();s.child.stdin.end(texto);const r=await s.fin;assert.equal(r.code,0,r.err);return r.out.trim() }
const tarea=randomUUID(), persona='10bfe922-e51a-40f5-9557-4a3436923c09'
const datos=`'${JSON.stringify({version:2,estado:'completada',resultado:'no_contesto',detalle:'Ensayo concurrente de resultado'})}'::jsonb`
const cerrar=(clave,id)=>`select crm.postventa_tarea_fn('${clave}','${id}',1,'cerrar',${datos});`
async function carrera(mismaClave) {
  const id=mismaClave?tarea:randomUUID(), clave=randomUUID()
  await sql(`begin;${actor}select crm.postventa_agendar_fn('${id}','${persona}',jsonb_build_object('tipo','llamada','titulo','Concurrencia sintética','vence_en',now()+interval '1 day'));commit;`)
  const a=sesion()
  a.child.stdin.write(`begin;${actor}${cerrar(clave,id)}select 'CIERRE_GUARDADO';\n`)
  await a.listo
  const b=sesion();b.child.stdin.end(`begin;${actor}${cerrar(mismaClave?clave:randomUUID(),id)}commit;`)
  // El primer cierre permanece sin commit mientras se envía el segundo.
  await new Promise(resolve=>setTimeout(resolve,300))
  a.child.stdin.end('commit;\n')
  const [ra,rb]=await Promise.all([a.fin,b.fin]);assert.equal(ra.code,0,ra.err)
  if(mismaClave) {assert.equal(rb.code,0,rb.err);assert.deepEqual(JSON.parse(ra.out.split('\n')[0]),JSON.parse(rb.out.trim()))}
  else {assert.notEqual(rb.code,0);assert.match(rb.err,/cambi[oó]|versi[oó]n|revision|revisi[oó]n|pendiente/i)}
  assert.equal(await sql(`select count(*) from crm.inversionista_gestiones where tarea_id='${id}' and tipo='cierre'`),'1')
  console.log(`PASS ${mismaClave?'misma clave: mismo recibo':'claves distintas: un ganador y un conflicto'}, un solo cierre`)
}
await carrera(true)
await carrera(false)
