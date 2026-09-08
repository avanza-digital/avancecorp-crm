// Integración HTTP/RLS real con Auth local; todas las escrituras son sintéticas.
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { como, leer, literal, rpc, sql } from './banco-local.mjs';

test('F5: lectura canónica, paridad y permisos actuales en HTTP', async t => {
  const fixture = leer('fixtures.json');
  const usuarios = fixture.usuarios;
  const tokens = Object.fromEntries(await Promise.all(Object.keys(usuarios).map(async r => [r,await como(r)])));
  const flags = JSON.parse(sql("select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags"));
  const bandera = (nombre, valor) => sql(`update crm.multiempresa_flags set activo=${valor} where nombre=${literal(nombre)};`);
  const listar = (rol, payload={}) => rpc('cartera_inversionistas_fn',payload,tokens[rol]);
  const ficha = (rol,id) => rpc('inversionista_ficha_fn',{p_inversionista:id},tokens[rol]);
  let global;
  try {
    bandera('ficha_360_neutral',false);
    await t.test('OFF conserva el recorrido publicado y bloquea la RPC neutral',async () => {
      const estado=await rpc('cartera_inversionistas_estado_fn',{},tokens.gerencia);
      assert.equal(estado.data.habilitada,false);
      assert.equal((await listar('gerencia')).data.code,'P0409');
    });
    bandera('ficha_360_neutral',true);
    await t.test('anon, cliente y ámbito ajeno no enumeran personas ni cuentan filas',async () => {
      assert.equal((await rpc('cartera_inversionistas_fn',{},undefined)).ok,false);
      assert.equal((await listar('cliente')).data.code,'42501');
      for(const rol of ['ajeno','supervisor_ajeno']) {
        const r=await listar(rol);
        assert.equal(r.ok,true);
        assert.deepEqual(r.data.filas,[]);
        assert.equal(r.data.total,0);
        assert.deepEqual(r.data.totales,[]);
      }
    });
    await t.test('Gerencia, supervisor y vendedor reciben una sola fila por persona',async () => {
      global=await listar('gerencia');
      assert.equal(global.ok,true,JSON.stringify(global.data));
      assert.ok(global.data.total>=3);
      assert.equal(new Set(global.data.filas.map(x=>x.inversionista_id)).size,global.data.total);
      for(const rol of ['vendedor','supervisor']) {
        const r=await listar(rol);
        assert.equal(r.ok,true,JSON.stringify(r.data));
        assert.deepEqual(r.data.filas.map(x=>x.inversionista_id),global.data.filas.map(x=>x.inversionista_id));
      }
    });
    await t.test('la falta de crm.inversiones no oculta contratos ni duplica capital',async () => {
      const fuente=JSON.parse(sql(`select jsonb_build_object(
        'contratos',(select count(*) from public.contratos),
        'enlaces',(select count(*) from crm.inversiones where contrato_id is not null),
        'capital',(select coalesce(sum(capital),0) from public.contratos where not es_demo and estado='activo'))`));
      assert.ok(fuente.contratos>fuente.enlaces,'El banco debe contener historia aún sin enlace de inversión');
      const avance=global.data.totales.find(x=>x.empresa==='avance' && x.moneda==='PEN');
      assert.equal(avance.cantidad,fuente.contratos);
      assert.equal(avance.capital_activo,fuente.capital);
      for(const empresa of ['qorilazo','prodelco']) {
        const monto=Number(sql(`select coalesce(sum(monto),0) from crm.cierres_externos where cooperativa=${literal(empresa)} and id<>'a112aead-184a-4979-9041-943978fadae4'`));
        assert.equal(global.data.totales.find(x=>x.empresa===empresa).capital_registrado,monto);
      }
    });
    await t.test('los filtros y la página comparten total; % y _ son texto literal',async () => {
      for(const empresa of ['avance','qorilazo','prodelco']) {
        const r=await listar('gerencia',{p_empresa:empresa,p_tamano:10});
        assert.ok(r.data.filas.every(x=>x.empresas.includes(empresa)));
        assert.ok(r.data.totales.every(x=>x.empresa===empresa));
        const siguiente=await listar('gerencia',{p_empresa:empresa,p_tamano:10,p_pagina:2});
        assert.equal(siguiente.data.total,r.data.total);
        assert.deepEqual(siguiente.data.filas,[]);
      }
      for(const p_texto of ['%','_','persona inexistente']) assert.equal((await listar('gerencia',{p_texto})).data.total,0);
      for(const p_texto of [global.data.filas[0].documento,global.data.filas[0].nombre]) {
        assert.ok((await listar('gerencia',{p_texto})).data.total>0);
        assert.equal((await listar('ajeno',{p_texto})).data.total,0);
      }
      for(const payload of [{p_tamano:1000},{p_pagina:0},{p_empresa:'otra'},{p_texto:'a'.repeat(121)},
        {p_sin_responsable:true,p_responsable:usuarios.vendedor.id}]) {
        assert.equal((await listar('gerencia',payload)).data.code,'22023');
      }
    });
    await t.test('la ficha inexistente y la ajena son indistinguibles',async () => {
      const id=global.data.filas[0].inversionista_id;
      const ajena=await ficha('ajeno',id);
      const inexistente=await ficha('ajeno',randomUUID());
      assert.deepEqual(ajena,inexistente);
      assert.equal(ajena.data,null);
    });
    await t.test('Directorio conserva lectura Avance, sin filas cooperativas ni banca',async () => {
      const r=await listar('directorio');
      assert.equal(r.ok,true,JSON.stringify(r.data));
      assert.ok(r.data.filas.length>0);
      assert.ok(r.data.filas.every(x=>x.empresas.every(e=>e==='avance')));
      assert.equal((await listar('directorio',{p_empresa:'qorilazo'})).data.total,0);
      for(const p of r.data.filas) {
        const d=await ficha('directorio',p.inversionista_id);
        assert.equal(d.data.capacidades.nueva_inversion,false);
        assert.equal(d.data.capacidades.contactar,false);
        assert.deepEqual(d.data.capacidades.cuentas_perfil_ids,[]);
        assert.ok(d.data.inversiones.every(i=>i.empresa==='avance'&&i.documentos.length===0&&i.cotitulares.length===0));
        assert.equal((await rpc('inversionista_cuentas_fn',{p_inversionista:p.inversionista_id,
          p_perfil:d.data.persona.perfil_id,p_moneda:'PEN'},tokens.directorio)).data.code,'42501');
      }
    });
    await t.test('cooperativa sin Portal abre identidad real y ninguna cuenta bancaria',async () => {
      const p=global.data.filas.find(x=>x.empresas.includes('qorilazo'));
      const d=await ficha('vendedor',p.inversionista_id);
      assert.equal(d.ok,true,JSON.stringify(d.data));
      assert.equal(d.data.persona.inversionista_id,p.inversionista_id);
      assert.equal(d.data.persona.perfil_id,null);
      assert.deepEqual(d.data.capacidades.cuentas_perfil_ids,[]);
      assert.equal(d.data.inversiones_total,1);
    });
    await t.test('revocar la relación retira lista, búsqueda, ficha y banca al anterior responsable',async () => {
      const p=global.data.filas.find(x=>x.empresas.includes('avance'));
      const mover=responsable=>rpc('reasignar_responsable_relacion_fn',{
        p_inversionista:p.inversionista_id,p_nuevo_responsable:responsable,
        p_motivo:'Ensayo sintético de cambio de responsable F5'},tokens.gerencia);
      const cambio=await mover(usuarios.ajeno.id);
      assert.equal(cambio.ok,true,JSON.stringify(cambio.data));
      try {
        assert.equal((await ficha('vendedor',p.inversionista_id)).data,null);
        assert.equal((await listar('vendedor',{p_texto:p.documento})).data.total,0);
        assert.equal((await ficha('supervisor',p.inversionista_id)).data,null);
        assert.equal((await ficha('ajeno',p.inversionista_id)).data.persona.responsable_id,usuarios.ajeno.id);
        assert.equal((await rpc('inversionista_cuentas_fn',{p_inversionista:p.inversionista_id,
          p_perfil:usuarios.cliente.id,p_moneda:'PEN'},tokens.vendedor)).data.code,'42501');
      } finally {assert.equal((await mover(usuarios.vendedor.id)).ok,true);}
    });
    await t.test('baja del actor invalida tokens todavía vigentes',async () => {
      // La baja vigente exige resolver dependencias; el actor ajeno está libre
      // después de devolver la relación en el caso anterior. No omitir el guard.
      sql(`update crm.equipo set activo=false where perfil_id=${literal(usuarios.ajeno.id)};`);
      try {assert.equal((await listar('ajeno')).data.code,'42501');}
      finally {sql(`update crm.equipo set activo=true where perfil_id=${literal(usuarios.ajeno.id)};`);}
    });
    await t.test('tablas auxiliares cerradas y auditoría sin documentos/contactos',() => {
      assert.equal(sql("select has_table_privilege('authenticated','crm.cartera_lecturas','SELECT')"),'f');
      assert.equal(sql("select has_function_privilege('authenticated','private.cartera_f5_fuentes()','EXECUTE')"),'f');
      assert.equal(sql("select has_function_privilege('service_role','crm.inversionista_ficha_fn(uuid,integer,integer)','EXECUTE')"),'f');
      const audit=JSON.parse(sql("select jsonb_agg(data_despues) from public.audit_log where tabla='crm.cartera_lecturas'"));
      assert.ok(audit.length>0);
      assert.ok(audit.every(x=>Object.keys(x).sort().join(',')==='actor_id,creado_en,id,inversionista_id,tipo'));
      assert.ok(audit.every(x=>!JSON.stringify(x).includes(global.data.filas[0].nombre)));
    });
  } finally {
    for(const [nombre,activo] of Object.entries(flags)) bandera(nombre,activo);
  }
});
