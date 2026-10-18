import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

const contenedor = 'avancecorp-tc-20261016'
const leer = (nombre) => readFileSync(new URL(nombre, import.meta.url), 'utf8')
const q = (s) => `'${String(s).replaceAll("'", "''")}'`
const args = (db) => ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-']
function sql(db, texto) {
  const r = spawnSync('docker', args(db), { input: texto, encoding: 'utf8', timeout: 120_000, maxBuffer: 2 * 1024 * 1024 })
  assert.equal(r.status, 0, r.stderr || r.error?.message)
  return r.stdout.trim()
}
function sesion(db, nombre) {
  const p = spawn('docker', args(db), { stdio: ['pipe', 'pipe', 'pipe'] })
  let salida = ''; let errores = ''
  const escuchas = new Set()
  p.stdout.on('data', (b) => { salida += b; for (const fn of escuchas) fn() })
  p.stderr.on('data', (b) => { errores += b })
  const fin = new Promise((resolve) => {
    p.on('error', (e) => { errores += e.message; resolve(-1) })
    p.on('close', resolve)
  })
  const marcador = (texto) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => { escuchas.delete(comprobar); reject(new Error(`Sin marcador ${texto}: ${errores}`)) }, 10_000)
    function comprobar() {
      if (salida.includes(texto)) { clearTimeout(timer); escuchas.delete(comprobar); resolve() }
    }
    escuchas.add(comprobar); comprobar()
  })
  p.stdin.write(`set application_name=${q(nombre)}; set statement_timeout='20s'; set lock_timeout='15s';\n`)
  return { p, nombre, marcador, async comprobar() { assert.equal(await fin, 0, errores); return salida } }
}
async function esperarBloqueo(db, bloqueada, titular) {
  const limite = Date.now() + 10_000
  while (Date.now() < limite) {
    const estado = JSON.parse(sql(db, `select coalesce(jsonb_agg(jsonb_build_object('espera',a.wait_event_type,
      'bloqueada',exists(select 1 from pg_stat_activity b where b.application_name=${q(titular.nombre)} and b.pid=any(pg_blocking_pids(a.pid))))),'[]')
      from pg_stat_activity a where a.application_name=${q(bloqueada.nombre)};`))
    if (estado.some((s) => s.espera === 'Lock' && s.bloqueada)) return
    if (bloqueada.p.exitCode !== null) throw new Error('La sesión terminó antes de esperar el candado')
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
  throw new Error('No se verificó la espera entre las sesiones reales')
}

const contrato = 'f2000000-0000-4000-8000-000000000008'
const gerente = 'f1000000-0000-4000-8000-000000000006'
const cerrojoGlobal = "select pg_advisory_xact_lock(hashtext('crm.periodos_cerrados')::bigint);"
const corregir = `select set_config('request.jwt.claim.sub',${q(gerente)},true);
  set local role authenticated;
  select crm.corregir_fecha_cierre_comercial(${q(contrato)},'2026-10-05','Corrección concurrente sintética');`
const creadas = new Set()
const sesiones = new Set()
try {
  for (const orden of ['cierre', 'correccion']) {
    const db = `tc_venta_cierre_${process.pid}_${orden}`
    assert.match(db, /^tc_venta_cierre_\d+_(cierre|correccion)$/)
    sql('postgres', `create database ${db} template tc_venta;`)
    creadas.add(db)
    sql(db, leer('reversa-persistencia.sql') + '\n' + leer('../../migrations/20261016190725_crm_tipo_cambio_por_venta.sql'))
    const fixture = leer('prueba-atribucion.sql').split('-- @MIGRACION_OPERACIONES@')[0]
      .replace("current_database()<>'tc_venta'", `current_database()<>'${db}'`)
    const escritores = leer('prueba-escritores.sql').split('select private.materializar_capital_valoraciones_para')[0]
      .replace('savepoint escritores;', '')
    const cortes = leer('prueba-cortes.sql').split('savepoint cierre_legado;')[0]
    sql(db, fixture + '\n' + nombres.map(cuerpoMigracion).join('\n') + '\n' + escritores + '\n' + cortes + '\ncommit;')
    const cierre = sesion(db, `tc-cierre-${process.pid}`)
    const correccion = sesion(db, `tc-correccion-${process.pid}`)
    sesiones.add(cierre); sesiones.add(correccion)
    if (orden === 'cierre') {
      cierre.p.stdin.write(`begin; ${cerrojoGlobal} select 'CIERRE_CON_CANDADO';\n`)
      await cierre.marcador('CIERRE_CON_CANDADO')
      correccion.p.stdin.end(`begin; select set_config('request.jwt.claim.sub',${q(gerente)},true); set local role authenticated;
        do $$ begin
          begin perform crm.corregir_fecha_cierre_comercial(${q(contrato)},'2026-10-05','Corrección concurrente sintética');
            raise exception 'Se corrigió un mes que ganó el cierre';
          exception when sqlstate 'P0409' then null; end;
        end $$; commit;`)
      await esperarBloqueo(db, correccion, cierre)
      assert.equal(sql(db, `select count(*) from pg_locks l join pg_stat_activity a on a.pid=l.pid
        where a.application_name=${q(correccion.nombre)} and l.relation='public.contratos'::regclass
          and l.mode in('RowShareLock','RowExclusiveLock') and l.granted;`), '0')
      cierre.p.stdin.end("select crm.cerrar_periodo('2026-10-01'); commit;\n")
      await cierre.comprobar(); await correccion.comprobar()
      assert.equal(sql(db, `select fecha_cierre_comercial from public.contratos where id=${q(contrato)};`), '2026-10-02')
      console.log('PASS: si el cierre gana, el corrector espera antes de bloquear la fuente y rechaza reescribir el sello')
    } else {
      correccion.p.stdin.write(`begin; ${corregir} select 'CORRECCION_VALORADA';\n`)
      await correccion.marcador('CORRECCION_VALORADA')
      cierre.p.stdin.end("begin; select crm.cerrar_periodo('2026-10-01'); commit;\n")
      await esperarBloqueo(db, cierre, correccion)
      correccion.p.stdin.end('commit;\n')
      await correccion.comprobar(); await cierre.comprobar()
      assert.equal(sql(db, `select exists(select 1 from crm.capital_mes_sellos s join crm.capital_cortes_valorados c on c.id=s.corte_id,
        jsonb_array_elements(c.base) e where e->>'fuente_id'=${q(contrato)} and e->>'fecha_comercial'='2026-10-05'
          and (e->>'equivalente_pen')::numeric=8000 and (e->>'revision_valoracion')::integer=2);`), 't')
      console.log('PASS: si la corrección gana, el cierre espera su commit y sella la revisión nueva de la misma transacción')
    }
    assert.equal(sql(db, 'select count(*) from crm.capital_mes_sellos;'), '1')
  }
} finally {
  for (const sesion of sesiones) if (sesion.p.exitCode === null) sesion.p.kill('SIGTERM')
  for (const db of creadas) sql('postgres', `drop database ${db} with(force);`)
}
