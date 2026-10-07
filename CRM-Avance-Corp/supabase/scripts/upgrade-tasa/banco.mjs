import assert from 'node:assert/strict'
import {spawn, spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'

// Destino fijo: copia aislada del fixture local, nunca una URL remota.
const contenedor='supabase_db_avancecorp-pr190-20261006'
const base='upgrade_tasa_20261007'
export function sql(texto, exigir=true) {
  const guardia=`do $$ begin if current_database()<>'${base}' or shobj_description((select oid from pg_database where datname=current_database()),'pg_database') is distinct from 'BANCO LOCAL upgrade tasa 20261007' then raise exception 'Banco incorrecto'; end if; end $$;\n`
  const r=spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',base,'-v','ON_ERROR_STOP=1','-f','-'],
    {input:guardia+texto,encoding:'utf8',maxBuffer:8*1024*1024})
  if(exigir) assert.equal(r.status,0,r.stderr||r.error?.message||r.stdout)
  return r
}
const archivo=ruta=>readFileSync(new URL(ruta,import.meta.url),'utf8')
const firmas=['private.rentabilidad_minimo_alta(text,numeric)','private.trg_contratos_observar_rentabilidad()',
  'private.resolver_tasa(uuid,text,uuid,timestamp with time zone,uuid)']
const estado=()=>JSON.parse(sql(`select json_agg(json_build_object('firma',p.oid::regprocedure::text,'definicion',pg_get_functiondef(p.oid),'propietario',p.proowner,'acl',p.proacl,'config',p.proconfig,'definer',p.prosecdef,'volatilidad',p.provolatile,'comentario',obj_description(p.oid,'pg_proc')) order by p.oid::regprocedure::text) from pg_proc p where p.oid in (${firmas.map(f=>`'${f}'::regprocedure`).join(',')});`).stdout)
const orden=process.argv[2]
if(orden==='aplicar') {
  const antes=estado()
  sql(archivo('../../migrations/20261007180108_crm_upgrade_tasa_flexible.sql'))
  for(const [i,despues] of estado().entries()) {
    const {definicion: a,comentario: ca,...metaA}=antes[i]
    const {definicion: b,comentario: cb,...metaB}=despues
    assert.notEqual(a,b); assert.deepEqual(metaA,metaB)
  }
  console.log('PASS: migración aplicada solo al banco; firmas, permisos, propietarios y atributos conservados')
} else if(orden==='test') {
  // La guarda de reversión debe negarse después del primer uso, dentro de la
  // misma transacción de fixtures; nunca ejecutar el COMMIT de la reversa aquí.
  const preflight=archivo('./reversa.sql').match(/do \$preflight\$[\s\S]*?\$preflight\$;/)?.[0]
  assert.ok(preflight)
  const literal="'"+preflight.replaceAll("'","''")+"'"
  const caso=`select pg_temp.rechaza(${literal},'P0001');\ndo $$ begin raise notice 'PASS: reversa rechazada después de usar una tasa inferior'; end $$;\nrollback;`
  const r=sql(archivo('./test.sql').replace(/rollback;\s*$/,()=>caso))
  console.log(r.stderr.split('\n').filter(l=>l.includes('PASS:')).join('\n'))
} else if(orden==='reversa'||orden==='retirar') {
  const antes=estado()
  sql(archivo('./reversa.sql'))
  const esperado=JSON.parse(archivo('./base-funciones.json'))
  for(const f of estado()) assert.equal(f.definicion,esperado.find(e=>e.firma===f.firma).definicion)
  if(orden==='retirar') {console.log('PASS: funciones originales restauradas en el banco'); process.exit(0)}
  sql(archivo('../../migrations/20261007180108_crm_upgrade_tasa_flexible.sql'))
  assert.deepEqual(estado(),antes)
  console.log('PASS: reversa exacta y reaplicación, incluidos comentarios y ACL')
} else if(orden==='carrera-reversa') {
  const antes=estado() // también comprueba la identidad del banco
  const escritor=spawn('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',base,'-v','ON_ERROR_STOP=1','-f','-'],
    {stdio:['pipe','pipe','pipe']})
  const terminado=new Promise(resolve=>escritor.on('close',resolve))
  try {
    await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('El escritor no adquirió el bloqueo local')),10000)
      escritor.once('error',e=>{clearTimeout(timeout);reject(e)})
      escritor.stdout.on('data',d=>{if(d.toString().includes('UPGRADE_LOCK_LISTO')) {clearTimeout(timeout);resolve()}})
      escritor.stdin.write("begin; lock table public.contratos in row exclusive mode; select 'UPGRADE_LOCK_LISTO';\n")
    })
    const r=sql(archivo('./reversa.sql'),false)
    assert.notEqual(r.status,0)
    assert.match(r.stderr,/lock timeout/)
  } finally {
    escritor.stdin.end('rollback;\n')
    await terminado
  }
  assert.deepEqual(estado(),antes)
  console.log('PASS: reversa bloqueada ante escritura concurrente; funciones y metadatos intactos')
} else throw new Error('Usa aplicar | test | reversa | retirar | carrera-reversa')
