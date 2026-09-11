import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {aplicar,como,fixture,informe,literal as q,sql} from './banco-local.mjs';
import {verificarContrato,estadoConciliacion} from './contrato-cliente.mjs';

const simplificar=r=>r.produccion.map(({empresa,moneda,capital,operaciones})=>({empresa,moneda,capital,operaciones}));
const huellas=()=>sql(`select jsonb_agg(jsonb_build_array(n.nspname,p.proname,
  pg_get_function_identity_arguments(p.oid),md5(pg_get_functiondef(p.oid)),p.proacl,p.proowner)
  order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','crm','private') and p.prokind='f'
    and p.proname not like 'metricas_f7_%' and p.proname not like 'metricas_multiempresa_%'`);
const dineroYFotos=()=>sql(`select jsonb_build_object(
  'contratos',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from public.contratos t),
  'cierres',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from crm.cierres_externos t),
  'periodos',(select md5(coalesce(jsonb_agg(t order by periodo)::text,'')) from crm.periodos_cerrados t),
  'auth',(select md5(coalesce(jsonb_agg(t order by id)::text,'')) from auth.users t),
  'flags',(select jsonb_object_agg(nombre,activo) from crm.multiempresa_flags where nombre<>'metricas_multiempresa_sombra'))`);
const errorEsperado=(codigo,consulta)=>`do $$begin
  begin ${consulta};raise exception 'Faltó el rechazo esperado';
  exception when sqlstate '${codigo}' then null;end;end$$;`;
const huellasF7=()=>sql(`select jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,
  md5(pg_get_functiondef(p.oid)),p.proacl,p.proowner) order by p.oid::regprocedure::text)
  from pg_proc p where p.oid=any(array['private.metricas_f7_autorizada()'::regprocedure,
    'private.metricas_f7_fuentes()'::regprocedure,'crm.metricas_multiempresa_estado_fn()'::regprocedure,
    'crm.metricas_multiempresa_fn(date)'::regprocedure])`);
function fuentesAlteradas(mutacion) {
  const def=sql("select pg_get_functiondef('private.metricas_f7_fuentes()'::regprocedure)");
  assert.ok(def.includes('AS $function$'));
  // Solo un auxiliar NUEVO F7, en una transacción de esta copia descartable.
  const reemplazo=def.replace(/AS \$function\$[\s\S]*\$function\$/,
    'AS $function$ select * from pg_temp.f7_fuentes_test $function$');
  return `create temporary table f7_fuentes_test on commit drop as select * from private.metricas_f7_fuentes();
    ${mutacion};${reemplazo};`;
}

test('F7: instalación aditiva, mismos núcleos, dinero, Auth y meses cerrados',()=>{
  const antes=huellas(),datos=dineroYFotos();aplicar();
  assert.equal(huellas(),antes);assert.equal(dineroYFotos(),datos);
  assert.equal(sql("select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'"),'f');
});

test('F7: permisos SQL efectivos, apagado y membresía vigente',()=>{
  for(const rol of ['anon','service_role']) {
    sql(`begin;set local role ${rol};${errorEsperado('42501','perform crm.metricas_multiempresa_fn()')}rollback;`);
  }
  for(const rol of Object.keys(fixture.usuarios).filter(x=>x!=='gerencia')) {
    sql(`begin;${como(rol,errorEsperado('42501','perform crm.metricas_multiempresa_estado_fn()'))}
      ${errorEsperado('42501','perform crm.metricas_multiempresa_fn()')}rollback;`);
  }
  sql(`begin;${como('gerencia',errorEsperado('P0409','perform crm.metricas_multiempresa_fn()'))}rollback;`);
  sql(`begin;set local role authenticated;
    ${errorEsperado('42501','perform private.metricas_f7_fuentes()')}
    ${errorEsperado('42501','perform private.metricas_f7_autorizada()')}rollback;`);
  for(const tabla of ['crm.equipo','public.perfiles']) {
    const id=tabla==='crm.equipo'?'perfil_id':'id';
    // Estado heredado de sesión revocada. Solo se omite el guard de dependencias
    // durante el setup sintético; queda restaurado ANTES de llamar a la RPC.
    const antes=tabla==='crm.equipo'?'alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;':'';
    const despues=tabla==='crm.equipo'?'alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;':'';
    sql(`begin;${antes}update ${tabla} set activo=false where ${id}=${q(fixture.usuarios.gerencia.id)};${despues}
      ${como('gerencia',errorEsperado('42501','perform crm.metricas_multiempresa_estado_fn()'))}rollback;`);
  }
});

test('F7: una divergencia del núcleo detiene la instalación y conserva el estado',()=>{
  const firma='private.peso_referido_conversion(date)';
  const actual=sql(`select pg_get_functiondef(${q(firma)}::regprocedure)`);
  assert.ok(actual.includes('AS $function$'));
  const divergente=actual.replace('AS $function$','AS $function$\n-- Divergencia sintética para comprobar el candado.\n');
  const candidata=readFileSync(new URL('../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql',import.meta.url),'utf8');
  const antes=huellas(),datos=dineroYFotos();
  // psql termina con error y PostgreSQL revierte la transacción abierta.
  assert.throws(()=>sql(`begin;${divergente};\n${candidata}\nrollback;`),/La base cambió: revisar/);
  assert.equal(huellas(),antes);assert.equal(dineroYFotos(),datos);
});

test('F7: paridad de capital, cantidad y atribución, separando empresas/PEN/USD',()=>{
  const r=verificarContrato(informe());assert.equal(r.produccion.length,4,'El banco necesita tres empresas y Avance USD');
  const fuente=JSON.parse(sql(`select jsonb_agg(x order by empresa,moneda) from (
    select case when k.contrato_id is not null then 'avance' else c.cooperativa end empresa,
      k.moneda,sum(k.monto) capital,count(*) operaciones
    from private.capital_episodios('2026-09-01 00:00-05',
      ((now() at time zone 'America/Lima')::date+1)::timestamp at time zone 'America/Lima',true,'{}') k
    left join crm.cierres_externos c on c.id=k.cierre_externo_id
    where k.medida='stock' group by 1,2) x`));
  assert.deepEqual(simplificar(r),fuente);
  assert.equal(r.fuentes_duplicadas,0);
  for(const c of r.conciliacion) {
    assert.equal(c.diferencia_capital,0);assert.equal(c.diferencia_operaciones,0);assert.equal(c.diferencia_atribucion,0);
    const a=r.atribucion.filter(x=>x.empresa===c.empresa&&x.moneda===c.moneda);
    assert.equal(a.reduce((s,x)=>s+x.capital,0),c.capital_nucleo);
  }
  for(const p of r.produccion)assert.equal(p.primeras+p.posteriores+p.sin_identidad,p.operaciones);
});

test('F7: una fuente repetida se avisa sin amplificarla con un segundo join',()=>{
  const antes=informe();
  const fuente=JSON.parse(sql(`select to_jsonb(f) from private.metricas_f7_fuentes() f
    where fecha_imputacion between date '2026-09-01' and (now() at time zone 'America/Lima')::date
    and inversionista_id is not null order by fuente_id limit 1`));
  const despues=verificarContrato(informe('2026-09-01',fuentesAlteradas(`insert into f7_fuentes_test
    select * from f7_fuentes_test where fuente_tipo=${q(fuente.fuente_tipo)} and fuente_id=${q(fuente.fuente_id)}`)));
  const grupo=r=>r.produccion.find(x=>x.empresa===fuente.empresa&&x.moneda===fuente.moneda);
  assert.equal(grupo(despues).operaciones,grupo(antes).operaciones+1);
  assert.equal(Math.round((grupo(despues).capital-grupo(antes).capital)*100),Math.round(fuente.capital*100));
  assert.equal(despues.fuentes_duplicadas,1);assert.equal(estadoConciliacion(despues),'diferencias');
});

test('F7: perder un grupo completo conserva la diferencia y el cliente puede mostrarla',()=>{
  const r=verificarContrato(informe('2026-09-01',fuentesAlteradas(
    "delete from f7_fuentes_test where empresa='avance' and moneda='USD'")));
  assert.equal(r.produccion.some(x=>x.empresa==='avance'&&x.moneda==='USD'),false);
  const diferencia=r.conciliacion.find(x=>x.empresa==='avance'&&x.moneda==='USD');
  assert.ok(diferencia.capital_nucleo>0);assert.equal(diferencia.capital_informe,0);
  assert.equal(diferencia.diferencia_capital,-diferencia.capital_nucleo);
  assert.equal(estadoConciliacion(r),'diferencias');
});

test('F7: conversión mantiene el numerador y divisor públicos, incluido upgrade elegible',()=>{
  const r=informe();
  const publicado=JSON.parse(sql(`begin;${como('gerencia',`select crm.metricas_conversiones_fn('2026-09-01',
    (now() at time zone 'America/Lima')::date)->'nucleo'`)};rollback;`));
  assert.equal(r.conversion.divisor,publicado.divisor);
  assert.equal(r.conversion.numerador,publicado.numerador);
  assert.ok(r.conversion.upgrades>0,'Necesita un upgrade elegible; no una paridad vacía');
  assert.ok(r.conversion.anulados>0,'Necesita anulaciones comerciales reales del banco');
});

test('F7: un cotitular añade una persona y nunca otro capital ni otra inversión',()=>{
  const antes=informe(),persona=randomUUID();
  const fuentes=JSON.parse(sql(`select jsonb_agg(id) from (select id from crm.inversiones
    where empresa_id=(select id from crm.empresas where clave='qorilazo') order by id limit 2) x`));
  assert.equal(fuentes.length,2);
  const despues=informe('2026-09-01',`insert into crm.inversionistas(id) values(${q(persona)});
    insert into crm.inversion_titulares(inversion_id,inversionista_id,rol)
      values(${q(fuentes[0])},${q(persona)},'cotitular'),(${q(fuentes[1])},${q(persona)},'cotitular');`);
  assert.equal(despues.personas.total,antes.personas.total+1);
  assert.equal(despues.personas.una_empresa,antes.personas.una_empresa+1);
  assert.deepEqual(simplificar(despues),simplificar(antes));
  assert.deepEqual(despues.atribucion,antes.atribucion);
  assert.equal(despues.personas.fuentes_contradictorias,antes.personas.fuentes_contradictorias);
});

test('F7: historia sin enlace conserva dinero y avisa cobertura incompleta',()=>{
  const fuente=JSON.parse(sql(`select jsonb_build_object('perfil',c.cliente_id,'persona',i.id)
    from public.contratos c join crm.inversionistas i on i.perfil_id=c.cliente_id
    where not c.es_demo and not exists(select 1 from crm.inversiones iv where iv.contrato_id=c.id)
    order by c.id limit 1`));
  const antes=informe();
  const despues=informe('2026-09-01',`update crm.inversionistas set perfil_id=null where id=${q(fuente.persona)};`);
  assert.deepEqual(simplificar(despues),simplificar(antes));
  assert.ok(despues.personas.fuentes_sin_enlace>antes.personas.fuentes_sin_enlace);
  assert.ok(despues.produccion.some(x=>x.sin_identidad>0));
});

test('F7: una contradicción histórica nunca elige una persona arbitraria',()=>{
  const antes=informe(),persona=randomUUID();
  const inversion=sql(`select iv.id from crm.inversiones iv join public.contratos c on c.id=iv.contrato_id
    where not c.es_demo and c.cliente_id is not null order by iv.id limit 1`);
  const despues=informe('2026-09-01',`insert into crm.inversionistas(id) values(${q(persona)});
    alter table crm.inversiones disable trigger trg_inversiones_empresa_coherente;
    update crm.inversiones set inversionista_id=${q(persona)} where id=${q(inversion)};
    alter table crm.inversiones enable trigger trg_inversiones_empresa_coherente;`);
  assert.deepEqual(simplificar(despues),simplificar(antes));
  assert.equal(despues.personas.fuentes_contradictorias,antes.personas.fuentes_contradictorias+1);
  assert.ok(despues.personas.total<=antes.personas.total,'La identidad contradictoria no crea una persona');
});

test('F7: medianoche Lima y fecha de ajuste de mes cerrado sin perder céntimos',()=>{
  const inicial=informe(),agosto=informe('2026-08-01');
  const ids=[randomUUID(),randomUUID(),randomUUID()];
  // Copias ficticias de cierre, sin tocar la fuente existente ni su ledger.
  // Dos cierres legados por instante y un ajuste imputado en septiembre.
  const preparar=`insert into crm.leads(id,nombre_completo,telefono,creado_por,origen,etapa,monto_estimado)
    values ${ids.map((id,n)=>`(${q(id)},'F7 borde sintético','5199000000${n+1}',${q(fixture.usuarios.gerencia.id)},'referido','nuevo',1000)`).join(',')};
    with base as (select * from crm.cierres_externos where cooperativa='qorilazo'
      and not es_cierre_inicial order by id limit 1),libres as (
      select id,n from (values ${ids.map((id,n)=>`(${q(id)}::uuid,${n+1})`).join(',')}) l(id,n))
    insert into crm.cierres_externos select (jsonb_populate_record(null::crm.cierres_externos,to_jsonb(b)||
      jsonb_build_object('id',x.id,'lead_id',l.id,'es_cierre_inicial',true,'inversionista_id',null,
        'numero_transaccion',x.id,'monto',x.monto,'fecha_comercial',x.comercial,'fecha_imputacion',x.imputacion,
        'creado_en',x.registro,'anulado_en',null,'anulado_por',null,'motivo_anulacion',null))).*
    from base b cross join (values
      (1,${q(ids[0])},0.01,'2026-09-01T04:59:59Z',null::date,null::date),
      (2,${q(ids[1])},0.02,'2026-09-01T05:00:00Z',null::date,null::date),
      (3,${q(ids[2])},0.03,'2026-09-02T17:00:00Z',date '2026-08-31',date '2026-09-02')
    ) x(n,id,monto,registro,comercial,imputacion) join libres l on l.n=x.n;`;
  const nuevo=informe('2026-09-01',preparar),viejo=informe('2026-08-01',preparar);
  const pen=r=>r.produccion.find(x=>x.empresa==='qorilazo'&&x.moneda==='PEN')??{capital:0,operaciones:0};
  assert.equal(Math.round((pen(nuevo).capital-pen(inicial).capital)*100),5);
  assert.equal(pen(nuevo).operaciones-pen(inicial).operaciones,2);
  assert.equal(Math.round((pen(viejo).capital-pen(agosto).capital)*100),1);
  assert.ok(nuevo.conciliacion.every(x=>x.diferencia_capital===0));
  assert.ok(viejo.conciliacion.every(x=>x.diferencia_capital===0),'El primer instante de septiembre no entra en el cierre de agosto');
});

test('F7: cambios de responsable no cambian atribución; veto reduce oportunidades',()=>{
  const antes=informe();
  const despues=informe('2026-09-01',`update crm.inversionistas set responsable_relacion_id=${q(fixture.usuarios.ajeno.id)},
    no_contactar=true,no_contactar_en=now(),no_contactar_por=${q(fixture.usuarios.gerencia.id)};`);
  assert.deepEqual(despues.atribucion,antes.atribucion);
  assert.deepEqual(despues.conversion,antes.conversion);
  assert.ok(antes.oportunidades.some(x=>x.personas>0));assert.ok(despues.oportunidades.every(x=>x.personas===0));
});

test('F7: un veto heredado en un lead también excluye la oportunidad',()=>{
  const antes=informe();
  const despues=informe('2026-09-01',`alter table crm.leads disable trigger trg_leads_000_no_contactar_puerta;
    update crm.leads set no_contactar=true;
    alter table crm.leads enable trigger trg_leads_000_no_contactar_puerta;
    -- Estado legado: el veto aún vive en el lead, como contempla F6.
    update crm.inversionistas set no_contactar=false,no_contactar_en=null,no_contactar_por=null;`);
  assert.deepEqual(despues.produccion,antes.produccion);
  assert.deepEqual(despues.personas,antes.personas);
  assert.ok(despues.oportunidades.some(x=>x.personas<antes.oportunidades.find(a=>a.empresa===x.empresa).personas));
});

test('F7: demo y desgloses no entran; vencimientos usan historia completa',()=>{
  assert.equal(sql(`select count(*) from private.metricas_f7_fuentes() f
    join private.cartera_f5_fuentes() c on c.fuente_id=f.fuente_id and c.empresa=f.empresa where c.es_demo`),'0');
  assert.equal(sql("select count(*) from private.metricas_f7_fuentes() where tipo_capital like 'desglose_%'"),'0');
  const r=informe();
  const esperado=JSON.parse(sql(`select coalesce(jsonb_agg(x order by empresa,moneda),'[]') from (
    select empresa,moneda,count(*) operaciones,sum(capital) capital from private.cartera_f5_fuentes()
    where not es_demo and vence_en between (now() at time zone 'America/Lima')::date and (now() at time zone 'America/Lima')::date+30
      and ((empresa='avance' and estado='activo') or (empresa<>'avance' and estado='vigente')) group by empresa,moneda) x`));
  assert.ok(esperado.length>0);assert.deepEqual(r.vencimientos,esperado);
  assert.deepEqual(informe('2026-08-01').vencimientos,r.vencimientos,'Vencimientos no depende del mes de producción');
});

test('F7: meses cerrados identificados, llamadas deterministas y sin escrituras',()=>{
  const antes=dineroYFotos();
  const mes=sql('select periodo from crm.periodos_cerrados order by periodo desc limit 1');
  assert.ok(mes,'El banco exige un mes sellado');
  const a=informe(mes),b=informe(mes);assert.equal(a.mes_sellado,true);
  delete a.generado_en;delete b.generado_en;assert.deepEqual(a,b);assert.equal(dineroYFotos(),antes);
  sql(`begin;update crm.multiempresa_flags set activo=true where nombre='metricas_multiempresa_sombra';
    ${como('gerencia',errorEsperado('22023',"perform crm.metricas_multiempresa_fn('infinity')"))}
    ${errorEsperado('22023',"perform crm.metricas_multiempresa_fn('2099-01-01')")}rollback;`);
});

test('F7: reversa apaga solo el informe y conserva núcleos/fuentes',()=>{
  const antes=dineroYFotos(),funciones=huellas(),funcionesF7=huellasF7();
  sql("update crm.multiempresa_flags set activo=true where nombre='metricas_multiempresa_sombra'");
  sql(readFileSync(new URL('reversa-operativa.sql',import.meta.url),'utf8'));
  assert.equal(sql("select activo from crm.multiempresa_flags where nombre='metricas_multiempresa_sombra'"),'f');
  assert.equal(dineroYFotos(),antes);assert.equal(huellas(),funciones);
  assert.equal(huellasF7(),funcionesF7,'La reversa debe conservar las cuatro funciones F7 y sus ACL/propietarios');
});
