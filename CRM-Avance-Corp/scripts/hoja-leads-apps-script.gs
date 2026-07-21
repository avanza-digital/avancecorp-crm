/**
 * Conector hoja "Leads AVANCE CORP — captura para CRM" → CRM (crm.leads).
 * ─────────────────────────────────────────────────────────────────────────────
 * Copia de respaldo del Apps Script que vive DENTRO de la hoja de Google
 * (Extensiones → Apps Script). Si la hoja pierde el script, se pega este
 * archivo tal cual y se ejecuta configurar() una vez.
 *
 * Qué hace: cada 5 minutos toma las filas cuya columna P (Estado importación)
 * está vacía, las manda al edge `crm-importar-leads` (valida, deduplica por
 * teléfono e inserta), y escribe el resultado en la columna P de cada fila:
 *   IMPORTADO ✓ · DUPLICADO: ya existe · RECHAZADO: <motivo concreto>
 * El equipo corrige la fila rechazada, BORRA su estado, y el siguiente ciclo
 * la reintenta. Sin estado vacío no hay reenvío: no se duplica trabajo.
 *
 * Seguridad: el edge exige el secreto x-importar-secret además del anon key.
 * El secreto NO vive en este código (rotado 2026-07-21): se lee de las
 * Propiedades del script — Apps Script → ⚙️ Configuración del proyecto →
 * Propiedades del script → agregar IMPORTAR_SECRET con el valor vigente.
 * (El ANON_KEY sí puede ir inline: es la llave PÚBLICA del proyecto.)
 * Solo quien edita el proyecto de Apps Script ve la propiedad; lo único que
 * permite es INSERTAR leads (lo mismo que ya hace llenando filas). No lee datos.
 */

const EDGE_URL =
  "https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-importar-leads";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRjdHFjYnpuZWtjeXhoanVqdWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwNzU4NzAsImV4cCI6MjA5MjY1MTg3MH0.2Rz9Nq05Duk1vQRZb0R_PtSX0ZiRbxP82JAPKusmsSo";
// Secreto compartido con el edge — SOLO de Propiedades del script (jamás inline).
const IMPORTAR_SECRET =
  PropertiesService.getScriptProperties().getProperty("IMPORTAR_SECRET");

const COL_ESTADO = 16; // columna P
const MAX_POR_LOTE = 200;

/**
 * EJECUTAR UNA VEZ (botón ▶ con "configurar" seleccionado): crea el encabezado
 * de la columna de estado y el trigger de cada 5 minutos. Re-ejecutarla es
 * seguro (no duplica triggers).
 */
function configurar() {
  const hoja = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  hoja.getRange(1, COL_ESTADO).setValue("Estado importación (automático — no tocar)");
  hoja.setColumnWidth(COL_ESTADO, 260);

  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === "importarLeads") ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger("importarLeads").timeBased().everyMinutes(5).create();

  importarLeads(); // primera pasada inmediata, para ver resultados al instante
}

/** Corre cada 5 minutos por trigger. También se puede ejecutar a mano. */
function importarLeads() {
  // Sin la propiedad IMPORTAR_SECRET el edge rechazaría todo con 401: mejor
  // fallar aquí con un mensaje accionable (visible en Ejecuciones del script).
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

    // getDisplayValues: todo como TEXTO tal cual se ve (evita que Sheets
    // convierta teléfonos a número o fechas a Date y rompa el formato).
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
      // reintentará solo, porque el estado con "ERROR" se limpia al final.
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
