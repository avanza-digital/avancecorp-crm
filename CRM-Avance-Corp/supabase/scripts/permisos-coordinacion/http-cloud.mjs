// Rama temporal aprobada por Miguel. Nunca admite producción ni copia datos reales.
// Auth administra exclusivamente usuarios sintéticos; todas las aserciones de
// acceso y corrección utilizan la anon key y sesiones humanas reales.
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const ref = 'dcrnkkjtvnnkvvvxzueo'
const privado = '/private/tmp/permisos-cloud-privado/'
const uid = n => 'cc150000-0000-4000-8000-' + String(n).padStart(12, '0')
const evidencia = []
const ok = nombre => { evidencia.push(nombre); console.log('PASS: ' + nombre) }
const guardar = (nombre, valor) => {
  writeFileSync(privado + nombre, JSON.stringify(valor, null, 2), { mode: 0o600 })
  chmodSync(privado + nombre, 0o600)
}

export async function ejecutar() {
  const entorno = JSON.parse(readFileSync(privado + 'branch.json', 'utf8'))
  const url = `https://${ref}.supabase.co`
  assert.equal(entorno.SUPABASE_URL, url, 'Solo la rama temporal autorizada')
  const destino = new URL(entorno.POSTGRES_URL)
  assert.ok(destino.hostname.includes(ref) || decodeURIComponent(destino.username).includes(ref))
  const pg = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG')))
  Object.assign(pg, {
    PGHOST: destino.hostname, PGPORT: destino.port || '5432', PGDATABASE: destino.pathname.slice(1),
    PGUSER: decodeURIComponent(destino.username), PGPASSWORD: decodeURIComponent(destino.password),
    PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15',
  })
  const sql = texto => {
    const r = spawnSync('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], {
      input: texto, env: pg, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 180000,
    })
    if (r.status !== 0) {
      guardar('ultimo-error-sql.json', { estado: r.status, error: r.stderr })
      throw new Error('SQL del banco falló; detalles en archivo privado, sin credenciales en argumentos')
    }
    return r.stdout.trim()
  }
  const opciones = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }
  const admin = createClient(url, entorno.SUPABASE_SERVICE_ROLE_KEY, opciones)
  const anon = () => createClient(url, entorno.SUPABASE_ANON_KEY, opciones)
  const usuarios = existsSync(privado + 'usuarios.json')
    ? JSON.parse(readFileSync(privado + 'usuarios.json', 'utf8')) : {}
  assert.equal(sql('select count(*) from cron.job where active;'), '0', 'Sin automatizaciones en la rama')
  assert.equal(sql("select count(*) from public.perfiles where correo not like 'prueba%@coordinacion.invalid';"), '0')

  if (sql('select count(*) from public.contratos;') === '0') {
    assert.equal(sql('select count(*) from crm.equipo;'), '0')
    for (let n = 1; n <= 20; n++) {
      if (usuarios[n]) continue
      const usuario = { id: uid(n), email: `prueba${n}@coordinacion.invalid`, password: randomBytes(24).toString('base64url') + 'Aa9!' }
      const r = await admin.auth.admin.createUser({ ...usuario, email_confirm: true })
      assert.equal(r.error, null, r.error?.message)
      assert.equal(r.data.user.id, usuario.id)
      usuarios[n] = usuario; guardar('usuarios.json', usuarios)
    }
    ok('20 identidades sintéticas creadas por Auth, sin enviar correos')
    let fixture = readFileSync(new URL('./fixtures.sql', import.meta.url), 'utf8')
    // El guard de nombre local se reemplaza por el destino cloud cerrado arriba
    // y un marcador de sesión. Se conserva la exigencia de tablas vacías.
    fixture = fixture.replace("current_database() not like 'permisos_coordinacion_%'",
      `current_setting('app.permisos_ref',true) is distinct from '${ref}'`)
    fixture = fixture.replace(/insert into auth\.users\(id,email\)[\s\S]*?from generate_series\(1,20\) n;/,
      '/* Identidades creadas mediante el endpoint administrativo de Auth. */')
    sql(`begin; set local app.permisos_ref='${ref}';\n${fixture}\ncommit;`)
    ok('Fixtures comerciales sintéticos con triggers de contratos activos')
  }

  const sesiones = {}
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
    const c = anon(); const u = usuarios[n]
    assert.ok(u, 'Identidad sintética disponible')
    const r = await c.auth.signInWithPassword({ email: u.email, password: u.password })
    assert.equal(r.error, null, r.error?.message)
    assert.equal(r.data.user.id, uid(n))
    sesiones[n] = c; ok('Sesión Auth real del actor ' + n)
  }
  const rpc = (n, nombre, parametros = {}) => (n === 0 ? anon() : sesiones[n]).schema('crm').rpc(nombre, parametros)
  const permitido = async (nombre, promesa) => {
    const r = await promesa; assert.equal(r.error, null, r.error?.message); ok(nombre); return r.data
  }
  const denegado = async (nombre, promesa, codigo = '42501') => {
    const r = await promesa; assert.equal(r.error?.code, codigo, r.error?.message); ok(nombre)
  }
  const corregir = (n, contrato, categoria, motivo = 'El analista registró una categoría incorrecta') =>
    rpc(n, 'corregir_categoria_contrato_fn', { p_contrato_id: uid(contrato), p_categoria: categoria, p_motivo: motivo })

  for (const [tabla, cantidad] of [['leads', 11], ['actividades', 1], ['tareas', 1]]) {
    const filas = await permitido('Coordinación consulta ' + tabla + ' con RLS real', sesiones[1].schema('crm').from(tabla).select('id'))
    assert.equal(filas.length, cantidad)
  }
  assert.equal((await permitido('Listado global de Leads por HTTP', rpc(1, 'cartera_filtrada_fn'))).items.length, 11)
  assert.equal((await permitido('Buscador global de Leads por HTTP', rpc(1, 'cartera_pagina_fn'))).length, 11)
  assert.equal((await permitido('Cartera completa de clientes por HTTP', rpc(1, 'cartera_inversionistas_filtrada_fn'))).total, 11)
  const estado = await permitido('Estado de cartera consultable', rpc(1, 'cartera_inversionistas_estado_fn'))
  assert.equal(estado.habilitada, true); assert.equal(estado.escritura_habilitada, false)
  const ficha = await permitido('Ficha de cliente consultable', rpc(1, 'inversionista_ficha_fn', { p_inversionista: uid(110) }))
  assert.equal(ficha.capacidades.nueva_inversion, false)
  assert.equal(ficha.capacidades.documentos, false)
  assert.deepEqual(ficha.capacidades.cuentas_perfil_ids, [])
  await permitido('Filtros de equipo visibles', rpc(1, 'equipo_visible_fn'))
  for (const [nombre, parametros] of [
    ['documento_lead_fn', { p_lead_id: uid(4010) }],
    ['conversion_estado_lead_v1', { p_lead_id: uid(4010) }],
    ['potencial_leads_fn', { p_lead_ids: [uid(4010)] }],
    ['estado_sla_leads_v2_fn', { p_lead_ids: [uid(4010)] }],
  ]) await permitido('Consulta ' + nombre, rpc(1, nombre, parametros))
  await denegado('Consulta no permite editar DNI', rpc(1, 'editar_lead_fn', { p_lead_id: uid(4010), p_cambios: { dni: '48009999' } }))
  await denegado('Consulta no permite gestión financiera', rpc(1, 'inversionista_gestion_fn', { p_inversionista: uid(110) }))
  await denegado('Consulta no permite documentos', rpc(1, 'inversionista_documento_fn', { p_inversionista: uid(110), p_fuente: uid(2010), p_documento: uid(2010) }))
  await denegado('Consulta no permite banca', rpc(1, 'inversionista_cuentas_fn', { p_inversionista: uid(110), p_perfil: uid(10), p_moneda: 'PEN' }))
  const escritos = await permitido('UPDATE directo de lead no concede filas', sesiones[1].schema('crm').from('leads').update({ nota: 'Intento denegado' }).eq('id', uid(4010)).select('id'))
  assert.deepEqual(escritos, [])
  await denegado('No permite insertar gestión de otro analista', sesiones[1].schema('crm').from('actividades').insert({ lead_id: uid(4010), tipo: 'nota', creado_por: uid(1) }))
  for (const n of [0, 4, 5, 6, 8, 9, 10]) await denegado('Corrección denegada al actor ' + n, corregir(n, 2020, 'renovacion'))
  await denegado('Categoría inválida rechazada', corregir(1, 2010, 'otra'), '22023')
  await denegado('Motivo insuficiente rechazado', corregir(1, 2010, 'renovacion', 'x'), '22023')

  const foto = () => sql(`select jsonb_build_object(
    'contratos',(select jsonb_agg(jsonb_build_array(id,capital,moneda,tasa_anual,fecha_inicio,fecha_vencimiento,analista_cierre_id) order by id) from public.contratos),
    'operaciones',(select jsonb_agg(to_jsonb(o) order by id) from crm.operaciones_cartera o),
    'relojes',(select jsonb_agg(jsonb_build_array(id,confirmado_en,vinculado_en,acreditado_en,fecha_comercial,plazo_hasta) order by id) from crm.conversion_acreditaciones));`)
  const antes = foto()
  const transiciones = [[10, 1, 'renovacion'], [11, 2, 'nuevo'], [12, 3, 'upgrade'], [13, 7, 'upgrade'], [14, 1, 'renovacion'], [15, 2, 'nuevo']]
  for (const [n, actor, categoria] of transiciones) {
    const r = await permitido(`Corrección real de contrato ${n} a ${categoria}, actor ${actor}`, corregir(actor, 2000 + n, categoria))
    assert.equal(r.ok, true); assert.equal(r.cambio, true); assert.equal(r.categoria, categoria)
    const categoriaRanking = sql(`select categoria from private.ranking_capital_origen_filas('2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',null) where operacion_id='${uid(2000 + n)}';`)
    assert.equal(categoriaRanking, categoria)
    const conversion = JSON.parse(sql(`select jsonb_build_object('eventos',count(*),'cierres',count(*) filter(where e.tipo='cierre'),'aporte',coalesce(sum(aporte_numerador),0)) from private.conversion_episodios('2026-10-01 00:00:00-05','2026-11-01 00:00:00-05','2026-10-01',true,'{}',0.15) e where (e.tipo='cierre' and e.lead_id='${uid(4000 + n)}') or (e.tipo='operacion' and e.operacion_id in (select o.id from private.operaciones_cartera_clasificadas() o where o.contrato_nuevo_id='${uid(2000 + n)}'));`))
    assert.deepEqual(conversion, { eventos: 1, cierres: categoria === 'nuevo' ? 1 : 0, aporte: categoria === 'renovacion' ? 0 : 1 })
    ok(`Ranking y conversión reclasificados sin duplicación: ${n}`)
  }
  assert.equal(foto(), antes); ok('Capital, tasas, fechas, operador, operaciones y relojes intactos')
  assert.equal(sql('select count(*) from crm.correcciones_categoria_contrato;'), '6')
  assert.equal((await permitido('Reintento HTTP idempotente', corregir(1, 2010, 'renovacion'))).cambio, false)
  assert.equal(sql('select count(*) from crm.correcciones_categoria_contrato;'), '6')
  await denegado('La auditoría no se puede fabricar por HTTP', sesiones[1].schema('crm').from('correcciones_categoria_contrato').insert({ contrato_id: uid(2010), actor_id: uid(1), categoria_anterior: 'renovacion', categoria_nueva: 'nuevo', motivo: 'Intento de fabricación' }))
  await permitido('Conversión mensual responde después de las correcciones', rpc(1, 'conversion_mensual_fn', { p_periodo: '2026-10-01' }))
  await permitido('Cumplimiento de metas responde después de las correcciones', rpc(1, 'cumplimiento_metas_fn', { p_periodo: '2026-10-01' }))

  sql("insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura) values('2026-10-01',0.15,1,'{}');")
  await denegado('Mes sellado rechaza la corrección por HTTP', corregir(1, 2020, 'renovacion'), 'P0409')
  sql(`begin; set local session_replication_role=replica; update crm.equipo set activo=false where perfil_id='${uid(1)}'; commit;`)
  assert.deepEqual(await permitido('Mismo JWT deja de leer Leads después de baja', sesiones[1].schema('crm').from('leads').select('id')), [])
  await denegado('Mismo JWT deja de consultar cartera después de baja', rpc(1, 'cartera_inversionistas_estado_fn'))
  await denegado('Mismo JWT deja de corregir después de baja', corregir(1, 2020, 'renovacion'))
  guardar('resultado-http.json', { resultado: 'PASS', ref, comprobaciones: evidencia, total: evidencia.length })
  console.log(`PASS: ${evidencia.length} comprobaciones con Auth/PostgREST reales; solo datos sintéticos`)
}
