import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { spawnSync } from 'node:child_process'

const endpoint = new URL(process.env.SUPABASE_URL)
const ref = endpoint.hostname.split('.')[0]
assert.notEqual(ref, 'dctqcbznekcyxhjujuci', 'PRODUCCION PROHIBIDA')
assert.equal(ref, process.env.CRM_ORIGEN_TEST_REF, 'Confirmar rama ficticia exclusiva')
assert.match(ref, /^[a-z]{20}$/)
const db = new URL(process.env.POSTGRES_URL)
assert.equal(db.username, `postgres.${ref}`)
const env = { ...process.env, PGHOST: db.hostname, PGPORT: '5432', PGDATABASE: 'postgres',
  PGUSER: decodeURIComponent(db.username), PGPASSWORD: decodeURIComponent(db.password), PGSSLMODE: 'require' }
const q = s => "'" + String(s).replaceAll("'", "''") + "'"
const id = n => `b0000000-0000-4000-8000-${String(n).padStart(12, '0')}`
let preparar = ''
function sql(s, error) {
  const r = spawnSync(process.env.PSQL_BIN || '/opt/homebrew/opt/postgresql@17/bin/psql', ['-XqAt', '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    input: `begin; set local statement_timeout='30s'; ${preparar} ${s}; rollback;`,
    env, encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024,
  })
  if (error) { assert.notEqual(r.status, 0); assert.match(r.stderr, error); return }
  assert.equal(r.status, 0, r.stderr)
  return r.stdout.trim().split('\n').at(-1)
}
assert.equal(sql("select count(*) from public.perfiles where nombre_completo not like 'PRUEBA %'"), '0')
// La semilla de ranking contiene la politica; las altas necesitan sus etapas.
preparar = "insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos) select md5('ranking-sla')::uuid,e,1440 from unnest(array['nuevo','contactado','reunion_agendada','propuesta_enviada']) e on conflict do nothing;"
const actor = n => `select set_config('request.jwt.claim.sub',${q(id(n))},true);`
const alta = origen => `select crm.crear_lead_si_disponible('PRUEBA ALTA CONCRETA','+51988009901',${origen},1000,'PEN')`
for (const n of [1, 2, 3]) {
  for (const origen of ['landing', 'formulario', 'oficina']) assert.equal(JSON.parse(sql(actor(n) + 'set local role authenticated;' + alta(q(origen)))).estado, 'creado')
  for (const origen of ["'otro'", 'null']) sql(actor(n) + 'set local role authenticated;' + alta(origen), /Selecciona un canal concreto/)
}
for (const origen of ['landing', 'formulario']) {
  const fila = { nombre_completo: 'PRUEBA PUENTE', telefono: '+51988009902', origen, monto_estimado: 1000, moneda: 'PEN' }
  assert.equal(JSON.parse(sql(`set local role service_role; select crm.importar_lead_fn(${q(JSON.stringify(fila))}::jsonb)`)).resultado, 'importado')
}
sql("insert into crm.leads(nombre_completo,telefono,monto_estimado,moneda) values('PRUEBA SIN CANAL','+51988009903',1000,'PEN')", /Selecciona un canal concreto/)
console.log('PASS altas de tres roles, puente Landing/Formulario y rechazo de Otro/ausente')

const key = process.env.SUPABASE_ANON_KEY
const service = process.env.SUPABASE_SERVICE_ROLE_KEY
assert.ok(key && service)
async function request(path, method, body, token, crm = true) {
  const r = await fetch(new URL(path, endpoint), { method,
    headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(crm ? { 'Content-Profile': 'crm', 'Accept-Profile': 'crm' } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30000) })
  return { status: r.status, data: await r.json() }
}
async function login(n) {
  const password = randomBytes(24).toString('base64url')
  const updated = await request(`/auth/v1/admin/users/${id(n)}`, 'PUT', { password, email_confirm: true }, service, false)
  assert.equal(updated.status, 200)
  const r = await request('/auth/v1/token?grant_type=password', 'POST', { email: `ranking-${n}@example.test`, password }, key, false)
  assert.equal(r.status, 200)
  return r.data.access_token
}
for (const token of [key, service, await login(1), await login(2), await login(3)]) {
  for (const method of ['GET', 'POST', 'PATCH', 'DELETE']) {
    const body = method === 'POST' ? { origen: 'landing' } : method === 'PATCH' ? { activo: false } : undefined
    const r = await request('/rest/v1/origenes_capital_confirmados?id=eq.00000000-0000-0000-0000-000000000000', method, body, token)
    assert.ok([401, 403].includes(r.status), `Tabla privada ${method}: ${r.status}`)
  }
}
for (const token of [key, service]) {
  const r = await request('/rest/v1/rpc/crear_lead_si_disponible', 'POST', { p_nombre_completo: 'PRUEBA', p_telefono: '+51988009904', p_origen: 'formulario', p_monto_estimado: 1000, p_moneda: 'PEN' }, token)
  assert.ok([401, 403].includes(r.status))
}
console.log('PASS HTTP/Auth: tabla privada sin CRUD para anon, service y tres roles; RPC manual protegida')

// Dos fuentes ficticias sin lead. Se crean y revierten dentro de cada ensayo.
const fuentes = `set local session_replication_role=replica;
insert into auth.users(id,email,aud,role) values('${id(100)}','origen-100@example.test','authenticated','authenticated');
insert into public.perfiles(id,nombre_completo,rol,activo) values('${id(100)}','PRUEBA ORIGEN SIN LEAD','cliente',true);
insert into crm.inversionistas(id,perfil_id) values(md5('origen-persona')::uuid,'${id(100)}');
insert into public.contratos select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object('id',md5('origen-contrato')::uuid,'numero_contrato','ORIGEN-PEN','cliente_id','${id(100)}','capital',10000,'moneda','PEN','categoria','nuevo','es_demo',false,'fecha_cierre_comercial','2026-09-12'))).* from public.contratos c where numero_contrato='RANKING-5';
insert into storage.buckets(id,name) values('prueba-origen','prueba-origen');
insert into storage.objects(id,bucket_id,name) values(md5('origen-comprobante')::uuid,'prueba-origen','prueba.pdf');
insert into crm.cierres_externos(id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,numero_transaccion,vendedor_id,creado_por,creado_en,es_cierre_inicial,inversionista_id,fecha_comercial,fecha_imputacion,referencia_externa,comprobante_objeto_id)
values(md5('origen-externo')::uuid,'qorilazo',1000,'USD','DNI','88899001','PRUEBA ORIGEN SIN LEAD','ORIGEN-USD','${id(2)}','${id(2)}','2026-09-12 12:00-05',false,md5('origen-persona')::uuid,'2026-09-12','2026-09-12','ORIGEN-USD-REF',md5('origen-comprobante')::uuid);
set local session_replication_role=origin;`
const confirmar = (origen = 'landing', externa = false, usuario = 3) => `insert into crm.origenes_capital_confirmados(${externa ? 'cierre_externo_id' : 'contrato_id'},origen,motivo,confirmado_por) values(md5('${externa ? 'origen-externo' : 'origen-contrato'}')::uuid,${q(origen)},'Confirmacion ficticia del banco',${q(id(usuario))});`
for (const origen of ['landing', 'formulario', 'referido', 'oficina']) {
  sql(fuentes + actor(3) + `do $$ declare a jsonb; b jsonb; c jsonb; d jsonb; begin
select jsonb_agg(to_jsonb(t)-'origen' order by operacion_id) into a from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null) t;
c:=crm.conversion_mensual_fn('2026-09-01');
${confirmar(origen)} ${confirmar('formulario', true)}
if private.ranking_origen_confirmado(md5('origen-contrato')::uuid,null)<>${q(origen)} then raise exception 'No lee confirmacion'; end if;
if not exists(select 1 from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null) where operacion_id=md5('origen-contrato')::uuid and capital=10000 and origen=${q(origen)}) then raise exception 'Contrato no clasificado'; end if;
if not exists(select 1 from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null) where operacion_id=md5('origen-externo')::uuid and capital=1000 and origen='formulario') then raise exception 'COOPAC no clasificada'; end if;
select jsonb_agg(to_jsonb(t)-'origen' order by operacion_id) into b from private.ranking_capital_origen_filas('2026-09-01 00:00-05','2026-10-01 00:00-05',null) t;
d:=crm.conversion_mensual_fn('2026-09-01');
if a is distinct from b or c is distinct from d then raise exception 'Cambio de capital, atribucion o conversion'; end if;
if (select count(*) from public.audit_log where tabla='crm.origenes_capital_confirmados')<>2 then raise exception 'Auditoria ausente'; end if;
end $$;`)
}
console.log('PASS cuatro canales: contrato PEN/COOPAC USD clasificados; capital, atribucion y conversion intactos')
for (const n of [1, 2]) sql(fuentes + actor(n) + confirmar(), /Gerencia/)
sql(fuentes + actor(3) + `set local session_replication_role=replica; update crm.equipo set activo=false where perfil_id='${id(3)}'; set local session_replication_role=origin;` + confirmar(), /Gerencia/)
sql(fuentes + confirmar(), /Gerencia/)
sql(fuentes + actor(3) + confirmar('landing', false, 2), /actor de la confirmacion/)
sql(fuentes + actor(3) + confirmar() + confirmar(), /duplicate key/)
sql(fuentes + actor(3) + confirmar() + "update crm.origenes_capital_confirmados set origen='formulario'", /solo admite desactivacion/)
sql(fuentes + actor(3) + confirmar() + 'delete from crm.origenes_capital_confirmados', /no se eliminan/)
sql(fuentes + actor(3) + "insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura) values('2026-09-01',0.15,1,'{}');" + confirmar(), /mes comercial ya esta sellado/)
sql(fuentes + actor(3) + "set local session_replication_role=replica; update public.contratos set es_demo=true where id=md5('origen-contrato')::uuid; set local session_replication_role=origin;" + confirmar(), /no elegible/)
sql(fuentes + actor(3) + "set local session_replication_role=replica; update public.contratos set categoria='renovacion' where id=md5('origen-contrato')::uuid; set local session_replication_role=origin;" + confirmar(), /no elegible/)
sql(fuentes + actor(3) + `set local session_replication_role=replica; update crm.cierres_externos set anulado_en=now(),anulado_por='${id(3)}',motivo_anulacion='PRUEBA anulacion' where id=md5('origen-externo')::uuid; set local session_replication_role=origin;` + confirmar('landing',true), /no elegible/)
sql(fuentes + actor(3) + confirmar() + "set local session_replication_role=replica; update public.contratos set es_demo=true where id=md5('origen-contrato')::uuid; set local session_replication_role=origin; update crm.origenes_capital_confirmados set activo=false; do $$begin if private.ranking_origen_confirmado(md5('origen-contrato')::uuid,null) is not null then raise exception 'Confirmacion no desactivada';end if;end $$")
console.log('PASS autorizacion, actor, duplicado, inmutabilidad, mes cerrado, demo y desactivacion posterior')
console.log('PASS todos los hechos del banco revertidos; ninguna escritura productiva')
