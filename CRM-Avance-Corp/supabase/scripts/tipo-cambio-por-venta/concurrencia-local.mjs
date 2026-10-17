import { spawn, spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
import { nombres, cuerpoMigracion } from './migraciones-locales.mjs'

const contenedor = 'avancecorp-tc-20261016'
const db = `tc_venta_conc_${process.pid}`
const args = (base) => ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', base, '-v', 'ON_ERROR_STOP=1', '-f', '-']
function sql(s, timeout = 10_000) {
  const r = spawnSync('docker', args(db), { input: s, encoding: 'utf8', timeout, maxBuffer: 1024 * 1024 })
  assert.equal(r.status, 0, r.stderr || r.error?.message)
  return r.stdout.trim()
}
function paralelo(s) {
  const p = spawn('docker', args(db), { stdio: ['pipe', 'pipe', 'pipe'] })
  let stderr = ''
  p.stdout.resume()
  p.stderr.on('data', (b) => { stderr += b })
  const terminado = new Promise((resolve, reject) => {
    p.on('error', reject)
    p.on('close', (code) => code === 0 ? resolve() : reject(new Error(stderr || `psql: ${code}`)))
  })
  p.stdin.end(s)
  return terminado
}

let creada = false
let escritor
try {
  const r = spawnSync('docker', ['exec', contenedor, 'createdb', '-U', 'supabase_admin', '-T', 'tc_venta', db], { encoding: 'utf8' })
  assert.equal(r.status, 0, r.stderr)
  creada = true
  sql(`begin;\n${nombres.map(cuerpoMigracion).join('\n')}\ncommit;`, 120_000)
  sql(`begin; set local session_replication_role=replica;
    insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial)
    values('e4000000-0000-4000-8000-000000000001','TC-CONCURRENCIA','e4000000-0000-4000-8000-000000000002',20000,'USD','mensual','2026-10-02','2027-10-02','nuevo','e4000000-0000-4000-8000-000000000003','2026-10-02');
    set local session_replication_role=origin;
    select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-10-02','politica','sbs_punto_medio_7d_v1',
      'publicacion_confirmada','2026-10-02','fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('a',64),
      'pares',(select jsonb_agg(jsonb_build_object('fecha',date '2026-10-02'-i,'compra','3.4','venta','3.4')) from generate_series(0,6) i)));
    commit;`)
  escritor = spawn('docker', args(db), { stdio: ['pipe', 'pipe', 'pipe'] })
  let err = ''
  escritor.stderr.on('data', (b) => { err += b })
  const terminado = new Promise((resolve, reject) => {
    escritor.on('error', reject)
    escritor.on('close', (code) => code === 0 ? resolve() : reject(new Error(err || `psql escritor: ${code}`)))
  })
  const bloqueado = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('El escritor no alcanzó el bloqueo')), 10_000)
    let salida = ''
    escritor.stdout.on('data', (b) => {
      salida += b
      if (salida.includes('ESCRITURA_BLOQUEADA')) { clearTimeout(timer); resolve() }
    })
    escritor.once('exit', () => { clearTimeout(timer); reject(new Error('El escritor terminó antes del bloqueo')) })
  })
  escritor.stdin.write(`begin; set local session_replication_role=replica;
    update public.contratos set capital=40000 where id='e4000000-0000-4000-8000-000000000001';
    select 'ESCRITURA_BLOQUEADA';
  `)
  await bloqueado
  const mientrasEdita = JSON.parse(sql('select private.materializar_capital_valoraciones();', 5000))
  assert.equal(mientrasEdita.creadas, 0)
  assert.equal(sql('select count(*) from crm.capital_valoraciones;'), '0')
  console.log('PASS: una fuente en edición no se congela con la lectura anterior ni bloquea al worker')
  escritor.stdin.end('commit;\n')
  await terminado
  await Promise.all([
    paralelo('select private.materializar_capital_valoraciones();'),
    paralelo('select private.materializar_capital_valoraciones();'),
  ])
  assert.equal(sql('select count(*) from crm.capital_valoraciones;'), '1')
  const actual = JSON.parse(sql(`select jsonb_build_object('monto',monto,'equivalente',equivalente_pen,'revision',revision)
    from crm.capital_valoraciones;`))
  assert.deepEqual(actual, { monto: 40000, equivalente: 136000, revision: 1 })
  console.log('PASS: dos materializadores concurrentes crean una sola revisión con el monto confirmado')
} finally {
  if (escritor?.exitCode === null) escritor.kill('SIGTERM')
  if (creada) {
    const r = spawnSync('docker', ['exec', contenedor, 'dropdb', '--force', '-U', 'supabase_admin', db], { encoding: 'utf8' })
    assert.equal(r.status, 0, r.stderr)
  }
}
