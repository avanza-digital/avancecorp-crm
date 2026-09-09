import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { sql, guardar, literal as q } from './banco-local.mjs';

// Cada grupo carga los borradores y sus fixtures dentro de BEGIN/ROLLBACK.
// No instala la candidata, no reejecuta F2 global ni toca datos productivos.
const ejecucion = randomUUID();
const definiciones = ['07-historicos.sql', '08-historicos-lote.sql'].map(nombre => ({
  nombre, contenido: readFileSync(new URL(nombre, import.meta.url), 'utf8'),
}));
const sha = texto => createHash('sha256').update(texto).digest('hex');
const fotoSql = `select jsonb_object_agg(tabla,huella) from (
  select 'contratos' tabla,private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) huella from public.contratos t
  union all select 'cuotas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.cronograma_pagos t
  union all select 'cierres',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.cierres_externos t
  union all select 'personas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionistas t
  union all select 'identificadores',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversionista_identificadores t
  union all select 'perfiles',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from public.perfiles t
  union all select 'leads',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.leads t
  union all select 'mapaF2',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.backfill_multiempresa_mapa t
  union all select 'inversiones',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversiones t
  union all select 'titulares',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from crm.inversion_titulares t
  union all select 'jobsPdf',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')) from private.contrato_pdf_jobs t
  union all select 'sellosPdf',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.contrato_id),'[]')) from private.contrato_pdfs t
  union all select 'banderas',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by t.nombre),'[]')) from crm.multiempresa_flags t
  union all select 'capital',private.idem_hash(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'))
    from private.capital_episodios('-infinity','infinity',true,'{}') t
) x`;
const objetosAusentesSql = `select to_regprocedure('private.inversion_historica_estado(text,uuid)') is null
  and to_regprocedure('private.inversion_historica_aplicar(uuid,jsonb)') is null
  and to_regclass('crm.inversion_backfill_lotes') is null`;
assert.equal(sql(objetosAusentesSql), 't', 'Este oráculo exige los borradores todavía sin instalar');
assert.equal(sql("select activo from crm.multiempresa_flags where nombre='inversiones_escritura'"), 'f');
const antes = JSON.parse(sql(fotoSql));
const preparacion = `begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
${definiciones.map(d => d.contenido).join('\n')}
create function pg_temp.foto_f4() returns jsonb language sql as $f$ ${fotoSql} $f$;
create function pg_temp.foto_lotes() returns jsonb language sql as $f$
  select pg_temp.foto_f4()||jsonb_build_object('lotes',private.idem_hash(
    coalesce((select jsonb_agg(to_jsonb(l) order by l.id) from crm.inversion_backfill_lotes l),'[]')))
$f$;
create function pg_temp.exigir(valor boolean,mensaje text) returns void language plpgsql as $f$
begin if valor is distinct from true then raise exception '%',mensaje; end if; end;
$f$;
create function pg_temp.rechazar(sentencia text,codigo text) returns void language plpgsql as $f$
declare v_foto jsonb:=pg_temp.foto_lotes(); v_rechazo boolean:=false;
begin
  begin execute sentencia;
  exception when others then
    if sqlstate<>codigo then raise; end if;
    v_rechazo:=true;
  end;
  perform pg_temp.exigir(v_rechazo,'No se produjo el rechazo esperado: '||codigo);
  perform pg_temp.exigir(v_foto=pg_temp.foto_lotes(),'El rechazo dejó efectos');
end;
$f$;
create temp view _f4_fuentes_base as
  select 'contrato'::text tipo,id from public.contratos where numero_contrato like 'F4-BASE-%'
  union all select 'cierre',id from crm.cierres_externos where numero_transaccion like 'F4-BASE-%';
create function pg_temp.mapa_base() returns jsonb language sql as $f$
  select jsonb_agg(private.inversion_historica_estado(tipo,id) order by tipo,id) from _f4_fuentes_base
$f$;
create temp table _f4_resultado(datos jsonb) on commit drop;
`;
const pruebas = [];
function probar(nombre, cuerpo, { antesDo = '' } = {}) {
  const guion = `${preparacion}\n${antesDo}\n
do $prueba$
declare mapa jsonb:=pg_temp.mapa_base(); lote uuid:=gen_random_uuid(); inicial jsonb:=pg_temp.foto_f4();
  r jsonb; x jsonb; h jsonb; f jsonb; v uuid; ce uuid; v_rol text; c record; n integer;
begin
  ${cuerpo}
  insert into _f4_resultado values(jsonb_build_object('nombre',${q(nombre)},'conforme',true));
end;
$prueba$;
set constraints all immediate;
select datos from _f4_resultado;
rollback;`;
  try {
    pruebas.push(JSON.parse(sql(guion)));
    console.log(`PASS: ${nombre}`);
  } catch (error) {
    guardar(`historicos-lote-${ejecucion}-fallo.json`, { grupo: nombre, error: error.message,
      definiciones: definiciones.map(d => ({ nombre: d.nombre, sha256: sha(d.contenido) })) });
    throw error;
  } finally {
    assert.deepEqual(JSON.parse(sql(fotoSql)), antes, 'El grupo debe revertir todas sus fixtures y enlaces');
    assert.equal(sql(objetosAusentesSql), 't', 'El grupo no deja tablas ni funciones instaladas');
  }
}

probar('Funciones y actas cerradas a los roles de la API', `
  for v_rol in select unnest(array['anon','authenticated','service_role']) loop
    perform pg_temp.exigir(not has_function_privilege(v_rol,'private.inversion_historica_aplicar(uuid,jsonb)','EXECUTE'), 'EXECUTE abierto');
    perform pg_temp.exigir(not has_function_privilege(v_rol,'private.inversion_historica_estado(text,uuid)','EXECUTE'), 'Censo abierto');
    perform pg_temp.exigir(not has_table_privilege(v_rol,'crm.inversion_backfill_lotes','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'), 'Actas abiertas');
    perform pg_temp.rechazar(format('set local role %I; select private.inversion_historica_aplicar(%L,%L::jsonb)',v_rol,lote,mapa),'42501');
    perform pg_temp.rechazar(format('set local role %I; select * from crm.inversion_backfill_lotes',v_rol),'42501');
  end loop;
  perform pg_temp.exigir((select relrowsecurity from pg_class where oid='crm.inversion_backfill_lotes'::regclass),'RLS apagada');
`);

probar('Entradas nulas, vacías, excesivas y repetidas se rechazan sin efectos', `
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(null,%L::jsonb)',mapa),'22023');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,null)',lote),'22023');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,'{}'),'22023');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,'[]'),'22023');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,jsonb_build_array(mapa->0,mapa->0)),'22023');
  select jsonb_agg(mapa->0) into x from generate_series(1,101);
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,x),'22023');
`);

probar('Cambiar huella, persona o empresa del censo no autoriza otro enlace', `
  for x in select * from (values
    (jsonb_set(mapa,'{0,huella}',to_jsonb(repeat('0',64)))),
    (jsonb_set(mapa,'{0,persona}',to_jsonb(gen_random_uuid()))),
    (jsonb_set(mapa,'{0,empresa}',to_jsonb(gen_random_uuid())))) cambios(m) loop
    perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,x),'40001');
  end loop;
`);

probar('Deriva del mapa F2 invalida la previsualización anterior', `
  select id into ce from crm.cierres_externos where numero_transaccion='F4-BASE-qorilazo';
  select inversionista_id into v from crm.cierres_externos where numero_transaccion='F4-BASE-prodelco';
  perform private.f2_mapear('cierre',ce,v,'B','Fixture negativa de deriva','alta');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,mapa),'40001');
  mapa:=pg_temp.mapa_base();
  perform pg_temp.exigir(exists(select 1 from jsonb_array_elements(mapa) m where m->>'estado'='revision'),'Conflicto no visible');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,mapa),'P0409');
`);

probar('El lote exige identidad encendida y escritor de inversiones apagado', `
  update crm.multiempresa_flags set activo=true where nombre='inversiones_escritura';
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,mapa),'P0409');
  update crm.multiempresa_flags set activo=false where nombre='inversiones_escritura';
  update crm.multiempresa_flags set activo=false where nombre='resolver_en_puertas';
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,mapa),'P0409');
`);

probar('Seis fuentes vinculadas conservan economía, PDF, identidad y atribución', `
  perform pg_temp.exigir(jsonb_array_length(mapa)=6,'Se esperan seis antecedentes');
  r:=private.inversion_historica_aplicar(lote,mapa);
  perform pg_temp.exigir(jsonb_array_length(r->'fuentes')=6,'Lote parcial');
  perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(r->'fuentes') entrada where entrada->>'accion'<>'vinculada'),'Acción incorrecta');
  perform pg_temp.exigir((pg_temp.foto_f4()-array['inversiones','titulares'])=(inicial-array['inversiones','titulares']),'Se alteró una fuente o identidad');
  for c in select * from _f4_fuentes_base loop
    x:=private.inversion_historica_estado(c.tipo,c.id);
    perform pg_temp.exigir(x->>'estado'='resuelto','Fuente sin conciliar');
    perform pg_temp.exigir((select i.creado_por is not distinct from (x->>'creado_por')::uuid
      from crm.inversiones i where i.id=(x->>'inversion')::uuid),'Se perdió el creador histórico');
  end loop;
  perform pg_temp.exigir((select count(*)=1 and bool_and(finalizado_en is not null) from crm.inversion_backfill_lotes),'Acta incompleta');
`);

probar('Repetir el lote en otro orden devuelve el acta sin duplicar', `
  r:=private.inversion_historica_aplicar(lote,mapa);
  h:=pg_temp.foto_lotes();
  select jsonb_agg(value order by ord desc) into x from jsonb_array_elements(mapa) with ordinality t(value,ord);
  perform pg_temp.exigir(private.inversion_historica_aplicar(lote,x)=r,'El orden cambió la identidad del lote');
  perform pg_temp.exigir(pg_temp.foto_lotes()=h,'El reintento escribió');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,jsonb_build_array(mapa->0)),'P0409');
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',gen_random_uuid(),mapa),'40001');
`);

probar('Un censo nuevo reconoce lo resuelto y conserva sus filas exactas', `
  perform private.inversion_historica_aplicar(lote,mapa);
  h:=pg_temp.foto_f4();
  r:=private.inversion_historica_aplicar(gen_random_uuid(),pg_temp.mapa_base());
  perform pg_temp.exigir(not exists(select 1 from jsonb_array_elements(r->'fuentes') entrada where entrada->>'accion'<>'sin_cambios'),'Se reescribió un vínculo resuelto');
  perform pg_temp.exigir(pg_temp.foto_f4()=h,'Un enlace anterior cambió');
  perform pg_temp.exigir((select count(*)=2 from crm.inversion_backfill_lotes),'No se conservan ambas actas');
`);

probar('Un vínculo anterior sin principal completa solo su titularidad', `
  select id into ce from crm.cierres_externos where numero_transaccion='F4-BASE-qorilazo';
  x:=private.inversion_historica_estado('cierre',ce);
  v:=private.inversion_vincular_fuente((x->>'persona')::uuid,null,ce,(x->>'creado_por')::uuid,true);
  delete from crm.inversion_titulares where inversion_id=v and rol='principal';
  h:=pg_temp.foto_f4();
  x:=private.inversion_historica_estado('cierre',ce);
  perform pg_temp.exigir(x->>'estado'='titular_pendiente','No detectó el titular faltante');
  r:=private.inversion_historica_aplicar(lote,jsonb_build_array(x));
  perform pg_temp.exigir(r#>>'{fuentes,0,accion}'='titular_completado','No completó el titular');
  perform pg_temp.exigir((pg_temp.foto_f4()-'titulares')=(h-'titulares'),'Cambió algo además del titular');
`);

probar('Cierre sin identidad vincula solo el puntero documentado y su inversión', `
  select id into ce from crm.cierres_externos where numero_transaccion='F4-BASE-prodelco';
  perform set_config('crm.op_privilegiada','on',true);
  update crm.cierres_externos set inversionista_id=null where id=ce;
  perform set_config('crm.op_privilegiada','off',true);
  h:=pg_temp.foto_f4();
  select to_jsonb(fuente)-'inversionista_id' into f from crm.cierres_externos fuente where id=ce;
  x:=private.inversion_historica_estado('cierre',ce);
  perform pg_temp.exigir(x->>'estado'='pendiente' and x->>'fuente_persona' is null,'Fixture no pendiente');
  r:=private.inversion_historica_aplicar(lote,jsonb_build_array(x));
  perform pg_temp.exigir((pg_temp.foto_f4()-array['cierres','inversiones','titulares'])=(h-array['cierres','inversiones','titulares']),'Cambió otra fuente, identidad o PDF');
  perform pg_temp.exigir((select to_jsonb(fuente)-'inversionista_id'=f and fuente.inversionista_id=(x->>'persona')::uuid from crm.cierres_externos fuente where id=ce),'Se alteró contenido histórico');
  perform pg_temp.exigir(current_setting('crm.op_privilegiada')='off','El privilegio quedó elevado');
`);

probar('Un fallo después de dos enlaces revierte todo y permite recuperar el lote', `
  perform pg_temp.rechazar(format('select private.inversion_historica_aplicar(%L,%L::jsonb)',lote,mapa),'P0999');
  perform pg_temp.exigir(pg_temp.foto_f4()=inicial,'El fallo dejó fuentes o relaciones parciales');
  perform pg_temp.exigir((select count(*)=0 from crm.inversion_backfill_lotes),'El fallo dejó el acta');
  execute 'drop trigger f4_ensayo_fallo_historico on crm.inversiones';
  r:=private.inversion_historica_aplicar(lote,mapa);
  perform pg_temp.exigir(jsonb_array_length(r->'fuentes')=6,'No recuperó el mismo lote');
`, { antesDo: `
create function pg_temp.f4_fallar_historico() returns trigger language plpgsql as $f$
begin
  if new.contrato_id in (select id from _f4_fuentes_base where tipo='contrato')
     and (select count(*) from crm.inversiones where cierre_externo_id in
       (select id from _f4_fuentes_base where tipo='cierre'))=2 then
    raise exception 'Fallo deliberado después de dos vínculos' using errcode='P0999';
  end if;
  return new;
end;
$f$;
create trigger f4_ensayo_fallo_historico before insert on crm.inversiones
  for each row execute function pg_temp.f4_fallar_historico();
` });

probar('Las actas finalizadas son inmutables y una incompleta no puede confirmar', `
  perform private.inversion_historica_aplicar(lote,mapa);
  perform pg_temp.rechazar(format('update crm.inversion_backfill_lotes set resultado=%L::jsonb where id=%L','{}',lote),'P0409');
  perform pg_temp.rechazar(format('update crm.inversion_backfill_lotes set mapa=%L::jsonb where id=%L','[]',lote),'P0409');
  perform pg_temp.rechazar(format('delete from crm.inversion_backfill_lotes where id=%L',lote),'P0409');
  perform pg_temp.rechazar(format('insert into crm.inversion_backfill_lotes(id,hash_mapa,mapa) values(%L,%L,%L::jsonb); set constraints all immediate',
    gen_random_uuid(),repeat('0',64),'[]'),'23514');
`);

const resultado = { entorno: 'avancecorp-f4-bank', ejecucion, terminadoEn: new Date().toISOString(), pruebas,
  definiciones: definiciones.map(d => ({ nombre: d.nombre, sha256: sha(d.contenido) })),
  sha256Oraculo: sha(readFileSync(new URL(import.meta.url))), huellasAntesYDespues: antes,
  transaccionesRevertidas: true, objetosNuevosSinInstalar: true,
  limites: ['Prueba transaccional del lote administrativo; concurrencia entre sesiones todavía pendiente.',
    'Las fuentes son sintéticas y las fixtures se revierten; el pipeline F2 original todavía no se reconstruyó.',
    'La candidata de 34 funciones permanece igual. Estos borradores todavía no se integraron.',
    'Contenido PDF conservado; no se aprueba G4 ni se autoriza producción.'] };
guardar(`historicos-lote-${ejecucion}.json`, resultado);
writeFileSync(new URL(`../evidencia-f4/historicos-lote-${ejecucion}.json`, import.meta.url), JSON.stringify(resultado, null, 2) + '\n', { flag: 'wx' });
console.log(`Lote histórico F4: ${pruebas.length} grupos conformes; todo el ensayo revertido.`);
