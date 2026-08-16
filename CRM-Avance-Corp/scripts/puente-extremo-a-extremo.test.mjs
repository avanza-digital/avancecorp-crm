/**
 * El puente y el conector, ejecutados DE VERDAD sobre Hojas de Google simuladas.
 * ─────────────────────────────────────────────────────────────────────────────
 * `puente-drive-origen.test.mjs` prueba las funciones puras. Esto prueba lo otro: lo
 * que solo se rompe cuando hay hojas de por medio — la marca de agua leída y escrita,
 * dos corridas pisándose, una escritura que falla a mitad, la hoja quedándose sin
 * filas, una pestaña renombrada. Es donde vivían todos los sustos de julio.
 *
 * Los dos .gs se cargan JUNTOS y en un mismo ámbito, que es como los ejecuta Apps
 * Script: un solo proyecto, un solo espacio de nombres. Si dos constantes chocaran,
 * esto reventaría igual que reventaría la hoja de Miguel.
 *
 * Correr: npm run test:puente:e2e
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { crearEntorno, Hoja, Libro } from "./apps-script-simulado.mjs";

const aqui = dirname(fileURLToPath(import.meta.url));
const CONECTOR = readFileSync(join(aqui, "hoja-leads-apps-script.gs"), "utf8");
const PUENTE = readFileSync(join(aqui, "puente-drive-origen.gs"), "utf8");

const EXPUESTO =
  "return { procesar, inicializarMarcas, leerMarcas, traerLeadsDelOrigen," +
  " vistaPreviaOrigen, prepararHoja, activarConector, apagarConector, importarLeads, configurar," +
  " TOPE_POR_PASADA, FECHA_CORTE, HOJA_MARCAS, HOJA_HUELLAS, HOJA_LEADS," +
  " HOJA_REVISAR, MOTIVO_BACKLOG };";

function cargar(entorno) {
  const g = entorno.globales;
  const fabrica = new Function(
    "SpreadsheetApp", "LockService", "Utilities", "Session",
    "ScriptApp", "PropertiesService", "UrlFetchApp", "console",
    CONECTOR + "\n" + PUENTE + "\n" + EXPUESTO
  );
  return fabrica(
    g.SpreadsheetApp, g.LockService, g.Utilities, g.Session,
    g.ScriptApp, g.PropertiesService, g.UrlFetchApp, g.console
  );
}

// ── Fixtures: encabezados reales del origen (leídos el 2026-07-27) ───────────

const CAB_LANDING = [
  "nombre", "Apellidos", "Celular", "WhatsApp", "Departamento", "Distrito",
  "¿Deseas depositar en plazo fijo en soles o dólares?",
  "¿Cuánto dinero deseas depositar?", "¿Ya eres socio de nuestra cooperativa?",
  "Estoy de acuerdo en recibir información comercial de la COOPAC MÁSCAPITAL",
  "Fecha de Registro",
];
const CAB_FB = [
  "red social", "fecha", "¿deseas aperturar tus ahorros a plazofijo?",
  "¿deseas ahorrar en soles o dolares con una taza de hasta el 15%?",
  "¿qué monto deseas ahorrar?", "¿eres socio de la cooperativa?",
  "Tienes alguna pregunta con respecto a nuestra campaña de ahorro a plazofijo?",
  "celular", "nombre", "celular", "ciudad",
];

/** Fila de landing con teléfono único. `fecha` vacía = sin fecha en el origen. */
const filaLanding = (i, fecha = "") => [
  "Persona" + i, "Apellido" + i, String(918000000 + i), "", "Lima", "Miraflores",
  "Soles", "1,000", "Si", "Si", fecha,
];
const filaFb = (i, fecha = "") => [
  "fb", fecha, "si", "ahorrar en soles", "5,000", "no", "",
  String(940000000 + i), "Persona FB " + i, "", "Lima",
];

const CAB_LEADS = [
  "Nombre completo *", "Teléfono *", "Capital estimado *", "Moneda *",
  "Canal de origen *", "Correo", "DNI", "Género", "Fecha de nacimiento",
  "Distrito", "Interés", "Nota", "Vendedor asignado (correo)",
  "¿Autorizó contacto?", "Fuente del consentimiento", "Estado importación (automático — no tocar)",
];

/**
 * Monta un mundo completo: nuestra hoja (LEADS vacía) y el origen con dos pestañas.
 * `landing` y `fb` son listas de filas de datos, sin encabezado.
 */
function montar({ landing = [], fb = [], filasLeads = [], maxFilasLeads, ...resto } = {}) {
  const hojaLeads = new Hoja("LEADS", 1074115978, [CAB_LEADS, ...filasLeads]);
  if (maxFilasLeads) hojaLeads.maxFilas = maxFilasLeads;
  const destino = new Libro("Leads AVANCE CORP — captura para CRM", [hojaLeads]);

  const hojaLanding = new Hoja("landing", 111, [CAB_LANDING, ...landing]);
  const hojaFb = new Hoja("formulario", 222, [CAB_FB, ...fb]);
  const origen = new Libro("02PLAZOFIJOMAS LANDING", [hojaLanding, hojaFb]);

  const entorno = crearEntorno({ destino, origen, ...resto });
  const gs = cargar(entorno);
  return { gs, destino, origen, hojaLeads, hojaLanding, hojaFb, espia: entorno.espia };
}

/** Filas de datos de LEADS (sin cabecera), tal como quedaron escritas. */
const leadsEscritos = (hojaLeads) => {
  const ultima = hojaLeads.getLastRow();
  if (ultima < 2) return [];
  return hojaLeads.getRange(2, 1, ultima - 1, 16).getDisplayValues();
};
const marcasDe = (gs, destino) => gs.leerMarcas(destino);

// ── 1. La frontera se pone a mano y NO importa nada ──────────────────────────

test("inicializarMarcas importa CERO leads y deja la frontera donde toca", () => {
  const { gs, destino, hojaLeads } = montar({
    landing: [filaLanding(1), filaLanding(2)],
    fb: [filaFb(1)],
  });

  gs.inicializarMarcas();

  assert.equal(leadsEscritos(hojaLeads).length, 0, "importó leads y no debía");
  assert.equal(destino.getSheetByName(gs.HOJA_HUELLAS), null, "creó huellas y no debía");

  const marcas = marcasDe(gs, destino);
  assert.deepEqual(Object.keys(marcas).sort(), ["111", "222"]);
  assert.equal(marcas["111"].ultimaFila, 3); // cabecera + 2 filas
  assert.equal(marcas["222"].ultimaFila, 2);
  assert.equal(marcas["111"].nombre, "landing");
});

test("inicializarMarcas NO mueve una frontera ya puesta (correrla dos veces es inocuo)", () => {
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  // Llegan leads nuevos y alguien vuelve a inicializar por costumbre.
  mundo.hojaLanding.appendRow(filaLanding(2));
  mundo.hojaLanding.appendRow(filaLanding(3));
  mundo.gs.inicializarMarcas();

  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes,
    "empujó la frontera y se habría comido los leads llegados entretanto");
});

test("una pestaña NUEVA se inicializa sin tocar las fronteras existentes", () => {
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();
  mundo.origen.hojas.push(new Hoja("tiktok", 333, [CAB_LANDING, filaLanding(9)]));

  mundo.gs.inicializarMarcas();

  const marcas = marcasDe(mundo.gs, mundo.destino);
  assert.deepEqual(Object.keys(marcas).sort(), ["111", "222", "333"]);
  assert.equal(marcas["333"].ultimaFila, 2);
});

// ── 2. Sin frontera, el puente se planta ─────────────────────────────────────

test("sin marcas, el puente SE DETIENE y no escribe nada", () => {
  const { gs, hojaLeads, destino } = montar({ landing: [filaLanding(1)] });

  assert.throws(() => gs.procesar(true), /marca de agua/i);
  assert.equal(leadsEscritos(hojaLeads).length, 0);
  assert.equal(destino.getSheetByName(gs.HOJA_MARCAS), null);
});

// ── 3. El camino feliz ───────────────────────────────────────────────────────

test("un lead NUEVO sin fecha entra entero: hoja, huella y marca", () => {
  const mundo = montar({ landing: [filaLanding(1)], fb: [] });
  mundo.gs.inicializarMarcas();

  mundo.hojaLanding.appendRow(filaLanding(7)); // llega uno nuevo, sin fecha
  const r = mundo.gs.procesar(true);

  assert.equal(r.aceptados.length, 1);
  const filas = leadsEscritos(mundo.hojaLeads);
  assert.equal(filas.length, 1);
  assert.equal(filas[0][0], "Persona7 Apellido7");
  assert.equal(filas[0][1], "+51918000007");
  assert.equal(filas[0][3], "PEN");
  assert.equal(filas[0][4], "LANDING");
  assert.equal(filas[0][15], "", "la columna de estado debe quedar vacía: es la señal del conector");
  assert.match(filas[0][11], /Sin fecha en el origen/);

  const huellas = mundo.destino.getSheetByName(mundo.gs.HOJA_HUELLAS);
  assert.equal(huellas.getLastRow(), 2, "cabecera + una huella");
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, 3);
});

test("el backlog sin fecha NO entra y tampoco ensucia REVISAR", () => {
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();

  const r = mundo.gs.procesar(true);

  assert.equal(r.aceptados.length, 0);
  assert.equal(r.backlogSinFecha, 3);
  const revisar = mundo.destino.getSheetByName(mundo.gs.HOJA_REVISAR);
  assert.ok(!revisar || revisar.getLastRow() <= 1, "el backlog acabó en REVISAR");
});

// ── 4. Los cuatro casos en que la marca deja de valer, de punta a punta ──────

test("pestaña RENOMBRADA: la memoria va por sheetId, así que sigue funcionando", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();

  mundo.hojaLanding.setName("landing 2026"); // se la renombra en el origen
  mundo.hojaLanding.appendRow(filaLanding(8));
  const r = mundo.gs.procesar(true);

  assert.equal(r.incidencias.length, 0, "se detuvo por un simple renombre");
  assert.equal(r.aceptados.length, 1);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].nombre, "landing 2026",
    "la marca debería anotar el nombre nuevo");
});

test("pestaña NUEVA sin inicializar: se detiene ella, las demás siguen", () => {
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();

  mundo.origen.hojas.push(new Hoja("tiktok", 333, [CAB_LANDING, filaLanding(50)]));
  mundo.hojaLanding.appendRow(filaLanding(9)); // y en landing sí llega uno bueno
  const r = mundo.gs.procesar(true);

  assert.equal(r.incidencias.length, 1);
  assert.equal(r.incidencias[0].pestana, "tiktok");
  assert.match(r.incidencias[0].motivo, /sin inicializar/i);
  assert.equal(r.aceptados.length, 1, "la pestaña sana también dejó de traer");
  assert.equal(marcasDe(mundo.gs, mundo.destino)["333"], undefined,
    "no debe inventarle una marca a la pestaña detenida");
});

test("ENCABEZADOS cambiados: se detiene y su marca queda intacta", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"];

  mundo.hojaLanding.getRange(1, 8, 1, 1).setValue("¿Cuánto capital deseas colocar?");
  mundo.hojaLanding.appendRow(filaLanding(10));
  const r = mundo.gs.procesar(true);

  assert.equal(r.aceptados.length, 0);
  assert.match(r.incidencias[0].motivo, /encabezados/i);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes.ultimaFila);
});

test("el origen PIERDE filas: se detiene", () => {
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();

  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent(); // desaparece la última
  const r = mundo.gs.procesar(true);

  assert.equal(r.aceptados.length, 0);
  assert.match(r.incidencias[0].motivo, /PERDIÓ filas/);
});

test("el origen se REORDENA: el ancla lo caza y se detiene", () => {
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();

  // Se intercambian dos filas ancladas: mismo número de filas, otro contenido.
  const f3 = mundo.hojaLanding.getRange(3, 1, 1, 11).getValues()[0];
  const f4 = mundo.hojaLanding.getRange(4, 1, 1, 11).getValues()[0];
  mundo.hojaLanding.getRange(3, 1, 1, 11).setValues([f4]);
  mundo.hojaLanding.getRange(4, 1, 1, 11).setValues([f3]);

  const r = mundo.gs.procesar(true);
  assert.equal(r.aceptados.length, 0);
  assert.match(r.incidencias[0].motivo, /ordenó o le insertaron/);
});

// ── 5. Concurrencia, fallo parcial y tope ────────────────────────────────────

test("dos corridas a la vez: la segunda se niega y NO escribe", () => {
  const mundo = montar({ landing: [filaLanding(1)], candadoLibre: false });

  assert.throws(() => mundo.gs.procesar(true), /Ya hay una corrida/);
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0);
  assert.equal(mundo.espia.candadoPedido, 1, "ni siquiera pidió el candado");
});

test("el candado se toma ANTES de escribir y se suelta siempre", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const pedidosTrasInit = mundo.espia.candadoPedido;

  mundo.hojaLanding.appendRow(filaLanding(11));
  mundo.gs.procesar(true);

  assert.equal(mundo.espia.candadoPedido, pedidosTrasInit + 1);
  assert.equal(mundo.espia.candadoSoltado, mundo.espia.candadoPedido, "algún candado quedó sin soltar");
});

test("la vista previa NO escribe ni toma el candado de escritura", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const marcaAntes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;
  mundo.hojaLanding.appendRow(filaLanding(12));

  const r = mundo.gs.procesar(false);

  assert.equal(r.aceptados.length, 1, "la vista previa debe DECIR qué entraría");
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0, "pero no escribirlo");
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, marcaAntes,
    "la vista previa movió la frontera");
});

test("si la escritura de leads falla, la MARCA NO AVANZA (se repite, no se pierde)", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  mundo.hojaLanding.appendRow(filaLanding(13));
  mundo.hojaLeads.fallarAlEscribir = () => { throw new Error("cuota agotada a mitad"); };

  assert.throws(() => mundo.gs.procesar(true), /cuota agotada/);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes,
    "la marca avanzó pese a que la escritura falló: ese lead se habría perdido para siempre");
});

test("si fallan las HUELLAS, la marca tampoco avanza (es lo último que se mueve)", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  // La pestaña de huellas ya existe y falla al escribir: la marca no puede haberse
  // movido antes. No es una catástrofe (los leads ya están en la hoja), pero anotar
  // «ya lo hice» antes de haberlo terminado de hacer es exactamente lo que no toca.
  const huellas = mundo.destino.insertSheet(mundo.gs.HOJA_HUELLAS, mundo.destino.getNumSheets());
  huellas.appendRow(["Huella (no tocar)", "Teléfono", "Origen", "Registrado el", "Traído el"]);
  huellas.fallarAlEscribir = () => { throw new Error("permisos de la pestaña protegida"); };

  mundo.hojaLanding.appendRow(filaLanding(16));
  assert.throws(() => mundo.gs.procesar(true), /permisos/);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes);
});

test("con el tope alcanzado, la marca avanza solo hasta lo mirado", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();

  const cuantas = mundo.gs.TOPE_POR_PASADA + 20;
  for (let i = 0; i < cuantas; i++) mundo.hojaLanding.appendRow(filaLanding(1000 + i));

  const r1 = mundo.gs.procesar(true);
  assert.equal(r1.aceptados.length, mundo.gs.TOPE_POR_PASADA);
  const marca1 = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;
  assert.equal(marca1, 2 + mundo.gs.TOPE_POR_PASADA,
    "la marca debería quedarse en la última fila EXAMINADA, no al final de la pestaña");

  const r2 = mundo.gs.procesar(true);
  assert.equal(r2.aceptados.length, 20, "las que quedaban debían seguir contando como nuevas");
});

// ── 6. Capacidad de la hoja (lo de la Fase 2, ejecutado de verdad) ───────────

test("la hoja CRECE sola cuando los leads pasan de su última fila", () => {
  // Una hoja justo en su techo, como la de verdad: 2001 filas.
  const mundo = montar({ landing: [filaLanding(1)], maxFilasLeads: 2001 });
  mundo.gs.inicializarMarcas();

  // Se llena hasta el borde y luego llegan más.
  const relleno = [];
  for (let f = 2; f <= 2001; f++) relleno.push(["x", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
  mundo.hojaLeads.getRange(2, 1, relleno.length, 16).setValues(relleno);
  assert.equal(mundo.hojaLeads.getLastRow(), 2001);

  mundo.hojaLanding.appendRow(filaLanding(14));
  mundo.gs.procesar(true);

  assert.ok(mundo.hojaLeads.getMaxRows() > 2001, "la hoja no creció: la pasada habría muerto");
  assert.equal(mundo.hojaLeads.getRange(2002, 2, 1, 1).getDisplayValues()[0][0], "+51918000014");
});

test("sin crecer, escribir fuera de la rejilla revienta (el simulador es fiel)", () => {
  const hoja = new Hoja("LEADS", 1, [CAB_LEADS]);
  hoja.maxFilas = 3;
  assert.throws(() => hoja.getRange(3, 1, 2, 16), /out of bounds/);
});

// ── 7. El conector ───────────────────────────────────────────────────────────

test("prepararHoja deja la hoja lista y NO enciende nada", () => {
  const mundo = montar({});
  const filas = mundo.gs.prepararHoja();

  assert.ok(filas >= 1000);
  assert.equal(mundo.espia.disparadores.length, 0, "preparar la hoja creó un disparador");
  assert.equal(mundo.espia.peticiones.length, 0, "preparar la hoja lanzó una importación");
  assert.equal(mundo.hojaLeads.getRange(1, 1, 1, 1).getDisplayValues()[0][0], "Nombre completo *");
  assert.equal(mundo.hojaLeads.formatos.get("2,2"), "@", "el teléfono debe quedar como TEXTO");
});

test("activarConector enciende UNO solo y apagarConector lo quita", () => {
  const mundo = montar({ propiedades: { IMPORTAR_SECRET: "s3cr3t0" } });
  mundo.gs.prepararHoja();

  mundo.gs.activarConector();
  assert.equal(mundo.espia.disparadores.length, 1);
  assert.equal(mundo.espia.disparadores[0].getHandlerFunction(), "importarLeads");
  assert.equal(mundo.espia.disparadores[0].cada, 5);

  mundo.gs.activarConector(); // idempotente: no duplica ciclos
  assert.equal(mundo.espia.disparadores.length, 1);

  mundo.gs.apagarConector();
  assert.equal(mundo.espia.disparadores.length, 0);
});

test("activarConector se niega si falta el secreto (falla ahí, no en el primer ciclo)", () => {
  const mundo = montar({ propiedades: {} });
  mundo.gs.prepararHoja();
  assert.throws(() => mundo.gs.activarConector(), /IMPORTAR_SECRET/);
  assert.equal(mundo.espia.disparadores.length, 0);
});

test("configurar() ya no existe: avisa en vez de importar por sorpresa", () => {
  const mundo = montar({ propiedades: { IMPORTAR_SECRET: "s3cr3t0" } });
  assert.equal(typeof mundo.gs.configurar, "function", "debe seguir existiendo, para poder avisar");
  assert.throws(() => mundo.gs.configurar(), /prepararHoja/);
  assert.equal(mundo.espia.disparadores.length, 0);
  assert.equal(mundo.espia.peticiones.length, 0);
});

test("importarLeads manda solo lo pendiente y escribe el estado que responde el edge", () => {
  const pendientes = [
    ["Ana", "+51918000021", "1000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000022", "2000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", "IMPORTADO ✓"],
  ];
  const mundo = montar({
    filasLeads: pendientes,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: {
      codigo: 200,
      cuerpo: JSON.stringify({ resultados: [{ fila: 2, estado: "IMPORTADO ✓" }] }),
    },
  });

  mundo.gs.importarLeads();

  assert.equal(mundo.espia.peticiones.length, 1);
  const cuerpo = JSON.parse(mundo.espia.peticiones[0].opciones.payload);
  assert.equal(cuerpo.filas.length, 1, "reenvió una fila que ya estaba importada");
  assert.equal(cuerpo.filas[0].nombre, "Ana");
  assert.equal(mundo.espia.peticiones[0].opciones.headers["x-importar-secret"], "s3cr3t0");
  assert.equal(mundo.hojaLeads.getRange(2, 16, 1, 1).getDisplayValues()[0][0], "IMPORTADO ✓");
});

test("importarLeads sin secreto falla con un mensaje que dice qué hacer", () => {
  const mundo = montar({ filasLeads: [["Ana", "+51918000021", "1000", "PEN", "LANDING", "", "", "", "", "", "", "", "", "SI", "", ""]] });
  assert.throws(() => mundo.gs.importarLeads(), /Propiedades del script/);
  assert.equal(mundo.espia.peticiones.length, 0);
});

test("el conector NO se lleva por delante la pestaña equivocada", () => {
  // El puente crea sus pestañas de memoria; el conector debe seguir mirando LEADS.
  const mundo = montar({ landing: [filaLanding(1)], propiedades: { IMPORTAR_SECRET: "s3cr3t0" } });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.appendRow(filaLanding(15));
  mundo.gs.procesar(true);

  assert.ok(mundo.destino.getSheetByName(mundo.gs.HOJA_MARCAS), "no creó la hoja de marcas");
  mundo.gs.importarLeads();

  const cuerpo = JSON.parse(mundo.espia.peticiones[0].opciones.payload);
  assert.equal(cuerpo.filas.length, 1);
  assert.equal(cuerpo.filas[0].telefono, "+51918000015", "importó de una pestaña que no es LEADS");
});
