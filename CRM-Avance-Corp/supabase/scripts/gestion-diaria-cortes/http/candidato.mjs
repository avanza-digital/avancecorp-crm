// Instalación/reversa exactas exclusivamente en el banco HTTP autorizado.
// El SQL de la migración permanece byte a byte intacto. La reversa sólo admite
// la semilla OFF original: no sirve después de publicar ninguna política.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { carpeta, sql, verificarBanco } from './banco.mjs';

const [modo,...otros] = process.argv.slice(2);
assert.ok(['--instalar','--revertir','--ensayar-atomicidad','--estado'].includes(modo) && otros.length===0);
verificarBanco();
const fuente = readFileSync(new URL('../../../migrations/20260921214018_crm_gestion_diaria_cortes.sql',import.meta.url),'utf8');
const sha256 = createHash('sha256').update(fuente).digest('hex');
assert.equal(sha256,'8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5');
const q = x => `'${String(x).replaceAll("'","''")}'`;
const firmas = [
  'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
  'private.gestion_diaria_equipo_core(date,uuid)','private.gestion_diaria_umbrales()',
  'private.assert_gestion_diaria_analista()','private.assert_gestion_diaria_equipo()','private.assert_gestion_diaria()',
];
const archivo = `${carpeta}/candidato-resguardo.json`;
const funciones = () => JSON.parse(sql(`select jsonb_agg(jsonb_build_object(
  'firma',f.firma,'definicion',pg_get_functiondef(p.oid),'md5',md5(pg_get_functiondef(p.oid)),
  'propietario',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'comentario',obj_description(p.oid,'pg_proc')) order by f.firma)
  from unnest(array[${firmas.map(q).join(',')}]) f(firma) join pg_proc p on p.oid=f.firma::regprocedure`));
const comentario = () => sql("select obj_description('crm.gestion_diaria_equipo_fn(date,uuid)'::regprocedure,'pg_proc')");
const instalada = () => sql("select to_regclass('crm.politica_gestion_diaria') is not null") === 't';
const gates = `select private.assert_gestion_diaria(); select private.assert_sla_nucleo();
  select private.assert_sla_operacion(); select private.assert_sla_comandos(); select private.assert_sla_avisos();`;
const politico = () => JSON.parse(sql("select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p"));
const huellasNegocio = () => {
  const tablas = JSON.parse(sql("select jsonb_agg(format('%I.%I',schemaname,tablename) order by schemaname,tablename) from pg_tables where schemaname in ('crm','public') and tablename not in ('politica_gestion_diaria','audit_log')"));
  return Object.fromEntries(tablas.map(t=>[t,sql(`select count(*)::text||':'||md5(coalesce(string_agg(to_jsonb(x)::text,E'\\n' order by to_jsonb(x)::text),'')) from ${t} x`)]));
};

if(modo==='--estado') {
  console.log(JSON.stringify({instalada:instalada(),sha256,...(instalada()?{politica:politico().map(p=>({version:p.version,activos:p.cortes_activos}))}:{})}));
} else if(modo==='--instalar' || modo==='--ensayar-atomicidad') {
  assert.equal(instalada(),false,'No reinstalar ni reemplazar una política existente');
  sql(gates);
  const antes=funciones();
  assert.equal(antes.length,6);
  if(existsSync(archivo)) {
    const previo=JSON.parse(readFileSync(archivo,'utf8'));
    assert.equal(previo.sha256,sha256);
    assert.deepEqual(antes,previo.antes,'La base cambió respecto del resguardo');
  }
  if(modo==='--ensayar-atomicidad') {
    const negocio = huellasNegocio();
    const audit = sql('select count(*) from public.audit_log');
    assert.match(fuente,/commit;\s*$/);
    // Callback: String.replace interpretaría $$ como un único $ en un string.
    assert.throws(()=>sql(fuente.replace(/commit;\s*$/, () =>
      "do $$ begin raise exception 'F43_FALLO_TRANSACCIONAL_SIMULADO'; end $$; commit;")),/F43_FALLO_TRANSACCIONAL_SIMULADO/);
    assert.equal(instalada(),false);
    assert.deepEqual(funciones(),antes);
    assert.deepEqual(huellasNegocio(),negocio);
    assert.equal(sql('select count(*) from public.audit_log'),audit);
    console.log('PASS: fallo antes del commit revierte candidato, negocio y auditoría íntegramente');
  } else {
    const resguardo = {sha256,antes,comentarioAntes:comentario()};
    writeFileSync(`${carpeta}/candidato-antes.json`,JSON.stringify(resguardo,null,2)+'\n',{mode:0o600});
    sql(fuente);
    resguardo.despues=funciones();
    resguardo.politica=politico();
    assert.equal(resguardo.politica.length,1);
    assert.equal(resguardo.politica[0].version,1);
    assert.equal(resguardo.politica[0].cortes_activos,false);
    writeFileSync(archivo,JSON.stringify(resguardo,null,2)+'\n',{mode:0o600});
    console.log('PASS: candidato exacto instalado sólo en el banco; política v1 OFF y gates íntegros');
  }
} else {
  assert.equal(instalada(),true,'No hay candidato que revertir');
  const r=JSON.parse(readFileSync(archivo,'utf8'));
  assert.equal(r.sha256,sha256);
  assert.deepEqual(funciones(),r.despues,'Drift de funciones: detener reversa');
  assert.deepEqual(politico(),r.politica,'Hay política nueva/cambiada: no borrar historia');
  assert.equal(r.politica.length,1);
  assert.equal(r.politica[0].version,1);
  assert.equal(r.politica[0].cortes_activos,false);
  const negocio=huellasNegocio();
  const audit=sql('select count(*) from public.audit_log');
  const guardas=r.despues.map(f=>`if md5(pg_get_functiondef(${q(f.firma)}::regprocedure))<>${q(f.md5)} then raise exception 'Drift durante reversa'; end if;`).join('\n');
  const reversa=`begin; set local lock_timeout='5s';
    do $destino$ begin
      if current_database()<>'postgres' or
        shobj_description((select oid from pg_database where datname=current_database()), 'pg_database')
        is distinct from 'BANCO SINTETICO gestion-diaria-f4-http / sin produccion' then
        raise exception 'Reversa exclusivamente para el banco local autorizado';
      end if;
    end $destino$;
    lock table crm.politica_gestion_diaria in access exclusive mode;
    do $$ begin
      if (select jsonb_agg(to_jsonb(p) order by version) from crm.politica_gestion_diaria p) is distinct from ${q(JSON.stringify(r.politica))}::jsonb then
        raise exception 'Hay política nueva/cambiada: no borrar historia'; end if;
      ${guardas}
      perform private.assert_gestion_diaria();
    end $$;
    ${r.antes.map(f=>f.definicion+';').join('\n')}
    drop function private.assert_gestion_diaria_cortes();
    drop function private.gestion_diaria_cortes(date,uuid[],timestamptz);
    drop function private.gestion_diaria_umbrales(timestamptz);
    drop function private.politica_gestion_diaria_vigente(timestamptz);
    drop table crm.politica_gestion_diaria;
    drop function private.trg_politica_gestion_diaria_insertar();
    comment on function crm.gestion_diaria_equipo_fn(date,uuid) is ${q(r.comentarioAntes)};
    ${gates}
    notify pgrst,'reload schema'; commit;`;
  writeFileSync(`${carpeta}/reversa-candidato-solo-local.sql`,reversa,{mode:0o600});
  sql(reversa);
  assert.equal(instalada(),false);
  assert.deepEqual(funciones(),r.antes);
  assert.equal(comentario(),r.comentarioAntes);
  assert.deepEqual(huellasNegocio(),negocio,'Negocio cambió durante la reversa');
  assert.equal(sql('select count(*) from public.audit_log'),audit,'No borrar ni reescribir la auditoría');
  console.log('PASS: eliminados sólo objetos nuevos F4 de semilla OFF; funciones/ACL/comentario previos exactos, negocio y auditoría conservados');
}
