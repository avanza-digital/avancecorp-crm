#!/usr/bin/env node

// EVIDENCIA DE ACCESOS DE LA F7 (el requisito D+7 / D+14 antes de demoler)
//
// El vigia diario prueba que la puerta SIGUE CERRADA. Esto prueba otra cosa
// distinta: si alguien INTENTO abrirla. Son preguntas separadas y hacen falta
// las dos antes de derribar una pieza.
//
// 🔴 LA REGLA QUE MANDA AQUI: «no aparece nada» NO es «nadie lo uso». Solo
//    vale como «sin evidencia de uso en la ventana [X, Y]», y por eso el guion
//    MIDE la ventana que de verdad se pudo mirar en vez de dar por buena la
//    que se pidio. Y por eso el gate FALLA CERRADO: ante un hueco, un
//    truncamiento o una denegacion sin adjudicar, dice NO.
//
// ─── LO QUE APRENDIO LA SEGUNDA AUDITORIA (Codex, 04/09) Y AQUI SE CORRIGE ───
//
// 🔴 A. EL METODO SOLO VE AL QUE FRACASA. Una llamada con EXITO no deja ERROR
//    en postgres_logs, y si no entra por PostgREST tampoco en edge_logs. Las 11
//    piezas son SECURITY DEFINER y el servidor tiene track_functions=none y
//    pgaudit.log=none: un exito de `postgres`/owner por conexion directa es
//    INVISIBLE aqui. Por eso la evidencia de logs NO basta sola — la prueba
//    fuerte es el CENSO ESTRUCTURAL (quien NOMBRA la pieza en su cuerpo), que
//    vive en la migracion de demolicion, no aqui. Este guion es una de dos
//    patas, no la unica.
//
// 🔴 B. QUE SIGNIFICA DE VERDAD «COBERTURA». La API sirve entero cualquier
//    rango de <=24 h (el 10,8 % de la 1a auditoria fue por pedir 7 dias de una
//    vez; por eso se trocea a 24 h). Dentro de un tramo de 24 h ya servido, que
//    el ultimo registro caiga a las 17:10 en vez de a las 17:55 NO es un hueco:
//    es una noche tranquila. Confundir «sin datos al borde» con «no observado»
//    fabricaba un hueco fantasma que dejaba a las gemelas en ROJO para siempre.
//    ⇒ un tramo <=24 h no truncado se da por OBSERVADO ENTERO (su ventana
//    pedida). El unico «me perdi filas» de verdad es el TRUNCAMIENTO (C). El
//    min/max solo se usa como guardia contra un recorte GRUESO del rango (si lo
//    servido cubre <90 % de lo pedido, se parte por la mitad). edge_logs y
//    postgres_logs se miden POR SEPARADO: un bucket edge vacio ya NO impide
//    consultar postgres.
//
// 🔴 C. `limit 1000` PODIA FABRICAR UN CERO. 1000 errores de ruido recientes
//    empujan fuera del resultado una denegacion mas vieja. Ahora, si una
//    consulta vuelve con exactamente el limite, el tramo se marca TRUNCADO y el
//    gate falla cerrado sobre el.
//
// 🔴 D. `permission denied for schema crm` NO llega al filtro. Ese error ni
//    siquiera nombra la pieza (la llamada muere en el USAGE del esquema antes
//    de resolver la funcion). Ahora hay una sonda aparte para las denegaciones
//    de ESQUEMA, independiente del nombre de la pieza.
//
// 🔴 E. LA COLA DE INGESTA. postgres_logs tarda minutos en asentar. Consultar
//    hasta `now()` y darlo por cubierto pierde el final de la ventana. Ahora el
//    techo se retrae INGESTA_MARGEN_MS.
//
// 🔴 F. EL RESUMEN NO SERVIA DE GATE. Unia los tramos PEDIDOS (no los
//    observados) y salia con codigo 0 aun con rastro. Ahora `--gate` valida
//    proyecto y juego de piezas, une lo OBSERVADO, y devuelve codigo != 0 ante
//    hueco / truncamiento / rastro / denegacion de esquema sin adjudicar.
//
// 🔑 EL DIALECTO ES EL VIEJO (BigQuery, `cross join unnest`). El nuevo
//    (ClickHouse) responde con error de backend en este proyecto. ⚠️ El
//    endpoint `logs.all` se retira el 23/09/2026: migrar a `logs` antes.
//
// 🔑 LA RUTA NO DISTINGUE EL ESQUEMA (viaja en la cabecera Accept-Profile /
//    Content-Profile, que el log NO conserva). Un intento contra
//    `/rpc/crear_contrato_producto` cuenta para las DOS piezas homonimas: es
//    conservador (puede dar falso ROJO, nunca falso verde).
//
// Uso:
//   npm run evidencia:f7                 -> cosecha los ultimos 7 dias
//   npm run evidencia:f7 -- --dias 3     -> ventana mas corta
//   npm run evidencia:f7 -- --resumen    -> no consulta: que tramos hay y donde
//                                           hay huecos (informativo, sale 0)
//   npm run evidencia:f7 -- --gate       -> no consulta: EL FRENO. Sale != 0 si
//                                           una pieza que ya toca demoler no
//                                           tiene su ventana [cerrada, drop]
//                                           cubierta y limpia. Correr ANTES de
//                                           aplicar cualquier demolicion.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const PIEZAS_SQL = 'supabase/scripts/evidencia-f7-piezas.sql';
const DIR_ACTAS = join(CRM_ROOT, 'supabase/scripts/evidencia-f7');
const API = 'https://api.supabase.com';
const RETENCION_DIAS = 7;      // documentado por Supabase para el plan Pro
const REINTENTOS = 5;
const PAUSA_MS = 6000;         // ritmo que el canal aguanta sin 429
const TRAMO_MS = 86400_000;    // 24 h: el maximo por consulta que la API acepta
const TRAMO_MINIMO_MS = 3600_000;
const LIMITE_FILAS = 1000;     // el `limit` de las consultas de detalle
// Cola de ingesta: el final reciente de la ventana aun no esta asentado en el
// log. Retraemos el techo para no dar por cubierto lo que todavia no llego.
const INGESTA_MARGEN_MS = 10 * 60_000;
// Guardia contra un recorte GRUESO del rango: si lo servido (por min o por max)
// cubre menos que esto de lo pedido, el tramo se parte por la mitad. NO es un
// umbral de calidad: una noche tranquila cubre <100 % y esta perfectamente
// observada. A 24 h la API sirve entero, asi que esto casi nunca dispara.
const COBERTURA_MINIMA = 0.9;

const argv = process.argv.slice(2);
const opciones = new Set(argv.filter((a) => a.startsWith('--')));
const permitidos = new Set(['--dias', '--resumen', '--gate', '--help', '-h']);
const desconocidos = [...opciones].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (opciones.has('--help') || opciones.has('-h')) {
  console.log('npm run evidencia:f7 [-- --dias N] [-- --resumen] [-- --gate]');
  process.exit(0);
}
const diasPedidos = (() => {
  const i = argv.indexOf('--dias');
  if (i === -1) return RETENCION_DIAS;
  const n = Number(argv[i + 1]);
  if (!Number.isFinite(n) || n <= 0) fallar('--dias necesita un numero positivo');
  return n;
})();

function fallar(mensaje, detalle) {
  console.error(`\n❌ ${mensaje}`);
  if (detalle) console.error(String(detalle).trim().slice(0, 4000));
  process.exit(1);
}

// Los sellos del canal vienen en MICROsegundos desde epoch, no en ISO:
// compararlos como texto contra un ISO da siempre falso.
const deMicros = (n) => (n === null || n === undefined ? null : new Date(Number(n) / 1000).toISOString());
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// 0) Credenciales y proyecto
// ---------------------------------------------------------------------------
function leerToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const archivo = join(homedir(), '.supabase', 'access-token');
  if (existsSync(archivo)) {
    const t = readFileSync(archivo, 'utf8').trim();
    if (t) return t;
  }
  const r = spawnSync('security', ['find-generic-password', '-s', 'Supabase CLI', '-w'],
    { encoding: 'utf8' });
  const t = (r.stdout ?? '').trim();
  if (r.status === 0 && t) return t;
  fallar(
    'No hay token de la API de gestion.',
    'Exporta SUPABASE_ACCESS_TOKEN, o lanza el guion desde una sesion que pueda\n' +
    'leer el llavero (entrada «Supabase CLI»).',
  );
}

function leerRef() {
  const archivo = join(CRM_ROOT, 'supabase/.temp/project-ref');
  if (!existsSync(archivo)) fallar('No encuentro supabase/.temp/project-ref (¿proyecto sin enlazar?)');
  return readFileSync(archivo, 'utf8').trim();
}

// ---------------------------------------------------------------------------
// 1) Las piezas, leidas del LIBRO vivo
// ---------------------------------------------------------------------------
function leerPiezas() {
  const r = spawnSync('npx', ['supabase', 'db', 'query', '--linked', '--file', PIEZAS_SQL],
    { cwd: CRM_ROOT, encoding: 'utf8', env: process.env });
  if (r.error) fallar(`No se pudo ejecutar supabase CLI: ${r.error.message}`);
  const salida = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  // Trampa heredada: `db query` sale con 0 aunque la consulta reviente; el
  // error viaja DENTRO del JSON.
  const m = /\{[\s\S]*\}/.exec(salida);
  if (!m) fallar('El servidor no devolvio JSON al pedir las piezas', salida);
  let d;
  try { d = JSON.parse(m[0]); } catch { fallar('JSON ilegible al pedir las piezas', salida); }
  if (!Array.isArray(d.rows)) fallar('El servidor devolvio un error al pedir las piezas', salida);
  const piezas = d.rows[0]?.piezas;
  if (!Array.isArray(piezas) || piezas.length === 0) {
    fallar('El libro no devolvio ni una pieza en observacion (¿ya se demolieron todas?)');
  }
  return piezas;
}

// ---------------------------------------------------------------------------
// 2) El canal, con reintentos y ritmo
// ---------------------------------------------------------------------------
let token, ref;
async function consultar(sql, desde, hasta) {
  let ultimo = '';
  for (let intento = 1; intento <= REINTENTOS; intento++) {
    const url = new URL(`${API}/v1/projects/${ref}/analytics/endpoints/logs.all`);
    url.searchParams.set('sql', sql);
    url.searchParams.set('iso_timestamp_start', desde.toISOString());
    url.searchParams.set('iso_timestamp_end', hasta.toISOString());
    try {
      const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
      const texto = await res.text();
      ultimo = `HTTP ${res.status} ${texto.slice(0, 300)}`;
      if (res.ok) {
        const d = JSON.parse(texto);
        // Ojo: el canal devuelve 200 CON un `error` dentro. Leerlo como «sin
        // filas» haria mentir al acta.
        if (!d.error) { await espera(PAUSA_MS); return d.result ?? []; }
        ultimo = `200 con error: ${String(d.error).slice(0, 250)}`;
      }
    } catch (e) {
      ultimo = `red: ${e.message}`;
    }
    await espera(PAUSA_MS * intento);
  }
  fallar('La API de registros no respondio bien tras varios intentos', ultimo);
}

// Bordes de CADA stream por separado: un tramo con edge vacio puede tener
// postgres lleno, y al reves. Medir solo edge_logs (como antes) ciega el otro.
const bordes = (fuente) =>
  `select min(t.timestamp) as suelo, max(t.timestamp) as techo, count(*) as n from ${fuente} t`;

const sqlRutas = (nombres) => `
  select t.timestamp, request.path as ruta, request.method as metodo,
         response.status_code as estado
  from edge_logs t
  cross join unnest(t.metadata) as m
  cross join unnest(m.request) as request
  cross join unnest(m.response) as response
  where ${nombres.map((n) => `request.path like '%/rpc/${n}%'`).join(' or ')}
  order by t.timestamp desc limit ${LIMITE_FILAS}`;

// 🔴 AQUI HUBO UN FALSO POSITIVO INDUSTRIAL, medido el 04/09. Buscar el nombre
//    de la pieza en TODO postgres_logs devolvia 55, 13, 9... rastros por pieza,
//    y los 34 mensajes distintos eran NUESTRO PROPIO TRABAJO: el texto de las
//    migraciones F5.b/c/d y F7.1/7.2, sus ensayos y los mensajes de sus guardas.
//    Una migracion que NOMBRA la pieza no es alguien LLAMANDOLA.
//    La forma real (medida): los registros de sentencia son severidad LOG y
//    codigo 00000; un intento denegado es severidad ERROR. Se filtra por eso.
const sqlPostgres = (nombres) => `
  select t.timestamp, t.event_message, parsed.error_severity as severidad,
         parsed.sql_state_code as codigo
  from postgres_logs t
  cross join unnest(t.metadata) as m
  cross join unnest(m.parsed) as parsed
  where parsed.error_severity = 'ERROR'
    and (${nombres.map((n) => `t.event_message like '%${n}%'`).join(' or ')})
  order by t.timestamp desc limit ${LIMITE_FILAS}`;

// 🔴 SONDA D — la denegacion de ESQUEMA no nombra la pieza. Si un rol pierde el
//    USAGE de `crm`/`public`, la llamada muere ANTES de resolver la funcion y
//    el error es `permission denied for schema crm`, que el filtro por nombre
//    de arriba jamas veria. Se busca aparte, y CUALQUIER golpe obliga a
//    adjudicar a ojo: el gate no da verde hasta que un humano lo explique.
const sqlDenegacionEsquema = `
  select t.timestamp, t.event_message
  from postgres_logs t
  cross join unnest(t.metadata) as m
  cross join unnest(m.parsed) as parsed
  where parsed.error_severity = 'ERROR'
    and (t.event_message like '%permission denied for schema crm%'
      or t.event_message like '%permission denied for schema public%')
  order by t.timestamp desc limit ${LIMITE_FILAS}`;

// 🔴 SEGUNDO FILTRO, Y HACE FALTA. Quedarse en «severidad ERROR que nombra la
//    pieza» seguia dando 7 rastros, y los 7 eran NUESTRAS PROPIAS GUARDAS
//    gritando durante los ensayos (el trigger del libro F7, el preflight de la
//    F5, la sonda de OID). Dos de ellos incluso con codigo 42501, porque
//    nuestro propio `raise ... using errcode` usa ese codigo: el codigo NO
//    distingue. Lo que distingue es QUIEN redacto el mensaje.
//    Una denegacion de verdad la redacta POSTGRES, y solo tiene estas formas
//    (con o sin el esquema calificando el nombre):
//      * `permission denied for function [crm.|public.]X`  (viva, sin EXECUTE)
//      * `function [crm.|public.]X(...) does not exist`     (ya demolida)
//    Todo lo demas es prosa nuestra: se guarda aparte para mirarla a ojo, pero
//    NO cuenta como intento. Contarla haria imposible leer el veredicto.
const esDenegacionDePostgres = (msg, nombre) => {
  const m = String(msg ?? '');
  const denegada = m.includes(`permission denied for function ${nombre}`)
    || m.includes(`permission denied for function crm.${nombre}`)
    || m.includes(`permission denied for function public.${nombre}`);
  const inexistente = m.includes(nombre) && m.includes('does not exist') && m.includes('function');
  return denegada || inexistente;
};

// ---------------------------------------------------------------------------
// 3) Lectura de las actas ya cosechadas
// ---------------------------------------------------------------------------
function actas() {
  if (!existsSync(DIR_ACTAS)) return [];
  return readdirSync(DIR_ACTAS)
    .filter((f) => f.endsWith('.json'))
    .map((f) => { try { return JSON.parse(readFileSync(join(DIR_ACTAS, f), 'utf8')); } catch { return null; } })
    .filter(Boolean)
    .sort((a, b) => String(a.cosechado_en).localeCompare(String(b.cosechado_en)));
}

// Une los tramos OBSERVADOS (lo que de verdad se pudo mirar, NO lo pedido) y
// devuelve intervalos [desde, hasta] fusionados. Un tramo truncado o partido
// que no llego a asentarse no entra: solo cuenta lo cubierto de verdad.
function fusionarObservado(lista) {
  const tramos = lista
    .filter((t) => t?.observado?.desde && t?.observado?.hasta && !t.truncado)
    .map((t) => [t.observado.desde, t.observado.hasta])
    .sort((x, y) => x[0].localeCompare(y[0]));
  const unidos = [];
  for (const [d, h] of tramos) {
    const ult = unidos[unidos.length - 1];
    if (ult && d <= ult[1]) ult[1] = h > ult[1] ? h : ult[1];
    else unidos.push([d, h]);
  }
  return unidos;
}

function tramosCubiertos(lista) {
  return fusionarObservado(lista.flatMap((a) => a.tramos ?? []));
}

// ¿El intervalo [ini, fin] esta cubierto ENTERO por los tramos unidos?
// Devuelve los huecos que falten (vacio = cubierto).
function huecosEn(ini, fin, unidos) {
  const huecos = [];
  let cursor = ini;
  for (const [d, h] of unidos) {
    if (h <= cursor) continue;
    if (d > cursor) { huecos.push([cursor, d < fin ? d : fin]); }
    if (h > cursor) cursor = h;
    if (cursor >= fin) break;
  }
  if (cursor < fin) huecos.push([cursor, fin]);
  return huecos.filter(([a, b]) => a < b);
}

// ---------------------------------------------------------------------------
// 3a) `--resumen`: informativo, siempre sale 0
// ---------------------------------------------------------------------------
if (opciones.has('--resumen')) {
  const todas = actas();
  if (todas.length === 0) { console.log('Todavia no hay ni un acta cosechada.'); process.exit(0); }
  const u = tramosCubiertos(todas);
  console.log(`\n${todas.length} acta(s). TRAMOS OBSERVADOS ya cosechados:`);
  for (const [d, h] of u) console.log(`  ${d}  ->  ${h}`);
  const huecos = u.slice(1).map((t, i) => [u[i][1], t[0]]).filter(([a, b]) => a < b);
  if (huecos.length > 0) {
    console.log('\n⚠️  HUECOS entre tramos observados (dias que ya no se recuperan):');
    for (const [a, b] of huecos) console.log(`  ${a}  ->  ${b}`);
  } else {
    console.log('\n✅ Sin huecos entre los tramos observados.');
  }
  const truncados = todas.flatMap((a) => a.tramos ?? []).filter((t) => t.truncado);
  if (truncados.length > 0) console.log(`\n⚠️  ${truncados.length} tramo(s) TRUNCADO(s) (tocaron el limite de ${LIMITE_FILAS}).`);
  const conRastro = todas.flatMap((a) => a.hallazgos.filter((h) => h.intentos > 0 || h.intentos_postgres > 0));
  console.log(`\nPiezas con rastro en el conjunto de actas: ${conRastro.length}`);
  for (const h of conRastro) console.log(`  ${h.firma}: ruta ${h.intentos}, postgres ${h.intentos_postgres}`);
  const esq = todas.flatMap((a) => a.denegaciones_esquema ?? []);
  if (esq.length > 0) console.log(`\nℹ️  ${esq.length} denegacion(es) de ESQUEMA (aviso, no bloquean: no nombran funcion ni las produce el cierre F7).`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 3b) `--gate`: EL FRENO. No consulta; decide sobre las actas. Sale != 0.
// ---------------------------------------------------------------------------
if (opciones.has('--gate')) {
  ref = leerRef();
  const piezas = leerPiezas();
  const hoy = new Date();
  const todas = actas().filter((a) => a.proyecto === ref); // proyecto ajeno NO cuenta
  const problemas = [];

  if (todas.length === 0) fallar('El gate no tiene ni un acta de este proyecto sobre la que decidir.');

  // Denegaciones de ESQUEMA: `permission denied for schema crm` NO nombra la
  // funcion, asi que NO se puede atribuir a ninguna de nuestras piezas — y NO
  // la produce nuestro cierre (revocamos EXECUTE de la funcion, no el USAGE del
  // esquema; un cierre nuestro diria «for function»). Son ruido de fondo de un
  // rol sin USAGE. Se REPORTAN como aviso, no bloquean: bloquear con esto
  // dejaria el gate rojo para siempre y la gente lo saltaria con --force.
  const esquema = todas.flatMap((a) => (a.denegaciones_esquema ?? []).map((e) => ({ ...e, acta: a.cosechado_en })));

  for (const p of piezas) {
    const tocaDemoler = p.drop_no_antes_de && new Date(p.drop_no_antes_de) <= hoy;
    if (!tocaDemoler) continue; // solo se juzga lo que ya toca derribar

    const ventanaIni = p.cerrada_en;                 // la observacion empieza al CERRAR
    const ventanaFin = p.drop_no_antes_de;           // y termina el dia del drop
    const unidos = tramosCubiertos(todas);
    const huecos = huecosEn(ventanaIni, ventanaFin, unidos);
    if (huecos.length > 0) {
      problemas.push(`${p.firma}: ventana [${ventanaIni} .. ${ventanaFin}] con ${huecos.length} hueco(s) sin observar; el primero ${huecos[0][0]} -> ${huecos[0][1]}`);
    }

    // Truncamiento que solape la ventana: no me fio del conteo de ese tramo.
    const truncados = todas.flatMap((a) => a.tramos ?? [])
      .filter((t) => t.truncado && t.pedido?.hasta > ventanaIni && t.pedido?.desde < ventanaFin);
    if (truncados.length > 0) {
      problemas.push(`${p.firma}: ${truncados.length} tramo(s) TRUNCADO(s) dentro de su ventana; el conteo no es de fiar.`);
    }

    // Rastro DENTRO de la ventana de observacion (ts >= cerrada_en). Un uso
    // ANTERIOR al cierre era legitimo (la pieza estaba abierta): no cuenta.
    let ruta = 0, pg = 0;
    for (const a of todas) {
      const h = (a.hallazgos ?? []).find((x) => x.firma === p.firma);
      if (!h) continue;
      ruta += (h.muestras ?? []).filter((s) => s.ts && s.ts >= ventanaIni && s.ts <= ventanaFin).length;
      pg += (h.muestras_postgres ?? []).filter((s) => s.ts && s.ts >= ventanaIni && s.ts <= ventanaFin).length;
    }
    if (ruta > 0 || pg > 0) {
      problemas.push(`${p.firma}: rastro DENTRO de la ventana (ruta ${ruta}, postgres ${pg}). No se demuele sin explicar quien llamo.`);
    }
  }

  const esqTotal = esquema.length;

  const enJuego = piezas.filter((p) => p.drop_no_antes_de && new Date(p.drop_no_antes_de) <= hoy);
  console.log(`Gate de evidencia F7 · proyecto ${ref} · ${todas.length} acta(s)`);
  console.log(`Piezas que HOY (${hoy.toISOString().slice(0, 10)}) ya tocaria demoler: ${enJuego.length}`);
  if (enJuego.length === 0) {
    console.log('\n✅ Ninguna pieza ha llegado aun a su fecha de drop. Nada que frenar hoy.');
    process.exit(0);
  }
  if (esqTotal > 0) {
    console.log(`\nℹ️  ${esqTotal} denegacion(es) de ESQUEMA en el conjunto de actas (aviso, NO bloqueo):`);
    console.log('   `permission denied for schema` no nombra funcion ni la produce nuestro cierre.');
    console.log('   Es ruido de un rol sin USAGE. Si un pico coincide con una ventana, mirarlo a ojo.');
  }
  if (problemas.length > 0) {
    console.error(`\n⛔ GATE ROJO — ${problemas.length} motivo(s). NO se aplica ninguna demolicion:`);
    for (const m of problemas) console.error(`   • ${m}`);
    console.error('\n   Recuerda: esto es UNA pata. La otra es el censo estructural de la migracion.');
    process.exit(2);
  }
  console.log(`\n✅ GATE VERDE para ${enJuego.length} pieza(s): ventana [cerrada..drop] cubierta y sin rastro.`);
  console.log('   ⚠️  Sigue haciendo falta el censo estructural (quien NOMBRA la pieza) de la migracion.');
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 4) La cosecha, tramo a tramo
// ---------------------------------------------------------------------------
token = leerToken();
ref = leerRef();
const piezas = leerPiezas();
const nombres = [...new Set(piezas.map((p) => p.nombre_rpc))];

// El techo se retrae por la cola de ingesta (E): lo mas reciente aun no asento.
const hasta = new Date(Date.now() - INGESTA_MARGEN_MS);
const desde = new Date(hasta.getTime() - diasPedidos * TRAMO_MS);

console.log(`Proyecto ${ref} · ${piezas.length} piezas · ${nombres.length} nombres distintos`);
console.log(`Ventana PEDIDA: ${desde.toISOString()} -> ${hasta.toISOString()} (${diasPedidos} d, techo retraido ${INGESTA_MARGEN_MS / 60000} min por ingesta)`);
console.log(`Se consulta en tramos de 24 h: un barrido largo devuelve solo el tramo mas viejo.\n`);

/**
 * Mide UN stream en [d, h]. Un tramo <=24 h no truncado se observa ENTERO:
 * `observado` = la ventana PEDIDA, no [min, max] (ver nota B). El min/max solo
 * sirve de guardia contra un recorte GRUESO del rango: si lo servido cubre
 * <COBERTURA_MINIMA de lo pedido, se parte por la mitad; y si ni al llegar al
 * suelo de 1 h remonta, la hoja queda PARCIAL con su ventana real [min, max].
 */
async function medirStream(fuente, d, h, profundidad = 0) {
  const r = (await consultar(bordes(fuente), d, h))[0];
  const n = Number(r?.n ?? 0);
  const suelo = deMicros(r?.suelo);
  const techo = deMicros(r?.techo);
  const pedido = { desde: d.toISOString(), hasta: h.toISOString() };
  if (n === 0) return [{ pedido, observado: { desde: null, hasta: null }, filas: 0, vacio: true }];

  const total = h - d;
  const cobertura = Math.min((new Date(techo) - d) / total, (h - new Date(suelo)) / total);
  const partible = total > TRAMO_MINIMO_MS && profundidad < 5;
  if (cobertura < COBERTURA_MINIMA && partible) {
    console.log(`  ↯ ${fuente} ${pedido.desde.slice(5, 16)}..${pedido.hasta.slice(5, 16)} cubre ${(cobertura * 100).toFixed(0)}% -> se parte`);
    const medio = new Date(d.getTime() + total / 2);
    return [
      ...await medirStream(fuente, d, medio, profundidad + 1),
      ...await medirStream(fuente, medio, h, profundidad + 1),
    ];
  }
  const parcial = cobertura < COBERTURA_MINIMA; // solo si ni partiendo remonto
  return [{
    pedido,
    // OBSERVADO = pedido cuando la hoja se acepta entera; [min,max] si es parcial.
    observado: parcial ? { desde: suelo, hasta: techo } : { desde: pedido.desde, hasta: pedido.hasta },
    filas: n,
    cobertura: Number(cobertura.toFixed(3)),
    parcial,
  }];
}

const tramos = [];
const porNombre = Object.fromEntries(nombres.map((n) => [n, { ruta: [], pg: [], menciones: [] }]));
const denegacionesEsquema = [];

for (let t = diasPedidos; t >= 1; t--) {
  const d = new Date(hasta.getTime() - t * TRAMO_MS);
  const h = new Date(hasta.getTime() - (t - 1) * TRAMO_MS);

  // edge_logs y postgres_logs se miden POR SEPARADO (B): un edge vacio ya no
  // impide mirar postgres. Se usa la union de las hojas de ambos como la
  // rejilla de sub-tramos a consultar de verdad.
  const hojasEdge = await medirStream('edge_logs', d, h);
  const hojasPg = await medirStream('postgres_logs', d, h);
  const cortes = [...new Set([
    ...hojasEdge.flatMap((x) => [x.pedido.desde, x.pedido.hasta]),
    ...hojasPg.flatMap((x) => [x.pedido.desde, x.pedido.hasta]),
  ])].sort();

  for (let i = 0; i < cortes.length - 1; i++) {
    const sd = new Date(cortes[i]);
    const sh = new Date(cortes[i + 1]);
    const edge = hojasEdge.find((x) => x.pedido.desde <= cortes[i] && x.pedido.hasta >= cortes[i + 1]);
    const pgb = hojasPg.find((x) => x.pedido.desde <= cortes[i] && x.pedido.hasta >= cortes[i + 1]);
    const filasEdge = edge && !edge.vacio ? edge.filas : 0;
    const filasPg = pgb && !pgb.vacio ? pgb.filas : 0;

    // El observado del sub-tramo: la interseccion de lo que cada stream cubrio.
    const obsDesde = [edge?.observado?.desde, pgb?.observado?.desde].filter(Boolean).sort().slice(-1)[0] ?? null;
    const obsHasta = [edge?.observado?.hasta, pgb?.observado?.hasta].filter(Boolean).sort()[0] ?? null;
    const parcial = Boolean(edge?.parcial || pgb?.parcial);

    const registro = {
      pedido: { desde: sd.toISOString(), hasta: sh.toISOString() },
      observado: { desde: obsDesde, hasta: obsHasta },
      filas_edge: filasEdge,
      filas_postgres: filasPg,
      filas: filasEdge + filasPg,
      parcial,
    };

    if (filasEdge === 0 && filasPg === 0) {
      registro.vacio = true;
      tramos.push(registro);
      console.log(`  ∅ ${registro.pedido.desde.slice(5, 16)} .. ${registro.pedido.hasta.slice(5, 16)}  sin registros en ningun stream`);
      continue;
    }

    const rutas = filasEdge > 0 ? await consultar(sqlRutas(nombres), sd, sh) : [];
    const pg = filasPg > 0 ? await consultar(sqlPostgres(nombres), sd, sh) : [];
    const esq = filasPg > 0 ? await consultar(sqlDenegacionEsquema, sd, sh) : [];

    // TRUNCAMIENTO (C): si una consulta toco el limite, pudo dejar fuera filas
    // mas viejas. No me fio del conteo de este tramo.
    registro.truncado = rutas.length >= LIMITE_FILAS || pg.length >= LIMITE_FILAS || esq.length >= LIMITE_FILAS;

    for (const f of rutas) {
      const n = nombres.find((x) => String(f.ruta ?? '').includes(`/rpc/${x}`));
      if (n) porNombre[n].ruta.push({ ...f, ts: deMicros(f.timestamp) });
    }
    let denegados = 0;
    for (const f of pg) {
      const n = nombres.find((x) => String(f.event_message ?? '').includes(x));
      if (!n) continue;
      const fila = { ...f, ts: deMicros(f.timestamp) };
      if (esDenegacionDePostgres(f.event_message, n)) { porNombre[n].pg.push(fila); denegados++; }
      else porNombre[n].menciones.push(fila);
    }
    for (const f of esq) denegacionesEsquema.push({ ts: deMicros(f.timestamp), event_message: String(f.event_message ?? '').slice(0, 300) });

    tramos.push(registro);
    const aviso = registro.truncado ? ' ⚠️TRUNCADO' : (registro.parcial ? ' ⚠️parcial' : '');
    console.log(`  ✓ ${registro.pedido.desde.slice(5, 16)} .. ${registro.pedido.hasta.slice(5, 16)}  edge ${filasEdge} / pg ${filasPg} · rutas ${rutas.length} · denegaciones ${denegados} (de ${pg.length} que nombran una pieza) · esquema ${esq.length}${aviso}`);
  }
}

const hallazgos = piezas.map((p) => ({
  firma: p.firma,
  ola: p.ola,
  nombre_rpc: p.nombre_rpc,
  cerrada_en: p.cerrada_en,
  drop_no_antes_de: p.drop_no_antes_de,
  d7: p.d7,
  d14: p.d14,
  intentos: porNombre[p.nombre_rpc].ruta.length,
  intentos_postgres: porNombre[p.nombre_rpc].pg.length,
  // Errores que NOMBRAN la pieza sin ser una denegacion de Postgres: casi
  // siempre nuestras propias guardas en un ensayo. Se guardan para mirarlas,
  // nunca se cuentan como intento.
  menciones_en_errores: porNombre[p.nombre_rpc].menciones.length,
  // Se guardan TODAS hasta el limite de truncamiento: asi el gate cuenta el
  // rastro real dentro de la ventana sin que el tope muerda antes que el
  // truncamiento (que ya frena por su cuenta). Con 0 rastros el acta es minima.
  muestras: porNombre[p.nombre_rpc].ruta.slice(0, LIMITE_FILAS),
  muestras_postgres: porNombre[p.nombre_rpc].pg.slice(0, LIMITE_FILAS),
  muestras_menciones: porNombre[p.nombre_rpc].menciones.slice(0, 20),
}));

const observados = tramos.filter((t) => !t.vacio && !t.parcial && !t.truncado);
const unidos = fusionarObservado(tramos);
const cubierto = {
  desde: unidos.length ? unidos[0][0] : null,
  hasta: unidos.length ? unidos[unidos.length - 1][1] : null,
};

mkdirSync(DIR_ACTAS, { recursive: true });
const sello = hasta.toISOString().replace(/[:.]/g, '-');
const acta = {
  cosechado_en: hasta.toISOString(),
  proyecto: ref,
  dialecto: 'bigquery',
  // ⚠️ NO es una medicion viva: es el valor documentado por Supabase (Pro).
  retencion_dias_declarada: RETENCION_DIAS,
  margen_ingesta_min: INGESTA_MARGEN_MS / 60000,
  limite_filas_por_consulta: LIMITE_FILAS,
  ventana_pedida: { desde: desde.toISOString(), hasta: hasta.toISOString() },
  ventana_cubierta_por_tramos: cubierto,
  tramos,
  // La ruta de PostgREST no distingue crm.X de public.X (el esquema viaja en
  // Accept-Profile / Content-Profile, que el log NO conserva). Un intento
  // cuenta para las dos piezas homonimas: conservador, nunca falso verde.
  nota_ambiguedad_esquema: true,
  // 🔴 LO QUE ESTE METODO NO VE: un EXITO. track_functions=none + pgaudit=none:
  // una llamada exitosa de postgres/owner por conexion directa no deja rastro.
  // La prueba fuerte es el censo estructural de la migracion, no esta acta.
  no_ve_exitos: true,
  denegaciones_esquema: denegacionesEsquema,
  hallazgos,
};
writeFileSync(join(DIR_ACTAS, `${sello}.json`), `${JSON.stringify(acta, null, 2)}\n`);

const conRastro = hallazgos.filter((h) => h.intentos > 0 || h.intentos_postgres > 0);
const truncados = tramos.filter((t) => t.truncado);
const parciales = tramos.filter((t) => t.parcial && !t.vacio);
console.log(`\nTramos observados limpios: ${observados.length} · registros mirados: ${tramos.reduce((a, t) => a + (t.filas || 0), 0)}`);
console.log(`Acta guardada: supabase/scripts/evidencia-f7/${sello}.json`);
if (truncados.length > 0) console.log(`\n⚠️  ${truncados.length} tramo(s) TRUNCADO(s): tocaron el limite de ${LIMITE_FILAS}. El gate los frena.`);
if (parciales.length > 0) console.log(`⚠️  ${parciales.length} tramo(s) PARCIAL(es): ni partiendo llegaron a cubrir la ventana.`);
if (denegacionesEsquema.length > 0) console.log(`ℹ️  ${denegacionesEsquema.length} denegacion(es) de ESQUEMA (aviso): 'for schema' no nombra funcion ni la produce nuestro cierre. Ruido de un rol sin USAGE; no bloquea.`);
const conMenciones = hallazgos.filter((h) => h.menciones_en_errores > 0);
if (conMenciones.length > 0) {
  console.log(`\nℹ️  ${conMenciones.length} pieza(s) NOMBRADAS en errores que NO son denegaciones`);
  console.log('   (guardas propias en ensayos). Quedan en el acta para mirarlas a ojo.');
}
if (conRastro.length === 0) {
  console.log(
    `\n✅ SIN EVIDENCIA DE USO en los tramos observados (${cubierto.desde} -> ${cubierto.hasta}).` +
    '\n   (Esto NO dice que nadie lo usara: dice que en ESTOS tramos no hay rastro DE FRACASO.' +
    '\n    Un exito por conexion directa es invisible aqui — de eso responde el censo de la migracion.)',
  );
} else {
  console.log(`\n⚠️  ${conRastro.length} pieza(s) CON rastro:`);
  for (const h of conRastro) console.log(`   ${h.firma}: ruta ${h.intentos}, postgres ${h.intentos_postgres}`);
  console.log('   Ninguna de estas se demuele sin explicar quien llamo y por que.');
}
