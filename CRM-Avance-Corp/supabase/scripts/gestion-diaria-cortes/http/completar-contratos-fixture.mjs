// Completa los dos contratos HISTÓRICOS del seed canónico sin volver a escribir
// actividades inmutables. El producto técnico legacy está archivado y permite
// snapshots, como se verificó en el origen. No se desactiva ningún trigger.
import './fetch-local.mjs';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { BANK_CLIENT, BANK_CONTRACT, BANK_LEGACY_CONTRACT, LEADS, USERS } from '../../fixtures.mjs';
import { sql, credencialesLocales } from './banco.mjs';

assert.deepEqual(process.argv.slice(2), ['--solo-banco-autorizado']);
const ids = Object.fromEntries(JSON.parse(sql("select jsonb_agg(jsonb_build_object('correo',correo,'id',id)) from public.perfiles"))
  .map(p => [USERS.find(u => u.email === p.correo)?.key, p.id]));
assert.ok(ids.clientBank && ids.vend1 && ids.gerencia && !ids.undefined, 'Perfiles fuera del seed canónico');
assert.equal(sql('select count(*) from crm.leads'), String(LEADS.length));
const c = credencialesLocales();
const admin = createClient(c.API_URL, c.SERVICE_ROLE_KEY, { auth: { persistSession:false, autoRefreshToken:false } });
async function exigir(etiqueta, peticion) {
  const r = await peticion;
  if (r.error) throw new Error(`${etiqueta}: ${r.error.code} ${r.error.message}`);
  return r.data;
}
sql(`begin;
  insert into crm.empresas(clave,nombre_legal,nombre_visible,monedas,crea_contrato_avance,
    requiere_portal,exige_numero_transaccion,fuente_capital)
  select * from (values
    ('avance','Avance prueba','Avance prueba',array['PEN','USD'],true,true,false,'contratos'),
    ('qorilazo','Qorilazo prueba','Qorilazo prueba',array['PEN'],false,false,true,'cierres_externos'),
    ('prodelco','Prodelco prueba','Prodelco prueba',array['PEN'],false,false,true,'cierres_externos')
  ) x(clave,nombre_legal,nombre_visible,monedas,crea_contrato_avance,requiere_portal,exige_numero_transaccion,fuente_capital)
  where not exists(select 1 from crm.empresas e where e.clave=x.clave);
  insert into crm.productos_inversion(codigo,estado,es_legacy,permite_altas_legacy,archivado_en)
  select 'HISTORICO-SIN-CATALOGO','archivado',true,true,now()
  where not exists(select 1 from crm.productos_inversion where codigo='HISTORICO-SIN-CATALOGO');
  insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,
    vigencia_solicitud_dias,modo,nota)
  select 1,'-infinity',15,18,1,'observacion','Regla del fixture local; sin datos personales'
  where not exists(select 1 from crm.politica_rentabilidad);
  insert into crm.multiempresa_flags(nombre,activo)
  select * from (values ('ficha_360_neutral',true),('inversiones_escritura',true),
    ('metricas_multiempresa_sombra',false),('postventa_neutral',true),('resolver_en_puertas',true)) x(nombre,activo)
  where not exists(select 1 from crm.multiempresa_flags f where f.nombre=x.nombre);
  commit;`);
const teniaLectura = sql("select has_table_privilege('service_role','crm.periodos_cerrados','SELECT')") === 't';
try {
  assert.equal(sql("select permite_altas_legacy from crm.productos_inversion where codigo='HISTORICO-SIN-CATALOGO'"),'t');
  if (!teniaLectura) sql('grant select on crm.periodos_cerrados to service_role');
  for (const f of [BANK_CONTRACT, BANK_LEGACY_CONTRACT]) {
    const actual = await exigir('Leer contrato ficticio', admin.from('contratos').select('id').eq('id',f.id).maybeSingle());
    if (!actual) await exigir('Crear contrato histórico ficticio',admin.from('contratos').insert({
      id:f.id, numero_contrato:f.number, cliente_id:ids.clientBank, creado_por:ids.vend1,
      capital:f.capital, categoria:f.category, moneda:f.currency, estado:'activo',
      fecha_inicio:f.startDate,fecha_vencimiento:f.endDate,modalidad:f.paymentMode,
      tipo_interes:f.interestType,tasa_anual:f.annualRate,notas_internas:f.internalNotes,
    }));
  }
} finally {
  if (!teniaLectura) sql('revoke select on crm.periodos_cerrados from service_role');
}
const cuenta = await exigir('Leer cuenta ficticia',admin.schema('crm').from('cuentas_bancarias').select('id').eq('id',BANK_CONTRACT.accountId).maybeSingle());
if (!cuenta) await exigir('Crear cuenta ficticia',admin.schema('crm').from('cuentas_bancarias').insert({
  id:BANK_CONTRACT.accountId,cliente_id:ids.clientBank,creado_por:ids.vend1,
  moneda:BANK_CONTRACT.currency,banco:BANK_CLIENT.bank,numero_cuenta:BANK_CLIENT.accountNumber,
  tipo_cuenta:BANK_CLIENT.accountType,cci:BANK_CLIENT.cci,activa:true,origen:'perfil',titular_distinto:false,
}));
const enlace = await exigir('Leer enlace ficticio',admin.schema('crm').from('contrato_cuentas_pago').select('id,cuenta_bancaria_id')
  .eq('contrato_id',BANK_CONTRACT.id).maybeSingle());
if (!enlace) await exigir('Enlazar cuenta ficticia',admin.schema('crm').from('contrato_cuentas_pago').insert({
  id:BANK_CONTRACT.paymentLinkId,contrato_id:BANK_CONTRACT.id,cuenta_bancaria_id:BANK_CONTRACT.accountId,creado_por:ids.vend1,
}));
else assert.equal(enlace.cuenta_bancaria_id,BANK_CONTRACT.accountId);
assert.equal(sql(`select count(*) from crm.contrato_cuentas_pago where contrato_id='${BANK_LEGACY_CONTRACT.id}'`),'0');
sql(`begin;
  alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
  update crm.equipo set activo=false where perfil_id='${ids.vendInactive}';
  alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
  commit;`);
assert.equal(sql("select permite_altas_legacy from crm.productos_inversion where codigo='HISTORICO-SIN-CATALOGO'"),'t');
console.log('PASS: dos contratos históricos ficticios y cuenta canónica; catálogo técnico conservado y baja histórica completada');
