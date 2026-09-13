import test from 'node:test';
import assert from 'node:assert/strict';
import {activarSql,actores,como,errorEsperado,huellaEconomica,literal as q,
  miembrosSql,migracion,preparar,sql,sqlAsync} from './banco-local.mjs';

test('F8: banco aislado completo',async t=>{
  const datos=preparar();
  assert.equal(datos.despues,datos.antes,'La instalación alteró hechos económicos');
  const a=actores();
  assert.ok(a.gerencia&&a.supervisor&&a.supervisor_ajeno);
  assert.equal(a.vendedores.length,2);

  await t.test('instala apagado, vacío, privado, auditado y sin tocar F3-F7',()=>{
    const estado=JSON.parse(sql(`select jsonb_build_object(
      'control',(select jsonb_build_object('activo',activo,'revision',revision)
        from crm.piloto_f8_control where singleton),
      'miembros',(select count(*) from crm.piloto_f8_miembros),
      'f3',(select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'),
      'globales',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags
        where nombre in ('inversiones_escritura','ficha_360_neutral',
          'postventa_neutral','metricas_multiempresa_sombra')),
      'rls',(select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='crm' and c.relname in ('piloto_f8_control','piloto_f8_miembros')),
      'data_api',has_table_privilege('authenticated','crm.piloto_f8_control','SELECT')
        or has_table_privilege('authenticated','crm.piloto_f8_miembros','SELECT')
        or has_table_privilege('service_role','crm.piloto_f8_control','SELECT')
        or has_table_privilege('service_role','crm.piloto_f8_miembros','SELECT'))`));
    assert.deepEqual(estado.control,{activo:false,revision:0});
    assert.equal(estado.miembros,0);assert.equal(estado.f3,true);
    assert.ok(Object.values(estado.globales).every(x=>x===false));
    assert.equal(estado.rls,true);assert.equal(estado.data_api,false);
    sql(`begin;set local role authenticated;
      ${errorEsperado('42501','perform * from crm.piloto_f8_control')}
      ${errorEsperado('42501','perform private.piloto_f8_actor_activo(auth.uid())')}
      rollback;`);
    assert.throws(()=>sql(migracion),/F8 ya existe/);
  });

  await t.test('rechaza equipo incompleto y perfiles inactivos',()=>{
    sql(`begin;
      insert into crm.piloto_f8_miembros(perfil_id,rol_esperado,vence_en,motivo)
      values (${q(a.gerencia)},'gerencia',now()+interval '2 days','Piloto económico F8'),
        (${q(a.supervisor)},'supervisor',now()+interval '2 days','Piloto económico F8'),
        (${q(a.vendedores[0])},'vendedor',now()+interval '2 days','Piloto económico F8');
      ${errorEsperado('P0409',activarSql(a.gerencia))}
      rollback;`);
    sql(`begin;${miembrosSql(a)}
      insert into crm.piloto_f8_miembros
        (perfil_id,rol_esperado,habilitado_desde,vence_en,motivo,actualizado_por)
      values (${q(a.supervisor_ajeno)},'supervisor',now()+interval '1 day',
        now()+interval '2 days','Quinto integrante futuro F8',${q(a.gerencia)});
      ${errorEsperado('P0409',activarSql(a.gerencia))}
      rollback;`);
    sql(`begin;${miembrosSql(a)}
      update crm.piloto_f8_miembros set vence_en=now()+interval '3 days'
      where perfil_id=${q(a.vendedores[1])};
      ${errorEsperado('P0409',activarSql(a.gerencia))}
      rollback;`);
    sql(`begin;${miembrosSql(a)}
      update public.perfiles set activo=false where id=${q(a.vendedores[1])};
      ${errorEsperado('P0409',activarSql(a.gerencia))}
      rollback;`);
  });

  await t.test('solo el equipo nominal obtiene F4, F5 y F6',()=>{
    for(const actor of [a.gerencia,a.supervisor,...a.vendedores]) {
      const estado=JSON.parse(sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
        ${como(actor,`select jsonb_build_object(
          'f5',crm.cartera_inversionistas_estado_fn(),
          'f6',crm.postventa_estado_fn())`)};rollback;`));
      assert.equal(estado.f5.habilitada,true);
      assert.equal(estado.f5.escritura_habilitada,true);
      assert.equal(estado.f6.habilitada,true);
    }
    const ajeno=JSON.parse(sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      ${como(a.supervisor_ajeno,`select jsonb_build_object(
        'f5',crm.cartera_inversionistas_estado_fn(),
        'f6',crm.postventa_estado_fn())`)};rollback;`));
    assert.equal(ajeno.f5.habilitada,false);
    assert.equal(ajeno.f5.escritura_habilitada,false);
    assert.equal(ajeno.f6.habilitada,false);
  });

  await t.test('revalida la membresía CRM y permite revocar un participante',()=>{
    sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      update public.perfiles set activo=false where id=${q(a.vendedores[0])};
      ${como(a.vendedores[0],`${errorEsperado('42501',
        'perform crm.cartera_inversionistas_estado_fn()')}
        ${errorEsperado('42501','perform crm.postventa_estado_fn()')}`)}rollback;`);
    const equipoRoto=JSON.parse(sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      update public.perfiles set activo=false where id=${q(a.vendedores[0])};
      ${como(a.gerencia,`select jsonb_build_object(
        'f5',crm.cartera_inversionistas_estado_fn(),
        'f6',crm.postventa_estado_fn())`)}rollback;`));
    assert.equal(equipoRoto.f5.habilitada,false);
    assert.equal(equipoRoto.f6.habilitada,false);

    const revocado=sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      update crm.piloto_f8_miembros set activo=false where perfil_id=${q(a.vendedores[0])};
      set local request.jwt.claim.sub=${q(a.vendedores[0])};
      select (select activo::text from crm.piloto_f8_control where singleton)||','||
        private.piloto_f8_actor_activo(auth.uid())::text;
      ${errorEsperado('55000',`delete from crm.piloto_f8_miembros
        where perfil_id=${q(a.vendedores[1])}`)}
      rollback;`);
    assert.equal(revocado,'false,false');
  });

  await t.test('F8 y las banderas globales no pueden coexistir',()=>{
    sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      ${errorEsperado('P0409',`update crm.multiempresa_flags set activo=true
        where nombre='inversiones_escritura'`)}rollback;`);
    sql(`begin;${miembrosSql(a)}
      update crm.multiempresa_flags set activo=true where nombre='ficha_360_neutral';
      ${errorEsperado('P0409',activarSql(a.gerencia))}rollback;`);
    sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      delete from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra';
      ${errorEsperado('P0409',`insert into crm.multiempresa_flags(nombre,activo)
        values ('metricas_multiempresa_sombra',true)`)}rollback;`);
    sql(`begin isolation level repeatable read;${miembrosSql(a)}
      ${errorEsperado('0A000',activarSql(a.gerencia))}rollback;`);
  });

  await t.test('la ventana total no puede ampliarse mientras F8 está activo',()=>{
    sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      ${errorEsperado('P0409',`update crm.piloto_f8_control
        set vence_en=vence_en+interval '1 day'`)}rollback;`);
    sql(`begin;${miembrosSql(a)}
      ${errorEsperado('22023',`update crm.piloto_f8_control set activo=true,
        inicia_en=now()-interval '31 days',vence_en=now()+interval '1 day',
        motivo='Ventana demasiado larga F8',actualizado_por=${q(a.gerencia)}`)}rollback;`);
  });

  await t.test('sincroniza el espejo para todos pero limita la operación nueva',()=>{
    const resultado=sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      set local request.jwt.claim.sub=${q(a.supervisor_ajeno)};
      select private.inversiones_escritura_bajo_candado();
      ${errorEsperado('42501',"perform private.inversion_persona_autorizada(null::uuid)")}
      rollback;`);
    assert.equal(resultado,'t');

    const definicion=sql("select pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)");
    const reemplazo=definicion.replace(/AS \$function\$[\s\S]*\$function\$$/,
      'AS $function$ select * from pg_temp.f8_fuentes_prueba $function$');
    assert.notEqual(reemplazo,definicion);
    sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}
      create temporary table f8_fuentes_prueba on commit drop
        as select * from private.cartera_f5_fuentes();
      update f8_fuentes_prueba set inversionista_id=null,identidad_coherente=false
      where fuente_id=(select fuente_id from f8_fuentes_prueba order by fuente_id limit 1);
      ${reemplazo};
      set local request.jwt.claim.sub=${q(a.vendedores[0])};
      ${errorEsperado('P0409',"perform private.inversion_persona_autorizada(null::uuid)")}
      rollback;`);
  });

  await t.test('cinco carreras dejan un solo modo activo',async()=>{
    sql(`${miembrosSql(a)}`);
    for(let i=0;i<5;i++) {
      sql(`update crm.piloto_f8_control set activo=false,
          inicia_en=now()-interval '1 minute',vence_en=now()+interval '2 days',
          motivo='Reinicio de carrera F8';
        update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura';`);
      const consultaPiloto=`begin;set local lock_timeout='3s';${activarSql(a.gerencia)}
        select pg_sleep(0.08);commit;`;
      const consultaGlobal=`begin;set local lock_timeout='3s';
        update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';
        select pg_sleep(0.08);commit;`;
      const resultados=await Promise.all([sqlAsync(consultaPiloto),sqlAsync(consultaGlobal)]);
      assert.equal(resultados.filter(x=>x.status===0).length,1,JSON.stringify(resultados));
      assert.ok(resultados.find(x=>x.status!==0)?.stderr.match(/F8|piloto|rollout/));
      const estado=sql(`select (select activo::int from crm.piloto_f8_control where singleton)::text||','||
        (select activo::int from crm.multiempresa_flags where nombre='inversiones_escritura')::text`);
      assert.ok(estado==='1,0'||estado==='0,1',estado);
    }
    sql(`update crm.piloto_f8_control set activo=false,motivo='Cierre de carreras F8';
      update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura';`);
  });

  await t.test('el vencimiento corta el acceso sin intervención manual',async()=>{
    sql(`update crm.piloto_f8_miembros set activo=true,
        habilitado_desde=now()-interval '1 minute',vence_en=now()+interval '350 milliseconds',
        motivo='Prueba de vencimiento F8';
      update crm.piloto_f8_control set activo=true,
        inicia_en=now()-interval '1 minute',
        vence_en=(select min(vence_en) from crm.piloto_f8_miembros where activo),
        motivo='Prueba de vencimiento F8';`);
    await new Promise(resolve=>setTimeout(resolve,500));
    assert.equal(sql(`set request.jwt.claim.sub=${q(a.vendedores[0])};
      select private.piloto_f8_actor_activo(auth.uid())`),'f');
    const estado=JSON.parse(sql(`begin;${como(a.vendedores[0],
      'select crm.cartera_inversionistas_estado_fn()')}rollback;`));
    assert.equal(estado.habilitada,false);
    sql(`update crm.piloto_f8_control set activo=false,motivo='Cierre de vencimiento F8';`);
  });

  await t.test('el apagado corta capacidades y conserva toda la historia',()=>{
    const antes=huellaEconomica();
    sql(`update crm.piloto_f8_miembros set activo=true,
        habilitado_desde=now()-interval '1 minute',vence_en=now()+interval '2 days',
        motivo='Prueba de reversa F8';
      ${activarSql(a.gerencia)} update crm.piloto_f8_control set activo=false,
      motivo='Reversa operativa controlada F8';`);
    for(const actor of [a.gerencia,a.supervisor,...a.vendedores]) {
      assert.equal(sql(`set request.jwt.claim.sub=${q(actor)};
        select private.inversiones_escritura_bajo_candado()`),'f');
    }
    assert.equal(huellaEconomica(),antes);
    const auditados=Number(sql(`select count(*) from public.audit_log
      where tabla in ('crm.piloto_f8_control','crm.piloto_f8_miembros')`));
    assert.ok(auditados>0);
  });
});
