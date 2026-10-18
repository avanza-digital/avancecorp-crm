// Matriz focalizada con Auth/PostgREST reales. Solo la copia autorizada.
// La service_role prepara fixtures e invoca la puerta exclusiva del importador.
// Todas las aserciones humanas usan JWT de sus propios usuarios sintéticos.
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const ref = 'yefiownpxvembwvfbtfx'
const privado = '/private/tmp/formulario3-origen-privado/'
const entorno = JSON.parse(readFileSync(privado + 'branch.json', 'utf8'))
const url = `https://${ref}.supabase.co`
assert.equal(entorno.SUPABASE_URL, url, 'Destino exclusivo: rama temporal autorizada')
const opciones = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
const admin = createClient(url, entorno.SUPABASE_SERVICE_ROLE_KEY, opciones)
const anon = () => createClient(url, entorno.SUPABASE_ANON_KEY, opciones)
const usuarios = existsSync(privado + 'usuarios.json') ? JSON.parse(readFileSync(privado + 'usuarios.json', 'utf8')) : {}
const roles = ['supervisor', 'supervisor_otro', 'vendedor', 'vendedor_otro', 'gerencia', 'coordinador', 'inactivo', 'directorio']
const evidencia = []
const ok = (nombre, extra = {}) => { evidencia.push({ nombre, estado: 'PASS', ...extra }); console.log('PASS: ' + nombre) }
const guardar = (nombre, datos) => {
  writeFileSync(privado + nombre, JSON.stringify(datos, null, 2), { mode: 0o600 })
  chmodSync(privado + nombre, 0o600)
}
const literal = s => "'" + s.replaceAll("'", "''") + "'"
function sql(texto) {
  // Management API: la copia restaurada no acepta la contraseña postgres que
  // branches get entrega. No se cambia esa contraseña ni se debilitan permisos.
  const r = spawnSync('supabase', ['db', 'query', '--linked', '--project-ref', ref, '--output', 'json', texto], { encoding: 'utf8' })
  if (r.status !== 0) {
    throw new Error('SQL Management API del banco falló; salida privada omitida')
  }
  const data = JSON.parse(r.stdout)
  assert.ok(Array.isArray(data.rows), 'Respuesta SQL estructurada')
  return data.rows.length ? String(Object.values(data.rows[0])[0]) : ''
}
function fotoSintetica() {
  return sql(`with l as (select * from crm.leads where nombre_completo like 'PRUEBA F3 NATIVO%')
    select md5(jsonb_build_object('leads',(select jsonb_agg(to_jsonb(l) order by id) from l),
      'actividades',(select jsonb_agg(to_jsonb(a) order by a.id) from crm.actividades a join l on l.id=a.lead_id),
      'tareas',(select jsonb_agg(to_jsonb(a) order by a.id) from crm.tareas a join l on l.id=a.lead_id),
      'episodios',(select jsonb_agg(to_jsonb(a) order by a.id) from crm.lead_asignaciones a join l on l.id=a.lead_id))::text);`)
}
async function crear() {
  assert.equal(sql('select count(*) from cron.job where active;'), '0', 'Cron desactivado en la copia')
  // No se toca ni se desactiva el conjunto copiado: solo teléfonos y perfiles ficticios.
  const colision = await admin.schema('crm').from('leads').select('id').in('telefono', Array.from({ length: 20 }, (_, i) => '+519845000' + String(i + 1).padStart(2, '0')))
  assert.equal(colision.error, null); assert.equal(colision.data.length, 0, 'Teléfonos sintéticos libres')
  for (const [i, rol] of roles.entries()) {
    if (usuarios[rol]) continue
    const email = `f3_nativo_${rol}_20261015@pruebas.invalid`
    const password = randomBytes(24).toString('base64url') + 'aA8!'
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { nombre_completo: 'PRUEBA F3 NATIVO ' + rol } })
    assert.equal(error, null, error?.message)
    usuarios[rol] = { id: data.user.id, email, password, dni: String(49450091 + i) }
    guardar('usuarios.json', usuarios)
    ok('Auth: usuario sintético ' + rol + ' sin enviar correo')
  }
  const inserts = roles.map(rol => {
    const u = usuarios[rol]
    const perfil = `insert into public.perfiles(id,nombre_completo,rol,tipo_documento,dni,activo) values (${literal(u.id)},${literal('PRUEBA F3 NATIVO ' + rol)},${literal(rol === 'directorio' ? 'directorio' : 'comercial')},'DNI',${literal(u.dni)},true);`
    if (rol === 'directorio') return perfil
    const sup = rol === 'vendedor' ? literal(usuarios.supervisor.id) : rol === 'vendedor_otro' ? literal(usuarios.supervisor_otro.id) : 'null'
    const crmRol = rol === 'inactivo' ? 'gerencia' : rol.replace('_otro', '')
    return perfil + `insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo,creado_por) values (${literal(u.id)},${literal(crmRol)},${sup},${rol !== 'inactivo'},${literal(u.id)});`
  })
  sql("begin; select set_config('crm.op_privilegiada','on',true);\n" + inserts.join('\n') + '\ncommit;')
  ok('Ocho perfiles sintéticos con jerarquía y membresía real, sin modificar usuarios copiados')
  if (!existsSync(privado + 'importar.env')) {
    writeFileSync(privado + 'importar.env', 'CRM_IMPORTAR_SECRET=' + randomBytes(32).toString('hex') + '\n', { mode: 0o600 })
  }
}
async function sesiones() {
  const resultado = {}
  for (const rol of roles) {
    const u = usuarios[rol]; assert.ok(u)
    const c = anon()
    const { data, error } = await c.auth.signInWithPassword({ email: u.email, password: u.password })
    assert.equal(error, null, error?.message); assert.equal(data.user.id, u.id)
    resultado[rol] = c; ok('Sesión Auth real: ' + rol)
  }
  return resultado
}
function filas() {
  return [
    ['CARTERA Formulario', 'formulario', null, 'vendedor'],
    ['CARTERA F3 nuevo', 'formulario_3', null, 'vendedor'],
    ['CARTERA F3 legado', 'formulario', 'Formulario 3', 'vendedor_otro'],
    ['CARTERA Landing', 'landing', null, 'vendedor'],
    ['COLA Formulario', 'formulario', null, null],
    ['COLA F3 legado', 'formulario', 'Formulario 3', null],
    ['COLA F3 nuevo', 'formulario_3', null, null],
  ].map(([nombre, origen, campania, actor], i) => ({ nombre_completo: 'PRUEBA F3 NATIVO ' + nombre,
    telefono: '9845000' + String(i + 1).padStart(2, '0'), origen, ...(campania ? { campania_origen: campania } : {}),
    ...(actor ? { vendedor_id: usuarios[actor].id } : {}), monto_estimado: 5000, moneda: 'PEN' }))
}
async function importar(p_fila) {
  const r = await admin.schema('crm').rpc('importar_lead_fn', { p_fila })
  assert.equal(r.error, null, r.error?.message)
  return r.data
}
const columnas = 'id,telefono,origen,campania_origen,vendedor_id,asignado_supervisor_id,alta_manual,nota,creado_por'
const leer = (cliente, fs = filas()) => cliente.schema('crm').from('leads').select(columnas).in('telefono', fs.map(f => '+51' + f.telefono)).order('telefono')
async function matriz(fase) {
  assert.ok(['a', 'b'].includes(fase))
  assert.equal(sql('select count(*) from cron.job where active;'), '0')
  if (fase === 'a') {
    for (const fila of filas()) assert.equal((await importar(fila)).resultado, 'importado')
    ok('A: siete altas por puerta exclusiva del servidor; no se ejecutó Edge')
  }
  const ss = await sesiones()
  const todo = await leer(ss.gerencia); assert.equal(todo.error, null); assert.equal(todo.data.length, 7)
  for (const [i, l] of todo.data.entries()) {
    const esF3 = [1, 2, 5, 6].includes(i)
    assert.equal(l.origen, esF3 ? (fase === 'a' ? 'formulario' : 'formulario_3') : i === 3 ? 'landing' : 'formulario')
    assert.equal(l.campania_origen, esF3 ? 'Formulario 3' : null)
    assert.equal(l.alta_manual, false); assert.equal(l.creado_por, null)
  }
  ok(fase.toUpperCase() + ': persistencia de origen, campaña y alta automática correcta')
  const cantidades = { vendedor: [3, 1, 1], supervisor: [3, 1, 1], vendedor_otro: [1, 1, 0], supervisor_otro: [1, 1, 0],
    gerencia: [4, 2, 1], directorio: [4, 2, 1], coordinador: [0, 0, 0], inactivo: [0, null, null] }
  for (const [rol, [total, f3, form]] of Object.entries(cantidades)) {
    const c = ss[rol].schema('crm')
    const directo = await leer(ss[rol], filas().slice(0, 4))
    assert.equal(directo.error, null); assert.equal(directo.data.length, total, rol + ' RLS directo')
    ok('RLS directo conserva ámbito: ' + rol, { cantidad: total })
    for (const [origen, n] of [['formulario_3', f3], ['formulario', form]]) {
      const r = await c.rpc('cartera_filtrada_fn', { p_texto: 'PRUEBA F3 NATIVO CARTERA', p_origen: origen })
      if (n === null) { assert.equal(r.error?.code, '42501'); continue }
      assert.equal(r.error, null, r.error?.message); assert.equal(r.data.items.length, n, rol + ' filtro ' + origen)
      assert.equal(r.data.resumen.totales.vivos, n)
      const almacenado = fase === 'a' && origen === 'formulario_3' ? 'formulario' : origen
      assert.ok(r.data.items.every(l => l.origen === almacenado))
      if (origen === 'formulario_3') assert.ok(r.data.items.every(l => l.campania_origen === 'Formulario 3'))
    }
    ok('Filtros y cifras Formulario/Formulario 3 separados: ' + rol)
    const anterior = await c.rpc('cartera_filtrada_fn', { p_texto: 'PRUEBA F3 NATIVO CARTERA' })
    if (rol === 'inactivo') { assert.equal(anterior.error?.code, '42501'); continue }
    assert.equal(anterior.error, null); assert.equal(anterior.data.items.length, total)
    const campania = await c.rpc('cartera_filtrada_fn', { p_texto: 'PRUEBA F3 NATIVO CARTERA', p_campania_origen: 'Formulario 3' })
    assert.equal(campania.error, null); assert.equal(campania.data.items.length, f3)
    const pagina = await c.rpc('cartera_pagina_fn', { p_texto: 'PRUEBA F3 NATIVO CARTERA', p_limite: 20 })
    assert.equal(pagina.error, null); assert.equal(pagina.data.length, total)
    ok('Contratos anteriores y paginación siguen funcionando: ' + rol)
  }
  for (const rol of roles) {
    for (const [rpc, args] of [['leads_por_repartir', {}], ['agenda_reparto_diaria', { p_desde: '2026-10-15', p_dias: 1 }], ['conversion_divisor_coordinacion_fn', {}]]) {
      const consulta = ss[rol].schema('crm').rpc(rpc, args)
      const r = await (rpc === 'leads_por_repartir' ? consulta.in('id', todo.data.map(l => l.id)) : consulta)
      if (['gerencia', 'coordinador'].includes(rol)) assert.equal(r.error, null, rpc + ': ' + r.error?.message)
      else assert.equal(r.error?.code, '42501', rol + ': ' + rpc)
    }
    ok('Puertas Coordinación: autorización exacta de ' + rol)
  }
  const v = ss.vendedor.schema('crm')
  const lead = todo.data[1], otro = todo.data[2]
  const bloqueado = await v.from('leads').update({ campania_origen: 'Alterada' }).eq('id', lead.id)
  assert.equal(bloqueado.error?.code, '42501'); ok('Campaña automática no editable por analista')
  const nota = 'Nota comercial sintética ' + fase
  const permitido = await v.from('leads').update({ nota }).eq('id', lead.id).select('id,nota,campania_origen')
  assert.equal(permitido.error, null); assert.equal(permitido.data.length, 1); assert.equal(permitido.data[0].nota, nota)
  assert.equal(permitido.data[0].campania_origen, 'Formulario 3'); ok('Gestión comercial normal permitida sin perder campaña')
  const cruzado = await v.from('leads').update({ nota: 'No debe guardarse' }).eq('id', otro.id).select('id')
  assert.equal(cruzado.error, null); assert.equal(cruzado.data.length, 0); ok('Escritura cruzada bloqueada por RLS')
  const directa = await v.rpc('importar_lead_fn', { p_fila: {} }); assert.equal(directa.error?.code, '42501'); ok('Sesión humana no invoca importador servidor')
  const sinSesion = await leer(anon()); assert.equal(sinSesion.error?.code, '42501'); ok('Anónimo no puede leer leads')
  const cola = await ss.coordinador.schema('crm').rpc('leads_por_repartir').in('id', todo.data.map(l => l.id))
  assert.equal(cola.error, null)
  assert.equal(cola.data.filter(l => todo.data.slice(4).some(x => x.id === l.id)).length, 3)
  assert.ok(!cola.data.some(l => todo.data.slice(0, 4).some(x => x.id === l.id)))
  ok('Cola contiene los tres pendientes y excluye los cuatro asignados')
  const antes = await leer(ss.gerencia)
  const huellaAntes = fotoSintetica()
  for (const fila of filas()) assert.equal((await importar(fila)).resultado, 'duplicado')
  assert.deepEqual((await leer(ss.gerencia)).data, antes.data); assert.equal(fotoSintetica(), huellaAntes)
  ok('Reenvío de los siete registros conserva fichas completas, historia, tareas y responsables')
  const manual = await v.rpc('crear_lead_si_disponible', { p_nombre_completo: 'PRUEBA F3 NATIVO MANUAL', p_telefono: '984500008', p_origen: 'formulario_3', p_monto_estimado: 1000, p_moneda: 'PEN' })
  if (fase === 'a') {
    assert.equal(manual.error?.code, '42501'); ok('A: alta manual F3 espera activación')
  } else {
    assert.equal(manual.error, null, manual.error?.message)
    const m = await v.from('leads').select('origen,alta_manual,vendedor_id,campania_origen').eq('telefono', '+51984500008').single()
    assert.equal(m.error, null); assert.equal(m.data.origen, 'formulario_3'); assert.equal(m.data.alta_manual, true)
    assert.equal(m.data.vendedor_id, usuarios.vendedor.id); ok('B: alta manual nativa con procedencia y autoasignación correctas')
    const config = await ss.gerencia.schema('crm').rpc('configuracion_reparto_fn')
    assert.equal(config.error, null); assert.equal(config.data.coordinacion_libre, true, 'Reparto libre copiado: no se modifica la agenda del banco')
    for (const l of todo.data.slice(4, 6)) {
      const denegado = await v.rpc('repartir_lead', { p_lead: l.id, p_supervisor: usuarios.supervisor.id })
      assert.equal(denegado.error?.code, '42501')
      const r = await ss.coordinador.schema('crm').rpc('repartir_lead', { p_lead: l.id, p_supervisor: usuarios.supervisor.id })
      assert.equal(r.error, null, r.error?.message)
      const repetido = await ss.coordinador.schema('crm').rpc('repartir_lead', { p_lead: l.id, p_supervisor: usuarios.supervisor.id })
      assert.equal(repetido.error?.code, 'P0002')
    }
    const ids = todo.data.slice(4, 6).map(l => l.id)
    const derivado = await ss.supervisor.schema('crm').rpc('derivar_leads_equipo_fn', { p_lead_ids: ids, p_asesor_ids: ids.map(() => usuarios.vendedor.id) })
    assert.equal(derivado.error, null, derivado.error?.message); assert.equal(derivado.data.derivados, 2)
    const fin = await leer(ss.gerencia, filas().slice(4, 6)); assert.equal(fin.error, null)
    assert.ok(fin.data.every(l => l.vendedor_id === usuarios.vendedor.id && l.asignado_supervisor_id === null))
    assert.deepEqual(fin.data.map(l => l.origen), ['formulario', 'formulario_3'])
    ok('B: Coordinación → supervisor → analista por las mismas puertas; segundo reparto rechazado')
    for (const fila of filas().slice(4, 6)) assert.equal((await importar(fila)).resultado, 'duplicado')
    assert.deepEqual((await leer(ss.gerencia, filas().slice(4, 6))).data, fin.data)
    ok('B: reenvío posterior al reparto no cambia responsables')
    const nueva = { ...filas()[6], telefono: '984500009' }
    assert.equal((await importar(nueva)).resultado, 'importado')
    const n = await leer(ss.gerencia, [nueva]); assert.equal(n.error, null); assert.equal(n.data[0].origen, 'formulario_3')
    assert.equal((await importar({ ...nueva, origen: 'formulario', campania_origen: 'Formulario 3' })).resultado, 'duplicado')
    ok('B: alta canónica nueva y reintento legado comparten identidad')
  }
}

async function edge(fase) {
  const secreto = readFileSync(privado + 'importar.env', 'utf8').trim().split('=')[1]
  assert.match(secreto, /^[0-9a-f]{64}$/)
  const enviar = async (filas, jwt = true, secret = true) => {
    const headers = { 'Content-Type': 'application/json' }
    if (jwt) headers.Authorization = 'Bearer ' + entorno.SUPABASE_ANON_KEY
    if (secret) headers['x-importar-secret'] = secreto
    const r = await fetch(url + '/functions/v1/crm-importar-leads', { method: 'POST', headers,
      body: JSON.stringify({ filas }), signal: AbortSignal.timeout(45000) })
    return { status: r.status, body: await r.json() }
  }
  assert.equal((await enviar([], false)).status, 401); ok('Edge: gateway exige JWT')
  assert.equal((await enviar([], true, false)).status, 401); ok('Edge: exige secreto separado')
  const fs = [
    { fila: 11, telefono: '984500011', canal: 'FORMULARIO', campania_origen: 'Formulario 3' },
    { fila: 12, telefono: '984500012', canal: 'Formulario 3' },
    { fila: 13, telefono: '984500013', canal: 'FORMULARIO' },
  ].map(f => ({ nombre: 'PRUEBA F3 NATIVO EDGE ' + f.fila, capital: '5000', moneda: 'PEN', autorizo: 'SI', fuente_consentimiento: 'Prueba temporal aislada', ...f }))
  const r = await enviar(fs); assert.equal(r.status, 200); assert.equal(r.body.resultados.length, 3)
  assert.ok(r.body.resultados.every(x => x.resultado === (fase === 'a' ? 'importado' : 'duplicado')))
  const l = await leer(admin, fs); assert.equal(l.error, null); assert.equal(l.data.length, 3)
  assert.deepEqual(l.data.map(x => x.origen), fase === 'a' ? ['formulario', 'formulario', 'formulario'] : ['formulario_3', 'formulario_3', 'formulario'])
  assert.ok(l.data.every(x => !x.alta_manual && !x.vendedor_id && !x.asignado_supervisor_id))
  ok('Edge ' + fase.toUpperCase() + ': n8n legado, etiqueta nueva y Formulario conservan contrato y cola')
  const reenviar = await enviar(fs.slice(0, 2).map(f => ({ ...f, fila: f.fila + 100, canal: 'formulario_3' })))
  assert.equal(reenviar.status, 200); assert.ok(reenviar.body.resultados.every(x => x.resultado === 'duplicado'))
  assert.deepEqual((await leer(admin, fs)).data, l.data); ok('Edge: alias canónico y otra fila no duplican ni alteran la ficha')
  const invalida = await enviar([{ ...fs[1], fila: 14, telefono: '984500014', campania_origen: 'Otra' }])
  assert.equal(invalida.status, 200); assert.equal(invalida.body.resultados[0].resultado, 'rechazado')
  const ausente = await leer(admin, [{ telefono: '984500014' }]); assert.equal(ausente.error, null); assert.equal(ausente.data.length, 0)
  ok('Edge: campaña incompatible rechazada sin alta parcial')
  if (fase === 'b') {
    const f = { ...fs[1], fila: 15, telefono: '984500015', nombre: 'PRUEBA F3 NATIVO EDGE 15' }
    const nuevo = await enviar([f]); assert.equal(nuevo.status, 200); assert.equal(nuevo.body.resultados[0].resultado, 'importado')
    const creado = await leer(admin, [f]); assert.equal(creado.error, null); assert.equal(creado.data[0].origen, 'formulario_3')
    ok('Edge B: nueva importación completa queda nativa')
  }
}

export async function ejecutar(fase) {
  assert.ok(['crear', 'a', 'b', 'edge-a', 'edge-b'].includes(fase), 'Usar crear, a, b, edge-a o edge-b')
  let estado = 'FAIL'
  try {
    if (fase === 'crear') await crear()
    else if (fase.startsWith('edge-')) await edge(fase.slice(-1))
    else await matriz(fase)
    estado = 'PASS'
  } finally {
    writeFileSync(new URL('./http-cloud-' + fase + '.json', import.meta.url), JSON.stringify({ ref, fase, estado, pruebas: evidencia }, null, 2) + '\n')
  }
}
if (process.argv[1]?.endsWith('/http-cloud.mjs')) {
  await ejecutar(process.argv[2])
}
