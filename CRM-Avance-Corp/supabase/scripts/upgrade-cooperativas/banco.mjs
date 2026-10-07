import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
import {fileURLToPath} from 'node:url'

// Solo esta copia local, sin URL ni credenciales remotas. La plantilla y los
// hashes previos se registran en README.md; nunca escribe en el banco de origen.
export const contenedor='supabase_db_avancecorp-pr190-20261006'
export const db='upgrade_cooperativas_20261006'
export const q=x=>x==null?'null':"'"+String(x).replaceAll("'","''")+"'"
export function ejecutar(texto) {
  const guardia=`do $$ begin if current_database()<>'${db}' or shobj_description((select oid from pg_database where datname=current_database()),'pg_database') is distinct from 'BANCO LOCAL upgrade cooperativas 20261006 / sin produccion' then raise exception 'Banco incorrecto'; end if; end $$;\n`
  return spawnSync('docker',['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-f','-'],
    {input:guardia+texto,encoding:'utf8',maxBuffer:16*1024*1024})
}
export function sql(texto) {
  const r=ejecutar(texto)
  assert.equal(r.status,0,(r.stderr||r.error?.message||'')+'\n'+(r.stdout||''))
  return r.stdout.trim()
}
if(process.argv[1]===fileURLToPath(import.meta.url)) {
  const orden=process.argv[2]
  if(orden==='aplicar') console.log(sql(readFileSync(new URL('../../migrations/20261006221545_crm_upgrade_cooperativas.sql',import.meta.url),'utf8'))||'PASS migración local')
  else if(orden==='reversa-y-aplicar') {
    sql(readFileSync(new URL('./reversa.sql',import.meta.url),'utf8'))
    sql(readFileSync(new URL('../../migrations/20261006221545_crm_upgrade_cooperativas.sql',import.meta.url),'utf8'))
    console.log('PASS reversa exacta y migración final aplicadas en banco local')
  }
  else if(orden==='test') console.log(sql(readFileSync(new URL('./test.sql',import.meta.url),'utf8')))
  else if(orden==='replay') {
    const sinTransaccion=s=>s.replace(/^begin;$/m,'').replace(/^(commit|rollback);$/gm,'')
    const reversa=sinTransaccion(readFileSync(new URL('./reversa.sql',import.meta.url),'utf8'))
    const migracion=sinTransaccion(readFileSync(new URL('../../migrations/20261006221545_crm_upgrade_cooperativas.sql',import.meta.url),'utf8'))
    const pruebas=sinTransaccion(readFileSync(new URL('./test.sql',import.meta.url),'utf8')).replaceAll('4998000','4888000')
    const huella=`select md5(string_agg(pg_get_functiondef(p.oid),'' order by p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('crm','private') and p.proname in ('preparar_upgrade_fn','preparar_reinversion_fn','preparar_continuidad_coopac',
        'continuidad_coopac_fuente','postventa_reinversion_guard','inversion_solicitud_resultado','confirmar_inversion_revisada_fn');`
    const antes=sql(huella)
    // Solo borra las clasificaciones sintéticas DENTRO de la transacción que
    // se deshace para ensayar la reversa antes del primer upgrade. Sus guardas
    // siguen activas. La negativa con datos ya fue probada en concurrencia.mjs.
    console.log(sql(`begin;
      delete from crm.inversion_solicitud_origenes where tipo='upgrade';
      delete from crm.inversionista_gestiones where tipo='upgrade';
      ${reversa}\n${migracion}\n${pruebas}\nrollback;`))
    assert.equal(sql(huella),antes,'El replay debe restaurar exactamente las funciones')
    console.log('PASS: reversa, migración final y pruebas reales; rollback deja las funciones intactas')
  }
  else if(orden==='consulta') console.log(sql(readFileSync(0,'utf8')))
  else throw new Error('Usa aplicar | test | consulta; destino local fijo')
}
