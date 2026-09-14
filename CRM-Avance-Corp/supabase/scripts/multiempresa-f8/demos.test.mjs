import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {activarSql,actores,como,errorEsperado,huellaEconomica,literal as q,
  miembrosSql,migracionDemo,preparar,reversaDemo,sql} from './banco-local.mjs';

const json=s=>JSON.parse(sql(s));
const cierreDemo='a112aead-184a-4979-9041-943978fadae4';

// Solo fixtures sintéticos en el destino cerrado del banco F8. Reproduce las
// 598 fuentes del corte: 593 reales enlazadas, 5 demos, 4 demos sin identidad.
function fixture(a) {
  const perfiles=[randomUUID(),randomUUID()];
  const contratos=[randomUUID(),randomUUID(),randomUUID()];
  const lead=randomUUID(),demoMixto=randomUUID();
  const base=json(`select to_jsonb(f) from private.cartera_f5_fuentes() f
    where empresa='avance' and not es_demo and identidad_coherente
    and exists(select 1 from public.contratos c where c.id=f.fuente_id and categoria='nuevo')
    order by fuente_id limit 1`);
  const n=Number(sql('select count(*) from private.cartera_f5_fuentes()'));
  const partes=[`begin;set local crm.op_privilegiada='on';set local crm.marcando_demo='on';
    update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';`];
  for(let k=0;k<2;k++) {
    const p={id:perfiles[k],nombre_completo:`DEMO F8 AISLADO ${k}`,dni:k?'1234':null,
      correo:`${perfiles[k]}@fixtures.invalid`,telefono:`98803000${k}`,activo:true,
      creado_por:a.vendedores[0],asesor_perfil_id:a.vendedores[0]};
    partes.push(`insert into auth.users(id,aud,role,email)
      values(${q(p.id)},'authenticated','authenticated',${q(p.correo)});
      insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,
        to_jsonb(p)||${q(JSON.stringify(p))}::jsonb)).*
        from public.perfiles p where p.rol='cliente' order by p.id limit 1;`);
  }
  for(let k=0;k<4;k++) {
    const c={id:k<3?contratos[k]:demoMixto,cliente_id:k<3?perfiles[k===0?0:1]:base.perfil_id,
      numero_contrato:`F8-DEMO-${k}`,es_demo:true,categoria:'nuevo',producto_condicion_id:null,
      creado_por:a.vendedores[0],analista_cierre_id:a.vendedores[0],renovado_a_id:null,
      fecha_cierre_comercial:null,fuente_cierre_comercial:'registro'};
    partes.push(`insert into public.contratos select (jsonb_populate_record(null::public.contratos,
      to_jsonb(c)||${q(JSON.stringify(c))}::jsonb)).* from public.contratos c
      where c.id=${q(base.fuente_id)};`);
  }
  const l={id:lead,nombre_completo:'CIERRE DEMO F8 AISLADO',dni:'99883001',
    telefono:'988030002',correo:`${lead}@fixtures.invalid`,activo:true,
    perfil_id:null,contrato_id:null,inversionista_id:null,etapa:'convertido',
    no_contactar:false,vendedor_id:a.vendedores[0],creado_por:a.vendedores[0]};
  const ce={id:cierreDemo,lead_id:lead,cooperativa:'qorilazo',monto:5000,
    documento_tipo:'DNI',documento:'99883001',nombre_completo:l.nombre_completo,
    numero_transaccion:'F8-DEMO-TX',referencia_externa:'F8-DEMO-CE',inversionista_id:null,
    vendedor_id:a.vendedores[0],creado_por:a.vendedores[0],anulado_en:null,
    anulado_por:null,motivo_anulacion:null,es_cierre_inicial:true,
    fecha_comercial:null,fecha_imputacion:null,comprobante_objeto_id:null};
  partes.push(`insert into crm.leads select (jsonb_populate_record(null::crm.leads,
    to_jsonb(l)||${q(JSON.stringify(l))}::jsonb)).* from crm.leads l
    where etapa='convertido' order by id limit 1;
    insert into crm.cierres_externos select (jsonb_populate_record(null::crm.cierres_externos,
    to_jsonb(c)||${q(JSON.stringify(ce))}::jsonb)).* from crm.cierres_externos c order by id limit 1;
    insert into public.contratos select (jsonb_populate_record(null::public.contratos,
      to_jsonb(c)||jsonb_build_object('id',gen_random_uuid(),'numero_contrato','F8-REAL-'||g.n,
        'es_demo',false,'categoria','nuevo','producto_condicion_id',null,'renovado_a_id',null,
        'fecha_cierre_comercial',null,'fuente_cierre_comercial','registro'))).*
    from public.contratos c cross join generate_series(1,${598-n-5}) g(n)
    where c.id=${q(base.fuente_id)};
    update crm.multiempresa_flags set activo=true where nombre='resolver_en_puertas';commit;`);
  sql(partes.join('\n'));
  return {perfiles,contratos,lead,demoMixto,base};
}

const censo=()=>json(`select jsonb_build_object('fuentes',count(*),
  'reales',count(*) filter(where es_demo is not true),
  'demo',count(*) filter(where es_demo),
  'huecos_reales',count(*) filter(where es_demo is not true and
    (not coalesce(identidad_coherente,false) or inversionista_id is null)),
  'huecos_demo',count(*) filter(where es_demo and
    (not coalesce(identidad_coherente,false) or inversionista_id is null)))
  from private.cartera_f5_fuentes()`);

function contratoApi() {
  return sql(`select md5(jsonb_agg(jsonb_build_array(n.nspname,p.proname,
    pg_get_function_arguments(p.oid),pg_get_function_result(p.oid),p.proacl::text)
    order by p.oid)::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','crm')`);
}

// Sustituto transaccional para probar huecos/NULL sin alterar fuentes ni
// desactivar sus triggers. El resto de los RPC ejecuta su SQL real.
function mutanteFuentes(cambio) {
  const d=sql("select pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure)");
  const s=d.replace(/AS \$function\$[\s\S]*\$function\$$/,
    'AS $function$ select * from pg_temp.f8_fuentes_prueba $function$');
  assert.notEqual(s,d);
  return `create temporary table f8_fuentes_prueba on commit drop
    as select * from private.cartera_f5_fuentes();${cambio};${s};`;
}

function personaSinFuentes(a,id,p) {
  return `insert into auth.users(id,aud,role,email)
    values(${q(p)},'authenticated','authenticated',${q(`${p}@fixtures.invalid`)});
    insert into public.perfiles select (jsonb_populate_record(null::public.perfiles,to_jsonb(x)||
      jsonb_build_object('id',${q(p)},'nombre_completo','CLIENTE SIN FUENTES F8','dni',null,
        'correo',${q(`${p}@fixtures.invalid`)}))).*
      from public.perfiles x where x.rol='cliente' order by x.id limit 1;
    insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
      values(${q(id)},${q(p)},${q(a.vendedores[0])});`;
}

test('F8: exclusión demo y cobertura real',async t=>{
  preparar({demos:false});
  const a=actores(),f=fixture(a);
  assert.deepEqual(censo(),{fuentes:598,reales:593,demo:5,huecos_reales:0,huecos_demo:4});
  const huella=huellaEconomica(),api=contratoApi();
  const cruda=sql("select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure))");
  const antesFuentes=sql('select md5(jsonb_agg(f order by empresa,fuente_id)::text) from private.cartera_f5_fuentes() f');
  const antesMetricas=sql('select md5(jsonb_agg(f order by fuente_id)::text) from private.metricas_f7_fuentes() f');

  await t.test('reproduce el bloqueo anterior por cuatro demos',()=>{
    sql(`begin;${miembrosSql(a)}${errorEsperado('P0409',activarSql(a.gerencia))}rollback;`);
    // Antes de la corrección el helper de postventa sí acepta ese cierre demo.
    assert.equal(sql(`begin;set local crm.op_privilegiada='on';
      update crm.cierres_externos set inversionista_id=${q(f.base.inversionista_id)}
        where id=${q(cierreDemo)};
      select (private.postventa_fuente(${q(cierreDemo)},${q(f.base.inversionista_id)},'qorilazo')).id;
      rollback;`),cierreDemo);
  });
  sql(migracionDemo);
  const piloto=(consulta,actor=a.gerencia,previo='')=>
    `begin;${previo}${miembrosSql(a)}${activarSql(a.gerencia)}${como(actor,consulta)}rollback;`;

  await t.test('instala apagado y conserva datos, Auth, firmas, permisos y métricas F7',()=>{
    assert.equal(huellaEconomica(),huella);
    assert.equal(contratoApi(),api);
    assert.equal(sql("select md5(pg_get_functiondef('private.cartera_f5_fuentes()'::regprocedure))"),cruda);
    assert.equal(sql('select md5(jsonb_agg(f order by empresa,fuente_id)::text) from private.cartera_f5_fuentes() f'),antesFuentes);
    assert.equal(sql('select md5(jsonb_agg(f order by fuente_id)::text) from private.metricas_f7_fuentes() f'),antesMetricas);
    assert.equal(sql('select activo from crm.piloto_f8_control'),'f');
    assert.equal(sql(`select count(*) from crm.multiempresa_flags where activo and nombre in
      ('inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra')`),'0');
    assert.equal(sql('select count(*) from private.cartera_f5_fuentes_reales()'),'593');
    assert.throws(()=>sql(migracionDemo),/ya existe/);
  });

  await t.test('cuatro huecos demo permiten el piloto solo al equipo nominal',()=>{
    for(const actor of [a.gerencia,a.supervisor,...a.vendedores]) {
      const e=json(piloto('select crm.cartera_inversionistas_estado_fn();',actor));
      assert.equal(e.habilitada,true);assert.equal(e.escritura_habilitada,true);
    }
    assert.equal(json(piloto('select crm.cartera_inversionistas_estado_fn();',a.supervisor_ajeno)).habilitada,false);
  });

  await t.test('F5 global aplica la misma cobertura real con el piloto apagado',()=>{
    const global=`update crm.multiempresa_flags set activo=true where nombre='ficha_360_neutral';`;
    const estado=json(`begin;${global}${como(a.gerencia,
      'select crm.cartera_inversionistas_estado_fn();')}rollback;`);
    assert.equal(estado.habilitada,true);assert.equal(estado.escritura_habilitada,false);
    const m=mutanteFuentes(`update f8_fuentes_prueba set identidad_coherente=false,inversionista_id=null
      where fuente_id=${q(f.base.fuente_id)}`);
    assert.equal(json(`begin;${global}${m}${como(a.gerencia,
      'select crm.cartera_inversionistas_estado_fn();')}rollback;`).habilitada,false);
  });

  await t.test('un hueco real bloquea tanto el encendido como la cartera ya activa',()=>{
    const m=mutanteFuentes(`update f8_fuentes_prueba set identidad_coherente=false,inversionista_id=null
      where fuente_id=${q(f.base.fuente_id)}`);
    sql(`begin;${m}${miembrosSql(a)}${errorEsperado('P0409',activarSql(a.gerencia))}rollback;`);
    const e=json(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}${m}
      ${como(a.gerencia,'select crm.cartera_inversionistas_estado_fn();')}rollback;`);
    assert.equal(e.habilitada,false);assert.equal(e.escritura_habilitada,false);
  });

  await t.test('es_demo NULL no permite eludir el bloqueo de identidad',()=>{
    const m=mutanteFuentes(`update f8_fuentes_prueba set es_demo=null,identidad_coherente=false,
      inversionista_id=null where fuente_id=${q(f.base.fuente_id)}`);
    sql(`begin;${m}${miembrosSql(a)}${errorEsperado('P0409',activarSql(a.gerencia))}rollback;`);
  });

  await t.test('persona mixta: lista, ficha, cantidades y capital solo incluyen fuentes reales',()=>{
    const id=f.base.inversionista_id;
    const esperado=json(`select jsonb_build_object('cantidad',count(*),'capital',sum(capital))
      from private.cartera_f5_fuentes() where inversionista_id=${q(id)} and not es_demo`);
    const ficha=json(piloto(`select crm.inversionista_ficha_fn(${q(id)},1,1);`));
    assert.ok(ficha);assert.equal(ficha.inversiones_total,esperado.cantidad);
    assert.ok(ficha.inversiones.every(x=>!x.es_demo&&x.fuente_id!==f.demoMixto));
    assert.equal(ficha.totales.reduce((n,x)=>n+x.cantidad,0),esperado.cantidad);
    assert.equal(ficha.totales.reduce((n,x)=>n+x.capital_registrado,0),esperado.capital);
    const lista=json(piloto('select crm.cartera_inversionistas_fn(1,50);'));
    assert.equal(lista.totales.reduce((n,x)=>n+x.cantidad,0),593);
    assert.ok(lista.filas.some(x=>x.inversionista_id===id));
    assert.equal(sql(piloto(`select coalesce(crm.inversionista_documento_fn(
      ${q(id)},${q(f.demoMixto)},${q(f.demoMixto)})::text,'NULL');`)),'NULL');
    const propio=`update crm.inversionistas set responsable_relacion_id=${q(a.vendedores[0])}
      where id=${q(id)};`;
    assert.equal(sql(piloto(`select coalesce(crm.inversionista_documento_fn(
      ${q(id)},${q(f.demoMixto)},${q(f.demoMixto)})::text,'NULL');`,a.vendedores[0],propio)),'NULL');
  });

  await t.test('perfil con solo demos queda fuera incluso de ficha y cuentas por UUID',()=>{
    const id=randomUUID();
    const previo=`insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
      values(${q(id)},${q(f.perfiles[0])},${q(a.vendedores[0])});`;
    const lista=json(piloto("select crm.cartera_inversionistas_fn(1,50,'DEMO F8 AISLADO');",a.gerencia,previo));
    assert.equal(lista.total,0);assert.deepEqual(lista.totales,[]);
    assert.equal(sql(piloto(`select coalesce(crm.inversionista_ficha_fn(${q(id)})::text,'NULL');`,a.gerencia,previo)),'NULL');
    sql(piloto(errorEsperado('42501',`perform crm.inversionista_cuentas_fn(
      ${q(id)},${q(f.perfiles[0])},'PEN')`),a.gerencia,previo));
  });

  await t.test('cliente legítimo sin fuentes conserva su ficha y respeta el responsable',()=>{
    const id=randomUUID(),p=randomUUID();
    const previo=personaSinFuentes(a,id,p);
    const ficha=json(piloto(`select crm.inversionista_ficha_fn(${q(id)});`,a.vendedores[0],previo));
    assert.equal(ficha.inversiones_total,0);assert.equal(ficha.persona.inversionista_id,id);
    assert.equal(sql(piloto(`select coalesce(crm.inversionista_ficha_fn(${q(id)})::text,'NULL');`,a.vendedores[1],previo)),'NULL');
  });

  await t.test('un filtro futuro del lector no excluye perfiles con historia exclusivamente real',()=>{
    const id=sql(`select inversionista_id from private.cartera_f5_fuentes()
      where empresa='avance' and not es_demo and identidad_coherente
        and inversionista_id<>${q(f.base.inversionista_id)} order by inversionista_id limit 1`);
    assert.ok(id);
    const m=mutanteFuentes(`delete from f8_fuentes_prueba where inversionista_id=${q(id)}`);
    const ficha=json(piloto(`select crm.inversionista_ficha_fn(${q(id)});`,a.gerencia,m));
    assert.equal(ficha.persona.inversionista_id,id);assert.equal(ficha.inversiones_total,0);
  });

  await t.test('cierre demo enlazado por lead vivo o histórico no crea una ficha vacía',()=>{
    for(const historico of [false,true]) {
      const id=randomUUID(),p=randomUUID();
      const previo=personaSinFuentes(a,id,p)+`set local crm.op_privilegiada='on';`+
        (historico?`insert into crm.inversionista_leads(inversionista_id,lead_id,rol)
          values(${q(id)},${q(f.lead)},'historico');`:
          `update crm.leads set inversionista_id=${q(id)} where id=${q(f.lead)};`);
      assert.equal(sql(piloto(`select coalesce(crm.inversionista_ficha_fn(${q(id)})::text,'NULL');`,a.gerencia,previo)),'NULL');
    }
  });

  await t.test('Directorio conserva lectura Avance real y excluye perfiles solo demo',()=>{
    const lector=sql("select id from public.perfiles where rol='directorio' and activo order by id limit 1");
    assert.ok(lector,'El banco debe contener un lector Directorio');
    const id=randomUUID();
    const r=json(`begin;update crm.multiempresa_flags set activo=true where nombre='ficha_360_neutral';
      insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
        values(${q(id)},${q(f.perfiles[0])},${q(a.vendedores[0])});
      ${como(lector,`select jsonb_build_object('demo',crm.inversionista_ficha_fn(${q(id)}),
        'mixta',crm.inversionista_ficha_fn(${q(f.base.inversionista_id)}));`)}rollback;`);
    assert.equal(r.demo,null);assert.ok(r.mixta);
    assert.ok(r.mixta.inversiones.every(x=>x.empresa==='avance'&&!x.es_demo));
    assert.equal(r.mixta.capacidades.documentos,false);
  });

  await t.test('demos contradictorios no reaparecen como perfiles sin inversiones',()=>{
    const p1=randomUUID(),p2=randomUUID(),iv=randomUUID();
    const previo=`insert into crm.inversionistas(id,perfil_id,responsable_relacion_id) values
      (${q(p1)},${q(f.perfiles[0])},${q(a.vendedores[0])}),
      (${q(p2)},${q(f.perfiles[1])},${q(a.vendedores[0])});
      insert into crm.inversiones select (jsonb_populate_record(null::crm.inversiones,to_jsonb(x)||
        jsonb_build_object('id',${q(iv)},'inversionista_id',${q(p2)},
          'contrato_id',${q(f.contratos[0])},'cierre_externo_id',null))).*
      from crm.inversiones x where x.contrato_id is not null order by x.id limit 1;`;
    assert.equal(json(piloto("select crm.cartera_inversionistas_fn(1,50,'DEMO F8 AISLADO');",a.gerencia,previo)).total,0);
  });

  await t.test('la clasificación demo sigue reservada a Gerencia con motivo y rastro',()=>{
    sql(`begin;${como(a.vendedores[0],errorEsperado('42501',
      `perform public.marcar_contrato_demo(${q(f.contratos[0])},false,'Intento sin permiso')`))}rollback;`);
    sql(`begin;${como(a.gerencia,errorEsperado('22023',
      `perform public.marcar_contrato_demo(${q(f.contratos[0])},false,'')`))}rollback;`);
    sql(`begin;${como(a.gerencia,`select public.marcar_contrato_demo(
      ${q(f.contratos[0])},false,'Reclasificación sintética a real');`)}reset role;
      ${miembrosSql(a)}${errorEsperado('P0409',activarSql(a.gerencia))}
      do $check$ begin
        if not exists(select 1 from public.audit_log where fila_id=${q(f.contratos[0])}
          and operacion='demo_marca' and usuario_id=${q(a.gerencia)}) then
          raise exception 'Falta la auditoría de Gerencia';end if;
      end $check$;rollback;`);
  });

  await t.test('el cierre demo tampoco sirve de origen de postventa o renovación',()=>{
    const id=f.base.inversionista_id;
    const previo=`set local crm.op_privilegiada='on';
      update crm.cierres_externos set inversionista_id=${q(id)} where id=${q(cierreDemo)};`;
    sql(`begin;${previo}${errorEsperado('42501',
      `perform private.postventa_fuente(${q(cierreDemo)},${q(id)},'qorilazo')`)}rollback;`);
    const vencimientos=json(piloto('select crm.postventa_vencimientos_fn();',a.gerencia,previo));
    assert.ok(vencimientos.filas.every(x=>x.fuente_id!==cierreDemo&&x.fuente_id!==f.demoMixto));
  });

  await t.test('ningún rol de API obtiene acceso al lector privado',()=>{
    for(const rol of ['anon','authenticated','service_role']) {
      sql(`begin;set local role ${rol};${errorEsperado('42501',
        'perform * from private.cartera_f5_fuentes_reales()')}rollback;`);
    }
  });

  await t.test('instalación y reversa rechazan piloto o cualquier bandera global encendida',()=>{
    for(const sentencia of [migracionDemo,reversaDemo]) {
      assert.throws(()=>sql(`begin;${miembrosSql(a)}${activarSql(a.gerencia)}${sentencia}`),/apagados|Apagar F8/);
      for(const flag of ['inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra']) {
        assert.throws(()=>sql(`begin;update crm.multiempresa_flags set activo=true where nombre=${q(flag)};
          ${sentencia}`),/apagados|Apagar F8/);
      }
    }
    assert.equal(sql('select activo from crm.piloto_f8_control'),'f');
  });

  await t.test('reversa rechaza deriva y consumidores adicionales, con rollback completo',()=>{
    const original=sql("select md5(pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure))");
    const primerLector=sql("select md5(pg_get_functiondef('private.trg_piloto_f8_control_validar()'::regprocedure))");
    assert.throws(()=>sql(`begin;alter function private.cartera_f5_personas_visibles() cost 101;
      ${reversaDemo}`),/La base cambió/);
    assert.throws(()=>sql(`begin;create function public.f8_consumidor_prueba() returns bigint
      language sql as $$select count(*) from private.cartera_f5_fuentes_reales()$$;
      ${reversaDemo}`),/Otro consumidor/);
    assert.throws(()=>sql(`begin;create view private.f8_vista_prueba as
      select * from private.cartera_f5_fuentes_reales();${reversaDemo}`),/dependencia de catálogo/);
    assert.equal(sql("select md5(pg_get_functiondef('private.cartera_f5_personas_visibles()'::regprocedure))"),original);
    assert.equal(sql("select md5(pg_get_functiondef('private.trg_piloto_f8_control_validar()'::regprocedure))"),primerLector);
    assert.equal(huellaEconomica(),huella);
  });

  await t.test('reversa de definiciones restaura el bloqueo anterior sin borrar historia',()=>{
    sql(reversaDemo);
    sql(`begin;${miembrosSql(a)}${errorEsperado('P0409',activarSql(a.gerencia))}rollback;`);
    assert.equal(huellaEconomica(),huella);
    assert.equal(contratoApi(),api);
    assert.deepEqual(censo(),{fuentes:598,reales:593,demo:5,huecos_reales:0,huecos_demo:4});
    assert.throws(()=>sql(`begin;alter function private.cartera_f5_fuentes() cost 101;
      ${migracionDemo}`),/La autoridad demo cambió/);
    assert.throws(()=>sql(`begin;create function public.f8_consumidor_prueba() returns bigint
      language sql as $$select count(*) from private.cartera_f5_fuentes()$$;
      ${migracionDemo}`),/consumidor sin revisar/);
    assert.throws(()=>sql(`begin;create view private.f8_vista_prueba as
      select * from private.cartera_f5_fuentes();${migracionDemo}`),/dependencia de catálogo/);
    sql(migracionDemo);
  });
});
