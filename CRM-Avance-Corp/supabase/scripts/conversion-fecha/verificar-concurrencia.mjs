import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'

// Banco local efímero exclusivamente sintético. No admite URL ni parámetros.
const contenedor = 'supabase_db_crm-avance-corp-local'
const base = new URL('.', import.meta.url)
const migracion = readFileSync(new URL('../../migrations/20260927073637_crm_conversion_fecha_comercial_plazo.sql', base), 'utf8')
const cierre = readFileSync(new URL('reloj-cierre-banco.sql', base), 'utf8')
const activarUnidad = readFileSync(new URL('activar-politica-banco.sql', base), 'utf8')
const actor = "select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',false);"
const acreditar = `select private.conversion_acreditar_fuente(
  (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
  'contrato','e0000000-0000-4000-8000-00000000000a','Prueba de carrera entre sesiones');`
const procesos = new Set()
function comando(args) {
  const r = spawnSync('docker', ['exec', contenedor, ...args], { encoding: 'utf8', timeout: 30_000 })
  if (r.error || r.status !== 0) throw new Error(r.error?.message ?? r.stderr)
  return r.stdout
}
function sesion(banco, nombre) {
  const p = spawn('docker', ['exec', '-i', contenedor, 'psql', '-X', '-At', '-U', 'postgres', '-d', banco, '-v', 'ON_ERROR_STOP=1'])
  procesos.add(p)
  let salida = '', errores = '', terminado = false
  p.stdout.on('data', d => { salida += d })
  p.stderr.on('data', d => { errores += d })
  const fin = new Promise((resolve, reject) => {
    p.on('error', reject)
    p.on('close', codigo => { terminado = true; procesos.delete(p); resolve({ codigo, salida, errores }) })
  })
  p.stdin.write(`set application_name='${nombre}'; set statement_timeout='15s'; set lock_timeout='10s'; ${actor}\n`)
  return {
    escribir: sql => p.stdin.write(`${sql}\n`),
    cerrar: () => p.stdin.end(), fin,
    async esperar(marca) {
      const limite = Date.now() + 10_000
      while (!salida.includes(marca)) {
        if (terminado || Date.now() > limite) throw new Error(`No llegó ${marca}: ${errores}`)
        await new Promise(resolve => setTimeout(resolve, 20))
      }
    },
  }
}
function consulta(banco, sql) {
  return comando(['psql', '-X', '-At', '-U', 'postgres', '-d', banco, '-v', 'ON_ERROR_STOP=1', '-c', sql]).trim()
}
async function exigirBloqueo(banco, nombre) {
  const limite = Date.now() + 5000
  while (Date.now() < limite) {
    if (consulta(banco, `select exists(select 1 from pg_stat_activity where datname=current_database()
      and application_name='${nombre}' and wait_event_type='Lock' and wait_event='advisory')`) === 't') return
    await new Promise(resolve => setTimeout(resolve, 30))
  }
  throw new Error('FAIL: la segunda sesión no esperó el candado mensual real')
}
async function caso(modo) {
  const banco = `conversion_carrera_${process.pid}_${modo}`
  assert.match(banco, /^conversion_carrera_\d+_(credito|sello|duplicado)$/)
  comando(['createdb', '-U', 'postgres', '--template=conversion_fecha_20260927', banco])
  try {
    const inicial = sesion(banco, 'conversion_preparacion')
    inicial.escribir(`begin; ${migracion}\n${activarUnidad}\n${cierre}
      -- SOLO TEST: relojes distintos permiten simular que dos transacciones
      -- cruzan medianoche. Este cuerpo NUNCA forma parte de la migración.
      create or replace function private.conversion_instante_servidor()
      returns timestamptz language sql volatile security invoker set search_path=''
      as $$ select case when current_setting('application_name')='conversion_antes'
        then '2026-10-10 23:59:59-05'::timestamptz
        else '2026-10-11 09:20-05'::timestamptz end $$;
      select crm.cerrar_periodo('2026-08-01'); commit;
      -- El banco contiene cartera: comparar contra su foto base, no contra
      -- cero (esa producción ajena a captación se debe conservar).
      begin; select crm.cerrar_periodo('2026-09-01');
      select 'BASE_NUM='||coalesce(sum(numerador),0) from crm.cierre_mes_vendedor where periodo='2026-09-01';
      select 'APORTE='||private.peso_referido_conversion('2026-09-01'); rollback;`)
    inicial.cerrar()
    const instalado = await inicial.fin
    assert.equal(instalado.codigo, 0, instalado.errores)
    const baseNumerador = Number(instalado.salida.match(/BASE_NUM=([\d.]+)/)?.[1])
    const aporteReferido = Number(instalado.salida.match(/APORTE=([\d.]+)/)?.[1])
    assert.ok(Number.isFinite(baseNumerador) && Number.isFinite(aporteReferido))
    const primera = sesion(banco, modo === 'sello' ? 'conversion_sello_primero' : 'conversion_antes')
    primera.escribir(`begin; ${modo === 'sello' ? "select crm.cerrar_periodo('2026-09-01');" : acreditar} select 'PRIMERA_LISTA';`)
    await primera.esperar('PRIMERA_LISTA')
    const nombreSegunda = `conversion_segunda_${modo}`
    const segunda = sesion(banco, nombreSegunda)
    segunda.escribir(`begin; ${modo === 'credito' ? "select crm.cerrar_periodo('2026-09-01');" : acreditar} commit;`)
    segunda.cerrar()
    await exigirBloqueo(banco, nombreSegunda)
    primera.escribir('commit;')
    primera.cerrar()
    const a = await primera.fin, b = await segunda.fin
    assert.equal(a.codigo, 0, a.errores)
    if (modo === 'duplicado') {
      assert.notEqual(b.codigo, 0)
      assert.match(b.errores, /La acreditacion cambio mientras esperaba el candado/)
      const antes = consulta(banco, 'select md5(to_jsonb(ca)::text) from crm.conversion_acreditaciones ca')
      consulta(banco, acreditar)
      assert.equal(consulta(banco, 'select md5(to_jsonb(ca)::text) from crm.conversion_acreditaciones ca'), antes)
    } else {
      assert.equal(b.codigo, 0, b.errores)
      assert.equal(consulta(banco, 'select estado from crm.conversion_acreditaciones'),
        modo === 'credito' ? 'acreditada' : 'fuera_de_plazo')
      const numerador = Number(consulta(banco, "select coalesce(sum(numerador),0) from crm.cierre_mes_vendedor where periodo='2026-09-01'"))
      assert.ok(Math.abs(numerador - baseNumerador - (modo === 'credito' ? aporteReferido : 0)) < 1e-9,
        `FAIL: foto ${numerador}, base ${baseNumerador}, referido ${aporteReferido}`)
    }
    assert.equal(consulta(banco, 'select count(*) from crm.conversion_acreditaciones'), '1')
    console.log(`PASS: carrera ${modo}, dos sesiones y bloqueo advisory observado`)
  } finally {
    // Solo este banco recién creado por el proceso; nunca la base plantilla.
    for (const p of procesos) p.stdin.end('rollback;\n')
    comando(['dropdb', '-U', 'postgres', '--force', banco])
  }
}
for (const modo of ['credito', 'sello', 'duplicado']) await caso(modo)

// Puertas reales de Gerencia, en ambos órdenes. La fuente nueva tiene snapshot
// contractual válido y es una captación, no una operación de cartera del seed.
const fuenteMovimiento = 'e0000000-0000-4000-8000-00000000f007'
const movimientos = {
  corregir: `select crm.corregir_fecha_cierre_comercial('${fuenteMovimiento}','2026-09-08','Correccion concurrente del dia comercial');`,
  anular: `select crm.anular_cierre_avance((select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),'Anulacion concurrente sintetica');`,
  sellar: "select crm.cerrar_periodo('2026-09-01');",
  retirar: `select crm.contrato_eliminar_auditado('${fuenteMovimiento}','b0000000-0000-4000-8000-000000000003');`,
}
async function casoMovimientos(accionA, accionB) {
  const modo = `${accionA}_${accionB}`
  const banco = `conversion_movimiento_${process.pid}_${modo}`
  assert.match(banco, /^conversion_movimiento_\d+_(corregir_sellar|sellar_corregir|anular_sellar|sellar_anular|corregir_anular|anular_corregir|retirar_sellar|sellar_retirar)$/)
  comando(['createdb', '-U', 'postgres', '--template=conversion_fecha_20260927', banco])
  try {
    const inicial = sesion(banco, 'conversion_preparacion')
    inicial.escribir(`begin; ${migracion}\n${activarUnidad}\n${cierre}
      create or replace function private.conversion_instante_servidor()
      returns timestamptz language sql volatile security invoker set search_path=''
      as $$ select case when current_setting('application_name')='conversion_antes'
        then '2026-10-10 23:59:59-05'::timestamptz else '2026-10-11 09:20-05'::timestamptz end $$;
      set application_name='conversion_antes';
      select set_config('crm.op_privilegiada','on',true);
      insert into public.contratos
      select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
        'id','${fuenteMovimiento}','numero_contrato','BANCO-CARRERA-MOVIMIENTO',
        'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
        'creado_en','2026-09-25T17:00:00+00:00'))).*
      from public.contratos c where id='e0000000-0000-4000-8000-00000000000a';
      update crm.leads set contrato_id='${fuenteMovimiento}'
        where perfil_id='c0000000-0000-4000-8000-000000000001';
      set application_name='conversion_preparacion';
      select crm.cerrar_periodo('2026-08-01'); commit;
      begin; select crm.cerrar_periodo('2026-09-01');
      select 'BASE_NUM='||coalesce(sum(numerador),0) from crm.cierre_mes_vendedor where periodo='2026-09-01';
      select 'APORTE='||private.peso_referido_conversion('2026-09-01'); rollback;`)
    inicial.cerrar()
    const instalado = await inicial.fin
    assert.equal(instalado.codigo, 0, instalado.errores)
    const baseNumerador = Number(instalado.salida.match(/BASE_NUM=([\d.]+)/)?.[1])
    const aporteReferido = Number(instalado.salida.match(/APORTE=([\d.]+)/)?.[1])
    assert.ok(Number.isFinite(baseNumerador) && Number.isFinite(aporteReferido))
    const a = sesion(banco, 'movimiento_primero')
    a.escribir(`begin; ${movimientos[accionA]} select 'MOVIMIENTO_LISTO';`)
    await a.esperar('MOVIMIENTO_LISTO')
    const nombreB = `movimiento_segundo_${modo}`
    const b = sesion(banco, nombreB)
    b.escribir(`begin; ${movimientos[accionB]} commit;`)
    b.cerrar()
    await exigirBloqueo(banco, nombreB)
    a.escribir('commit;')
    a.cerrar()
    const ra = await a.fin, rb = await b.fin
    assert.equal(ra.codigo, 0, ra.errores)
    if (modo === 'sellar_corregir') {
      assert.notEqual(rb.codigo, 0)
      assert.match(rb.errores, /No se puede reescribir un mes comercial sellado/)
    } else if (modo === 'sellar_anular' || modo === 'corregir_anular') {
      assert.notEqual(rb.codigo, 0)
      assert.match(rb.errores, /La acreditacion cambio durante la anulacion/)
      consulta(banco, actor + movimientos.anular)
    } else assert.equal(rb.codigo, 0, rb.errores)
    if (modo.includes('retirar')) consulta(banco, actor + movimientos.anular)
    assert.equal(consulta(banco, `select fecha_cierre_comercial from public.contratos where id='${fuenteMovimiento}'`),
      modo.includes('retirar') ? '' : modo.includes('corregir') && modo !== 'sellar_corregir' ? '2026-09-08' : '2026-09-05')
    assert.equal(consulta(banco, "select count(*) from crm.ajustes_mes_cerrado"),
      ['sellar_anular', 'sellar_retirar'].includes(modo) ? '1' : '0')
    if (modo.includes('sellar')) {
      const numerador = Number(consulta(banco, "select sum(numerador) from crm.cierre_mes_vendedor where periodo='2026-09-01'"))
      const excluida = ['anular_sellar', 'retirar_sellar'].includes(modo)
      assert.ok(Math.abs(numerador - baseNumerador + (excluida ? aporteReferido : 0)) < 1e-9)
      assert.equal(consulta(banco, 'select incluida_en_sello from crm.conversion_acreditaciones'), excluida ? 'f' : 't')
    }
    assert.equal(consulta(banco, 'select count(*) from crm.cierres_avance_anulados'),
      modo.includes('anular') || modo.includes('retirar') ? '1' : '0')
    assert.equal(consulta(banco, 'select count(*) from crm.conversion_acreditaciones'), '1')
    console.log(`PASS: carrera ${modo}, conflicto/reintento y foto/deuda verificados`)
  } finally {
    for (const p of procesos) p.stdin.end('rollback;\n')
    comando(['dropdb', '-U', 'postgres', '--force', banco])
  }
}
for (const [a, b] of [
  ['corregir', 'sellar'], ['sellar', 'corregir'], ['anular', 'sellar'],
  ['sellar', 'anular'], ['corregir', 'anular'], ['anular', 'corregir'],
  ['retirar', 'sellar'], ['sellar', 'retirar'],
]) await casoMovimientos(a, b)
console.log('PASS: bancos efímeros propios retirados; plantilla intacta')
