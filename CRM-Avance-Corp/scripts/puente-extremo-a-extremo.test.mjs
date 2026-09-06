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
  "return { procesar, inicializarMarcas, retrocederMarca, leerMarcas, traerLeadsDelOrigen," +
  " vistaPreviaOrigen, prepararHoja, activarConector, apagarConector, importarLeads, configurar," +
  " corridaProgramada, instalarHorario, quitarHorario, verHorario, verEstado," +
  " leerEstado, medirOrigen, relojDeLima, contarEstadosDeLeads, crearMenu, onEdit," +
  " TOPE_POR_PASADA, FECHA_CORTE, HOJA_MARCAS, HOJA_HUELLAS, HOJA_LEADS," +
  " HOJA_REVISAR, MOTIVO_BACKLOG, CADENCIA_MINUTOS, COL_ESTADO, categoriaResultadoImportacion };";

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
  "Teléfono alternativo",
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
  return hojaLeads.getRange(2, 1, ultima - 1, 17).getDisplayValues();
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
  assert.equal(filas[0][16], "", "el WhatsApp repetido no debe duplicar el teléfono");
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
    ["Ana", "+51918000021", "1000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", "", "+51918000999"],
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
  assert.equal(cuerpo.filas[0].telefono_alternativo, "+51918000999");
  assert.equal(mundo.espia.peticiones[0].opciones.headers["x-importar-secret"], "s3cr3t0");
  assert.equal(mundo.hojaLeads.getRange(2, 16, 1, 1).getDisplayValues()[0][0], "IMPORTADO ✓");
});

test("cada corrida identifica IMPORTADO, DUPLICADO, RECHAZADO y ERROR temporal por fila", () => {
  const filas = [
    ["Ana", "+51918000101", "1000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000102", "2000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", ""],
    ["Carla", "+51918000103", "3000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", ""],
    ["Diego", "+51918000104", "4000", "PEN", "LANDING", "", "", "", "", "Lima", "Nuevo", "", "", "SI", "landing", "ERROR temporal (503) — se reintenta solo"],
  ];
  const mundo = montar({
    filasLeads: filas,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: {
      codigo: 200,
      cuerpo: JSON.stringify({
        resultados: [
          { fila: 2, resultado: "importado", estado: "IMPORTADO ✓" },
          { fila: 3, resultado: "duplicado", estado: "DUPLICADO: ya existe en el CRM" },
          { fila: 4, resultado: "rechazado", estado: "RECHAZADO: capital inválido" },
          { fila: 5, resultado: "error_temporal", estado: "ERROR temporal: CRM ocupado — se reintenta solo" },
        ],
      }),
    },
  });

  mundo.gs.importarLeads();

  const estados = mundo.hojaLeads.getRange(2, 16, 4, 1).getDisplayValues().flat();
  assert.deepEqual(estados, [
    "IMPORTADO ✓",
    "DUPLICADO: ya existe en el CRM",
    "RECHAZADO: capital inválido",
    "ERROR temporal: CRM ocupado — se reintenta solo",
  ]);
  const cuenta = mundo.gs.contarEstadosDeLeads(mundo.hojaLeads);
  assert.deepEqual(
    { importados: cuenta.importados, duplicados: cuenta.duplicados, rechazados: cuenta.rechazados, errores: cuenta.errores },
    { importados: 1, duplicados: 1, rechazados: 1, errores: 1 },
  );
});

test("una respuesta parcial del CRM deja cada fila ausente como ERROR temporal", () => {
  const filas = [
    ["Ana", "+51918000111", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000112", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
    ["Carla", "+51918000113", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
  ];
  const mundo = montar({
    filasLeads: filas,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: {
      codigo: 200,
      cuerpo: JSON.stringify({
        resultados: [
          { fila: 2, resultado: "importado", estado: "IMPORTADO ✓" },
          { fila: 999, resultado: "rechazado", estado: "RECHAZADO: fila ajena" },
        ],
      }),
    },
  });

  mundo.gs.importarLeads();

  const estados = mundo.hojaLeads.getRange(2, 16, 3, 1).getDisplayValues().flat();
  assert.equal(estados[0], "IMPORTADO ✓");
  assert.match(estados[1], /^ERROR temporal: el CRM no confirmó esta fila/);
  assert.match(estados[2], /^ERROR temporal: el CRM no confirmó esta fila/);
});

test("una categoría contradictoria o sin estado reconocible se reintenta, no se adivina", () => {
  const filas = [
    ["Ana", "+51918000115", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000116", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
  ];
  const mundo = montar({
    filasLeads: filas,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: {
      codigo: 200,
      cuerpo: JSON.stringify({
        resultados: [
          { fila: 2, resultado: "importado", estado: "RECHAZADO: respuesta contradictoria" },
          { fila: 3, resultado: "importado", estado: "confirmado" },
        ],
      }),
    },
  });

  mundo.gs.importarLeads();

  const estados = mundo.hojaLeads.getRange(2, 16, 2, 1).getDisplayValues().flat();
  assert.ok(estados.every((e) => /^ERROR temporal: el CRM no confirmó esta fila/.test(e)));
});

test("un error HTTP del lote identifica TODAS las filas como temporales", () => {
  const filas = [
    ["Ana", "+51918000121", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000122", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
  ];
  const mundo = montar({
    filasLeads: filas,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: { codigo: 503, cuerpo: "servicio no disponible" },
  });

  mundo.gs.importarLeads();

  const estados = mundo.hojaLeads.getRange(2, 16, 2, 1).getDisplayValues().flat();
  assert.deepEqual(estados, [
    "ERROR temporal (503) — se reintenta solo",
    "ERROR temporal (503) — se reintenta solo",
  ]);
});

test("si UrlFetch falla antes de responder, ninguna fila queda en limbo", () => {
  const filas = [
    ["Ana", "+51918000131", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
    ["Beto", "+51918000132", "1000", "PEN", "LANDING", "", "", "", "", "", "Nuevo", "", "", "SI", "landing", ""],
  ];
  const mundo = montar({
    filasLeads: filas,
    propiedades: { IMPORTAR_SECRET: "s3cr3t0" },
    respuestaHttp: { error: new Error("timeout") },
  });

  mundo.gs.importarLeads();

  const estados = mundo.hojaLeads.getRange(2, 16, 2, 1).getDisplayValues().flat();
  assert.ok(estados.every((e) => /^ERROR temporal \(sin respuesta del CRM\)/.test(e)));
});

test("importarLeads sin secreto falla con un mensaje que dice qué hacer", () => {
  const mundo = montar({ filasLeads: [["Ana", "+51918000021", "1000", "PEN", "LANDING", "", "", "", "", "", "", "", "", "SI", "", ""]] });
  assert.throws(() => mundo.gs.importarLeads(), /Propiedades del script/);
  assert.equal(mundo.espia.peticiones.length, 0);
});

// ── 8. Fase 4: la cadencia de 15 minutos, ejecutada ──────────────────────────
//
// Lo que aquí se prueba no es "que funcione": es que el pre-chequeo AHORRE de verdad
// (el simulador cuenta las celdas descargadas) y que no ahorre de más — cualquier
// duda tiene que acabar en lectura completa. Un pre-chequeo que se equivoque hacia
// callar no se nota en producción: simplemente los leads dejan de llegar.

/** Cuántas celdas del origen se han descargado, sumando sus dos pestañas. */
const celdasLeidasDelOrigen = (m) => m.hojaLanding.celdasLeidas + m.hojaFb.celdasLeidas;
const reiniciarContadores = (m) => {
  m.hojaLanding.celdasLeidas = 0;
  m.hojaFb.celdasLeidas = 0;
};

test("fuera de la ventana (domingo) la corrida no toca NI UNA celda del origen", () => {
  const mundo = montar({ landing: [filaLanding(1)], ahora: "2026-08-16 09:20" }); // domingo
  mundo.gs.inicializarMarcas();
  reiniciarContadores(mundo);

  const r = mundo.gs.corridaProgramada();

  assert.match(r.omitida, /domingo/);
  assert.equal(celdasLeidasDelOrigen(mundo), 0, "leyó el origen un domingo");
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0);
});

test("de madrugada tampoco corre", () => {
  const mundo = montar({ landing: [filaLanding(1)], ahora: "2026-08-17 03:00" });
  mundo.gs.inicializarMarcas();
  assert.match(mundo.gs.corridaProgramada().omitida, /ventana/);
});

test("sin novedad en el origen: se decide sin descargar ni una celda", () => {
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada();          // la 1.ª del día paga el suelo diario
  reiniciarContadores(mundo);

  const r = mundo.gs.corridaProgramada(); // la de 15 minutos después

  assert.equal(r.omitida, "sin novedad");
  assert.equal(celdasLeidasDelOrigen(mundo), 0,
    "descargó el origen entero para descubrir que no había nada nuevo");
  assert.equal(mundo.gs.leerEstado().ultimoVeredicto, "sin novedad en el origen");
});

test("el origen crece: la misma corrida SÍ paga la lectura y trae el lead", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada();
  reiniciarContadores(mundo);

  mundo.hojaLanding.appendRow(filaLanding(31));
  const r = mundo.gs.corridaProgramada();

  assert.equal(r.aceptados.length, 1);
  assert.ok(celdasLeidasDelOrigen(mundo) > 0, "trajo un lead sin leer el origen (?)");
  assert.equal(leadsEscritos(mundo.hojaLeads)[0][1], "+51918000031");
  assert.equal(mundo.gs.leerEstado().pasadaCompletaEl, "2026-08-17");
});

test("el SUELO DIARIO: al día siguiente se lee entero aunque nada haya crecido", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada();
  reiniciarContadores(mundo);

  mundo.espia.ponerReloj("2026-08-18 07:00"); // martes
  const r = mundo.gs.corridaProgramada();

  assert.ok(!r.omitida, "el suelo diario no disparó la lectura completa");
  assert.ok(celdasLeidasDelOrigen(mundo) > 0);
  assert.equal(mundo.gs.leerEstado().pasadaCompletaEl, "2026-08-18");
});

const avisosDe = (gs) => gs.leerEstado().avisos || {};

test("una pestaña detenida queda anotada como aviso, con la fecha en que empezó", () => {
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent(); // el origen pierde una fila

  mundo.gs.corridaProgramada();
  const aviso = avisosDe(mundo.gs)["pestana-detenida"];
  assert.ok(aviso, "no anotó el aviso");
  assert.match(aviso.titulo, /pestaña\(s\) detenida\(s\)/);
  assert.match(aviso.detalle, /PERDIÓ filas/);
  assert.equal(aviso.desde, "17/08/2026 09:20");

  // Al día siguiente sigue roto: el aviso SIGUE, y su "desde" no se mueve — lo que
  // interesa es cuánto lleva así, no cuántas veces se repitió.
  mundo.espia.ponerReloj("2026-08-18 09:20");
  mundo.gs.corridaProgramada();
  assert.equal(avisosDe(mundo.gs)["pestana-detenida"].desde, "17/08/2026 09:20");
  assert.equal(avisosDe(mundo.gs)["pestana-detenida"].ultimo, "18/08/2026 09:20");
});

test("el aviso SE APAGA solo cuando el problema se arregla", () => {
  // Un aviso que no se apaga miente igual que uno que nunca suena, y enseña a
  // ignorar el panel.
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent();
  mundo.gs.corridaProgramada();
  assert.ok(avisosDe(mundo.gs)["pestana-detenida"]);

  // Se arregla como manda el propio aviso: se borra la marca de esa pestaña y se
  // vuelve a poner la frontera.
  const marcas = mundo.destino.getSheetByName(mundo.gs.HOJA_MARCAS);
  marcas.getRange(2, 1, marcas.getLastRow() - 1, 7).clearContent();
  mundo.gs.inicializarMarcas();
  mundo.espia.ponerReloj("2026-08-18 09:20");
  mundo.gs.corridaProgramada();

  assert.deepEqual(avisosDe(mundo.gs), {}, "el aviso siguió encendido con todo arreglado");
});

test("al ABRIR la hoja, los avisos salen a la cara (el sustituto del correo)", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.corridaProgramada(); // sin frontera → queda el aviso "sin-marcas"

  mundo.destino.avisos.length = 0;
  mundo.gs.crearMenu();

  assert.equal(mundo.destino.avisos.length, 1, "abrir la hoja no dijo nada de un puente parado");
  assert.match(mundo.destino.avisos[0].titulo, /1 aviso/);
  assert.match(mundo.destino.avisos[0].mensaje, /marca de agua/);

  // Y con todo en orden, la hoja se abre sin ruido.
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada();
  mundo.destino.avisos.length = 0;
  mundo.gs.crearMenu();
  assert.equal(mundo.destino.avisos.length, 0, "molestó al abrir la hoja sin tener nada que decir");
});

test("una pestaña detenida NO se re-descubre cada cuarto de hora", () => {
  // Mientras un humano no la arregle, esa pestaña choca con su marca en CADA
  // pre-chequeo. Sin memoria de lo ya detenido serían 96 lecturas de 12.000 filas
  // al día por algo que ya se sabe — la cuota entera, tirada, mientras el puente
  // "funciona".
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent(); // el origen pierde una fila

  const primera = mundo.gs.corridaProgramada(); // la descubre, avisa y la anota
  assert.equal(primera.incidencias.length, 1);
  reiniciarContadores(mundo);

  const segunda = mundo.gs.corridaProgramada(); // 15 min después, todo igual de roto
  assert.equal(segunda.omitida, "sin novedad",
    "vuelve a descargar el origen entero por una avería que ya conocía");
  assert.equal(celdasLeidasDelOrigen(mundo), 0);
  assert.equal(avisosDe(mundo.gs)["pestana-detenida"].desde, "17/08/2026 09:20",
    "y el aviso sigue contando desde que empezó, no desde la última corrida");

  // Pero si el origen vuelve a moverse, hay que mirar otra vez.
  mundo.hojaLanding.appendRow(filaLanding(41));
  mundo.hojaLanding.appendRow(filaLanding(42));
  assert.ok(!mundo.gs.corridaProgramada().omitida, "dejó de mirar una pestaña que cambió");
});

test("recordar lo detenido no puede tapar el trabajo pendiente de una pestaña SANA", () => {
  // La memoria de averías es solo eso: averías. Si se convirtiera en un "ya miré
  // esto" general, una pestaña sana a la que el tope dejó leads a medias se quedaría
  // esperando al suelo diario — hasta 24 h de retraso, otra vez, y sin que se note.
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent(); // landing se avería
  for (let i = 0; i < mundo.gs.TOPE_POR_PASADA + 20; i++) mundo.hojaFb.appendRow(filaFb(2000 + i));

  const primera = mundo.gs.corridaProgramada();
  assert.equal(primera.incidencias.length, 1, "landing debía quedar detenida");
  assert.equal(primera.aceptados.length, mundo.gs.TOPE_POR_PASADA, "el tope debía cortar a fb");

  const segunda = mundo.gs.corridaProgramada();
  assert.ok(!segunda.omitida, "dejó los 20 leads de fb esperando al día siguiente");
  assert.equal(segunda.aceptados.length, 20);
});

test("sin marca de agua la corrida automática NO revienta: lo anota y sigue viva", () => {
  // Lanzar aquí serían 96 correos de fallo de Google al día, hasta que nadie los mire.
  const mundo = montar({ landing: [filaLanding(1)] }); // sin inicializarMarcas

  const r = mundo.gs.corridaProgramada();

  assert.equal(r.omitida, "sin marca de agua");
  const aviso = avisosDe(mundo.gs)["sin-marcas"];
  assert.ok(aviso, "un puente parado sin dejar rastro es la avería que nadie descubre");
  assert.match(aviso.titulo, /falta la marca de agua/);
  assert.match(aviso.detalle, /Inicializar marca de agua/);

  // Tres corridas más el mismo día: el aviso es UNO y sigue fechado en la primera.
  mundo.gs.corridaProgramada();
  mundo.gs.corridaProgramada();
  mundo.espia.ponerReloj("2026-08-18 07:00");
  mundo.gs.corridaProgramada();
  assert.equal(Object.keys(avisosDe(mundo.gs)).length, 1);
  assert.equal(avisosDe(mundo.gs)["sin-marcas"].desde, aviso.desde,
    "reescribió el inicio del aviso: se pierde cuánto lleva parado");
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0);
  assert.match(mundo.gs.leerEstado().ultimoVeredicto, /PARADO/);
  // Un puente parado NO puede dejar el día por leído. Esto no salva ningún lead —
  // cuando por fin se ponga la frontera, lo que llegue después entra igual porque el
  // origen habrá crecido— pero sí evita que el panel diga "hoy se leyó el origen
  // entero" el día en que no se leyó nada. El panel existe para eso.
  assert.ok(!mundo.gs.leerEstado().pasadaCompletaEl,
    "el diario dio el día por leído sin haber leído nada");
});

test("una pestaña VACÍA en el origen no obliga a leerlo entero cada cuarto de hora", () => {
  // El pre-chequeo y la pasada completa tienen que medir con la MISMA vara: una
  // pestaña sin nada mide 1 fila para getDataRange y 0 para getLastRow. Con dos varas
  // distintas, el pre-chequeo lee "perdió filas" en cada corrida y manda descargar las
  // 12.000 filas del origen 96 veces al día — justo la cuota que esta fase vino a salvar.
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.origen.hojas.push(new Hoja("borradores", 444, []));
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada(); // la 1.ª del día paga el suelo
  reiniciarContadores(mundo);

  const r = mundo.gs.corridaProgramada();

  assert.equal(r.omitida, "sin novedad",
    "una pestaña vacía dispara una lectura completa en cada corrida");
  assert.equal(celdasLeidasDelOrigen(mundo), 0);
});

test("si la pasada falla, la corrida lo anota — y la marca NO avanza", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  mundo.hojaLanding.appendRow(filaLanding(32));
  mundo.hojaLeads.fallarAlEscribir = () => { throw new Error("cuota agotada a mitad"); };

  const r = mundo.gs.corridaProgramada(); // no lanza

  assert.equal(r.omitida, "error");
  assert.match(r.error, /cuota agotada/);
  assert.match(avisosDe(mundo.gs)["error"].titulo, /FALLÓ/);
  assert.match(avisosDe(mundo.gs)["error"].detalle, /cuota agotada/);
  assert.match(mundo.gs.leerEstado().ultimoError, /cuota agotada/);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes,
    "la marca avanzó pese al fallo");

  // Y cuando la corrida vuelve a salir bien, el aviso se apaga solo.
  mundo.hojaLeads.fallarAlEscribir = null;
  mundo.gs.corridaProgramada();
  assert.equal(avisosDe(mundo.gs)["error"], undefined, "el aviso de error se quedó encendido");
});

test("dos corridas solapadas NO son un error: ni aviso ni escándalo", () => {
  // A 15 minutos, una pasada lenta sobre 12.000 filas puede pisar a la siguiente (o
  // pisarla un "Traer" a mano). El candado ya lo resuelve; poner el panel en rojo por
  // eso sería avisar de que las defensas funcionan, y un rojo permanente no lo mira nadie.
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.appendRow(filaLanding(34)); // hay trabajo de verdad que hacer
  mundo.espia.candadoLibre = false;             // …pero otra corrida va por delante

  const r = mundo.gs.corridaProgramada();

  assert.equal(r.omitida, "solapada");
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0, "escribió con otra corrida en marcha");
  assert.deepEqual(avisosDe(mundo.gs), {}, "puso un aviso porque el candado hizo su trabajo");
  assert.match(mundo.gs.leerEstado().ultimoVeredicto, /otra corrida en marcha/);
});

test("el ORIGEN SECO es un dato del panel, NO una avería que ponga el puente en rojo", () => {
  // Lleva seco desde el 24-jul y es una hoja ajena: convertirlo en aviso sería tener
  // el puente en rojo permanente, y a un rojo permanente se le deja de mirar.
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  mundo.gs.corridaProgramada();               // deja constancia de desde cuándo vigila

  mundo.espia.ponerReloj("2026-08-21 09:20"); // viernes, 4 días después, origen igual
  mundo.gs.corridaProgramada();

  assert.deepEqual(avisosDe(mundo.gs), {}, "puso el puente en rojo por algo que ya se sabe");
  const d = mundo.gs.verEstado();
  assert.equal(d.estado.vigilaDesde, "2026-08-17");
  const panel = mundo.espia.ventanas[mundo.espia.ventanas.length - 1];
  assert.match(panel, /ESTADO DEL PUENTE/, "el panel debería salir en pantalla");
  assert.match(panel, /Vigilado desde hace 4 día\(s\); todavía sin verlo crecer/);
  assert.ok(!/Recibió filas HOY/.test(panel),
    "el panel afirma que el origen recibió hoy sin haberlo visto crecer NUNCA");
  assert.match(panel, /Sin avisos activos/);
});

test("instalarHorario deja UN disparador de 15 min y se lleva los seis viejos", () => {
  const mundo = montar({});
  // El horario anterior: seis semanales a las 9 a. m., todos con el mismo manejador.
  for (let i = 0; i < 6; i++) {
    mundo.espia.disparadores.push({ getHandlerFunction: () => "corridaProgramada", hora: 9 });
  }

  mundo.gs.instalarHorario();

  assert.equal(mundo.espia.disparadores.length, 1, "sumó el nuevo a los viejos");
  assert.equal(mundo.espia.disparadores[0].getHandlerFunction(), "corridaProgramada");
  assert.equal(mundo.espia.disparadores[0].cada, mundo.gs.CADENCIA_MINUTOS);
  assert.equal(mundo.gs.verHorario(), 1);

  mundo.gs.quitarHorario();
  assert.equal(mundo.espia.disparadores.length, 0);
});

test("el panel de estado se puede pedir en cualquier momento y solo LEE", () => {
  const mundo = montar({ landing: [filaLanding(1)], propiedades: { IMPORTAR_SECRET: "s3cr3t0" } });
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.appendRow(filaLanding(33));
  mundo.gs.corridaProgramada();
  mundo.gs.activarConector();

  const antes = leadsEscritos(mundo.hojaLeads).length;
  const d = mundo.gs.verEstado();

  assert.equal(d.puente, 0, "no debería haber horario del puente encendido en esta prueba");
  assert.equal(d.conector, 1);
  assert.equal(d.hoja.total, 1);
  assert.equal(d.hoja.pendientes, 1, "el lead recién traído está esperando al conector");
  assert.equal(d.pestanas.length, 2);
  assert.equal(leadsEscritos(mundo.hojaLeads).length, antes, "el panel escribió algo");
});

// ── 8 bis. Los seis agujeros que encontró Codex el 2026-08-16 ───────────────

test("renombrar las columnas de TELÉFONO detiene la pestaña — no la salta en silencio", () => {
  // El peor de todos: la comprobación de "¿hay columna de teléfono?" iba ANTES de la
  // de "¿sigue siendo la misma pestaña?". Renombrar esas dos columnas en el origen
  // hacía que el puente se saltara la pestaña sin incidencia, sin aviso, y encima
  // apagando el aviso anterior. Los leads dejaban de llegar y el panel decía
  // "sin avisos activos".
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();

  mundo.hojaLanding.getRange(1, 3, 1, 2).setValues([["Contacto principal", "Contacto alterno"]]);
  mundo.hojaLanding.appendRow(filaLanding(70));
  const r = mundo.gs.corridaProgramada();

  assert.equal(r.incidencias.length, 1, "se saltó la pestaña en silencio");
  assert.match(r.incidencias[0].motivo, /encabezados/i);
  assert.ok(mundo.gs.leerEstado().avisos["pestana-detenida"], "no dejó aviso de la avería");
});

test("una pestaña que NUNCA tuvo teléfonos se salta sin dar guerra", () => {
  // La otra cara: el arreglo no puede convertir en avería permanente una pestaña de
  // resumen que jamás fue de leads.
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.origen.hojas.push(new Hoja("resumen", 555, [["Mes", "Total"], ["julio", "12"]]));
  mundo.gs.inicializarMarcas();
  mundo.hojaLanding.appendRow(filaLanding(71));

  const r = mundo.gs.procesar(true);

  assert.equal(r.incidencias.length, 0, "convirtió una pestaña de resumen en avería");
  assert.equal(r.aceptados.length, 1);
});

test("si falla la escritura de REVISAR, la marca NO avanza (el lead no se evapora)", () => {
  // La marca se guardaba ANTES que REVISAR. Si esa escritura fallaba, la fila que iba
  // a revisión quedaba por debajo de la frontera y en la pasada siguiente pasaba a ser
  // "historia": ni en LEADS, ni en REVISAR, ni en ningún sitio.
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  // Llega una fila nueva SIN teléfono válido: su destino es REVISAR.
  const sinTelefono = filaLanding(72);
  sinTelefono[2] = "no tengo";
  mundo.hojaLanding.appendRow(sinTelefono);
  const revisar = mundo.destino.insertSheet(mundo.gs.HOJA_REVISAR, mundo.destino.getNumSheets());
  revisar.fallarAlEscribir = () => { throw new Error("cuota agotada escribiendo REVISAR"); };

  assert.throws(() => mundo.gs.procesar(true), /REVISAR/);
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes,
    "la frontera avanzó y ese lead ya no aparecerá en ninguna parte");
});

test("si falla la escritura de la marca, las fronteras anteriores SIGUEN ahí", () => {
  // Se borraba primero y se escribía después. Si lo segundo fallaba, la memoria
  // quedaba vacía: el puente se planta, y al re-inicializar, todo lo llegado
  // entretanto se convierte en historia. Ahora es una sola escritura.
  const mundo = montar({ landing: [filaLanding(1)], fb: [filaFb(1)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino);
  assert.equal(Object.keys(antes).length, 2);

  mundo.hojaLanding.appendRow(filaLanding(73));
  mundo.destino.getSheetByName(mundo.gs.HOJA_MARCAS).fallarAlEscribir = () => {
    throw new Error("se cayó guardando la marca");
  };

  assert.throws(() => mundo.gs.procesar(true), /guardando la marca/);
  const despues = marcasDe(mundo.gs, mundo.destino);
  assert.equal(Object.keys(despues).length, 2, "se quedó SIN memoria: se perderían leads al re-inicializar");
  assert.equal(despues["111"].ultimaFila, antes["111"].ultimaFila);
});

test("un nombre que empieza por = llega como texto, no como fórmula", () => {
  // El origen es de otra empresa: lo que venga de ahí puede ser cualquier cosa. Un
  // lead llamado "=1+1" acababa en la hoja como "2", y el conector subía "2" al CRM
  // como nombre del cliente.
  const mundo = montar({ landing: [] });
  mundo.gs.inicializarMarcas();
  const traviesa = filaLanding(74);
  traviesa[1] = "";
  mundo.hojaLanding.appendRow(traviesa);
  // El texto se inyecta CRUDO en la celda del origen: así es como llega de verdad —
  // por una respuesta de formulario—, no escribiéndolo con setValues (que lo
  // convertiría en fórmula ya en el propio origen).
  mundo.hojaLanding.celdas.set(mundo.hojaLanding.getLastRow() + ",1", "=1+1");

  mundo.gs.procesar(true);

  const escrito = leadsEscritos(mundo.hojaLeads)[0][0];
  assert.equal(escrito, "1+1", "el nombre se guardó como fórmula: " + escrito);
  assert.ok(!/FÓRMULA/.test(escrito));
});

// ── 9. La ida y vuelta por Sheets: lo que se escribe es lo que se lee ────────
//
// Descubierto EN PRODUCCIÓN el 2026-08-16, la primera vez que se abrió el panel de
// verdad: la fecha de la frontera salía como "Sun Aug 16 2026 16:48:00 GMT-0500".
// El texto "16/08/2026 16:48" se escribía bien, pero Sheets lo reconocía como FECHA,
// lo guardaba como fecha, y `getValues` devolvía un objeto Date.
//
// Ninguna prueba lo cazó porque el simulador guardaba el texto tal cual. Ahora imita
// la interpretación de Sheets, y estas pruebas ejercitan el viaje completo.

test("la fecha de la frontera vuelve tal como se escribió, no como objeto de fecha", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();

  const m = marcasDe(mundo.gs, mundo.destino)["111"];
  assert.equal(m.actualizado, "17/08/2026 09:20");
  assert.ok(!/Aug|GMT|\(/.test(m.actualizado), "volvió deformada: " + m.actualizado);
});

test("el panel enseña la fecha de la frontera en castellano y en hora de Lima", () => {
  // A propósito NO usa un fixture: sale de la hoja simulada, que es donde ocurre la
  // deformación. Un fixture escrito a mano habría pasado esta prueba con el bug vivo.
  const mundo = montar({ landing: [filaLanding(1)], propiedades: { IMPORTAR_SECRET: "s3cr3t0" } });
  mundo.gs.inicializarMarcas();
  mundo.gs.verEstado();

  const panel = mundo.espia.ventanas[mundo.espia.ventanas.length - 1];
  assert.match(panel, /\(puesta el 17\/08\/2026 09:20\)/);
  assert.ok(!/GMT|Aug|hora estándar/.test(panel), "el panel trae una fecha en inglés");
});

test("EL BLINDAJE: lo que se guarda en las marcas es TEXTO, no una fecha", () => {
  // Pincha `forzarTexto`. Se mira el valor CRUDO de la celda, no lo que devuelve
  // leerMarcas: si se mirara lo segundo, la cura de abajo taparía este agujero y el
  // mutante que quita el blindaje sobreviviría. (Pasó: los dos arreglos se cubrían
  // mutuamente y ninguno quedaba probado.)
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();

  const hoja = mundo.destino.getSheetByName(mundo.gs.HOJA_MARCAS);
  const celda = hoja.getRange(2, 7, 1, 1).getValues()[0][0];
  assert.equal(typeof celda, "string", "Sheets convirtió el sello de hora en fecha");
  assert.equal(celda, "17/08/2026 09:20");
});

test("LA CURA: una marca vieja, ya guardada como fecha, se lee en hora de Lima", () => {
  // El estado REAL de la hoja de Miguel al descubrir esto: la pestaña ya existe y su
  // columna de fecha ya está envenenada. El blindaje evita que vuelva a pasar, pero
  // no arregla lo ya guardado — de eso se encarga `momentoDeCelda`.
  const mundo = montar({ landing: [filaLanding(1)] });
  const marcas = mundo.destino.insertSheet(mundo.gs.HOJA_MARCAS, mundo.destino.getNumSheets());
  marcas.appendRow(["sheetId (no tocar)", "Pestaña", "Última fila vista", "Filas al cerrar",
    "Huella de encabezados", "Ancla de contenido", "Actualizado"]);
  // Sin formato de texto: exactamente como quedó en producción.
  marcas.getRange(2, 1, 1, 7).setValues([["111", "landing", 3, 3, "h1", "h2", "05/08/2026 10:30"]]);
  assert.equal(Object.prototype.toString.call(marcas.getRange(2, 7, 1, 1).getValues()[0][0]),
    "[object Date]", "el fixture debería estar envenenado, si no la prueba no prueba nada");

  const leida = mundo.gs.leerMarcas(mundo.destino)["111"];

  assert.equal(leida.actualizado, "05/08/2026 10:30");
  assert.ok(!/GMT|Aug/.test(leida.actualizado));
});

test("una pestaña con identificador CERO no se toma por nueva", () => {
  // El caso real: en la hoja de Miguel, `landing` tiene sheetId 0 — el que Google le
  // da a la primera pestaña de un libro. Todas las pruebas usaban identificadores
  // normales, y el 0 sobrevive por una casualidad afortunada (el texto "0" es
  // "verdadero" en JavaScript, el número 0 no). Si alguien cambiara ese String por un
  // Number, la pestaña principal del origen se detendría entera y en silencio.
  const hojaCero = new Hoja("landing", 0, [CAB_LANDING, filaLanding(1)]);
  const hojaFb = new Hoja("formulario", 222, [CAB_FB]);
  const origen = new Libro("02PLAZOFIJOMAS LANDING", [hojaCero, hojaFb]);
  const destino = new Libro("Leads AVANCE CORP — captura para CRM", [new Hoja("LEADS", 7, [CAB_LEADS])]);
  const entorno = crearEntorno({ destino, origen });
  const gs = cargar(entorno);

  gs.inicializarMarcas();
  assert.ok(gs.leerMarcas(destino)["0"], "no guardó la marca de la pestaña con id 0");

  hojaCero.appendRow(filaLanding(60));
  const r = gs.procesar(true);

  assert.equal(r.incidencias.length, 0, "detuvo la pestaña principal: " + JSON.stringify(r.incidencias));
  assert.equal(r.aceptados.length, 1);
});

test("la fecha de una frontera que NO se tocó no se rejuvenece", () => {
  // La columna "Actualizado" es la que responde "¿cuánto lleva esta pestaña sin
  // mirarse?". Sellar todas las filas con la hora de hoy —incluidas las detenidas—
  // convierte esa columna en ruido justo cuando hace falta para diagnosticar.
  const mundo = montar({
    landing: [filaLanding(1), filaLanding(2), filaLanding(3)],
    fb: [filaFb(1)],
  });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].actualizado;

  mundo.hojaLanding.getRange(4, 1, 1, 11).clearContent(); // landing se avería
  mundo.espia.ponerReloj("2026-08-18 11:30");             // martes, dos días después
  mundo.hojaFb.appendRow(filaFb(2));                      // y en fb sí llega uno
  const r = mundo.gs.procesar(true);

  assert.equal(r.incidencias.length, 1, "landing debía quedar detenida");
  const marcas = marcasDe(mundo.gs, mundo.destino);
  assert.equal(marcas["111"].actualizado, antes,
    "la pestaña detenida figura como recién mirada, y lleva dos días sin traerse nada");
  assert.equal(marcas["222"].actualizado, "18/08/2026 11:30",
    "la pestaña que sí se miró debería llevar la hora de esta pasada");
});

// ── onEdit — no reintenta una fila que ya IMPORTÓ ────────────────────────────
//
// Antes, cualquier edición de A–O borraba la columna P sin mirar qué decía. Una
// fila ya "IMPORTADO ✓" se limpiaba igual que una "RECHAZADO", el siguiente ciclo
// la reenviaba, y como el importador SOLO INSERTA (nunca actualiza), el dedup se
// encontraba a sí misma y la reetiquetaba "DUPLICADO: ya existe en el CRM" —
// pisando un estado que era correcto. Visto en producción el 2026-08-25.

/** Fila completa de LEADS (17 columnas, mismo orden que CAB_LEADS) con un estado dado. */
const filaConEstado = (estado) => [
  "Cliente Test", "+51999999999", "1000", "PEN", "LANDING", "", "", "", "",
  "Lima", "Nuevo", "", "", "SI", "Landing COOPAC MÁSCAPITAL — landing", estado, "",
];

/** El evento `e` que Sheets le pasa a onEdit al editar `[fila, columna]` de `hoja`. */
const eventoEdicion = (hoja, fila, columna, numFilas = 1, numColumnas = 1) => ({
  range: hoja.getRange(fila, columna, numFilas, numColumnas),
});

const estadoDe = (hojaLeads, fila) => hojaLeads.getRange(fila, 16, 1, 1).getDisplayValues()[0][0];

test("onEdit CONSERVA el estado IMPORTADO al editar otra columna de la fila", () => {
  const { gs, hojaLeads } = montar({ filasLeads: [filaConEstado("IMPORTADO ✓")] });

  gs.onEdit(eventoEdicion(hojaLeads, 2, 1)); // se edita el nombre (columna A)

  assert.equal(estadoDe(hojaLeads, 2), "IMPORTADO ✓",
    "una fila ya importada no debe volver a quedar pendiente de reintento");
});

// F2.b [D-4] (identidad unificada): con la identidad encendida el CRM responde «YA ES
// CLIENTE (asesor: X): reingreso registrado en su ficha». Es una escritura confirmada
// (la nota de reingreso ya está en la ficha): ni se reintenta ni se limpia al editar.
test("F2.b D-4: «YA ES CLIENTE» es una categoría propia (ya_cliente), no un error a reintentar", () => {
  const { gs } = montar({ filasLeads: [filaConEstado("IMPORTADO ✓")] });
  assert.equal(gs.categoriaResultadoImportacion({
    resultado: "ya_cliente",
    estado: "YA ES CLIENTE (asesor: Ana Pérez): reingreso registrado en su ficha",
  }), "ya_cliente");
  assert.equal(gs.categoriaResultadoImportacion({ estado: "YA ES CLIENTE" }), "ya_cliente",
    "un edge que solo mande el estado también se entiende");
  assert.equal(gs.categoriaResultadoImportacion({ resultado: "ya_cliente", estado: "DUPLICADO: ya existe en el CRM" }), null,
    "estado y resultado contradictorios = respuesta ambigua (se reintenta)");
});

test("onEdit CONSERVA «YA ES CLIENTE»: reenviar esa fila anotaría OTRO reingreso en la ficha", () => {
  const ESTADO = "YA ES CLIENTE (asesor: Ana Pérez): reingreso registrado en su ficha";
  const { gs, hojaLeads } = montar({ filasLeads: [filaConEstado(ESTADO)] });

  gs.onEdit(eventoEdicion(hojaLeads, 2, 1)); // se edita el nombre (columna A)

  assert.equal(estadoDe(hojaLeads, 2), ESTADO, "una fila «ya es cliente» no debe volver a quedar pendiente");
});

test("onEdit SIGUE limpiando DUPLICADO/RECHAZADO/ERROR — esas sí hay que reintentarlas", () => {
  const { gs, hojaLeads } = montar({
    filasLeads: [
      filaConEstado("DUPLICADO: ya existe en el CRM"),
      filaConEstado("RECHAZADO: sin monto"),
      filaConEstado("ERROR temporal: el CRM no confirmó esta fila — se reintenta solo"),
    ],
  });

  gs.onEdit(eventoEdicion(hojaLeads, 2, 1, 3, 1)); // se editan las 3 filas a la vez (columna A)

  assert.equal(estadoDe(hojaLeads, 2), "", "DUPLICADO debía quedar reintentable");
  assert.equal(estadoDe(hojaLeads, 3), "", "RECHAZADO debía quedar reintentable");
  assert.equal(estadoDe(hojaLeads, 4), "", "ERROR temporal debía quedar reintentable");
});

test("onEdit trata cada fila por su PROPIO estado, no por el de la primera", () => {
  // Defensa contra el mutante obvio: leer el estado UNA vez fuera del bucle y
  // aplicarlo a todas las filas del rango editado.
  const { gs, hojaLeads } = montar({
    filasLeads: [filaConEstado("IMPORTADO ✓"), filaConEstado("RECHAZADO: sin monto")],
  });

  gs.onEdit(eventoEdicion(hojaLeads, 2, 1, 2, 1)); // ambas filas, columna A

  assert.equal(estadoDe(hojaLeads, 2), "IMPORTADO ✓", "la importada no se toca");
  assert.equal(estadoDe(hojaLeads, 3), "", "la rechazada sí se reintenta");
});

test("onEdit sigue sin tocar nada si SOLO se edita la propia columna de estado", () => {
  const { gs, hojaLeads } = montar({ filasLeads: [filaConEstado("IMPORTADO ✓")] });

  gs.onEdit(eventoEdicion(hojaLeads, 2, gs.COL_ESTADO)); // se edita P, no A–O

  assert.equal(estadoDe(hojaLeads, 2), "IMPORTADO ✓", "editar la propia columna no debe limpiarla");
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

// ── El día que el origen cambió de formato de fecha (2026-09-01) ─────────────

test("el origen empieza a escribir MM/DD a media mañana y los leads siguen entrando", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();

  // El corte, y las dos formas de escribir el día 1 del mes siguiente.
  const corte = mundo.gs.FECHA_CORTE;
  const siguiente = new Date(Date.UTC(+corte.slice(0, 4), +corte.slice(5, 7), 1))
    .toISOString().slice(0, 10);
  const alReves = `${siguiente.slice(5, 7)}/${siguiente.slice(8, 10)}/${siguiente.slice(0, 4)}`;
  const vieja = `23/07/${+corte.slice(0, 4) - 1}`; // backlog de verdad, del año pasado

  // El origen se REESCRIBE en vez de usar appendRow: escribir por ahí haría que el
  // simulador interpretara el texto con SU locale, y lo que aquí se prueba es
  // justamente el texto que el origen dibuja cuando cambia de formato.
  mundo.origen.hojas[0] = new Hoja("landing", 111, [
    CAB_LANDING,
    filaLanding(1),                        // la de siempre, por debajo de la marca
    filaLanding(7, alReves + " 10:20"),     // llega nueva, con el mes por delante
    filaLanding(8, vieja + " 09:00"),       // llega nueva, pero dice ser del año pasado
  ]);

  const r = mundo.gs.procesar(true);

  // Las dos entran: una porque su fecha es ambigua y manda la posición, la otra
  // porque su fecha es imposible (nueva y anterior al corte) y manda la posición.
  const filas = leadsEscritos(mundo.hojaLeads);
  assert.deepEqual(filas.map((f) => f[1]), ["+51918000007", "+51918000008"],
    "algún lead nuevo murió en el corte, como en producción");
  assert.equal(r.aceptados.length, 2);
  assert.equal(r.fechasImposibles, 1, "no se contó la fecha imposible");
  assert.match(filas[1][11], /imposible/i, "el lead no avisa de su fecha falsa en la Nota");
});

test("la fecha imposible levanta un aviso en el panel, y se apaga cuando deja de pasar", () => {
  const mundo = montar({ landing: [filaLanding(1)] });
  mundo.gs.inicializarMarcas();
  const corte = mundo.gs.FECHA_CORTE;
  const vieja = `23/07/${+corte.slice(0, 4) - 1}`;
  mundo.origen.hojas[0] = new Hoja("landing", 111, [
    CAB_LANDING, filaLanding(1), filaLanding(9, vieja + " 09:00"),
  ]);

  mundo.gs.corridaProgramada();
  const avisos = () => mundo.gs.leerEstado().avisos || {};
  assert.ok(avisos()["fecha-imposible"], "el origen corrompió una fecha y el panel no dice nada");

  // El origen se arregla: llega una fila normal y el aviso tiene que apagarse.
  mundo.espia.ponerReloj("2026-08-18 09:20"); // otro día: la corrida vuelve a ser completa
  mundo.origen.hojas[0].appendRow(filaLanding(10));
  mundo.gs.corridaProgramada();
  assert.equal(avisos()["fecha-imposible"], undefined, "el aviso no se apaga solo: enseña a ignorar el panel");
});

test("rescatar filas ya miradas: la marca desanda y los leads vuelven a entrar", () => {
  // Tres filas SIN fecha ya estaban cuando se puso la frontera: son historia y ninguna
  // entra. Es la forma exacta de las 34 del 2026-09-01 después de que la marca les
  // pasara por encima.
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2), filaLanding(3)] });
  mundo.gs.inicializarMarcas();
  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, 4);
  assert.equal(mundo.gs.procesar(true).aceptados.length, 0, "entró historia y no debía");

  // Rosa desanda la frontera hasta la fila 2: las dos de abajo vuelven a mirarse.
  mundo.espia.respuestas.push({ boton: "OK", texto: "landing" }); // ¿qué pestaña?
  mundo.espia.respuestas.push({ boton: "OK", texto: "2" });       // ¿hasta qué fila?
  mundo.espia.respuestas.push({ boton: "OK" });                   // confirma
  const r = mundo.gs.retrocederMarca();

  assert.deepEqual({ de: r.de, a: r.a, recuperadas: r.recuperadas }, { de: 4, a: 2, recuperadas: 2 });
  assert.equal(leadsEscritos(mundo.hojaLeads).length, 0, "el rescate importó leads y no debía");

  const despues = mundo.gs.procesar(true);
  assert.equal(despues.incidencias.length, 0,
    "la pestaña se detuvo: el ancla no se recalculó en la fila nueva");
  assert.deepEqual(leadsEscritos(mundo.hojaLeads).map((f) => f[1]),
    ["+51918000002", "+51918000003"]);
});

test("el rescate se echa atrás si quien mira cancela", () => {
  const mundo = montar({ landing: [filaLanding(1), filaLanding(2)] });
  mundo.gs.inicializarMarcas();
  const antes = marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila;

  mundo.espia.respuestas.push({ boton: "OK", texto: "landing" });
  mundo.espia.respuestas.push({ boton: "OK", texto: "2" });
  mundo.espia.respuestas.push({ boton: "CANCEL" }); // se lo piensa mejor
  assert.equal(mundo.gs.retrocederMarca(), null);

  assert.equal(marcasDe(mundo.gs, mundo.destino)["111"].ultimaFila, antes,
    "movió la frontera después de un CANCELAR");
});
