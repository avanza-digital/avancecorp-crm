/**
 * Mutantes del puente y el conector: romper cada defensa a propósito y exigir que la
 * suite se ponga ROJA.
 * ─────────────────────────────────────────────────────────────────────────────
 * POR QUÉ EXISTE. Una suite verde no dice que las defensas estén probadas; dice que
 * hoy nadie las rompió. Por cada arreglo hay aquí un mutante que lo neutraliza: si
 * las pruebas siguen verdes con el mutante puesto, ese arreglo NO está probado y la
 * cifra de "N pruebas" no vale nada.
 *
 * POR QUÉ ESTÁ EN EL REPO (2026-08-16). Vivía en una carpeta temporal de sesión, así
 * que "25 mutantes muertos" era una afirmación que nadie podía volver a comprobar —
 * exactamente el error que en julio costó perder el arnés de 33 aserciones del puente.
 * Lo señaló Codex y tenía razón: si no se puede re-ejecutar desde el repositorio, no
 * es evidencia.
 *
 * Correr: npm run test:mutantes
 *
 * EL ÁRBOL DE ENTRADA NO SE TOCA (2026-10-04). La primera versión escribía cada
 * mutante sobre los .gs del repositorio y los "restauraba" después: mientras corría,
 * el repositorio contenía un mutante; una edición hecha entretanto se perdía al
 * restaurar; y una señal no prevista dejaba el mutante puesto. Ahora cada corrida
 * copia el cierre completo (los dos .gs, el simulador y las dos suites) a un temporal
 * propio, muta SOLO la copia y corre `node --test` con cwd dentro de ella: las suites
 * leen el mutante por import.meta.url sin enterarse. Al terminar, o ante SIGINT/SIGTERM,
 * se mata el hijo y se borra únicamente ese temporal.
 *
 * Antes de considerar mutantes se exige una LÍNEA BASE VERDE en la copia. Un fallo de
 * ejecución (node no arranca, señal, tiempo agotado, módulo ausente, suite que no
 * llega a correr entera) NO cuenta como mutante muerto: se reporta aparte y la corrida
 * sale con código 2. Y antes de aplicarse, cada mutante comprueba que el texto que va a
 * sustituir sigue existiendo: si un arreglo se reescribe y el mutante deja de aplicar,
 * se reporta como fallo y no como éxito silencioso.
 */
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const PUENTE = "puente-drive-origen.gs";
const CONECTOR = "hoja-leads-apps-script.gs";
const SUITES = ["puente-drive-origen.test.mjs", "puente-extremo-a-extremo.test.mjs"];
/** Todo lo que las suites leen o importan. Viaja entero a la copia, sin symlinks. */
const CIERRE = [PUENTE, CONECTOR, "apps-script-simulado.mjs", ...SUITES];
const PREFIJO_TEMPORAL = join(tmpdir(), "mutantes-puente-");

/** `de` tiene que aparecer TAL CUAL en el archivo; `a` es la mutación. */
export const MUTANTES = [
  // ── La cadencia y su pre-chequeo ──────────────────────────────────────────
  {
    nombre: "el pre-chequeo no ve que el origen CRECIÓ",
    archivo: PUENTE,
    de: `    if (p.filas > m.filas) {
      motivos.push(p.nombre + ": creció (" + m.filas + " → " + p.filas + " filas)");
      return;
    }`,
    a: `    if (false) { return; }`,
  },
  {
    nombre: "el pre-chequeo se traga que el origen PERDIÓ filas",
    archivo: PUENTE,
    de: `    if (p.filas < m.filas) {
      motivos.push(p.nombre + ": PERDIÓ filas (" + m.filas + " → " + p.filas + ")");
      return;
    }`,
    a: `    if (p.filas < m.filas) { return; }`,
  },
  {
    nombre: "el pre-chequeo ignora una pestaña SIN marca",
    archivo: PUENTE,
    de: `    if (!m) {
      motivos.push(p.nombre + ": sin marca de agua (pestaña nueva o sin inicializar)");
      return;
    }`,
    a: `    if (!m) { return; }`,
  },
  {
    nombre: "no hay suelo diario (nunca se fuerza la lectura completa)",
    archivo: PUENTE,
    de: `  const forzada = String((estado || {}).pasadaCompletaEl || "") !== String((reloj || {}).fecha || "");`,
    a: `  const forzada = false;`,
  },
  {
    nombre: "el trabajo que dejó el tope a medias se olvida",
    archivo: PUENTE,
    de: `    if (Number(m.ultimaFila) < Number(m.filas)) {
      motivos.push(p.nombre + ": quedó trabajo pendiente de la pasada anterior");
    }`,
    a: `    if (false) { return; }`,
  },
  {
    nombre: "el pre-chequeo se calcula pero se ignora: siempre lectura completa",
    archivo: PUENTE,
    de: `    if (!decision.mirar) {`,
    a: `    if (false) {`,
  },
  {
    nombre: "el pre-chequeo mide con otra vara que la pasada completa (sin Math.max)",
    archivo: PUENTE,
    de: `      filas: Math.max(p.getLastRow(), 1),`,
    a: `      filas: p.getLastRow(),`,
  },
  {
    nombre: "no se recuerda lo ya detenido (96 lecturas al día por la misma avería)",
    archivo: PUENTE,
    de: `    if (Number(detenidas[p.id]) === p.filas) return;`,
    a: `    if (false) return;`,
  },
  {
    nombre: "se recuerdan como detenidas TODAS las pestañas, no solo las averiadas",
    archivo: PUENTE,
    de: `  (incidencias || []).forEach(function (x) {
    if (tam[x.id] !== undefined) r[x.id] = tam[x.id];
  });`,
    a: `  Object.keys(tam).forEach(function (k) { r[k] = tam[k]; });`,
  },

  // ── La ventana horaria ────────────────────────────────────────────────────
  {
    nombre: "la ventana horaria no filtra nada (corre 24/7, domingos incluidos)",
    archivo: PUENTE,
    de: `  if (reloj.dia === DIA_SIN_CORRIDA) {`,
    a: `  if (false) {`,
  },
  {
    nombre: "corre también de madrugada",
    archivo: PUENTE,
    de: `  if (reloj.hora < VENTANA_DESDE || reloj.hora > VENTANA_HASTA) {`,
    a: `  if (false) {`,
  },
  {
    nombre: "instalarHorario suma el nuevo disparador a los viejos",
    archivo: PUENTE,
    de: `  const borrados = quitarHorario(true);
  ScriptApp.newTrigger(FUNCION_PROGRAMADA)`,
    a: `  const borrados = 0;
  ScriptApp.newTrigger(FUNCION_PROGRAMADA)`,
  },

  // ── Los avisos: que nada se rompa en silencio ─────────────────────────────
  {
    nombre: "la corrida automática vuelve a LANZAR (96 correos de Google al día)",
    archivo: PUENTE,
    de: `  } catch (e) {
    const detalle = (e && e.message) ? e.message : String(e);`,
    a: `  } catch (e) {
    if (e) throw e;
    const detalle = String(e);`,
  },
  {
    nombre: "una corrida solapada se reporta como ERROR (alerta por lo que funciona)",
    archivo: PUENTE,
    de: `    if (/Ya hay una corrida/.test(detalle)) {`,
    a: `    if (false) {`,
  },
  {
    nombre: "sin marcas, la corrida automática se lo calla (ni avisa ni anota)",
    archivo: PUENTE,
    de: `      anotarAviso("sin-marcas", "El puente está PARADO: falta la marca de agua", aviso, reloj);`,
    a: `      aviso.length;`,
  },
  {
    nombre: "el diario da hoy por leído aunque la pasada no llegara a hacerse",
    archivo: PUENTE,
    de: `      anotarEstado({ ultimaCorrida: reloj.texto, ultimoVeredicto: "PARADO: sin marca de agua" });`,
    a: `      anotarEstado({ ultimaCorrida: reloj.texto, ultimoVeredicto: "PARADO: sin marca de agua", pasadaCompletaEl: reloj.fecha });`,
  },
  {
    nombre: "el aviso reescribe su fecha de inicio en cada corrida",
    archivo: PUENTE,
    de: `    desde: (previo && previo.desde) || reloj.texto,`,
    a: `    desde: reloj.texto,`,
  },
  {
    nombre: "el aviso de pestaña detenida no se apaga al arreglarse",
    archivo: PUENTE,
    de: `    } else {
      limpiarAviso("pestana-detenida");
    }`,
    a: `    }`,
  },
  {
    nombre: "el aviso de error no se apaga cuando la corrida vuelve a salir bien",
    archivo: PUENTE,
    de: `    limpiarAviso("error");`,
    a: `    true;`,
  },
  {
    nombre: "abrir la hoja no dice nada de los avisos pendientes",
    archivo: PUENTE,
    de: `  avisarEnPantalla();`,
    a: `  true;`,
  },
  {
    nombre: "el aviso salta al abrir la hoja aunque no haya nada que decir",
    archivo: PUENTE,
    de: `    if (!claves.length) return 0;`,
    a: `    if (false) return 0;`,
  },
  {
    nombre: "el panel afirma que el origen recibió HOY sin haberlo visto crecer nunca",
    archivo: PUENTE,
    de: `  } else if (!est.crecioEl) {`,
    a: `  } else if (false) {`,
  },

  // ── El orden de las escrituras (hallazgos de Codex, 2026-08-16) ───────────
  {
    nombre: "el chequeo de teléfono vuelve a ir ANTES de comprobar la pestaña",
    archivo: PUENTE,
    de: `    const marca = marcasPrevias[idPestana];
    const veredicto = revisarPestana(`,
    a: `    if (col.telefono < 0 && col.whatsapp < 0) return;
    const marca = marcasPrevias[idPestana];
    const veredicto = revisarPestana(`,
  },
  {
    nombre: "REVISAR vuelve a escribirse DESPUÉS de mover la frontera",
    archivo: PUENTE,
    de: `    escribirRechazos(destino, rechazados);
    // Se fusiona sobre lo previo para no perder la marca de una pestaña que esta
    // pasada no llegó a mirar (tope alcanzado, detenida por incidencia, sin teléfono).
    guardarMarcas(destino, fusionar(marcasPrevias, marcasNuevas));`,
    a: `    guardarMarcas(destino, fusionar(marcasPrevias, marcasNuevas));
    escribirRechazos(destino, rechazados);`,
  },
  {
    nombre: "guardar la frontera vuelve a ser borrar-y-luego-escribir",
    archivo: PUENTE,
    de: `  const filasPrevias = Math.max(hoja.getLastRow() - 1, 0);
  const alto = Math.max(claves.length, filasPrevias);
  asegurarFilas(hoja, 1 + alto);`,
    a: `  if (hoja.getLastRow() > 1) {
    hoja.getRange(2, 1, hoja.getLastRow() - 1, CABECERA_MARCAS.length).clearContent();
  }
  const alto = claves.length;
  asegurarFilas(hoja, 1 + alto);`,
  },

  // ── Los datos que pasan por una celda ─────────────────────────────────────
  {
    nombre: "la fecha de la celda se lee con String(Date) (zona del PROYECTO, en inglés)",
    archivo: PUENTE,
    de: `  if (Object.prototype.toString.call(v) === "[object Date]") {
    return Utilities.formatDate(v, ZONA_DE_CORRIDA, "dd/MM/yyyy HH:mm");
  }`,
    a: `  if (false) { return ""; }`,
  },
  {
    nombre: "la rejilla de marcas deja de forzarse a TEXTO (Sheets vuelve a interpretar)",
    archivo: PUENTE,
    de: `  forzarTexto(hoja, CABECERA_MARCAS.length);`,
    a: `  true;`,
  },
  {
    nombre: "todas las fronteras se sellan con la hora de hoy, tocadas o no",
    archivo: PUENTE,
    de: `      m.actualizado || cuando];`,
    a: `      cuando];`,
  },
  {
    nombre: "el sheetId se lee como NÚMERO (la pestaña con id 0 desaparece)",
    archivo: PUENTE,
    de: `      const id = String(f[0]).trim();
      if (!id) return;`,
    a: `      const id = Number(f[0]);
      if (!id) return;`,
  },
  {
    nombre: "una fecha imposible (99/99/2026) vuelve a ser salvoconducto",
    archivo: PUENTE,
    de: `  const vuelta = new Date(ms);
  if (vuelta.getUTCMonth() !== m - 1 || vuelta.getUTCDate() !== dd) return null;`,
    a: ``,
  },

  // ── El origen cambió cómo escribe la fecha (2026-09-01) ───────────────────
  {
    nombre: "el corte vuelve a condenar una fecha AMBIGUA (el fallo del 2026-09-01)",
    archivo: PUENTE,
    de: `  if (corte !== null && fecha && fecha.msTarde < corte) {`,
    a: `  if (corte !== null && fecha && fecha.ms < corte) {`,
  },
  {
    nombre: "el texto de la celda vuelve a pisar a la fecha que Sheets GUARDA",
    archivo: PUENTE,
    de: `  const dn = piezasDeIso(String(nativa || ""));
  if (dn) return fechaCierta(dn);`,
    a: ``,
  },
  {
    nombre: "solo se prueba la lectura DD/MM (la otra mitad del formato desaparece)",
    archivo: PUENTE,
    de: `  if (!comoInglesa) return fechaCierta(comoLatina);
  if (!comoLatina) return fechaCierta(comoInglesa);`,
    a: `  if (!comoInglesa) return fechaCierta(comoLatina);
  if (!comoLatina) return null;`,
  },
  {
    nombre: "el corte vuelve a condenar una fila NUEVA por una fecha imposible",
    archivo: PUENTE,
    de: `    if (!(marca > 0 && numeroFila > marca)) {`,
    a: `    if (true) {`,
  },
  {
    nombre: "la fecha falsa se cuela en el desglose por mes y en la huella",
    archivo: PUENTE,
    de: `    lead.fecha = null;   // no puede contaminar el desglose por mes ni la huella`,
    a: ``,
  },
  {
    nombre: "el origen corrompe fechas y el panel se queda mudo",
    archivo: PUENTE,
    de: `      if (lead.fechaImposible) fechasImposibles++;`,
    a: ``,
  },
  {
    nombre: "el nombre del lead se escribe sin quitarle el = inicial (fórmula)",
    archivo: PUENTE,
    de: `      sinFormula(l.nombre),   // A Nombre completo *`,
    a: `      l.nombre,               // A Nombre completo *`,
  },

  // ── El rescate: retroceder la marca de agua ───────────────────────────────
  {
    nombre: "el rescate NO recalcula el ancla (la pestaña se detendría en la siguiente pasada)",
    archivo: PUENTE,
    de: `    ancla: anclaDeFilas(datos, n),`,
    a: `    ancla: marca.ancla,`,
  },
  {
    nombre: "el rescate acepta ADELANTAR la frontera (leads que desaparecen sin rastro)",
    archivo: PUENTE,
    de: `  if (n >= Number(marca.ultimaFila)) {`,
    a: `  if (false) {`,
  },
  {
    nombre: "el rescate deja desandar el origen entero",
    archivo: PUENTE,
    de: `  if (Number(marca.ultimaFila) - n > TOPE_RETROCESO) {`,
    a: `  if (false) {`,
  },
  {
    nombre: "el rescate mueve la frontera aunque quien mira CANCELE",
    archivo: PUENTE,
    de: `  if (confirmar !== ui.Button.OK) return null;`,
    a: ``,
  },

  // ── El conector ───────────────────────────────────────────────────────────
  {
    nombre: "la hoja no reconoce «YA ES CLIENTE» (lo reintentaría y anotaría reingresos repetidos)",
    archivo: CONECTOR,
    de: `  else if (estado.indexOf("YA ES CLIENTE") === 0) porEstado = "ya_cliente";\n`,
    a: ``,
  },
  {
    nombre: "el panel cuenta «YA ES CLIENTE» como «otros» (invisible)",
    archivo: PUENTE,
    de: `    else if (e.indexOf("YA ES CLIENTE") === 0) cuenta.ya_clientes++;\n`,
    a: ``,
  },
  {
    nombre: "el contador del panel vuelve a ignorar las filas sin teléfono principal",
    archivo: PUENTE,
    de: `    const hayDatos = String(identidad[i][0]).trim() || String(identidad[i][1]).trim() || String(estados[i][0]).trim();`,
    a: `    const hayDatos = String(identidad[i][1]).trim();`,
  },
  {
    nombre: "onEdit limpia «YA ES CLIENTE» como si fuera un rechazo",
    archivo: CONECTOR,
    de: `    if (estado.indexOf("IMPORTADO") === 0 || estado.indexOf("YA ES CLIENTE") === 0) continue;`,
    a: `    if (estado.indexOf("IMPORTADO") === 0) continue;`,
  },
  {
    nombre: "activarConector deja de exigir el secreto antes de encender",
    archivo: CONECTOR,
    de: `  secretoDeImportacion(); // falla AQUÍ si falta, no dentro del primer ciclo silencioso`,
    a: `  true;`,
  },
];

/**
 * Corre las suites en la copia, en un proceso hijo con cwd dentro de ella.
 * Devuelve tipo, contadores de integridad TAP, nombres de fallos y motivo.
 * "roja" es lo único que puede matar un mutante: aserciones que fallaron con la suite
 * entera corrida. Todo lo demás es un problema de ejecución, no una defensa probada.
 */
function correrSuites(copia, suites, tiempoMaximoMs, alCambiarHijo) {
  return new Promise((resolver) => {
    let salida = "";
    let terminado = false;
    // Si el arnés corre dentro de otro `node --test`, el hijo heredaría NODE_TEST_CONTEXT
    // y el runner anidado dejaría de emitir TAP. El hijo es un runner nuevo.
    const entorno = { ...process.env };
    delete entorno.NODE_TEST_CONTEXT;
    const hijo = spawn(
      process.execPath,
      ["--test", "--test-reporter=tap", "--test-reporter-destination=stdout", ...suites.map((s) => join("scripts", s))],
      { cwd: copia, env: entorno, stdio: ["ignore", "pipe", "ignore"], detached: true }
    );
    alCambiarHijo(hijo);
    hijo.stdout.on("data", (d) => { salida += d; });
    const resolve = (resultado) => {
      if (terminado) return;
      terminado = true;
      clearTimeout(temporizador);
      matar(hijo);
      hijo.stdout.destroy();
      alCambiarHijo(null);
      resolver(resultado);
    };
    // El plazo resuelve por sí mismo: un pipe heredado no puede retener `close`.
    const temporizador = setTimeout(() => resolve({ tipo: "infra", motivo: `superó los ${tiempoMaximoMs} ms` }), tiempoMaximoMs);
    // El líder puede salir antes que sus descendientes y antes de `close`.
    hijo.once("exit", () => matar(hijo));
    hijo.on("error", (e) => {
      resolve({ tipo: "infra", motivo: `no se pudo lanzar node (${e.code || e.message})` });
    });
    hijo.on("close", (codigo, senal) => {
      if (terminado) return;
      if (senal) return resolve({ tipo: "infra", motivo: `node --test terminó por señal ${senal}` });
      if (/ERR_MODULE_NOT_FOUND|Cannot find (module|package)/.test(salida)) {
        return resolve({ tipo: "infra", motivo: "falta un módulo o archivo del cierre" });
      }
      const cuenta = (clave) => {
        const m = salida.match(new RegExp(`^# ${clave} (\\d+)$`, "m"));
        return m ? Number(m[1]) : null;
      };
      const integridad = {
        pruebas: cuenta("tests"), suites: cuenta("suites"), aprobadas: cuenta("pass"),
        fallos: cuenta("fail"), canceladas: cuenta("cancelled"),
        omitidas: cuenta("skipped"), pendientes: cuenta("todo"),
      };
      // Node cuenta como un test el propio archivo si este no registró ninguno.
      const subpruebas = new Set([...salida.matchAll(/^# Subtest: (.+)$/gm)].map((m) => m[1]));
      const archivosSinPruebas = suites.filter((s) => subpruebas.has(join("scripts", s)));
      const resultado = { ...integridad, archivosSinPruebas, codigo, senal };
      const infra = (motivo) => resolve({ ...resultado, tipo: "infra", motivo });
      if (Object.values(integridad).some((n) => n === null)) {
        return infra(`node --test no entregó resumen completo (código ${codigo})`);
      }
      const { pruebas, aprobadas, fallos, canceladas, omitidas, pendientes } = integridad;
      if (canceladas || omitidas || pendientes) {
        return infra(`${canceladas} cancelada(s), ${omitidas} omitida(s), ${pendientes} pendiente(s)`);
      }
      if (pruebas === 0 || archivosSinPruebas.length || /^\s*1\.\.0\s*$/m.test(salida)) return infra("suite sin pruebas");
      if (pruebas !== aprobadas + fallos) return infra("resumen de pruebas inconsistente");
      if (codigo === 0 && fallos === 0) return resolve({ ...resultado, tipo: "verde" });
      if (codigo !== 1 || fallos === 0) return infra(`salida sin fallos de pruebas coherentes (código ${codigo})`);
      // Solo nombres de pruebas: nunca el detalle, que puede contener datos de las fuentes.
      const nombres = [...salida.matchAll(/^not ok \d+ - (.*)$/gm)].map((m) => m[1]);
      resolve({ ...resultado, tipo: "roja", nombres });
    });
  });
}

/** Mata al hijo y a todo su grupo (node --test lanza un proceso por suite). */
function matar(hijo) {
  if (!hijo?.pid) return;
  try { process.kill(-hijo.pid, "SIGKILL"); } catch { /* ya no existe */ }
}

/**
 * Ejecuta todos los mutantes sobre una COPIA de `raiz` y devuelve
 * { codigo, base, resultados }. Código 0: todos muertos; 1: alguno sobrevive o no
 * aplica; 2: línea base roja o fallos de ejecución. Nunca escribe en `raiz`.
 */
export async function ejecutarMutantes(opciones = {}) {
  let copia = null;
  let hijo = null;
  const limpiar = () => {
    matar(hijo);
    // Solo el temporal propio: jamás un rm fuera de él.
    if (copia && copia.startsWith(PREFIJO_TEMPORAL)) rmSync(copia, { recursive: true, force: true });
    copia = null;
  };
  const porSenal = (senal) => { limpiar(); process.exit(senal === "SIGINT" ? 130 : 143); };
  const alSalir = () => limpiar();
  process.once("SIGINT", porSenal);
  process.once("SIGTERM", porSenal);
  process.once("exit", alSalir);

  const resultados = [];
  try {
    if (!opciones || typeof opciones !== "object" || Array.isArray(opciones)) throw new Error("opciones inválidas");
    const {
      raiz = AQUI, mutantes: descriptores = MUTANTES,
      suites: seleccionSuites = SUITES, tiempoMaximoMs = 180_000,
    } = opciones;
    if (typeof raiz !== "string" || !raiz.length || !Number.isFinite(tiempoMaximoMs) || tiempoMaximoMs <= 0 || tiempoMaximoMs > 2 ** 31 - 1) {
      throw new Error("raíz o plazo inválidos");
    }
    if (!Array.isArray(descriptores) || !Array.isArray(seleccionSuites)) throw new Error("listas de opciones inválidas");
    // Capturar valores antes del primer await; nunca volver a consultar al caller.
    const mutantes = Array.from(descriptores, (m) => {
      if (!m || typeof m !== "object" || Array.isArray(m)) throw new Error("descriptor inválido");
      const { nombre, archivo, de, a } = m;
      return { nombre, archivo, de, a };
    });
    const suites = Array.from(seleccionSuites);
    for (const m of mutantes) {
      if (Object.values(m).some((v) => typeof v !== "string") || !m.nombre.length || !m.de.length) throw new Error("descriptor inválido");
      if (m.archivo !== PUENTE && m.archivo !== CONECTOR) throw new Error("archivo fuera del cierre permitido");
    }
    if (!suites.length || suites.some((s) => !SUITES.includes(s))) throw new Error("suites fuera del cierre permitido");
    copia = mkdtempSync(PREFIJO_TEMPORAL);
    mkdirSync(join(copia, "scripts"));
    for (const f of CIERRE) {
      copyFileSync(join(raiz, f), join(copia, "scripts", f));
      chmodSync(join(copia, "scripts", f), 0o644); // el origen puede ser de solo lectura; la copia no
    }
    const originales = new Map();
    for (const m of mutantes) {
      if (!originales.has(m.archivo)) originales.set(m.archivo, readFileSync(join(copia, "scripts", m.archivo), "utf8"));
    }
    const correr = () => correrSuites(copia, suites, tiempoMaximoMs, (h) => { hijo = h; });

    console.log(`Mutantes del puente: ${mutantes.length}`);
    console.log(`Copia de trabajo: ${copia}`);

    const base = await correr();
    if (base.tipo !== "verde") {
      const motivo = base.tipo === "infra"
        ? `fallo de ejecución: ${base.motivo}`
        : `${base.fallos} prueba(s) ROJA(S) de ${base.pruebas}:\n  · ${base.nombres.slice(0, 10).join("\n  · ")}`;
      console.error(`\n✖ LÍNEA BASE NO VERDE — ${motivo}\nSin base verde no se puede medir ningún mutante. Abortado.`);
      return { codigo: 2, base, resultados };
    }
    console.log(`Línea base: ${base.pruebas} pruebas verdes en la copia.\n`);

    let sobreviven = 0;
    let invalidas = 0;
    for (const m of mutantes) {
      const texto = originales.get(m.archivo);
      const enCopia = join(copia, "scripts", m.archivo);
      let veredicto;
      let verificacion;
      if (!texto.includes(m.de)) {
        veredicto = "no aplica";
        console.error(`⚠️  NO APLICA (el código cambió y este mutante quedó obsoleto): ${m.nombre}`);
        sobreviven++;
      } else {
        writeFileSync(enCopia, texto.replace(m.de, m.a));
        const r = await correr();
        verificacion = r;
        writeFileSync(enCopia, texto); // se restaura LA COPIA, nunca el origen
        if (r.tipo === "infra" || r.pruebas !== base.pruebas) {
          veredicto = "ejecución inválida";
          const motivo = r.tipo === "infra" ? r.motivo : `la suite no corrió entera (${r.pruebas} de ${base.pruebas} pruebas)`;
          console.error(`⚠️  EJECUCIÓN INVÁLIDA (no cuenta como muerto): ${m.nombre} — ${motivo}`);
          invalidas++;
        } else if (r.tipo === "verde") {
          veredicto = "sobrevive";
          console.error(`✖ SOBREVIVE: ${m.nombre}`);
          sobreviven++;
        } else {
          veredicto = "muere";
          console.log(`✔ muere:     ${m.nombre}`);
        }
      }
      resultados.push({ nombre: m.nombre, veredicto, ...(verificacion && { verificacion }) });
    }

    console.log(`\n${mutantes.length - sobreviven - invalidas}/${mutantes.length} mutantes muertos.`);
    if (sobreviven) {
      console.error(
        `\n${sobreviven} mutante(s) sobreviven: esas defensas NO están probadas.\n` +
        `Un mutante vivo significa que se puede romper el arreglo sin que ninguna prueba se entere.\n`
      );
    }
    if (invalidas) {
      console.error(`\n${invalidas} ejecución(es) inválida(s): no se pudo medir esos mutantes. La corrida no vale.\n`);
    }
    return { codigo: invalidas ? 2 : sobreviven ? 1 : 0, base, resultados };
  } catch {
    // También cubre getters que lancen: no publicar valores ni mensajes del caller.
    console.error("\n✖ El arnés no pudo correr: opciones inválidas o fallo de infraestructura");
    return { codigo: 2, resultados };
  } finally {
    limpiar();
    process.off("SIGINT", porSenal);
    process.off("SIGTERM", porSenal);
    process.off("exit", alSalir);
  }
}

const esCli = (() => {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; }
})();
if (esCli) ejecutarMutantes().then((r) => process.exit(r.codigo));
