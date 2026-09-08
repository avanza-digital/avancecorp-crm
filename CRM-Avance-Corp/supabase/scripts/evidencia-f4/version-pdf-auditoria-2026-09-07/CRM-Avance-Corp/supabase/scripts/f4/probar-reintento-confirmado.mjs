import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { sql, literal as q, leer, guardar, sesion, rpc } from './banco-local.mjs';

const caracterizar = process.argv.includes('--caracterizar');
const f = leer('fixtures.json');
const base = leer('operaciones-base.json');
const ejecucion = randomUUID();
const pruebas = [];
const t = await sesion(f.usuarios.vendedor, f.password);
const gerente = await sesion(f.usuarios.gerencia, f.password);
const ajeno = await sesion(f.usuarios.ajeno, f.password);
const flag = sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'") === 't';
const ok = (r, nombre) => {
  assert.equal(r.ok, true, `${nombre}: ${JSON.stringify(r.data)}`);
  return r.data;
};
const rechaza = (r, codigo) => {
  assert.equal(r.ok, false);
  assert.equal(r.data.code, codigo, JSON.stringify(r.data));
};
const historia = s => sql(`select jsonb_build_object('solicitud',to_jsonb(s),'inversion',to_jsonb(i),
  'fuente',coalesce((select to_jsonb(c) from public.contratos c where c.id=i.contrato_id),
    (select to_jsonb(c) from crm.cierres_externos c where c.id=i.cierre_externo_id)),
  'pdfs',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from private.contrato_pdfs p where p.contrato_id=i.contrato_id),
  'sagas',(select coalesce(jsonb_agg(to_jsonb(a) order by a.clave),'[]') from crm.multiempresa_idempotencia a))
  from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id where s.id=${q(s.id)}`);
sql("update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura'");
try {
  for (const empresa of ['avance', 'qorilazo']) {
    const persona = base.identidades.avance;
    assert.equal(sql(`select no_contactar from crm.inversionistas where id=${q(persona)}`), 'f');
    const s = JSON.parse(sql(`select to_jsonb(s) from crm.inversion_solicitudes s
      join crm.empresas e on e.id=s.empresa_id
      where s.inversionista_id=${q(persona)} and s.estado='confirmada' and e.clave=${q(empresa)}
      order by s.creado_en desc limit 1`));
    const pendiente = randomUUID();
    const datos = structuredClone(s.datos);
    if (empresa !== 'avance') {
      datos.numero_transaccion = `F4-${pendiente}`;
      datos.evidencia.ruta = `${persona}/${pendiente}/comprobante.png`;
    }
    ok(await rpc('preparar_inversion_fn', { p_clave: pendiente, p_datos: datos }, t), 'Preparar antes del veto');
    guardar(`reintento-confirmado-${ejecucion}-${empresa}.json`, { s, pendiente, datos });
    const antes = historia(s);
    let marcado = false;
    try {
      ok(await rpc('marcar_no_contactar', { p_lead_id: base.leads.avance,
        p_motivo: 'Ensayo local: veto posterior a una inversión confirmada' }, gerente), 'Marcar veto por RPC');
      marcado = true;
      for (const actor of [t, gerente]) {
        const repetir = await rpc('confirmar_inversion_fn', { p_solicitud: s.id }, actor);
        const preparar = await rpc('preparar_inversion_fn', { p_clave: s.id, p_datos: s.datos }, actor);
        if (caracterizar) {
          rechaza(repetir, 'P0429');
          rechaza(preparar, 'P0429');
        } else {
          const resultado = ok(repetir, 'Recuperar confirmada después del veto');
          assert.equal(resultado.reintento, true);
          assert.equal(resultado.inversion_id, s.inversion_id);
          assert.equal(resultado.fuente.id, s.resultado.fuente.id);
          const preparada = ok(preparar, 'Releer preparación confirmada');
          assert.equal(preparada.estado, 'confirmada');
          assert.equal(preparada.inversion_id, s.inversion_id);
        }
        if (empresa === 'avance') {
          const acceso = await rpc('acceso_inversion_fn', { p_solicitud: s.id, p_paso: 'reclamar' }, actor);
          if (caracterizar) rechaza(acceso, 'P0429');
          else {
            assert.equal(ok(acceso, 'Releer acceso de inversión confirmada').estado, 'enlazado');
            assert.equal(acceso.data.reanudar, true);
            assert.equal(acceso.data.perfil_id, f.usuarios.cliente.id);
          }
        }
      }
      rechaza(await rpc('confirmar_inversion_fn', { p_solicitud: pendiente }, t), 'P0429');
      rechaza(await rpc('preparar_inversion_fn', { p_clave: pendiente, p_datos: datos }, t), 'P0429');
      const nueva = randomUUID();
      rechaza(await rpc('preparar_inversion_fn', { p_clave: nueva, p_datos: datos }, t), 'P0429');
      assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(nueva)}`), '0');
      assert.equal(sql(`select estado from crm.inversion_solicitudes where id=${q(pendiente)}`), 'preparada');
      const distintos = structuredClone(s.datos);
      if (empresa === 'avance') distintos.contrato.capital = Number(distintos.contrato.capital) + 1;
      else distintos.monto = Number(distintos.monto) + 1;
      rechaza(await rpc('preparar_inversion_fn', { p_clave: s.id, p_datos: distintos }, t), caracterizar ? 'P0429' : 'P0409');
      rechaza(await rpc('confirmar_inversion_fn', { p_solicitud: s.id }, ajeno), '42501');
      rechaza(await rpc('preparar_inversion_fn', { p_clave: s.id, p_datos: s.datos }, ajeno), '42501');
      if (empresa === 'avance') rechaza(await rpc('acceso_inversion_fn', { p_solicitud: s.id, p_paso: 'reclamar' }, ajeno), '42501');
      assert.equal(historia(s), antes, 'Una relectura no altera fuente, solicitud, inversión, PDF ni saga Auth');
      pruebas.push({ empresa, vetoPorRpcVigente: true, actores: ['vendedor', 'gerencia'],
        relecturaConfirmada: caracterizar ? 'defecto P0429 reproducido' : 'mismo resultado',
        nuevasYPreparadasBloqueadas: true, equipoAjenoRechazado: true,
        historiaPdfYAuthIntactos: true, conforme: !caracterizar });
      console.log(`Reintento confirmado F4 ${empresa}: ${caracterizar ? 'defecto reproducido' : 'recuperación y bloqueos conformes'}.`);
    } finally {
      if (marcado) ok(await rpc('levantar_no_contactar', { p_lead_id: base.leads.avance,
        p_motivo: 'Fin del ensayo local de recuperación de inversión confirmada' }, gerente), 'Restituir veto');
    }
  }
  const prefijo = caracterizar ? 'reintento-confirmado-defecto' : 'reintento-confirmado';
  writeFileSync(new URL(`../evidencia-f4/${prefijo}-${ejecucion}.json`, import.meta.url), JSON.stringify({
    entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
    limite: 'Veto posterior a la confirmación en Avance y cooperativa. No sustituye los ensayos pendientes de cambio de rol, multirrol o baja del responsable. Quedan dos solicitudes ficticias preparadas intencionalmente.',
  }, null, 2) + '\n', { flag: 'wx' });
} finally {
  sql(`update crm.multiempresa_flags set activo=${flag} where nombre='inversiones_escritura'`);
}
