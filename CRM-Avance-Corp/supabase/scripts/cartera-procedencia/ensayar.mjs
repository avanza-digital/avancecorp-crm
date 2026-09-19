// Ensayo completo de la PROCEDENCIA en Leads sobre la copia local, a paridad con
// producción: gate analítico verde antes, equivalencia sin filtro (RPC y resumen
// general) para todos los actores, instalación con el gate en rojo por causa
// ajena (como está producción), instalación real, oráculo, partición
// sistema+manual = todo para cada actor, reversa con sus guardas negativas y
// reinstalación. Genera reversa.sql y el registrador con las huellas medidas.
// Nunca toca producción: `banco.mjs` fija el contenedor y la base.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar, objeto } from './banco.mjs';
import { F10, F11, F10_LARGA, F11_LARGA, MD5_F10, HUELLA_F10, definicionF10, generarReversa } from './generar-reversa.mjs';
import { VERSION, NOMBRE, escribirRegistrador } from './generar-registrador.mjs';

const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const sinTx = (s) => s.replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');
const migracion = leer(`../../migrations/${VERSION}_${NOMBRE}.sql`);
const cuerpo = sinTx(migracion);
const oraculo = leer('./test-cartera-procedencia.sql');
const oraculo16 = leer('../cartera-origen/test-cartera-origen.sql');

assert.equal(sql('select current_database()'), db);
const gate = () => sql('select private.assert_analitica_leads_citas()');
const md5Vivo = (f) => sql(`select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))),'-')`);
const huella = (fLarga) => sql(`select coalesce((select huella from private.analitica_leads_citas_exenciones where objeto='${fLarga}'),'-')`);
const acl = (f) => sql(`select coalesce((select proacl::text from pg_proc where oid=to_regprocedure('${f}')),'-')`);
const rojo = () => sql(`select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok)`);
/** Ejecuta y EXIGE fallo con un mensaje concreto (todo dentro de una tx deshecha). */
function debeFallar(script, patron, motivo) {
  const r = ejecutar(`begin;${script}\nrollback;`);
  assert.notEqual(r.status, 0, `Debió fallar: ${motivo}`);
  assert.match(r.stderr, patron, `Falló por otra causa (${motivo}): ${r.stderr.slice(0, 300)}`);
}
assert.match(gate(), /^OK/, 'El gate analítico debe estar verde ANTES del ensayo');
assert.equal(md5Vivo(F10), MD5_F10, 'La copia debe partir de la función viva de producción (16/09)');
assert.equal(huella(F10_LARGA), HUELLA_F10, 'La declaración analítica de la firma de 10 es la de producción');
const aclAntes = acl(F10);
assert.equal(rojo(), '', 'Sin contadores en rojo al empezar');
const definicion10 = definicionF10();

// Un contador crudo AJENO y sin declarar, como el que hoy tiene producción
// (crm.contrato_eliminar_auditado): pone el gate en rojo por causa ajena.
const rojoAjeno = `
create function crm.oraculo_rojo_ajeno_fn() returns integer language sql stable security definer set search_path='' as $r$
  select count(*)::integer from crm.leads where activo;
$r$;`;

// 1. Equivalencia sin filtro, actor por actor, en UNA transacción deshecha: la
//    función anterior renombrada a pg_temp responde igual que la nueva sin
//    p_procedencia (salvo la clave nueva `procedencia`, nula, y las dos claves
//    nuevas por fila, que se quitan para comparar y se validan aparte), y el
//    resumen general —que la llama por nombre— responde igual antes y después.
const actores = objeto(`select coalesce(jsonb_agg(perfil_id),'[]') from (
  select perfil_id from crm.equipo where activo and private.rol_crm(perfil_id) is not null
  union select id from public.perfiles where rol='directorio' and activo) a`);
assert.ok(actores.length >= 5, 'Faltan actores para comparar');
const anterior = definicion10.replace('crm.cartera_filtrada_fn', 'pg_temp.cartera_filtrada_anterior') + ';';
const comparaciones = [
  'p_limite=>50', "p_limite=>200,p_etapa=>'nuevo'", "p_limite=>10,p_texto=>'an'", "p_limite=>50,p_origen=>'landing'",
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
declare v_actor uuid; a jsonb; b jsonb; b2 jsonb; n integer:=0; filas integer:=0; c text;
begin
  foreach v_actor in array array[${listaActores}] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    foreach c in array array[${comparaciones.map((c) => `$c$${c}$c$`).join(',')}] loop
      execute 'select pg_temp.cartera_filtrada_anterior('||c||')' into a;
      execute 'select crm.cartera_filtrada_fn('||c||')' into b;
      -- Toda fila trae las dos claves nuevas con forma válida; lo del sistema nunca tiene autor.
      if exists (select 1 from jsonb_array_elements(b->'items') i
          where not (i ? 'procedencia') or not (i ? 'cargado_por') or i->>'procedencia' not in ('sistema','manual')
             or (i->>'procedencia'='sistema' and i->'cargado_por' <> 'null'::jsonb)) then
        raise exception 'Fila sin procedencia válida para % con %: %',v_actor,c,b->'items';
      end if;
      filas:=filas+jsonb_array_length(b->'items');
      b2:=jsonb_set(b - 'procedencia','{items}',coalesce((select jsonb_agg((t.i - 'procedencia' - 'cargado_por') order by t.o)
        from jsonb_array_elements(b->'items') with ordinality as t(i,o)),'[]'::jsonb));
      if b->'procedencia' is distinct from 'null'::jsonb or b2 is distinct from a then
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
  raise notice 'Equivalencia sin filtro: % lecturas idénticas (% filas) y % resúmenes idénticos para % actores',n,filas,${actores.length},${actores.length};
end;
$equivalencia$;
reset role;`;
const ensayo = sql(`begin;${anterior}\n${resumenAntes}\n${cuerpo}\n${equivalencia}\nselect 'ENSAYO_DESHECHO';rollback;`);
assert.match(ensayo, /ENSAYO_DESHECHO/);
assert.equal(md5Vivo(F10), MD5_F10, 'El ensayo deshecho no dejó rastro');

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
assert.equal(md5Vivo(F10), MD5_F10, 'El ensayo con rojo no dejó rastro');

// 3. Instalación real en la copia + gate + oráculo + partición por actor.
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras instalar');
assert.equal(md5Vivo(F10), '-', 'La firma de 10 desaparece');
assert.equal(acl(F11), aclAntes, 'ACL idéntica en la firma nueva');
assert.match(sql(oraculo), /CARTERA_PROCEDENCIA_OK/);
const md5F11 = md5Vivo(F11);
const huellaF11 = huella(F11_LARGA);
assert.match(md5F11, /^[0-9a-f]{32}$/); assert.match(huellaF11, /^[0-9a-f]{32}$/);
assert.equal(sql(`select declarado_en::text from private.analitica_leads_citas_exenciones where objeto='${F11_LARGA}'`).slice(0, 10), '2026-09-13',
  'La declaración conserva su fecha original (se movió, no se recreó)');
// Sobre los datos reales de la copia: para cada actor, sistema + manual = todo
// (mismos totales que sin filtro) y ninguna fila cambia de bando entre lecturas.
const particion = sql(`begin;set local role authenticated;
do $particion$
declare v_actor uuid; t jsonb; s jsonb; m jsonb; n integer:=0;
begin
  foreach v_actor in array array[${listaActores}] loop
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    t:=crm.cartera_filtrada_fn(p_limite=>200); s:=crm.cartera_filtrada_fn(p_limite=>200,p_procedencia=>'sistema'); m:=crm.cartera_filtrada_fn(p_limite=>200,p_procedencia=>'manual');
    if (t#>>'{resumen,totales,vivos}')::int <> (s#>>'{resumen,totales,vivos}')::int + (m#>>'{resumen,totales,vivos}')::int
       or (t#>>'{resumen,capital,asignado,pen}')::numeric <> (s#>>'{resumen,capital,asignado,pen}')::numeric + (m#>>'{resumen,capital,asignado,pen}')::numeric
       or exists (select 1 from jsonb_array_elements(s->'items') i where i->>'procedencia'<>'sistema')
       or exists (select 1 from jsonb_array_elements(m->'items') i where i->>'procedencia'<>'manual')
       or (select count(*) from jsonb_array_elements(t->'items') i where i->>'procedencia'='manual') <> jsonb_array_length(m->'items') then
      raise exception 'La partición sistema+manual no reconstruye la cartera para %',v_actor;
    end if;
    n:=n+1;
  end loop;
  raise notice 'Partición sistema + manual = todo para % actores',n;
end;
$particion$;
reset role;select 'PARTICION_OK';rollback;`);
assert.match(particion, /PARTICION_OK/);

// Reversa y registrador GENERADOS con las huellas recién medidas.
const reversa = generarReversa({ md5F11, huellaF11, definicion: definicion10 });
writeFileSync(new URL('reversa.sql', import.meta.url), reversa);
const cuerpoReversa = sinTx(reversa);
const registrador = escribirRegistrador({ md5F11 });

// 4. Guardas de la reversa, cada una en su transacción deshecha: sello
//    incoherente, función de 11 args corregida después, y conservación del
//    rojo ajeno cuando existe.
debeFallar(`update private.analitica_lc_sello set sello='0000deadbeef' where id;\n${cuerpoReversa}`,
  /REVERSA: la lista de exenciones no coincide con su sello/, 'sello alterado por fuera');
debeFallar(`alter function ${F11} cost 250;\n${cuerpoReversa}`,
  /REVERSA: la funci.n de 11 argumentos no es la publicada/, 'función corregida después de la entrega');
const reversaConRojo = sql(`begin;${rojoAjeno}\n${cuerpoReversa}\nselect (select coalesce(string_agg(objeto,',' order by objeto),'') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok))||' | '||coalesce(md5(pg_get_functiondef(to_regprocedure('${F10}'))),'-');rollback;`);
assert.equal(reversaConRojo, `crm.oraculo_rojo_ajeno_fn() | ${MD5_F10}`, 'Reversa con rojo ajeno: conserva el rojo y restaura la del 16/09');

// 5. Reversa real: vuelve la función del 16/09 byte a byte, su declaración
//    original, el gate sigue verde y el oráculo del 16/09 vuelve a pasar.
sql(reversa);
assert.match(gate(), /^OK/, 'Gate analítico tras la reversa');
assert.equal(md5Vivo(F10), MD5_F10, 'Reversa: la función del 16/09 tal cual');
assert.equal(md5Vivo(F11), '-', 'Reversa: la firma de 11 desaparece');
assert.equal(acl(F10), aclAntes, 'Reversa: ACL original');
assert.equal(huella(F10_LARGA), HUELLA_F10, 'Reversa: declaración analítica original');
assert.match(sql(oraculo16), /CARTERA_ORIGEN_OK/);

// 6. Reinstalación: idempotencia del preflight sobre una base revertida y
//    definición determinista (la que la reversa y el registrador esperan).
sql(migracion);
assert.match(gate(), /^OK/, 'Gate analítico tras reinstalar');
assert.match(sql(oraculo), /CARTERA_PROCEDENCIA_OK/);
assert.equal(md5Vivo(F11), md5F11, 'La definición instalada es la que la reversa y el registrador esperan');
assert.equal(huella(F11_LARGA), huellaF11, 'La huella del censo es determinista');

writeFileSync(new URL('verificacion.json', import.meta.url), JSON.stringify({
  estado: 'PASS', banco: db, fecha: new Date().toISOString(),
  migracion: `${VERSION}_${NOMBRE}.sql`,
  migracion_sha256: createHash('sha256').update(migracion).digest('hex'),
  reversa_sha256: createHash('sha256').update(reversa).digest('hex'),
  registrador: registrador.SALIDA.split('/').pop(),
  md5_f10: MD5_F10, huella_f10: HUELLA_F10, md5_f11: md5F11, huella_f11: huellaF11,
  actores_comparados: actores.length, lecturas_por_actor: comparaciones.length, resumen_general_comparado: true,
  pasos: ['gate verde antes', 'equivalencia sin filtro (RPC + resumen general) deshecha, claves nuevas validadas por fila',
    'instalación con rojo ajeno preexistente (deshecha)', 'instalación + gate + oráculo + partición sistema/manual por actor',
    'reversa y registrador generados con las huellas medidas',
    'guardas de la reversa: sello alterado y función corregida rechazadas; rojo ajeno conservado',
    'reversa + gate + oráculo 16/09', 'reinstalación + gate + oráculo'],
}, null, 2) + '\n');
console.log(`PASS: equivalencia (${actores.length} actores × ${comparaciones.length} lecturas + resumen), rojo ajeno, instalación, oráculo, partición, guardas de reversa, reversa y reinstalación en ${db}. md5 F11 ${md5F11}`);
