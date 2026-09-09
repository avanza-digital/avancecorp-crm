import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {como,leer,literal as q,rpc,sql,http} from './banco-local.mjs';
test('G5: Avance → Qorilazo, fecha comercial/imputación y anulación sin borrar capital',async()=>{
  const e=leer('evidencia-flujo.json'), persona=sql(`select private.inversionista_canonica(${q(e.persona)})`);
  const token=await como('vendedor'),gerencia=await como('gerencia');
  const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r.data));return r.data;};
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral')");
    // Mes sintético anterior al período operativo del banco, sellado por su RPC.
    sql("insert into crm.conversion_pesos(vigente_desde,peso_referido,nota) select '2026-07-01',0.150,'Regla de la migración; ensayo F5' where not exists(select 1 from crm.conversion_pesos)");
    if(sql("select count(*) from crm.periodos_cerrados where periodo='2026-07-01'")==='0') ok(await rpc('cerrar_periodo',{p_periodo:'2026-07-01'},gerencia));
    const sello=()=>sql("select to_jsonb(p) from crm.periodos_cerrados p where periodo='2026-07-01'");
    const antes=sello(),id=randomUUID(),ruta=`${persona}/${id}/comprobante.png`;
    const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUN0AAAAASUVORK5CYII=','base64');
    const datos={inversionista_id:persona,empresa:'qorilazo',monto:450,moneda:'PEN',fecha_comercial:'2026-07-15',vence_en:'2027-07-15',
      numero_transaccion:`F5-FECHA-${id}`,referencia:'AJUSTE SINTETICO F5',evidencia:{ruta}};
    ok(await rpc('preparar_inversion_fn',{p_clave:id,p_datos:datos},token));
    ok(await http(`/storage/v1/object/f4-comprobantes/${ruta}`,{token,rawBody:png,headers:{'Content-Type':'image/png','x-upsert':'false'}}));
    const r=ok(await rpc('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0},token));
    const ficha=()=>rpc('inversionista_ficha_fn',{p_inversionista:persona},token).then(ok);
    const inicial=await ficha(),fuente=inicial.inversiones.find(x=>x.fuente_id===r.fuente.cierre_id);
    assert.equal(fuente.fecha_comercial,'2026-07-15');
    assert.equal(fuente.fecha_imputacion,sql("select (statement_timestamp() at time zone 'America/Lima')::date"));
    assert.notEqual(fuente.fecha_comercial,fuente.fecha_imputacion);
    const monto=d=>d.totales.find(x=>x.empresa==='qorilazo'&&x.moneda==='PEN').capital_registrado;
    ok(await rpc('anular_cierre_externo',{p_cierre_id:fuente.fuente_id,p_motivo:'Anulación comercial sintética para comprobar F5'},gerencia));
    const final=await ficha();assert.equal(final.inversiones.find(x=>x.fuente_id===fuente.fuente_id).estado,'anulado_comercialmente');
    assert.equal(monto(final),monto(inicial));assert.equal(sello(),antes);
    assert.equal(sql(`select estado from crm.inversiones where id=${q(r.inversion_id)}`),'anulada');
  } finally {for(const[nombre,activo]of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
