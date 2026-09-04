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
    "\nreturn { ubicarColumnas, normalizarFila, telefonoPeru, telefonosDeFila, telefonoEnOtraCelda," +
    " pidePrestamo, filaLegible, legible, montoDe, monedaDe, siNo, ordenRevision," +
    " revisarPestana, huellaTexto, huellaCabeceras, anclaDeFilas, esDescartePorDiseno," +
    " fechaDeCelda, marcaRetrocedida, TOPE_RETROCESO," +
    " fusionar, momentoDe, diasEntre, dentroDeVentana, decidirPasada, textoDelPanel," +
    " celdasTelefonicas, clasificarSegundoNumero, nuevoConteoSegundos," +
    " reconocerTelefono, telefonoContacto," +
    " informeSegundosNumeros," +
    " FECHA_CORTE, MOTIVO_BACKLOG, MOTIVO_CORTE, CADENCIA_MINUTOS," +
    " VENTANA_DESDE, VENTANA_HASTA };"
)();

/**
 * LAS FECHAS DE PRUEBA SE DERIVAN DEL CORTE, NUNCA SE ESCRIBEN A MANO.
 *
 * El 2026-08-11 el corte se movió de julio a agosto y estas pruebas se pusieron rojas
 * en silencio: sus filas, fechadas el 23 de julio, pasaron a ser "backlog" y morían en
 * el corte antes de llegar a lo que cada prueba mide (el mapeo, el rescate de teléfono,
 * el préstamo). Nadie lo vio porque `test:puente` no estaba en ningún control.
 *
 * Derivándolas del corte, mover la fecha ya no puede romper una prueba que no habla de
 * fechas — y las tres que SÍ hablan de fechas prueban justo la frontera: el día antes,
 * el día del corte y el día después.
 */
const CORTE = gs.FECHA_CORTE;
const dias = (iso, n) => {
  const t = Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) + n * 86400000;
  return new Date(t).toISOString().slice(0, 10);
};
const latina = (iso) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const ANTES = dias(CORTE, -1);   // víspera del corte → NO entra
const JUSTO = CORTE;             // el día del corte → SÍ entra
const DESPUES = dias(CORTE, 1);  // el día siguiente → SÍ entra

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
  assert.equal(l.telefonoAlternativo, "", "WhatsApp repetido no debe duplicarse");
  assert.match(l.nota, /Sin fecha en el origen/);
});

test("dos celulares distintos conservan principal y alternativo", () => {
  const fila = ["Rosa", "Diaz", "918620573", "987654321",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 700, CAB_LANDING);
  assert.equal(l.telefono, "+51918620573");
  assert.equal(l.telefonoAlternativo, "+51987654321");
});

test("la segunda columna celular no mapeada también se conserva como alternativo", () => {
  const fila = ["fb", `${DESPUES}T18:47:09-05:00`, "si", "ahorrar en soles",
    "50,000", "si", "", "918000001", "Rosa Diaz", "p:+51918000002", "Lima", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 6001, CAB_FB);
  assert.equal(l.telefono, "+51918000001");
  assert.equal(l.telefonoAlternativo, "+51918000002");
  assert.equal(l.telefonoRescatado, false);
});

const filaLanding = (fecha) => ["Carmen rosa", "Joya ormeño", "51918376855", "51918376855",
  "Lima", "Surquillo", "Soles", "50,000 a más", "Si", "Si", fecha, "", ""];

test("la VÍSPERA del corte → descartada como backlog (no a REVISAR)", () => {
  const l = gs.normalizarFila(filaLanding(latina(ANTES) + " 11:43"), colLanding, "landing", 4, CAB_LANDING);
  assert.match(l.motivo, /^Anterior al corte/);
  assert.equal(gs.esDescartePorDiseno(l.motivo), true); // no ensucia REVISAR
});

test("el DÍA del corte → entra (el corte es 'desde', no 'después de')", () => {
  const l = gs.normalizarFila(filaLanding(latina(JUSTO) + " 9:10"), colLanding, "landing", 689, CAB_LANDING);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, false);
});

test("el día DESPUÉS del corte → entra con su fecha, sin marca de sinFecha", () => {
  const l = gs.normalizarFila(filaLanding(latina(DESPUES) + " 9:10"), colLanding, "landing", 689, CAB_LANDING);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, false);
  assert.equal(l.capital, "50000");
});

// ── El origen cambió cómo escribe la fecha (2026-09-01) ─────────────────────
//
// A media mañana del 2026-09-01 el origen pasó de escribir DD/MM/AAAA a MM/DD/AAAA.
// El puente leía siempre el primer número como el día, así que "09/01/2026" se
// convirtió en el 9 de ENERO: anterior al corte, descartado en silencio. 34 leads
// reales se quedaron fuera del CRM un día entero con el puente en verde.

/** El día 1 del mes SIGUIENTE al corte: la forma exacta de las filas que se perdieron. */
const MES_SIGUIENTE = (() => {
  const t = Date.UTC(+CORTE.slice(0, 4), +CORTE.slice(5, 7), 1); // mes +1, día 1
  return new Date(t).toISOString().slice(0, 10);
})();
const AL_DERECHO = latina(MES_SIGUIENTE);                                    // "01/09/2026"
const AL_REVES = `${MES_SIGUIENTE.slice(5, 7)}/${MES_SIGUIENTE.slice(8, 10)}/${MES_SIGUIENTE.slice(0, 4)}`; // "09/01/2026"
const FILA_NUEVA = 7443;   // la primera que se perdió
const MARCA = FILA_NUEVA - 1;

test("el caso existe: escrita al revés, la fecha es AMBIGUA y cruza el corte", () => {
  // Si un día mueven el corte a un mes donde las dos lecturas caen del mismo lado,
  // esto lo dice aquí en vez de dejar las pruebas de abajo midiendo otra cosa.
  const f = gs.fechaDeCelda(AL_REVES);
  assert.equal(f.ambigua, true);
  const corte = Date.UTC(+CORTE.slice(0, 4), +CORTE.slice(5, 7) - 1, +CORTE.slice(8, 10));
  assert.ok(f.ms < corte && f.msTarde >= corte,
    `las dos lecturas de "${AL_REVES}" caen del mismo lado del corte ${CORTE}`);
});

test("la fila escrita AL REVÉS (MM/DD) ya no muere en el corte: entra por posición", () => {
  const l = gs.normalizarFila(filaLanding(AL_REVES + " 10:20"), colLanding, "landing",
    FILA_NUEVA, CAB_LANDING, MARCA);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, true);      // no se sabe el día → vale el del ingreso
  assert.equal(l.fechaAmbigua, true);
  assert.match(l.nota, /Fecha ambigua/);
});

test("la misma fila AL DERECHO (DD/MM) entra igual: el puente no elige formato", () => {
  const l = gs.normalizarFila(filaLanding(AL_DERECHO + " 7:48"), colLanding, "landing",
    FILA_NUEVA, CAB_LANDING, MARCA);
  assert.equal(l.motivo, "");
});

test("lo que Sheets GUARDA manda sobre lo que dibuja: fecha nativa → sin ambigüedad", () => {
  const l = gs.normalizarFila(filaLanding(AL_REVES + " 10:20"), colLanding, "landing",
    FILA_NUEVA, CAB_LANDING, MARCA, [MES_SIGUIENTE]);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, false);
  assert.equal(l.fechaAmbigua, false);
  assert.equal(l.fecha.texto, AL_DERECHO);
});

test("la puerta de atrás sigue cerrada: una fila AMBIGUA que ya estaba es backlog", () => {
  const l = gs.normalizarFila(filaLanding(AL_REVES + " 10:20"), colLanding, "landing",
    671, CAB_LANDING, MARCA);
  assert.equal(l.motivo, gs.MOTIVO_BACKLOG);
});

test("una fila NUEVA con fecha vieja ENTRA: la posición no puede mentir, la fecha sí", () => {
  // El caso real: el origen guardó "09/01/2026" como 9 de enero. La fila es de hoy.
  const l = gs.normalizarFila(filaLanding(latina(ANTES) + " 11:43"), colLanding, "landing",
    FILA_NUEVA, CAB_LANDING, MARCA);
  assert.equal(l.motivo, "");
  assert.equal(l.fechaImposible, latina(ANTES));
  assert.equal(l.sinFecha, true);          // vale la fecha del ingreso
  assert.equal(l.fecha, null, "la fecha falsa contaminaría el desglose por mes");
  assert.match(l.nota, /FECHA IMPOSIBLE|imposible/i);
});

test("y esa misma fecha, en una fila que ya estaba, se sigue descartando en silencio", () => {
  const l = gs.normalizarFila(filaLanding(latina(ANTES) + " 11:43"), colLanding, "landing",
    671, CAB_LANDING, MARCA);
  assert.match(l.motivo, /^Anterior al corte/);
  assert.equal(gs.esDescartePorDiseno(l.motivo), true);
});

test("una fila rota no arrastra a la de al lado (el lote sigue)", () => {
  const filas = ["99/99/2026", AL_REVES + " 10:20", "", "no es una fecha"];
  const motivos = filas.map((f, i) =>
    gs.normalizarFila(filaLanding(f), colLanding, "landing", FILA_NUEVA + i, CAB_LANDING, MARCA).motivo);
  assert.deepEqual(motivos, ["", "", "", ""]); // las cuatro entran, ninguna revienta
});

// El parseo de una celda suelta no depende del corte: aquí las fechas van literales.
test("fechaDeCelda: un día > 12 desambigua solo, venga como venga", () => {
  assert.equal(gs.fechaDeCelda("09/15/2026").texto, "15/09/2026"); // no hay mes 15
  assert.equal(gs.fechaDeCelda("09/15/2026").ambigua, false);
  assert.equal(gs.fechaDeCelda("31/08/2026").texto, "31/08/2026"); // ni mes 31
  assert.equal(gs.fechaDeCelda("31/08/2026").ambigua, false);
});

test("fechaDeCelda: el mismo número dos veces no es ambiguo", () => {
  assert.equal(gs.fechaDeCelda("05/05/2026").ambigua, false);
});

test("fechaDeCelda: la basura sigue sin ser un salvoconducto", () => {
  assert.equal(gs.fechaDeCelda("99/99/2026"), null);
  assert.equal(gs.fechaDeCelda("31/02/2026"), null); // febrero no tiene 31
  assert.equal(gs.fechaDeCelda(""), null);
  assert.equal(gs.fechaDeCelda("mañana"), null);
});

test("fechaDeCelda: una fecha nativa ilegible no tapa al texto", () => {
  assert.equal(gs.fechaDeCelda("31/08/2026", "").texto, "31/08/2026");
  assert.equal(gs.fechaDeCelda("31/08/2026", "2026-99-99").texto, "31/08/2026");
});

// ── Rescate de teléfono (casos reales de REVISAR del 2026-07-27) ─────────────

test("rescate: celular trae un monto, el número real está en otra columna con 'p:'", () => {
  // Fila real: cuillrmo — celular="5ooooo", el número en la 2ª col "celular".
  const fila = ["fb", `${DESPUES}T18:47:09-05:00`, "✅_si_deseo_aperturar_mi_cuenta_de_ahorros",
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
  const fila = ["fb", `${DESPUES}T17:09:15-05:00`, "✅_si_deseo_aperturar_mi_cuenta_de_ahorros",
    "ð¡_ahorrar_en_soles", "50,000_", "no", "no grasias", "9158903210", "David",
    "p:+51913264211", "trujillo", "", ""];
  const l = gs.normalizarFila(fila, colFb, "formulario", 5950, CAB_FB);
  assert.equal(l.motivo, "");
  assert.equal(l.telefono, "+51913264211");
  assert.equal(l.telefonoRescatado, true);
});

test("el rescate NO toma un número de la columna de monto ni una fecha", () => {
  const fila = ["fb", `${DESPUES}T10:00:00-05:00`, "✅_si", "ð¡_ahorrar_en_soles",
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
  const fila = ["fb", `${DESPUES}T08:00:00-05:00`, "✅_si", "ð¡_ahorrar_en_soles",
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

// ── Marca de agua: la otra mitad del corte ───────────────────────────────────
//
// Sin fecha que juzgar, la única señal es la POSICIÓN. Estas pruebas fijan las dos
// caras de la regla y, sobre todo, los cuatro casos en que la marca deja de valer.

const SIN_FECHA = ["Liliana", "Pinche Dahua", "51918620573", "51918620573",
  "Loreto", "Pampa hermosa", "Soles", "1,000", "Si", "Si", "", "", ""];

test("lead ANTIGUO sin fecha (por encima de la marca) → backlog, no entra", () => {
  const l = gs.normalizarFila(SIN_FECHA, colLanding, "landing", 671, CAB_LANDING, 6158);
  assert.equal(l.motivo, gs.MOTIVO_BACKLOG);
  assert.equal(gs.esDescartePorDiseno(l.motivo), true); // tampoco llena REVISAR
});

test("lead NUEVO sin fecha (por debajo de la marca) → entra, como pidió Miguel", () => {
  const l = gs.normalizarFila(SIN_FECHA, colLanding, "landing", 6159, CAB_LANDING, 6158);
  assert.equal(l.motivo, "");
  assert.equal(l.sinFecha, true);
  assert.match(l.nota, /Sin fecha en el origen/);
});

test("la fila JUSTO en la marca es historia; la siguiente ya es nueva", () => {
  assert.equal(gs.normalizarFila(SIN_FECHA, colLanding, "landing", 6158, CAB_LANDING, 6158).motivo,
    gs.MOTIVO_BACKLOG);
  assert.equal(gs.normalizarFila(SIN_FECHA, colLanding, "landing", 6159, CAB_LANDING, 6158).motivo,
    "");
});

test("sin marca (0 o ausente) el guardia no actúa — no inventa una frontera", () => {
  assert.equal(gs.normalizarFila(SIN_FECHA, colLanding, "landing", 671, CAB_LANDING, 0).motivo, "");
  assert.equal(gs.normalizarFila(SIN_FECHA, colLanding, "landing", 671, CAB_LANDING).motivo, "");
});

// ── Los cuatro casos en que la marca deja de ser fiable ──────────────────────

const marcaOk = {
  sheetId: "123", nombre: "landing", ultimaFila: 6158, filas: 6158,
  cabeceras: gs.huellaCabeceras(CAB_LANDING), ancla: "hDEADBEEF",
};

test("pestaña sin inicializar → se detiene y lo dice", () => {
  const v = gs.revisarPestana(undefined, 6158, gs.huellaCabeceras(CAB_LANDING), "hDEADBEEF");
  assert.equal(v.ok, false);
  assert.match(v.motivo, /sin inicializar/i);
});

test("el origen PERDIÓ filas → se detiene (los números de fila ya no significan lo mismo)", () => {
  const v = gs.revisarPestana(marcaOk, 6000, gs.huellaCabeceras(CAB_LANDING), "hDEADBEEF");
  assert.equal(v.ok, false);
  assert.match(v.motivo, /PERDIÓ filas/);
});

test("cambiaron los encabezados → se detiene (el mapeo pudo moverse)", () => {
  const otras = CAB_LANDING.slice();
  otras[7] = "¿Cuánto capital deseas colocar?";
  const v = gs.revisarPestana(marcaOk, 6158, gs.huellaCabeceras(otras), "hDEADBEEF");
  assert.equal(v.ok, false);
  assert.match(v.motivo, /encabezados/);
});

test("las filas ancladas cambiaron → se detiene (se ordenó o se insertó en medio)", () => {
  const v = gs.revisarPestana(marcaOk, 6158, gs.huellaCabeceras(CAB_LANDING), "hOTRACOSA");
  assert.equal(v.ok, false);
  assert.match(v.motivo, /ordenó o le insertaron/);
});

test("todo en su sitio → sigue adelante", () => {
  const v = gs.revisarPestana(marcaOk, 6200, gs.huellaCabeceras(CAB_LANDING), "hDEADBEEF");
  assert.equal(v.ok, true);
  assert.equal(v.motivo, "");
});

// ── Las huellas que sostienen esas comprobaciones ────────────────────────────

test("la huella NUNCA empieza por dígito (si no, Sheets la lee como número y falla siempre)", () => {
  for (const s of ["", "a", "landing", "0", "12345678", "x".repeat(500)]) {
    assert.match(gs.huellaTexto(s), /^h[0-9a-f]{8}$/, JSON.stringify(s));
  }
});

test("huella de encabezados: tolera espacios y mayúsculas, cambia con un renombre real", () => {
  const conRuido = CAB_LANDING.map((h) => "  " + h.toUpperCase() + " ");
  assert.equal(gs.huellaCabeceras(conRuido), gs.huellaCabeceras(CAB_LANDING));
  const renombrada = CAB_LANDING.slice();
  renombrada[2] = "Número de contacto";
  assert.notEqual(gs.huellaCabeceras(renombrada), gs.huellaCabeceras(CAB_LANDING));
});

test("ancla: mira SOLO el final, y distingue dónde cae el corte entre celdas", () => {
  const base = [CAB_LANDING, ["a"], ["b"], ["c"], ["d"], ["e"]];
  const ancla = gs.anclaDeFilas(base, 6, 3); // filas 4,5,6
  // Cambiar una fila de ARRIBA no la mueve: el ancla vigila la frontera, no el pasado.
  const arriba = base.map((f, i) => (i === 1 ? ["OTRA"] : f));
  assert.equal(gs.anclaDeFilas(arriba, 6, 3), ancla);
  // Cambiar una fila anclada sí la mueve.
  const abajo = base.map((f, i) => (i === 5 ? ["OTRA"] : f));
  assert.notEqual(gs.anclaDeFilas(abajo, 6, 3), ancla);
  // Y el separador hace su trabajo: ["ab","c"] no puede dar lo mismo que ["a","bc"].
  assert.notEqual(
    gs.anclaDeFilas([CAB_LANDING, ["ab", "c"]], 2, 1),
    gs.anclaDeFilas([CAB_LANDING, ["a", "bc"]], 2, 1)
  );
});

test("una fecha IMPOSIBLE no es un salvoconducto", () => {
  // `Date.UTC` no valida: 99/99/2026 se normaliza a una fecha FUTURA, con lo que
  // supera el corte y, al "tener fecha", tampoco lo frena la marca de agua por
  // posición. Una fila de basura se convertía en lead nuevo. Lo encontró Codex.
  const conFecha = (f) => {
    const fila = ["Ana", "Perez", "918000001", "", "Lima", "Surco",
      "Soles", "1,000", "No", "Si", f, "", ""];
    return gs.normalizarFila(fila, colLanding, "landing", 1000, CAB_LANDING, 6158);
  };
  for (const basura of ["99/99/2026", "31/02/2026", "00/00/2026", "45/13/2025"]) {
    const l = conFecha(basura);
    assert.equal(l.sinFecha, true, basura + " se leyó como fecha válida");
    // Sin fecha y por debajo de la frontera: manda la posición, que es lo correcto.
    assert.equal(l.motivo, gs.MOTIVO_BACKLOG, basura);
  }
  // Y una fecha que SÍ existe sigue funcionando igual.
  const buena = conFecha(latina(DESPUES));
  assert.equal(buena.sinFecha, false);
  assert.equal(buena.motivo, "");
});

test("esDescartePorDiseno: solo corte y backlog; lo accionable NO", () => {
  assert.equal(gs.esDescartePorDiseno(gs.MOTIVO_CORTE + " (2026-08-17)"), true);
  assert.equal(gs.esDescartePorDiseno(gs.MOTIVO_BACKLOG), true);
  for (const m of ["Pide PRÉSTAMO — no es lead de ahorro", "Sin nombre",
    "Sin teléfono válido (se buscó en toda la fila)", "Teléfono ya presente en la hoja"]) {
    assert.equal(gs.esDescartePorDiseno(m), false, m);
  }
});

test("fusionar: lo nuevo pisa, lo que no se tocó sobrevive", () => {
  const r = gs.fusionar({ a: 1, b: 2 }, { b: 3, c: 4 });
  assert.deepEqual(r, { a: 1, b: 3, c: 4 });
});

// ── Fase 4: el calendario y el pre-chequeo, sin Hojas de por medio ───────────
//
// Las fechas ancla son reales y verificadas contra el calendario del negocio: el
// 15 y el 16 de agosto de 2026 cayeron en sábado y domingo (por eso el arranque se
// fijó en el lunes 17). Si `momentoDe` se equivocara de día de la semana, el puente
// correría los domingos o dejaría de correr los lunes, en silencio.

const DOMINGO = "2026-08-16 09:20";
const LUNES = "2026-08-17 09:20";
const SABADO = "2026-08-15 09:20";

test("momentoDe: parte la hora de Lima y acierta el día de la semana", () => {
  const lunes = gs.momentoDe(LUNES);
  assert.equal(lunes.fecha, "2026-08-17");
  assert.equal(lunes.hora, 9);
  assert.equal(lunes.minuto, 20);
  assert.equal(lunes.dia, 1, "el 17 de agosto de 2026 es LUNES");
  assert.equal(lunes.texto, "17/08/2026 09:20");
  assert.equal(gs.momentoDe(DOMINGO).dia, 0, "el 16 de agosto de 2026 es DOMINGO");
  assert.equal(gs.momentoDe(SABADO).dia, 6, "el 15 de agosto de 2026 es SÁBADO");
});

test("momentoDe: una hora ilegible LANZA, no devuelve un día plausible", () => {
  // Devolver algo razonable ante basura es cómo se acaba corriendo el domingo.
  for (const basura of ["", "ayer", "17/08/2026 09:20", null]) {
    assert.throws(() => gs.momentoDe(basura), /hora de Lima/, JSON.stringify(basura));
  }
});

test("dentroDeVentana: domingo NUNCA, y la ventana es de 7 a 22 h", () => {
  const en = (cuando) => gs.dentroDeVentana(gs.momentoDe(cuando));
  assert.equal(en("2026-08-16 09:20").ok, false, "corrió un domingo");
  assert.match(en("2026-08-16 09:20").motivo, /domingo/);
  assert.equal(en("2026-08-16 23:00").ok, false);

  assert.equal(en("2026-08-17 06:59").ok, false, "corrió antes de abrir la ventana");
  assert.equal(en("2026-08-17 07:00").ok, true);
  assert.equal(en("2026-08-17 21:45").ok, true, "la última corrida del día debe entrar");
  assert.equal(en("2026-08-17 22:00").ok, false, "corrió después de cerrar la ventana");
  assert.equal(en("2026-08-15 10:00").ok, true, "el sábado SÍ se trabaja");
  assert.equal(gs.dentroDeVentana(null).ok, false);
});

test("diasEntre: cuenta días de calendario y se niega con basura", () => {
  assert.equal(gs.diasEntre("2026-08-17", "2026-08-17"), 0);
  assert.equal(gs.diasEntre("2026-07-24", "2026-08-16"), 23); // el origen seco, de verdad
  assert.equal(gs.diasEntre("2026-08-17", "2026-08-16"), -1);
  assert.equal(gs.diasEntre("", "2026-08-17"), null);
  assert.equal(gs.diasEntre("hoy", "2026-08-17"), null);
});

// ── El pre-chequeo: cuándo vale la pena pagar la lectura de 12.000 filas ──────

const RELOJ = () => gs.momentoDe(LUNES);
/** Una pestaña ya mirada hasta el final, con su marca al día. */
const marcaAlDia = (filas) => ({ ultimaFila: filas, filas: filas, cabeceras: "h1", ancla: "h2" });
/** El estado de quien ya hizo su lectura completa HOY: el suelo no fuerza nada. */
const sueloPagado = { pasadaCompletaEl: "2026-08-17" };

test("pre-chequeo: si nada cambió y hoy ya se leyó entero, NO se lee nada", () => {
  const d = gs.decidirPasada(
    [{ id: "111", nombre: "landing", filas: 6158 }],
    { 111: marcaAlDia(6158) },
    sueloPagado,
    RELOJ()
  );
  assert.equal(d.mirar, false, "iba a descargar 12.000 filas para nada");
  assert.equal(d.forzada, false);
  assert.deepEqual(d.motivos, []);
});

test("pre-chequeo: el origen CRECIÓ → hay que leer", () => {
  const d = gs.decidirPasada(
    [{ id: "111", nombre: "landing", filas: 6160 }],
    { 111: marcaAlDia(6158) },
    sueloPagado,
    RELOJ()
  );
  assert.equal(d.mirar, true);
  assert.match(d.motivos[0], /creció/);
});

test("pre-chequeo: filas que DESAPARECEN no se ignoran, se van a mirar", () => {
  // Es el caso que detiene la pestaña entera. Si el pre-chequeo lo tapara, la
  // incidencia no se descubriría nunca y nadie recibiría la alerta.
  const d = gs.decidirPasada(
    [{ id: "111", nombre: "landing", filas: 6000 }],
    { 111: marcaAlDia(6158) },
    sueloPagado,
    RELOJ()
  );
  assert.equal(d.mirar, true);
  assert.match(d.motivos[0], /PERDIÓ filas/);
});

test("pre-chequeo: una pestaña SIN marca manda leer (para que la pasada la detenga)", () => {
  const d = gs.decidirPasada(
    [{ id: "999", nombre: "tiktok", filas: 12 }],
    { 111: marcaAlDia(6158) },
    sueloPagado,
    RELOJ()
  );
  assert.equal(d.mirar, true);
  assert.match(d.motivos[0], /sin marca de agua/);
});

test("pre-chequeo: si el TOPE dejó trabajo a medias, se sigue aunque no crezca", () => {
  const d = gs.decidirPasada(
    [{ id: "111", nombre: "landing", filas: 6158 }],
    { 111: { ultimaFila: 5000, filas: 6158 } }, // la pasada anterior se cortó en la 5000
    sueloPagado,
    RELOJ()
  );
  assert.equal(d.mirar, true);
  assert.match(d.motivos[0], /trabajo pendiente/);
});

test("pre-chequeo: el SUELO DIARIO obliga a una lectura completa al día", () => {
  // Sin este suelo, borrar una fila e insertar otra en el mismo cuarto de hora deja
  // el contador igual y el lead nuevo no entraría jamás.
  const d = gs.decidirPasada(
    [{ id: "111", nombre: "landing", filas: 6158 }],
    { 111: marcaAlDia(6158) },
    { pasadaCompletaEl: "2026-08-16" }, // la última completa fue ayer
    RELOJ()
  );
  assert.equal(d.mirar, true);
  assert.equal(d.forzada, true);
  assert.match(d.motivos[0], /suelo diario/);
});

test("pre-chequeo: sin diario de estado, se lee (equivocarse hacia MIRAR)", () => {
  for (const estado of [null, {}, { pasadaCompletaEl: "" }]) {
    const d = gs.decidirPasada(
      [{ id: "111", nombre: "landing", filas: 6158 }],
      { 111: marcaAlDia(6158) },
      estado,
      RELOJ()
    );
    assert.equal(d.mirar, true, JSON.stringify(estado));
    assert.equal(d.forzada, true);
  }
});

// ── El panel ─────────────────────────────────────────────────────────────────

const PANEL_BASE = {
  reloj: gs.momentoDe(LUNES),
  ventana: { ok: true, motivo: "" },
  puente: 1,
  conector: 1,
  marcas: { 111: { ultimaFila: 6158, actualizado: "17/08/2026 07:00" } },
  estado: {
    ultimaCorrida: "17/08/2026 09:15",
    ultimoVeredicto: "sin novedad en el origen",
    ultimaPasadaCompleta: "17/08/2026 07:00",
    traidosUltimaPasada: 3,
    crecioEl: "2026-07-24",
  },
  pestanas: [{ id: "111", nombre: "landing", filas: 6158 }],
  hoja: { total: 279, pendientes: 0, importados: 279, rechazados: 0, errores: 0 },
};

test("el panel dice lo que hay que saber en cinco segundos", () => {
  const t = gs.textoDelPanel(PANEL_BASE);
  assert.match(t, /Puente: ENCENDIDO/);
  assert.match(t, /Conector al CRM: ENCENDIDO/);
  assert.match(t, /Ahora mismo: toca correr/);
  assert.match(t, /landing: 6158 filas · frontera en la 6158/);
  assert.match(t, /24 días/, "no dice hace cuánto que el origen no recibe nada");
  assert.match(t, /279 filas con datos · 0 esperando subir/);
  assert.match(t, /✓ Sin avisos activos/, "el silencio no se distingue de un panel roto");
});

test("los AVISOS van arriba del todo, con desde cuándo duran", () => {
  const t = gs.textoDelPanel({
    ...PANEL_BASE,
    estado: {
      ...PANEL_BASE.estado,
      avisos: {
        "pestana-detenida": {
          desde: "17/08/2026 09:15",
          ultimo: "17/08/2026 12:00",
          titulo: "1 pestaña(s) detenida(s)",
          detalle: "El puente detuvo estas pestañas...\nlanding: el origen PERDIÓ filas",
        },
      },
    },
  });
  assert.match(t, /AVISOS ACTIVOS \(1\)/);
  assert.ok(t.indexOf("AVISOS ACTIVOS") < t.indexOf("MÁQUINA"), "los avisos no van los primeros");
  assert.match(t, /desde 17\/08\/2026 09:15/);
});

test("el panel canta lo APAGADO y lo que está sin frontera", () => {
  const t = gs.textoDelPanel({
    ...PANEL_BASE,
    puente: 0,
    conector: 0,
    marcas: {},
    ventana: { ok: false, motivo: "es domingo y el puente no corre los domingos" },
    estado: { ultimoError: "17/08/2026 09:15 — cuota agotada", incidencias: ["landing: el origen PERDIÓ filas"] },
  });
  assert.match(t, /Puente: APAGADO/);
  assert.match(t, /Conector al CRM: APAGADO/);
  assert.match(t, /no toca \(es domingo/);
  assert.match(t, /SIN marca de agua/);
  assert.match(t, /Último error: .*cuota agotada/);
  assert.match(t, /PESTAÑAS DETENIDAS/);
});

test("el panel avisa si hay MÁS de un disparador del puente", () => {
  // Dos disparadores son dos corridas simultáneas cada cuarto de hora: el candado
  // las salva, pero es cuota tirada y hay que verlo.
  assert.match(gs.textoDelPanel({ ...PANEL_BASE, puente: 3 }), /3 disparadores donde debería haber 1/);
});

// ── Fase 2: reglas de forma, comprobadas sobre el CÓDIGO ─────────────────────
//
// Estas reglas no se pueden ejercitar sin un simulador de Hojas de Google (eso es
// la fase siguiente), pero sí se pueden EXIGIR estructuralmente. Se hace sobre el
// código con los comentarios QUITADOS: varios de esos comentarios nombran justo lo
// que estas pruebas prohíben ("Nunca getSheets()[0]"), así que una comprobación
// ingenua sobre el texto crudo fallaría por leer la prosa. Misma lección que el
// oráculo del cierre de mes.

const conector = readFileSync(join(aqui, "hoja-leads-apps-script.gs"), "utf8");
const sinComentarios = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
const CODIGO_PUENTE = sinComentarios(fuente);
const CODIGO_CONECTOR = sinComentarios(conector);

test("la pestaña de leads se resuelve por NOMBRE, nunca por posición", () => {
  for (const [donde, codigo] of [["puente", CODIGO_PUENTE], ["conector", CODIGO_CONECTOR]]) {
    assert.ok(!/getSheets\(\)\s*\[\s*0\s*\]/.test(codigo),
      `${donde}: sigue resolviendo la hoja por getSheets()[0]`);
    assert.ok(!/getIndex\(\)\s*!==?\s*1/.test(codigo),
      `${donde}: sigue identificando la pestaña por su índice`);
  }
  assert.match(CODIGO_CONECTOR, /getSheetByName\(HOJA_LEADS\)/);
});

test("la capacidad de la hoja se calcula, no se fija en un número", () => {
  assert.ok(!/FILAS_CONFIG/.test(CODIGO_CONECTOR),
    "el techo fijo de filas (FILAS_CONFIG) sigue vivo");
  assert.match(CODIGO_CONECTOR, /function asegurarCapacidadLeads/);
  assert.match(CODIGO_CONECTOR, /insertRowsAfter/);
  // Y lo nuevo se prepara: una fila insertada sin formato es donde Sheets vuelve a
  // reinterpretar el DNI como número.
  assert.match(CODIGO_CONECTOR, /prepararTramo\(hoja,\s*antes \+ 1/);
});

test("escribirLeads asegura capacidad ANTES de escribir", () => {
  const cuerpo = CODIGO_PUENTE.slice(CODIGO_PUENTE.indexOf("function escribirLeads"));
  const iAsegura = cuerpo.indexOf("asegurarCapacidadLeads");
  const iEscribe = cuerpo.indexOf("setValues");
  assert.ok(iAsegura > 0, "escribirLeads no asegura capacidad");
  assert.ok(iAsegura < iEscribe, "asegura la capacidad DESPUÉS de escribir: no sirve");
});

test("preparar la hoja NO enciende nada", () => {
  const i = CODIGO_CONECTOR.indexOf("function prepararHoja");
  const fin = CODIGO_CONECTOR.indexOf("\nfunction ", i + 1);
  const cuerpo = CODIGO_CONECTOR.slice(i, fin);
  assert.ok(!/newTrigger/.test(cuerpo), "prepararHoja crea un disparador");
  assert.ok(!/importarLeads\(\)/.test(cuerpo), "prepararHoja lanza una importación");
});

test("el secreto se lee DENTRO de la función, no al cargar el proyecto", () => {
  // Un PropertiesService en el nivel superior corre en CADA ejecución del proyecto,
  // incluidos los disparadores simples que van sin autorización (el menú del puente,
  // onEdit), y además congela el secreto al cargar: rotarlo obligaría a reiniciar.
  //
  // ⚠️ La primera versión de esta prueba miraba solo el texto ANTERIOR a la primera
  // función, y un mutante que declaraba la constante más abajo la sobrevivía: las
  // declaraciones de nivel superior pueden ir intercaladas entre funciones. Se
  // comprueba por indentación (nivel superior = columna 0) y por ubicación única.
  assert.ok(!/^(?:const|let|var)\s+[^\n]*PropertiesService/m.test(CODIGO_CONECTOR),
    "hay una declaración de nivel superior que lee PropertiesService");

  const usos = [...CODIGO_CONECTOR.matchAll(/PropertiesService/g)];
  assert.equal(usos.length, 1, "PropertiesService debería usarse en un solo sitio");
  const i = CODIGO_CONECTOR.indexOf("function secretoDeImportacion");
  const fin = CODIGO_CONECTOR.indexOf("\nfunction ", i + 1);
  assert.ok(i >= 0 && usos[0].index > i && usos[0].index < fin,
    "el único uso de PropertiesService no está dentro de secretoDeImportacion");
});

test("los scripts NO piden permisos nuevos: nada de correo", () => {
  // Decisión de Miguel (2026-08-16): sin envío de correo. No es solo una función de
  // menos — `MailApp`/`GmailApp` obligan a re-autorizar el proyecto al pegarlo, y los
  // disparadores ya instalados fallan con "Authorization is required" hasta que
  // alguien ejecuta algo a mano. Los avisos van al panel y al abrir la hoja.
  for (const [donde, codigo] of [["puente", CODIGO_PUENTE], ["conector", CODIGO_CONECTOR]]) {
    assert.ok(!/\b(MailApp|GmailApp)\b/.test(codigo),
      `${donde}: volvió a usar el servicio de correo (permiso nuevo al pegar)`);
  }
});

test("el origen del Drive sigue siendo SOLO LECTURA", () => {
  // La regla más dura del proyecto: el documento es de la empresa y no se toca.
  //
  // ⚠️ La versión anterior solo buscaba llamadas que empezaran por `origen.` — y el
  // código recorre las pestañas en una variable llamada `pestana`, así que un
  // `pestana.getRange(...).setValue(...)` habría pasado la prueba tan campante.
  // Lo encontró Codex el 2026-08-16. Ahora se comprueba al revés: se localiza la
  // función que abre el origen y se prohíbe TODA escritura dentro de ella.
  const escrituras = /\.(setValue|setValues|insertSheet|setName|deleteRow|appendRow|clearContent|insertRowsAfter|setNumberFormat|setDataValidation|protect|hideSheet)\s*\(/;

  for (const nombre of ["procesarNucleo", "inicializarMarcas", "medirOrigen"]) {
    const i = CODIGO_PUENTE.indexOf("function " + nombre);
    assert.ok(i >= 0, "no encuentro " + nombre);
    const fin = CODIGO_PUENTE.indexOf("\nfunction ", i + 1);
    const cuerpo = CODIGO_PUENTE.slice(i, fin < 0 ? undefined : fin);
    // Dentro de esas funciones, toda variable que salga de `origen` es intocable.
    const lineas = cuerpo.split("\n");
    lineas.forEach((linea, n) => {
      if (!/\b(pestana|origen)\b/.test(linea)) return;
      assert.ok(!escrituras.test(linea),
        `${nombre}, línea ${n + 1}: escritura sobre una pestaña del origen → ${linea.trim()}`);
    });
  }
  assert.ok(!/\borigen\.(setValue|setValues|insertSheet|setName|deleteRow|appendRow|clear)/.test(CODIGO_PUENTE),
    "hay una escritura directa sobre el libro de origen");
});


// ── Fase 0: diagnóstico de segundos números ─────────────────────────────────
// Mide lo que el ORIGEN da, no lo que el puente deja pasar. Su valor entero está
// en distinguir "no hay segundo número" de "hay uno y lo estamos tirando": si esa
// distinción se borra, el diagnóstico diría que todo está bien y la Fase 2 se
// cancelaría por un dato falso.

const clasificar = (fila, col, cabeceras) => {
  const cuenta = gs.nuevoConteoSegundos();
  gs.clasificarSegundoNumero(fila, col, gs.celdasTelefonicas(cabeceras, col), cuenta);
  return cuenta;
};

test("la regla del teléfono del puente es la MISMA que la del CRM", () => {
  const e = (v) => (gs.reconocerTelefono(v) || {}).e164 || null;
  // Celular peruano
  assert.equal(e("987654321"), "+51987654321");
  assert.equal(e("964,262,777"), "+51964262777");   // Sheets lo trató como número
  assert.equal(e("p:+51910585900"), "+51910585900"); // fila real del origen
  // Fijos: SOLO marcados. Ocho dígitos pelados son un DNI, no un teléfono.
  assert.equal(e("014457890"), "+5114457890");
  assert.equal(e("084 234567"), "+5184234567");
  assert.equal(e("+51 1 445 7890"), "+5114457890");
  assert.equal(e("14457890"), null, "ocho dígitos pelados = DNI, no teléfono");
  assert.equal(e("46736918"), null, "un DNI no puede parecer un teléfono");
  // El mundo
  assert.equal(e("+1 415 555 2671"), "+14155552671");
  assert.equal(e("+34612345678"), "+34612345678");
  assert.equal(e("0034612345678"), "+34612345678");
  // Lo que sigue sin ser teléfono
  assert.equal(e("5ooooo"), null);
  assert.equal(e("rosa@correo.com"), null);
  assert.equal(e("+51123456789"), null, "dice ser Perú sin forma peruana");
  assert.equal(e("9158903210"), null, "diez dígitos: celular peruano malo");
  // Qué responde WhatsApp y qué no
  assert.equal(gs.reconocerTelefono("987654321").movil, true);
  assert.equal(gs.reconocerTelefono("014457890").movil, false);
  assert.equal(gs.telefonoContacto("014457890"), "+5114457890");
  assert.equal(gs.telefonoPeru("014457890"), "", "un fijo no sirve de identidad por sí solo");
});

test("un lead con SOLO un fijo ya no se pierde: entra con el fijo de principal", () => {
  const fila = ["Luis", "Vega", "014457890", "",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 900, CAB_LANDING);
  assert.equal(l.telefono, "+5114457890");
  assert.equal(l.motivo, "", "antes moría con «Sin teléfono válido»");
  assert.match(l.nota, /FIJO — no responde WhatsApp/);
});

test("un celular en la fila gana la identidad aunque el fijo venga primero", () => {
  const fila = ["Ana", "Ruiz", "014457890", "987654321",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 901, CAB_LANDING);
  assert.equal(l.telefono, "+51987654321", "WhatsApp es como se trabaja");
  assert.equal(l.telefonoAlternativo, "+5114457890");
  assert.doesNotMatch(l.nota, /FIJO/);
});

test("lo ilegible viaja CRUDO en vez de morir en el origen", () => {
  // WhatsApp con un número a medias: hasta hoy se tiraba aquí mismo.
  const fila = ["Ana", "Ruiz", "987654321", "99988 7",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 910, CAB_LANDING);
  assert.equal(l.telefono, "+51987654321");
  assert.equal(l.telefonoAlternativo, "");
  assert.equal(l.telefonoAlternativoCrudo, "99988 7");
});

test("un correo en la columna de WhatsApp NO se muestra como teléfono", () => {
  const fila = ["Ana", "Ruiz", "987654321", "ana@correo.com",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 911, CAB_LANDING);
  assert.equal(l.telefonoAlternativoCrudo, "", "un correo mal puesto no es un número perdido");
});

test("el crudo NO se pesca de columnas que no son de teléfono", () => {
  // El distrito, el nombre o una respuesta abierta jamás pueden acabar
  // presentados como «segundo número sin validar»: un dato equivocado
  // disfrazado de teléfono es peor que ninguno.
  const fila = ["Ana", "Ruiz", "987654321", "",
    "Lima", "Surquillo 1234", "Soles", "1,000", "No", "Si", "", "nota larga", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 912, CAB_LANDING);
  assert.equal(l.telefonoAlternativoCrudo, "");
});

test("si hay un segundo número BUENO, no se guarda crudo (excluyentes)", () => {
  const fila = ["Ana", "Ruiz", "987654321", "918620573",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 913, CAB_LANDING);
  assert.equal(l.telefonoAlternativo, "+51918620573");
  assert.equal(l.telefonoAlternativoCrudo, "");
});

test("un lead extranjero entra y conserva sus dos números", () => {
  const fila = ["Rosa", "Diaz", "+34612345678", "+34911223344",
    "Madrid", "", "Soles", "50,000", "No", "Si", "", "", ""];
  const l = gs.normalizarFila(fila, colLanding, "landing", 902, CAB_LANDING);
  assert.equal(l.telefono, "+34612345678");
  assert.equal(l.telefonoAlternativo, "+34911223344");
});

test("diagnóstico: dos celulares distintos → cuenta como el que YA llega", () => {
  const fila = ["Rosa", "Diaz", "918620573", "987654321",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const c = clasificar(fila, colLanding, CAB_LANDING);
  assert.equal(c.celular, 1);
  assert.equal(c.fijo, 0);
  assert.equal(c.sinSegundo, 0);
});

test("diagnóstico: WhatsApp que repite el celular NO se cuenta como pérdida", () => {
  const fila = ["Carmen", "Joya", "51918376855", "51918376855",
    "Lima", "Surquillo", "Soles", "50,000", "Si", "Si", "", "", ""];
  const c = clasificar(fila, colLanding, CAB_LANDING);
  assert.equal(c.repetido, 1);
  assert.equal(c.celular, 0);
  assert.equal(c.fijo, 0);
});

test("diagnóstico: un FIJO como segundo número se cuenta como pérdida", () => {
  const fila = ["Luis", "Vega", "918620573", "014457890",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const c = clasificar(fila, colLanding, CAB_LANDING);
  assert.equal(c.fijo, 1, "el fijo es el dato que la Fase 2 viene a rescatar");
  assert.equal(c.celular, 0);
});

test("diagnóstico: un celular gana a un fijo cuando la fila trae los dos", () => {
  const cab = ["Nombre", "Celular", "Telefono fijo", "WhatsApp"];
  const col = gs.ubicarColumnas(cab);
  const c = clasificar(["Ana", "918620573", "014457890", "987654321"], col, cab);
  assert.equal(c.celular, 1, "otro celular vale más que un fijo");
  assert.equal(c.fijo, 0);
});

test("diagnóstico: un correo en la columna de teléfono no infla lo perdido", () => {
  const fila = ["Ana", "Ruiz", "918620573", "ana@correo.com",
    "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const c = clasificar(fila, colLanding, CAB_LANDING);
  assert.equal(c.ilegible, 0, "un correo mal puesto no es un número que perdimos");
  assert.equal(c.sinSegundo, 1);
});

test("diagnóstico: una fila sin ningún teléfono no cuenta como fila medida", () => {
  const fila = ["Ana", "Ruiz", "", "", "Lima", "Surco", "Soles", "1,000", "No", "Si", "", "", ""];
  const c = clasificar(fila, colLanding, CAB_LANDING);
  assert.equal(c.sinTelefono, 1);
  assert.equal(c.filas, 0, "el porcentaje se calcula sobre filas CON teléfono");
});

test("celdasTelefonicas encuentra la 2ª columna 'celular' que el mapeo no asigna", () => {
  // El caso real de la pestaña de Facebook: dos columnas se llaman "celular" y
  // ubicarColumnas() solo puede quedarse con la primera.
  const indices = gs.celdasTelefonicas(CAB_FB, colFb);
  const nombres = indices.map((i) => CAB_FB[i]);
  assert.ok(nombres.filter((n) => /celular/i.test(n)).length >= 2,
    "las DOS columnas 'celular' tienen que entrar en la medición: " + nombres.join(" | "));
  assert.equal(indices.indexOf(colFb.dni), -1, "el DNI no es un teléfono");
  assert.equal(indices.indexOf(colFb.monto), -1, "el monto no es un teléfono");
});

test("el informe dice el TECHO REAL, que es lo que decide la Fase 2", () => {
  const t = gs.nuevoConteoSegundos();
  t.filas = 100; t.celular = 10; t.fijo = 25; t.ilegible = 5;
  t.repetido = 40; t.sinSegundo = 20;
  const texto = gs.informeSegundosNumeros([], t);
  assert.match(texto, /TECHO REAL: 35 de 100/,
    "techo = los que ya llegan MÁS los que se están perdiendo");
  assert.match(texto, /HOY YA LLEGA/);
  assert.match(texto, /SE PIERDE/);
});

// ── Retroceder la marca de agua (el rescate) ────────────────────────────────
//
// La marca avanza aunque la pasada no acepte nada: es "hasta aquí he mirado". Cuando
// el puente descarta mal, arreglar el descarte no basta —la frontera ya pasó por
// encima—, y hay que desandarla. Es la única operación que mueve la frontera hacia
// atrás, así que es también la única que puede volver a abrir la puerta al backlog.

const filaOrigen = (i) => ["Persona" + i, "Apellido" + i, String(918000000 + i), "",
  "Lima", "Surquillo", "Soles", "1,000", "No", "Si", "", ""];
const DATOS = [CAB_LANDING].concat(
  Array.from({ length: 60 }, (_, i) => filaOrigen(i + 1))); // cabecera + 60 filas
const marcaEn = (fila) => ({
  sheetId: "111", nombre: "landing", ultimaFila: fila, filas: DATOS.length,
  cabeceras: gs.huellaCabeceras(DATOS[0]), ancla: gs.anclaDeFilas(DATOS, fila),
  actualizado: "01/09/2026 09:00",
});

test("retroceder recalcula el ancla EN LA FILA NUEVA (si no, la pestaña se detendría)", () => {
  const nueva = gs.marcaRetrocedida(marcaEn(61), DATOS, 50, "landing");

  assert.equal(nueva.ultimaFila, 50);
  assert.equal(nueva.filas, DATOS.length, "perder el total haría creer que el origen encogió");
  assert.equal(nueva.ancla, gs.anclaDeFilas(DATOS, 50));
  assert.notEqual(nueva.ancla, marcaEn(61).ancla);
  // Lo que de verdad importa: la marca resultante convence a las cuatro
  // comprobaciones de la próxima pasada.
  const veredicto = gs.revisarPestana(nueva, DATOS.length,
    gs.huellaCabeceras(DATOS[0]), gs.anclaDeFilas(DATOS, nueva.ultimaFila));
  assert.equal(veredicto.ok, true, veredicto.motivo);
});

test("retroceder NO adelanta: la frontera solo se mueve hacia atrás", () => {
  assert.throws(() => gs.marcaRetrocedida(marcaEn(50), DATOS, 55, "landing"), /solo RETROCEDE/);
  assert.throws(() => gs.marcaRetrocedida(marcaEn(50), DATOS, 50, "landing"), /solo RETROCEDE/);
});

test("retroceder NO puede reprocesar el origen entero", () => {
  assert.throws(() => gs.marcaRetrocedida(marcaEn(61), DATOS, 1, "landing"), /encabezados/);
  const lejos = { ...marcaEn(61), ultimaFila: gs.TOPE_RETROCESO + 62 };
  assert.throws(() => gs.marcaRetrocedida(lejos, DATOS, 60, "landing"), /demasiado grande/);
});

test("retroceder rechaza lo que no es una fila", () => {
  assert.throws(() => gs.marcaRetrocedida(marcaEn(61), DATOS, "hola", "landing"), /no es un número/);
  assert.throws(() => gs.marcaRetrocedida(marcaEn(61), DATOS, "", "landing"), /no es un número/);
  assert.throws(() => gs.marcaRetrocedida(marcaEn(61), DATOS, 2.5, "landing"), /no es un número/);
  assert.throws(() => gs.marcaRetrocedida(marcaEn(61), DATOS, -3, "landing"), /no es un número/);
  assert.throws(() => gs.marcaRetrocedida(null, DATOS, 50, "landing"), /no tiene marca/);
});
