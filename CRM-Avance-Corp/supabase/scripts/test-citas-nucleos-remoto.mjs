// Banco Supabase desechable con seed-demo. Sesiones y PostgREST reales.
// La clave privilegiada sólo prepara identidades ficticias y prueba offboarding.
// No envía correos, no invoca Edge Functions y no admite producción.
import assert from 'node:assert/strict';
import { randomInt, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { USERS, PRODUCTION_PROJECT_REF } from './fixtures.mjs';

const url = process.env.SUPABASE_URL;
assert(url && new URL(url).protocol === 'https:' && !url.includes(PRODUCTION_PROJECT_REF));
assert(process.env.CRM_DEMO_PASSWORD?.length >= 12);
assert(process.env.SUPABASE_ANON_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY);
const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
const client = () => createClient(url, process.env.SUPABASE_ANON_KEY, options);
const admin = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, options);
const sesiones = {};
let verificaciones = 0;
function check(value, label) { assert(value, label); verificaciones++; console.log(`PASS ${label}`); }
async function ok(request, label) {
  const { data, error } = await request;
  assert(!error, `${label}: ${error?.code} ${error?.message}`);
  return data;
}
async function denegado(request, label, code = '42501') {
  const { error } = await request;
  check(error?.code === code, `${label}: rechazo ${code}`);
}

for (const user of USERS) {
  const c = client();
  const auth = await ok(c.auth.signInWithPassword({ email: user.email, password: process.env.CRM_DEMO_PASSWORD }), `Auth ${user.key}`);
  sesiones[user.key] = { c, id: auth.user.id };
}
const hoy = new Date();
const anio = hoy.getUTCFullYear();
const mes = hoy.getUTCMonth();
const fecha = (m, d) => new Date(Date.UTC(anio, m, d, 15)).toISOString();
const rango = m => ({ p_desde: fecha(m, 1).slice(0, 10), p_hasta: fecha(m + 1, 0).slice(0, 10) });
const rpc = (key, fn, args) => sesiones[key].c.schema('crm').rpc(fn, args);
const leer = async (m = mes) => ok(rpc('gerencia', 'citas_gerencia_consulta_fn', rango(m)), 'consulta Gerencia');
const filas = (r, id) => r.citas.filter(x => x.lead_id === id);
const fila = (r, id) => r.citas.find(x => x.id === id);
check((await leer()).version === 2, 'Gerencia recibe el contrato V2');
for (const user of USERS.filter(u => u.key !== 'gerencia')) {
  await denegado(rpc(user.key, 'citas_gerencia_consulta_fn', rango(mes)), `${user.key} no accede al detalle global`);
}
await denegado(client().schema('crm').rpc('citas_gerencia_consulta_fn', rango(mes)), 'Anon no accede');
await denegado(rpc('gerencia', 'citas_gerencia_consulta_fn', { ...rango(mes), p_desde: fecha(mes, 2).slice(0, 10) }), 'Mes parcial inválido', '22023');
const gerencia = sesiones.gerencia.id;
try {
  await ok(admin.from('perfiles').update({ activo: false }).eq('id', gerencia), 'inactivar perfil Gerencia');
  await denegado(rpc('gerencia', 'citas_gerencia_consulta_fn', rango(mes)), 'Perfil Gerencia inactivo');
} finally {
  await ok(admin.from('perfiles').update({ activo: true }).eq('id', gerencia), 'restaurar perfil Gerencia');
}
try {
  await ok(admin.schema('crm').from('equipo').update({ activo: false }).eq('perfil_id', gerencia), 'inactivar membresía Gerencia');
  await denegado(rpc('gerencia', 'citas_gerencia_consulta_fn', rango(mes)), 'Membresía Gerencia inactiva');
} finally {
  await ok(admin.schema('crm').from('equipo').update({ activo: true }).eq('perfil_id', gerencia), 'restaurar membresía Gerencia');
}

const sufijo = randomUUID().slice(0, 8);
async function lead(nombre) {
  const id = randomUUID();
  await ok(rpc('vend1', 'crear_lead_si_disponible', {
    p_id: id, p_nombre_completo: `CITAS BANCO ${nombre} ${sufijo}`,
    p_telefono: `9${randomInt(10000000, 99999999)}`, p_origen: 'referido',
    p_monto_estimado: 10000, p_moneda: 'PEN', p_vendedor_id: sesiones.vend1.id,
  }), 'crear lead por la RPC del CRM con sesión de analista');
  await ok(sesiones.vend1.c.schema('crm').from('leads').select('id').eq('id', id).single(), 'confirmar alta del lead');
  return id;
}
async function cita(leadId, vence) {
  return (await ok(sesiones.vend1.c.schema('crm').from('tareas').insert({
    id: randomUUID(), lead_id: leadId, tipo: 'reunion', titulo: 'CITAS BANCO',
    modalidad_reunion: 'presencial', ubicacion_reunion: 'Oficina de prueba', vence_en: vence, creado_por: sesiones.vend1.id,
  }).select('id').single(), 'agendar con sesión de analista')).id;
}
const atras = dias => new Date(Date.now() - dias * 86400000).toISOString();
const nativo = await lead('NATIVO');
const ausencia = await cita(nativo, fecha(mes, 0));
const siguiente = randomUUID();
await ok(rpc('vend1', 'cerrar_reunion', {
  p_tarea_id: ausencia, p_estado: 'no_show', p_detalle: 'No asistió; acuerda nueva cita.',
  p_siguiente: { id: siguiente, tipo: 'reunion', titulo: 'CITAS RECUPERACIÓN', vence_en: atras(2), modalidad_reunion: 'presencial', ubicacion_reunion: 'Oficina de prueba' },
}), 'registrar ausencia y siguiente cita');
let r = await leer(mes - 1);
check(fila(r, ausencia)?.estado_comercial === 'no_show', 'Inasistencia del mes anterior visible');
check(fila(r, siguiente)?.reagendada_de === ausencia && fila(r, siguiente)?.estado_comercial === 'vencida', 'Historial trae la nueva cita del mes actual');
check(filas(r, nativo).every(x => !x.cierre_posterior), 'Ningún cierre antes de convertir');
const asistencia = randomUUID();
await ok(rpc('vend1', 'reprogramar_reunion', { p_tarea_id: siguiente, p_nueva_id: asistencia, p_vence_en: atras(1) }), 'reprogramar');
r = await leer();
check(fila(r, siguiente)?.estado_comercial === 'reprogramada' && fila(r, asistencia)?.reagendada_de === siguiente, 'Reprogramación conserva su cadena');
await ok(rpc('vend1', 'cerrar_reunion', { p_tarea_id: asistencia, p_estado: 'completada', p_resultado_reunion: 'interesado', p_detalle: 'Entrevista realizada.' }), 'registrar asistencia');
r = await leer();
check(fila(r, asistencia)?.estado_comercial === 'realizada' && !!fila(r, asistencia)?.asistencia_registrada_en, 'Asistencia tiene actividad real y fecha de registro');
const cancelada = await cita(nativo, atras(1));
await ok(rpc('vend1', 'cerrar_reunion', { p_tarea_id: cancelada, p_estado: 'cancelada', p_motivo_no_realizada: 'cancelada_cliente' }), 'cancelar por analista');
const futura = await cita(nativo, fecha(mes + 1, 2));
r = await leer();
check(fila(r, cancelada)?.estado_comercial === 'cancelada', 'Cancelación del analista clasificada');
check(fila(r, futura)?.estado_comercial === 'programada', 'Historial incluye cita futura fuera del mes');

const email = `citas-${sufijo}@pruebas.example`;
const usuario = await ok(admin.auth.admin.createUser({ email, password: process.env.CRM_DEMO_PASSWORD, email_confirm: true }), 'crear identidad cliente ficticia sin correo');
await ok(admin.from('perfiles').upsert({ id: usuario.user.id, correo: email, nombre_completo: 'CLIENTE CITAS BANCO', rol: 'cliente', activo: true,
  dni: String(randomInt(95000000, 98999999)), asesor_perfil_id: sesiones.vend1.id,
}).select('id').single(), 'preparar perfil cliente ficticio');
await ok(rpc('vend1', 'convertir_lead', { p_lead_id: nativo, p_perfil_id: usuario.user.id }), 'convertir lead en cliente');
r = await leer();
check(r.conversiones.filter(x => x.lead_id === nativo).length === 1, 'Conversión a cliente se cuenta una vez por lead');
check(fila(r, ausencia)?.cierre_posterior && fila(r, asistencia)?.cierre_posterior, 'Ausencia recuperada y entrevista tienen cierre posterior');
check(!fila(r, futura)?.cierre_posterior, 'Una fecha posterior al cierre no se atribuye al depósito');
check(fila(r, futura)?.estado_comercial === 'sistema', 'Conversión cancela la tarea pendiente por sistema');
await ok(rpc('gerencia', 'anular_cierre_avance', { p_lead_id: nativo, p_motivo: 'Prueba ficticia de anulación: excluir el cierre de las métricas.' }), 'anular cierre Avance');
r = await leer();
check(!r.conversiones.some(x => x.lead_id === nativo) && filas(r, nativo).every(x => !x.cierre_posterior), 'Anulación retira conversión y cierres sin borrar el historial');

const externo = await lead('COOPERATIVA');
const reunionExterna = await cita(externo, atras(1));
await ok(rpc('vend1', 'cerrar_reunion', { p_tarea_id: reunionExterna, p_estado: 'completada', p_resultado_reunion: 'interesado' }), 'asistencia previa a cooperativa');
const cierre = await ok(rpc('vend1', 'convertir_lead_externo', {
  p_lead_id: externo, p_cooperativa: 'qorilazo', p_monto: 10000, p_moneda: 'PEN',
  p_documento_tipo: 'DNI', p_documento: String(randomInt(95000000, 98999999)),
  p_nombre: 'CLIENTE CITAS COOPERATIVA', p_numero_transaccion: `CITAS-${sufijo}`,
}), 'registrar cierre cooperativa');
r = await leer();
check(fila(r, reunionExterna)?.cierre_posterior, 'Cierre operativo externo procede del núcleo');
check(!r.conversiones.some(x => x.lead_id === externo), 'Cooperativa sin perfil cliente no infla depósitos por conversión a cliente');
await ok(rpc('gerencia', 'anular_cierre_externo', { p_cierre_id: cierre.cierre_id, p_motivo: 'Prueba ficticia de anulación de cierre externo.' }), 'anular cierre externo');
check(!fila(await leer(), reunionExterna)?.cierre_posterior, 'Anulación externa se refleja en la siguiente lectura');
console.log(JSON.stringify({ estado: 'PASS', verificaciones, nativo, externo, contratosReales: 0, correosEnviados: 0 }));
