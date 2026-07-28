/**
 * Puente: documento de origen del Drive → hoja "Leads AVANCE CORP — captura para CRM".
 * ─────────────────────────────────────────────────────────────────────────────
 * Rosa deja de transcribir. Este script LEE el documento donde caen los leads por
 * primera vez, se queda solo con los campos que el vendedor necesita, los normaliza
 * al formato exacto que exige el conector (hoja-leads-apps-script.gs) y los escribe
 * en NUESTRA hoja. De ahí, el conector de 5 min los sube solo al CRM.
 *
 * ⚠️ EL DOCUMENTO DE ORIGEN ES DE LA EMPRESA Y NO SE TOCA.
 *    Este archivo abre el origen con openById() y solo llama getSheets/getName/
 *    getDataRange/getDisplayValues. No hay ni un setValue, insertSheet, setName ni
 *    deleteRow sobre `origen` — es auditable con un Ctrl+F: la única variable que
 *    recibe escrituras es `destino` (nuestra hoja).
 *
 * DÓNDE VA: dentro de NUESTRA hoja (Extensiones → Apps Script), como archivo nuevo
 * junto al conector. Quien autorice el script necesita acceso de lectura al origen.
 *
 * CÓMO SE USA: menú "AVANCE CORP" → "Vista previa" (no escribe nada, solo dice qué
 * entraría y qué no) y "Traer leads del origen".
 */

// ── Configuración ────────────────────────────────────────────────────────────

/** Documento de origen (02PLAZOFIJOMAS LANDING). Solo lectura. */
const ORIGEN_ID = "1VriA6vr-QjLDRnyH-sx-sgNwyYNvsNFR1d1JZbRBwEs";

/** Canal por pestaña del origen. Valores válidos = los del menú de la columna E. */
const CANAL_POR_PESTANA = { landing: "LANDING" };
const CANAL_POR_DEFECTO = "FORMULARIO";

/**
 * Qué poner en "Interés" cuando la persona dijo que YA es socio de la cooperativa
 * (55 casos). "Nuevo" es lo conservador: el dato de que ya es socio nunca se pierde,
 * queda escrito en la Nota. Cambiar a "Renovación" si el negocio decide tratarlos así.
 */
const INTERES_SI_YA_ES_SOCIO = "Nuevo";
const INTERES_POR_DEFECTO = "Nuevo";

/**
 * "¿Autorizó contacto?" es columna obligatoria de nuestra hoja. Cuando la pestaña de
 * origen SÍ trae el dato, manda el dato real de la fila. Este valor solo aplica a las
 * pestañas que no tienen esa columna (el formulario de Facebook). Fijado 2026-07-22.
 */
const CONSENTIMIENTO_SI_NO_HAY_COLUMNA = "SI";

/** Texto de la columna "Fuente del consentimiento", por pestaña (clave normalizada). */
const FUENTE_POR_PESTANA = { landing: "Landing COOPAC MÁSCAPITAL" };
const FUENTE_POR_DEFECTO = "Formulario de campaña de ahorro (Facebook)";

const HOJA_DESTINO = "LEADS";
const HOJA_REVISAR = "REVISAR (no importados)";
const HOJA_HUELLAS = "_puente_huellas"; // oculta: evita traer dos veces lo mismo
const TOPE_POR_PASADA = 500;

/**
 * FECHA DE CORTE — el backlog viejo NO entra al CRM (decisión de Miguel, 2026-07-23).
 *
 * Frena SOLO las filas que traen fecha legible ANTERIOR a esta. Se descartan con
 * motivo "Anterior al corte": se cuentan en el reporte pero no se listan en REVISAR
 * (son cientos, por diseño — taparían lo que sí hay que mirar).
 *
 * Una fila SIN fecha legible ENTRA IGUAL (decisión de Miguel, 2026-07-27): la fecha
 * que vale es la del día en que el lead ingresa al CRM. El origen dejó de llenar
 * "Fecha de Registro" en las filas nuevas y la regla anterior ("sin fecha → a
 * revisar") tenía 159 leads potenciales presos en REVISAR. El backlog de 2025 sí
 * viene fechado, así que el corte lo sigue dejando fuera.
 *
 * Formato "AAAA-MM-DD". Dejar en "" desactiva el corte (entra todo — NO recomendado:
 * son ~500 leads de 2025).
 */
const FECHA_CORTE = "2026-07-22";

/**
 * Motivo de los descartes POR DISEÑO (el backlog anterior al corte). Se cuentan en
 * el reporte pero NO se listan en la pestaña de revisión: son cientos y enterrarían
 * los descartes que sí hay que mirar (teléfono malo, sin monto, sin moneda…).
 */
const MOTIVO_CORTE = "Anterior al corte";

/**
 * UN LEAD NO SE PIERDE POR UN DATO QUE FALTA (decisión de Miguel, 2026-07-23).
 *
 * La base exige `monto_estimado > 0` (CHECK `leads_monto_estimado_valido`), así que
 * un lead sin monto NO se puede insertar vacío ni en 0: hay que poner un número.
 * Se usa 1 como MARCADOR EVIDENTE — nadie lo confunde con un monto real — y la Nota
 * lo dice con todas sus letras para que el vendedor lo pregunte.
 *
 * Ojo al leer reportes: estos leads caen en el rango de capital más bajo.
 */
const MONTO_SI_NO_INDICA = 1;

/**
 * Misma idea para la moneda (la columna es obligatoria en la hoja y la base defaultea
 * a PEN). Se asume PEN y queda anotado; nunca se descarta el lead por esto.
 */
const MONEDA_SI_NO_INDICA = "PEN";

// ── Menú ─────────────────────────────────────────────────────────────────────

/**
 * Disparador SIMPLE: Google lo corre al ABRIR la hoja (no al pulsar ▶ en el editor).
 * Si el menú no aparece, recarga la hoja; y si aun así no sale, ejecuta una vez
 * instalarMenu() desde el editor.
 */
function onOpen() {
  crearMenu();
}

function crearMenu() {
  SpreadsheetApp.getUi()
    .createMenu("AVANCE CORP")
    .addItem("Vista previa (no escribe nada)", "vistaPreviaOrigen")
    .addItem("Traer leads del origen", "traerLeadsDelOrigen")
    .addSeparator()
    .addItem("Activar horario automático (lun–sáb 9 a. m.)", "instalarHorario")
    .addItem("Ver horario", "verHorario")
    .addItem("Apagar horario automático", "quitarHorario")
    .addToUi();
}

/**
 * Plan B del menú: crea un disparador INSTALABLE de apertura (convive con cualquier
 * onOpen que ya tenga el proyecto) y además dibuja el menú ahora mismo.
 * Ejecutar UNA VEZ desde el editor. Idempotente.
 */
function instalarMenu() {
  const libro = SpreadsheetApp.getActiveSpreadsheet();
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === "crearMenu") ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger("crearMenu").forSpreadsheet(libro).onOpen().create();
  try { crearMenu(); } catch (e) { /* el libro no está abierto en otra pestaña */ }
  console.log("Menú instalado. Recarga la hoja: aparece \"AVANCE CORP\" a la derecha de Ayuda.");
}

// ── Horario automático ───────────────────────────────────────────────────────

const HORA_DE_CORRIDA = 9;                  // 9 a. m.
const ZONA_DE_CORRIDA = "America/Lima";     // fijada aquí: NO depende de la zona del proyecto
const FUNCION_PROGRAMADA = "corridaProgramada";

/** Lunes a sábado. El domingo queda fuera por decisión de Miguel (2026-07-22). */
function diasDeCorrida() {
  const D = ScriptApp.WeekDay;
  return [D.MONDAY, D.TUESDAY, D.WEDNESDAY, D.THURSDAY, D.FRIDAY, D.SATURDAY];
}

/**
 * Deja el puente corriendo solo: lunes a sábado, 9 a. m. de Lima. Un disparador semanal
 * por día (Apps Script no tiene "todos los días menos domingo").
 *
 * Idempotente: borra los horarios anteriores antes de crear los nuevos, así que se puede
 * ejecutar las veces que haga falta sin duplicar corridas.
 */
function instalarHorario() {
  const borrados = quitarHorario(true);
  diasDeCorrida().forEach(function (dia) {
    ScriptApp.newTrigger(FUNCION_PROGRAMADA)
      .timeBased()
      .onWeekDay(dia)
      .atHour(HORA_DE_CORRIDA)
      .inTimezone(ZONA_DE_CORRIDA)
      .create();
  });
  informar(
    "Horario automático ACTIVADO\n\n" +
    "El puente traerá los leads nuevos de lunes a sábado, entre las " + HORA_DE_CORRIDA +
    " y las " + (HORA_DE_CORRIDA + 1) + " a. m. (hora de Lima). Domingos no corre.\n\n" +
    "Google no garantiza el minuto exacto: dispara dentro de esa hora.\n" +
    "De ahí, el conector sube los leads al CRM en su ciclo de 5 min.\n\n" +
    (borrados ? "(Se reemplazaron " + borrados + " horarios anteriores.)" : "")
  );
}

/** Apaga el horario. Devuelve cuántos disparadores quitó. */
function quitarHorario(silencioso) {
  let n = 0;
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === FUNCION_PROGRAMADA) { ScriptApp.deleteTrigger(t); n++; }
  });
  if (!silencioso) {
    informar(n
      ? "Horario automático APAGADO (" + n + " disparadores quitados).\n\n" +
        "El puente ya solo corre cuando lo pides desde el menú."
      : "No había horario automático activo.");
  }
  return n;
}

/** Qué hay programado ahora mismo. Solo lee. */
function verHorario() {
  const propios = ScriptApp.getProjectTriggers().filter(function (t) {
    return t.getHandlerFunction() === FUNCION_PROGRAMADA;
  });
  informar(propios.length
    ? "Horario automático ACTIVO: " + propios.length + " corridas por semana, " +
      "lunes a sábado entre las " + HORA_DE_CORRIDA + " y las " + (HORA_DE_CORRIDA + 1) +
      " a. m. (hora de Lima)."
    : "Horario automático APAGADO. Actívalo con \"Activar horario automático\".");
  return propios.length;
}

/**
 * Lo que corre el disparador. Sin ventanas: nadie está mirando la hoja a esa hora.
 * Si algo falla, Google avisa por correo al dueño del script; el detalle queda en el
 * Registro de ejecución del proyecto.
 */
function corridaProgramada() {
  console.log("Corrida programada — " +
    Utilities.formatDate(new Date(), ZONA_DE_CORRIDA, "EEE dd/MM/yyyy HH:mm"));
  const r = procesar(true);
  console.log(resumen(r));
  return r;
}

// ── Ejecución manual ─────────────────────────────────────────────────────────

/**
 * Ejecutable directamente desde el editor (▶ con "vistaPreviaOrigen" seleccionada).
 * NO escribe nada. El resultado sale en el Registro de ejecución y, si la hoja está
 * abierta, también como ventana.
 */
function vistaPreviaOrigen() {
  const r = procesar(false);
  informar(
    "Vista previa — no se escribió nada\n\n" + resumen(r) +
    "\n\nEjecuta \"Traer leads del origen\" para escribirlos en la hoja."
  );
  return r;
}

function traerLeadsDelOrigen() {
  const r = procesar(true);
  informar(
    "Listo\n\n" + resumen(r) +
    "\n\nLas filas nuevas se importan solas al CRM en el próximo ciclo de 5 min." +
    (r.rechazados.length
      ? "\nLas descartadas están en la pestaña \"" + HOJA_REVISAR + "\" con el motivo."
      : "")
  );
  return r;
}

/**
 * Deja el resultado SIEMPRE en el Registro de ejecución del editor, y además como
 * ventana cuando hay interfaz. Así el reporte nunca depende de que el menú exista.
 */
function informar(texto) {
  console.log("\n" + texto);
  try {
    SpreadsheetApp.getUi().alert(texto);
  } catch (e) {
    // Ejecutado desde el editor sin la hoja abierta: el registro ya lo tiene todo.
  }
}

function resumen(r) {
  const porMotivo = {};
  r.rechazados.forEach(function (x) {
    porMotivo[x.motivo] = (porMotivo[x.motivo] || 0) + 1;
  });
  let noAutoriza = 0, sinMonto = 0, sinMoneda = 0, conPregunta = 0, sinFecha = 0, telRescatado = 0;
  r.aceptados.forEach(function (l) {
    if (l.autorizo === "NO") noAutoriza++;
    if (l.sinMonto) sinMonto++;
    if (l.sinMoneda) sinMoneda++;
    if (l.pregunta) conPregunta++;
    if (l.sinFecha) sinFecha++;
    if (l.telefonoRescatado) telRescatado++;
  });

  let t = FECHA_CORTE
    ? "CORTE ACTIVO: se frena solo lo fechado ANTES del " + FECHA_CORTE +
      " (sin fecha legible = entra igual).\n\n"
    : "⚠️ SIN CORTE: entraría TODO el origen, incluido el backlog viejo.\n\n";

  t += "Filas leídas del origen: " + r.leidas +
    "\nLeads utilizables: " + r.aceptados.length +
    "\n   · de esos, " + noAutoriza + " marcaron NO autorizar → entran como no-contactar" +
    (conPregunta ? "\n   · " + conPregunta + " traen COMENTARIO del cliente → va al inicio de la Nota" : "") +
    (sinMonto ? "\n   · " + sinMonto + " SIN MONTO → entran con " + MONTO_SI_NO_INDICA + " y aviso en la Nota" : "") +
    (sinMoneda ? "\n   · " + sinMoneda + " SIN MONEDA → entran como " + MONEDA_SI_NO_INDICA + " y aviso en la Nota" : "") +
    (sinFecha ? "\n   · " + sinFecha + " sin fecha en el origen → entran contando desde hoy" : "") +
    (telRescatado ? "\n   · " + telRescatado + " con el teléfono fuera de su columna → número rescatado" : "") +
    "\nYa traídos antes (se omiten): " + r.repetidosPasadas +
    "\nDescartados: " + r.rechazados.length;
  Object.keys(porMotivo).forEach(function (m) {
    t += "\n   · " + m + ": " + porMotivo[m];
  });

  // Desglose por mes de los que SÍ entrarían: deja ver de un vistazo si el corte
  // está haciendo lo que se espera (o si se coló algo viejo).
  const porMes = {};
  r.aceptados.forEach(function (l) {
    const k = l.fecha ? l.fecha.mes : "sin fecha";
    porMes[k] = (porMes[k] || 0) + 1;
  });
  const meses = Object.keys(porMes).sort();
  if (meses.length) {
    t += "\n\nLos que entrarían, por mes:";
    meses.forEach(function (m) { t += "\n   · " + m + ": " + porMes[m]; });
  }
  return t;
}

// ── Núcleo ───────────────────────────────────────────────────────────────────

function procesar(escribir) {
  const destino = SpreadsheetApp.getActiveSpreadsheet();
  if (!destino) {
    throw new Error(
      "No hay hoja activa. Este script tiene que vivir DENTRO de la hoja " +
      "\"Leads AVANCE CORP — captura para CRM\" (Extensiones → Apps Script), " +
      "no como proyecto suelto de script.google.com."
    );
  }
  const hojaLeads = destino.getSheetByName(HOJA_DESTINO) || destino.getSheets()[0];
  console.log("Destino: " + destino.getName() + " → pestaña \"" + hojaLeads.getName() + "\"");

  const huellas = leerHuellas(destino);          // lo ya traído en pasadas previas
  const telefonosEnHoja = telefonosYaEnLaHoja(hojaLeads); // y lo ya escrito a mano
  const vistosAhora = {};

  const origen = SpreadsheetApp.openById(ORIGEN_ID); // ← solo lectura, ver cabecera
  const aceptados = [];
  const rechazados = [];
  const duplicados = []; // rechazados por duplicado: se huellán para no re-listarlos
  let leidas = 0;
  let repetidosPasadas = 0;

  origen.getSheets().forEach(function (pestana) {
    // El tope es de la PASADA entera, no de cada pestaña: sin esto, el `break` de
    // abajo solo cortaba la pestaña en curso y la siguiente seguía sumando
    // (por eso una corrida con tope 500 devolvió 501).
    if (aceptados.length >= TOPE_POR_PASADA) return;

    const nombrePestana = pestana.getName();
    const datos = pestana.getDataRange().getDisplayValues();
    if (datos.length < 2) return;

    const col = ubicarColumnas(datos[0]);
    // Deja rastro en el Registro de ejecución: si una pestaña no aporta nada, aquí
    // se ve por qué (columna no reconocida, encabezado renombrado, etc.).
    console.log("Origen · pestaña \"" + nombrePestana + "\": " + (datos.length - 1) +
      " filas · columnas detectadas → " + describirColumnas(col, datos[0]));
    console.log("   ↳ autorizó contacto: " + (col.consent >= 0
      ? "dato real de cada fila"
      : "sin columna → \"" + CONSENTIMIENTO_SI_NO_HAY_COLUMNA + "\""));
    if (col.telefono < 0 && col.whatsapp < 0) {
      console.log("   ↳ omitida: no encontré columna de teléfono.");
      return; // pestaña sin teléfonos: no es de leads
    }

    for (let i = 1; i < datos.length; i++) {
      const fila = datos[i];
      if (fila.every(function (c) { return String(c).trim() === ""; })) continue;
      if (esFilaDeEncabezado(fila, datos[0])) continue;
      leidas++;

      const lead = normalizarFila(fila, col, nombrePestana, i + 1, datos[0]);

      if (lead.motivo) { rechazados.push(lead); continue; }

      const huella = nombrePestana + "|" + lead.telefono;
      if (huellas[huella]) { repetidosPasadas++; continue; }
      // Los DUPLICADOS también se huellán: se listan en REVISAR UNA sola vez (esta
      // pasada) y las siguientes los saltan en silencio. Sin esto, cada corrida
      // re-lista la historia completa de duplicados (163 filas el 2026-07-27) y
      // entierra lo que Rosa sí tiene que mirar.
      if (vistosAhora[lead.telefono]) {
        lead.motivo = "Teléfono repetido dentro del origen";
        lead.huella = huella;
        duplicados.push(lead);
        rechazados.push(lead);
        continue;
      }
      if (telefonosEnHoja[lead.telefono]) {
        lead.motivo = "Teléfono ya presente en la hoja";
        lead.huella = huella;
        duplicados.push(lead);
        rechazados.push(lead);
        continue;
      }

      vistosAhora[lead.telefono] = true;
      lead.huella = huella;
      aceptados.push(lead);
      if (aceptados.length >= TOPE_POR_PASADA) break;
    }
  });

  if (escribir) {
    escribirLeads(hojaLeads, aceptados);
    // Huellas ANTES que REVISAR: si la corrida muere a mitad (timeout de Apps
    // Script sobre las ~12k filas del origen), lo grave es "leads escritos sin
    // huella" — pasó el 2026-07-27 y la corrida siguiente re-listó TODO como
    // "ya presente". REVISAR es cosmético: va al final.
    guardarHuellas(destino, aceptados.concat(duplicados));
    escribirRechazos(destino, rechazados);
  }
  return { leidas: leidas, aceptados: aceptados, rechazados: rechazados, repetidosPasadas: repetidosPasadas };
}

/**
 * Mapea los encabezados del origen a los campos que nos sirven. Por PALABRA CLAVE,
 * no por posición ni por texto exacto: si mañana alguien renombra o mueve una
 * columna, el puente sigue funcionando. El orden de las reglas importa — "¿Deseas
 * depositar en soles o dólares?" tiene que caer en moneda, no en monto.
 */
function ubicarColumnas(cabeceras) {
  // Columnas que se ignoran SIEMPRE, aunque se parezcan a otra cosa:
  // "¿deseas aperturar tus AHORROS?" no es el monto (y 186 de 187 responden igual),
  // y Departamento no cabe en la hoja, que trabaja a nivel de distrito.
  const DESCARTAR = /apertur|departamento|^region/;

  const reglas = [
    ["moneda",       /sol(es)?\s*(o|y|\/)\s*dolar|moneda|en\s+soles|en\s+dolares/],
    ["monto",        /cuanto|monto|dinero|capital|deposit|invert/],
    ["socio",        /socio/],
    ["consent",      /de acuerdo|acepto|autoriz|consent|informacion comercial|recibir informacion/],
    ["whatsapp",     /whatsapp|celular\s*2|telefono\s*2|numero\s*2/],
    ["telefono",     /^celular|^telefono|^numero|^movil|^tel\b/],
    ["apellido",     /apellido/],
    ["nombre",       /^nombre/],
    ["distrito",     /distrito/],
    ["ciudad",       /ciudad|provincia/],
    ["pregunta",     /pregunta|consulta|mensaje|comentario|duda/],
    ["correo",       /correo|email|e-mail/],
    ["dni",          /^dni|documento/],
  ];
  const col = {};
  reglas.forEach(function (r) { col[r[0]] = -1; });
  col.fechas = [];

  cabeceras.forEach(function (bruto, i) {
    const h = normalizar(bruto);
    if (!h) return;
    if (DESCARTAR.test(h)) return;
    if (/fecha/.test(h)) { col.fechas.push(i); return; }
    for (let k = 0; k < reglas.length; k++) {
      const nombre = reglas[k][0];
      if (col[nombre] === -1 && reglas[k][1].test(h)) { col[nombre] = i; return; }
    }
    // Lo que no cae en ninguna regla se descarta a propósito: WhatsApp duplicado,
    // Departamento, "¿deseas aperturar tus ahorros?" (186 de 187 responden igual).
  });
  return col;
}

/** Para el Registro: qué encabezado real quedó en cada campo, y cuáles faltan. */
function describirColumnas(col, cabeceras) {
  const partes = [];
  Object.keys(col).forEach(function (campo) {
    if (campo === "fechas") {
      if (col.fechas.length) partes.push("fecha=" + col.fechas.map(function (i) { return cabeceras[i]; }).join(" y "));
      return;
    }
    if (col[campo] >= 0) partes.push(campo + "=\"" + cabeceras[col[campo]] + "\"");
  });
  const faltan = Object.keys(col).filter(function (c) { return c !== "fechas" && col[c] < 0; });
  return partes.join(" · ") + (faltan.length ? "  |  sin columna: " + faltan.join(", ") : "");
}

/** Convierte una fila del origen en una fila de nuestra hoja, o la rechaza con motivo. */
function normalizarFila(fila, col, pestana, numeroFila, cabeceras) {
  const val = function (i) { return i >= 0 && i < fila.length ? String(fila[i]).trim() : ""; };

  const lead = {
    pestana: pestana, fila: numeroFila, motivo: "",
    crudo: filaLegible(fila, cabeceras),
  };

  // FECHA DE CORTE — frena solo lo que trae fecha legible Y vieja. Sin fecha legible
  // el lead ENTRA (decisión de Miguel, 2026-07-27): su fecha real es el día en que
  // ingresa; a un posible cliente no se le frena por un dato administrativo que el
  // origen olvidó llenar.
  const fecha = fechaMasAntigua(fila, col.fechas);
  lead.fecha = fecha;
  lead.sinFecha = !fecha;
  const corte = corteEnMs();
  if (corte !== null && fecha && fecha.ms < corte) {
    lead.motivo = MOTIVO_CORTE + " (" + FECHA_CORTE + ")";
    return lead;
  }

  // Nombre y teléfono se resuelven ANTES de cualquier rechazo: así toda fila que
  // caiga en REVISAR sale con esas dos columnas llenas cuando el dato sí existe.
  lead.nombre = [val(col.nombre), val(col.apellido)]
    .filter(String).join(" ").replace(/\s+/g, " ").trim();

  // Teléfono: primero sus columnas (celular; respaldo WhatsApp / celular 2). Si no
  // dan un número usable, RESCATE en el resto de la fila: la pestaña de Facebook
  // tiene dos columnas "celular" — la primera trae lo que la persona tipeó (a veces
  // un monto o su propio nombre) y el número real está en la otra, con prefijo "p:".
  lead.telefono = telefonoPeru(val(col.telefono)) || telefonoPeru(val(col.whatsapp));
  if (!lead.telefono) {
    lead.telefono = telefonoEnOtraCelda(fila, col);
    lead.telefonoRescatado = !!lead.telefono;
  }

  // PRÉSTAMO — vino a pedir plata, no a depositarla (regla de Miguel, 2026-07-27).
  // Lo decide un humano en REVISAR. Va antes que los rechazos por dato faltante
  // porque es el motivo que más importa ver ahí.
  if (pidePrestamo(val(col.pregunta))) {
    lead.motivo = "Pide PRÉSTAMO — no es lead de ahorro";
    return lead;
  }

  if (!lead.nombre) { lead.motivo = "Sin nombre"; return lead; }
  if (!lead.telefono) {
    lead.motivo = "Sin teléfono válido (se buscó en toda la fila)";
    return lead;
  }

  // Monto y moneda NO descartan al lead: si faltan, entra marcado (ver constantes).
  lead.capital = montoDe(val(col.monto));
  lead.sinMonto = !lead.capital;
  if (lead.sinMonto) lead.capital = String(MONTO_SI_NO_INDICA);

  const m = monedaDe(val(col.moneda));
  lead.sinMoneda = !m.moneda;
  lead.moneda = m.moneda || MONEDA_SI_NO_INDICA;

  lead.canal = CANAL_POR_PESTANA[normalizar(pestana)] || CANAL_POR_DEFECTO;
  lead.distrito = limpiarLugar(val(col.distrito) || val(col.ciudad));
  lead.correo = val(col.correo);
  lead.dni = /^\d{8}$/.test(val(col.dni)) ? val(col.dni) : "";

  const esSocio = siNo(val(col.socio)) === "SI";
  lead.interes = esSocio ? INTERES_SI_YA_ES_SOCIO : INTERES_POR_DEFECTO;

  // Consentimiento: si la pestaña tiene la columna, manda el dato real de la fila
  // (un "No" explícito viaja como NO y el CRM lo marca no-contactar). Solo cuando la
  // pestaña no tiene columna aplica la decisión de Miguel (§ CONSENTIMIENTO_SI_NO_HAY_COLUMNA).
  lead.autorizo = col.consent >= 0
    ? siNo(val(col.consent)) || CONSENTIMIENTO_SI_NO_HAY_COLUMNA
    : CONSENTIMIENTO_SI_NO_HAY_COLUMNA;
  lead.fuenteConsentimiento = (FUENTE_POR_PESTANA[normalizar(pestana)] || FUENTE_POR_DEFECTO) + " — " + pestana;

  // Nota: todo lo que el vendedor agradece saber y no tiene columna propia.
  // (`fecha` ya se calculó arriba, al aplicar el corte.)
  //
  // ORDEN DELIBERADO (decisión de Miguel, 2026-07-23): PRIMERO lo que el cliente
  // escribió de su puño y letra — es con lo que el vendedor abre la llamada y lo
  // único que no se puede reconstruir de ningún otro campo. Después los avisos de
  // dato faltante, y al final la trazabilidad.
  lead.pregunta = preguntaUtil(val(col.pregunta));
  lead.nota = [
    lead.pregunta ? "💬 PREGUNTÓ: " + lead.pregunta : "",
    lead.sinMonto ? "⚠️ NO INDICÓ MONTO — confirmar con el cliente" : "",
    lead.sinMoneda ? "⚠️ NO INDICÓ MONEDA — se asumió " + MONEDA_SI_NO_INDICA : "",
    lead.telefonoRescatado ? "⚠️ Teléfono tomado de OTRA columna del origen — confirmar al contactar" : "",
    lead.sinFecha ? "Sin fecha en el origen (vale la del ingreso)" : "",
    esSocio ? "Ya es socio de la cooperativa" : "",
    m.mixta ? "Marcó soles y dólares — se asumió PEN" : "",
  ].filter(String).join(" · ");

  return lead;
}

// ── Normalizadores ───────────────────────────────────────────────────────────

/** Minúsculas, sin tildes, sin guiones bajos ni emojis: para comparar texto. */
function normalizar(s) {
  return String(s == null ? "" : s)
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "") // quita tildes
    .replace(/[_\-]+/g, " ")                          // "🟡_ahorrar_en_soles" → legible
    .toLowerCase().replace(/\s+/g, " ").trim();
}

/** Teléfono peruano canónico "+51XXXXXXXXX", o "" si no es utilizable. */
function telefonoPeru(v) {
  if (!v || v.indexOf("@") >= 0) return ""; // hay correos metidos en la columna de teléfono
  const d = String(v).replace(/\D/g, "");
  if (/^51[9]\d{8}$/.test(d)) return "+" + d;         // ya viene con código de país
  if (/^9\d{8}$/.test(d)) return "+51" + d;           // celular de 9 dígitos
  if (/^0?51[9]\d{8}$/.test(d)) return "+" + d.slice(-11);
  return "";                                          // fijos, truncados, basura
}

/**
 * RESCATE: busca un celular peruano válido en CUALQUIER otra celda de la fila, para
 * los leads que escriben el número donde no toca (o cuando el origen tiene dos
 * columnas "celular" y el mapeo por encabezado solo puede quedarse con la primera).
 * Se saltan las columnas ya intentadas y las que por diseño traen números que NO son
 * teléfono (monto, DNI). telefonoPeru() es estricto — 9 dígitos empezando en 9, con
 * o sin +51 — así que fechas, DNIs y montos con miles no pasan por número.
 */
function telefonoEnOtraCelda(fila, col) {
  for (let i = 0; i < fila.length; i++) {
    if (i === col.telefono || i === col.whatsapp || i === col.monto || i === col.dni) continue;
    const t = telefonoPeru(String(fila[i] == null ? "" : fila[i]).trim());
    if (t) return t;
  }
  return "";
}

/**
 * La persona pide un PRÉSTAMO o crédito: no es lead de ahorro (nosotros captamos
 * depósitos, no colocamos créditos). "presta" cubre préstamo/prestamos/préstame/
 * prestan; normalizar() ya quitó las tildes. Puede dar un falso positivo raro
 * ("prestar atención"), pero REVISAR lo mira un humano: mejor una revisión de más
 * que un préstamo colado al CRM.
 */
function pidePrestamo(v) {
  const n = normalizar(v);
  return n ? /presta|credito/.test(n) : false;
}

/** "50,000 a más" → 50000 · "más de 100,000" → 100000 · "5,000_" → 5000. */
function montoDe(v) {
  const m = String(v).match(/\d[\d.,]*/);
  if (!m) return "";
  const n = parseInt(m[0].replace(/[.,]/g, ""), 10);
  return n > 0 ? String(n) : "";
}

/** PEN / USD. Marca `mixta` cuando la persona eligió las dos. */
function monedaDe(v) {
  const n = normalizar(v);
  const usd = /dolar|usd|\$/.test(n);
  const pen = /\bsol(es)?\b|\bpen\b|s\//.test(n);
  if (usd && pen) return { moneda: "PEN", mixta: true };
  if (usd) return { moneda: "USD", mixta: false };
  if (pen) return { moneda: "PEN", mixta: false };
  return { moneda: "", mixta: false };
}

/** "Si"/"SI"/"✅_si_deseo…" → SI · "No"/"NO" → NO. El NO se evalúa primero: una
 *  respuesta que empieza con "no" manda, aunque más adelante diga "si". */
function siNo(v) {
  const n = normalizar(v);
  if (!n) return "";
  if (/^no\b|^n$/.test(n)) return "NO";
  if (/^si\b|^s$|^yes|^acepto|^de acuerdo|\bsi\b/.test(n)) return "SI";
  return "";
}

/**
 * El comentario del cliente, SOLO si aporta algo. En el lote real la mayoría
 * escribe "no", "si" u "ok" (no tenían pregunta): meter eso en la nota como
 * "PREGUNTÓ: no" es ruido que le resta valor al aviso cuando sí hay pregunta.
 * Devuelve "" cuando el texto no dice nada.
 */
function preguntaUtil(v) {
  const t = String(v || "").trim();
  if (!t) return "";
  const n = normalizar(t);
  // Respuestas vacías de contenido, tal como aparecen en el origen.
  if (/^(no|si|s|n|ok|oki|ninguna?|ninguno|nada|nada mas|todo bien|x|-|\.)$/.test(n)) return "";
  return t.slice(0, 300);
}

/**
 * La fila del origen, legible para Rosa: "Encabezado: valor", una línea por dato
 * (salto de línea DENTRO de la misma celda). Reemplaza el volcado plano de antes
 * (`fila.join(" | ")`), que aplastaba toda la fila en un pipe sin etiquetas — nadie
 * podía saber qué campo era cuál. Solo entran las columnas que traen dato.
 */
function filaLegible(fila, cabeceras) {
  const partes = [];
  for (let i = 0; i < fila.length; i++) {
    const valor = legible(fila[i]);
    if (!valor) continue;
    const encabezado = legible(cabeceras && cabeceras[i] != null ? cabeceras[i] : "") || ("Columna " + (i + 1));
    partes.push(encabezado + ": " + valor);
  }
  return partes.join("\n").slice(0, 800);
}

/**
 * Encabezado o valor crudo → texto legible: quita guiones BAJOS y símbolos/emojis
 * sueltos del inicio (así viene el formulario de Facebook, tanto la pregunta como
 * a veces la respuesta: "✅_si_deseo_aperturar_mi_cuenta"). Solo toca "_", nunca
 * "-": el guion normal aparece en fechas ISO ("2026-07-23T18:47:09-05:00") y hay
 * que dejarlo intacto. A diferencia de normalizar(), conserva mayúsculas y tildes
 * — esto es para MOSTRAR, no para comparar.
 */
function legible(s) {
  return String(s == null ? "" : s)
    .replace(/_+/g, " ")
    .replace(/^[^\p{L}\p{N}¿¡+]+/u, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** Descarta lugares que en realidad son códigos o números sueltos ("15"). */
function limpiarLugar(v) {
  const t = String(v).trim();
  if (!t || /^\d+$/.test(t)) return "";
  return t.replace(/\s+/g, " ");
}

/**
 * De todas las columnas de fecha de la fila, la MÁS ANTIGUA: esa es la fecha real
 * en que la persona dejó sus datos (las otras suelen ser marcas de exportación).
 */
function fechaMasAntigua(fila, indices) {
  let mejor = null;
  (indices || []).forEach(function (i) {
    const t = String(fila[i] || "").trim();
    let iso = t.match(/^(\d{4})-(\d{2})-(\d{2})/);
    let d = null;
    if (iso) d = { a: +iso[1], m: +iso[2], dd: +iso[3] };
    else {
      const lat = t.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/);
      if (lat) d = { a: +lat[3], m: +lat[2], dd: +lat[1] };
    }
    if (!d) return;
    const ms = Date.UTC(d.a, d.m - 1, d.dd);
    if (mejor === null || ms < mejor.ms) {
      mejor = {
        ms: ms,
        texto: pad(d.dd) + "/" + pad(d.m) + "/" + d.a,
        mes: d.a + "-" + pad(d.m), // para el desglose del reporte
      };
    }
  });
  return mejor; // { ms, texto, mes } | null
}

/** La fecha de corte como milisegundos, o null si no hay corte configurado. */
function corteEnMs() {
  const m = String(FECHA_CORTE || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3]) : null;
}

function pad(n) { return (n < 10 ? "0" : "") + n; }

/** Filas que repiten el encabezado en medio de los datos. */
function esFilaDeEncabezado(fila, cabeceras) {
  let iguales = 0;
  for (let i = 0; i < Math.min(fila.length, cabeceras.length); i++) {
    if (String(fila[i]).trim() && normalizar(fila[i]) === normalizar(cabeceras[i])) iguales++;
  }
  return iguales >= 2;
}

// ── Escritura (SOLO en nuestra hoja) ─────────────────────────────────────────

function escribirLeads(hoja, leads) {
  if (!leads.length) return;
  const filas = leads.map(function (l) {
    return [
      l.nombre,               // A Nombre completo *
      l.telefono,             // B Teléfono *
      l.capital,              // C Capital estimado *
      l.moneda,               // D Moneda *
      l.canal,                // E Canal de origen *
      l.correo,               // F Correo
      l.dni,                  // G DNI
      "",                     // H Género          — el origen no lo trae
      "",                     // I Fecha nacimiento— el origen no lo trae
      l.distrito,             // J Distrito
      l.interes,              // K Interés
      l.nota,                 // L Nota
      "",                     // M Vendedor asignado — se reparte DENTRO del CRM
      l.autorizo,             // N ¿Autorizó contacto?
      l.fuenteConsentimiento, // O Fuente del consentimiento
      "",                     // P Estado: vacío = el conector la toma en el próximo ciclo
    ];
  });
  hoja.getRange(hoja.getLastRow() + 1, 1, filas.length, 16).setValues(filas);
}

/**
 * Prioridad de cada motivo al ordenar REVISAR (menor = más arriba). Función pura,
 * probada en puente-drive-origen.test.mjs.
 */
function ordenRevision(motivo) {
  const m = String(motivo || "");
  if (m.indexOf("PRÉSTAMO") >= 0) return 0;
  if (m.indexOf("Sin teléfono") === 0) return 1;
  if (m.indexOf("Sin nombre") === 0) return 2;
  if (m.indexOf("repetido dentro del origen") >= 0) return 8;
  if (m.indexOf("ya presente") >= 0) return 9;
  return 5;
}

/**
 * La pestaña de revisión es la RED DE SEGURIDAD: todo lead descartado que un humano
 * podría rescatar queda aquí, con el motivo y la fila COMPLETA del origen. Se
 * reescribe entera en cada pasada (es una foto del estado actual del origen, no un
 * histórico), así que arreglar el dato en el origen lo saca de esta lista solo.
 *
 * Los descartes por corte de fecha NO entran: son por diseño y taparían el resto.
 */
function escribirRechazos(libro, rechazados) {
  rechazados = rechazados.filter(function (r) {
    return String(r.motivo).indexOf(MOTIVO_CORTE) !== 0;
  });
  // Lo accionable arriba (préstamo, sin teléfono, sin nombre); los duplicados al
  // final — solo aparecen la pasada en que se descubren (quedan huellados).
  rechazados = rechazados.slice().sort(function (a, b) {
    return ordenRevision(a.motivo) - ordenRevision(b.motivo);
  });
  let hoja = libro.getSheetByName(HOJA_REVISAR);
  if (!hoja) hoja = libro.insertSheet(HOJA_REVISAR);

  // El encabezado se reescribe SIEMPRE, exista la pestaña o no: si alguien la creó
  // a mano (o quedó de una corrida vieja sin encabezado), esto la deja arreglada
  // en la próxima corrida sin que nadie tenga que tocar nada manualmente.
  hoja.getRange(1, 1, 1, 6).setValues(
    [["Motivo", "Pestaña de origen", "Fila", "Nombre", "Teléfono crudo", "Fila completa del origen"]]
  );
  hoja.getRange(1, 1, 1, 6).setFontWeight("bold").setBackground("#f4cccc");
  hoja.setFrozenRows(1);
  hoja.setColumnWidth(6, 480);

  if (hoja.getLastRow() > 1) {
    hoja.getRange(2, 1, hoja.getLastRow() - 1, 6).clearContent();
  }
  if (!rechazados.length) return;
  const filas = rechazados.map(function (r) {
    return [r.motivo, r.pestana, r.fila, r.nombre || "", r.telefono || "", r.crudo];
  });
  hoja.getRange(2, 1, filas.length, 6).setValues(filas);
  hoja.getRange(2, 6, filas.length, 1).setWrap(true).setVerticalAlignment("top");
}

function leerHuellas(libro) {
  const hoja = libro.getSheetByName(HOJA_HUELLAS);
  const mapa = {};
  if (!hoja || hoja.getLastRow() < 1) return mapa;
  hoja.getRange(1, 1, hoja.getLastRow(), 1).getValues().forEach(function (f) {
    if (f[0]) mapa[String(f[0])] = true;
  });
  return mapa;
}

/**
 * Además de la huella (columna A, la ÚNICA que lee leerHuellas), se guarda aquí la
 * trazabilidad que se sacó de la Nota: de qué fila del origen salió cada lead y con
 * qué fecha se registró. Esa información es interna — al vendedor no le sirve para
 * vender — pero si algún dato sale raro permite volver a la fila exacta del origen.
 * Hoja oculta: nunca viaja al CRM.
 */
function guardarHuellas(libro, leads) {
  let hoja = libro.getSheetByName(HOJA_HUELLAS);
  if (!hoja) {
    hoja = libro.insertSheet(HOJA_HUELLAS);
    hoja.appendRow(["Huella (no tocar)", "Teléfono", "Origen", "Registrado el", "Traído el"]);
    hoja.hideSheet();
  }
  protegerHuellas(hoja);
  if (!leads.length) return;
  const traidoEl = Utilities.formatDate(new Date(), ZONA_DE_CORRIDA, "dd/MM/yyyy HH:mm");
  hoja.getRange(hoja.getLastRow() + 1, 1, leads.length, 5)
    .setValues(leads.map(function (l) {
      return [
        l.huella,
        l.telefono,
        l.pestana + " fila " + l.fila,
        l.fecha ? l.fecha.texto : "",
        traidoEl,
      ];
    }));
}

/**
 * Blinda la pestaña de huellas: solo quien instaló el puente (y por tanto el propio
 * script, que corre con su identidad) puede editarla o borrarla. Si alguien más la
 * borrara, el puente perdería la memoria: re-listaría todos los avisos de duplicado
 * y, con LEADS limpia, re-traería leads ya importados (el CRM los frena, pero es
 * ruido). Idempotente: si ya está protegida, no hace nada.
 *
 * ⚠️ Si algún día OTRA persona va a operar "Traer leads del origen" desde el menú,
 * hay que añadirla como editora de esta protección (Datos → Hojas e intervalos
 * protegidos) — si no, su corrida fallaría justo al guardar las huellas.
 */
function protegerHuellas(hoja) {
  if (hoja.getProtections(SpreadsheetApp.ProtectionType.SHEET).length) return;
  const p = hoja.protect().setDescription("Memoria del puente — solo el dueño");
  const yo = Session.getEffectiveUser();
  p.addEditor(yo);
  p.removeEditors(p.getEditors().filter(function (u) {
    return u.getEmail() !== yo.getEmail();
  }));
  if (p.canDomainEdit()) p.setDomainEdit(false);
}

function telefonosYaEnLaHoja(hoja) {
  const mapa = {};
  if (hoja.getLastRow() < 2) return mapa;
  hoja.getRange(2, 2, hoja.getLastRow() - 1, 1).getDisplayValues().forEach(function (f) {
    const t = telefonoPeru(f[0]);
    if (t) mapa[t] = true;
  });
  return mapa;
}
