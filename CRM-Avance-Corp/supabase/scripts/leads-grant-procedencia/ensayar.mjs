// Ensayo del grant por columna de alta_manual / creado_por sobre la copia local
// (misma base que cartera-procedencia, a paridad con producción en ACL: relacl y
// attacl medidos el 19/09). Prueba lo que el grant VALE, no solo que se aplique:
// con el ACL de tabla retirado (en transacción deshecha), las dos columnas dejan
// de leerse ANTES de la migración y siguen leyéndose DESPUÉS. Nunca toca
// producción: `banco.mjs` fija contenedor y base. Genera el registrador.
import { readFileSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { db, sql, ejecutar } from '../cartera-procedencia/banco.mjs';

const VERSION = '20260919211105', NOMBRE = 'crm_leads_grant_columna_procedencia';
const RELACL_PROD = '{postgres=arwdDxtm/postgres,authenticated=rw/postgres,service_role=arwd/postgres}';
const ATTACL_ESPERADA = '{authenticated=r/postgres,service_role=r/postgres}';
const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const sinTx = (s) => s.replace(/^begin;\n/m, '').replace(/^commit;\s*$/m, '');
const migracion = leer(`../../migrations/${VERSION}_${NOMBRE}.sql`);
const cuerpo = sinTx(migracion);
const reversa = leer('./reversa.sql');
const cuerpoReversa = sinTx(reversa);

assert.equal(sql('select current_database()'), db);
const relacl = () => sql(`select relacl::text from pg_class where oid='crm.leads'::regclass`);
const attacl = (c) => sql(`select coalesce(attacl::text,'NULL') from pg_attribute where attrelid='crm.leads'::regclass and attname='${c}'`);
const puede = (rol, c) => sql(`select has_column_privilege('${rol}','crm.leads','${c}','SELECT')`);
function debeFallar(script, patron, motivo) {
  const r = ejecutar(`begin;${script}\nrollback;`);
  assert.notEqual(r.status, 0, `Debió fallar: ${motivo}`);
  assert.match(r.stderr, patron, `Falló por otra causa (${motivo}): ${r.stderr.slice(0, 300)}`);
}

// 0. Paridad con producción: ACL de tabla y columnas sin ACL propia. Si una
//    corrida anterior dejó el grant puesto, se retira con la reversa vigente
//    (así el ensayo es repetible y la reversa se ejercita una vez más).
assert.equal(relacl(), RELACL_PROD, 'El ACL de tabla de la copia debe ser el de producción');
if (attacl('alta_manual') !== 'NULL' || attacl('creado_por') !== 'NULL') sql(reversa);
assert.equal(attacl('alta_manual'), 'NULL'); assert.equal(attacl('creado_por'), 'NULL');
assert.equal(attacl('tenencia_desde'), ATTACL_ESPERADA, 'El molde (tenencia_desde) está como en producción');
assert.equal(puede('anon', 'alta_manual'), 'f');
const otrasAntes = sql(`select jsonb_object_agg(attname, attacl::text)::text from pg_attribute where attrelid='crm.leads'::regclass and attnum>0 and not attisdropped and coalesce(cardinality(attacl),0)>0`);

// 1. HECHO medido (PG 17, 19/09), no folclore: un REVOKE de TABLA arrastra las
//    ACL por columna del mismo privilegio (tenencia_desde pierde su `r`). Así que
//    el grant por columna NO es una red contra «alguien revoca el grant de
//    tabla»: su valor es convención, registro y paridad con PostgREST. Se deja
//    asertado para que nadie vuelva a prometer lo contrario. Transacción deshecha.
const cascada = sql(`begin;revoke select on crm.leads from authenticated;
select coalesce((select attacl::text from pg_attribute where attrelid='crm.leads'::regclass and attname='tenencia_desde'),'NULL')
  ||' '||has_column_privilege('authenticated','crm.leads','tenencia_desde','SELECT')::text
  ||' '||has_column_privilege('authenticated','crm.leads','alta_manual','SELECT')::text;rollback;`);
assert.equal(cascada, '{service_role=r/postgres} false false', 'El REVOKE de tabla arrastra la ACL por columna (semántica de PostgreSQL)');
assert.equal(relacl(), RELACL_PROD, 'El mutante se deshizo');

// 2. Instalación deshecha: preflight + grant + postflight pasan y no queda rastro.
const ensayo = sql(`begin;${cuerpo}\nselect 'ENSAYO_DESHECHO';rollback;`);
assert.match(ensayo, /ENSAYO_DESHECHO/);
assert.equal(attacl('alta_manual'), 'NULL', 'El ensayo deshecho no dejó rastro');

// 3. Guarda del preflight: con la ACL ya puesta, no se instala dos veces a ciegas.
debeFallar(`grant select (alta_manual) on crm.leads to authenticated;\n${cuerpo}`,
  /PREFLIGHT: alta_manual \/ creado_por ya tienen ACL por columna/, 'ACL previa');

// 4. Instalación real.
sql(migracion);
assert.equal(attacl('alta_manual'), ATTACL_ESPERADA); assert.equal(attacl('creado_por'), ATTACL_ESPERADA);
assert.equal(relacl(), RELACL_PROD, 'El ACL de tabla no cambia');
assert.equal(puede('anon', 'alta_manual'), 'f'); assert.equal(puede('anon', 'creado_por'), 'f');
const otrasDespues = sql(`select jsonb_object_agg(attname, attacl::text)::text from pg_attribute where attrelid='crm.leads'::regclass and attnum>0 and not attisdropped and coalesce(cardinality(attacl),0)>0 and attname not in ('alta_manual','creado_por')`);
assert.equal(otrasDespues, otrasAntes, 'Las demás ACL por columna quedan intactas');

// 5. Lo que SÍ garantiza el grant: si alguien pasa a privilegios por columna
//    (revoke de tabla + grant columna a columna), estas dos quedan en la lista
//    que hay que reponer, igual que tenencia_desde. Se simula ese cierre y se
//    reponen SOLO las columnas que hoy tienen ACL propia: la RPC invoker sigue
//    fallando (necesita muchas más), pero las dos columnas se leen. Deshecho.
const cierre = sql(`begin;revoke select on crm.leads from authenticated;
grant select (alta_manual, creado_por, tenencia_desde) on crm.leads to authenticated;
select has_column_privilege('authenticated','crm.leads','alta_manual','SELECT')::text||' '||has_column_privilege('authenticated','crm.leads','creado_por','SELECT')::text||' '||has_column_privilege('authenticated','crm.leads','nombre_completo','SELECT')::text;rollback;`);
assert.equal(cierre, 'true true false', 'Con privilegios por columna, las dos entran en la lista a reponer');
assert.equal(relacl(), RELACL_PROD, 'El cierre simulado se deshizo');

// 6. Oráculo funcional como un analista real: lee las columnas y la RPC invoker responde.
const actor = sql(`select perfil_id from crm.equipo where activo and rol_crm='vendedor' limit 1`);
assert.match(actor, /^[0-9a-f-]{36}$/, 'Hace falta un analista en la copia');
const lectura = sql(`begin;set local request.jwt.claim.sub='${actor}';set local role authenticated;
select (select count(*) from (select alta_manual, creado_por from crm.leads limit 5) t)::text||' '||(crm.cartera_filtrada_fn(p_limite=>1)->'items'->0 ? 'procedencia')::text;reset role;rollback;`);
assert.match(lectura, /^\d+ (true|false)$/, `Lectura como analista: ${lectura}`);

// 7. Reversa real + guardas: vuelve a NULL y sigue legible por tabla. Con el
//    ACL de tabla cerrado, la cascada ya vació la ACL por columna y la reversa
//    se niega porque no encuentra lo publicado (deshecho).
debeFallar(`revoke select on crm.leads from authenticated;\n${cuerpoReversa}`,
  /REVERSA: la ACL por columna de alta_manual no es la publicada/, 'reversa con el ACL de tabla cerrado');
sql(reversa);
assert.equal(attacl('alta_manual'), 'NULL'); assert.equal(attacl('creado_por'), 'NULL');
assert.equal(relacl(), RELACL_PROD); assert.equal(puede('authenticated', 'alta_manual'), 't');
debeFallar(cuerpoReversa, /REVERSA: la ACL por columna de alta_manual no es la publicada/, 'reversa sin nada que revertir');

// 8. Reinstalación: idempotencia del preflight sobre una base revertida.
sql(migracion);
assert.equal(attacl('alta_manual'), ATTACL_ESPERADA); assert.equal(attacl('creado_por'), ATTACL_ESPERADA);

// Registrador fail-closed (mismo patrón de la casa): PIN = las dos ACL por columna.
const tag = '$mig_grant_proc$', tagReg = '$reg_grant_proc$';
assert.ok(!migracion.includes(tag) && !migracion.includes(tagReg));
const registrador = `-- Registra ${VERSION} (${NOMBRE}) CON su cuerpo — fail-closed.
-- GENERADO por supabase/scripts/leads-grant-procedencia/ensayar.mjs leyendo la
-- migración del archivo: no editar a mano; regenerar. PRIMERO aplicar la migración
-- con \`db query --linked --file\`, DESPUÉS este registrador.
do ${tagReg}
declare v_n int; v_cuerpo text;
begin
  v_cuerpo := ${tag}${migracion}${tag};
  -- 1) PIN: la ACL por columna publicada está puesta tal cual.
  if (select coalesce(attacl::text,'') from pg_attribute where attrelid='crm.leads'::regclass and attname='alta_manual') <> '${ATTACL_ESPERADA}'
     or (select coalesce(attacl::text,'') from pg_attribute where attrelid='crm.leads'::regclass and attname='creado_por') <> '${ATTACL_ESPERADA}' then
    raise exception 'registrar grant procedencia: la migración ${VERSION} no está aplicada tal cual — aplicarla antes de registrar';
  end if;
  -- 2) La versión no puede existir con OTRO cuerpo.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and statements is not null
     and (cardinality(statements) <> 1 or statements[1] <> v_cuerpo);
  if v_n > 0 then
    raise exception 'registrar grant procedencia: la versión ${VERSION} existe con OTRO cuerpo — investigar antes de tocar';
  end if;
  -- 3) Registro (idempotente).
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('${VERSION}', '${NOMBRE}', array[v_cuerpo])
  on conflict (version) do nothing;
  -- 4) RELECTURA fail-closed.
  select count(*) into v_n from supabase_migrations.schema_migrations
   where version = '${VERSION}' and name = '${NOMBRE}'
     and cardinality(statements) = 1 and statements[1] = v_cuerpo;
  if v_n <> 1 then
    raise exception 'registrar grant procedencia: la relectura no encontró la fila exacta';
  end if;
end ${tagReg};
`;
writeFileSync(new URL(`../registrar-${VERSION}.sql`, import.meta.url), registrador);

writeFileSync(new URL('verificacion.json', import.meta.url), JSON.stringify({
  estado: 'PASS', banco: db, fecha: new Date().toISOString(),
  migracion: `${VERSION}_${NOMBRE}.sql`,
  migracion_sha256: createHash('sha256').update(migracion).digest('hex'),
  reversa_sha256: createHash('sha256').update(reversa).digest('hex'),
  registrador: `registrar-${VERSION}.sql`,
  relacl: RELACL_PROD, attacl: ATTACL_ESPERADA, actor_oraculo: 'analista activo de la copia',
  hallazgo: 'REVOKE SELECT ON TABLE arrastra las ACL por columna del mismo privilegio (PG 17): el grant por columna es convención y registro, no una red contra el revoke de tabla',
  pasos: ['paridad de ACL con producción', 'hecho: el revoke de tabla arrastra la ACL por columna',
    'instalación deshecha', 'guarda del preflight (ACL previa)', 'instalación + ACL exacta + anon sin lectura + otras intactas',
    'cierre simulado a privilegios por columna: las dos entran en la lista a reponer',
    'oráculo como analista (select directo + RPC invoker)', 'guardas de la reversa + reversa + reinstalación'],
}, null, 2) + '\n');
console.log(`PASS: grant por columna ensayado en ${db}; registrador escrito.`);
