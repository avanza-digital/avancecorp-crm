import { entorno } from './banco-local.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, sesion, rpc, http } from './banco-local.mjs';

const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const vendedor = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const ejecucion = randomUUID();
const hoy = sql("select (statement_timestamp() at time zone 'America/Lima')::date");
const pruebas = [];
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT9sAAAAASUVORK5CYII=', 'base64');
function ok(r, caso) { assert.equal(r.ok, true, `${caso}: ${JSON.stringify(r.data)}`); return r.data; }
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
// Misma semilla de la migración vigente (20260811154434), sin sustituir políticas.
sql(`insert into crm.conversion_pesos(vigente_desde,peso_referido,nota)
  select '2026-07-01',0.150,'Regla documentada; banco ficticio F4'
  where not exists(select 1 from crm.conversion_pesos);`);
if (sql("select count(*) from crm.periodos_cerrados where periodo='2026-07-01'") === '0') {
  ok(await rpc('cerrar_periodo', { p_periodo: '2026-07-01' }, gerente), 'sello por la RPC vigente');
}
assert.equal(sql("select count(*) from crm.periodos_cerrados where periodo='2026-08-01'"), '0',
  'El caso agosto requiere un mes abierto dentro de la ventana de ajuste');
const sello = () => sql(`select jsonb_build_object(
  'mes',(select to_jsonb(p) from crm.periodos_cerrados p where periodo='2026-07-01'),
  'foto',(select coalesce(jsonb_agg(to_jsonb(v) order by vendedor_id),'[]') from crm.cierre_mes_vendedor v where periodo='2026-07-01'))`);
const cerradoAntes = sello();
const conv = () => sql(`select coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text),'[]')
  from private.conversion_episodios('2026-09-01T00:00:00-05:00','2026-10-01T00:00:00-05:00','2026-09-01',true,'{}',0.15) c`);
const convAntes = conv();
function solicitud(fecha, monto = 450) {
  const clave = randomUUID();
  return { clave, payload: { inversionista_id: base.identidades.qorilazo, empresa: 'qorilazo',
    monto, moneda: 'PEN', numero_transaccion: `F4-FECHA-${clave}`, referencia: `ENSAYO-${ejecucion}`,
    fecha_comercial: fecha, vence_en: '2027-07-15', evidencia: { ruta: `${base.identidades.qorilazo}/${clave}/comprobante.png` } } };
}
const preparar = s => rpc('preparar_inversion_fn', { p_clave: s.clave, p_datos: s.payload }, vendedor);
for (const invalida of [solicitud('2099-01-01'), solicitud('infinity'), solicitud(hoy, 'NaN'), solicitud(hoy, -1), solicitud(hoy, 100.001)]) {
  const r = await preparar(invalida);
  assert.equal(r.ok, false);
  assert.equal(r.data.code, '22023');
  assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(invalida.clave)}`), '0');
}
pruebas.push({ nombre: 'Fechas futuras/infinita y montos inválidos rechazados antes de preparar', casos: 5 });
const resultados = [];
for (const fecha of ['2026-08-20', '2026-07-15']) {
  const s = solicitud(fecha);
  ok(await preparar(s), 'preparar fecha comercial');
  ok(await http(`/storage/v1/object/f4-comprobantes/${s.payload.evidencia.ruta}`, {
    token: vendedor, rawBody: png, headers: { 'Content-Type': 'image/png', 'x-upsert': 'false' },
  }), 'comprobante');
  const res = ok(await rpc('confirmar_inversion_fn', { p_solicitud: s.clave }, vendedor), 'confirmar fecha comercial');
  resultados.push(res);
  const ajuste = fecha.startsWith('2026-07');
  assert.equal(res.fuente.fecha_comercial, fecha);
  assert.equal(res.fuente.fecha_imputacion, ajuste ? hoy : fecha);
  assert.equal(res.fuente.ajuste_mes_cerrado, ajuste);
  assert.equal(sql(`select count(*) from crm.inversion_ajustes_mes_cerrado where inversion_id=${q(res.inversion_id)}`), ajuste ? '1' : '0');
  const fila = JSON.parse(sql(`select to_jsonb(c) from private.capital_episodios(
    '2026-07-01T00:00:00-05:00','2026-10-01T00:00:00-05:00',true,'{}') c
    where c.cierre_externo_id=${q(res.fuente.cierre_id)}`));
  assert.equal(fila.monto, 450);
  assert.equal(fila.moneda, 'PEN');
  assert.equal(fila.mes_comercial, ajuste ? hoy.slice(0, 7) + '-01' : '2026-08-01');
  pruebas.push({ nombre: ajuste ? 'Mes sellado: ajuste posterior con fecha comercial conservada' : 'Mes abierto: se usa la fecha comercial anterior al registro',
    monto: 450, moneda: 'PEN', fechaComercial: fecha, fechaImputacion: res.fuente.fecha_imputacion });
}
const anular = resultados[0];
const r = ok(await rpc('anular_cierre_externo', { p_cierre_id: anular.fuente.cierre_id,
  p_motivo: 'ENSAYO F4 DE ANULACION COMERCIAL' }, gerente), 'anulación comercial');
assert(r);
assert.equal(sql(`select estado from crm.inversiones where id=${q(anular.inversion_id)}`), 'anulada');
assert.equal(sql(`select count(*) from crm.inversion_eventos where inversion_id=${q(anular.inversion_id)} and tipo='anulacion'`), '1');
assert.equal(sql(`select sum(c.monto) from private.capital_episodios(
  '2026-08-01T00:00:00-05:00','2026-09-01T00:00:00-05:00',true,'{}') c
  where c.cierre_externo_id=${q(anular.fuente.cierre_id)}`), '450.00');
assert.equal(sql(`select private.cierre_anulado(${q(base.leads.qorilazo)})`), 'f',
  'Anular una inversión adicional no puede anular el cierre inicial del lead');
assert.equal(conv(), convAntes);
assert.equal(sello(), cerradoAntes, 'Se reescribió un período cerrado');
const estado = ok(await rpc('cierres_estado_fn', { p_lead_ids: [base.leads.qorilazo] }, gerente), 'lector del cierre inicial');
assert(estado);
const lector = ok(await rpc('cierres_externos_fn', { p_periodo: '2026-08-01' }, gerente), 'lector mensual de cierres');
const leida = lector.cierres_mes.find(c => c.cierre_id === anular.fuente.cierre_id);
assert(leida, 'El lector debe encontrar la inversión en su mes comercial');
assert.equal(leida.fecha_comercial, '2026-08-20');
assert.equal(leida.es_cierre_inicial, false);
assert(leida.anulado_en, 'La fila mensual conserva también el rastro de su anulación');
assert.equal(lector.cierres_mes_total, Number(sql(`select count(*) from crm.cierres_externos
  where coalesce(fecha_imputacion,(creado_en at time zone 'America/Lima')::date) between '2026-08-01' and '2026-08-31'`)));
pruebas.push({ nombre: 'Anulación comercial conserva Capital, conversión inicial e historia, y sincroniza la inversión', capitalConservadoPEN: 450 });
pruebas.push({ nombre: 'Sello y fotografías anteriores idénticos después del ajuste y la anulación', sinReescritura: true });
writeFileSync(new URL(`../evidencia-f4/fechas-anulacion-${ejecucion}.json`, import.meta.url), JSON.stringify({
  entorno, ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  alcance: 'Fechas cooperativas, meses sellados, lectura mensual y anulación de inversión adicional. Anulación inicial, renovaciones, comisión y carrera sello/alta aún requieren pruebas específicas.',
}, null, 2) + '\n');
console.log('Fechas F4: registro anterior y mes sellado correctos; anulación conserva Capital e historia sin afectar el cierre inicial.');
