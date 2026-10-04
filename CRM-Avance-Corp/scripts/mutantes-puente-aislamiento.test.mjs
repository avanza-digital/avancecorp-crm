/**
 * Aislamiento del arnés de mutantes: el árbol de entrada NO se toca jamás.
 * ─────────────────────────────────────────────────────────────────────────────
 * El arnés original escribía cada mutante sobre los .gs del repositorio y los
 * "restauraba" después. Eso tiene tres agujeros: mientras corre, el repositorio
 * contiene un mutante; una edición ajena hecha entretanto se pierde al restaurar;
 * y una señal no prevista (SIGTERM, SIGKILL) deja el mutante puesto.
 *
 * Aquí se monta un ÁRBOL SINTÉTICO (copias de los .gs, suites sintéticas que los leen
 * por import.meta.url) y se lanza el arnés como proceso hijo real desde ese árbol.
 * Lo que se mira es el árbol de entrada —antes, durante y después— y que el temporal
 * del arnés desaparezca. Las dos últimas pruebas usan el cierre REAL (suites de
 * verdad) para demostrar que las suites hijas leen la copia y no el original.
 *
 * Correr: node --test scripts/mutantes-puente-aislamiento.test.mjs
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs, {
  appendFileSync, chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, rmSync, writeFileSync,
} from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { MUTANTES, ejecutarMutantes } from "./mutantes-puente.mjs";

const AQUI = dirname(fileURLToPath(import.meta.url));
const ARNES = join(AQUI, "mutantes-puente.mjs");
const PUENTE = "puente-drive-origen.gs";
const CONECTOR = "hoja-leads-apps-script.gs";
const FUENTES = [PUENTE, CONECTOR];
const SUITE_E2E = "puente-extremo-a-extremo.test.mjs";

const esperar = (ms) => new Promise((r) => setTimeout(r, ms));
const huella = (ruta) => createHash("sha256").update(readFileSync(ruta)).digest("hex");
const rutaCopia = (salida) => (salida.match(/^Copia de trabajo: (.+)$/m) || [])[1];

async function hastaQue(condicion, ms = 15_000) {
  const limite = Date.now() + ms;
  while (!condicion()) {
    if (Date.now() > limite) throw new Error("se agotó la espera");
    await esperar(10);
  }
}

/**
 * Suite sintética: lee los dos .gs por import.meta.url, como las suites reales.
 *  · huellas: SHA-256 que debe tener cada archivo leído (cualquier mutante lo cambia).
 *  · esperaMs/marcador: se anuncia al empezar y al acabar, para poder matar a mitad.
 *  · mutado: {archivo, de}; MUTADO es true cuando ese texto ya no está (mutante puesto).
 *  · matarSiMutado: con el mutante puesto, tumba al runner (fallo de ejecución, no de prueba).
 *  · cuerpoSiMutado: código que corre dentro de la prueba solo con el mutante puesto.
 *  · extra: código de nivel superior tras la prueba (puede registrar más pruebas según MUTADO).
 *  · cabecera: código que va antes de todo (para forzar un módulo ausente).
 */
const suiteSintetica = ({
  huellas = {}, esperaMs = 0, marcador = "", mutado = null, matarSiMutado = false,
  cuerpoSiMutado = "", cuerpo = "", extra = "", cabecera = "",
} = {}) => `
${cabecera}
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
const aqui = dirname(fileURLToPath(import.meta.url));
const textos = {
  ${JSON.stringify(PUENTE)}: readFileSync(join(aqui, ${JSON.stringify(PUENTE)}), "utf8"),
  ${JSON.stringify(CONECTOR)}: readFileSync(join(aqui, ${JSON.stringify(CONECTOR)}), "utf8"),
};
const VIGILADO = ${JSON.stringify(mutado)};
const MUTADO = Boolean(VIGILADO) && !textos[VIGILADO.archivo].includes(VIGILADO.de);
if (MUTADO && ${JSON.stringify(matarSiMutado)}) process.kill(process.ppid, "SIGKILL");
const marcador = ${JSON.stringify(marcador)};
test("suite sintética", async () => {
  if (marcador) writeFileSync(join(marcador, "inicio-" + process.pid), "");
  if (MUTADO) { ${cuerpoSiMutado} }
  if (${esperaMs}) await new Promise((r) => setTimeout(r, ${esperaMs}));
  if (marcador) writeFileSync(join(marcador, "fin-" + process.pid), "");
  for (const [archivo, huella] of Object.entries(${JSON.stringify(huellas)})) {
    assert.equal(createHash("sha256").update(textos[archivo]).digest("hex"), huella, archivo + " está mutado");
  }
  ${cuerpo}
});
${extra}
`;
/** Lo justo para que la suite sintética sepa si un mutante está puesto. */
const vigilado = (m) => ({ archivo: m.archivo, de: m.de });

/**
 * Monta un árbol de entrada propio: raíz con package.json (los scripts npm que usaba
 * el arnés viejo) y scripts/ con copias de los .gs, el simulador, las dos suites con
 * el contenido sintético indicado y el propio arnés. Se borra al acabar la prueba `t`,
 * pase o falle (finalizador), para no dejar árboles huérfanos en el temporal.
 */
function montarArbol(t, { intacto = false, ...opciones } = {}) {
  const raiz = mkdtempSync(join(tmpdir(), "arbol-mutantes-"));
  const scripts = join(raiz, "scripts");
  const finalizadores = [];
  t.after(async () => {
    try {
      for (const finalizar of finalizadores.reverse()) await finalizar();
    } finally {
      if (existsSync(scripts)) chmodSync(scripts, 0o755);
      rmSync(raiz, { recursive: true, force: true });
    }
  });
  mkdirSync(scripts);
  for (const f of [...FUENTES, "apps-script-simulado.mjs"]) copyFileSync(join(AQUI, f), join(scripts, f));
  // `intacto`: la suite sintética exige que cada .gs tenga la huella del original, así
  // que CUALQUIER mutante aplicado en la copia la pone roja (y solo si se lee la copia).
  const huellas = intacto ? Object.fromEntries(FUENTES.map((f) => [f, huella(join(scripts, f))])) : {};
  const suite = suiteSintetica({ marcador: raiz, huellas, ...opciones });
  writeFileSync(join(scripts, "puente-drive-origen.test.mjs"), suite);
  writeFileSync(join(scripts, SUITE_E2E), suite);
  copyFileSync(ARNES, join(scripts, "mutantes-puente.mjs"));
  writeFileSync(join(raiz, "package.json"), JSON.stringify({
    type: "module",
    scripts: {
      "test:puente": "node --test scripts/puente-drive-origen.test.mjs",
      "test:puente:e2e": `node --test scripts/${SUITE_E2E}`,
    },
  }));
  const leer = () => Object.fromEntries(FUENTES.map((f) => [f, readFileSync(join(scripts, f), "utf8")]));
  const soloLectura = () => { for (const f of FUENTES) chmodSync(join(scripts, f), 0o444); chmodSync(scripts, 0o555); };
  const marcadores = (prefijo) => readdirSeguro(raiz).filter((n) => n.startsWith(prefijo));
  return { raiz, scripts, leer, soloLectura, marcadores, alFinalizar: (f) => finalizadores.push(f) };
}
const readdirSeguro = (d) => { try { return readdirSync(d); } catch { return []; } };
const escapar = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Lanza el arnés como CLI desde el árbol. Devuelve el proceso y una promesa de fin. */
function lanzarArnes(arbol) {
  const proceso = spawn(process.execPath, [join(arbol.scripts, "mutantes-puente.mjs")], {
    cwd: arbol.raiz,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let salida = "";
  proceso.stdout.on("data", (d) => { salida += d; });
  proceso.stderr.on("data", (d) => { salida += d; });
  const fin = new Promise((resolve) => {
    const tope = setTimeout(() => proceso.kill("SIGKILL"), 150_000);
    proceso.on("close", (codigo, senal) => { clearTimeout(tope); resolve({ codigo, senal, salida }); });
  });
  arbol.alFinalizar(async () => {
    if (proceso.exitCode === null && proceso.signalCode === null) proceso.kill("SIGTERM");
    await fin;
    const copia = rutaCopia(salida);
    if (copia && copia.startsWith(join(tmpdir(), "mutantes-puente-"))) rmSync(copia, { recursive: true, force: true });
  });
  return { proceso, fin, salida: () => salida };
}

/** Lo que toda corrida tiene que cumplir, acabe como acabe: fuentes intactas y temporal borrado. */
function comprobarIntacto(arbol, original, salida) {
  assert.deepEqual(arbol.leer(), original, "el árbol de entrada cambió");
  const copia = rutaCopia(salida);
  assert.ok(copia && copia.startsWith(tmpdir()), "el arnés no anunció su copia de trabajo bajo el temporal");
  assert.equal(existsSync(copia), false, "el temporal del arnés no se borró: " + copia);
  return copia;
}

// ── 1. Edición ajena a mitad de corrida: se conserva, y el árbol nunca cambia ──

test("el árbol de entrada no cambia mientras corre el arnés, y una edición ajena sobrevive", async (t) => {
  const arbol = montarArbol(t);
  const original = arbol.leer();
  const EDICION = "\n// edición ajena hecha mientras corría el arnés\n";
  let esperado = { ...original };
  const violaciones = [];
  let editado = false;

  const { fin } = lanzarArnes(arbol);
  const inicio = Date.now();
  const muestreo = setInterval(() => {
    const ahora = arbol.leer();
    for (const f of FUENTES) {
      if (ahora[f] !== esperado[f] && violaciones.length < 5) {
        violaciones.push(`${f} cambió a los ${Date.now() - inicio} ms de empezar`);
      }
    }
    // La carrera: en cuanto se ve el árbol tocado (o pasados 400 ms), alguien edita
    // la fuente. El arnés no es dueño del árbol: esa edición tiene que quedarse.
    if (!editado && (violaciones.length || Date.now() - inicio > 400)) {
      editado = true;
      appendFileSync(join(arbol.scripts, PUENTE), EDICION);
      esperado = { ...esperado, [PUENTE]: esperado[PUENTE] + EDICION };
    }
  }, 10);
  arbol.alFinalizar(() => clearInterval(muestreo));

  const r = await fin;
  clearInterval(muestreo);
  const final = arbol.leer();

  assert.match(r.salida, /\d+\/\d+ mutantes muertos/, "el arnés no llegó al final");
  assert.ok(editado, "la edición ajena nunca llegó a hacerse");
  assert.deepEqual(violaciones, [], "el árbol de entrada cambió durante la corrida");
  assert.equal(final[PUENTE], original[PUENTE] + EDICION, "la edición ajena se perdió: el arnés reescribió la fuente");
  assert.equal(final[CONECTOR], original[CONECTOR]);
  assert.equal(existsSync(rutaCopia(r.salida)), false, "el temporal no se borró");
});

// ── 2. Camino feliz con la fuente de SOLO LECTURA: todos mueren leyendo la copia ──

test("con la fuente de solo lectura, los 46 mutantes se aplican en la copia y mueren", async (t) => {
  const arbol = montarArbol(t, { intacto: true });
  arbol.soloLectura();
  const original = arbol.leer();

  const r = await lanzarArnes(arbol).fin;

  assert.equal(r.codigo, 0, r.salida);
  assert.match(r.salida, new RegExp(`Línea base: 2 pruebas verdes`));
  assert.match(r.salida, new RegExp(`^${MUTANTES.length}/${MUTANTES.length} mutantes muertos\\.$`, "m"));
  assert.doesNotMatch(r.salida, /SOBREVIVE|NO APLICA|INVÁLIDA/);
  assert.equal((r.salida.match(/^✔ muere:/gm) || []).length, MUTANTES.length);
  comprobarIntacto(arbol, original, r.salida);
});

// ── 3. Sin línea base verde no se mide nada ──────────────────────────────────

test("línea base ROJA por aserción: aborta con código 2 sin tocar ningún mutante", async (t) => {
  const arbol = montarArbol(t, { cuerpo: 'assert.fail("roja a propósito");' });
  const original = arbol.leer();

  const r = await lanzarArnes(arbol).fin;

  assert.equal(r.codigo, 2);
  assert.match(r.salida, /LÍNEA BASE NO VERDE — 2 prueba\(s\) ROJA\(S\) de 2/);
  assert.match(r.salida, /· suite sintética/);
  assert.doesNotMatch(r.salida, /muere|SOBREVIVE|mutantes muertos/);
  comprobarIntacto(arbol, original, r.salida);
});

test("línea base con fallo de EJECUCIÓN (módulo ausente): se dice que es infra, no pruebas rojas", async (t) => {
  const arbol = montarArbol(t, { cabecera: 'import "./modulo-que-no-existe.mjs";' });
  const original = arbol.leer();

  const r = await lanzarArnes(arbol).fin;

  assert.equal(r.codigo, 2);
  assert.match(r.salida, /LÍNEA BASE NO VERDE — fallo de ejecución: falta un módulo/);
  assert.doesNotMatch(r.salida, /ROJA\(S\)|muere|SOBREVIVE/);
  comprobarIntacto(arbol, original, r.salida);
});

// ── 4. Un fallo de ejecución durante un mutante NO es un mutante muerto ──────

test("si el runner muere por señal con un mutante puesto, se reporta EJECUCIÓN INVÁLIDA y no «muere»", async (t) => {
  const primero = MUTANTES[0];
  const arbol = montarArbol(t, { intacto: true, mutado: vigilado(primero), matarSiMutado: true });
  const original = arbol.leer();

  const r = await lanzarArnes(arbol).fin;

  assert.equal(r.codigo, 2);
  assert.match(r.salida, new RegExp(`EJECUCIÓN INVÁLIDA \\(no cuenta como muerto\\): ${escapar(primero.nombre)} — node --test terminó por señal SIGKILL`));
  assert.doesNotMatch(r.salida, new RegExp(`muere:\\s+${escapar(primero.nombre)}`));
  assert.match(r.salida, new RegExp(`^${MUTANTES.length - 1}/${MUTANTES.length} mutantes muertos\\.$`, "m"));
  assert.match(r.salida, /1 ejecución\(es\) inválida\(s\)/);
  comprobarIntacto(arbol, original, r.salida);
});

test("cancelación por Promise pendiente con un mutante: infra, nunca una defensa probada", async (t) => {
  const mutante = MUTANTES[0];
  const arbol = montarArbol(t, {
    mutado: vigilado(mutante),
    // El timeout de la prueba produce cancelled, sin ninguna aserción fallida.
    // No depende de que esta versión de node vacíe los recursos del runner.
    extra: 'test("promesa pendiente", { timeout: 50 }, () => MUTADO ? new Promise(() => {}) : undefined);',
  });
  const original = arbol.leer();
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });

  assert.equal(r.base.tipo, "verde");
  assert.equal(r.base.pruebas, 2);
  assert.equal(r.codigo, 2, "una cancelación sin aserción fallida no mata el mutante");
  assert.equal(r.resultados[0].veredicto, "ejecución inválida");
  const v = r.resultados[0].verificacion;
  assert.equal(v.tipo, "infra");
  assert.equal(v.pruebas, r.base.pruebas);
  assert.equal(v.fallos, 0);
  assert.equal(v.canceladas, 1);
  assert.equal(v.omitidas, 0);
  assert.equal(v.pendientes, 0);
  assert.equal(v.aprobadas, 1);
  assert.match(v.motivo, /cancelada/);
  assert.deepEqual(arbol.leer(), original);
});

test("descendiente con pipe heredado: muere el líder y el grupo no escribe después del plazo", async (t) => {
  const mutante = MUTANTES[0];
  const arbol = montarArbol(t, {
    mutado: vigilado(mutante),
    cabecera: 'import { spawn } from "node:child_process"; import { existsSync } from "node:fs";',
    cuerpoSiMutado: `
      const grupo = process.ppid;
      // Hereda el pipe de la suite y sigue perteneciendo al grupo del runner.
      const codigo = 'const fs = require("node:fs"); fs.writeFileSync(process.argv[1], String(process.pid)); setTimeout(() => fs.writeFileSync(process.argv[2], "escapó"), 1600);';
      const descendiente = spawn(process.execPath, ["-e", codigo, join(marcador, "descendiente-activo"), join(marcador, "fin-descendiente")], { stdio: ["ignore", "inherit", "ignore"] });
      descendiente.unref();
      while (!existsSync(join(marcador, "descendiente-activo"))) await new Promise((r) => setTimeout(r, 10));
      writeFileSync(join(marcador, "grupo"), String(grupo));
      process.kill(grupo, "SIGKILL");
      await new Promise(() => {});
    `,
  });
  arbol.alFinalizar(() => {
    const archivo = join(arbol.raiz, "grupo");
    if (existsSync(archivo)) {
      const grupo = Number(readFileSync(archivo, "utf8"));
      if (Number.isInteger(grupo) && grupo > 1) {
        try { process.kill(-grupo, "SIGKILL"); } catch { /* ya terminó */ }
      }
    }
  });
  const original = arbol.leer();
  const inicio = Date.now();
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 600 });
  const duracion = Date.now() - inicio;
  assert.equal(r.base.tipo, "verde");
  assert.ok(existsSync(join(arbol.raiz, "grupo")), "el fixture debe haber matado al runner");
  assert.ok(existsSync(join(arbol.raiz, "descendiente-activo")), "el descendiente debe haber arrancado");
  await esperar(1800);
  assert.deepEqual(arbol.marcadores("fin-descendiente"), [], "el descendiente sobrevivió al líder y escribió su marcador");
  assert.ok(duracion < 1200, `el arnés esperó ${duracion} ms al pipe del descendiente`);
  assert.equal(r.codigo, 2);
  assert.equal(r.resultados[0].veredicto, "ejecución inválida");
  assert.match(r.resultados[0].verificacion.motivo, /señal SIGKILL/);
  assert.deepEqual(arbol.leer(), original);
});

test("tiempo agotado con un mutante: infra, hijo detenido y copia borrada", async (t) => {
  const mutante = MUTANTES[0];
  const arbol = montarArbol(t, {
    mutado: vigilado(mutante),
    cuerpoSiMutado: `
      writeFileSync(join(marcador, "mutante-iniciado"), "");
      await new Promise((r) => setTimeout(r, 1500));
      writeFileSync(join(marcador, "fin-tardio"), "escapó");
    `,
    extra: 'writeFileSync(join(marcador, "copia"), process.cwd());',
  });
  const original = arbol.leer();
  const inicio = Date.now();
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 400 });
  const duracion = Date.now() - inicio;
  assert.equal(r.base.tipo, "verde");
  assert.ok(existsSync(join(arbol.raiz, "mutante-iniciado")), "el plazo debe agotarse dentro de la prueba");
  assert.equal(r.codigo, 2);
  assert.equal(r.resultados[0].veredicto, "ejecución inválida");
  assert.equal(r.resultados[0].verificacion.tipo, "infra");
  assert.match(r.resultados[0].verificacion.motivo, /superó los 400 ms/);
  assert.ok(duracion < 1200, `el plazo no limitó la ejecución: ${duracion} ms`);
  await esperar(1700);
  assert.deepEqual(arbol.marcadores("fin-tardio"), []);
  assert.equal(existsSync(readFileSync(join(arbol.raiz, "copia"), "utf8")), false);
  assert.deepEqual(arbol.leer(), original);
});

test("preparación: base y mutantes usan la misma fotografía aunque editen antes de copiar", async (t) => {
  const mutante = MUTANTES[0];
  const edicion = "\n// edición externa justo antes de copiar\n";
  const arbol = montarArbol(t, {
    cuerpo: `assert.ok(textos[${JSON.stringify(mutante.archivo)}].includes(${JSON.stringify(edicion)}), "se perdió la edición que vio la base");`,
  });
  const original = arbol.leer();
  const fuente = join(arbol.scripts, mutante.archivo);
  const copiar = fs.copyFileSync;
  let editado = false;
  let r;
  fs.copyFileSync = (origen, ...args) => {
    if (origen === fuente && !editado) {
      appendFileSync(fuente, edicion);
      editado = true;
    }
    return copiar(origen, ...args);
  };
  syncBuiltinESMExports();
  try {
    r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
  } finally {
    fs.copyFileSync = copiar;
    syncBuiltinESMExports();
  }
  assert.ok(editado, "la carrera de preparación debe haberse provocado");
  assert.equal(r.base.tipo, "verde", "la base debe ver la edición copiada");
  assert.deepEqual(arbol.leer(), { ...original, [mutante.archivo]: original[mutante.archivo] + edicion });
  assert.equal(r.codigo, 1, "perder una edición ajena no debe acreditar la muerte del mutante");
  assert.equal(r.resultados[0].veredicto, "sobrevive");
  assert.equal(r.resultados[0].verificacion.tipo, "verde");
});

test("preparación: rechaza archivo escapado sin escribir la fuente del fixture", async (t) => {
  const arbol = montarArbol(t, { intacto: true });
  const original = arbol.leer();
  const fuente = join(arbol.scripts, PUENTE);
  const desdeCopia = join(tmpdir(), "mutantes-puente-sonda", "scripts");
  const archivo = relative(desdeCopia, fuente);
  assert.equal(join(desdeCopia, archivo), fuente);
  assert.ok(existsSync(fuente), "el ataque debe apuntar a un archivo real del fixture");
  const escribir = fs.writeFileSync;
  const escrituras = [];
  let r;
  try {
    fs.writeFileSync = (ruta, contenido, ...args) => {
      if (ruta === fuente) escrituras.push(contenido === original[PUENTE] ? "restauración" : "mutación");
      return escribir(ruta, contenido, ...args);
    };
    syncBuiltinESMExports();
    r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [{ ...MUTANTES[0], archivo }], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
  } finally {
    fs.writeFileSync = escribir;
    syncBuiltinESMExports();
  }
  assert.deepEqual(escrituras, [], "ni mutar ni restaurar puede escribir en la fuente de entrada");
  assert.equal(r.codigo, 2);
  assert.equal(r.base, undefined, "debe rechazar antes de correr la base");
  assert.deepEqual(r.resultados, []);
  assert.deepEqual(arbol.marcadores("inicio-"), []);
  assert.deepEqual(arbol.leer(), original);
});

/** Archivo sintético fuera de scripts/: solo crea un marcador dentro de su fixture. */
function montarSuiteExterna(arbol) {
  const archivo = join(arbol.raiz, "externa.test.mjs");
  const marcador = join(arbol.raiz, "suite-externa-ejecutada");
  writeFileSync(archivo, `
    import { test } from "node:test";
    import { writeFileSync } from "node:fs";
    test("suite externa sintética", () => writeFileSync(${JSON.stringify(marcador)}, "ejecutada"));
  `);
  const desdeCopia = join(tmpdir(), "mutantes-puente-sonda", "scripts");
  const suite = relative(desdeCopia, archivo);
  assert.equal(join(desdeCopia, suite), archivo);
  assert.ok(existsSync(archivo));
  return { suite, marcador };
}

test("preparación: rechaza suite escapada antes de ejecutar el archivo del fixture", async (t) => {
  const arbol = montarArbol(t);
  const original = arbol.leer();
  const { suite, marcador } = montarSuiteExterna(arbol);
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [MUTANTES[0]], suites: [suite], tiempoMaximoMs: 2000 });
  assert.equal(existsSync(marcador), false, "se ejecutó una suite fuera del cierre copiado");
  assert.equal(r.codigo, 2);
  assert.equal(r.base, undefined);
  assert.deepEqual(r.resultados, []);
  assert.deepEqual(arbol.leer(), original);
});

test("preparación: cambios del caller en descriptores durante la base no cambian lo medido", async (t) => {
  const arbol = montarArbol(t, { intacto: true, esperaMs: 250 });
  const original = arbol.leer();
  const descriptor = { ...MUTANTES[0] };
  const mutantes = [descriptor];
  const fin = ejecutarMutantes({ raiz: arbol.scripts, mutantes, suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
  arbol.alFinalizar(() => fin);
  await hastaQue(() => arbol.marcadores("inicio-").length > 0);
  assert.deepEqual(arbol.marcadores("fin-"), [], "la base debe seguir esperando");
  descriptor.nombre = "descriptor cambiado por el caller";
  descriptor.a = descriptor.de;
  mutantes.push({ ...descriptor });
  const r = await fin;
  assert.equal(r.codigo, 0, "la ejecución debe usar los valores capturados antes de la base");
  assert.equal(r.resultados.length, 1);
  assert.equal(r.resultados[0].nombre, MUTANTES[0].nombre);
  assert.equal(r.resultados[0].veredicto, "muere");
  assert.equal(mutantes.length, 2, "el arnés no debe congelar ni modificar los datos del caller");
  assert.equal(descriptor.a, descriptor.de);
  assert.deepEqual(arbol.leer(), original);
});

test("preparación: cambiar suites durante la base no permite ejecutar fuera del cierre", async (t) => {
  const arbol = montarArbol(t, { intacto: true, esperaMs: 250 });
  const original = arbol.leer();
  const { suite, marcador } = montarSuiteExterna(arbol);
  const suites = [SUITE_E2E];
  const fin = ejecutarMutantes({ raiz: arbol.scripts, mutantes: [MUTANTES[0]], suites, tiempoMaximoMs: 2000 });
  arbol.alFinalizar(() => fin);
  await hastaQue(() => arbol.marcadores("inicio-").length > 0);
  assert.deepEqual(arbol.marcadores("fin-"), [], "la base debe seguir esperando");
  suites[0] = suite;
  const r = await fin;
  assert.equal(existsSync(marcador), false, "el cambio posterior del caller escapó de la validación");
  assert.equal(r.codigo, 0);
  assert.equal(r.resultados[0].veredicto, "muere");
  assert.deepEqual(suites, [suite], "el arnés no debe alterar la lista del caller");
  assert.deepEqual(arbol.leer(), original);
});

test("preparación: opciones mal formadas son infraestructura sin publicar sus valores", async (t) => {
  const arbol = montarArbol(t);
  const original = arbol.leer();
  const valido = { raiz: arbol.scripts, mutantes: [MUTANTES[0]], suites: [SUITE_E2E], tiempoMaximoMs: 2000 };
  const detalle = "DETALLE_SINTETICO_NO_PUBLICABLE";
  const casos = [
    ["opciones null", null],
    ["opciones array", Object.assign([], valido)],
    ["mutantes null", { ...valido, mutantes: null }],
    ["descriptor null", { ...valido, mutantes: [null] }],
    ["texto no primitivo", { ...valido, mutantes: [{ ...MUTANTES[0], de: {} }] }],
    ["reemplazo ejecutable", { ...valido, mutantes: [{ ...MUTANTES[0], a: () => detalle }] }],
    ["texto vacío", { ...valido, mutantes: [{ ...MUTANTES[0], de: "" }] }],
    ["archivo no literal", { ...valido, mutantes: [{ ...MUTANTES[0], archivo: "./" + PUENTE }] }],
    ["archivo absoluto", { ...valido, mutantes: [{ ...MUTANTES[0], archivo: join(arbol.scripts, PUENTE) }] }],
    ["suites no array", { ...valido, suites: SUITE_E2E }],
    ["suites vacías", { ...valido, suites: [] }],
    ["suite no literal", { ...valido, suites: ["./" + SUITE_E2E] }],
    ["raíz no primitiva", { ...valido, raiz: {} }],
    ...[0, -1, NaN, Infinity, 2 ** 31, "2000"].map((tiempoMaximoMs, i) => [`plazo inválido ${i}`, { ...valido, tiempoMaximoMs }]),
    ["getter de opciones", { ...valido, get suites() { throw new Error(detalle); } }],
    ["getter de descriptor", { ...valido, mutantes: [{ ...MUTANTES[0], get archivo() { throw new Error(detalle); } }] }],
  ];
  const informar = console.error;
  const diagnosticos = [];
  try {
    console.error = (...partes) => diagnosticos.push(partes.join(" "));
    for (const [nombre, opciones] of casos) {
      let r;
      let rechazo = false;
      try { r = await ejecutarMutantes(opciones); } catch { rechazo = true; }
      assert.equal(rechazo, false, `${nombre}: debe devolver código 2, no rechazar la promesa`);
      assert.equal(r.codigo, 2, nombre);
      assert.equal(r.base, undefined, `${nombre}: no debe lanzar la base`);
      assert.deepEqual(r.resultados, [], nombre);
      assert.deepEqual(arbol.marcadores("inicio-"), [], nombre);
    }
  } finally {
    console.error = informar;
  }
  assert.ok(diagnosticos.length >= casos.length);
  assert.ok(diagnosticos.every((d) => !d.includes(detalle) && !d.includes(arbol.raiz)), "los diagnósticos deben ser genéricos");
  assert.deepEqual(arbol.leer(), original);
});

test("suite verde incompleta: un test omitido al mutar invalida la medición", async (t) => {
  const mutante = MUTANTES[0];
  const arbol = montarArbol(t, {
    mutado: vigilado(mutante),
    extra: 'if (!MUTADO) test("segunda defensa", () => {});',
  });
  const original = arbol.leer();
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });

  assert.equal(r.base.tipo, "verde");
  assert.equal(r.base.pruebas, 2);
  assert.equal(r.codigo, 2, "una suite incompleta no demuestra supervivencia");
  assert.equal(r.resultados[0].veredicto, "ejecución inválida");
  assert.deepEqual(r.resultados[0].verificacion, {
    tipo: "verde", pruebas: 1, suites: 0, aprobadas: 1, fallos: 0,
    canceladas: 0, omitidas: 0, pendientes: 0, codigo: 0, senal: null,
    archivosSinPruebas: [],
  }, "se debe conservar la verificación completa, incluso si la medición no vale");
  assert.deepEqual(arbol.leer(), original);
});

for (const [opcion, contador] of [["skip", "omitidas"], ["todo", "pendientes"]]) {
  for (const enBase of [true, false]) {
    test(`pruebas ${contador} en ${enBase ? "base" : "mutante"}: ejecución inválida aun con el mismo total`, async (t) => {
      const mutante = MUTANTES[0];
      const arbol = montarArbol(t, {
        mutado: vigilado(mutante),
        extra: `test("defensa no ejecutada", { ${opcion}: ${enBase ? "true" : "MUTADO"} }, () => {});`,
      });
      const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
      assert.equal(r.codigo, 2);
      const v = enBase ? r.base : r.resultados[0].verificacion;
      assert.equal(v.tipo, "infra");
      assert.equal(v.pruebas, 2);
      assert.equal(v.aprobadas, 1);
      assert.equal(v.fallos, 0);
      assert.equal(v[contador], 1);
      if (enBase) assert.deepEqual(r.resultados, []);
      else {
        assert.equal(r.base.tipo, "verde");
        assert.equal(r.base.pruebas, v.pruebas);
        assert.equal(r.resultados[0].veredicto, "ejecución inválida");
      }
    });
  }
}

test("cancelación en base: aborta antes de medir mutantes", async (t) => {
  const arbol = montarArbol(t, {
    extra: 'test("promesa pendiente", { timeout: 50 }, () => new Promise(() => {}));',
  });
  const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [MUTANTES[0]], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
  assert.equal(r.codigo, 2);
  assert.equal(r.base.tipo, "infra");
  assert.equal(r.base.canceladas, 1);
  assert.equal(r.base.fallos, 0);
  assert.deepEqual(r.resultados, []);
});

for (const enBase of [true, false]) {
  test(`suite incompleta sin tests registrados en ${enBase ? "base" : "mutante"}: no aceptar el test del archivo`, async (t) => {
    const mutante = MUTANTES[0];
    const arbol = montarArbol(t);
    writeFileSync(join(arbol.scripts, SUITE_E2E), `
      import { test } from "node:test";
      import { readFileSync } from "node:fs";
      const texto = readFileSync(new URL(${JSON.stringify(mutante.archivo)}, import.meta.url), "utf8");
      if (${enBase ? "false" : `texto.includes(${JSON.stringify(mutante.de)})`}) test("defensa", () => {});
    `);
    const r = await ejecutarMutantes({ raiz: arbol.scripts, mutantes: [mutante], suites: [SUITE_E2E], tiempoMaximoMs: 2000 });
    assert.equal(r.codigo, 2);
    const v = enBase ? r.base : r.resultados[0].verificacion;
    assert.equal(v.tipo, "infra");
    assert.match(v.motivo, /sin pruebas/);
    assert.deepEqual(v.archivosSinPruebas, [SUITE_E2E]);
    if (enBase) assert.deepEqual(r.resultados, []);
    else {
      assert.equal(r.base.tipo, "verde");
      assert.equal(r.resultados[0].veredicto, "ejecución inválida");
    }
  });
}

// ── 5. Dos corridas a la vez sobre el mismo árbol: cada una con su temporal ──

test("dos ejecuciones concurrentes no se pisan: temporales distintos, ambas verdes, ambos borrados", async (t) => {
  const arbol = montarArbol(t, { intacto: true });
  const original = arbol.leer();

  const [a, b] = await Promise.all([lanzarArnes(arbol).fin, lanzarArnes(arbol).fin]);

  assert.equal(a.codigo, 0, a.salida);
  assert.equal(b.codigo, 0, b.salida);
  const copiaA = comprobarIntacto(arbol, original, a.salida);
  const copiaB = comprobarIntacto(arbol, original, b.salida);
  assert.notEqual(copiaA, copiaB, "las dos corridas compartieron temporal");
});

// ── 6. Señales con un hijo activo: se mata al hijo, se borra el temporal, el origen no se toca ──

for (const [senal, codigo] of [["SIGINT", 130], ["SIGTERM", 143]]) {
  test(`${senal} con un hijo activo: código ${codigo}, hijo muerto, temporal borrado, fuentes intactas`, async (t) => {
    const arbol = montarArbol(t, { esperaMs: 1500 });
    const original = arbol.leer();

    const { proceso, fin } = lanzarArnes(arbol);
    await hastaQue(() => arbol.marcadores("inicio-").length > 0); // la suite hija ya corre
    proceso.kill(senal);
    const r = await fin;

    assert.equal(r.codigo, codigo, `terminó con código ${r.codigo} y señal ${r.senal}`);
    await esperar(2000); // si el hijo siguiera vivo, aquí ya habría escrito "fin-"
    assert.deepEqual(arbol.marcadores("fin-"), [], "la suite hija siguió corriendo después de la señal");
    comprobarIntacto(arbol, original, r.salida);
  });
}

test("SIGKILL al arnés: puede quedar temporal, pero las fuentes no se tocan", async (t) => {
  const arbol = montarArbol(t, { esperaMs: 1500 });
  const original = arbol.leer();

  const { proceso, fin } = lanzarArnes(arbol);
  await hastaQue(() => arbol.marcadores("inicio-").length > 0);
  proceso.kill("SIGKILL");
  const r = await fin;

  assert.equal(r.senal, "SIGKILL");
  await esperar(2000); // el hijo huérfano termina su suite: tampoco él toca el origen
  assert.deepEqual(arbol.leer(), original, "el árbol de entrada cambió");
});

// ── 7. El cierre REAL: las suites de verdad leen el mutante en la copia ──────
//
// Lo que se prueba es que las suites reales, corriendo en la copia, VEN la mutación,
// mientras el original queda byte a byte igual. Estas dos pruebas dependen de que las
// suites reales estén verdes: si no lo están, el arnés aborta con código 2 y aquí se
// ve como fallo con ese mensaje, no como mutantes muertos.

test("una mutación conocida la detecta la suite e2e real en la copia, con el original intacto", async () => {
  const conocido = MUTANTES.find((m) => /ventana horaria no filtra nada/.test(m.nombre));
  assert.ok(conocido, "el mutante de la ventana horaria ya no existe");
  const antes = FUENTES.map((f) => huella(join(AQUI, f)));

  const r = await ejecutarMutantes({ raiz: AQUI, mutantes: [conocido], suites: [SUITE_E2E] });

  assert.equal(r.codigo, 0);
  assert.ok(r.base.pruebas > 50, "la suite e2e real debería tener decenas de pruebas");
  assert.deepEqual(r.resultados.map(({ nombre, veredicto }) => ({ nombre, veredicto })), [{ nombre: conocido.nombre, veredicto: "muere" }]);
  assert.equal(r.resultados[0].verificacion.tipo, "roja");
  assert.ok(r.resultados[0].verificacion.fallos > 0);
  assert.deepEqual(FUENTES.map((f) => huella(join(AQUI, f))), antes, "el original cambió");
});

test("corrida real completa: los 46 mutantes aplican, mueren con las dos suites y el original no cambia", async () => {
  const antes = FUENTES.map((f) => huella(join(AQUI, f)));

  const r = await ejecutarMutantes({ raiz: AQUI });

  assert.equal(r.codigo, 0, "código " + r.codigo + " — " + JSON.stringify(r.resultados.filter((x) => x.veredicto !== "muere")));
  assert.equal(r.resultados.length, MUTANTES.length);
  assert.deepEqual(r.resultados.filter((x) => x.veredicto !== "muere"), []);
  assert.deepEqual(FUENTES.map((f) => huella(join(AQUI, f))), antes, "el original cambió");
});
