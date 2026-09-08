import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { banco, sql, literal as q, guardar, leer, sesion, rpc } from './banco-local.mjs';
import { contratoPrueba } from './operaciones-fixture.mjs';

const f = leer('fixtures.json');
const vendedor = f.usuarios.vendedor.id;
const token = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
assert.equal(sql("select to_regclass('crm.inversion_solicitudes') is null"), 't',
  'Esta semilla debe completarse ANTES de instalar F4');
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
const nombre = 'operaciones-base.json';
const estado = existsSync(join(banco, nombre)) ? leer(nombre) : { leads: {}, contratos: {}, cierres: {} };
const checkpoint = () => guardar(nombre, estado);
// Semilla publicada por 20260811154434_crm_conversion_mensual_ponderada.sql.
sql(`insert into crm.conversion_pesos(vigente_desde,peso_referido,nota)
  select '2026-07-01',0.150,'Regla documentada; banco ficticio F4'
  where not exists(select 1 from crm.conversion_pesos);`);
async function llamar(nombre, datos, t = token) {
  const r = await rpc(nombre, datos, t);
  assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`);
  return r.data;
}

if (!estado.producto) {
  assert.equal(sql("select count(*) from crm.productos_inversion where codigo='F4-SINTETICO'"), '0',
    'Revisar respuesta perdida del catálogo antes de repetirlo');
  const condiciones = ['nuevo', 'renovacion', 'upgrade'].flatMap(categoria =>
    ['PEN', 'USD'].map(moneda => ({ categoria, moneda, plazo_meses: 12, modalidad: 'mensual',
      tipo_interes: 'simple', capital_minimo: 100, capital_maximo: 1000000,
      tasa_referencia: 15, tasa_minima: 15, tasa_maxima: 15 })));
  estado.producto = await llamar('crear_producto_inversion', {
    p_codigo: 'F4-SINTETICO', p_nombre: 'Producto ficticio del banco F4',
    p_descripcion: 'Solo ensayo, sin dinero real', p_vigente_desde: '2025-01-01',
    p_vigente_hasta: '2028-12-31', p_condiciones: condiciones,
  }, gerente);
  checkpoint();
}
if (!estado.productoPublicado) {
  estado.productoPublicado = await llamar('publicar_version_producto_inversion', {
    p_version_id: estado.producto.version_id, p_expected_revision: 1,
  }, gerente);
  checkpoint();
}
estado.condiciones = JSON.parse(sql(`select jsonb_object_agg(categoria||'_'||moneda,id)
  from crm.producto_condiciones where version_id=${q(estado.producto.version_id)}`));
checkpoint();
// Configuración técnica publicada: los contratos vigentes usan el flujo libre
// y su propio snapshot. Se reproduce la semilla original del catálogo (20260807),
// no se conceden permisos ni se evita ningún trigger para hacer pasar la prueba.
sql(`insert into crm.productos_inversion(codigo,estado,revision,es_legacy,permite_altas_legacy,archivado_en)
  select 'HISTORICO-SIN-CATALOGO','archivado',1,true,true,now()
  where not exists(select 1 from crm.productos_inversion where codigo='HISTORICO-SIN-CATALOGO');`);
sql(`update public.perfiles set domicilio='CALLE FICTICIA F4 123, LIMA' where id=${q(f.usuarios.cliente.id)} and domicilio is null;`);
sql(`update public.perfiles set telefono='999450001' where id=${q(vendedor)} and telefono is null;`);

for (const [etiqueta, telefono] of [['avance', '999440001'], ['qorilazo', '999440002'], ['prodelco', '999440003']]) {
  if (!estado.leads[etiqueta]) {
    const id = randomUUID();
    sql(`insert into crm.leads(id,nombre_completo,telefono,monto_estimado,etapa,
      vendedor_id,creado_por,origen) values(${q(id)},${q(`PERSONA FICTICIA F4 ${etiqueta}`)},
      ${q(telefono)},1000,'propuesta_enviada',${q(vendedor)},${q(vendedor)},'otro');`);
    estado.leads[etiqueta] = id;
    checkpoint();
  }
}
if (!estado.conversionAvance) {
  estado.conversionAvance = await llamar('convertir_lead', {
    p_lead_id: estado.leads.avance, p_perfil_id: f.usuarios.cliente.id,
  });
  checkpoint();
}
for (const [caso, categoria, inicio] of [
  ['inicial', 'nuevo', '2026-08-01'], ['upgrade_mismo_mes', 'upgrade', '2026-08-15'],
  ['upgrade_elegible', 'upgrade', '2026-09-01'], ['upgrade_adicional', 'upgrade', '2026-09-02'],
]) {
  if (estado.contratos[caso]) continue;
  const datos = contratoPrueba(f.usuarios.cliente.id, vendedor, { categoria, inicio });
  datos.contrato.numero_contrato = `F4-BASE-${caso.toUpperCase().replaceAll('_', '-')}`;
  assert.equal(sql(`select count(*) from public.contratos where numero_contrato=${q(datos.contrato.numero_contrato)}`), '0',
    'Revisar un alta ya confirmada cuya respuesta pudo perderse');
  estado.contratos[caso] = await llamar('crear_contrato_con_cuenta_pdf_v2', {
    p_contrato: datos.contrato, p_cronograma: datos.cronograma, p_cuenta: datos.cuenta,
  });
  checkpoint();
}
for (const [cooperativa, dni] of [['qorilazo', '92000002'], ['prodelco', '92000003']]) {
  if (estado.cierres[cooperativa]) continue;
  estado.cierres[cooperativa] = await llamar('convertir_lead_externo', {
    p_lead_id: estado.leads[cooperativa], p_cooperativa: cooperativa,
    p_monto: 2000, p_moneda: 'PEN', p_documento_tipo: 'DNI', p_documento: dni,
    p_nombre: `PERSONA FICTICIA F4 ${cooperativa}`, p_numero_transaccion: `F4-BASE-${cooperativa}`,
    p_referencia: `REFERENCIA FICTICIA ${cooperativa}`, p_vence_en: '2027-09-07', p_nota: 'Ensayo aislado F4',
  });
  checkpoint();
}
estado.identidades = JSON.parse(sql(`select jsonb_object_agg(case
  when id=${q(estado.leads.avance)} then 'avance'
  when id=${q(estado.leads.qorilazo)} then 'qorilazo' else 'prodelco' end,inversionista_id)
  from crm.leads where id in (${Object.values(estado.leads).map(q).join(',')})`));
estado.completo = true;
checkpoint();
assert.equal(sql('select count(*) from public.contratos'), '4');
assert.equal(sql('select count(*) from crm.cierres_externos'), '2');
assert.equal(sql('select count(*) from crm.inversiones'), '0');
console.log('Antecedentes por RPC real: 3 leads convertidos, 4 contratos Avance con cuentas y cronogramas, 2 cierres cooperativos. F4 apagada.');
