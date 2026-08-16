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
 * Cada mutante restaura el archivo pase lo que pase (también con Ctrl-C), y antes de
 * aplicarse comprueba que el texto que va a sustituir sigue existiendo: si un arreglo
 * se reescribe y el mutante deja de aplicar, se reporta como fallo y no como éxito
 * silencioso.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..");
const PUENTE = join(AQUI, "puente-drive-origen.gs");
const CONECTOR = join(AQUI, "hoja-leads-apps-script.gs");

/** `de` tiene que aparecer TAL CUAL en el archivo; `a` es la mutación. */
const MUTANTES = [
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
    de: `    const vuelta = new Date(ms);
    if (vuelta.getUTCMonth() !== d.m - 1 || vuelta.getUTCDate() !== d.dd) return;`,
    a: `    const vuelta = ms;`,
  },
  {
    nombre: "el nombre del lead se escribe sin quitarle el = inicial (fórmula)",
    archivo: PUENTE,
    de: `      sinFormula(l.nombre),   // A Nombre completo *`,
    a: `      l.nombre,               // A Nombre completo *`,
  },

  // ── El conector ───────────────────────────────────────────────────────────
  {
    nombre: "activarConector deja de exigir el secreto antes de encender",
    archivo: CONECTOR,
    de: `  secretoDeImportacion(); // falla AQUÍ si falta, no dentro del primer ciclo silencioso`,
    a: `  true;`,
  },
];

const original = new Map();
for (const m of MUTANTES) {
  if (!original.has(m.archivo)) original.set(m.archivo, readFileSync(m.archivo, "utf8"));
}
const restaurar = () => {
  for (const [archivo, texto] of original) writeFileSync(archivo, texto);
};
process.on("exit", restaurar);
process.on("SIGINT", () => { restaurar(); process.exit(130); });

const suiteVerde = () => {
  try {
    execSync("npm run test:puente --silent && npm run test:puente:e2e --silent", {
      cwd: RAIZ,
      stdio: "pipe",
    });
    return true;
  } catch {
    return false;
  }
};

console.log(`Mutantes del puente: ${MUTANTES.length}\n`);
let sobreviven = 0;

for (const m of MUTANTES) {
  const texto = original.get(m.archivo);
  if (!texto.includes(m.de)) {
    console.error(`⚠️  NO APLICA (el código cambió y este mutante quedó obsoleto): ${m.nombre}`);
    sobreviven++;
    continue;
  }
  writeFileSync(m.archivo, texto.replace(m.de, m.a));
  const verde = suiteVerde();
  restaurar();
  if (verde) {
    console.error(`✖ SOBREVIVE: ${m.nombre}`);
    sobreviven++;
  } else {
    console.log(`✔ muere:     ${m.nombre}`);
  }
}

console.log(`\n${MUTANTES.length - sobreviven}/${MUTANTES.length} mutantes muertos.`);
if (sobreviven) {
  console.error(
    `\n${sobreviven} mutante(s) sobreviven: esas defensas NO están probadas.\n` +
    `Un mutante vivo significa que se puede romper el arreglo sin que ninguna prueba se entere.\n`
  );
  process.exit(1);
}
