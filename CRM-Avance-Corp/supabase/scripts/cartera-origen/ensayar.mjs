// Ensayo completo del filtro de origen en la copia local, a paridad con
// producción: gate analítico verde antes, equivalencia sin filtro (RPC y
// resumen general) para todos los actores, instalación con el gate en rojo por
// causa ajena (como está producción), instalación real, oráculo, reversa con sus
// guardas negativas y reinstalación. Nunca toca producción: `banco.mjs` fija el
// contenedor y la base.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar, objeto } from './banco.mjs';

const F9 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date)';
const F10 = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text)';
const MD5_F9 = '5d246e9518123c72352a958606853c35'; // producción, 16/09
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const sinTx = (s) => s.replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');
const migracion = leer('../../migrations/20260916220124_crm_cartera_filtro_origen.sql');
const cuerpo = sinTx(migracion);
const oraculo = leer('./test-cartera-origen.sql');
const oraculo13 = leer('../test-cartera-filtrada.sql');
const reversa = leer('./reversa.sql');
const cuerpoReversa = sinTx(reversa);

assert.equal(sql('select current_database()'), db);
const gate = () => sql('select private.assert_analitica_leads_citas()');
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const acl = (f) => sql(`select coalesce((select proacl::text from pg_proc where oid=to_regprocedure('${f}')),'-')`);
const rojo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok)`);
/** Ejecuta y EXIGE fallo con un mensaje concreto (todo dentro de una tx deshecha). */
function debeFallar(script, patron, motivo) {
  const r = ejecutar(`begin;${script}\nrollback;`);
  assert.notEqual(r.status, 0, `Debió fallar: ${motivo}`);
  assert.match(r.stderr, patron, `Falló por otra causa (${motivo}): ${r.stderr.slice(0, 300)}`);
}
assert.match(gate(), /^OK/, 'El gate analítico debe estar verde ANTES del ensayo');
assert.equal(md5Vivo(F9), MD5_F9, 'La copia debe partir de la función viva de producción');
const aclAntes = acl(F9);
assert.equal(rojo(), '', 'Sin contadores en rojo al empezar');

// Un contador crudo AJENO y sin declarar, como el que hoy tiene producción
// (crm.contrato_eliminar_auditado): pone el gate en rojo por causa ajena.
const rojoAjeno = `
create function crm.oraculo_rojo_ajeno_fn() returns integer language sql stable security definer set search_path='' as $r$
  select count(*)::integer from crm.leads where activo;
$r$;`;

// 1. Equivalencia sin filtro, actor por actor, en UNA transacción deshecha: la
//    función anterior renombrada a pg_temp responde igual que la nueva sin
//    p_origen (salvo la clave nueva `origen`, que llega nula) y el resumen
//    general —que la llama por nombre— responde igual antes y después.
const actores = objeto(`select coalesce(jsonb_agg(perfil_id),'[]') from (
  select perfil_id from crm.equipo where activo and private.rol_crm(perfil_id) is not null
  union select id from public.perfiles where rol='directorio' and activo) a`);
assert.ok(actores.length >= 5, 'Faltan actores para comparar');
const anterior = sql(`select pg_get_functiondef('${F9}'::regprocedure)`)
  .replace('crm.cartera_filtrada_fn', 'pg_temp.cartera_filtrada_anterior') + ';';
const comparaciones = [
  'p_limite=>50', "p_limite=>200,p_etapa=>'nuevo'", "p_limite=>10,p_texto=>'an'",
  "p_limite=>50,p_desde=>(now() at time zone 'America/Lima')::date-30,p_hasta=>(now() at time zone 'America/Lima')::date",
];
const listaActores = actores.map((a) => `'${a}'::uuid`).join(',');
const resumenAntes = `
create temporary table resumen_antes(actor uuid primary key, payload jsonb) on commit drop;
grant select, insert on resumen_antes to authenticated;
set local role authenticated;
do $antes$
declare v_actor uuid;
begin
  foreach v_actor in array array[${listaActores}] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    insert into resumen_antes select v_actor, crm.resumen_cartera_fn();
  end loop;
end;
$antes$;
reset role;`;
const equivalencia = `
set local role authenticated;
do $equivalencia$
declare v_actor uuid; a jsonb; b jsonb; n integer:=0; c text;
begin
  foreach v_actor in array array[${listaActores}] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    foreach c in array array[${comparaciones.map((c) => `$c$${c}$c$`).join(',')}] loop
      execute 'select pg_temp.cartera_filtrada_anterior('||c||')' into a;
      execute 'select crm.cartera_filtrada_fn('||c||')' into b;
      if b->'origen' is distinct from 'null'::jsonb or (b - 'origen') is distinct from a then
        raise exception 'Respuesta distinta para % con %: anterior % / nueva %',v_actor,c,a,b;
      end if;
      n:=n+1;
    end loop;
    select payload into a from resumen_antes where resumen_antes.actor=v_actor;
    b:=crm.resumen_cartera_fn();
    if a is distinct from b then
      raise exception 'Resumen general distinto para %: antes % / después %',v_actor,a,b;
    end if;
  end loop;
  raise notice 'Equivalencia sin filtro: % lecturas idénticas y % resúmenes idénticos para % actores',n,${actores.length},${actores.length};
end;
$equivalencia$;
reset role;`;
const ensayo = sql(`begin;${anterior}\n${resumenAntes}\n${cuerpo}\n${equivalencia}\nselect 'ENSAYO_DESHECHO';rollback;`);
assert.match(ensayo, /ENSAYO_DESHECHO/);
assert.equal(md5Vivo(F9), MD5_F9, 'El ensayo deshecho no dejó rastro');

// 2. Con el gate en ROJO por causa ajena (como producción hoy): la migración se
//    instala igual, conserva ese rojo tal cual y deja la firma nueva declarada.
const conRojo = sql(`begin;${rojoAjeno}
do $$ begin
  begin perform private.assert_analitica_leads_citas(); raise exception 'El gate no se puso en rojo';
  exception when others then if sqlerrm not like '%SIN declarar%oraculo_rojo_ajeno_fn%' then raise; end if; end;
end $$;
${cuerpo}
select (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok))
  ||' | '||(select (declarada and huella_ok)::text from private.contadores_crudos_leads_citas() where objeto like 'crm.cartera_filtrada_fn(%');
rollback;`);
assert.equal(conRojo, 'crm.oraculo_rojo_ajeno_fn() | true', 'Con rojo ajeno: instala, conserva el rojo y declara la firma nueva');
assert.equal(md5Vivo(F9), MD5_F9, 'El ensayo con rojo no dejó rastro');

// 3. Instalación real en la copia + gate + oráculo.
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras instalar');
assert.equal(md5Vivo(F9), '-', 'La firma de 9 desaparece');
assert.equal(acl(F10), aclAntes, 'ACL idéntica en la firma nueva');
assert.match(sql(oraculo), /CARTERA_ORIGEN_OK/);

// 4. Guardas de la reversa (P2 de Codex), cada una en su transacción deshecha:
//    sello incoherente, función de 10 args corregida después, y conservación
//    del rojo ajeno cuando existe.
debeFallar(`update private.analitica_lc_sello set sello='0000deadbeef' where id;\n${cuerpoReversa}`,
  /REVERSA: la lista de exenciones no coincide con su sello/, 'sello alterado por fuera');
debeFallar(`alter function ${F10} cost 250;\n${cuerpoReversa}`,
  /REVERSA: la funci.n de 10 argumentos no es la publicada/, 'función corregida después de la entrega');
const reversaConRojo = sql(`begin;${rojoAjeno}\n${cuerpoReversa}\nselect (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok))||' | '||coalesce(md5(pg_get_functiondef(to_regprocedure('${F9}'))),'-');rollback;`);
assert.equal(reversaConRojo, `crm.oraculo_rojo_ajeno_fn() | ${MD5_F9}`, 'Reversa con rojo ajeno: conserva el rojo y restaura la del 13/09');

// 5. Reversa real: vuelve la función del 13/09 byte a byte, el gate sigue verde y
//    el oráculo del 13/09 vuelve a pasar sobre ella.
sql(reversa);
assert.match(gate(), /^OK/, 'Gate analítico tras la reversa');
assert.equal(md5Vivo(F9), MD5_F9, 'Reversa: la función del 13/09 tal cual');
assert.equal(md5Vivo(F10), '-', 'Reversa: la firma de 10 desaparece');
assert.equal(acl(F9), aclAntes, 'Reversa: ACL original');
assert.match(sql(oraculo13), /CARTERA_FILTRADA_RLS_OK/);

// 6. Reinstalación: idempotencia del preflight sobre una base revertida.
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras reinstalar');
assert.match(sql(oraculo), /CARTERA_ORIGEN_OK/);
assert.equal(md5Vivo(F10), 'be33021420cd8ae2edbf58692b45e9eb', 'La definición instalada es la que la reversa espera');

writeFileSync(new URL('verificacion.json', import.meta.url), JSON.stringify({
  estado: 'PASS', banco: db, fecha: new Date().toISOString(),
  migracion_sha256: createHash('sha256').update(migracion).digest('hex'),
  reversa_sha256: createHash('sha256').update(reversa).digest('hex'),
  actores_comparados: actores.length, lecturas_por_actor: comparaciones.length, resumen_general_comparado: true,
  pasos: ['gate verde antes', 'equivalencia sin filtro (RPC + resumen general) deshecha',
    'instalación con rojo ajeno preexistente (deshecha)', 'instalación + gate + oráculo',
    'guardas de la reversa: sello alterado y función corregida rechazadas; rojo ajeno conservado',
    'reversa + gate + oráculo 13/09', 'reinstalación + gate + oráculo'],
}, null, 2) + '\n');
console.log(`PASS: equivalencia (${actores.length} actores × ${comparaciones.length} lecturas + resumen), rojo ajeno, instalación, oráculo, guardas de reversa, reversa y reinstalación en ${db}.`);
