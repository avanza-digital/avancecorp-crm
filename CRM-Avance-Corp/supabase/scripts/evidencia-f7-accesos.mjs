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
//    que se pidio.
//
// ─── LO QUE SE MIDIO EL 04/09/2026 MONTANDO ESTO (y por que el guion es asi) ──
//
// 🔴 1. UNA CONSULTA DE VARIOS DIAS DEVUELVE SOLO UNO, EN SILENCIO.
//    Pedir 7 dias devolvio 12 449 registros con un 200 OK; los mismos 7 dias
//    troceados en ventanas de 24 h suman 115 185. La API sirvio el 10,8 % —el
//    dia MAS VIEJO— sin marcar el resultado como parcial. Un guion que pidiera
//    la semana entera y viera «0 intentos» certificaria una semana limpia
//    habiendo mirado un dia. Por eso aqui se consulta DIA A DIA y cada tramo
//    comprueba que lo observado cubre lo pedido; si no, se parte por la mitad.
//
// 🔴 2. LA API REBOTA Y ADEMAS LIMITA EL RITMO. La misma consulta devolvio 500
//    y, repetida, 200 con datos; y encadenar peticiones sin pausa acaba en
//    429 (ThrottlerException). Un error tratado como «no hay filas» fabrica el
//    falso verde. Aqui un fallo ABORTA, y antes reintenta con pausas.
//
// 🔴 3. LA RETENCION SON 7 DIAS EXACTOS. A 7 dias el suelo cae en 2026-08-28;
//    a 8 dias la fuente devuelve CERO filas. Es una ventana rodante y dura:
//    el tramo de 14 dias que exige el metodo NO se puede mirar de una vez — se
//    COSE con lecturas sucesivas, y cada lectura queda guardada como acta. Una
//    lectura que no se hizo a tiempo es un tramo perdido PARA SIEMPRE. Por eso
//    se cosecha seguido, no solo en D+7 y D+14.
//
// 🔑 4. EL DIALECTO ES EL VIEJO (BigQuery, con `cross join unnest`). La
//    documentacion nueva describe uno de ClickHouse (`from logs where
//    source = ...`) que en ESTE proyecto responde con error de backend.
//
// 🔑 5. LA RUTA NO DISTINGUE EL ESQUEMA. `crm.mi_acceso_fn` —que solo existe
//    en `crm`— entra por `/rest/v1/rpc/mi_acceso_fn`, igual que una de
//    `public`: el esquema viaja en una cabecera. Un intento contra
//    `/rpc/crear_contrato_producto` cuenta para las DOS piezas homonimas, y el
//    acta lo dice en vez de fingir precision que no tiene.
//
// Uso:
//   npm run evidencia:f7                 -> cosecha los ultimos 7 dias
//   npm run evidencia:f7 -- --dias 3     -> ventana mas corta
//   npm run evidencia:f7 -- --resumen    -> no consulta: lee las actas ya
//                                           cosechadas y dice que tramos
//                                           quedan cubiertos y donde hay huecos

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const CRM_ROOT = fileURLToPath(new URL('../..', import.meta.url));
const PIEZAS_SQL = 'supabase/scripts/evidencia-f7-piezas.sql';
const DIR_ACTAS = join(CRM_ROOT, 'supabase/scripts/evidencia-f7');
const API = 'https://api.supabase.com';
const RETENCION_DIAS = 7;      // medido, no supuesto
const REINTENTOS = 5;
const PAUSA_MS = 6000;         // ritmo que el canal aguanta sin 429
const TRAMO_MS = 86400_000;    // 24 h: el tamano que SI devuelve completo
const TRAMO_MINIMO_MS = 3600_000;
// Un tramo se acepta si lo observado llega al menos hasta aqui de lo pedido.
const COBERTURA_MINIMA = 0.9;

const argv = process.argv.slice(2);
const opciones = new Set(argv.filter((a) => a.startsWith('--')));
const permitidos = new Set(['--dias', '--resumen', '--help', '-h']);
const desconocidos = [...opciones].filter((a) => !permitidos.has(a));
if (desconocidos.length > 0) fallar(`Opciones desconocidas: ${desconocidos.join(', ')}`);
if (opciones.has('--help') || opciones.has('-h')) {
  console.log('npm run evidencia:f7 [-- --dias N] [-- --resumen]');
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

const BORDES = 'select min(t.timestamp) as suelo, max(t.timestamp) as techo, count(*) as n from edge_logs t';

const sqlRutas = (nombres) => `
  select t.timestamp, request.path as ruta, request.method as metodo,
         response.status_code as estado
  from edge_logs t
  cross join unnest(t.metadata) as m
  cross join unnest(m.request) as request
  cross join unnest(m.response) as response
  where ${nombres.map((n) => `request.path like '%/rpc/${n}%'`).join(' or ')}
  order by t.timestamp desc limit 1000`;

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
  order by t.timestamp desc limit 1000`;

// 🔴 SEGUNDO FILTRO, Y HACE FALTA. Quedarse en «severidad ERROR que nombra la
//    pieza» seguia dando 7 rastros, y los 7 eran NUESTRAS PROPIAS GUARDAS
//    gritando durante los ensayos (el trigger del libro F7, el preflight de la
//    F5, la sonda de OID). Dos de ellos incluso con codigo 42501, porque
//    nuestro propio `raise ... using errcode` usa ese codigo: el codigo NO
//    distingue. Lo que distingue es QUIEN redacto el mensaje.
//    Una denegacion de verdad la redacta POSTGRES, y solo tiene dos formas:
//      * `permission denied for function X`   (pieza viva, sin EXECUTE)
//      * `function X(...) does not exist`     (pieza ya demolida)
//    Todo lo demas es prosa nuestra: se guarda aparte para mirarla a ojo, pero
//    NO cuenta como intento. Contarla haria imposible leer el veredicto.
const esDenegacionDePostgres = (msg, nombre) => {
  const m = String(msg ?? '');
  return m.includes(`permission denied for function ${nombre}`)
    || (m.includes(nombre) && m.includes('does not exist') && m.includes('function'));
};

// ---------------------------------------------------------------------------
// 3) Resumen de lo ya cosechado (no consulta al servidor)
// ---------------------------------------------------------------------------
function actas() {
  if (!existsSync(DIR_ACTAS)) return [];
  return readdirSync(DIR_ACTAS)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(DIR_ACTAS, f), 'utf8')))
    .sort((a, b) => a.cosechado_en.localeCompare(b.cosechado_en));
}

function tramosCubiertos() {
  // Une los tramos OBSERVADOS (no los pedidos) y devuelve los huecos.
  const tramos = actas()
    .flatMap((a) => a.tramos ?? [])
    .filter((t) => t.observado?.desde && t.observado?.hasta)
    .map((t) => [t.pedido.desde, t.pedido.hasta])
    .sort((x, y) => x[0].localeCompare(y[0]));
  const unidos = [];
  for (const [d, h] of tramos) {
    const ult = unidos[unidos.length - 1];
    if (ult && d <= ult[1]) ult[1] = h > ult[1] ? h : ult[1];
    else unidos.push([d, h]);
  }
  return unidos;
}

if (opciones.has('--resumen')) {
  const todas = actas();
  if (todas.length === 0) {
    console.log('Todavia no hay ni un acta cosechada.');
    process.exit(0);
  }
  const u = tramosCubiertos();
  console.log(`\n${todas.length} acta(s). TRAMOS DE REGISTRO YA COSECHADOS:`);
  for (const [d, h] of u) console.log(`  ${d}  ->  ${h}`);
  const huecos = u.slice(1).map((t, i) => [u[i][1], t[0]]).filter(([a, b]) => a < b);
  if (huecos.length > 0) {
    console.log('\n⚠️  HUECOS sin cosechar (dias que ya no se pueden recuperar):');
    for (const [a, b] of huecos) console.log(`  ${a}  ->  ${b}`);
  } else {
    console.log('\n✅ Sin huecos entre actas.');
  }
  const conRastro = todas.flatMap((a) => a.hallazgos.filter((h) => h.intentos > 0 || h.intentos_postgres > 0));
  console.log(`\nPiezas con rastro en el conjunto de actas: ${conRastro.length}`);
  for (const h of conRastro) console.log(`  ${h.firma}: ruta ${h.intentos}, postgres ${h.intentos_postgres}`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 4) La cosecha, tramo a tramo
// ---------------------------------------------------------------------------
token = leerToken();
ref = leerRef();
const piezas = leerPiezas();
const nombres = [...new Set(piezas.map((p) => p.nombre_rpc))];

const hasta = new Date();
const desde = new Date(hasta.getTime() - diasPedidos * TRAMO_MS);

console.log(`Proyecto ${ref} · ${piezas.length} piezas · ${nombres.length} nombres distintos`);
console.log(`Ventana PEDIDA: ${desde.toISOString()} -> ${hasta.toISOString()} (${diasPedidos} d)`);
console.log(`Se consulta en tramos de 24 h: un barrido largo devuelve solo el tramo mas viejo.\n`);

/** Mide un tramo y, si lo observado no cubre lo pedido, lo parte por la mitad. */
async function medirTramo(d, h, profundidad = 0) {
  const r = (await consultar(BORDES, d, h))[0];
  const n = Number(r?.n ?? 0);
  const suelo = deMicros(r?.suelo);
  const techo = deMicros(r?.techo);
  const pedido = { desde: d.toISOString(), hasta: h.toISOString() };

  if (n === 0) return [{ pedido, observado: { desde: null, hasta: null }, filas: 0, vacio: true }];

  const cubre = (new Date(techo) - d) / (h - d);
  const partible = (h - d) > TRAMO_MINIMO_MS && profundidad < 5;
  if (cubre < COBERTURA_MINIMA && partible) {
    console.log(`  ↯ tramo ${pedido.desde.slice(5, 16)}..${pedido.hasta.slice(5, 16)} cubre solo ${(cubre * 100).toFixed(0)}% -> se parte`);
    const medio = new Date(d.getTime() + (h - d) / 2);
    return [...await medirTramo(d, medio, profundidad + 1), ...await medirTramo(medio, h, profundidad + 1)];
  }
  return [{ pedido, observado: { desde: suelo, hasta: techo }, filas: n, cobertura: Number(cubre.toFixed(3)) }];
}

const tramos = [];
const porNombre = Object.fromEntries(nombres.map((n) => [n, { ruta: [], pg: [], menciones: [] }]));

for (let t = diasPedidos; t >= 1; t--) {
  const d = new Date(hasta.getTime() - t * TRAMO_MS);
  const h = new Date(hasta.getTime() - (t - 1) * TRAMO_MS);
  const medidos = await medirTramo(d, h);
  for (const m of medidos) {
    tramos.push(m);
    if (m.vacio) {
      console.log(`  ∅ ${m.pedido.desde.slice(5, 16)} .. ${m.pedido.hasta.slice(5, 16)}  sin registros`);
      continue;
    }
    const rutas = await consultar(sqlRutas(nombres), new Date(m.pedido.desde), new Date(m.pedido.hasta));
    const pg = await consultar(sqlPostgres(nombres), new Date(m.pedido.desde), new Date(m.pedido.hasta));
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
    console.log(`  ✓ ${m.pedido.desde.slice(5, 16)} .. ${m.pedido.hasta.slice(5, 16)}  ${m.filas} registros · rutas ${rutas.length} · denegaciones ${denegados} (de ${pg.length} errores que nombran una pieza)`);
  }
}

const hallazgos = piezas.map((p) => ({
  firma: p.firma,
  ola: p.ola,
  nombre_rpc: p.nombre_rpc,
  cerrada_en: p.cerrada_en,
  d7: p.d7,
  d14: p.d14,
  intentos: porNombre[p.nombre_rpc].ruta.length,
  intentos_postgres: porNombre[p.nombre_rpc].pg.length,
  // Errores que NOMBRAN la pieza sin ser una denegacion de Postgres: casi
  // siempre nuestras propias guardas en un ensayo. Se guardan para mirarlas,
  // nunca se cuentan como intento.
  menciones_en_errores: porNombre[p.nombre_rpc].menciones.length,
  muestras: porNombre[p.nombre_rpc].ruta.slice(0, 20),
  muestras_postgres: porNombre[p.nombre_rpc].pg.slice(0, 10),
  muestras_menciones: porNombre[p.nombre_rpc].menciones.slice(0, 10),
}));

const observados = tramos.filter((t) => !t.vacio);
const cubierto = {
  desde: observados.length ? observados[0].pedido.desde : null,
  hasta: observados.length ? observados[observados.length - 1].pedido.hasta : null,
};

mkdirSync(DIR_ACTAS, { recursive: true });
const sello = hasta.toISOString().replace(/[:.]/g, '-');
const acta = {
  cosechado_en: hasta.toISOString(),
  proyecto: ref,
  dialecto: 'bigquery',
  retencion_dias_medida: RETENCION_DIAS,
  ventana_pedida: { desde: desde.toISOString(), hasta: hasta.toISOString() },
  ventana_cubierta_por_tramos: cubierto,
  tramos,
  // La ruta de PostgREST no distingue crm.X de public.X (el esquema viaja en
  // una cabecera). Un intento cuenta para las dos piezas homonimas.
  nota_ambiguedad_esquema: true,
  hallazgos,
};
writeFileSync(join(DIR_ACTAS, `${sello}.json`), `${JSON.stringify(acta, null, 2)}\n`);

const conRastro = hallazgos.filter((h) => h.intentos > 0 || h.intentos_postgres > 0);
console.log(`\nTramos observados: ${observados.length} · registros mirados: ${observados.reduce((a, t) => a + t.filas, 0)}`);
console.log(`Acta guardada: supabase/scripts/evidencia-f7/${sello}.json`);
const conMenciones = hallazgos.filter((h) => h.menciones_en_errores > 0);
if (conMenciones.length > 0) {
  console.log(`\nℹ️  ${conMenciones.length} pieza(s) NOMBRADAS en errores que NO son denegaciones`);
  console.log('   (guardas propias en ensayos). Quedan en el acta para mirarlas a ojo.');
}
if (conRastro.length === 0) {
  console.log(
    `\n✅ SIN EVIDENCIA DE USO en los tramos observados (${cubierto.desde} -> ${cubierto.hasta}).` +
    '\n   (Esto NO dice que nadie lo usara: dice que en ESTOS tramos no hay rastro.)',
  );
} else {
  console.log(`\n⚠️  ${conRastro.length} pieza(s) CON rastro:`);
  for (const h of conRastro) console.log(`   ${h.firma}: ruta ${h.intentos}, postgres ${h.intentos_postgres}`);
  console.log('   Ninguna de estas se demuele sin explicar quien llamo y por que.');
}
