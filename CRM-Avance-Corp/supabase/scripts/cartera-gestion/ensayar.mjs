#!/usr/bin/env node
// Ensayo completo de 20261001154153_crm_cartera_filtro_gestion en el banco Docker propio.
// Nunca toca producción (`banco.mjs` fija el contenedor). Repetible: si el banco ya tiene la
// migración, primero la revierte con reversa.sql y vuelve a empezar.
//
// Mide ANTES y DESPUÉS, y prueba que cada defensa falla cuando debe:
//   antes  → gate analítico, anclas, control (migración + oráculo en transacción deshecha),
//            igualdad vieja/nueva y `resumen_cartera_fn` en la misma sesión, rojo ajeno,
//            mutantes del preflight, del postflight y de la lógica;
//   aplica → como `postgres`, en UN mensaje (igual que `supabase db query --file`);
//   después→ oráculo, igualdad y rendimiento con volumen, guardas de la reversa, reversa real
//            (vuelve la huella 7169d942…), reaplicación, registrador y acreditación.
// Escribe reversa.sql, registrar.sql y verificacion.json.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { contenedor, ejecutar, sql, crudo, debeFallar, sinTx, deshecho } from './banco.mjs';
import {
  VERSION, NOMBRE, F12, F13, F12_LARGA, F13_LARGA, MD5_F12, MD5_PROSRC_F12, HUELLA_F12, generarReversa,
} from './generar-reversa.mjs';
import { generarRegistrador, RUTA_MIGRACION } from './generar-registrador.mjs';

const leer = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');
const escribir = (rel, texto) => writeFileSync(new URL(rel, import.meta.url), texto);
const md5 = (texto) => createHash('md5').update(texto, 'utf8').digest('hex');
const sha256 = (texto) => createHash('sha256').update(texto, 'utf8').digest('hex');

const migracion = readFileSync(RUTA_MIGRACION, 'utf8');
const cuerpoMigracion = sinTx(migracion);
const oraculo = leer('./test-cartera-gestion.sql');
const cuerpoOraculo = sinTx(oraculo);
const volumen = leer('./volumen.sql');
const igualdad = leer('./igualdad.sql');
const rendimiento = leer('./rendimiento.sql');
const particionVolumen = leer('./particion-volumen.sql');
const acreditar = leer('./acreditar.sql');

// ── Lecturas del estado del banco (todas con search_path vacío) ───────────────
const P = "set search_path = '';";
const md5Viva = (f) => sql(`${P} select coalesce(md5(pg_get_functiondef(to_regprocedure('${f}'))), '-')`);
const gate = () => sql('select private.assert_analitica_leads_citas()');
const selloVigente = () => sql('select ((select sello from private.analitica_lc_sello where id) = private.huella_exenciones_analitica_lc())::text') === 'true';
const exencion = (larga) => JSON.parse(sql(`select coalesce((select to_jsonb(e) from private.analitica_leads_citas_exenciones e where e.objeto = '${larga}'), 'null'::jsonb)::text`));
const contrato = (f) => sql(`${P} select coalesce((select proowner::regrole::text || ' | definer=' || prosecdef::text || ' | ' || provolatile::text || ' | ' || array_to_string(proconfig, ',') || ' | ' || proacl::text from pg_proc where oid = to_regprocedure('${f}')), '-')`);
const comentario = (f) => sql(`${P} select coalesce(obj_description(to_regprocedure('${f}'), 'pg_proc'), '-')`);
const censoRojo = () => sql(`select coalesce(string_agg(objeto, ',' order by objeto), '(ninguno)') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok)`);
const md5Resumen = () => sql(`${P} select md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure))`);
const filasDeDatos = () => sql('select (select count(*) from crm.leads) + (select count(*) from public.perfiles) + (select count(*) from crm.actividades) + (select count(*) from crm.equipo)');
const foto = (f, larga) => ({ md5: md5Viva(f), contrato: contrato(f), comentario: comentario(f), exencion: exencion(larga), sello_vigente: selloVigente(), gate: gate(), censo_rojo: censoRojo(), resumen_md5: md5Resumen() });

const evidencia = { estado: 'EN CURSO', banco: contenedor, fecha: new Date().toISOString(), migracion: `${VERSION}_${NOMBRE}.sql`, pasos: [] };
const anotar = (paso, resultado, detalle = {}) => {
  evidencia.pasos.push({ paso, resultado, ...detalle });
  console.log(`${resultado.padEnd(4)} ${paso}${detalle.resumen ? ' · ' + detalle.resumen : ''}`);
};
/** Reemplazo que EXIGE una sola coincidencia: un mutante que no muta sería un verde falso. */
const mutar = (texto, de, a) => {
  assert.equal(texto.split(de).length - 1, 1, `El mutante no encuentra su blanco exactamente una vez: ${de.slice(0, 80)}`);
  return texto.replace(de, () => a);
};

// ── 0 · Preparación ───────────────────────────────────────────────────────────
assert.equal(sql('select current_database()'), 'postgres');
if (md5Viva(F13) !== '-') {
  // Repetición: el banco quedó con la migración. Se vuelve al punto de partida con la reversa.
  sql(leer('./reversa.sql'), { unMensaje: true });
  sql(`delete from supabase_migrations.schema_migrations where version = '${VERSION}'`);
  anotar('0 · banco con la migración puesta: revertida para empezar de cero', 'OK');
}
assert.equal(md5Viva(F12), MD5_F12, 'El banco no parte de la función viva de producción (md5 de pg_get_functiondef con search_path vacío)');
assert.equal(filasDeDatos(), '0', 'El banco tiene leads, perfiles, equipo o actividades: este ensayo cuenta sobre un banco sin datos');
if (sql('select count(*) from private.analitica_leads_citas_exenciones') === '0') {
  sql(leer('./siembra-control-banco.sql'));
  anotar('0 · siembra de control (trinquete analítico) en el banco recién montado', 'OK');
}
// La definición viva de 12 argumentos, TAL CUAL: es lo que la reversa reinstala y contra lo
// que se compara la nueva. Su md5, calculado aquí byte a byte, es el ancla de producción.
const definicion12 = crudo(`${P} select pg_get_functiondef(to_regprocedure('${F12}'))`);
assert.equal(md5(definicion12), MD5_F12, 'La definición copiada no es byte a byte la de producción');
assert.equal(sql(`select md5(prosrc) from pg_proc where oid = to_regprocedure('${F12}')`), MD5_PROSRC_F12);
const anteriorTemporal = mutar(definicion12, 'FUNCTION crm.cartera_filtrada_fn(', 'FUNCTION pg_temp.cartera_filtrada_anterior(').trimEnd()
  + ';\ngrant execute on function pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) to authenticated;\n';

// ── 1 · ANTES ─────────────────────────────────────────────────────────────────
const antes = foto(F12, F12_LARGA);
assert.match(antes.gate, /^OK/, 'El gate analítico debe estar verde antes de empezar');
assert.ok(antes.sello_vigente);
assert.equal(antes.exencion.huella, HUELLA_F12);
assert.equal(antes.exencion.clase, 'operativo');
anotar('1 · ANTES: función viva, gate analítico, sello y declaración', 'PASS', { resumen: `md5 ${antes.md5} · ${antes.gate.slice(0, 60)}…`, antes });
{
  const r = ejecutar(acreditar);
  assert.notEqual(r.status, 0, 'acreditar.sql debe terminar SIEMPRE en raise');
  assert.match(r.stderr, /ESTADO: ANTES de publicar/);
  assert.match(r.stderr, /VEREDICTO: todas las anclas coinciden: la migración pasaría su preflight/);
  assert.doesNotMatch(r.stderr, /\[DIFERENTE\]/);
  anotar('1 · acreditar.sql (solo lectura) en estado ANTES', 'PASS', { resumen: 'todas las anclas coinciden; termina en raise' });
}

// ── 2 · Control: migración + oráculo en UNA transacción deshecha ─────────────
const okOraculo = (salida) => {
  const m = salida.match(/CARTERA_GESTION_OK (\d+)\/(\d+)/);
  assert.ok(m && m[1] === m[2] && Number(m[1]) > 50, `El oráculo no pasó: ${salida.slice(-400)}`);
  return Number(m[1]);
};
const medirNueva = `select 'NUEVA ' || md5(pg_get_functiondef(to_regprocedure('${F13}'))) || ' '
  || (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = '${F13_LARGA}');`;
const salidaControl = sql(deshecho(cuerpoMigracion, medirNueva, cuerpoOraculo));
const aserciones = okOraculo(salidaControl);
const [, md5F13, huellaF13] = salidaControl.match(/^NUEVA ([0-9a-f]{32}) ([0-9a-f]{32})$/m);
assert.equal(md5Viva(F12), MD5_F12, 'El control deshecho dejó rastro');
anotar('2 · control: migración + oráculo en transacción deshecha', 'PASS', { resumen: `${aserciones}/${aserciones} aserciones` });
// La reversa se escribe ANTES de aplicar de verdad (con lo medido en el control): si algo
// fallara después, el banco nunca queda con la migración puesta y sin camino de vuelta.
const reversa = generarReversa({ definicion12, md5F13, huellaF13 });
escribir('./reversa.sql', reversa);
const cuerpoReversa = sinTx(reversa);

// Cada ensayo con volumen se deshace y deja filas muertas e índices hinchados. Se limpian
// antes de cada uno (vacuum + reindex; las tablas están vacías) para que el tamaño físico —y con
// él los costes y el plan— no dependa de cuántas veces se corrió: índices compactos, como los
// de una base en uso normal.
const limpiarFilasMuertas = () => sql(['crm.leads', 'crm.actividades', 'crm.equipo', 'crm.lead_asignaciones', 'public.perfiles']
  .map((tabla) => `vacuum ${tabla};\nreindex table ${tabla};`).join('\n'));

// ── 3 · Igualdad vieja/nueva y resumen general, misma sesión, deshecho ───────
const actoresVolumen = [1, 2, 3, 11, 12, 101, 102, 107];
const fijarActor = "perform set_config('request.jwt.claim.sub', pg_temp.vactor(a)::text, true), set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(a), 'role', 'authenticated')::text, true);";
const resumenAntes = `
create temporary table resumen_antes (actor integer primary key, payload jsonb) on commit drop;
grant select, insert on resumen_antes to authenticated;
set local role authenticated;
do $antes$
declare a integer;
begin
  foreach a in array array[${actoresVolumen}] loop
    ${fijarActor}
    insert into pg_temp.resumen_antes values (a, crm.resumen_cartera_fn());
  end loop;
end;
$antes$;
reset role;`;
const resumenDespues = `
set local role authenticated;
do $despues$
declare a integer; iguales integer := 0;
begin
  foreach a in array array[${actoresVolumen}] loop
    ${fijarActor}
    if (select r.payload from pg_temp.resumen_antes r where r.actor = a) = crm.resumen_cartera_fn() then iguales := iguales + 1; end if;
  end loop;
  perform set_config('ensayo.resumen', iguales || '/' || ${actoresVolumen.length}, true);
end;
$despues$;
reset role;
select 'RESUMEN ' || current_setting('ensayo.resumen');`;
const leerIgualdad = (salida) => {
  const m = salida.match(/^IGUALDAD (\{.*\})$/m);
  assert.ok(m, `Sin resultado de igualdad: ${salida.slice(-300)}`);
  return JSON.parse(m[1]);
};
const leerVolumen = (salida) => JSON.parse(salida.match(/^VOLUMEN (\{.*\})$/m)[1]);
/** Resultado de particion-volumen.sql: ¿lo servido por cursor es EXACTAMENTE lo esperado? */
function leerParticion(salida) {
  const p = JSON.parse(salida.match(/^PARTICION (\{.*\})$/m)[1]);
  const descuadres = p.por_actor.reduce((n, x) => n + x.repetidas + x.perdidas + x.de_mas, 0) + p.en_las_dos_mitades;
  const cuadra = descuadres === 0 && p.por_actor.every((x) => x.esperadas === x.servidas && x.totales_distintos === 1 && x.total_declarado === x.esperadas);
  return { ...p, descuadres, cuadra };
}
let datosVolumen;
{
  limpiarFilasMuertas();
  const salida = sql(deshecho(anteriorTemporal, volumen, resumenAntes, cuerpoMigracion, igualdad, resumenDespues));
  const ig = leerIgualdad(salida);
  datosVolumen = leerVolumen(salida);
  assert.equal(ig.iguales, ig.total, `Respuestas distintas con p_gestion nulo: ${ig.distintas}`);
  assert.ok(ig.total >= 200 && ig.filas_comparadas > 1000 && ig.respuestas_con_datos > 50, 'Igualdad vacía: no comparó datos');
  assert.match(salida, new RegExp(`^RESUMEN ${actoresVolumen.length}/${actoresVolumen.length}$`, 'm'), 'resumen_cartera_fn cambió tras la migración');
  assert.equal(md5Viva(F12), MD5_F12, 'El ensayo de igualdad deshecho dejó rastro');
  anotar('3 · igualdad: nueva sin p_gestion (omitido y null) = vieja, y resumen_cartera_fn antes = después en la misma sesión', 'PASS', {
    resumen: `${ig.iguales}/${ig.total} respuestas idénticas (${ig.actores} actores × ${ig.llamadas} llamadas × 2), ${ig.filas_comparadas} filas; resumen ${actoresVolumen.length}/${actoresVolumen.length}`,
    igualdad: ig, volumen: datosVolumen });
}

// ── 4 · Con el gate en rojo por causa AJENA: instala igual y conserva ese rojo ─
const rojoAjeno = `
create function crm.oraculo_rojo_ajeno_fn() returns integer language sql stable security definer set search_path = '' as
  $r$ select count(*)::integer from crm.leads where activo $r$;
do $g$ begin
  begin perform private.assert_analitica_leads_citas(); raise exception 'El gate no se puso en rojo';
  exception when others then if position('oraculo_rojo_ajeno_fn' in sqlerrm) = 0 then raise; end if; end;
end $g$;`;
const leerRojo = (firma) => `select 'ROJO ' || (select coalesce(string_agg(objeto, ',' order by objeto), '') from private.contadores_crudos_leads_citas() where not (declarada and huella_ok))
  || ' | ' || coalesce((select (declarada and huella_ok)::text from private.contadores_crudos_leads_citas() where objeto = '${firma}'), 'sin declarar');`;
assert.match(sql(deshecho(rojoAjeno, cuerpoMigracion, leerRojo(F13_LARGA))), /^ROJO crm\.oraculo_rojo_ajeno_fn\(\) \| true$/m);
anotar('4 · con un contador ajeno en rojo: instala, conserva ese rojo y declara la firma nueva', 'PASS');

// ── 5 · Mutantes del PREFLIGHT: cada guarda rechaza lo que debe ──────────────
const mutantesPreflight = [
  ['la función viva cambió (otro md5)', `alter function ${F12} cost 250;`, /PREFLIGHT: cartera_filtrada_fn no coincide/],
  ['hay una segunda firma', `create function crm.cartera_filtrada_fn(p_solo integer) returns jsonb language sql stable as $f$ select '{}'::jsonb $f$;`, /PREFLIGHT: cartera_filtrada_fn no coincide/],
  ['el sello de la lista no cuadra', `update private.analitica_lc_sello set sello = '0000deadbeef' where id;`, /PREFLIGHT: la declaracion analitica/],
  ['la huella declarada caducó', `update private.analitica_leads_citas_exenciones set huella = md5('otra') where objeto = '${F12_LARGA}';
    update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;`, /PREFLIGHT: la declaracion analitica/],
  ['la declaración dejó de ser de inventario', `update private.analitica_leads_citas_exenciones set clase = 'analitica' where objeto = '${F12_LARGA}';
    update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;`, /PREFLIGHT: la declaracion analitica/],
  ['el trigger de tenencia está apagado', `alter table crm.leads disable trigger trg_leads_zzz_tenencia_desde;`, /PREFLIGHT: el sello de tenencia_desde/],
  ['el trigger de tenencia cambió de cuerpo', `create or replace function private.trg_leads_tenencia_desde() returns trigger language plpgsql security definer set search_path to 'pg_catalog' as $f$ begin return new; end $f$;`, /PREFLIGHT: el sello de tenencia_desde/],
  ['actividades ganó otra policy de lectura', `create policy gestion_mutante on crm.actividades for select to authenticated using (true);`, /otras permisivas de lectura/],
  // Guarda 5: el reloj y la integridad de la ACTIVIDAD.
  ['el trigger que sella creado_en (trg_01) está apagado', `alter table crm.actividades disable trigger trg_01_gestion_lead_serializada;`, /PREFLIGHT: la fuente de gestiones/],
  ['el trigger que reserva el resultado de llamada (trg_00) cambió de cuerpo', `create or replace function private.trg_actividades_resultado_solo_nucleo() returns trigger language plpgsql security definer set search_path to '' as $f$ begin return new; end $f$;`, /PREFLIGHT: la fuente de gestiones/],
  ['authenticated recibe UPDATE sobre una columna de actividades', `grant update (metadata) on crm.actividades to authenticated;`, /PREFLIGHT: la fuente de gestiones/],
  // A la permisiva ALL la caza antes la guarda 3 (también abre la lectura); las de abajo solo la 5.
  ['aparece una policy permisiva ALL en actividades', `create policy gestion_mutante_all on crm.actividades for all to authenticated using (true) with check (true);`, /otras permisivas de lectura|PREFLIGHT: la fuente de gestiones/],
  ['aparece una policy de UPDATE en actividades', `create policy gestion_mutante_upd on crm.actividades for update to authenticated using (true) with check (true);`, /PREFLIGHT: la fuente de gestiones/],
  ['aparece una segunda policy de INSERT en actividades', `create policy gestion_mutante_ins on crm.actividades for insert to authenticated with check (true);`, /PREFLIGHT: la fuente de gestiones/],
  ['aparece una restrictiva de SELECT en actividades', `create policy gestion_mutante_restrictiva on crm.actividades as restrictive for select to authenticated using (creado_por = (select auth.uid()));`, /PREFLIGHT: la fuente de gestiones/],
  ['el gate restrictivo de leads cambió de expresión', `alter policy crm_actor_activo_gate on crm.leads using (true);`, /PREFLIGHT: la fuente de gestiones/],
  ['RLS apagada en actividades', `alter table crm.actividades disable row level security;`, /PREFLIGHT: la fuente de gestiones/],
  // Un mutante por cláusula restante de la guarda 5 (una cláusula sin mutante es una defensa sin probar).
  ['trg_01 recreado con un WHEN que lo neutraliza (mismo nombre, misma función)', `drop trigger trg_01_gestion_lead_serializada on crm.actividades;
    create trigger trg_01_gestion_lead_serializada before insert on crm.actividades for each row when (new.lead_id is null) execute function private.trg_gestion_lead_serializada();`, /PREFLIGHT: la fuente de gestiones/],
  ['la policy de INSERT cambió su with check', `alter policy actividades_insert on crm.actividades with check (true);`, /PREFLIGHT: la fuente de gestiones/],
  ['la policy de INSERT se abrió a otro rol', `alter policy actividades_insert on crm.actividades to authenticated, anon;`, /PREFLIGHT: la fuente de gestiones/],
  ['aparece una policy de DELETE en actividades', `create policy gestion_mutante_del on crm.actividades for delete to authenticated using (true);`, /PREFLIGHT: la fuente de gestiones/],
  ['authenticated recibe DELETE sobre actividades', `grant delete on crm.actividades to authenticated;`, /PREFLIGHT: la fuente de gestiones/],
  ['anon recibe UPDATE sobre una columna de actividades', `grant update (detalle) on crm.actividades to anon;`, /PREFLIGHT: la fuente de gestiones/],
  ['anon recibe DELETE sobre actividades', `grant delete on crm.actividades to anon;`, /PREFLIGHT: la fuente de gestiones/],
];
for (const [nombre, preparacion, patron] of mutantesPreflight) {
  const error = debeFallar(deshecho(preparacion, cuerpoMigracion), patron, nombre);
  anotar(`5 · mutante de preflight: ${nombre}`, 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}
// Las anclas no dependen de quién aplique ni de su search_path. Con `private` en el camino,
// `pg_get_triggerdef` escribe la función del trigger sin esquema y su md5 es OTRO: la migración
// pasa igual porque fija el search_path vacío; sin esa línea (mutante) se rechazaría a sí misma.
const caminoHostil = 'set search_path = private, crm, public, auth, extensions;\n';
sql(caminoHostil + deshecho(cuerpoMigracion));
sql(caminoHostil + deshecho('set local role postgres;', cuerpoMigracion), { usuario: 'supabase_admin' });
anotar('5 · la migración pasa igual con `private` y `crm` en el search_path de la sesión, y aplicada con `set role postgres`', 'PASS');
{
  const sinFijar = mutar(migracion, "set local search_path = '';\n", '');
  const error = debeFallar(caminoHostil + deshecho(sinTx(sinFijar)), /PREFLIGHT: el sello de tenencia_desde/, 'sin fijar el search_path');
  anotar('5 · mutante: sin `set local search_path` y con ese camino de sesión, las anclas dejan de cuadrar', 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}
{
  // A la permisiva ALL la rechaza antes la guarda 3. Para probar que la cláusula de la guarda 5
  // no es código muerto: se quita la 3 del preflight (solo la primera aparición) y debe cazarla la 5.
  const GUARDA_3 = '  perform private.assert_actividades_de_lead_base();\n';
  const primera = migracion.indexOf(GUARDA_3);
  assert.ok(primera > 0 && migracion.indexOf(GUARDA_3, primera + 1) > primera, 'La guarda 3 debe estar en el preflight y en el postflight');
  assert.ok(primera < migracion.indexOf('  -- 5. El reloj y la integridad de la ACTIVIDAD.'), 'La guarda 3 debe ir antes de la 5');
  const sinGuarda3 = migracion.slice(0, primera) + migracion.slice(primera + GUARDA_3.length);
  const error = debeFallar(deshecho('create policy gestion_mutante_all on crm.actividades for all to authenticated using (true) with check (true);', sinTx(sinGuarda3)),
    /PREFLIGHT: la fuente de gestiones/, 'policy ALL sin la guarda 3');
  anotar('5 · mutante de preflight: policy permisiva ALL y sin la guarda 3, la caza la guarda 5', 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}

// ── 6 · Mutantes del POSTFLIGHT: lo que saliera mal al instalar se deshace ───
const pinF13 = (migracion.match(/md5\(pg_get_functiondef\(to_regprocedure\(f13\)\)\) = '([0-9a-f]{32})'/) ?? [])[1];
assert.ok(pinF13, 'No encuentro el md5 fijado en el postflight de la migración');
// Las dos últimas líneas del `exists` del filtro, tal como están en la migración.
const LINEA_TENENCIA = "            and g.creado_en >= l.tenencia_desde\n";
const LINEA_DESHECHO = "            and not (g.metadata ? 'deshecho_en')";
const FIN_PREDICADO = `${LINEA_DESHECHO})) = (p_gestion = 'con_gestion'))`;
assert.ok(migracion.includes(LINEA_TENENCIA + FIN_PREDICADO), 'El predicado de la migración no tiene la forma que este ensayo espera');
const MOVER_EXENCION = migracion.slice(migracion.indexOf('update private.analitica_leads_citas_exenciones e set'), migracion.indexOf('update private.analitica_lc_sello'));
const RESELLAR = migracion.slice(migracion.indexOf('update private.analitica_lc_sello'), migracion.indexOf('do $postflight$'));
const mutantesPostflight = [
  ['el cuerpo instalado no es el ensayado', mutar(migracion, LINEA_TENENCIA, ''), /POSTFLIGHT: firma, cuerpo, permisos o contrato/],
  ['anon recibe EXECUTE', mutar(migracion, 'boolean,text) to authenticated;', 'boolean,text) to authenticated, anon;'), /POSTFLIGHT: firma, cuerpo, permisos o contrato/],
  ['la función sale SECURITY DEFINER', mutar(migracion, 'stable security invoker set search_path', 'stable security definer set search_path'), /POSTFLIGHT: firma, cuerpo, permisos o contrato/],
  ['la declaración analítica no se mueve', mutar(migracion, MOVER_EXENCION, ''), /POSTFLIGHT: cambio un contador/],
  ['la lista no se resella', mutar(migracion, RESELLAR, ''), /POSTFLIGHT: cambio un contador/],
];
for (const [nombre, mutada, patron] of mutantesPostflight) {
  const error = debeFallar(deshecho(sinTx(mutada)), patron, nombre);
  anotar(`6 · mutante de postflight: ${nombre}`, 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}
{
  // La guarda 5 va dos veces (preflight y postflight) con la misma condición, letra por letra.
  const condiciones = migracion.match(/\(select count\(\*\) from pg_trigger t\n {6}where t\.tgrelid = 'crm\.actividades'::regclass[\s\S]*?\n {2}\) is not true then/g) ?? [];
  assert.equal(condiciones.length, 2, 'La guarda 5 debe estar en el preflight y en el postflight');
  assert.equal(condiciones[0], condiciones[1], 'La guarda 5 del postflight no es idéntica a la del preflight');
  // Y la del postflight no es código muerto: sin la del preflight, la caza ella.
  const inicio = migracion.indexOf('  -- 5. El reloj y la integridad de la ACTIVIDAD.');
  const cierre = "    raise exception 'PREFLIGHT: la fuente de gestiones (crm.actividades) no coincide con la version auditada';\n  end if;\n";
  assert.ok(inicio > 0 && migracion.indexOf(cierre) > inicio);
  const sinGuarda5 = migracion.slice(0, inicio) + migracion.slice(migracion.indexOf(cierre) + cierre.length);
  const error = debeFallar(deshecho('alter table crm.actividades disable trigger trg_01_gestion_lead_serializada;', sinTx(sinGuarda5)),
    /POSTFLIGHT: la fuente de gestiones/, 'guarda 5 solo en el postflight');
  anotar('6 · mutante de postflight: sin la guarda 5 del preflight y con trg_01 apagado, la caza su repetición', 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}
assert.equal(md5Viva(F12), MD5_F12, 'Un mutante dejó rastro');

// ── 7 · Mutantes de la LÓGICA: el oráculo se pone rojo cuando la regla se rompe ─
// El pin del cuerpo los cazaría antes (paso 6): aquí se desactiva a propósito, para probar
// al ORÁCULO y no al pin.
const sinPin = (texto) => mutar(texto, `= '${pinF13}'`, 'is not null');
const TIPOS = "            and g.tipo in ('llamada_realizada','llamada_no_contestada',\n              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')";
const mutantesLogica = [
  ['sin el ancla de la tenencia (cualquier intento, de cualquier época)', LINEA_TENENCIA, ''],
  ['ancla invertida (solo lo de ANTES de la tenencia)', 'g.creado_en >= l.tenencia_desde', 'g.creado_en < l.tenencia_desde'],
  ['borde estricto (> en vez de >=)', 'g.creado_en >= l.tenencia_desde', 'g.creado_en > l.tenencia_desde'],
  ['mide desde el alta del lead, no desde la tenencia', 'g.creado_en >= l.tenencia_desde', 'g.creado_en >= l.creado_en'],
  ['una nota cuenta como gestión', TIPOS, TIPOS.replace("'reunion_realizada')", "'reunion_realizada','nota')")],
  ['el WhatsApp enviado no cuenta', TIPOS, TIPOS.replace("'whatsapp_enviado',", '')],
  ['la llamada no contestada no cuenta', TIPOS, TIPOS.replace("'llamada_no_contestada',", '')],
  ['solo cuenta lo que hizo el propio titular (por autor)', 'where g.lead_id = l.id', 'where g.lead_id = l.id and g.creado_por = l.vendedor_id'],
  ['no exige titular', '(p_gestion is null or (l.vendedor_id is not null\n        and l.tenencia_desde is not null', '(p_gestion is null or (l.tenencia_desde is not null'],
  ['cuenta la gestión de cualquier lead', 'where g.lead_id = l.id', 'where g.lead_id is not null'],
  ['las dos mitades cambiadas', "= (p_gestion = 'con_gestion'))", "= (p_gestion = 'sin_gestion'))"],
  ['no valida el dominio', "     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))\n", ''],
  ['recorta aunque p_gestion venga nulo', 'and (p_gestion is null or (l.vendedor_id is not null', 'and (false or (l.vendedor_id is not null'],
  ['añade un eco «gestion» al payload', "'reasignados',coalesce(p_reasignados,false),", "'reasignados',coalesce(p_reasignados,false),'gestion',p_gestion,"],
  // Decisión del 01/10: un resultado de llamada deshecho NO es gestión.
  ['lo deshecho cuenta (se quita la exclusión de `deshecho_en`)', `\n${LINEA_DESHECHO}`, ''],
  ['solo cuenta lo deshecho (exclusión invertida)', "and not (g.metadata ? 'deshecho_en')", "and (g.metadata ? 'deshecho_en')"],
];
const cazados = [];
for (const [nombre, de, a] of mutantesLogica) {
  const r = ejecutar(deshecho(sinTx(sinPin(mutar(migracion, de, a))), cuerpoOraculo));
  const m = (r.stderr ?? '').match(/ORACULO GESTION: (\d+) FALLAS de (\d+)/);
  assert.ok(r.status !== 0 && m, `El mutante «${nombre}» SOBREVIVIÓ o falló por otra causa: ${(r.stderr ?? '').slice(0, 300)}${r.stdout.slice(-200)}`);
  cazados.push({ mutante: nombre, fallas: Number(m[1]), de: Number(m[2]) });
  anotar(`7 · mutante de lógica: ${nombre}`, 'PASS', { resumen: `oráculo en rojo: ${m[1]} fallas de ${m[2]}` });
}
// Mutante EQUIVALENTE, declarado: quitar `tenencia_desde is not null` no cambia nada, porque
// `creado_en >= NULL` ya da «sin gestión». La condición se conserva por claridad del contrato.
{
  const equivalente = sinPin(mutar(migracion, '\n        and l.tenencia_desde is not null', ''));
  okOraculo(sql(deshecho(sinTx(equivalente), cuerpoOraculo)));
  anotar('7 · mutante equivalente (sin `tenencia_desde is not null`): sobrevive, como se espera', 'PASS', { resumen: 'la comparación con NULL ya lo cubre; documentado' });
}
// Mutantes de ESTADO: la migración ya está puesta y es el SERVIDOR el que deja de defender. Las
// negativas de falsificación del oráculo tienen que ponerse rojas (no pasan en vacío).
for (const [nombre, estado] of [
  ['el servidor deja de sellar creado_en (trg_01 apagado)', 'alter table crm.actividades disable trigger trg_01_gestion_lead_serializada;'],
  ['el servidor deja de reservar deshecho_en (trg_00 apagado)', 'alter table crm.actividades disable trigger trg_00_actividades_resultado_solo_nucleo;'],
  ['authenticated puede reescribir y borrar actividades', `grant update, delete on crm.actividades to authenticated;
    create policy gestion_m_upd on crm.actividades for update to authenticated using (true) with check (true);
    create policy gestion_m_del on crm.actividades for delete to authenticated using (true);`],
]) {
  const r = ejecutar(deshecho(cuerpoMigracion, estado, cuerpoOraculo));
  const m = (r.stderr ?? '').match(/ORACULO GESTION: (\d+) FALLAS de (\d+)/);
  assert.ok(r.status !== 0 && m, `Con «${nombre}» el oráculo NO se puso rojo: ${(r.stderr ?? '').slice(0, 300)}${r.stdout.slice(-200)}`);
  anotar(`7 · mutante de estado contra el oráculo: ${nombre}`, 'PASS', { resumen: `oráculo en rojo: ${m[1]} fallas de ${m[2]}` });
}
// Y el oráculo de IGUALDAD también se pone rojo cuando debe.
for (const [nombre, de, a] of [mutantesLogica[12], mutantesLogica[13]]) {
  const ig = leerIgualdad(sql(deshecho(anteriorTemporal, volumen, sinTx(sinPin(mutar(migracion, de, a))), igualdad)));
  assert.ok(ig.iguales < ig.total, `El oráculo de igualdad no detectó «${nombre}»`);
  anotar(`7 · mutante contra la igualdad: ${nombre}`, 'PASS', { resumen: `detectado: solo ${ig.iguales}/${ig.total} idénticas` });
}
// Y el oráculo independiente con volumen (se define más abajo cómo se lee).
for (const [nombre, de, a, minimo] of [
  ['sin el ancla de la tenencia', LINEA_TENENCIA, '', 100],
  ['lo deshecho cuenta', `\n${LINEA_DESHECHO}`, '', 1],
]) {
  const pv = leerParticion(sql(deshecho(volumen, sinTx(sinPin(mutar(migracion, de, a))), particionVolumen)));
  assert.ok(!pv.cuadra && pv.descuadres >= minimo, `El oráculo independiente con volumen no detectó «${nombre}»`);
  anotar(`7 · mutante contra el oráculo independiente con volumen: ${nombre}`, 'PASS', { resumen: `detectado: ${pv.descuadres} filas descuadradas` });
}
assert.equal(md5Viva(F12), MD5_F12, 'Un mutante dejó rastro');
assert.equal(filasDeDatos(), '0');

// ── 8 · Aplicación REAL: como postgres y en UN mensaje ───────────────────────
sql(migracion, { unMensaje: true });
const despues = foto(F13, F13_LARGA);
assert.equal(despues.md5, md5F13, 'El md5 instalado no es el medido en el control');
assert.equal(md5F13, pinF13, 'El md5 instalado no es el fijado en el postflight');
assert.equal(md5Viva(F12), '-', 'La firma de 12 argumentos sigue instalada');
assert.equal(sql("select count(*) from pg_proc where proname = 'cartera_filtrada_fn' and pronamespace = 'crm'::regnamespace"), '1');
assert.equal(despues.contrato, antes.contrato, 'Cambió el contrato de seguridad (dueño, invoker, stable, search_path o ACL)');
assert.match(despues.gate, /^OK/, 'Gate analítico tras instalar');
assert.equal(despues.gate, antes.gate, 'El gate analítico no dice lo mismo que antes');
assert.ok(despues.sello_vigente, 'El sello no quedó vigente');
assert.equal(despues.censo_rojo, antes.censo_rojo);
assert.equal(despues.resumen_md5, antes.resumen_md5);
assert.deepEqual({ ...despues.exencion, objeto: null, huella: null, razon: null }, { ...antes.exencion, objeto: null, huella: null, razon: null },
  'La declaración no se movió: cambió su clase, su tipo o su fecha');
assert.equal(despues.exencion.huella, huellaF13, 'La huella del censo no es determinista');
// El cuerpo nuevo es el viejo más DOS bloques insertados, y nada más (no se retecleó).
const INSERCION_VALIDACION = "     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o\n     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.\n     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))\n";
const cuerpoNuevo = crudo(`select prosrc from pg_proc where oid = to_regprocedure('${F13}')`);
const inicioBase = cuerpoNuevo.indexOf('      -- Gestión vigente: el titular ACTUAL');
const finBase = cuerpoNuevo.indexOf(FIN_PREDICADO) + FIN_PREDICADO.length + 1;
assert.ok(inicioBase > 0 && finBase > inicioBase);
const cuerpoSinInserciones = mutar(cuerpoNuevo.slice(0, inicioBase) + cuerpoNuevo.slice(finBase), INSERCION_VALIDACION, '');
assert.equal(md5(cuerpoSinInserciones), MD5_PROSRC_F12, 'El cuerpo nuevo no es el vivo más las dos inserciones');
anotar('8 · aplicación real (postgres, un mensaje) y medición DESPUÉS', 'PASS', {
  resumen: `md5 ${md5F13} · gate igual que antes · sello vigente · cuerpo = vivo + 2 inserciones (${cuerpoNuevo.length - cuerpoSinInserciones.length} caracteres)`, despues });
debeFallar(migracion, /PREFLIGHT: cartera_filtrada_fn no coincide/, 'migración repetida', { unMensaje: true });
assert.equal(md5Viva(F13), md5F13);
anotar('8 · la migración repetida se niega y no cambia nada', 'PASS');

// ── 9 · Oráculo, igualdad y rendimiento con la migración instalada ───────────
const aserciones2 = okOraculo(sql(oraculo));
assert.equal(aserciones2, aserciones);
anotar('9 · oráculo de negocio sobre la migración instalada', 'PASS', { resumen: `${aserciones2}/${aserciones2} aserciones` });
{
  // La matriz remota (`../test-rls.mjs`) no se puede ejecutar aquí: exige credenciales. Para que su
  // oráculo de gestión no quede sin probar, se EXTRAE su código del archivo y se ejecuta con lo que
  // cada actor lee bajo RLS —de las tablas y de la función— sobre los fixtures del oráculo de
  // negocio. No sustituye a correr el gate (aquí no hay PostgREST ni sesiones reales).
  const gateRls = leer('../test-rls.mjs');
  const trozo = (patron, que) => {
    const m = gateRls.match(patron);
    assert.ok(m, `No encuentro ${que} en test-rls.mjs: si cambió de forma, hay que actualizar este paso`);
    return m[0];
  };
  const construir = new Function('leads', 'contactos', [
    trozo(/const micros = \(iso\) => \{[\s\S]*?\n {6}\};/, 'micros()'),
    trozo(/const TIPOS_CONTACTO_GESTION = new Set\(\[[\s\S]*?\]\);/, 'los tipos de contacto'),
    trozo(/const contactosVigentes = new Map\(\);[\s\S]*?const esperadaCon = \(id\) => \{[\s\S]*?\n {10}\};/, 'el oráculo de gestión'),
    'return { esperadaCon, leadPorId, tipos: [...TIPOS_CONTACTO_GESTION] };',
  ].join('\n'));
  const tipos = construir([], []).tipos;
  assert.equal(tipos.length, 5);
  const finFixtures = oraculo.indexOf('set local session_replication_role = origin;\nset local role authenticated;');
  assert.ok(finFixtures > 0, 'No encuentro el final de los fixtures del oráculo de negocio');
  const ACTORES = { analista_A: 2, supervisor_S1: 1, gerencia: 4, directorio: 7, analista_C: 5, supervisor_S2: 6 };
  const lecturas = Object.entries(ACTORES).map(([nombre, n]) => `select pg_temp.soy(${n});
select 'DATO ${nombre} t ' || crm.cartera_filtrada_fn(p_limite => 200)::text;
select 'DATO ${nombre} c ' || crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion')::text;
select 'DATO ${nombre} s ' || crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion')::text;
select 'DATO ${nombre} l ' || coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)::text from (select id, vendedor_id, tenencia_desde from crm.leads) x;
select 'DATO ${nombre} a ' || coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)::text from (select lead_id, tipo, creado_en, metadata from crm.actividades where tipo in (${tipos.map((t) => `'${t}'`).join(',')})) x;`).join('\n');
  const salida = sql(`${oraculo.slice(0, finFixtures)}set local session_replication_role = origin;\nset local role authenticated;\n${lecturas}\nreset role;\nrollback;\n`);
  const datos = {};
  for (const linea of salida.split('\n')) {
    const m = linea.match(/^DATO (\S+) (\S) (.*)$/);
    if (m) (datos[m[1]] ??= {})[m[2]] = JSON.parse(m[3]);
  }
  assert.deepEqual(Object.keys(datos), Object.keys(ACTORES));
  // Las mismas tres comprobaciones que hace el gate, con el código extraído.
  const evaluar = (d, { leads = d.l, contactos = d.a, c = d.c, s = d.s } = {}) => {
    const { esperadaCon, leadPorId } = construir(leads, contactos);
    const idsCon = new Set(c.items.map((f) => f.id));
    const idsSin = new Set(s.items.map((f) => f.id));
    return {
      con: c.items.every((f) => leadPorId.has(f.id) && esperadaCon(f.id)),
      sin: s.items.every((f) => leadPorId.has(f.id) && !esperadaCon(f.id)),
      mitades: Number(d.t.resumen.totales.vivos) === d.t.items.length && idsCon.size + idsSin.size === d.t.items.length
        && d.t.items.every((f) => idsCon.has(f.id) !== idsSin.has(f.id)),
      tamanos: `${idsCon.size}+${idsSin.size}`,
    };
  };
  const roja = (v) => !(v.con && v.sin);
  const cazados = { mitades_intercambiadas: 0, contactos_sin_la_marca_de_deshecho: 0, tenencia_retrasada: 0 };
  const porActor = {};
  for (const [nombre, d] of Object.entries(datos)) {
    const v = evaluar(d);
    assert.ok(v.con && v.sin && v.mitades, `El oráculo de test-rls.mjs no coincide con la función para ${nombre}: ${JSON.stringify(v)}`);
    porActor[nombre] = v.tamanos;
    // Controles negativos: ese oráculo se pone rojo cuando debe.
    if (roja(evaluar(d, { c: d.s, s: d.c }))) cazados.mitades_intercambiadas += 1;
    if (roja(evaluar(d, { contactos: d.a.map((a) => ({ ...a, metadata: Object.fromEntries(Object.entries(a.metadata ?? {}).filter(([k]) => k !== 'deshecho_en')) })) }))) cazados.contactos_sin_la_marca_de_deshecho += 1;
    if (roja(evaluar(d, { leads: d.l.map((l) => ({ ...l, tenencia_desde: l.tenencia_desde === null ? null : '2000-01-01T00:00:00+00:00' })) }))) cazados.tenencia_retrasada += 1;
  }
  assert.equal(cazados.mitades_intercambiadas, Object.keys(ACTORES).length, 'Intercambiar las mitades debe poner rojo el oráculo de todos los actores');
  assert.ok(cazados.contactos_sin_la_marca_de_deshecho >= 1 && cazados.tenencia_retrasada >= 1, 'El oráculo de test-rls.mjs no distingue lo deshecho o la tenencia');
  anotar('9 · el oráculo de gestión de test-rls.mjs (código extraído del archivo) coincide con la función, actor por actor bajo RLS', 'PASS', {
    resumen: `${Object.entries(porActor).map(([n, t]) => `${n} ${t}`).join(' · ')}; se pone rojo con mitades intercambiadas (${cazados.mitades_intercambiadas}/6), sin la marca de deshecho (${cazados.contactos_sin_la_marca_de_deshecho}/6) y con la tenencia retrasada (${cazados.tenencia_retrasada}/6)`,
    nota: 'No es una ejecución del gate: sin PostgREST ni sesiones reales', con_mas_sin_por_actor: porActor, controles_negativos: cazados });
}
{
  const ig = leerIgualdad(sql(deshecho(anteriorTemporal, volumen, igualdad)));
  assert.equal(ig.iguales, ig.total, `Respuestas distintas: ${ig.distintas}`);
  anotar('9 · igualdad con la migración instalada', 'PASS', { resumen: `${ig.iguales}/${ig.total} respuestas idénticas, ${ig.filas_comparadas} filas` });
}
{
  // La siembra de volumen se niega sobre una base con datos (aquí: sembrada dos veces seguidas
  // en la misma transacción, que se deshace).
  const error = debeFallar(deshecho(volumen, volumen), /VOLUMEN: la base tiene/, 'volumen sobre una base con datos');
  assert.equal(filasDeDatos(), '0', 'La siembra rechazada dejó datos');
  anotar('9 · la siembra de volumen se niega si la base ya tiene datos', 'PASS', { resumen: `rechazado: ${error.slice(0, 90)}` });
}
{
  const pv = leerParticion(sql(deshecho(volumen, particionVolumen)));
  assert.ok(pv.cuadra, `El Pipeline con volumen no cuadra con el oráculo independiente: ${JSON.stringify(pv.por_actor)}`);
  const g = (mitad) => pv.por_actor.find((x) => x.actor === 1 && x.mitad === mitad);
  assert.ok(pv.filas_recorridas > 2000 && g('con_gestion').paginas >= 3 && g('sin_gestion').paginas >= 3, 'Recorrido vacío: no paginó de verdad');
  assert.equal(pv.por_actor.filter((x) => x.actor === 3).reduce((n, x) => n + x.servidas, 0), 0, 'El coordinador recibió leads');
  assert.ok(pv.decididos_por_lo_deshecho > 0, 'El volumen no trae ningún lead cuya mitad dependa de un contacto deshecho');
  anotar('9 · Pipeline con volumen contra un oráculo independiente: por cursor, ni de más, ni de menos, ni repetidas', 'PASS', {
    resumen: `${pv.filas_recorridas} filas recorridas; gerencia ${g('con_gestion').servidas} «Gestionado» en ${g('con_gestion').paginas} páginas + ${g('sin_gestion').servidas} «Nuevo» en ${g('sin_gestion').paginas}; ${pv.decididos_por_lo_deshecho} leads están en «Nuevo» solo porque su contacto se deshizo`,
    particion: pv });
}
{
  limpiarFilasMuertas();
  const r = ejecutar(deshecho(anteriorTemporal, volumen, rendimiento), { usuario: 'supabase_admin' });
  assert.equal(r.status, 0, `rendimiento.sql falló: ${r.stderr.split('\n').filter((l) => /ERROR/.test(l)).join(' ').slice(0, 500)}`);
  const tiempos = JSON.parse(r.stdout.match(/^TIEMPOS (\[.*\])$/m)[1]);
  const pareada = JSON.parse(r.stdout.match(/^PAREADA (\[.*\])$/m)[1]);
  const primeras = JSON.parse(r.stdout.match(/^PRIMERAS (\[.*\])$/m)[1]);
  // Planes: tras cada MARCA, la sentencia interna de la función (la que empieza por el CTE).
  const trozos = r.stderr.split(/^(?:psql:<stdin>:\d+: )?LOG: {2}MARCA (.+)$/m);
  const planes = [];
  for (let i = 1; i < trozos.length - 1; i += 2) {
    const principal = trozos[i + 1].split(/^(?:psql:<stdin>:\d+: )?LOG: {2}duration: /m).slice(1).find((e) => e.includes('with recepciones as materialized'));
    if (!principal) continue;
    const lineas = principal.split('\n');
    const nodos = lineas.filter((l) => /on actividades g\b/.test(l)).map((l) => l.trim());
    const en = lineas.findIndex((l) => /on actividades g\b/.test(l));
    const condicion = (lineas[en + 1] ?? '').trim();
    // Las líneas propias del nodo (condición de índice, filtro, filas descartadas, visitas al montón).
    const detalle = en < 0 ? [] : lineas.slice(en + 1, en + 6).map((l) => l.trim()).filter((l) => /^(Index Cond|Filter|Rows Removed by Filter|Heap Fetches|Buffers):/.test(l));
    planes.push({ caso: trozos[i], ms_instrumentado: Number(principal.split(' ms')[0]), nodos_del_filtro: nodos,
      tipo_de_nodo: nodos.length ? (/Index Only Scan/.test(nodos[0]) ? 'Index Only Scan' : /Index Scan/.test(nodos[0]) ? 'Index Scan' : 'otro') : null,
      detalle_del_nodo: detalle,
      condicion_de_indice: nodos.length ? condicion : null, seq_scan_sobre_actividades: lineas.filter((l) => /Seq Scan on actividades/.test(l)).length,
      // Ajeno a este cambio, pero decide el tiempo absoluto: cómo busca la lateral de «reasignado»
      // (ya existente) sus eventos. Con BitmapAnd recorre el índice de reasignaciones por cada lead.
      lateral_reasignados: /Bitmap Index Scan on actividades_reasignacion_historial_idx/.test(principal) ? 'bitmap_and (lento)' : 'index_scan por lead',
      plan: /\(\$\d+ IS NULL\)/.test(principal) ? 'genérico (guardado)' : 'a medida (planificado en la llamada)',
      buffers: Number((principal.match(/Buffers: shared hit=(\d+)/) ?? [])[1] ?? NaN) });
  }
  assert.equal(planes.length, 8, 'No se capturaron los 8 planes');
  for (const p of planes) {
    assert.equal(p.seq_scan_sobre_actividades, 0, `Recorrido secuencial de actividades en ${p.caso}`);
    if (/gestion$/.test(p.caso)) {
      assert.equal(p.nodos_del_filtro.length, 1, `El filtro no aparece en el plan de ${p.caso}`);
      assert.match(p.nodos_del_filtro[0], /^-> {2}Index (Only )?Scan using (actividades_contacto_episodio_idx|idx_actividades_lead) on actividades g/, `El exists no usa índice en ${p.caso}`);
      assert.match(p.condicion_de_indice, /lead_id = .*creado_en >= /, `El índice no acota por lead y fecha en ${p.caso}`);
      assert.ok(p.detalle_del_nodo.some((l) => /^Filter:.*deshecho_en/.test(l)), `El plan de ${p.caso} no filtra lo deshecho`);
    } else {
      assert.equal(p.nodos_del_filtro.length, 0, `Sin filtro, el exists no debería estar en el plan de ${p.caso}`);
    }
  }
  if (process.env.ENSAYO_PLANES_DIR) {
    mkdirSync(process.env.ENSAYO_PLANES_DIR, { recursive: true });
    writeFileSync(`${process.env.ENSAYO_PLANES_DIR}/planes-auto-explain.txt`, r.stderr);
  }
  const t = (rol, v) => tiempos.find((x) => x.rol === rol && x.variante === v).mediana_ms;
  for (const rol of ['analista', 'gerencia']) {
    // Sin filtro no debe costar más que antes (margen amplio: es ruido de medición, no un SLA).
    assert.ok(t(rol, 'nueva_sin_filtro') <= t(rol, 'vieja') * 1.25 + 2, `La función sin filtro es más lenta que la vieja para ${rol}`);
  }
  const d = (rol) => pareada.find((x) => x.rol === rol).mediana_nueva_sin_filtro_menos_vieja_ms;
  anotar('9 · rendimiento con volumen: tiempos y plan del exists', 'PASS', {
    resumen: `analista ${t('analista', 'vieja')} → ${t('analista', 'nueva_sin_filtro')} ms sin filtro (pareada ${d('analista')} ms), ${t('analista', 'nueva_con_gestion')} / ${t('analista', 'nueva_sin_gestion')} ms con/sin gestión; gerencia ${t('gerencia', 'vieja')} → ${t('gerencia', 'nueva_sin_filtro')} ms (pareada ${d('gerencia')} ms), ${t('gerencia', 'nueva_con_gestion')} / ${t('gerencia', 'nueva_sin_gestion')} ms; exists: ${planes.find((p) => p.caso === 'gerencia nueva_con_gestion').tipo_de_nodo} sobre ${planes.find((p) => p.caso === 'gerencia nueva_con_gestion').nodos_del_filtro[0].match(/using (\S+)/)[1]}; lateral de reasignados (ajena): ${planes.find((p) => p.caso === 'gerencia vieja').lateral_reasignados}`,
    volumen: datosVolumen, tiempos, diferencia_pareada: pareada, primeras_llamadas_de_la_sesion: primeras, planes });
}
assert.equal(filasDeDatos(), '0', 'Los ensayos con datos dejaron filas');

// ── 10 · Reversa: generada, con sus guardas, real, y repetida ────────────────
debeFallar(deshecho(`alter function ${F13} cost 250;`, cuerpoReversa), /REVERSA: la funcion de 13 argumentos no es la publicada/, 'función corregida después de la entrega');
debeFallar(deshecho("update private.analitica_lc_sello set sello = '0000deadbeef' where id;", cuerpoReversa), /REVERSA: la lista de exenciones no coincide con su sello/, 'sello alterado por fuera');
assert.match(sql(deshecho(rojoAjeno, cuerpoReversa, leerRojo(F12_LARGA), `${P} select 'MD5 ' || md5(pg_get_functiondef(to_regprocedure('${F12}')));`)),
  new RegExp(`^ROJO crm\\.oraculo_rojo_ajeno_fn\\(\\) \\| true\\nMD5 ${MD5_F12}$`, 'm'));
anotar('10 · guardas de la reversa: función corregida y sello alterado se rechazan; un rojo ajeno se conserva', 'PASS');
sql(reversa, { unMensaje: true });
const revertido = foto(F12, F12_LARGA);
assert.equal(revertido.md5, MD5_F12, 'La reversa no devolvió la función byte a byte');
assert.equal(md5Viva(F13), '-', 'La firma de 13 argumentos sigue instalada');
assert.deepEqual(revertido, antes, 'Tras la reversa algo no quedó EXACTAMENTE como antes');
anotar('10 · reversa real: todo vuelve EXACTAMENTE al estado de antes', 'PASS', {
  resumen: `md5 ${revertido.md5} · sello vigente · gate, contrato, comentario y declaración idénticos a ANTES`, revertido });
debeFallar(reversa, /REVERSA: la firma de 13 argumentos no es la unica instalada/, 'reversa repetida', { unMensaje: true });
anotar('10 · la reversa repetida se niega', 'PASS');

// ── 11 · Reaplicación: el banco queda CON la migración ───────────────────────
sql(migracion, { unMensaje: true });
const final = foto(F13, F13_LARGA);
assert.deepEqual(final, despues, 'La reaplicación no deja exactamente lo mismo que la primera aplicación');
assert.equal(okOraculo(sql(oraculo)), aserciones);
anotar('11 · reaplicación: mismo md5, misma declaración, gate verde y oráculo en verde', 'PASS', { resumen: `md5 ${final.md5}` });

// ── 12 · Registrador y acreditación final ────────────────────────────────────
const registrador = generarRegistrador({ md5F13 });
escribir('./registrar.sql', registrador);
debeFallar(deshecho(cuerpoReversa, sinTx(registrador)), /REGISTRO: la migración \d+ no está aplicada tal cual/, 'registrar sin la migración');
sql(registrador, { unMensaje: true });
sql(registrador, { unMensaje: true });
assert.equal(sql(`select count(*) || ' ' || max(name) || ' ' || max(md5(statements[1])) from supabase_migrations.schema_migrations where version = '${VERSION}'`), `1 ${NOMBRE} ${md5(migracion)}`);
debeFallar(deshecho(`update supabase_migrations.schema_migrations set statements = array['otro'] where version = '${VERSION}';`, sinTx(registrador)),
  /REGISTRO: la versión \d+ ya está registrada con otro nombre u otro contenido/, 'registro con otro contenido');
anotar('12 · registrador: se niega sin la migración, registra, es idempotente y no pisa otro contenido', 'PASS');
{
  const r = ejecutar(acreditar);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /ESTADO: DESPUES de publicar/);
  assert.match(r.stderr, /VEREDICTO: todas las anclas coinciden: quedó instalado lo ensayado/);
  assert.doesNotMatch(r.stderr, /\[DIFERENTE\]/);
  assert.ok(acreditar.includes(md5F13) && acreditar.includes(huellaF13), 'acreditar.sql no lleva las huellas medidas');
  // acreditar.sql y la migración anclan lo MISMO: cada md5 fijado en las guardas está en los dos.
  const anclasDeGuardas = [...new Set([...migracion.matchAll(/'([0-9a-f]{32})'/g)].map((m) => m[1]))];
  assert.ok(anclasDeGuardas.length >= 9, 'No encuentro las anclas de las guardas en la migración');
  for (const ancla of anclasDeGuardas) assert.ok(acreditar.includes(ancla), `acreditar.sql no comprueba el ancla ${ancla} de la migración`);
  anotar('12 · acreditar.sql (solo lectura) en estado DESPUÉS', 'PASS');
}
assert.equal(filasDeDatos(), '0', 'El banco quedó con datos');

Object.assign(evidencia, {
  estado: 'PASS',
  anclas: {
    f12_md5_functiondef: MD5_F12, f12_md5_prosrc: MD5_PROSRC_F12, f12_huella_censo: HUELLA_F12,
    f13_md5_functiondef: md5F13, f13_md5_prosrc: md5(cuerpoNuevo), f13_huella_censo: huellaF13,
    trigger_tenencia_md5_triggerdef: (migracion.match(/md5\(pg_get_triggerdef\(t\.oid\)\) = '([0-9a-f]{32})'/) ?? [])[1],
    trigger_tenencia_md5_functiondef: (migracion.match(/md5\(pg_get_functiondef\(t\.tgfoid\)\) = '([0-9a-f]{32})'/) ?? [])[1],
    guarda_5: {
      trg_01_gestion_lead_serializada: (migracion.match(/\('trg_01_gestion_lead_serializada', '([0-9a-f]{32})', '([0-9a-f]{32})'\)/) ?? []).slice(1, 3),
      trg_00_actividades_resultado_solo_nucleo: (migracion.match(/\('trg_00_actividades_resultado_solo_nucleo', '([0-9a-f]{32})', '([0-9a-f]{32})'\)/) ?? []).slice(1, 3),
      actividades_insert_with_check: (migracion.match(/md5\(pg_get_expr\(p\.polwithcheck, p\.polrelid\)\) = '([0-9a-f]{32})'\)/) ?? [])[1],
      crm_actor_activo_gate: (migracion.match(/md5\(pg_get_expr\(p\.polqual, p\.polrelid\)\) = '([0-9a-f]{32})'/) ?? [])[1],
      nota: 'por trigger: [md5 de pg_get_triggerdef, md5 de pg_get_functiondef]',
    },
    nota: 'todas con search_path vacío',
  },
  archivos: {
    migracion_sha256: sha256(migracion), migracion_md5: md5(migracion),
    reversa_sha256: sha256(reversa), registrador_sha256: sha256(registrador), oraculo_sha256: sha256(oraculo),
  },
  aserciones_del_oraculo: aserciones,
  mutantes_de_logica: cazados,
  estado_final_del_banco: 'migración instalada y registrada; sin datos',
  banco_de_pruebas: 'esquema de producción SIN datos (paridad de funciones acreditada por huellas). El trinquete analítico se sembró con siembra-control-banco.sql (sintético): la fila de cartera_filtrada_fn lleva la clase, la razón y la huella reales; las demás declaraciones son de relleno.',
  no_acreditado_aqui: [
    'producción: nada se aplicó ni se leyó; las anclas se acreditan allí con acreditar.sql (solo lectura)',
    'advisors de Supabase (son de la nube)',
    'test:rls con sesiones reales y PostgREST/HTTP (el banco no tiene API ni credenciales)',
  ],
});
escribir('./verificacion.json', JSON.stringify(evidencia, null, 2) + '\n');
console.log(`\nPASS · ${evidencia.pasos.length} pasos en ${contenedor}. md5 de la firma de 13: ${md5F13}. Evidencia en verificacion.json`);
