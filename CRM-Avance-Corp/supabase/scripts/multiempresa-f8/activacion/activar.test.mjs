import test from 'node:test';
import assert from 'node:assert/strict';
import {crearActivacion,crearReversa} from './crear-sql.mjs';
import {preparar,actores,sql,sqlAsync,como,huellaEconomica,literal as q} from '../banco-local.mjs';

const estado=()=>JSON.parse(sql(`select jsonb_build_object(
 'activo',(select activo from crm.piloto_f8_control),
 'revision',(select revision from crm.piloto_f8_control),
 'miembros',(select count(*) from crm.piloto_f8_miembros))`));
const cerrado={activo:false,revision:0,miembros:0};
const pausa=ms=>new Promise(resolve=>setTimeout(resolve,ms));
// El candado observado sincroniza las sesiones; el sleep abre una ventana de carrera.
async function esperarCandado(nombre,concedido=true) {
  for(let i=0;i<30;i++) {
    if(sql(`select exists(select 1 from pg_stat_activity a join pg_locks l on l.pid=a.pid
      where a.datname=current_database() and a.application_name=${q(nombre)}
        and l.locktype='advisory' and l.mode='ExclusiveLock' and l.granted=${concedido}
        and l.objid=(hashtext('crm_piloto_f8_control')::bigint & 4294967295)::oid)`)==='t') return;
    await pausa(25);
  }
  assert.fail('No se observó el estado esperado del candado F8 para '+nombre);
}

test('F8: configuración nominal en banco sintético aislado',async t=>{
  preparar();
  const a=actores();
  // Refleja el caso elegido: un analista del supervisor piloto y otro de otro equipo.
  sql(`update crm.equipo set supervisor_id=${q(a.supervisor)} where perfil_id=${q(a.vendedores[0])};
    update crm.equipo set supervisor_id=${q(a.supervisor_ajeno)} where perfil_id=${q(a.vendedores[1])};`);
  const equipo=JSON.parse(sql(`select jsonb_agg(jsonb_build_object('perfil_id',perfil_id,
    'rol_esperado',rol_crm,'supervisor_id',supervisor_id) order by perfil_id)
    from crm.equipo where perfil_id in (${[a.gerencia,a.supervisor,...a.vendedores].map(q).join(',')})`));
  const opciones={responsable_id:a.gerencia,referencia:'F8-ENSAYO-01'};
  const texto=crearActivacion(equipo,opciones);
  const reversa=crearReversa({...opciones,referencia:'F8-ENSAYO-CIERRE-01'});
  const conEspera=texto.replace("perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control'));",
    "perform pg_advisory_xact_lock(hashtext('crm_piloto_f8_control')); perform pg_sleep(1.5);");
  const inicio='begin isolation level read committed;';
  const fin='select activo,revision,inicia_en,vence_en,';
  assert.ok(texto.includes(inicio)&&texto.includes(fin));
  const cuerpo=texto.slice(texto.indexOf(inicio)+inicio.length,texto.lastIndexOf(fin));
  const antes=huellaEconomica();
  const equiposAntes=sql('select md5(jsonb_agg(to_jsonb(e) order by perfil_id)::text) from crm.equipo e');

  await t.test('rechaza identificadores, duplicados y composición distintos del equipo aprobado',()=>{
    assert.throws(()=>crearActivacion(equipo.slice(0,3),opciones),/cuatro/);
    assert.throws(()=>crearActivacion(equipo.map((x,i)=>i===0?{...x,perfil_id:"x'); commit; --"}:x),opciones),/Identificador/);
    assert.throws(()=>crearActivacion(equipo.map((x,i)=>i===0?equipo[1]:x),opciones),/duplicados/);
    assert.throws(()=>crearActivacion(equipo.map(x=>({...x,rol_esperado:'vendedor'})),opciones),/Composición/);
  });
  await t.test('exige responsable explícito y referencia válida en activación y cierre',()=>{
    for(const generar of [o=>crearActivacion(equipo,o),crearReversa]) {
      assert.throws(()=>generar(),/Responsable/);
      assert.throws(()=>generar({...opciones,responsable_id:"x'; --"}),/Responsable/);
      assert.throws(()=>generar({...opciones,referencia:"x'; --"}),/Referencia/);
    }
    assert.throws(()=>sql(crearActivacion(equipo,{...opciones,responsable_id:a.supervisor})),/Falta responsable/);
    assert.deepEqual(estado(),cerrado);
  });
  await t.test('el SQL completo rechaza un supervisor desactualizado y revierte sin miembros',()=>{
    const distinto=equipo.map(x=>x.perfil_id===a.vendedores[0]?{...x,supervisor_id:a.supervisor_ajeno}:x);
    assert.throws(()=>sql(crearActivacion(distinto,opciones)),/Cambió una cuenta/);
    assert.deepEqual(estado(),cerrado);assert.equal(huellaEconomica(),antes);
  });
  const casos=[
    ['perfil inactivo',`update public.perfiles set activo=false where id=${q(a.vendedores[0])}`],
    ['cuenta suspendida',`update auth.users set banned_until=now()+interval '1 day' where id=${q(a.vendedores[0])}`],
    ['correo sin confirmar',`update auth.users set email_confirmed_at=null where id=${q(a.vendedores[0])}`],
    ['cuenta eliminada',`update auth.users set deleted_at=now() where id=${q(a.vendedores[0])}`],
    ['identidad email ausente',`delete from auth.identities where user_id=${q(a.vendedores[0])} and provider='email'`],
    ['supervisor cambiado',`update crm.equipo set supervisor_id=${q(a.supervisor_ajeno)} where perfil_id=${q(a.vendedores[0])}`],
    ['rol cambiado',`update crm.equipo set rol_crm='supervisor' where perfil_id=${q(a.vendedores[0])}`],
  ];
  for(const [nombre,mutacion] of casos) await t.test(nombre+' impide activar sin dejar cambios parciales',()=>{
    assert.throws(()=>sql(`begin;${mutacion};${cuerpo}rollback;`),/Cambió una cuenta/);
    assert.deepEqual(estado(),cerrado);assert.equal(huellaEconomica(),antes);
  });
  await t.test('F3 OFF y revisión previa impiden la primera activación',()=>{
    assert.throws(()=>sql(`begin;update crm.multiempresa_flags set activo=false
      where nombre='resolver_en_puertas';${cuerpo}rollback;`),/requiere F3 ON/);
    assert.deepEqual(estado(),cerrado);
    assert.throws(()=>sql(`begin;update crm.piloto_f8_control set activo=false;${cuerpo}rollback;`),/ya tuvo participantes/);
    assert.deepEqual(estado(),cerrado);
  });
  await t.test('rollout global encendido impide el piloto y revierte la transacción',()=>{
    assert.throws(()=>sql(`begin;update crm.multiempresa_flags set activo=true
      where nombre='ficha_360_neutral';${cuerpo}rollback;`),/requiere F3 ON/);
    assert.deepEqual(estado(),cerrado);
    assert.equal(sql("select activo from crm.multiempresa_flags where nombre='ficha_360_neutral'"),'f');
  });
  await t.test('no atribuye la ejecución administrativa a una sesión de otra persona',()=>{
    assert.throws(()=>sql(`begin;set local request.jwt.claim.sub=${q(a.gerencia)};${cuerpo}rollback;`),/sin suplantar/);
    assert.deepEqual(estado(),cerrado);
  });
  await t.test('una fuente sin identidad falla en el prechequeo y revierte todo',()=>{
    const definicion=sql("select pg_get_functiondef('private.cartera_f5_fuentes_reales()'::regprocedure)");
    const reemplazo=definicion.replace(/AS \$function\$[\s\S]*\$function\$$/,
      'AS $function$ select * from pg_temp.f8_cobertura_prueba $function$');
    assert.notEqual(reemplazo,definicion);
    assert.throws(()=>sql(`begin;create temporary table f8_cobertura_prueba on commit drop
      as select * from private.cartera_f5_fuentes_reales();
      update f8_cobertura_prueba set inversionista_id=null,identidad_coherente=false
      where fuente_id=(select fuente_id from f8_cobertura_prueba order by fuente_id limit 1);
      ${reemplazo};${cuerpo}rollback;`),/La cobertura real cambió/);
    assert.equal(sql("select pg_get_functiondef('private.cartera_f5_fuentes_reales()'::regprocedure)"),definicion);
    assert.deepEqual(estado(),cerrado);assert.equal(huellaEconomica(),antes);
  });
  for(const [nombre,competidor] of [
    ...['inversiones_escritura','ficha_360_neutral','postventa_neutral','metricas_multiempresa_sombra']
      .map(bandera=>[bandera,`begin;set local lock_timeout='5s';update crm.multiempresa_flags
        set activo=true where nombre=${q(bandera)};rollback;`]),
    ['reversa administrativa',reversa.replace(/commit;\s*$/,'rollback;')],
  ]) await t.test('activación simultánea con '+nombre+' termina sin bloqueo circular',async()=>{
    const primera=sqlAsync("set application_name='f8-ensayo-lock';"+conEspera.replace(/commit;\s*$/,'rollback;'));
    await esperarCandado('f8-ensayo-lock');
    const segunda=sqlAsync("set application_name='f8-ensayo-competidor';"+competidor);
    await esperarCandado('f8-ensayo-competidor',false);
    const resultados=await Promise.all([primera,segunda]);
    for(const r of resultados) assert.equal(r.status,0,r.stderr);
    assert.deepEqual(estado(),cerrado);assert.equal(huellaEconomica(),antes);
  });
  await t.test('dos activaciones concurrentes permiten una sola: cuatro miembros, siete días y cinco auditorías',async()=>{
    const auditoriaAntes=Number(sql("select count(*) from public.audit_log where tabla like 'crm.piloto_f8_%'"));
    const primera=sqlAsync("set application_name='f8-ensayo-duplicado';"+conEspera);
    await esperarCandado('f8-ensayo-duplicado');
    const duplicada=sqlAsync("set application_name='f8-ensayo-duplicado-competidor';"+texto);
    await esperarCandado('f8-ensayo-duplicado-competidor',false);
    const bandera=sqlAsync("set application_name='f8-ensayo-global-commit';begin;set local lock_timeout='5s';"+
      "update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';commit;");
    await esperarCandado('f8-ensayo-global-commit',false);
    const [ganadora,rechazada,global]=await Promise.all([primera,duplicada,bandera]);
    assert.equal(ganadora.status,0,ganadora.stderr);
    assert.notEqual(rechazada.status,0);assert.match(rechazada.stderr,/ya tuvo participantes/);
    assert.notEqual(global.status,0);assert.match(global.stderr,/Apaga F8 antes de activar el rollout global/);
    assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"),'f');
    assert.deepEqual(estado(),{activo:true,revision:1,miembros:4});
    assert.equal(sql("select vence_en-inicia_en=interval '7 days' from crm.piloto_f8_control"),'t');
    assert.equal(sql(`select bool_and(actualizado_por=${q(a.gerencia)}::uuid) from crm.piloto_f8_miembros`),'t');
    assert.equal(sql("select bool_and(motivo like 'Piloto F8 ref:F8-ENSAYO-01;%') from crm.piloto_f8_miembros"),'t');
    assert.equal(Number(sql("select count(*) from public.audit_log where tabla like 'crm.piloto_f8_%'"))-auditoriaAntes,5);
    assert.equal(sql("select count(*) from public.audit_log where tabla like 'crm.piloto_f8_%' and usuario_id is not null"),'0');
    assert.equal(huellaEconomica(),antes);
    assert.equal(sql('select md5(jsonb_agg(to_jsonb(e) order by perfil_id)::text) from crm.equipo e'),equiposAntes);
  });
  await t.test('habilita F5/F6 a los seleccionados y conserva el ámbito entre equipos',()=>{
    for(const actor of [a.gerencia,a.supervisor,...a.vendedores]){
      const cap=JSON.parse(sql(`begin;${como(actor,`select jsonb_build_object(
        'f5',crm.cartera_inversionistas_estado_fn(),'f6',crm.postventa_estado_fn())`)};rollback;`));
      assert.equal(cap.f5.habilitada,true);assert.equal(cap.f5.escritura_habilitada,true);assert.equal(cap.f6.habilitada,true);
    }
    const ajeno=JSON.parse(sql(`begin;${como(a.supervisor_ajeno,`select crm.cartera_inversionistas_estado_fn()`)};rollback;`));
    assert.equal(ajeno.habilitada,false);
    const postventaAjena=JSON.parse(sql(`begin;${como(a.supervisor_ajeno,'select crm.postventa_estado_fn()')};rollback;`));
    assert.equal(postventaAjena.habilitada,false);
    const visibles=JSON.parse(sql(`begin;set local request.jwt.claim.sub=${q(a.supervisor)}; select coalesce(jsonb_agg(x),'[]') from private.vendedor_ids_visibles(${q(a.supervisor)}::uuid) x;rollback;`));
    assert.ok(visibles.includes(a.vendedores[0]));assert.ok(!visibles.includes(a.vendedores[1]));
    assert.equal(sql("select has_table_privilege('authenticated','crm.piloto_f8_miembros','SELECT')"),'f');
  });
  await t.test('una segunda ejecución no amplía la vigencia ni repite miembros',()=>{
    const previo=sql('select to_jsonb(c) from crm.piloto_f8_control c');
    assert.throws(()=>sql(texto),/ya tuvo participantes/);
    assert.equal(sql('select to_jsonb(c) from crm.piloto_f8_control c'),previo);
  });
  await t.test('reversa apaga y conserva datos y asignaciones',()=>{
    sql(reversa);
    assert.equal(estado().activo,false);assert.equal(estado().miembros,4);
    assert.equal(sql('select count(*) from crm.piloto_f8_miembros where activo'),'0');
    assert.equal(sql(`select actualizado_por=${q(a.gerencia)}::uuid and motivo like
      'Cierre F8 ref:F8-ENSAYO-CIERRE-01;%' from crm.piloto_f8_control`),'t');
    assert.equal(sql(`select bool_and(actualizado_por=${q(a.gerencia)}::uuid and motivo like
      'Cierre F8 ref:F8-ENSAYO-CIERRE-01;%') from crm.piloto_f8_miembros`),'t');
    const revision=estado().revision;
    sql(reversa);assert.equal(estado().revision,revision,'Repetir el cierre OFF no fabrica otra revisión');
    assert.equal(huellaEconomica(),antes);
    assert.equal(sql('select md5(jsonb_agg(to_jsonb(e) order by perfil_id)::text) from crm.equipo e'),equiposAntes);
  });
});
