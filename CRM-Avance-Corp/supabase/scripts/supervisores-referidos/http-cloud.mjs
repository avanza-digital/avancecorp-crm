// Exclusivo de la rama temporal autorizada. No acepta producción.
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const ref = 'xniiuzkqssqnabkluusv'
const privado = '/private/tmp/supervisores-referidos-privado/'
const clases = ['gerencia', 'coordinador', 'directorio', 'sup1', 'sup2', 'sin_equipo', 'para_baja', 'para_cambio', 'vend1', 'vend2', 'cliente']
const uid = clase => 'ae160000-0000-4000-8000-' + String(clases.indexOf(clase) + 1).padStart(12, '0')
const guardar = (nombre, valor) => writeFileSync(privado + nombre, JSON.stringify(valor, null, 2), { mode: 0o600 })

export async function ejecutar(fase) {
  assert.ok(['preparar', 'antes', 'despues'].includes(fase))
  const entorno = JSON.parse(readFileSync(privado + 'branch.json', 'utf8'))
  const url = `https://${ref}.supabase.co`
  assert.equal(entorno.SUPABASE_URL, url)
  const destino = new URL(entorno.POSTGRES_URL)
  assert.ok(destino.hostname.includes(ref) || decodeURIComponent(destino.username).includes(ref))
  const pg = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG')))
  Object.assign(pg, { PGHOST: destino.hostname, PGPORT: destino.port || '5432', PGDATABASE: destino.pathname.slice(1),
    PGUSER: decodeURIComponent(destino.username), PGPASSWORD: decodeURIComponent(destino.password), PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15' })
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
  assert.equal(sql('select count(*) from cron.job where active'), '0')
  assert.equal(sql("select count(*) from public.perfiles where correo not like '%@referidos.example.invalid'"), '0')
  const opciones = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
  const anon = () => createClient(url, entorno.SUPABASE_ANON_KEY, opciones)
  const usuarios = existsSync(privado + 'usuarios.json') ? JSON.parse(readFileSync(privado + 'usuarios.json', 'utf8')) : {}

  if (fase === 'preparar') {
    assert.equal(sql('select count(*) from crm.equipo'), '0')
    const admin = createClient(url, entorno.SUPABASE_SERVICE_ROLE_KEY, opciones)
    for (const clase of clases) {
      if (usuarios[clase]) continue
      const u = { id: uid(clase), email: uid(clase) + '@referidos.example.invalid', password: randomBytes(24).toString('base64url') + 'Aa9!' }
      const r = await admin.auth.admin.createUser({ ...u, email_confirm: true })
      assert.equal(r.error, null, r.error?.message)
      usuarios[clase] = u; guardar('usuarios.json', usuarios)
    }
    let fixture = readFileSync(new URL('./semilla.sql', import.meta.url), 'utf8')
    fixture = fixture.replace("current_database() <> 'supervisores_referidos_20261016'", `current_setting('app.referidos_ref',true) is distinct from '${ref}'`)
    fixture = fixture.replace('grant select on actores to authenticated;', clases.map(c => `update actores set id='${uid(c)}' where clase='${c}';`).join('\n') + '\ngrant select on actores to authenticated;')
    fixture = fixture.replace("insert into auth.users(id,email) select id,id::text||'@referidos.example.invalid' from actores;", '/* Auth Admin creó las identidades. */')
    sql(`begin; set local app.referidos_ref='${ref}';\n${fixture}\ncommit;`)
    ok('Once identidades sintéticas y dos equipos preparados, sin enviar correos')
    return
  }
  const sesiones = {}
  for (const clase of clases) {
    const c = anon(); const u = usuarios[clase]; assert.ok(u)
    const r = await c.auth.signInWithPassword({ email: u.email, password: u.password })
    assert.equal(r.error, null, r.error?.message); assert.equal(r.data.user.id, uid(clase)); sesiones[clase] = c
  }
  ok('Once sesiones con JWT reales emitidos por Auth')
  let n = 0
  const datos = (extra = {}) => {
    n += 1
    return { p_id: 'af160000-0000-4000-8000-' + String(n).padStart(12, '0'),
      p_nombre_completo: 'REFERIDO HTTP SINTETICO', p_telefono: String(900900000 + n), p_origen: 'referido', p_monto_estimado: 20000, p_moneda: 'PEN', ...extra }
  }
  const alta = (actor, args) => (actor === 'anon' ? anon() : sesiones[actor]).schema('crm').rpc('crear_lead_si_disponible', args)
  const denegar = async (actor, args, mensaje) => {
    const r = await alta(actor, args); assert.equal(r.error?.code, '42501', r.error?.message); ok(mensaje)
  }
  if (fase === 'antes') {
    await denegar('sup1', datos(), 'Baseline productivo rechaza referido del supervisor')
    await denegar('gerencia', datos(), 'Baseline rechaza referido de Gerencia')
    guardar('http-antes.json', evidencia)
    return
  }
  let propio
  for (const actor of ['sup1', 'sin_equipo', 'vend1']) {
    for (const explicito of [false, true]) {
      const args = datos(explicito ? { p_vendedor_id: uid(actor) } : {})
      const r = await alta(actor, args)
      assert.equal(r.error, null, r.error?.message); assert.equal(r.data?.estado, 'creado'); assert.equal(r.data?.lead_id, args.p_id)
      const l = await sesiones[actor].schema('crm').from('leads').select('vendedor_id,asignado_supervisor_id,creado_por,origen').eq('id', args.p_id).single()
      assert.equal(l.error, null, l.error?.message)
      assert.deepEqual(l.data, { vendedor_id: uid(actor), asignado_supervisor_id: null, creado_por: uid(actor), origen: 'referido' })
      const repetido = await alta(actor, { ...args, p_vendedor_id: explicito ? null : uid(actor) })
      assert.equal(repetido.error, null, repetido.error?.message); assert.equal(repetido.data?.lead_id, args.p_id)
      ok(`${actor}: dueño ${explicito ? 'explícito' : 'omitido'}, autor e idempotencia correctos`)
      if (actor === 'sup1') propio = args.p_id
    }
  }
  for (const destinoActor of ['vend1', 'vend2', 'sup2']) await denegar('sup1', datos({ p_vendedor_id: uid(destinoActor) }), `Supervisor no crea referido a nombre de ${destinoActor}`)
  for (const actor of ['gerencia', 'coordinador', 'directorio', 'cliente', 'anon']) await denegar(actor, datos(), `${actor} no obtiene permiso para referidos`)
  for (const actor of ['sup2', 'vend1']) {
    const r = await sesiones[actor].schema('crm').from('leads').select('id').eq('id', propio)
    assert.equal(r.error, null); assert.deepEqual(r.data, []); ok(`${actor} no lee el referido del supervisor`)
  }
  for (const origen of ['oficina', 'landing', 'formulario', 'formulario_3']) {
    const args = datos({ p_origen: origen })
    const r = await alta('sup1', args); assert.equal(r.error, null, r.error?.message)
    const l = await sesiones.sup1.schema('crm').from('leads').select('vendedor_id,asignado_supervisor_id').eq('id', args.p_id).single()
    assert.equal(l.error, null); assert.deepEqual(l.data, { vendedor_id: null, asignado_supervisor_id: uid('sup1') })
    ok(`${origen} conserva bandeja de reparto`)
  }
  for (const tipo of ['DNI', 'CE', 'PASAPORTE']) {
    const args = datos(); const p_datos = Object.fromEntries(Object.entries(args).map(([k, v]) => [k.slice(2), v]))
    const doc = tipo === 'CE' ? '009990999' : String(96000000 + n)
    const r = await sesiones.sup1.schema('crm').rpc('crear_lead_documento_fn', { p_datos, p_tipo: tipo, p_documento: doc })
    assert.equal(r.error, null, r.error?.message); assert.equal(r.data?.estado, 'creado')
    const fallo = await sesiones.sup1.schema('crm').rpc('crear_lead_documento_fn', { p_datos: { ...p_datos, vendedor_id: uid('vend1') }, p_tipo: tipo, p_documento: doc })
    assert.equal(fallo.error?.code, '42501', fallo.error?.message); ok(`${tipo}: envoltorio permite propio y rechaza otro responsable`)
  }
  const directo = await sesiones.sup1.schema('crm').from('leads').insert({ nombre_completo: 'DIRECTO BLOQUEADO', telefono: '900999999', origen: 'referido', vendedor_id: uid('vend1') })
  assert.equal(directo.error?.code, '42501'); ok('INSERT directo sigue revocado')
  sql(`update public.perfiles set activo=false where id='${uid('sup1')}'`)
  await denegar('sup1', datos(), 'Baja del perfil revoca con el JWT ya emitido')
  sql(`update public.perfiles set activo=true where id='${uid('sup1')}'`)
  sql(`update crm.equipo set activo=false where perfil_id='${uid('para_baja')}'`)
  await denegar('para_baja', datos(), 'Baja CRM revoca con el JWT ya emitido')
  sql(`update crm.equipo set rol_crm='gerencia' where perfil_id='${uid('para_cambio')}'`)
  await denegar('para_cambio', datos(), 'Cambio de rol a Gerencia revoca con el JWT ya emitido')
  guardar('http-despues.json', evidencia)
  console.log(`${evidencia.length} comprobaciones HTTP PASS`)
}
