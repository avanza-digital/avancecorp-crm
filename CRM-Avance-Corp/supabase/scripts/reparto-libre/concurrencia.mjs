// Dos conexiones reales intentan cambiar la misma revisión. Solo una puede ganar.
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'
import assert from 'node:assert/strict'
import { db, contenedor, marca, sql } from './banco.mjs'

const q = (s) => s === null ? 'null' : "'" + String(s).replaceAll("'", "''") + "'"
const original = JSON.parse(sql('select row_to_json(c) from crm.configuracion_reparto c where singleton;'))
const actor = randomUUID()
sql(`begin;
  insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values (${q(actor)},'authenticated','authenticated',${q(actor+'@reparto.test')},now(),'{}','{}',now(),now());
  insert into public.perfiles(id,nombre_completo,correo,rol,activo)
  values (${q(actor)},'PRUEBA CONCURRENCIA REPARTO',${q(actor+'@reparto.test')},'comercial',true);
  insert into crm.equipo(perfil_id,rol_crm,activo) values (${q(actor)},'gerencia',true);
commit;`)

function cambiar() {
  return new Promise((resolve, reject) => {
    const p = spawn('docker', ['exec','-i',contenedor,'psql','-X','-qAt','-U','postgres','-d',db,
      '-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-f','-'])
    let out = '', err = ''
    p.stdout.on('data', (s) => { out += s })
    p.stderr.on('data', (s) => { err += s })
    p.on('error', reject)
    p.on('close', (code) => resolve({ code, out, err }))
    p.stdin.end(`begin;
      do $$ begin if current_database()<>${q(db)} or shobj_description(
        (select oid from pg_database where datname=current_database()),'pg_database') is distinct from ${q(marca)}
        then raise exception 'Banco incorrecto'; end if; end $$;
      select set_config('request.jwt.claim.sub',${q(actor)},true);
      set local role authenticated;
      select crm.guardar_configuracion_reparto_fn(${!original.coordinacion_libre},${original.revision});
      select pg_sleep(0.25);
      commit;`)
  })
}
try {
  const resultados = await Promise.all([cambiar(), cambiar()])
  assert.equal(resultados.filter((r) => r.code === 0).length, 1, JSON.stringify(resultados))
  assert.equal(resultados.filter((r) => r.code !== 0 && r.err.includes('PT409')).length, 1, JSON.stringify(resultados))
  const posterior = JSON.parse(sql('select row_to_json(c) from crm.configuracion_reparto c where singleton;'))
  assert.equal(posterior.revision, original.revision + 1)
  assert.equal(posterior.coordinacion_libre, !original.coordinacion_libre)
  assert.equal(posterior.actualizado_por, actor)
  console.log('PASS: dos sesiones reales, un cambio confirmado y un PT409; una sola revisión y actor correcto')
} finally {
  // Recuperación exclusiva del banco de prueba sellado. La cuenta queda inactiva.
  sql(`begin;
    update crm.configuracion_reparto set coordinacion_libre=${original.coordinacion_libre},
      revision=${original.revision},actualizado_en=${q(original.actualizado_en)}::timestamptz,
      actualizado_por=${q(original.actualizado_por)}::uuid where id=${q(original.id)}::uuid;
    update crm.equipo set activo=false where perfil_id=${q(actor)}::uuid;
    update public.perfiles set activo=false where id=${q(actor)}::uuid;
  commit;`)
}
