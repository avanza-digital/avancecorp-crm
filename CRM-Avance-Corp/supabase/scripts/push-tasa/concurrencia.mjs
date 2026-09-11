// Banco local explícito: escribe únicamente en una copia crm_push_tasa_* vacía.
// Ejemplo: node concurrencia.mjs crm_push_tasa_concurrencia_20260910
import { spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'
const base = process.argv[2]
if (!/^crm_push_tasa_[a-z0-9_]+$/.test(base ?? '')) throw new Error('Indica una copia local crm_push_tasa_*')
const servicio = `set local request.jwt.claims='{"role":"service_role"}';`
function sql(texto, marcador) {
  const proceso = spawn('docker', ['exec', '-i', 'supabase_db_avancecorp-f4-bank', 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', base, '-v', 'ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'] })
  let salida = ''; let errores = ''; let avisar
  const listo = new Promise(resolve => { avisar = resolve })
  proceso.stdout.on('data', datos => { salida += datos; if (marcador && salida.includes(marcador)) avisar() })
  proceso.stderr.on('data', datos => { errores += datos })
  const fin = new Promise((resolve, reject) => {
    proceso.on('error', reject)
    proceso.on('close', codigo => { avisar(); if (codigo) reject(new Error(errores || `psql terminó ${codigo}`)); else resolve(salida.trim()) })
  })
  proceso.stdin.end(texto)
  return { fin, listo }
}
assert.equal(await sql('select count(*) from crm.envios_push_tasa;').fin, '0', 'Usa una copia vacía: no se borran datos')
const suite = readFileSync(new URL('./test-push-tasa.sql', import.meta.url), 'utf8')
const corte = suite.indexOf('create temp table lote_push as')
assert.ok(corte > 0)
await sql(suite.slice(0, corte) + '\ncommit;').fin

// A conserva dos bloqueos mientras B reclama: ni duplicados ni espera por A.
const a = sql(`begin; ${servicio} set local statement_timeout='5s';
select crm.tomar_envios_push_tasa_fn(2);
\u005cecho LOTE_A_LISTO
select pg_sleep(2); commit;`, 'LOTE_A_LISTO')
await a.listo
const salidaB = await sql(`begin; ${servicio} set local statement_timeout='1s'; select crm.tomar_envios_push_tasa_fn(2); commit;`).fin
const salidaA = await a.fin
const lote = texto => JSON.parse(texto.split('\n').find(linea => linea.startsWith('[')))
const loteA = lote(salidaA); const loteB = lote(salidaB)
assert.equal(loteA.length, 2); assert.equal(loteB.length, 2)
assert.equal(new Set([...loteA, ...loteB].map(v => v.id)).size, 4)
console.log('PASS: dos transacciones simultáneas reclaman cuatro envíos distintos sin bloquearse')

// Baja vs respuesta 410. Con el orden inverso de bloqueos esta prueba produce
// deadlock: B bloquearía el envío y A ya tendría bloqueado el dispositivo.
const envio = loteA[0]
const dispositivo = await sql(`select dispositivo_id from crm.envios_push_tasa where id='${envio.id}';`).fin
assert.match(dispositivo, /^[0-9a-f-]{36}$/)
const baja = sql(`begin; set local statement_timeout='5s'; set local deadlock_timeout='200ms';
select 1 from crm.dispositivos_push_tasa where id='${dispositivo}' for update;
select set_config('request.jwt.claims',jsonb_build_object('sub',perfil_id,'session_id',sesion_id,'role','authenticated')::text,true) from crm.dispositivos_push_tasa where id='${dispositivo}';
\u005cecho DISPOSITIVO_BLOQUEADO
select pg_sleep(1);
select crm.desactivar_push_tasa_fn('${dispositivo}'); commit;`, 'DISPOSITIVO_BLOQUEADO')
await baja.listo
const confirmar = sql(`begin; ${servicio} set local statement_timeout='5s'; set local deadlock_timeout='200ms';
select crm.confirmar_envio_push_tasa_fn('${envio.id}','${envio.reserva}','invalido',410); commit;`)
const [resultado] = await Promise.all([confirmar.fin, baja.fin])
assert.equal(resultado, 'f')
assert.equal(await sql(`select activo from crm.dispositivos_push_tasa where id='${dispositivo}';`).fin, 'f')
console.log('PASS: desactivar y confirmar 410 simultáneamente no producen deadlock ni reactivan el teléfono')

// Un segundo worker debe saltar también filas agotadas que el primero está
// cancelando. Un UPDATE sin SKIP LOCKED quedaría esperando aquí.
await sql(`begin; ${servicio}
update crm.dispositivos_push_tasa set activo=false;
update crm.envios_push_tasa set estado='enviando',intentos=8,reservado_hasta=now()-interval '1 second'; commit;`).fin
const limpieza = sql(`begin; ${servicio} set local statement_timeout='5s';
select crm.tomar_envios_push_tasa_fn(10);
\u005cecho LIMPIEZA_LISTA
select pg_sleep(2); commit;`, 'LIMPIEZA_LISTA')
await limpieza.listo
const segundo = await sql(`begin; ${servicio} set local statement_timeout='1s'; select crm.tomar_envios_push_tasa_fn(10); commit;`).fin
await limpieza.fin
assert.equal(segundo, '[]')
console.log('PASS: la limpieza simultánea de filas inválidas y agotadas no espera bloqueos de otro worker')
