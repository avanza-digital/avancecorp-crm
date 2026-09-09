import test from 'node:test';
import assert from 'node:assert/strict';
import {randomInt,randomUUID} from 'node:crypto';
import {como,leer,literal as q,rpc,sql,guardar} from './banco-local.mjs';
import {contratoPrueba} from '../f4/operaciones-fixture.mjs';

test('G5: fusión por puerta vigente, contrato original y rechazo de otro origen',async()=>{
  const evidencia=leer('evidencia-flujo.json'), f=leer('fixtures.json');
  assert.ok(evidencia.persona && evidencia.contrato,'Ejecuta flujo.test.mjs antes de este caso');
  evidencia.persona=sql(`select private.inversionista_canonica(${q(evidencia.persona)})`);
  const gerente=await como('gerencia'), vendedor=await como('vendedor');
  const flags=JSON.parse(sql('select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags'));
  const ok=r=>{assert.equal(r.ok,true,`${r.status}: ${r.data?.message ?? ''}`);return r.data;};
  try {
    sql("update crm.multiempresa_flags set activo=true where nombre in ('resolver_en_puertas','inversiones_escritura','ficha_360_neutral')");
    const doc=`007${String(randomInt(1_000_000)).padStart(6,'0')}`;
    // Semilla de identidad histórica ficticia; la fusión y su revisión sí usan
    // las RPC públicas, sin UPDATE de canónica ni saltarse sus bloqueos.
    const canonica=sql(`begin; set local request.jwt.claim.sub=${q(f.usuarios.gerencia.id)};
      select private.inversionista_resolver('CE',${q(doc)},true,'ensayo_sintetico_f5'); commit;`);
    ok(await rpc('reasignar_responsable_relacion_fn',{p_inversionista:canonica,p_nuevo_responsable:f.usuarios.vendedor.id,
      p_motivo:'Asignación de identidad histórica sintética para el ensayo F5'},gerente));
    const preview=ok(await rpc('fusion_previsualizar_fn',{p_perdedora:evidencia.persona,p_canonica:canonica},gerente));
    assert.equal(preview.viable,true,JSON.stringify(preview.bloqueos));
    ok(await rpc('fusionar_inversionistas_fn',{p_perdedora:evidencia.persona,p_canonica:canonica,p_hash:preview.hash,
      p_motivo:'Fusión revisada de antecedentes ficticios para comprobar la cartera F5'},gerente));
    const ficha=ok(await rpc('inversionista_ficha_fn',{p_inversionista:evidencia.persona},vendedor));
    assert.equal(ficha.persona.inversionista_id,canonica); assert.equal(ficha.persona.perfil_id,evidencia.perfil);
    assert.equal(ficha.identidad_fusionada,true);
    assert.equal(ficha.inversiones.find(x=>x.fuente_id===evidencia.contrato).perfil_id,evidencia.perfil);
    const origen=JSON.parse(sql(`select jsonb_build_object('perfil',cliente_id,'tasa',tasa_anual,'capital',capital) from public.contratos where id=${q(evidencia.contrato)}`));
    const tasa=ok(await rpc('resolver_tasa_fn',{p_cliente_id:evidencia.perfil,p_categoria:'upgrade',p_contrato_origen_id:evidencia.contrato},vendedor));
    assert.equal(tasa.regla,'heredada_upgrade'); assert.equal(tasa.tasa_base,origen.tasa);
    const id=randomUUID(), datos={inversionista_id:canonica,empresa:'avance',...contratoPrueba(evidencia.perfil,f.usuarios.vendedor.id,{categoria:'upgrade',inicio:'2026-09-01',capital:500})};
    datos.contrato.contrato_origen_id=evidencia.contrato;
    datos.contrato.tasa_anual=origen.tasa;
    for(const cuota of datos.cronograma) if(cuota.tipo==='cuota') cuota.monto_programado=Math.round(500*origen.tasa/100/12*100)/100;
    ok(await rpc('preparar_inversion_fn',{p_clave:id,p_datos:datos},vendedor));
    const r=ok(await rpc('confirmar_inversion_revisada_fn',{p_solicitud:id,p_revision_datos_esperada:0},vendedor));
    const nuevo=JSON.parse(sql(`select jsonb_build_object('perfil',cliente_id,'tasa',tasa_anual,'origen',(select contrato_origen_id from crm.ledger_rentabilidad r where r.contrato_id=c.id limit 1)) from public.contratos c where id=${q(r.fuente.id)}`));
    assert.equal(nuevo.perfil,origen.perfil);assert.equal(nuevo.tasa,origen.tasa);assert.equal(nuevo.origen,evidencia.contrato);
    const ajeno=sql(`select c.id from public.contratos c where c.cliente_id<>${q(evidencia.perfil)} and c.estado='activo' limit 1`);
    assert.ok(ajeno);
    const falso=randomUUID(), d={...datos,contrato:{...datos.contrato,contrato_origen_id:ajeno}};
    const preparada=await rpc('preparar_inversion_fn',{p_clave:falso,p_datos:d},vendedor);
    // Preparar puede diferir la validación económica; confirmar nunca la acepta.
    if(preparada.ok) assert.equal((await rpc('confirmar_inversion_revisada_fn',{p_solicitud:falso,p_revision_datos_esperada:0},vendedor)).ok,false);
    else assert.equal(preparada.data.code,'P0409');
    assert.equal(sql(`select count(*) from crm.inversion_solicitudes where id=${q(falso)} and estado='confirmada'`),'0');
    guardar('evidencia-fusion.json',{canonica,origen:evidencia.contrato,upgrade:r.fuente.id,perfil:nuevo.perfil,estado:'PASS'});
  } finally {for(const[nombre,activo]of Object.entries(flags)) sql(`update crm.multiempresa_flags set activo=${activo} where nombre=${q(nombre)}`);}
});
