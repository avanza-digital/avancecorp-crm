/**
 * Conector hoja "Leads AVANCE CORP — captura para CRM" → CRM (crm.leads).
 * ─────────────────────────────────────────────────────────────────────────────
 * Copia de respaldo del Apps Script que vive DENTRO de la hoja de Google
 * (Extensiones → Apps Script). Si la hoja pierde el script, se pega este archivo
 * tal cual y se ejecuta configurar() UNA VEZ.
 *
 * DOS partes:
 *  1) configurar()  → deja la hoja "a prueba de errores": encabezados, menús
 *     desplegables (moneda/canal/interés/género/consentimiento), columnas de
 *     números como TEXTO (evita que Sheets reformatee DNI/teléfono/capital),
 *     colores en la columna de estado, y el disparador de importación cada 5 min.
 *  2) importarLeads() → cada 5 min manda las filas nuevas al edge, valida,
 *     deduplica por teléfono e inserta, y escribe el resultado en la columna P.
 *
 * Además onEdit() borra el estado de una fila apenas la editas → se re-importa
 * sola en el siguiente ciclo (no hay que borrar el estado a mano).
 *
 * Seguridad: el edge exige el secreto x-importar-secret además del anon key. El
 * secreto NO vive en este código: se lee de las Propiedades del script (⚙️
 * Configuración del proyecto → Propiedades del script → IMPORTAR_SECRET).
 * (El ANON_KEY sí va inline: es la llave PÚBLICA del proyecto.)
 */

const EDGE_URL =
  "https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-importar-leads";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRjdHFjYnpuZWtjeXhoanVqdWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwNzU4NzAsImV4cCI6MjA5MjY1MTg3MH0.2Rz9Nq05Duk1vQRZb0R_PtSX0ZiRbxP82JAPKusmsSo";
const IMPORTAR_SECRET =
  PropertiesService.getScriptProperties().getProperty("IMPORTAR_SECRET");

const COL_ESTADO = 16; // columna P
const MAX_POR_LOTE = 200;
const FILAS_CONFIG = 2000; // hasta dónde se aplican formatos/menús (holgado)

// Encabezados y menús: única fuente de verdad de la estructura de la hoja.
const ENCABEZADOS = [
  "Nombre completo *",
  "Teléfono *",
  "Capital estimado *",
  "Moneda *",
  "Canal de origen *",
  "Correo",
  "DNI",
  "Género",
  "Fecha de nacimiento",
  "Distrito",
  "Interés",
  "Nota",
  "Vendedor asignado (correo)",
  "¿Autorizó contacto?",
  "Fuente del consentimiento",
  "Estado importación (automático — no tocar)",
];
// Menús desplegables por columna (1-indexado). Evitan typos y celdas cruzadas.
const MENUS = {
  4: ["PEN", "USD"], // Moneda
  5: ["Referido", "LANDING", "FORMULARIO", "Wallking", "Otro"], // Canal
  8: ["F", "M"], // Género
  11: ["Nuevo", "Renovación", "Upgrade"], // Interés
  14: ["SI", "NO"], // ¿Autorizó contacto?
};
// Columnas que se fuerzan a TEXTO para que Sheets no las reinterprete como
// número/fecha (la causa del "DNI inválido"): teléfono, capital, DNI, fecha nac.
const COLS_TEXTO = [2, 3, 7, 9];

/**
 * EJECUTAR UNA VEZ (selecciona "configurar" y pulsa ▶). Idempotente: re-correrla
 * es seguro. Deja la hoja lista y arranca el disparador de 5 min.
 */
function configurar() {
  const hoja = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];

  // 1) Encabezados + estilo + fila congelada.
  const cab = hoja.getRange(1, 1, 1, ENCABEZADOS.length);
  cab.setValues([ENCABEZADOS])
    .setFontWeight("bold")
    .setBackground("#1f2937")
    .setFontColor("#ffffff")
    .setWrap(true)
    .setVerticalAlignment("middle");
  hoja.setFrozenRows(1);
  hoja.setRowHeight(1, 46);

  // 2) Columnas numéricas/fecha como TEXTO (adiós separadores de miles y fechas
  //    auto-convertidas). El resto del área de datos también a texto por higiene.
  const areaDatos = hoja.getRange(2, 1, FILAS_CONFIG, ENCABEZADOS.length);
  areaDatos.setNumberFormat("@"); // '@' = texto sin formato
  COLS_TEXTO.forEach(function (c) {
    hoja.getRange(2, c, FILAS_CONFIG, 1).setNumberFormat("@");
  });

  // 3) Menús desplegables (lista cerrada: no deja escribir un valor fuera).
  Object.keys(MENUS).forEach(function (col) {
    const regla = SpreadsheetApp.newDataValidation()
      .requireValueInList(MENUS[col], true)
      .setAllowInvalid(false)
      .setHelpText("Elige un valor de la lista.")
      .build();
    hoja.getRange(2, Number(col), FILAS_CONFIG, 1).setDataValidation(regla);
  });

  // 4) Anchos de columna cómodos.
  const anchos = [190, 130, 130, 90, 150, 210, 110, 80, 140, 130, 120, 240, 220, 140, 200, 260];
  anchos.forEach(function (w, i) { hoja.setColumnWidth(i + 1, w); });

  // 5) Colores automáticos en la columna de estado (verde/gris/rojo/azul).
  const rangoEstado = hoja.getRange(2, COL_ESTADO, FILAS_CONFIG, 1);
  const regla = function (texto, bg, fg) {
    return SpreadsheetApp.newConditionalFormatRule()
      .whenTextStartsWith(texto)
      .setBackground(bg)
      .setFontColor(fg)
      .setRanges([rangoEstado])
      .build();
  };
  hoja.setConditionalFormatRules([
    regla("IMPORTADO", "#d9ead3", "#1e4620"), // verde
    regla("DUPLICADO", "#fff2cc", "#7f6000"), // ámbar
    regla("RECHAZADO", "#f4cccc", "#990000"), // rojo
    regla("ERROR", "#cfe2f3", "#0b5394"),     // azul (temporal, se reintenta)
  ]);

  // 6) Disparador cada 5 min (sin duplicar) + primera pasada inmediata.
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === "importarLeads") ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger("importarLeads").timeBased().everyMinutes(5).create();

  SpreadsheetApp.getActiveSpreadsheet().toast(
    "Hoja configurada. Escribe leads desde la fila 2; se importan solos cada 5 min.",
    "Listo", 6);
  importarLeads();
}

/**
 * Disparador SIMPLE: al editar cualquier campo (A–O) de una fila de datos, borra
 * su estado (columna P) para que el siguiente ciclo la reintente. Corregir una
 * fila rechazada = simplemente arreglarla; no hay que tocar la columna de estado.
 */
function onEdit(e) {
  if (!e || !e.range) return;
  const hoja = e.range.getSheet();
  if (hoja.getIndex() !== 1) return; // solo la primera hoja
  const desde = e.range.getRow();
  const hasta = e.range.getLastRow();
  const col = e.range.getColumn();
  const colFin = e.range.getLastColumn();
  if (desde < 2) return;                 // no la cabecera
  if (col >= COL_ESTADO) return;         // no cuando se edita la propia col. de estado
  for (let r = Math.max(desde, 2); r <= hasta; r++) {
    hoja.getRange(r, COL_ESTADO).clearContent();
  }
}

/** Corre cada 5 minutos por disparador. También se puede ejecutar a mano. */
function importarLeads() {
  if (!IMPORTAR_SECRET) {
    throw new Error(
      "Falta IMPORTAR_SECRET: agrégala en ⚙️ Configuración del proyecto → Propiedades del script."
    );
  }
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(0)) return; // ya hay una pasada corriendo

  try {
    const hoja = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
    const ultimaFila = hoja.getLastRow();
    if (ultimaFila < 2) return;

    // getDisplayValues: texto tal cual se ve (con columnas en formato TEXTO,
    // el DNI/teléfono/capital llegan limpios, sin separadores de miles).
    const datos = hoja.getRange(2, 1, ultimaFila - 1, COL_ESTADO).getDisplayValues();

    const pendientes = [];
    for (let i = 0; i < datos.length; i++) {
      const fila = datos[i];
      const estado = String(fila[COL_ESTADO - 1]).trim();
      const vacia = fila.slice(0, COL_ESTADO - 1).every(function (c) {
        return String(c).trim() === "";
      });
      // Pendiente = sin estado, o con aviso de error temporal (se reintenta).
      const reintentable = estado === "" || estado.indexOf("ERROR temporal") === 0;
      if (!reintentable || vacia) continue;
      pendientes.push({
        fila: i + 2, // número real de fila en la hoja
        nombre: fila[0],
        telefono: fila[1],
        capital: fila[2],
        moneda: fila[3],
        canal: fila[4],
        correo: fila[5],
        dni: fila[6],
        genero: fila[7],
        fecha_nacimiento: fila[8],
        distrito: fila[9],
        interes: fila[10],
        nota: fila[11],
        vendedor_correo: fila[12],
        autorizo: fila[13],
        fuente_consentimiento: fila[14],
      });
      if (pendientes.length >= MAX_POR_LOTE) break; // el resto, al siguiente ciclo
    }
    if (pendientes.length === 0) return;

    const respuesta = UrlFetchApp.fetch(EDGE_URL, {
      method: "post",
      contentType: "application/json",
      headers: {
        Authorization: "Bearer " + ANON_KEY,
        "x-importar-secret": IMPORTAR_SECRET,
      },
      payload: JSON.stringify({ filas: pendientes }),
      muteHttpExceptions: true,
    });

    if (respuesta.getResponseCode() !== 200) {
      // Error global (red/servidor): se anota en la primera fila del lote y se
      // reintentará solo, porque el estado con "ERROR temporal" es reintentable.
      const aviso = "ERROR temporal (" + respuesta.getResponseCode() + ") — se reintenta solo";
      hoja.getRange(pendientes[0].fila, COL_ESTADO).setValue(aviso);
      return;
    }

    const resultados = JSON.parse(respuesta.getContentText()).resultados || [];
    resultados.forEach(function (r) {
      if (r.fila >= 2) hoja.getRange(r.fila, COL_ESTADO).setValue(r.estado);
    });
  } finally {
    lock.releaseLock();
  }
}
