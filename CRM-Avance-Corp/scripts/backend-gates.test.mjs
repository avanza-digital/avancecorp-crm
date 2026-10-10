/**
 * Contrato OFFLINE del control automático de backend: workflow `CRM RLS preflight` + package.
 * ─────────────────────────────────────────────────────────────────────────────
 * Comprueba, sobre el YAML y el package REALES del repositorio:
 *   · activación: ningún filtro de rutas puede dejar fuera una migración, una Edge
 *     Function, el arnés o la configuración del propio gate;
 *   · identidad: nombre del workflow, job, permisos y eventos no cambian por descuido.
 *
 * No llama a GitHub, no ejecuta las suites reales y no abre red. Un verde aquí
 * significa «el contrato del gate es el acordado», no «las suites pasaron».
 *
 * Correr: npm run test:backend-gates
 *         (node --test --test-reporter=tap scripts/backend-gates.test.mjs)
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isMap, isSeq, parseDocument } from "yaml";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ_CRM = resolve(AQUI, "..");
const RAIZ_REPO = resolve(RAIZ_CRM, "..");
const RUTA_WORKFLOW = ".github/workflows/crm-rls-preflight.yml";

const NOMBRE_WORKFLOW = "CRM RLS preflight";
const JOB = "preflight";
const EVENTOS = ["pull_request", "push", "workflow_dispatch"];
const RAMAS_PUSH = ["main", "tronco"];
const FILTROS_DE_RUTAS = ["paths", "paths-ignore"];
const PARSER_YAML = "2.9.1";

/** Los cuatro gates offline que ya existían. No se quitan ni se renombran. */
const GATES_EXISTENTES = ["check:scripts", "seed:preflight", "test:rls:preflight", "test:edge-preflight"];

/**
 * Suites sensibles que existían con pruebas pero nadie corría en CI, más este contrato.
 * Los comandos son los probados en Etapa 1 (ver ../CONTRATO-PASO-05.md); `--cached-only`
 * los hace OFFLINE: la descarga de imports es un paso aparte del workflow (online).
 */
const SCRIPTS_NUEVOS = {
  "test:backend-gates": "node --test --test-reporter=tap scripts/backend-gates.test.mjs",
  "test:backend-additional":
    "deno test --cached-only --node-modules-dir=auto --frozen supabase/functions/crm-usuarios/auth-attributes.test.ts supabase/functions/crm-importar-leads/telefonos.test.ts supabase/functions/crm-temperatura-lead/handler.test.ts supabase/functions/crm-usuarios/handler.test.ts",
  "test:contrato-pdf":
    "deno test --cached-only --config supabase/functions/crm-contrato-pdf-v2/deno.json --allow-read supabase/functions/crm-contrato-pdf-v2",
  "test:mutantes:aislamiento": "node --test --test-reporter=tap scripts/mutantes-puente-aislamiento.test.mjs",
};

/** Orden de los pasos `npm run …` del job: primero los existentes, luego los nuevos. */
const GATES_CI = [...GATES_EXISTENTES, ...Object.keys(SCRIPTS_NUEVOS)];

/**
 * Entradas Deno de los gates que YA EXISTÍAN, copiadas de sus scripts reales del package
 * (lista cerrada y verificada contra ellos; no hay parser universal de shell). `check:scripts`
 * llega a Deno a través de `npm run test:importar-leads-edge`; `test:edge-preflight` ejecuta
 * `deno check` + `deno test` y encadena `test:push-tasa`.
 */
const ENTRADAS_DENO_GATES_EXISTENTES = {
  "test:importar-leads-edge": [
    "supabase/functions/crm-importar-leads/autorizacion-contacto.test.ts",
    "supabase/functions/crm-importar-leads/destinos.test.ts",
    "supabase/functions/crm-importar-leads/resultado-importacion.test.ts",
    "supabase/functions/crm-importar-leads/catalogo.test.ts",
  ],
  "test:edge-preflight": [
    "../_supabase_functions/functions/crm-inversion-portal/index.ts",
    "../_supabase_functions/functions/crm-convertir-lead/index.ts",
    "../_supabase_functions/functions/crear-cliente/index.ts",
    "supabase/functions/crm-inversion-bienvenida/index.ts",
    "supabase/functions/crm-tipo-cambio/index.ts",
    "supabase/functions/crm-tipo-cambio/handler.ts",
    "supabase/functions/crm-tipo-cambio/handler.test.ts",
  ],
  "test:push-tasa": [
    "supabase/functions/crm-notificaciones-tasa/index.ts",
    "supabase/functions/crm-notificaciones-tasa/handler.test.ts",
    "supabase/functions/crm-notificaciones-tasa/transporte.test.ts",
  ],
};

/** Gates del job que llegan a Deno, directa o indirectamente por `npm run` (lista cerrada verificada). */
const GATES_QUE_USAN_DENO = ["check:scripts", "test:edge-preflight", "test:backend-additional", "test:contrato-pdf"];

/**
 * Preparación ONLINE de los imports Deno: UN paso del workflow, después de `npm ci` y antes
 * de TODOS los gates, porque el primer gate alcanzable (`check:scripts`) ya usa Deno. Cubre
 * las entradas de los gates existentes, las suites nuevas y, en su propio comando con su
 * `deno.json`, el PDF. Una línea por grupo de entradas; cada línea es un comando completo.
 */
const NOMBRE_PASO_PREPARACION = "Prepare Deno imports for every Deno gate";
const PREPARACION_LINEAS = [
  "deno install --entrypoint --node-modules-dir=auto --frozen " + ENTRADAS_DENO_GATES_EXISTENTES["test:importar-leads-edge"].join(" "),
  "deno install --entrypoint --node-modules-dir=auto --frozen " + ENTRADAS_DENO_GATES_EXISTENTES["test:edge-preflight"].join(" "),
  "deno install --entrypoint --node-modules-dir=auto --frozen " + ENTRADAS_DENO_GATES_EXISTENTES["test:push-tasa"].join(" "),
  "deno install --entrypoint --node-modules-dir=auto --frozen supabase/functions/crm-usuarios/auth-attributes.test.ts supabase/functions/crm-importar-leads/telefonos.test.ts supabase/functions/crm-temperatura-lead/handler.test.ts supabase/functions/crm-usuarios/handler.test.ts",
  "deno install --entrypoint --config supabase/functions/crm-contrato-pdf-v2/deno.json supabase/functions/crm-contrato-pdf-v2/handler.test.ts supabase/functions/crm-contrato-pdf-v2/renderer.test.ts supabase/functions/crm-contrato-pdf-v2/storage.test.ts",
];
const PREPARACION_DENO = PREPARACION_LINEAS.join("\n") + "\n";
/** Entradas `.ts` que la preparación descarga (tokens de cada línea). */
const ENTRADAS_PREPARADAS = PREPARACION_LINEAS.flatMap((l) => l.split(/\s+/).filter((t) => t.endsWith(".ts")));

/** Tokens `.ts` de un script del package: son sus entradas Deno (el package es una lista de comandos, no un shell libre). */
const entradasTs = (comando) => (comando ?? "").split(/\s+/).filter((t) => t.endsWith(".ts"));

/** ¿Un script llega a Deno, directamente o a través de otro `npm run`? Solo sigue los `npm run X` escritos tal cual. */
function alcanzaDeno(script, scripts, vistos = new Set()) {
  if (vistos.has(script)) return false;
  vistos.add(script);
  const comando = scripts[script] ?? "";
  if (/(^|\s)deno\s/.test(comando)) return true;
  return [...comando.matchAll(/npm run (\S+)/g)].some((m) => alcanzaDeno(m[1], scripts, vistos));
}

/**
 * Cambios de un solo archivo que el control NO puede dejar pasar. Son rutas reales del
 * repositorio (se comprueba que existen) para que el caso no sea hipotético.
 */
const CAMBIOS_SENSIBLES = [
  ["migración SQL", "CRM-Avance-Corp/supabase/migrations/20261002054402_crm_base_gestion_esquema.sql"],
  ["Edge Function del CRM (usuarios)", "CRM-Avance-Corp/supabase/functions/crm-usuarios/handler.ts"],
  ["Edge Function compartida", "_supabase_functions/functions/crm-convertir-lead/preflight.test.mjs"],
  ["scripts del arnés de mutantes", "CRM-Avance-Corp/scripts/mutantes-puente.mjs"],
  ["configuración del gate PDF", "CRM-Avance-Corp/supabase/functions/crm-contrato-pdf-v2/deno.json"],
  ["configuración del propio workflow", RUTA_WORKFLOW],
  ["package del backend", "CRM-Avance-Corp/package.json"],
  ["cambio solo de frontend (el job debe reportar igual)", "CRM-Avance-Corp/app/package.json"],
];

// ── Lectura estricta del YAML ────────────────────────────────────────────────

/**
 * Parsea el workflow con el parser real (`yaml`, YAML 1.2). Claves duplicadas, errores de
 * sintaxis o una estructura distinta de la esperada se rechazan con excepción: nunca se
 * aceptan en silencio. Devuelve el documento y su versión JS.
 */
function leerWorkflow(texto) {
  const doc = parseDocument(texto, { uniqueKeys: true, prettyErrors: true });
  if (doc.errors.length) {
    throw new Error("YAML inválido en " + RUTA_WORKFLOW + ":\n" + doc.errors.map((e) => e.message).join("\n"));
  }
  if (!isMap(doc.contents)) throw new Error("el workflow debe ser un mapa en su raíz");
  const on = doc.get("on");
  if (!isMap(on)) throw new Error("`on` debe ser un mapa de eventos, no " + describir(on));
  for (const evento of on.items) {
    const nombre = String(evento.key);
    if (!(evento.value === null || evento.value?.value === null || isMap(evento.value))) {
      throw new Error("el evento `" + nombre + "` debe ser nulo o un mapa, no " + describir(evento.value));
    }
  }
  const jobs = doc.get("jobs");
  if (!isMap(jobs)) throw new Error("`jobs` debe ser un mapa, no " + describir(jobs));
  for (const job of jobs.items) {
    if (!isMap(job.value)) throw new Error("el job `" + String(job.key) + "` debe ser un mapa");
    const steps = job.value.get("steps");
    if (!isSeq(steps)) throw new Error("el job `" + String(job.key) + "` debe tener una lista `steps`");
    for (const step of steps.items) {
      if (!isMap(step)) throw new Error("cada paso debe ser un mapa");
      const run = step.get("run");
      const uses = step.get("uses");
      if ((run === undefined) === (uses === undefined)) {
        throw new Error("cada paso debe tener exactamente uno de `run` o `uses`");
      }
      if (run !== undefined && typeof run !== "string") throw new Error("`run` debe ser texto");
    }
  }
  return { doc, js: doc.toJS() };
}

const describir = (nodo) => (nodo == null ? "nulo" : isSeq(nodo) ? "una lista" : isMap(nodo) ? "un mapa" : typeof nodo === "object" ? typeof nodo.value : typeof nodo);

/** Filtros de rutas declarados en un evento (vacío si el evento es nulo). */
const filtrosDeRutas = (evento) => (evento && typeof evento === "object" ? FILTROS_DE_RUTAS.filter((f) => f in evento) : []);

const textoWorkflow = () => readFileSync(join(RAIZ_REPO, RUTA_WORKFLOW), "utf8");
const leerJson = (ruta) => JSON.parse(readFileSync(join(RAIZ_CRM, ruta), "utf8"));

/** Pasos `run` del job, en orden. */
const pasosRun = (js) => js.jobs[JOB].steps.filter((s) => "run" in s);
/** Nombre del script npm que ejecuta un paso `npm run X`, o null. */
const scriptDelPaso = (paso) => (paso.run.match(/^npm run (\S+)\s*$/) || [])[1] ?? null;

// ── 1. Activación: el control corre para cualquier cambio en los eventos acordados ──

test("activación: los cambios sensibles existen en el repositorio (los casos no son hipotéticos)", () => {
  for (const [descripcion, ruta] of CAMBIOS_SENSIBLES) {
    assert.ok(existsSync(join(RAIZ_REPO, ruta)), `${descripcion}: no existe ${ruta}`);
  }
});

for (const evento of ["pull_request", "push"]) {
  test(`activación: ${evento} dispara el preflight para cualquier cambio, sin filtros de rutas`, () => {
    const { js } = leerWorkflow(textoWorkflow());
    const filtros = filtrosDeRutas(js.on[evento]);
    const omitidos = CAMBIOS_SENSIBLES.map(([d, r]) => `  · ${d} → ${r}`).join("\n");
    assert.deepEqual(
      filtros,
      [],
      `on.${evento} declara ${filtros.join(" y ")}: un cambio que no case con la lista no activa el control.\n` +
        `Cambios que deben activarlo siempre:\n${omitidos}`,
    );
  });
}

// ── Identidad: guardas de regresión (verdes desde el inicio, por diseño) ─────

test("identidad: nombre del workflow, eventos exactos y ramas de push", () => {
  const { js } = leerWorkflow(textoWorkflow());
  assert.equal(js.name, NOMBRE_WORKFLOW);
  assert.deepEqual(Object.keys(js.on).sort(), [...EVENTOS].sort(), "los eventos deben ser exactamente los acordados");
  assert.deepEqual(js.on.push?.branches, RAMAS_PUSH, "push debe cubrir exactamente main y tronco");
  assert.ok("workflow_dispatch" in js.on, "debe conservarse el disparo manual");
});

test("identidad: un solo job `preflight` con permisos `contents: read`", () => {
  const { js } = leerWorkflow(textoWorkflow());
  assert.deepEqual(Object.keys(js.jobs), [JOB], "el job que reporta el check debe seguir siendo `preflight`");
  assert.deepEqual(js.permissions, { contents: "read" }, "no se amplían permisos del token");
  assert.equal(js.jobs[JOB].permissions, undefined, "el job no redefine permisos");
});

// ── Shell declarada: el replay local y el job comparten semántica ────────────

/**
 * `shell: bash` en Actions equivale a `bash --noprofile --norc -eo pipefail {0}`; sin declararla,
 * la shell implícita depende del runner y no puede atribuírsele pipefail. Se fija en el job
 * (`defaults.run`) junto al directorio de trabajo, y ningún paso la redefine.
 */
const DEFAULTS_RUN = { shell: "bash", "working-directory": "CRM-Avance-Corp" };

test("shell: el job declara defaults.run.shell bash y working-directory CRM-Avance-Corp, sin excepciones por paso", () => {
  const { js } = leerWorkflow(textoWorkflow());
  const job = js.jobs[JOB];
  assert.deepEqual(job.defaults?.run, DEFAULTS_RUN, "defaults.run del job");
  assert.equal(job.shell, undefined);
  for (const paso of job.steps) {
    for (const clave of ["shell", "working-directory"]) {
      assert.equal(paso[clave], undefined, `el paso «${paso.name ?? "?"}» redefine ${clave}`);
    }
  }
  assert.equal(job["timeout-minutes"], 5, "los cinco minutos se conservan hasta medición contraria");
});

// ── 2. Cableado: las suites sensibles forman parte del control ───────────────

test("cableado: package declara los scripts nuevos con los comandos probados (offline)", () => {
  const { scripts } = leerJson("package.json");
  for (const [nombre, comando] of Object.entries(SCRIPTS_NUEVOS)) {
    assert.equal(scripts[nombre], comando, `script ${nombre}`);
  }
  for (const gate of GATES_EXISTENTES) assert.ok(scripts[gate], `el gate existente ${gate} desapareció`);
});

test("cableado: los archivos que ejecutan los scripts nuevos existen", () => {
  const rutas = Object.values(SCRIPTS_NUEVOS).flatMap((c) => c.split(/\s+/).filter((p) => /^(scripts|supabase)\//.test(p)));
  for (const ruta of rutas) assert.ok(existsSync(join(RAIZ_CRM, ruta)), `no existe ${ruta}`);
});

test("cableado: sin recursión — el contrato no se llama a sí mismo ni otro script lo encadena", () => {
  const { scripts } = leerJson("package.json");
  assert.doesNotMatch(scripts["test:backend-gates"] ?? "", /npm run/, "el contrato no debe lanzar otros scripts");
  for (const [nombre, comando] of Object.entries(scripts)) {
    if (nombre === "test:backend-gates") continue;
    assert.doesNotMatch(comando, /test:backend-gates|backend-gates\.test/, `${nombre} encadena el contrato: el CI ya lo ejecuta como paso propio`);
  }
});

test("cableado: parser YAML como dependencia directa fijada, también en el lockfile", () => {
  const pkg = leerJson("package.json");
  const lock = leerJson("package-lock.json");
  assert.equal(pkg.devDependencies?.yaml, PARSER_YAML, "devDependencies.yaml");
  assert.equal(lock.packages?.[""]?.devDependencies?.yaml, PARSER_YAML, "lock raíz");
  assert.equal(lock.packages?.["node_modules/yaml"]?.version, PARSER_YAML, "lock node_modules/yaml");
  assert.deepEqual(pkg.dependencies, { "@supabase/supabase-js": "2.110.2" }, "no cambian las dependencias de runtime");
});

/**
 * Deno lee `package.json` cuando corre con `--node-modules-dir=auto` (lo hacen los gates
 * existentes y las suites nuevas) y, con `--frozen`, exige que `deno.lock` registre cada
 * dependencia directa. Un parser añadido solo al package rompe esos gates por lockfile, no
 * por sus pruebas: los tres archivos deben moverse juntos.
 */
test("cableado: package.json, package-lock.json y deno.lock registran el mismo parser yaml (versión, integridad y dependencia del workspace)", () => {
  const pkg = leerJson("package.json");
  const lockNpm = leerJson("package-lock.json");
  const lockDeno = leerJson("deno.lock");
  const especificador = `npm:yaml@${PARSER_YAML}`;
  assert.equal(pkg.devDependencies?.yaml, PARSER_YAML, "package.json devDependencies.yaml");
  assert.equal(lockDeno.specifiers?.[especificador], PARSER_YAML, `deno.lock specifiers[${especificador}]`);
  const entradaDeno = lockDeno.npm?.[`yaml@${PARSER_YAML}`];
  assert.ok(entradaDeno, `deno.lock no registra npm yaml@${PARSER_YAML}`);
  assert.equal(entradaDeno.integrity, lockNpm.packages?.["node_modules/yaml"]?.integrity, "la integridad de yaml en deno.lock debe ser la del lock npm");
  const declaradas = Object.entries({ ...pkg.dependencies, ...pkg.devDependencies })
    .map(([nombre, version]) => `npm:${nombre}@${version}`)
    .sort();
  assert.deepEqual(
    [...(lockDeno.workspace?.packageJson?.dependencies ?? [])].sort(),
    declaradas,
    "deno.lock workspace.packageJson.dependencies debe reflejar exactamente las dependencias directas del package.json",
  );
});

test("cableado: el job ejecuta los cuatro gates existentes y las suites nuevas, cada uno en su paso", () => {
  const { js } = leerWorkflow(textoWorkflow());
  const ejecutados = pasosRun(js).map(scriptDelPaso).filter(Boolean);
  assert.deepEqual(ejecutados, GATES_CI, "pasos `npm run …` del job, en orden");
  const { scripts } = leerJson("package.json");
  for (const gate of GATES_CI) assert.ok(scripts[gate], `el CI llama a ${gate} pero package no lo define`);
});

// ── Preparación Deno: antes de TODOS los gates alcanzables que usan Deno ─────

test("preparación: los gates del job que llegan a Deno son exactamente la lista verificada (check:scripts es el primero)", () => {
  const { scripts } = leerJson("package.json");
  assert.deepEqual(GATES_CI.filter((g) => alcanzaDeno(g, scripts)), GATES_QUE_USAN_DENO);
  assert.equal(GATES_CI.find((g) => alcanzaDeno(g, scripts)), "check:scripts", "el primer gate del job ya usa Deno (vía test:importar-leads-edge)");
  assert.ok(alcanzaDeno("test:importar-leads-edge", scripts) && /npm run test:importar-leads-edge/.test(scripts["check:scripts"]));
  assert.ok(/npm run test:push-tasa/.test(scripts["test:edge-preflight"]), "test:edge-preflight encadena test:push-tasa");
});

test("preparación: la lista verificada de entradas Deno coincide con los scripts reales de los gates existentes", () => {
  const { scripts } = leerJson("package.json");
  for (const [script, entradas] of Object.entries(ENTRADAS_DENO_GATES_EXISTENTES)) {
    assert.ok(/(^|\s)deno\s/.test(scripts[script] ?? ""), `${script} ya no invoca deno: revisar la lista`);
    assert.deepEqual([...entradasTs(scripts[script])].sort(), [...entradas].sort(), `${script}: entradas .ts del script real vs lista verificada`);
    for (const entrada of entradas) assert.ok(existsSync(join(RAIZ_CRM, entrada)), `no existe ${entrada}`);
  }
});

test("preparación: un solo paso `deno install --entrypoint`, tras `npm ci` y antes del primer gate que usa Deno (y de todos los demás)", () => {
  const { js } = leerWorkflow(textoWorkflow());
  const pasos = pasosRun(js);
  const preparaciones = pasos.filter((p) => p.run === PREPARACION_DENO);
  assert.equal(preparaciones.length, 1, "falta el paso de preparación de imports Deno con el comando exacto (o está repetido)");
  assert.equal(preparaciones[0].name, NOMBRE_PASO_PREPARACION);
  const preparacion = pasos.indexOf(preparaciones[0]);
  const npmCi = pasos.findIndex((p) => p.run === "npm ci");
  assert.ok(npmCi !== -1 && npmCi < preparacion, "`npm ci` debe preceder a la preparación (instala el parser que leen los gates)");
  const { scripts } = leerJson("package.json");
  const primerGateDeno = pasos.findIndex((p) => scriptDelPaso(p) && alcanzaDeno(scriptDelPaso(p), scripts));
  assert.equal(scriptDelPaso(pasos[primerGateDeno]), "check:scripts");
  assert.ok(preparacion < primerGateDeno, `la preparación (paso ${preparacion + 1}) debe ir antes de ${scriptDelPaso(pasos[primerGateDeno])} (paso ${primerGateDeno + 1}), que ya usa Deno`);
  const primerGate = pasos.findIndex((p) => scriptDelPaso(p));
  assert.ok(preparacion < primerGate, "la preparación debe ir antes de todos los gates `npm run`");
});

test("preparación: cubre cada entrada Deno de los gates existentes, de las suites nuevas y del PDF con su deno.json", () => {
  for (const [script, entradas] of Object.entries(ENTRADAS_DENO_GATES_EXISTENTES)) {
    for (const entrada of entradas) assert.ok(ENTRADAS_PREPARADAS.includes(entrada), `${script}: la preparación no cubre ${entrada}`);
  }
  for (const [script, comando] of Object.entries(SCRIPTS_NUEVOS)) {
    if (!comando.startsWith("deno ")) continue;
    for (const entrada of entradasTs(comando)) assert.ok(ENTRADAS_PREPARADAS.includes(entrada), `${script}: la preparación no cubre ${entrada}`);
  }
  const pdf = PREPARACION_LINEAS.filter((l) => l.includes("--config supabase/functions/crm-contrato-pdf-v2/deno.json"));
  assert.equal(pdf.length, 1, "el PDF se prepara en su propio comando con su deno.json");
  assert.deepEqual(entradasTs(pdf[0]), ["handler.test.ts", "renderer.test.ts", "storage.test.ts"].map((f) => "supabase/functions/crm-contrato-pdf-v2/" + f));
  for (const linea of PREPARACION_LINEAS) {
    assert.match(linea, /^deno install --entrypoint /, "cada línea es un comando completo de preparación");
    if (!linea.includes("--config ")) assert.match(linea, / --node-modules-dir=auto --frozen /, "mismos flags de resolución que los gates (--frozen no se quita)");
  }
  for (const entrada of ENTRADAS_PREPARADAS) assert.ok(existsSync(join(RAIZ_CRM, entrada)), `no existe ${entrada}`);
});

// ── 3. Sin verde falso ───────────────────────────────────────────────────────
//
// 3a. El contrato completo, como función: todo lo anterior más la ausencia de desvíos.
//     Se aplica al YAML/package reales y a variantes defectuosas construidas a partir de
//     ellos; cada variante debe ser RECHAZADA con el motivo esperado.

/** Contrato completo del gate sobre un texto YAML y un package ya parseado. Lanza si falla. */
function contrato(textoYaml, pkg) {
  const { js } = leerWorkflow(textoYaml);
  for (const evento of ["pull_request", "push"]) {
    const filtros = filtrosDeRutas(js.on[evento]);
    if (filtros.length) throw new Error(`activación: on.${evento} declara ${filtros.join(" y ")}`);
  }
  if (js.name !== NOMBRE_WORKFLOW) throw new Error("identidad: nombre del workflow");
  if (JSON.stringify(Object.keys(js.on).sort()) !== JSON.stringify([...EVENTOS].sort())) throw new Error("identidad: eventos");
  if (JSON.stringify(js.on.push?.branches) !== JSON.stringify(RAMAS_PUSH)) throw new Error("identidad: ramas de push");
  if (JSON.stringify(Object.keys(js.jobs)) !== JSON.stringify([JOB])) throw new Error("identidad: job");
  if (JSON.stringify(js.permissions) !== JSON.stringify({ contents: "read" })) throw new Error("identidad: permisos");
  const run = js.jobs[JOB].defaults?.run ?? {};
  for (const [clave, valor] of Object.entries(DEFAULTS_RUN)) {
    if (run[clave] !== valor) throw new Error(`shell: defaults.run.${clave} debe ser ${JSON.stringify(valor)}, no ${JSON.stringify(run[clave])}`);
  }
  validarSinDesvios(js, pkg); // antes del cableado: un `|| true` se señala como desvío, no como paso mal escrito
  const ejecutados = pasosRun(js).map(scriptDelPaso).filter(Boolean);
  if (JSON.stringify(ejecutados) !== JSON.stringify(GATES_CI)) throw new Error("cableado: pasos npm run " + JSON.stringify(ejecutados));
  for (const gate of GATES_CI) if (!pkg.scripts?.[gate]) throw new Error("cableado: falta el script " + gate);
  for (const [nombre, comando] of Object.entries(SCRIPTS_NUEVOS)) {
    if (pkg.scripts[nombre] !== comando) throw new Error("cableado: comando de " + nombre);
  }
  const pasos = pasosRun(js);
  const preparacion = pasos.findIndex((p) => p.run === PREPARACION_DENO);
  if (preparacion === -1) throw new Error("cableado: preparación Deno");
  if (preparacion > pasos.findIndex((p) => scriptDelPaso(p))) throw new Error("preparación: debe preceder a todos los gates (el primero ya usa Deno)");
  return js;
}

/** Rechaza todo lo que pueda convertir un fallo en verde: `if`, continue-on-error, `|| …`, `;`, `exit 0`. */
function validarSinDesvios(js, pkg) {
  const job = js.jobs[JOB];
  for (const clave of ["if", "continue-on-error", "strategy"]) {
    if (clave in job) throw new Error(`desvío: el job declara ${clave}`);
  }
  job.steps.forEach((paso, i) => {
    const etiqueta = paso.name ?? `#${i + 1}`;
    for (const clave of ["if", "continue-on-error", "shell", "working-directory"]) {
      if (clave in paso) throw new Error(`desvío: el paso «${etiqueta}» declara ${clave}`);
    }
    if ("run" in paso) comprobarComando(`el paso «${etiqueta}»`, paso.run);
  });
  for (const gate of GATES_CI) comprobarComando(`el script ${gate}`, pkg.scripts[gate]);
}

/** Patrones que devuelven 0 aunque algo haya fallado. Ningún comando del gate los necesita. */
const PATRONES_DE_DESVIO = [
  [/\|\|/, "||"],
  [/;/, ";"],
  [/\bexit 0\b/, "exit 0"],
  [/\bset \+e\b/, "set +e"],
  [/(^|\s)true\s*$/m, "true como último comando"],
];
function comprobarComando(donde, comando) {
  for (const [patron, nombre] of PATRONES_DE_DESVIO) {
    if (patron.test(comando)) throw new Error(`desvío: ${donde} contiene ${nombre}: ${JSON.stringify(comando)}`);
  }
}

/** Variante del YAML real con una sustitución textual que DEBE aplicarse (si no, el caso no prueba nada). */
function variante(texto, de, a) {
  assert.ok(texto.includes(de), `la variante no aplica: el YAML real no contiene ${JSON.stringify(de)}`);
  return texto.replace(de, a);
}

const yamlReal = () => textoWorkflow();
const pkgReal = () => leerJson("package.json");

/** Bloques textuales del YAML real usados para construir variantes de orden (deben existir tal cual). */
const BLOQUE_PREPARACION = `      - name: ${NOMBRE_PASO_PREPARACION}\n        run: |\n${PREPARACION_LINEAS.map((l) => "          " + l).join("\n")}\n`;
const BLOQUE_CHECK_SCRIPTS = "      - name: Check script syntax\n        run: npm run check:scripts\n";

test("sin verde falso: el YAML y el package reales cumplen el contrato completo", () => {
  contrato(yamlReal(), pkgReal());
});

const VARIANTES_RECHAZADAS = [
  ["paths-ignore en pull_request", (y) => variante(y, "  pull_request:\n", "  pull_request:\n    paths-ignore:\n      - 'docs/**'\n"), /activación: on\.pull_request declara paths-ignore/],
  ["paths en push", (y) => variante(y, "    branches: [main, tronco]\n", "    branches: [main, tronco]\n    paths:\n      - 'CRM-Avance-Corp/**'\n"), /activación: on\.push declara paths/],
  ["job con if", (y) => variante(y, "    runs-on: ubuntu-latest\n", "    runs-on: ubuntu-latest\n    if: github.event_name != 'pull_request'\n"), /desvío: el job declara if/],
  ["job con continue-on-error", (y) => variante(y, "    runs-on: ubuntu-latest\n", "    runs-on: ubuntu-latest\n    continue-on-error: true\n"), /desvío: el job declara continue-on-error/],
  ["paso con if", (y) => variante(y, "        run: npm run test:contrato-pdf\n", "        if: github.event_name == 'push'\n        run: npm run test:contrato-pdf\n"), /desvío: el paso .* declara if/],
  ["paso con continue-on-error", (y) => variante(y, "        run: npm run test:rls:preflight\n", "        run: npm run test:rls:preflight\n        continue-on-error: true\n"), /desvío: el paso .* declara continue-on-error/],
  ["run con || true", (y) => variante(y, "run: npm run test:mutantes:aislamiento\n", "run: npm run test:mutantes:aislamiento || true\n"), /desvío: .*\|\|/],
  ["run encadenado con ;", (y) => variante(y, "run: npm run test:backend-additional\n", "run: npm run test:backend-additional; npm run test:contrato-pdf\n"), /desvío: .*;/],
  ["run con exit 0", (y) => variante(y, "run: npm run check:scripts\n", "run: |\n          npm run check:scripts\n          exit 0\n"), /desvío: .*exit 0/],
  ["job renombrado", (y) => variante(y, "\n  preflight:\n", "\n  preflight-v2:\n"), /identidad: job/],
  ["paso de suite eliminado", (y) => variante(y, "      - name: Validate contract PDF unit suite (offline)\n        run: npm run test:contrato-pdf\n", ""), /cableado: pasos npm run/],
  ["permisos ampliados", (y) => variante(y, "permissions:\n  contents: read\n", "permissions:\n  contents: write\n"), /identidad: permisos/],
  ["clave duplicada", (y) => variante(y, "permissions:\n", "permissions:\n  contents: read\npermissions:\n"), /YAML inválido/],
  ["YAML inválido", (y) => variante(y, "jobs:\n", "jobs: [\n"), /YAML inválido/],
  ["on como lista", (y) => variante(y, "on:\n  pull_request:\n  push:\n    branches: [main, tronco]\n  workflow_dispatch:\n", "on: [pull_request, push, workflow_dispatch]\n"), /`on` debe ser un mapa/],
  ["preparación Deno después del primer gate (check:scripts ya usa Deno)", (y) => variante(y, BLOQUE_PREPARACION + "\n" + BLOQUE_CHECK_SCRIPTS, BLOQUE_CHECK_SCRIPTS + "\n" + BLOQUE_PREPARACION), /preparación: debe preceder a todos los gates/],
  ["preparación Deno sin una entrada de un gate existente", (y) => variante(y, " supabase/functions/crm-tipo-cambio/handler.test.ts\n", "\n"), /cableado: preparación Deno/],
  ["shell implícita (sin defaults.run.shell)", (y) => variante(y, "        shell: bash\n", ""), /shell: defaults\.run\.shell debe ser "bash", no undefined/],
  ["shell distinta (sh)", (y) => variante(y, "        shell: bash\n", "        shell: sh\n"), /shell: defaults\.run\.shell debe ser "bash", no "sh"/],
  ["sin working-directory del job", (y) => variante(y, "        working-directory: CRM-Avance-Corp\n", ""), /shell: defaults\.run\.working-directory/],
  ["paso con shell propia", (y) => variante(y, "        run: npm run seed:preflight\n", "        shell: sh\n        run: npm run seed:preflight\n"), /desvío: el paso .* declara shell/],
  ["paso con working-directory propio", (y) => variante(y, "        run: npm run seed:preflight\n", "        working-directory: CRM-Avance-Corp/app\n        run: npm run seed:preflight\n"), /desvío: el paso .* declara working-directory/],
];

for (const [nombre, construir, motivo] of VARIANTES_RECHAZADAS) {
  test(`sin verde falso: variante «${nombre}» es rechazada`, () => {
    const texto = construir(yamlReal());
    assert.throws(() => contrato(texto, pkgReal()), motivo);
  });
}

test("sin verde falso: variantes del package son rechazadas (|| true, ;, script eliminado)", () => {
  const base = pkgReal();
  const con = (cambios) => ({ ...base, scripts: { ...base.scripts, ...cambios } });
  assert.throws(() => contrato(yamlReal(), con({ "test:contrato-pdf": SCRIPTS_NUEVOS["test:contrato-pdf"] + " || true" })), /desvío: el script test:contrato-pdf contiene \|\|/);
  assert.throws(() => contrato(yamlReal(), con({ "test:rls:preflight": "node supabase/scripts/test-rls.mjs --preflight; true" })), /desvío: el script test:rls:preflight/);
  const sinScript = con({});
  delete sinScript.scripts["test:mutantes:aislamiento"];
  assert.throws(() => contrato(yamlReal(), sinScript), /cableado: falta el script test:mutantes:aislamiento/);
});

// 3b. Propagación REAL del fallo con sustitutos. Los sustitutos solo demuestran que el
//     comando tal cual está escrito (paso del YAML, script del package) devuelve exit≠0
//     cuando lo que ejecuta falla; NO demuestran que la suite real pasa ni falla.

// `shell: bash` declarado en `defaults.run` del job (DEFAULTS_RUN) equivale en Actions a
// `bash --noprofile --norc -eo pipefail {0}`; el replay usa exactamente esa invocación.
const BASH = ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c"];
const ENTORNO = { ...process.env, NODE_TEST_CONTEXT: undefined, NO_COLOR: "1" };

function arbolTemporal(t) {
  const raiz = mkdtempSync(join(tmpdir(), "backend-gates-"));
  t.after(() => rmSync(raiz, { recursive: true, force: true }));
  return raiz;
}
const salidaDe = (codigo) => `node -e "process.exit(${codigo})"`;
const correr = (cmd, cwd) => spawnSync(BASH[0], [...BASH.slice(1), cmd], { cwd, env: ENTORNO, encoding: "utf8", timeout: 60_000 });

/** Ejecuta en orden los pasos `npm run …` del job real sobre un package sustituto; devuelve en qué paso se detuvo. */
function ejecutarPasos(raiz, scriptsSustitutos) {
  writeFileSync(join(raiz, "package.json"), JSON.stringify({ name: "sustituto", private: true, scripts: scriptsSustitutos }));
  const { js } = leerWorkflow(yamlReal());
  assert.equal(js.jobs[JOB].defaults?.run?.shell, "bash", "el replay con bash -eo pipefail solo vale si el job declara shell: bash");
  const pasos = pasosRun(js).filter((p) => scriptDelPaso(p));
  const ejecutados = [];
  for (const paso of pasos) {
    const r = correr(paso.run, raiz);
    ejecutados.push({ script: scriptDelPaso(paso), status: r.status, signal: r.signal });
    if (r.status !== 0) break;
  }
  return { pasos: pasos.length, ejecutados };
}

test("propagación: con todos los sustitutos verdes, los pasos npm del job corren en orden y terminan en 0", (t) => {
  const raiz = arbolTemporal(t);
  const verdes = Object.fromEntries(GATES_CI.map((g) => [g, salidaDe(0)]));
  const { pasos, ejecutados } = ejecutarPasos(raiz, verdes);
  assert.equal(pasos, GATES_CI.length);
  assert.deepEqual(ejecutados.map((e) => e.script), GATES_CI);
  assert.deepEqual(ejecutados.map((e) => e.status), GATES_CI.map(() => 0));
});

for (const roto of ["test:rls:preflight", "test:backend-additional", "test:mutantes:aislamiento"]) {
  test(`propagación: si el sustituto de ${roto} falla, ese paso devuelve exit≠0 y no corre ninguno posterior`, (t) => {
    const raiz = arbolTemporal(t);
    const sustitutos = Object.fromEntries(GATES_CI.map((g) => [g, salidaDe(g === roto ? 3 : 0)]));
    const { ejecutados } = ejecutarPasos(raiz, sustitutos);
    const ultimo = ejecutados.at(-1);
    assert.equal(ultimo.script, roto, "la secuencia debe detenerse exactamente en el paso roto");
    assert.notEqual(ultimo.status, 0, "el fallo del proceso hijo debe salir del paso");
    assert.equal(ejecutados.length, GATES_CI.indexOf(roto) + 1, "ningún paso posterior debe ejecutarse");
    assert.ok(ejecutados.slice(0, -1).every((e) => e.status === 0));
  });
}

/** Árbol sustituto para los comandos reales de los scripts nuevos: mismas rutas, contenido mínimo. */
function arbolDeScripts(raiz, { roto = null } = {}) {
  const nodo = (falla) => `import { test } from "node:test";\ntest("sustituto", () => { if (${falla}) throw new Error("falla a propósito"); });\n`;
  const deno = (falla) => `Deno.test("sustituto", () => { if (${falla}) throw new Error("falla a propósito"); });\n`;
  const archivos = {
    "scripts/backend-gates.test.mjs": nodo,
    "scripts/mutantes-puente-aislamiento.test.mjs": nodo,
    "supabase/functions/crm-usuarios/auth-attributes.test.ts": deno,
    "supabase/functions/crm-importar-leads/telefonos.test.ts": deno,
    "supabase/functions/crm-temperatura-lead/handler.test.ts": deno,
    "supabase/functions/crm-usuarios/handler.test.ts": deno,
    "supabase/functions/crm-contrato-pdf-v2/handler.test.ts": deno,
  };
  for (const [ruta, plantilla] of Object.entries(archivos)) {
    mkdirSync(dirname(join(raiz, ruta)), { recursive: true });
    writeFileSync(join(raiz, ruta), plantilla(ruta === roto));
  }
  writeFileSync(join(raiz, "supabase/functions/crm-contrato-pdf-v2/deno.json"), JSON.stringify({ lock: false }));
  writeFileSync(join(raiz, "package.json"), JSON.stringify({ name: "sustituto", private: true, type: "module" }));
}

const ARCHIVO_ROTO_POR_SCRIPT = {
  "test:backend-gates": "scripts/backend-gates.test.mjs",
  "test:backend-additional": "supabase/functions/crm-usuarios/handler.test.ts",
  "test:contrato-pdf": "supabase/functions/crm-contrato-pdf-v2/handler.test.ts",
  "test:mutantes:aislamiento": "scripts/mutantes-puente-aislamiento.test.mjs",
};

for (const [script, archivoRoto] of Object.entries(ARCHIVO_ROTO_POR_SCRIPT)) {
  test(`propagación: el comando real de ${script} devuelve 0 con sustitutos verdes y ≠0 si un sustituto falla`, (t) => {
    const comando = pkgReal().scripts[script];
    assert.equal(comando, SCRIPTS_NUEVOS[script]);
    const verde = arbolTemporal(t);
    arbolDeScripts(verde);
    const ok = correr(comando, verde);
    assert.equal(ok.status, 0, `con sustitutos verdes debe salir 0:\n${ok.stdout}\n${ok.stderr}`);
    const rojo = arbolTemporal(t);
    arbolDeScripts(rojo, { roto: archivoRoto });
    const fallo = correr(comando, rojo);
    assert.notEqual(fallo.status, 0, `con un sustituto roto debe salir ≠0:\n${fallo.stdout}\n${fallo.stderr}`);
    assert.equal(fallo.signal, null, "debe terminar por código, no por señal");
  });
}
