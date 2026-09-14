// Banco exclusivo de Citas, Auth/PostgREST reales. Sin producción ni correos.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { USERS } from './fixtures.mjs';
const url = process.env.SUPABASE_URL;
assert.equal(url, 'https://xhgsjtzpmwlqfkninphl.supabase.co');
const password = process.env.CRM_DEMO_PASSWORD;
assert(password?.length >= 12);
const opts = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
const cliente = () => createClient(url, process.env.SUPABASE_ANON_KEY, opts);
const admin = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, opts);
let pruebas = 0;
const comprobar = (valor, nombre) => { assert(valor, nombre); pruebas++; console.log(`PASS ${nombre}`); };
const ok = async peticion => { const r = await peticion; assert(!r.error, r.error?.message); return r.data; };
const denegado = async (peticion, nombre) => { const r = await peticion; comprobar(r.error?.code === '42501', nombre); };
const config = { citas_por_lead: 1.25, entrevistas_porcentaje: 70, depositos_porcentaje: 70,
  excluir_manuales_base: false, actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas',
  base_avance: 'actividad_real', mes_resultado: 'evento', analista_resultado: 'evento',
  mes_inicio: '2099-01', mostrar_meta_citas: false, base_depositos: 'entrevistas' };
for (const u of USERS) {
  const c = cliente();
  await ok(c.auth.signInWithPassword({ email: u.email, password }));
  await denegado(c.schema('crm').rpc('control_citas_configuracion_fn'), `${u.key}: no lee configuración`);
  await denegado(c.schema('crm').rpc('guardar_control_citas_fn', { p_version_esperada: 0, p_configuracion: config }), `${u.key}: no guarda`);
  await denegado(c.schema('crm').rpc('aplicar_control_citas_fn', { p_version_esperada: 1 }), `${u.key}: no aplica`);
}
await denegado(cliente().schema('crm').rpc('control_citas_configuracion_fn'), 'Anónimo denegado');
const email = `citas-control-${randomUUID()}@pruebas.example`;
const alta = await ok(admin.auth.admin.createUser({ email, password, email_confirm: true }));
const id = alta.user.id;
try {
  await ok(admin.from('perfiles').upsert({ id, correo: email, nombre_completo: 'SUPERADMIN CITAS SINTETICO', rol: 'superadmin', activo: true }));
  const c = cliente();
  await ok(c.auth.signInWithPassword({ email, password }));
  const rpc = (name, args) => c.schema('crm').rpc(name, args);
  const antes = await ok(rpc('control_citas_configuracion_fn'));
  const guardado = await ok(rpc('guardar_control_citas_fn', { p_version_esperada: antes.version_actual, p_configuracion: config, p_nota: 'Prueba HTTP de preparación; no usar en producción' }));
  comprobar(guardado.version_actual === antes.version_actual + 1, 'Superadmin guarda nueva versión');
  comprobar(!guardado.aplicaciones.some(a => a.version === guardado.version_actual), 'Guardar no aplica');
  const conflicto = await rpc('guardar_control_citas_fn', { p_version_esperada: antes.version_actual, p_configuracion: config }).abortSignal(AbortSignal.timeout(15_000));
  comprobar(conflicto.error?.code === 'PT409' && conflicto.status === 409, 'Conflicto concurrente responde HTTP 409 sin sobrescribir');
  const conflictoAplicacion = await rpc('aplicar_control_citas_fn', { p_version_esperada: antes.version_actual }).abortSignal(AbortSignal.timeout(15_000));
  comprobar(conflictoAplicacion.error?.code === 'PT409' && conflictoAplicacion.status === 409, 'Aplicación desactualizada responde HTTP 409');
  const aplicado = await ok(rpc('aplicar_control_citas_fn', { p_version_esperada: guardado.version_actual }));
  comprobar(aplicado.aplicaciones.some(a => a.version === guardado.version_actual && a.mes_inicio === '2099-01'), 'Aplicación explícita conserva vigencia');
  await denegado(c.schema('crm').from('control_citas_versiones').select('*'), 'Superadmin sin acceso directo al historial');
  await denegado(c.schema('crm').from('control_citas_aplicaciones').select('*'), 'Superadmin sin acceso directo a aplicaciones');
  await ok(admin.from('perfiles').update({ activo: false }).eq('id', id));
  await denegado(rpc('control_citas_configuracion_fn'), 'Perfil inactivo denegado aunque el token siga vigente');
} finally {
  // Conserva auditoría e historia por sus FK; la identidad ficticia queda inactiva.
  await ok(admin.from('perfiles').update({ activo: false }).eq('id', id));
  await ok(admin.auth.admin.updateUserById(id, { ban_duration: '876000h' }));
}
console.log(JSON.stringify({ estado: 'PASS', pruebas, produccion: false, correos: 0, vigencia_sintetica: '2099-01' }));
