/**
 * Conector hoja "Leads AVANCE CORP — captura para CRM" → CRM (crm.leads).
 * ─────────────────────────────────────────────────────────────────────────────
 * Copia de respaldo del Apps Script que vive DENTRO de la hoja de Google
 * (Extensiones → Apps Script). Si la hoja pierde el script, se pega este archivo
 * tal cual y se ejecuta configurar() UNA VEZ.
 *
 * TRES operaciones, deliberadamente SEPARADAS (2026-08-16):
 *  1) prepararHoja()    → deja la hoja "a prueba de errores": encabezados, menús
 *     desplegables (moneda/canal/interés/género/consentimiento), columnas de
 *     números como TEXTO (evita que Sheets reformatee DNI/teléfono/capital) y
 *     colores en la columna de estado. NO crea disparadores NI importa nada.
 *  2) activarConector() → enciende el disparador de importación cada 5 min.
 *     apagarConector() lo apaga (es la vuelta atrás).
 *  3) importarLeads()   → cada 5 min manda las filas nuevas al edge, valida,
 *     deduplica por teléfono e inserta, y escribe el resultado en la columna P.
 *
 * ⚠️ ANTES eran UNA sola función, `configurar()`, que daba formato, creaba el
 * disparador Y lanzaba una importación. Tres cosas irreversibles en un botón: no
 * había forma de preparar la hoja sin encender la máquina. Separarlas es lo que
 * permite el arranque controlado (preparar → mirar → recién entonces encender).
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

/**
 * El secreto se lee DENTRO de la función que lo usa, nunca aquí arriba.
 *
 * El código de nivel superior de TODOS los archivos del proyecto se evalúa en CADA
 * ejecución — incluidos los disparadores simples (`onOpen` del puente, `onEdit` de
 * aquí), que corren sin autorización. Un `PropertiesService` en el nivel superior
 * ata el menú y la edición de celdas a un servicio que puede no estar disponible
 * ahí, y además congela el secreto en el momento de cargar: rotarlo obligaría a
 * reiniciar. Leerlo al usarlo cuesta lo mismo y no tiene ninguna de las dos pegas.
 */
function secretoDeImportacion() {
  const s = PropertiesService.getScriptProperties().getProperty("IMPORTAR_SECRET");
  if (!s) {
    throw new Error(
      "Falta IMPORTAR_SECRET: agrégala en ⚙️ Configuración del proyecto → Propiedades del script."
    );
  }
  return s;
}

/** La pestaña de leads se llama por su NOMBRE, nunca por su posición. */
const HOJA_LEADS = "LEADS";

const COL_ESTADO = 16; // columna P
const MAX_POR_LOTE = 200;

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
  "Teléfono alternativo",
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
const COLS_TEXTO = [2, 3, 7, 9, 17];

/**
 * La pestaña de leads, por NOMBRE. Nunca `getSheets()[0]`: basta con que alguien
 * arrastre una pestaña —o que el puente cree una de memoria en el sitio equivocado—
 * para que el conector se ponga a importar huellas creyendo que son leads.
 */
function hojaDeLeads(libro) {
  const l = libro || SpreadsheetApp.getActiveSpreadsheet();
  const hoja = l.getSheetByName(HOJA_LEADS);
  if (!hoja) {
    throw new Error(
      "No encuentro la pestaña \"" + HOJA_LEADS + "\" en esta hoja. " +
      "Ejecuta prepararHoja() una vez, o renombra la pestaña de leads así."
    );
  }
  return hoja;
}

/** Igual, pero para preparar: si no existe, la crea (o renombra la hoja virgen). */
function hojaDeLeadsOCrear(libro) {
  const existente = libro.getSheetByName(HOJA_LEADS);
  if (existente) return existente;
  const todas = libro.getSheets();
  if (todas.length === 1 && todas[0].getLastRow() === 0) {
    return todas[0].setName(HOJA_LEADS); // libro recién creado: "Hoja 1" → LEADS
  }
  return libro.insertSheet(HOJA_LEADS, libro.getNumSheets());
}

/**
 * PASO 1 — Deja la hoja lista. Idempotente y SIN efectos: no crea disparadores ni
 * importa nada, así que se puede ejecutar con toda tranquilidad para mirar el
 * resultado antes de encender la máquina.
 */
function prepararHoja() {
  const libro = SpreadsheetApp.getActiveSpreadsheet();
  const hoja = hojaDeLeadsOCrear(libro);

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

  // 2) Formato de texto y menús en TODA la rejilla que hoy existe — no en un número
  //    fijo de filas. El "2000" de antes no era holgura: era un techo exacto, y la
  //    hoja acabó midiendo justo 2001 filas. A partir de ahí, cada fila nueva nacía
  //    sin formato y Sheets volvía a "arreglar" el teléfono y el DNI.
  prepararTramo(hoja, 2, hoja.getMaxRows() - 1);

  // 3) Anchos de columna cómodos.
  const anchos = [190, 130, 130, 90, 150, 210, 110, 80, 140, 130, 120, 240, 220, 140, 200, 260, 150];
  anchos.forEach(function (w, i) { hoja.setColumnWidth(i + 1, w); });

  // 4) Colores automáticos en la columna de estado (verde/ámbar/rojo/azul). El rango
  //    se toma de la rejilla real por el mismo motivo que arriba.
  const rangoEstado = hoja.getRange(2, COL_ESTADO, Math.max(hoja.getMaxRows() - 1, 1), 1);
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
    regla("YA ES CLIENTE", "#d9d2e9", "#20124d"), // lila (F2.b: la persona ya es cliente; reingreso anotado en su ficha)
    regla("RECHAZADO", "#f4cccc", "#990000"), // rojo
    regla("ERROR", "#cfe2f3", "#0b5394"),     // azul (temporal, se reintenta)
  ]);

  libro.toast(
    "Hoja preparada (" + hoja.getMaxRows() + " filas con formato y menús). " +
    "NO se encendió nada: para eso, \"Encender el conector\".",
    "Listo", 8);
  return hoja.getMaxRows();
}

/**
 * Aplica formato de texto y menús a un tramo de filas. Se usa en dos momentos: al
 * preparar la hoja entera y, sobre todo, al AMPLIARLA — las filas recién insertadas
 * nacen crudas, y son justo donde Sheets reinterpreta el DNI como número.
 */
function prepararTramo(hoja, desdeFila, cuantas) {
  if (cuantas < 1) return;
  hoja.getRange(desdeFila, 1, cuantas, ENCABEZADOS.length).setNumberFormat("@");
  COLS_TEXTO.forEach(function (c) {
    hoja.getRange(desdeFila, c, cuantas, 1).setNumberFormat("@");
  });
  Object.keys(MENUS).forEach(function (col) {
    const regla = SpreadsheetApp.newDataValidation()
      .requireValueInList(MENUS[col], true)
      .setAllowInvalid(false)
      .setHelpText("Elige un valor de la lista.")
      .build();
    hoja.getRange(desdeFila, Number(col), cuantas, 1).setDataValidation(regla);
  });
}

/**
 * Garantiza que la hoja llega hasta `filasNecesarias`, con formato. La llama el
 * PUENTE antes de escribir (los dos archivos comparten ámbito global).
 *
 * Sin esto, escribir más allá de la última fila de la rejilla lanza "out of bounds"
 * y la pasada muere DESPUÉS de haber leído las 12.000 filas del origen. Con 500
 * leads por pasada y una hoja de 2001 filas, la quinta pasada llena reventaba.
 *
 * Devuelve cuántas filas se añadieron (0 = no hizo falta).
 */
function asegurarCapacidadLeads(hoja, filasNecesarias) {
  const antes = hoja.getMaxRows();
  const faltan = Number(filasNecesarias) - antes;
  if (faltan <= 0) return 0;
  // Un colchón: crecer de 500 en 500 evita insertar fila a fila en cada pasada.
  const aAnadir = Math.max(faltan, 500);
  hoja.insertRowsAfter(antes, aAnadir);
  prepararTramo(hoja, antes + 1, aAnadir);
  return aAnadir;
}

/**
 * PASO 2 — Enciende la importación automática cada 5 min. Idempotente: quita los
 * suyos antes de crear, así que no duplica ciclos.
 */
function activarConector() {
  secretoDeImportacion(); // falla AQUÍ si falta, no dentro del primer ciclo silencioso
  hojaDeLeads();          // y falla aquí si la pestaña no está preparada
  const quitados = apagarConector(true);
  ScriptApp.newTrigger("importarLeads").timeBased().everyMinutes(5).create();
  SpreadsheetApp.getActiveSpreadsheet().toast(
    "Conector ENCENDIDO: las filas nuevas de la hoja suben al CRM cada 5 minutos." +
    (quitados ? " (Se reemplazó " + quitados + " disparador anterior.)" : ""),
    "Listo", 8);
}

/** Apaga la importación automática. Es la vuelta atrás del paso 2. */
function apagarConector(silencioso) {
  let n = 0;
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === "importarLeads") { ScriptApp.deleteTrigger(t); n++; }
  });
  if (!silencioso) {
    SpreadsheetApp.getActiveSpreadsheet().toast(
      n ? "Conector APAGADO (" + n + " disparador(es) quitado(s)). La hoja se queda como está."
        : "El conector ya estaba apagado.",
      "Listo", 6);
  }
  return n;
}

/**
 * Quedó como aviso a propósito: era una sola función que daba formato, encendía el
 * disparador Y lanzaba una importación. Si alguien la ejecuta por costumbre, es
 * mejor un mensaje claro que una importación no pedida.
 */
function configurar() {
  throw new Error(
    "configurar() ya no existe: hacía tres cosas irreversibles de golpe.\n\n" +
    "Ahora son dos pasos separados:\n" +
    "  1) prepararHoja()     — formatos y menús, no enciende nada\n" +
    "  2) activarConector()  — enciende la importación cada 5 min\n\n" +
    "Y apagarConector() para la vuelta atrás."
  );
}

/**
 * Disparador SIMPLE: al editar cualquier campo de datos (A–O o Q), borra
 * su estado (columna P) para que el siguiente ciclo la reintente. Corregir una
 * fila rechazada = simplemente arreglarla; no hay que tocar la columna de estado.
 *
 * EXCEPCIÓN — una fila ya IMPORTADA no se limpia. El importador solo INSERTA,
 * nunca actualiza: reintentar una fila que ya entró no corrige nada en el CRM,
 * el dedup la encuentra a sí misma y la reetiqueta "DUPLICADO", pisando el
 * "IMPORTADO ✓" real con una etiqueta que confunde (visto el 2026-08-25: un
 * lead que sí había entrado parecía, por la hoja, que nunca lo había hecho).
 * Si de verdad hace falta forzar el reintento, se borra la celda P a mano —
 * eso lo sigue permitiendo la salvedad de la línea de abajo.
 */
function onEdit(e) {
  if (!e || !e.range) return;
  const hoja = e.range.getSheet();
  if (hoja.getName() !== HOJA_LEADS) return; // por NOMBRE, no por posición
  const desde = e.range.getRow();
  const hasta = e.range.getLastRow();
  const col = e.range.getColumn();
  const colFin = e.range.getLastColumn();
  if (desde < 2) return;                 // no la cabecera
  if (col === COL_ESTADO && colFin === COL_ESTADO) return; // solo la propia col. de estado
  if (col > ENCABEZADOS.length) return;  // fuera de la tabla
  for (let r = Math.max(desde, 2); r <= hasta; r++) {
    const celda = hoja.getRange(r, COL_ESTADO);
    const estado = String(celda.getValue()).trim();
    // IMPORTADO y YA ES CLIENTE son escrituras confirmadas en el CRM: reenviarlas
    // reetiquetaría la fila (DUPLICADO) o anotaría OTRO reingreso en la ficha.
    if (estado.indexOf("IMPORTADO") === 0 || estado.indexOf("YA ES CLIENTE") === 0) continue;
    celda.clearContent();
  }
}

/** Estado único para una fila que el CRM no confirmó; siempre queda reintentable. */
function estadoErrorTemporalImportacion(detalle) {
  const d = String(detalle || "").replace(/\s+/g, " ").trim();
  return d
    ? "ERROR temporal (" + d.slice(0, 80) + ") — se reintenta solo"
    : "ERROR temporal: el CRM no confirmó esta fila — se reintenta solo";
}

/**
 * Lee el contrato nuevo (`resultado`) y conserva compatibilidad con una versión
 * anterior del edge que solo enviaba `estado`. Si ambos vienen y se contradicen,
 * la respuesta es ambigua: esa fila se reintenta en vez de inventar un resultado.
 */
function categoriaResultadoImportacion(resultado) {
  if (!resultado || typeof resultado !== "object") return null;
  const declarada = String(resultado.resultado || "").trim().toLowerCase();
  const estado = String(resultado.estado || "").trim();
  let porEstado = null;
  if (estado.indexOf("IMPORTADO") === 0) porEstado = "importado";
  else if (estado.indexOf("DUPLICADO") === 0) porEstado = "duplicado";
  else if (estado.indexOf("YA ES CLIENTE") === 0) porEstado = "ya_cliente";
  else if (estado.indexOf("RECHAZADO") === 0) porEstado = "rechazado";
  else if (estado.indexOf("ERROR temporal") === 0) porEstado = "error_temporal";

  const validas = ["importado", "duplicado", "ya_cliente", "rechazado", "error_temporal"];
  if (declarada && validas.indexOf(declarada) < 0) return null;
  if (!porEstado) return null;
  if (declarada && porEstado && declarada !== porEstado) return null;
  return declarada || porEstado;
}

/**
 * Concilia EXACTAMENTE las filas enviadas con lo que devolvió el CRM.
 *
 * - resultado válido y único → conserva IMPORTADO/DUPLICADO/YA ES CLIENTE/RECHAZADO/ERROR;
 * - fila ausente, repetida o respuesta ambigua → ERROR temporal reintentable;
 * - resultados de filas que no pertenecían a esta corrida → se ignoran.
 *
 * Así ninguna corrida deja filas en limbo ni atribuye a una fila el resultado de
 * otra, incluso ante respuestas parciales o deformadas.
 */
function conciliarResultadosImportacion(pendientes, resultadosCrm) {
  const esperadas = Object.create(null);
  const confirmadas = Object.create(null);
  const ambiguas = Object.create(null);
  pendientes.forEach(function (p) { esperadas[String(p.fila)] = true; });

  if (Array.isArray(resultadosCrm)) {
    resultadosCrm.forEach(function (r) {
      const fila = Number(r && r.fila);
      const clave = String(fila);
      if (!Number.isInteger(fila) || !esperadas[clave]) return;
      if (Object.prototype.hasOwnProperty.call(confirmadas, clave)) {
        ambiguas[clave] = true;
        return;
      }
      const categoria = categoriaResultadoImportacion(r);
      const estado = String(r && r.estado || "").replace(/\s+/g, " ").trim().slice(0, 300);
      confirmadas[clave] = categoria && estado
        ? { fila: fila, estado: estado }
        : { fila: fila, estado: estadoErrorTemporalImportacion("") };
    });
  }

  return pendientes.map(function (p) {
    const clave = String(p.fila);
    if (ambiguas[clave] || !confirmadas[clave]) {
      return { fila: p.fila, estado: estadoErrorTemporalImportacion("") };
    }
    return confirmadas[clave];
  });
}

function escribirConciliacionImportacion(hoja, conciliados) {
  conciliados.forEach(function (r) {
    hoja.getRange(r.fila, COL_ESTADO).setValue(r.estado);
  });
}

/** Corre cada 5 minutos por disparador. También se puede ejecutar a mano. */
function importarLeads() {
  const secreto = secretoDeImportacion(); // lanza con mensaje claro si falta
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(0)) return; // ya hay una pasada corriendo

  try {
    const hoja = hojaDeLeads();
    const ultimaFila = hoja.getLastRow();
    if (ultimaFila < 2) return;

    // getDisplayValues: texto tal cual se ve (con columnas en formato TEXTO,
    // el DNI/teléfono/capital llegan limpios, sin separadores de miles).
    const datos = hoja.getRange(2, 1, ultimaFila - 1, ENCABEZADOS.length).getDisplayValues();

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
        telefono_alternativo: fila[16],
      });
      if (pendientes.length >= MAX_POR_LOTE) break; // el resto, al siguiente ciclo
    }
    if (pendientes.length === 0) return;

    let respuesta;
    try {
      respuesta = UrlFetchApp.fetch(EDGE_URL, {
        method: "post",
        contentType: "application/json",
        headers: {
          Authorization: "Bearer " + ANON_KEY,
          "x-importar-secret": secreto,
        },
        payload: JSON.stringify({ filas: pendientes }),
        muteHttpExceptions: true,
      });
    } catch (error) {
      escribirConciliacionImportacion(hoja, pendientes.map(function (p) {
        return { fila: p.fila, estado: estadoErrorTemporalImportacion("sin respuesta del CRM") };
      }));
      console.error("crm-importar-leads no respondió: " + String(error));
      return;
    }

    if (respuesta.getResponseCode() !== 200) {
      // Un error global afecta al lote ENTERO. Antes solo se marcaba la primera
      // fila y las demás quedaban sin explicación; ahora todas quedan identificadas.
      const aviso = estadoErrorTemporalImportacion(String(respuesta.getResponseCode()));
      escribirConciliacionImportacion(hoja, pendientes.map(function (p) {
        return { fila: p.fila, estado: aviso };
      }));
      return;
    }

    let cuerpo;
    try {
      cuerpo = JSON.parse(respuesta.getContentText());
    } catch (error) {
      cuerpo = null;
      console.error("crm-importar-leads devolvió JSON inválido: " + String(error));
    }
    const conciliados = conciliarResultadosImportacion(
      pendientes,
      cuerpo && Array.isArray(cuerpo.resultados) ? cuerpo.resultados : []
    );
    escribirConciliacionImportacion(hoja, conciliados);
  } finally {
    lock.releaseLock();
  }
}
