// Rama temporal autorizada para esta publicación. Nunca admite producción.
// Auth Admin solo crea identidades sintéticas; las lecturas usan JWT reales.
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, chmodSync, existsSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const ref = 'olqqhmatdhrasbzxarbz'
const privado = '/private/tmp/supervisores-cloud-privado/'
const clases = ['gerencia', 'directorio', 'coordinador', 'sup1', 'sup2', 'sin_equipo', 'sin_ventas', 'vend1', 'vend2', 'cliente']
const meses = ['2026-09-01', '2026-10-01', '2026-11-01']
const uid = clase => 'ad160000-0000-4000-8000-' + String(clases.indexOf(clase) + 1).padStart(12, '0')
const guardar = (nombre, valor) => {
  writeFileSync(privado + nombre, JSON.stringify(valor, null, 2), { mode: 0o600 })
  chmodSync(privado + nombre, 0o600)
}

export async function ejecutar(fase) {
  assert.ok(['preparar', 'antes', 'despues'].includes(fase), 'Fase explícita requerida')
  const entorno = JSON.parse(readFileSync(privado + 'branch.json', 'utf8'))
  const url = `https://${ref}.supabase.co`
  assert.equal(entorno.SUPABASE_URL, url, 'Solo la rama temporal autorizada')
  const destino = new URL(entorno.POSTGRES_URL)
  assert.ok(destino.hostname.includes(ref) || decodeURIComponent(destino.username).includes(ref))
  const pg = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG')))
  Object.assign(pg, { PGHOST: destino.hostname, PGPORT: destino.port || '5432',
    PGDATABASE: destino.pathname.slice(1), PGUSER: decodeURIComponent(destino.username),
    PGPASSWORD: decodeURIComponent(destino.password), PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15' })
  const sql = texto => {
    const r = spawnSync('/opt/homebrew/opt/postgresql@17/bin/psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
      { input: texto, env: pg, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 180000 })
    if (r.status !== 0) {
      guardar('http-sql-error.json', { estado: r.status, error: r.stderr })
      throw new Error('SQL sintético falló; diagnóstico privado guardado')
    }
    return r.stdout.trim()
  }
  const evidencia = []
  const ok = nombre => { evidencia.push(nombre); console.log('PASS: ' + nombre) }
  assert.equal(sql('select count(*) from cron.job where active;'), '0', 'Sin automatizaciones')
  assert.equal(sql("select count(*) from public.perfiles where correo not like '%@supervisores.test';"), '0', 'Sin personas reales')
  const opciones = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
  const anon = () => createClient(url, entorno.SUPABASE_ANON_KEY, opciones)
  const usuarios = existsSync(privado + 'usuarios.json')
    ? JSON.parse(readFileSync(privado + 'usuarios.json', 'utf8')) : {}
  const huella = () => sql(`select md5(jsonb_build_object(
    'contratos',(select jsonb_agg(to_jsonb(c) order by id) from public.contratos c),
    'cooperativas',(select jsonb_agg(to_jsonb(c) order by id) from crm.cierres_externos c),
    'sellos',(select jsonb_agg(to_jsonb(p) order by periodo) from crm.periodos_cerrados p))::text);`)

  if (fase === 'preparar') {
    assert.equal(sql('select count(*) from public.contratos;'), '0')
    assert.equal(sql('select count(*) from crm.equipo;'), '0')
    const admin = createClient(url, entorno.SUPABASE_SERVICE_ROLE_KEY, opciones)
    for (const clase of clases) {
      if (usuarios[clase]) continue
      const u = { id: uid(clase), email: uid(clase) + '@supervisores.test', password: randomBytes(24).toString('base64url') + 'Aa9!' }
      const r = await admin.auth.admin.createUser({ ...u, email_confirm: true })
      assert.equal(r.error, null, r.error?.message)
      assert.equal(r.data.user.id, u.id)
      usuarios[clase] = u; guardar('usuarios.json', usuarios)
    }
    ok('Diez identidades sintéticas creadas en Auth, sin enviar correos')
    let fixture = readFileSync(new URL('./semilla.sql', import.meta.url), 'utf8')
    fixture = fixture.replace("current_database() <> 'supervisores_metas_20261016'",
      `current_setting('app.supervisores_ref',true) is distinct from '${ref}'`)
    fixture = fixture.replace('grant select on actores to authenticated;',
      clases.map(c => `update actores set id='${uid(c)}' where clase='${c}';`).join('\n') + '\ngrant select on actores to authenticated;')
    fixture = fixture.replace("insert into auth.users(id,email) select id,id::text||'@supervisores.test' from actores;",
      '/* Auth Admin ya creó las identidades. */')
    sql(`begin; set local app.supervisores_ref='${ref}';\n${fixture}\n
      set local role authenticated;
      select pg_temp.sesion('gerencia');
      create temporary table foto as select crm.cumplimiento_metas_fn('2026-10-01')->'fuera_ranking' filas;
      reset role;
      select set_config('crm.op_privilegiada','on',true);
      insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
        select '2026-11-01',0.15,1,jsonb_build_object('fuera_ranking',filas) from foto;
      commit;`)
    guardar('huella-negocio.json', { huella: huella() })
    ok('Fixture con dos equipos, tres supervisores vendedores, uno sin ventas y mes sellado')
    return
  }

  const sesiones = {}
  for (const clase of clases) {
    const c = anon(); const u = usuarios[clase]; assert.ok(u)
    const r = await c.auth.signInWithPassword({ email: u.email, password: u.password })
    assert.equal(r.error, null, r.error?.message)
    assert.equal(r.data.user.id, uid(clase)); sesiones[clase] = c
  }
  ok('Diez sesiones humanas con JWT emitido por Auth')
  const rpc = (actor, mes) => (actor === 'anon' ? anon() : sesiones[actor])
    .schema('crm').rpc('cumplimiento_metas_fn', { p_periodo: mes })
  const leer = async (actor, mes) => {
    const r = await rpc(actor, mes); assert.equal(r.error, null, r.error?.message); return r.data
  }
  const denegar = async actor => {
    const r = await rpc(actor, '2026-10-01'); assert.equal(r.error?.code, '42501', r.error?.message)
    ok('Lectura denegada: ' + actor)
  }
  const lecturas = {}
  for (const actor of clases.filter(c => c !== 'cliente')) {
    lecturas[actor] = {}
    for (const mes of meses) lecturas[actor][mes] = await leer(actor, mes)
  }
  await denegar('anon'); await denegar('cliente')
  if (fase === 'antes') {
    guardar('lecturas-antes.json', lecturas)
    ok('27 respuestas HTTP de referencia guardadas antes de la migración')
    return
  }
  const antes = JSON.parse(readFileSync(privado + 'lecturas-antes.json', 'utf8'))
  for (const [actor, periodos] of Object.entries(lecturas)) {
    for (const [mes, despues] of Object.entries(periodos)) {
      const original = antes[actor][mes]
      if (['gerencia', 'directorio', 'coordinador', 'vend1', 'vend2'].includes(actor) || mes === '2026-09-01') {
        assert.deepEqual(despues, original); ok(`Paridad histórica o de rol: ${actor} / ${mes}`)
      } else {
        const propias = antes.gerencia[mes].fuera_ranking.filter(f => f.persona_id === uid(actor) && f.rol_crm === 'supervisor')
        assert.deepEqual(despues, { ...original, fuera_ranking: propias })
        assert.equal(propias.length, actor === 'sin_ventas' ? 0 : 1)
        ok(`Solo ventas propias, una vez y sin equipo ajeno: ${actor} / ${mes}`)
      }
    }
  }
  const capital = (actor, mes, moneda) => lecturas[actor][mes].fuera_ranking
    .flatMap(f => f.detalles).filter(d => d.moneda === moneda).reduce((s, d) => s + d.capital_real, 0)
  assert.equal(capital('sup1', '2026-10-01', 'PEN'), 30000)
  assert.equal(capital('sup1', '2026-11-01', 'USD'), 4000)
  assert.equal(capital('sup2', '2026-10-01', 'PEN'), 62000)
  ok('Importes PEN/USD, cooperativa y foto sellada conservan atribución exacta')
  const adminSql = texto => sql(`begin; select set_config('crm.op_privilegiada','on',true); ${texto} commit;`)
  try {
    adminSql(`update public.perfiles set activo=false where id='${uid('sin_equipo')}';`)
    await denegar('sin_equipo'); ok('La baja de perfil revoca acceso con el mismo JWT')
  } finally { adminSql(`update public.perfiles set activo=true where id='${uid('sin_equipo')}';`) }
  try {
    adminSql(`update public.perfiles set rol='analista' where id='${uid('sin_equipo')}';
      update crm.equipo set rol_crm='vendedor',supervisor_id='${uid('sup1')}' where perfil_id='${uid('sin_equipo')}';`)
    for (const mes of ['2026-10-01', '2026-11-01']) assert.deepEqual((await leer('sin_equipo', mes)).fuera_ranking, [])
    ok('Cambio a analista retira acceso de supervisor en mes abierto y sellado con el mismo JWT')
  } finally {
    adminSql(`update public.perfiles set rol='comercial' where id='${uid('sin_equipo')}';
      update crm.equipo set rol_crm='supervisor',supervisor_id=null where perfil_id='${uid('sin_equipo')}';`)
  }
  try {
    adminSql(`update crm.equipo set activo=false where perfil_id='${uid('sin_ventas')}';`)
    await denegar('sin_ventas'); ok('Baja CRM revoca acceso con el mismo JWT')
  } finally { adminSql(`update crm.equipo set activo=true where perfil_id='${uid('sin_ventas')}';`) }
  assert.equal(huella(), JSON.parse(readFileSync(privado + 'huella-negocio.json', 'utf8')).huella)
  ok('Contratos, cooperativas y sellos permanecen íntegros')
  guardar('resultado-http.json', { resultado: 'PASS', ref, comprobaciones: evidencia, total: evidencia.length })
  console.log(`PASS: ${evidencia.length} comprobaciones con Auth/PostgREST reales`)
}
