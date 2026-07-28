/**
 * Pruebas del puente origen→hoja (puente-drive-origen.gs) con `node --test`.
 * Correr: npm run test:puente  (o `node --test scripts/puente-drive-origen.test.mjs`)
 *
 * El arnés original (probar-puente.mjs, 33 aserciones) se perdió por vivir en el
 * scratchpad de una sesión — este vive EN EL REPO para que no vuelva a pasar.
 *
 * El .gs no es un módulo: se carga con new Function() y se le piden las funciones
 * puras. Los encabezados y filas de prueba son copias de filas REALES del documento
 * de origen (02PLAZOFIJOMAS LANDING) leídas el 2026-07-27, teléfonos incluidos tal
 * cual (ya son datos operativos del negocio, no inventados).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const aqui = dirname(fileURLToPath(import.meta.url));
const fuente = readFileSync(join(aqui, "puente-drive-origen.gs"), "utf8");
const gs = new Function(
  fuente +
    "\nreturn { ubicarColumnas, normalizarFila, telefonoPeru, telefonoEnOtraCelda, pidePrestamo, filaLegible, legible, montoDe, monedaDe, siNo, ordenRevision };"
)();

// Encabezados REALES de las dos pestañas del origen (2026-07-27).
const CAB_LANDING = [
  "nombre", "Apellidos", "Celular", "WhatsApp", "Departamento", "Distrito",
  "¿Deseas depositar en plazo fijo en soles o dólares?",
  "¿Cuánto dinero deseas depositar?", "¿Ya eres socio de nuestra cooperativa?",
  "Estoy de acuerdo en recibir información comercial de la COOPAC MÁSCAPITAL",
  "Fecha de Registro", "", "",
];
const CAB_FB = [
  "red social", "fecha", "¿deseas aperturar tus ahorros a plazofijo?",
  "¿deseas ahorrar en soles o dolares con una taza de hasta el 15%?",
  "¿qué monto deseas ahorrar?", "¿eres socio de la cooperativa?",
  "Tienes alguna pregunta con respecto a nuestra campaña de ahorro a plazofijo?",
  "celular", "nombre", "celular", "ciudad", "", "",
];
const colLanding = gs.ubicarColumnas(CAB_LANDING);
const colFb = gs.ubicarColumnas(CAB_FB);

test("mapeo landing: cada campo cae en su columna", () => {
  assert.equal(colLanding.nombre, 0);
  assert.equal(colLanding.apellido, 1);
  assert.equal(colLanding.telefono, 2);
  assert.equal(colLanding.whatsapp, 3);
  assert.equal(colLanding.distrito, 5);
  assert.equal(colLanding.moneda, 6);   // "soles o dólares" es moneda, no monto
  assert.equal(colLanding.monto, 7);
  assert.equal(colLanding.consent, 9);  // "MÁSCAPITAL" no se la roba como monto
  assert.deepEqual(colLanding.fechas, [10]);
});

test("mapeo fb: la 2ª columna 'celular' queda sin asignar (por eso existe el rescate)", () => {
  assert.equal(colFb.telefono, 7);      // la primera "celular"
  assert.equal(colFb.whatsapp, -1);     // la segunda NO matchea "celular 2"
  assert.equal(colFb.pregunta, 6);
  assert.equal(colFb.consent, -1);      // fb no trae la columna → default SI
});

// ── Fecha: sin fecha ENTRA; fecha vieja se corta ─────────────────────────────

test("sin fecha legible → ENTRA igual, marcado y con aviso en la Nota", () => {
  const fila = ["Liliana", "Pinche Dahua", "51918620573", "51918620573",
    "Loreto", "Pampa hermosa", "Soles", "1,000", "Si", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 671, CAB_LANDING);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, true);
  assert.equal(l.telefono, "+51918620573");
  assert.match(l.nota, /Sin fecha en el origen/);
});

test("fecha legible ANTERIOR al corte → descartada como backlog (no a REVISAR)", () => {
  const fila = ["Pamela", "Valderrama", "964262777", "964262777",
    "Lima", "Miraflores", "Soles/Dólares", "10,000", "NO", "Si", "20/07/2025 11:43", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 4, CAB_LANDING);
  assert.match(l.motivo, /^Anterior al corte/);
});

test("fecha legible nueva → entra con su fecha, sin marca de sinFecha", () => {
  const fila = ["Carmen rosa", "Joya ormeño", "51918376855", "51918376855",
    "Lima", "Surquillo", "Soles", "50,000 a más", "Si", "Si", "23/07/2026 9:10", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 689, CAB_LANDING);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, false);
  assert.equal(l.capital, "50000");
});

// ── Rescate de teléfono (casos reales de REVISAR del 2026-07-27) ─────────────

test("rescate: celular trae un monto, el número real está en otra columna con 'p:'", () => {
  // Fila real: cuillrmo — celular="5ooooo", el número en la 2ª col "celular".
  const fila = ["fb", "2026-07-23T18:47:09-05:00", "✅_si_deseo_aperturar_mi_cuenta_de_ahorros",
    "ð¡_ahorrar_en_soles", "50,000_", "si_", "Ay", "5ooooo", "cuillrmo",
    "p:+51910585900", "50000", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 5948, CAB_FB);
  assert.equal(l.motivo, "");
  assert.equal(l.telefono, "+51910585900");
  assert.equal(l.telefonoRescatado, true);
  assert.match(l.nota, /OTRA columna/);
  assert.equal(l.capital, "50000");
  assert.equal(l.moneda, "PEN");
});

test("rescate: celular con 10 dígitos inválidos, número real en otra columna", () => {
  // Fila real: David — celular="9158903210" (10 dígitos) no sirve.
  const fila = ["fb", "2026-07-23T17:09:15-05:00", "✅_si_deseo_aperturar_mi_cuenta_de_ahorros",
    "ð¡_ahorrar_en_soles", "50,000_", "no", "no grasias", "9158903210", "David",
    "p:+51913264211", "trujillo", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 5950, CAB_FB);
  assert.equal(l.motivo, "");
  assert.equal(l.telefono, "+51913264211");
  assert.equal(l.telefonoRescatado, true);
});

test("el rescate NO toma un número de la columna de monto ni una fecha", () => {
  const fila = ["fb", "2026-07-23T10:00:00-05:00", "✅_si", "ð¡_ahorrar_en_soles",
    "987654321", "no", "", "basura", "Fulano", "", "Lima", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 10, CAB_FB);
  assert.equal(l.motivo, "Sin teléfono válido (se buscó en toda la fila)");
});

test("sin ningún teléfono en toda la fila → REVISAR con motivo claro", () => {
  const fila = ["Manuel", "Lomas", "Manuel LOMAS", "", "Lima", "Lima",
    "Soles", "1,000", "no", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 99, CAB_LANDING);
  assert.equal(l.motivo, "Sin teléfono válido (se buscó en toda la fila)");
  assert.equal(l.nombre, "Manuel Lomas"); // REVISAR sale con el nombre visible
});

// ── Préstamos → REVISAR ──────────────────────────────────────────────────────

test("pide préstamo → REVISAR, con nombre y teléfono visibles para quien revisa", () => {
  const fila = ["fb", "2026-07-24T08:00:00-05:00", "✅_si", "ð¡_ahorrar_en_soles",
    "1,000_", "no", "quiero prestamo", "943315482", "miguel brice;o",
    "p:+51943315482", "///", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 5960, CAB_FB);
  assert.equal(l.motivo, "Pide PRÉSTAMO — no es lead de ahorro");
  assert.equal(l.telefono, "+51943315482");
  assert.equal(l.nombre, "miguel brice;o");
});

test("variantes de préstamo/crédito que deben ir a REVISAR", () => {
  for (const p of ["quiero prestamo", "Préstamos por favor", "necesito un crédito",
    "dan creditos?", "me pueden prestar 5000"]) {
    assert.equal(gs.pidePrestamo(p), true, p);
  }
});

test("preguntas de ahorro NO se confunden con préstamo", () => {
  for (const p of ["cual es la taza de interes?", "que importe cubre el seguro?",
    "Tienen seguro de la SBS?", "solo cuenta de ahorros", "", "no", "ok"]) {
    assert.equal(gs.pidePrestamo(p), false, p || "(vacía)");
  }
});

test("orden de REVISAR: lo accionable arriba, los duplicados al final", () => {
  const motivos = [
    "Teléfono ya presente en la hoja",
    "Sin nombre",
    "Pide PRÉSTAMO — no es lead de ahorro",
    "Teléfono repetido dentro del origen",
    "Sin teléfono válido (se buscó en toda la fila)",
  ];
  const orden = motivos.slice().sort((a, b) => gs.ordenRevision(a) - gs.ordenRevision(b));
  assert.deepEqual(orden, [
    "Pide PRÉSTAMO — no es lead de ahorro",
    "Sin teléfono válido (se buscó en toda la fila)",
    "Sin nombre",
    "Teléfono repetido dentro del origen",
    "Teléfono ya presente en la hoja",
  ]);
});

// ── Formato legible de REVISAR ───────────────────────────────────────────────

test("filaLegible: cada dato con su encabezado, una línea por dato", () => {
  const texto = gs.filaLegible(
    ["fb", "50,000_", "si_", "", "p:+51910585900"],
    ["red social", "¿qué monto deseas ahorrar?", "¿eres socio?", "vacia", "celular"]
  );
  assert.equal(texto,
    "red social: fb\n¿qué monto deseas ahorrar?: 50,000\n¿eres socio?: si\ncelular: p:+51910585900");
});

test("legible: limpia los guiones bajos de Facebook pero no rompe fechas ISO", () => {
  assert.equal(gs.legible("✅_si_deseo_aperturar_mi_cuenta_de_ahorros"),
    "si deseo aperturar mi cuenta de ahorros");
  assert.equal(gs.legible("2026-07-23T18:47:09-05:00"), "2026-07-23T18:47:09-05:00");
});
