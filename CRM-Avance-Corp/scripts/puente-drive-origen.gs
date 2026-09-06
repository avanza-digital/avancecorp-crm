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
 *
 * SOLO: cada 15 minutos, de lunes a sábado entre las 7 y las 22 (hora de Lima). Casi
 * todas esas corridas no cuestan nada —solo preguntan si el origen creció—; la lectura
 * completa se paga cuando hay algo nuevo, y una vez al día pase lo que pase. "Ver
 * estado del puente" responde en cinco segundos si esto está vivo.
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

// El nombre de la pestaña de leads vive en el CONECTOR (`HOJA_LEADS`), que es quien
// define la forma de esa hoja. Tenerlo dos veces era pedir que un día divergieran.
const HOJA_REVISAR = "REVISAR (no importados)";
const HOJA_HUELLAS = "_puente_huellas"; // oculta: evita traer dos veces lo mismo
const HOJA_MARCAS = "_puente_marcas";   // oculta: hasta qué fila ya miró el puente
const TOPE_POR_PASADA = 500;

/**
 * Cuántas filas como mucho puede DESANDAR `retrocederMarca` de una vez.
 *
 * Retroceder la marca es rescatar; retrocederla de más es abrir la puerta al backlog:
 * las filas viejas SIN fecha que quedan por debajo de la nueva frontera dejan de ser
 * historia y entran al CRM con la fecha de hoy, falseando el divisor de la conversión
 * (en el origen están DISPERSAS —landing 671-872, 2508-5288—, así que un retroceso
 * grande las arrastra sin que se note). Un rescate real es de horas o días, nunca de
 * miles de filas: si de verdad hiciera falta más, se cambia esta constante a
 * conciencia y queda escrito por qué.
 */
const TOPE_RETROCESO = 500;

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
 *
 * 2026-08-11 — corte movido al 2026-08-15 (decisión D6 de Miguel, 2026-08-10). Es la
 * fecha desde la que la conversión mensual empieza a contar de verdad: el dataset se
 * limpió y `crm.leads` quedó en 1 fila, así que lo que entre antes falsearía el
 * divisor del mes de estreno de la métrica.
 *
 * 2026-08-16 — corte movido al LUNES 17 DE AGOSTO (orden de Miguel): «los leads quiero
 * que desde el lunes que viene comiencen a llegar al sistema desde el 17 de agosto».
 * El 15 y el 16 cayeron en sábado y domingo y pasaron sin que la cadena estuviera
 * encendida, así que el arranque real es el lunes. Desde esa fecha, todo lead nuevo
 * entra; nada anterior.
 *
 * 2026-08-16 — LA PUERTA DE ATRÁS, CERRADA. Hasta hoy este corte solo frenaba las filas
 * CON fecha legible: las que vienen sin fecha lo esquivaban por diseño, y la única
 * defensa era acordarse de PAUSAR el temporizador a mano. Eso ya no hace falta — ver
 * la MARCA DE AGUA, abajo. La regla de Miguel del 2026-07-27 («sin fecha → entra»)
 * sigue viva para los leads NUEVOS, que es a los que se refería.
 */
const FECHA_CORTE = "2026-08-17";

/**
 * MARCA DE AGUA — la mitad que le faltaba al corte de fecha.
 *
 * El corte no puede juzgar una fila sin fecha, y el origen tiene cientos de filas
 * viejas a las que nunca les llenaron "Fecha de Registro" (las huellas del 27-jul lo
 * enseñan: las sin fecha están DISPERSAS en medio de la pestaña —landing 671-872,
 * 2508-5288— mientras las fechadas del 23-24 de julio están al final, 6122-6158). Sin
 * más defensa, encender el puente cualquier día metía ese backlog al CRM con la fecha
 * del día, falseando el divisor de la conversión del mes.
 *
 * La señal que sí existe es la POSICIÓN: en este origen las filas nuevas se añaden al
 * final. Así que el puente recuerda hasta qué fila miró cada pestaña y aplica la única
 * regla honesta que se puede aplicar sin fecha:
 *
 *   una fila SIN fecha que ya estaba ahí la vez anterior es BACKLOG (no entra);
 *   una fila SIN fecha que apareció DESPUÉS es un lead nuevo (entra, como pidió Miguel).
 *
 * LA FRONTERA SE PONE A MANO, UNA VEZ: `inicializarMarcas()`. Importa CERO leads, deja
 * el reporte de dónde quedó cada pestaña y no vuelve a mover una marca ya puesta. Una
 * decisión que define qué leads existen y cuáles no, no se toma sola en una corrida
 * automática: una primera pasada que "adoptara" la frontera en silencio sería la misma
 * trampa de antes con otra cara. Por eso, si no hay marcas, el puente SE DETIENE.
 *
 * Y LA MARCA POR NÚMERO DE FILA SOLO VALE SI EL ORIGEN SIGUE CRECIENDO POR ABAJO. Eso
 * es un supuesto, no una ley, así que se comprueba en cada pasada (`revisarPestana`):
 * si desaparecen filas, si cambian los encabezados, si la pestaña es nueva o si las
 * filas ancladas ya no dicen lo mismo, esa pestaña se DETIENE y avisa, en vez de
 * seguir clasificando con una marca que ya miente.
 *
 * Se guarda por sheetId (no por nombre: renombrar la pestaña no puede borrar la
 * memoria) en la pestaña oculta y protegida `_puente_marcas`.
 */
const MOTIVO_BACKLOG = "Sin fecha y ya estaba en el origen";

/** Cuántas filas del final se anclan por contenido para detectar reordenamientos. */
const ANCLA_FILAS = 3;

/**
 * Motivo de los descartes POR DISEÑO (el backlog anterior al corte). Se cuentan en
 * el reporte pero NO se listan en la pestaña de revisión: son cientos y enterrarían
 * los descartes que sí hay que mirar (teléfono malo, sin monto, sin moneda…).
 */
const MOTIVO_CORTE = "Anterior al corte";

/**
 * LO NUEVO POR POSICIÓN NO LO JUZGA EL CORTE (decisión de Miguel, 2026-09-02).
 *
 * El origen añade por abajo: una fila que aparece DESPUÉS de la marca de agua es nueva
 * por construcción, y lo nuevo NO PUEDE ser anterior al corte. Cuando lo parece, la
 * fecha es la que miente, no la posición.
 *
 * Pasó el 2026-09-01: el formulario empezó a escribir "09/01/2026" pensando en MM/DD,
 * la hoja de origen está en es-PE y lo GUARDÓ como 9 de enero. No es un problema de
 * cómo se dibuja la fecha —el valor quedó corrompido al escribirlo—, así que no hay
 * forma de leerlo mejor: `getValues()` devuelve, fielmente, el 9 de enero. Lo único
 * que sigue sabiendo la verdad es el número de fila. 34 leads reales pasaron un día
 * entero fuera del CRM mientras el puente corría en verde.
 *
 * Así que la fecha imposible no descarta: el lead entra con la fecha del ingreso —la
 * misma regla que Miguel fijó el 2026-07-27 para las filas sin fecha—, lo dice en su
 * Nota, se cuenta en el reporte de cada pasada y levanta un aviso en el panel que no
 * se apaga hasta que el origen deje de mandar fechas imposibles.
 *
 * ⚠️ El corte SIGUE INTACTO para todo lo demás: una fila que ya estaba (por encima de
 * la marca) con fecha anterior al corte se descarta igual y en silencio. Lo que cambia
 * es solo el caso en que la posición y la fecha se contradicen.
 */
const AVISO_FECHA_IMPOSIBLE = "fecha-imposible";

/** Los dos descartes que son POLÍTICA, no incidencias: no van a REVISAR. */
function esDescartePorDiseno(motivo) {
  const m = String(motivo || "");
  return m.indexOf(MOTIVO_CORTE) === 0 || m.indexOf(MOTIVO_BACKLOG) === 0;
}

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
    // El orden es el del arranque controlado: preparar → mirar → encender.
    .addItem("1 · Preparar la hoja (formatos y menús)", "prepararHoja")
    .addItem("2 · Inicializar marca de agua (no importa nada)", "inicializarMarcas")
    .addItem("3 · Vista previa (no escribe nada)", "vistaPreviaOrigen")
    .addItem("Diagnóstico de segundos números (no escribe nada)", "diagnosticarSegundosNumeros")
    .addSeparator()
    .addItem("Traer leads del origen (ahora)", "traerLeadsDelOrigen")
    .addSeparator()
    .addItem("Ver estado del puente", "verEstado")
    .addItem("Rescatar filas ya miradas (retroceder la marca)", "retrocederMarca")
    .addSeparator()
    .addItem("Encender el conector (sube al CRM cada 5 min)", "activarConector")
    .addItem("Apagar el conector", "apagarConector")
    .addSeparator()
    .addItem("Activar horario del puente (cada 15 min, lun–sáb)", "instalarHorario")
    .addItem("Ver horario del puente", "verHorario")
    .addItem("Apagar horario del puente", "quitarHorario")
    .addToUi();

  // El menú primero, SIEMPRE, y el aviso después: sin correo, abrir la hoja es el
  // único momento en que algo puede salir a buscarte. Si el aviso fallara, ya se ha
  // dibujado el menú (y avisarEnPantalla se traga lo suyo por dentro).
  avisarEnPantalla();
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

// ── Cadencia: cada 15 minutos, con pre-chequeo barato ────────────────────────

const ZONA_DE_CORRIDA = "America/Lima";     // fijada aquí: NO depende de la zona del proyecto
const FUNCION_PROGRAMADA = "corridaProgramada";

/**
 * POR QUÉ CADA 15 MINUTOS Y NO UNA VEZ AL DÍA.
 *
 * El horario anterior eran seis disparadores semanales a las 9 a. m. Un lead que
 * llegaba a las 9:05 esperaba casi un día entero a que alguien lo llamara, y en
 * captación de ahorro ese día lo es todo.
 *
 * Lo que impedía subir la frecuencia es el COSTE: una pasada completa se descarga las
 * ~12.000 filas × 11 columnas de cada pestaña del origen. Repetir eso 96 veces al día
 * se come la cuota de la cuenta (las cuentas gratuitas tienen un tope diario de tiempo
 * total de disparadores —del orden de hora y media— y encima se comparte con el
 * conector, que ya corre cada 5 minutos).
 *
 * De ahí el PRE-CHEQUEO: cada corrida pregunta primero cuántas filas tiene cada
 * pestaña —metadato, no se descarga ni una celda— y si nada cambió, termina ahí. La
 * pasada completa se paga solo cuando el origen creció.
 *
 * Y como «el número de filas no cambió» NO es lo mismo que «no hay nada que hacer»
 * (alguien pudo borrar una fila e insertar otra en el mismo cuarto de hora), hay un
 * SUELO: al menos UNA pasada completa al día, la primera de la ventana. En el peor
 * caso el coste es el del horario viejo; en el mejor, un lead entra en 15 minutos.
 */
const CADENCIA_MINUTOS = 15;

/**
 * Ventana de corridas, en HORA DE LIMA. El disparador de Apps Script no sabe de días
 * ni de zonas —dispara cada 15 minutos, siempre—, así que es la propia función la que
 * decide si toca. Domingos NO corre (decisión de Miguel, 2026-07-22).
 * `VENTANA_HASTA` es inclusiva: la última corrida del día arranca a las 21:45.
 */
const VENTANA_DESDE = 7;
const VENTANA_HASTA = 21;
const DIA_SIN_CORRIDA = 0; // 0 = domingo

/**
 * Enciende la cadencia: UN disparador cada 15 minutos. Los días y las horas los pone
 * la propia corrida (ver VENTANA_DESDE), no el disparador.
 *
 * Idempotente, y además MIGRA: borra todo disparador que apunte a `corridaProgramada`,
 * incluidos los seis semanales de las 9 a. m. del horario anterior.
 */
function instalarHorario() {
  const borrados = quitarHorario(true);
  ScriptApp.newTrigger(FUNCION_PROGRAMADA)
    .timeBased()
    .everyMinutes(CADENCIA_MINUTOS)
    .create();
  informar(
    "Horario automático ACTIVADO\n\n" +
    "El puente mirará el origen cada " + CADENCIA_MINUTOS + " minutos, de lunes a " +
    "sábado entre las " + VENTANA_DESDE + " y las " + (VENTANA_HASTA + 1) +
    " (hora de Lima). Domingos no corre.\n\n" +
    "Casi todas esas corridas no cuestan nada: solo preguntan cuántas filas tiene el " +
    "origen y, si no creció, terminan ahí. La lectura completa se paga cuando hay " +
    "leads nuevos, y una vez al día pase lo que pase.\n\n" +
    "De ahí, el conector sube los leads al CRM en su ciclo de 5 min.\n\n" +
    (borrados ? "(Se reemplazaron " + borrados + " disparadores anteriores.)" : "")
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
      ? "Horario automático APAGADO (" + n + " disparador(es) quitado(s)).\n\n" +
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
    ? "Horario automático ACTIVO: el puente mira el origen cada " + CADENCIA_MINUTOS +
      " minutos, de lunes a sábado entre las " + VENTANA_DESDE + " y las " +
      (VENTANA_HASTA + 1) + " (hora de Lima)." +
      (propios.length > 1
        ? "\n\n⚠️ Hay " + propios.length + " disparadores donde debería haber UNO. " +
          "Vuelve a ejecutar \"Activar horario del puente\": deja solo el que toca."
        : "")
    : "Horario automático APAGADO. Actívalo con \"Activar horario del puente\".");
  return propios.length;
}

/**
 * LA HORA DE LIMA, por el único camino que no depende de la zona del proyecto de Apps
 * Script (que puede estar en hora del Pacífico sin que nadie se entere hasta que el
 * puente corre de madrugada). Todo lo que este archivo sabe del reloj sale de aquí.
 */
function relojDeLima(fecha) {
  return momentoDe(Utilities.formatDate(fecha || new Date(), ZONA_DE_CORRIDA, "yyyy-MM-dd HH:mm"));
}

/** "AAAA-MM-DD HH:MM" → sus piezas + el día de la semana (0 = domingo). Pura. */
function momentoDe(texto) {
  const m = String(texto || "").match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
  if (!m) throw new Error("No pude leer la hora de Lima: \"" + texto + "\"");
  return {
    fecha: m[1] + "-" + m[2] + "-" + m[3],
    hora: +m[4],
    minuto: +m[5],
    // UTC a propósito: sobre una fecha SIN hora, es aritmética de calendario pura y
    // no puede desplazarse un día por la zona en que corra el intérprete.
    dia: new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).getUTCDay(),
    texto: m[3] + "/" + m[2] + "/" + m[1] + " " + m[4] + ":" + m[5],
  };
}

/** Días enteros entre dos fechas "AAAA-MM-DD". Pura. `null` si alguna no es fecha. */
function diasEntre(desde, hasta) {
  const a = String(desde || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const b = String(hasta || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!a || !b) return null;
  return Math.round(
    (Date.UTC(+b[1], +b[2] - 1, +b[3]) - Date.UTC(+a[1], +a[2] - 1, +a[3])) / 86400000
  );
}

/** ¿Toca correr a esta hora de Lima? Pura: es una decisión de calendario, nada más. */
function dentroDeVentana(reloj) {
  if (!reloj) return { ok: false, motivo: "sin reloj" };
  if (reloj.dia === DIA_SIN_CORRIDA) {
    return { ok: false, motivo: "es domingo y el puente no corre los domingos" };
  }
  if (reloj.hora < VENTANA_DESDE || reloj.hora > VENTANA_HASTA) {
    return {
      ok: false,
      motivo: "son las " + reloj.hora + " h y la ventana es de " + VENTANA_DESDE +
        " a " + (VENTANA_HASTA + 1) + " h (hora de Lima)",
    };
  }
  return { ok: true, motivo: "" };
}

/**
 * EL PRE-CHEQUEO, en su parte decidible sin tocar Hojas de Google. Recibe el tamaño
 * de cada pestaña del origen y la memoria del puente, y responde si hay que pagar la
 * lectura completa.
 *
 * Está escrito para EQUIVOCARSE HACIA MIRAR: cualquier cosa rara —pestaña sin marca,
 * filas que desaparecen, trabajo que quedó a medias por el tope, memoria de estado
 * ilegible— manda hacer la pasada completa, que es la que sabe detener pestañas y
 * avisar. Ahorrar una lectura nunca puede costar un lead.
 */
function decidirPasada(pestanas, marcas, estado, reloj) {
  const motivos = [];
  const detenidas = (estado || {}).detenidas || {};
  (pestanas || []).forEach(function (p) {
    // LO QUE YA SE SABE ROTO NO SE VUELVE A DESCUBRIR CADA CUARTO DE HORA. Una
    // pestaña detenida sigue chocando con su marca en cada pre-chequeo: sin esto,
    // desde el momento en que se detiene una y hasta que un humano la arregla, el
    // puente descargaría las 12.000 filas del origen 96 veces al día — exactamente la
    // cuota que esta cadencia vino a salvar. Solo se salta mientras el origen siga
    // EXACTAMENTE igual que cuando se detuvo; y la pasada del suelo diario vuelve a
    // mirarla (y a avisar) una vez al día.
    if (Number(detenidas[p.id]) === p.filas) return;

    const m = (marcas || {})[p.id];
    if (!m) {
      motivos.push(p.nombre + ": sin marca de agua (pestaña nueva o sin inicializar)");
      return;
    }
    if (p.filas > m.filas) {
      motivos.push(p.nombre + ": creció (" + m.filas + " → " + p.filas + " filas)");
      return;
    }
    if (p.filas < m.filas) {
      motivos.push(p.nombre + ": PERDIÓ filas (" + m.filas + " → " + p.filas + ")");
      return;
    }
    // Mismo tamaño, pero la pasada anterior se quedó a medias por el tope: lo que
    // falta por mirar sigue ahí y no lo va a anunciar ningún crecimiento.
    if (Number(m.ultimaFila) < Number(m.filas)) {
      motivos.push(p.nombre + ": quedó trabajo pendiente de la pasada anterior");
    }
  });

  // EL SUELO DIARIO. "Mismo número de filas" no prueba que el contenido sea el mismo:
  // borrar una fila e insertar otra deja el contador igual. Una pasada completa al día
  // cierra ese hueco y cuesta exactamente lo que costaba el horario viejo.
  const forzada = String((estado || {}).pasadaCompletaEl || "") !== String((reloj || {}).fecha || "");
  if (forzada) motivos.push("suelo diario: hoy todavía no hubo una pasada completa");

  return { mirar: motivos.length > 0, forzada: forzada, motivos: motivos };
}

/**
 * Qué pestañas quedaron detenidas y con qué tamaño, para que el pre-chequeo no
 * vuelva a pagar la lectura completa mientras el origen no cambie.
 */
function mapaDetenidas(incidencias, pestanas) {
  const tam = {};
  (pestanas || []).forEach(function (p) { tam[p.id] = p.filas; });
  const r = {};
  (incidencias || []).forEach(function (x) {
    if (tam[x.id] !== undefined) r[x.id] = tam[x.id];
  });
  return r;
}

/**
 * EL PRE-CHEQUEO BARATO, la mitad que sí toca Hojas. Pregunta solo cuántas filas
 * tiene cada pestaña: es metadato, no descarga celdas.
 *
 * ⚠️ Mide con `Math.max(getLastRow(), 1)` porque es EXACTAMENTE como lo mide la pasada
 * completa (`getDataRange()` devuelve una fila para una pestaña vacía). Comparar dos
 * varas distintas dejaría el pre-chequeo gritando "creció" en cada corrida — o, peor,
 * callado cuando sí creció.
 */
function medirOrigen() {
  const origen = SpreadsheetApp.openById(ORIGEN_ID); // ← solo lectura, ver cabecera
  return origen.getSheets().map(function (p) {
    return {
      id: String(p.getSheetId()),
      nombre: p.getName(),
      filas: Math.max(p.getLastRow(), 1),
    };
  });
}

/**
 * Lo que corre el disparador, cada 15 minutos.
 *
 * NO LANZA. Con esta cadencia, una excepción no controlada son 96 correos de fallo de
 * Google al día: el aviso se vuelve ruido y el ruido se ignora, que es la única forma
 * de que un puente parado pase desapercibido. Aquí se atrapa y se anota un AVISO —
 * con la fecha desde la que dura— que sale en el panel y al abrir la hoja. Las
 * ejecuciones a mano (menú, editor) sí lanzan: ahí hay alguien mirando la pantalla.
 */
function corridaProgramada() {
  const reloj = relojDeLima();
  const ventana = dentroDeVentana(reloj);
  if (!ventana.ok) {
    console.log("Corrida " + reloj.texto + " — no toca: " + ventana.motivo);
    return { omitida: ventana.motivo };
  }
  console.log("Corrida programada — " + reloj.texto);

  try {
    const destino = SpreadsheetApp.getActiveSpreadsheet();
    // Se lee SIN candado a propósito: son lecturas, y lo único que puede pasar es
    // decidir mirar cuando no hacía falta. La pasada completa sí toma el candado.
    const marcas = leerMarcas(destino);
    const estado = leerEstado();

    if (!Object.keys(marcas).length) {
      const aviso =
        "El puente está PARADO: todavía no tiene marca de agua, así que no puede " +
        "distinguir un lead nuevo de una fila vieja del origen y no trae nada.\n\n" +
        "Abre la hoja y ejecuta una vez: AVANCE CORP → \"2 · Inicializar marca de " +
        "agua\". No importa ningún lead; solo anota dónde está hoy el final de cada " +
        "pestaña.";
      anotarAviso("sin-marcas", "El puente está PARADO: falta la marca de agua", aviso, reloj);
      anotarEstado({ ultimaCorrida: reloj.texto, ultimoVeredicto: "PARADO: sin marca de agua" });
      return { omitida: "sin marca de agua" };
    }
    limpiarAviso("sin-marcas"); // ya hay frontera: el aviso deja de tener sentido

    const pestanas = medirOrigen();
    const decision = decidirPasada(pestanas, marcas, estado, reloj);
    const tamanos = pestanas.map(function (p) { return p.nombre + "=" + p.filas; }).join(" · ");

    if (!decision.mirar) {
      console.log("   ↳ sin novedad en el origen (" + tamanos + "): no se lee ni una celda.");
      anotarEstado(fusionar(
        vigilarFuente(estado, pestanas, reloj),
        { ultimaCorrida: reloj.texto, ultimoVeredicto: "sin novedad en el origen" }
      ));
      return { omitida: "sin novedad", pestanas: pestanas };
    }

    console.log("   ↳ toca leer: " + decision.motivos.join(" · "));
    const r = procesar(true);
    console.log(resumen(r));

    anotarEstado(fusionar(
      vigilarFuente(estado, pestanas, reloj),
      {
        ultimaCorrida: reloj.texto,
        ultimoVeredicto: r.aceptados.length + " leads traídos, " +
          r.rechazados.length + " descartados",
        pasadaCompletaEl: reloj.fecha,
        ultimaPasadaCompleta: reloj.texto,
        traidosUltimaPasada: r.aceptados.length,
        incidencias: r.incidencias.map(function (x) { return x.pestana + ": " + x.motivo; }),
        detenidas: mapaDetenidas(r.incidencias, pestanas),
        ultimoError: "",
      }
    ));

    // La pasada salió: si algo había fallado antes, ya no falla.
    limpiarAviso("error");
    if (r.incidencias.length) {
      anotarAviso(
        "pestana-detenida",
        r.incidencias.length + " pestaña(s) detenida(s): el puente NO trajo lo que había ahí",
        "El puente detuvo estas pestañas porque su marca de agua dejó de ser fiable:\n\n" +
        r.incidencias.map(function (x) { return "   · " + x.pestana + ": " + x.motivo; }).join("\n") +
        "\n\nSu marca quedó INTACTA y no se importó nada de ellas. Revisa el origen y, " +
        "si el cambio es legítimo, borra la fila de esa pestaña en \"" + HOJA_MARCAS +
        "\" y vuelve a ejecutar \"Inicializar marca de agua\".",
        reloj
      );
    } else {
      limpiarAviso("pestana-detenida");
    }
    // No frena nada —los leads entran—, pero el origen está corrompiendo un dato y
    // eso no puede vivir solo en el reporte de una corrida que nadie abre.
    if (r.fechasImposibles) {
      anotarAviso(
        AVISO_FECHA_IMPOSIBLE,
        r.fechasImposibles + " lead(s) con FECHA IMPOSIBLE: el origen está guardando mal la fecha",
        "Filas recién llegadas al origen vienen fechadas ANTES del corte (" + FECHA_CORTE +
        "), lo que no puede ser: se añaden por abajo. Pasó el 2026-09-01, cuando el " +
        "formulario empezó a escribir la fecha con el mes por delante (\"09/01/2026\") y " +
        "la hoja de origen la guardó como 9 de enero.\n\n" +
        "NO se pierde ningún lead: entran con la fecha del día en que llegan al CRM y " +
        "su Nota lo dice. Lo que hay que arreglar está en el ORIGEN — que la columna " +
        "\"Fecha de Registro\" vuelva a escribirse como la lee esa hoja.",
        reloj
      );
    } else {
      limpiarAviso(AVISO_FECHA_IMPOSIBLE);
    }
    return r;
  } catch (e) {
    const detalle = (e && e.message) ? e.message : String(e);
    // Una corrida que se topa con otra en marcha NO es un fallo: es el candado
    // haciendo su trabajo (una pasada lenta sobre 12.000 filas puede pisar a la
    // siguiente). Anotarlo como avería sería poner el panel en rojo por lo que
    // funciona bien, y un panel en rojo permanente no lo mira nadie.
    if (/Ya hay una corrida/.test(detalle)) {
      console.log("Corrida " + reloj.texto + " omitida: ya había otra en marcha.");
      anotarEstado({ ultimaCorrida: reloj.texto, ultimoVeredicto: "omitida: otra corrida en marcha" });
      return { omitida: "solapada" };
    }
    console.error("Corrida " + reloj.texto + " FALLIDA: " + detalle);
    anotarEstado({
      ultimaCorrida: reloj.texto,
      ultimoVeredicto: "FALLÓ",
      ultimoError: reloj.texto + " — " + detalle,
    });
    anotarAviso(
      "error",
      "La última corrida FALLÓ",
      "La corrida automática de las " + reloj.texto + " terminó con un error:\n\n" +
      detalle + "\n\nLa marca de agua NO avanza cuando una corrida falla, así que no " +
      "se pierde ningún lead: la próxima corrida vuelve a mirar esas filas. Si el " +
      "error se repite, el detalle completo está en el Registro de ejecución del " +
      "proyecto de Apps Script.",
      reloj
    );
    return { omitida: "error", error: detalle };
  }
}

// ── Estado y avisos ──────────────────────────────────────────────────────────

/**
 * DIARIO DE A BORDO. Vive en las Propiedades del script, no en una pestaña: no hay
 * que crearla, ni protegerla, ni cuidar en qué posición queda (una pestaña de más
 * delante de LEADS pone al conector a importar cualquier cosa — ya pasó).
 *
 * ⚠️ ES OBSERVABILIDAD, NO MEMORIA. Quién entra y quién no lo deciden la marca de
 * agua y las huellas, que viven en la hoja. Si esto se pierde o se corrompe, el
 * puente sigue trayendo exactamente los mismos leads: lo único que pasa es que el
 * panel queda en blanco y hoy se hace una lectura completa de más. Por eso todas las
 * funciones de aquí abajo tragan sus errores en vez de tumbar la corrida.
 */
const PROP_ESTADO = "PUENTE_ESTADO";

/**
 * SIN CORREO (decisión de Miguel, 2026-08-16). Los avisos no se envían a ningún
 * lado: se ANOTAN en el diario, salen en el Registro de ejecución y aparecen en dos
 * sitios donde alguien los va a ver — el panel («Ver estado del puente») y un
 * mensaje al ABRIR la hoja, que es lo que de verdad se abre todos los días.
 *
 * Ventaja que no es menor: sin `MailApp` el proyecto no pide ningún permiso nuevo,
 * así que pegar los scripts no obliga a re-autorizar nada.
 *
 * Lo que se pierde, dicho claro: nadie recibe un empujón fuera de la hoja. Un puente
 * parado se descubre al abrirla, no en el momento. A cambio, cada aviso lleva DESDE
 * CUÁNDO está activo y **se borra solo** cuando el problema deja de existir — un
 * aviso que no se apaga miente igual que uno que nunca suena.
 */
function leerEstado() {
  try {
    const s = PropertiesService.getScriptProperties().getProperty(PROP_ESTADO);
    return s ? JSON.parse(s) : {};
  } catch (e) {
    console.error("No pude leer el estado del puente (" + e.message + "). Sigo igual: " +
      "el estado es un diario, no la memoria.");
    return {};
  }
}

/** Escribe el estado entero. Nunca lanza: ver la nota de PROP_ESTADO. */
function guardarEstado(estado) {
  try {
    PropertiesService.getScriptProperties().setProperty(PROP_ESTADO, JSON.stringify(estado || {}));
  } catch (e) {
    console.error("No pude guardar el estado del puente: " + e.message);
  }
  return estado;
}

/** Anota unos pocos campos sobre lo ya guardado (releyendo, para no pisar alertas). */
function anotarEstado(parcial) {
  return guardarEstado(fusionar(leerEstado(), parcial || {}));
}

/**
 * ¿Está entrando algo en el origen? Es una pregunta distinta de «¿hay leads nuevos
 * para el CRM?»: mide el tamaño CRUDO de las pestañas, sin marca de agua ni corte de
 * por medio. Devuelve lo que hay que anotar en el diario.
 *
 * Que el origen lleve semanas seco NO es un aviso: es un HECHO conocido desde el
 * 24-jul-2026 y una hoja que no es nuestra. Convertirlo en alarma sería tener el
 * puente en rojo permanente, que es la forma más rápida de dejar de mirar el rojo.
 * Va como un dato más del panel, con los días contados.
 */
function vigilarFuente(estado, pestanas, reloj) {
  const previo = (estado || {}).filasOrigen || {};
  const ahora = {};
  let crecio = false;
  (pestanas || []).forEach(function (p) {
    ahora[p.id] = p.filas;
    if (previo[p.id] !== undefined && p.filas > Number(previo[p.id])) crecio = true;
  });

  const parcial = { filasOrigen: ahora };
  // La primera vez no se puede afirmar que creció ni que está seco: solo desde
  // cuándo lo estamos mirando. Inventar aquí una fecha de crecimiento sería mentir
  // en el panel justo el día en que el panel se estrena.
  if (!(estado || {}).vigilaDesde) parcial.vigilaDesde = reloj.fecha;
  if (crecio) parcial.crecioEl = reloj.fecha;
  return parcial;
}

/**
 * Anota un aviso en el diario. NO manda correo (ver la nota de PROP_ESTADO): queda
 * en el Registro de ejecución, sale en el panel y salta al abrir la hoja.
 *
 * Guarda DESDE CUÁNDO está activo, no cuántas veces se repitió: «parado desde el
 * lunes a las 9:15» dice algo; «se avisó 96 veces» no dice nada.
 */
function anotarAviso(clave, titulo, detalle, reloj) {
  const avisos = leerEstado().avisos || {};
  const previo = avisos[clave];
  avisos[clave] = {
    desde: (previo && previo.desde) || reloj.texto,
    ultimo: reloj.texto,
    titulo: titulo,
    detalle: detalle,
  };
  if (previo) console.log("(sigue activo desde " + avisos[clave].desde + ") " + titulo);
  else console.error("AVISO — " + titulo + "\n" + detalle);
  anotarEstado({ avisos: avisos });
  return avisos[clave];
}

/**
 * Apaga un aviso porque el problema dejó de existir. Es la mitad que se olvida: un
 * aviso que no se apaga solo miente igual que uno que nunca suena, y encima enseña a
 * ignorar el panel.
 */
function limpiarAviso(clave) {
  const avisos = leerEstado().avisos || {};
  if (!avisos[clave]) return false;
  console.log("Resuelto: " + (avisos[clave].titulo || clave));
  delete avisos[clave];
  anotarEstado({ avisos: avisos });
  return true;
}

/**
 * Lo que se ve al ABRIR la hoja si hay algo que mirar. Es el sustituto del correo:
 * la hoja se abre casi todos los días, y esto no cuesta ningún permiso nuevo.
 *
 * Se llama desde el menú, que puede venir del `onOpen` SIMPLE (corre sin
 * autorización). Por eso va entero dentro de un try: si ahí no se pudieran leer las
 * propiedades, el menú tiene que aparecer igual. Nunca al revés — el aviso no puede
 * costar el menú.
 *
 * ⚠️ Con el disparador simple no está garantizado que salga. Donde SÍ está es con el
 * disparador INSTALABLE que crea `instalarMenu()` (corre con autorización completa):
 * ejecutarlo una vez es lo que hace del banner un canal fiable. Va en la Fase 5.
 */
function avisarEnPantalla() {
  try {
    const avisos = leerEstado().avisos || {};
    const claves = Object.keys(avisos);
    if (!claves.length) return 0;
    SpreadsheetApp.getActiveSpreadsheet().toast(
      claves.map(function (k) {
        return "• " + avisos[k].titulo + " (desde " + avisos[k].desde + ")";
      }).join("\n") + "\n\nMenú AVANCE CORP → \"Ver estado del puente\".",
      "⚠️ El puente tiene " + claves.length + " aviso(s)",
      30
    );
    return claves.length;
  } catch (e) {
    return 0;
  }
}

// ── El panel: ¿esto está vivo? ───────────────────────────────────────────────

/**
 * Lo que antes había que reconstruir a mano abriendo tres pestañas y el Registro de
 * ejecución. Solo LEE. Es la respuesta a la pregunta que de verdad se hace uno:
 * «¿el puente está funcionando, o lleva semanas parado y nadie se ha dado cuenta?».
 */
function verEstado() {
  const destino = SpreadsheetApp.getActiveSpreadsheet();
  const reloj = relojDeLima();
  const disparadores = ScriptApp.getProjectTriggers();
  const cuantos = function (nombre) {
    return disparadores.filter(function (t) { return t.getHandlerFunction() === nombre; }).length;
  };
  const datos = {
    reloj: reloj,
    ventana: dentroDeVentana(reloj),
    puente: cuantos(FUNCION_PROGRAMADA),
    conector: cuantos("importarLeads"),
    marcas: leerMarcas(destino),
    estado: leerEstado(),
    pestanas: medirOrigen(),
    hoja: contarEstadosDeLeads(hojaDeLeads(destino)),
  };
  informar(textoDelPanel(datos));
  return datos;
}

/** El panel, como texto. PURA: recibe los datos ya leídos, así se puede probar. */
function textoDelPanel(d) {
  const est = d.estado || {};
  const marcas = d.marcas || {};
  let t = "ESTADO DEL PUENTE — " + d.reloj.texto + " (hora de Lima)\n";

  // Los avisos van ARRIBA DEL TODO y con su antigüedad: lo primero que hay que saber
  // es si algo está roto, y desde cuándo. Si no hay ninguno, se dice también — el
  // silencio no se distingue de que el panel no funcione.
  const avisos = est.avisos || {};
  const claves = Object.keys(avisos);
  if (claves.length) {
    t += "\n⛔ AVISOS ACTIVOS (" + claves.length + ")\n";
    claves.forEach(function (k) {
      t += "   · " + avisos[k].titulo + " — desde " + avisos[k].desde + "\n";
      t += "     " + String(avisos[k].detalle || "").split("\n")[0] + "\n";
    });
  } else {
    t += "\n✓ Sin avisos activos.\n";
  }

  t += "\nMÁQUINA\n";
  t += "   · Puente: " + (d.puente
    ? "ENCENDIDO, mira cada " + CADENCIA_MINUTOS + " min · lun–sáb de " + VENTANA_DESDE +
      " a " + (VENTANA_HASTA + 1) + " h" + (d.puente > 1 ? " ⚠️ (" + d.puente + " disparadores donde debería haber 1)" : "")
    : "APAGADO — no trae nada solo") + "\n";
  t += "   · Ahora mismo: " + (d.ventana.ok ? "toca correr" : "no toca (" + d.ventana.motivo + ")") + "\n";
  t += "   · Conector al CRM: " + (d.conector ? "ENCENDIDO, cada 5 min" : "APAGADO — los leads se quedan en la hoja") + "\n";
  t += "   · Corte de fecha: " + (FECHA_CORTE || "sin corte ⚠️") + "\n";

  t += "\nÚLTIMA CORRIDA\n";
  t += est.ultimaCorrida
    ? "   · " + est.ultimaCorrida + " — " + (est.ultimoVeredicto || "sin detalle") + "\n"
    : "   · Todavía no ha corrido ninguna (o el diario se borró)\n";
  if (est.ultimaPasadaCompleta) {
    t += "   · Última lectura completa del origen: " + est.ultimaPasadaCompleta +
      " (" + (est.traidosUltimaPasada || 0) + " leads traídos)\n";
  }
  if (est.ultimoError) t += "   · ⛔ Último error: " + est.ultimoError + "\n";
  if (est.incidencias && est.incidencias.length) {
    t += "   · ⛔ PESTAÑAS DETENIDAS en la última lectura:\n";
    est.incidencias.forEach(function (x) { t += "        " + x + "\n"; });
  }

  t += "\nEL ORIGEN\n";
  (d.pestanas || []).forEach(function (p) {
    const m = marcas[p.id];
    t += "   · " + p.nombre + ": " + p.filas + " filas · " +
      (m ? "frontera en la " + m.ultimaFila + " (puesta el " + (m.actualizado || "?") + ")"
         : "⛔ SIN marca de agua — el puente no puede traer de aquí") + "\n";
  });
  const desde = est.crecioEl || est.vigilaDesde || "";
  const dias = desde ? diasEntre(desde, d.reloj.fecha) : null;
  if (dias === null) {
    t += "   · Sin datos todavía de cuándo creció por última vez\n";
  } else if (!est.crecioEl) {
    // El primer día NO se puede afirmar nada del origen: solo que empezamos a mirar.
    // Decir "Recibió filas HOY" —lo que salía antes— es la mentira más cara posible
    // en este panel, porque es justo la pregunta que trajo aquí a todo el mundo.
    t += "   · Vigilado desde hace " + dias + " día(s); todavía sin verlo crecer ni una vez\n";
  } else if (dias === 0) {
    t += "   · Recibió filas HOY\n";
  } else {
    t += "   · " + (est.crecioEl ? "Sin recibir una fila nueva desde hace " : "Sin recibir nada en los ") +
      dias + " días" + (est.crecioEl ? "" : " que lleva vigilado") + "\n";
  }

  t += "\nNUESTRA HOJA\n";
  const h = d.hoja || {};
  t += "   · " + (h.total || 0) + " filas con datos · " + (h.pendientes || 0) +
    " esperando subir al CRM · " + (h.importados || 0) + " subidas · " +
    (h.duplicados || 0) + " duplicadas · " + (h.rechazados || 0) + " rechazadas" +
    (h.ya_clientes ? " · " + h.ya_clientes + " ya clientes (reingreso en su ficha)" : "") +
    (h.errores ? " · " + h.errores + " con error temporal" : "") + "\n";
  return t;
}

/** Cuenta la columna de estado de nuestra hoja. Dos columnas, no la hoja entera. */
function contarEstadosDeLeads(hoja) {
  const cuenta = { total: 0, pendientes: 0, importados: 0, duplicados: 0, ya_clientes: 0, rechazados: 0, errores: 0, otros: 0 };
  const ultima = hoja.getLastRow();
  if (ultima < 2) return cuenta;
  const identidad = hoja.getRange(2, 1, ultima - 1, 2).getDisplayValues(); // nombre y teléfono
  const estados = hoja.getRange(2, COL_ESTADO, ultima - 1, 1).getDisplayValues();
  for (let i = 0; i < estados.length; i++) {
    // Fila vacía de la rejilla = sin nombre, sin teléfono y sin estado. Una fila con
    // el teléfono principal vacío (el importador acepta solo el alternativo) o con
    // estado escrito SÍ cuenta (Codex v5 #1).
    const hayDatos = String(identidad[i][0]).trim() || String(identidad[i][1]).trim() || String(estados[i][0]).trim();
    if (!hayDatos) continue;
    cuenta.total++;
    const e = String(estados[i][0]).trim();
    if (!e) cuenta.pendientes++;
    else if (e.indexOf("IMPORTADO") === 0) cuenta.importados++;
    else if (e.indexOf("RECHAZADO") === 0) cuenta.rechazados++;
    else if (e.indexOf("ERROR") === 0) cuenta.errores++;
    else if (e.indexOf("DUPLICADO") === 0) cuenta.duplicados++;
    else if (e.indexOf("YA ES CLIENTE") === 0) cuenta.ya_clientes++;
    else cuenta.otros++;
  }
  return cuenta;
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

/**
 * DIAGNÓSTICO DE SEGUNDOS NÚMEROS — Fase 0 del plan "Los dos números del lead".
 *
 * Responde, sobre el ORIGEN REAL y sin escribir absolutamente nada: de cada fila
 * que trae lead, ¿cuántas dan un segundo número aprovechable, cuántas repiten el
 * primero, cuántas dan un FIJO (que hoy se pierde) y cuántas dan algo ilegible?
 *
 * Existe porque el número que importa —"¿cuántos leads DEBERÍAN llegar con dos
 * números?"— nunca se midió, y sin él no se sabe si arreglar el puente vale 900
 * leads o 40. Mide lo que HAY en el origen, no lo que el puente deja pasar: por
 * eso mira las celdas telefónicas por su ENCABEZADO y no reusa telefonosDeFila(),
 * que ya viene filtrado por la regla que estamos evaluando.
 *
 * No toca el origen (solo getSheets/getDataRange/getDisplayValues), no toca
 * nuestra hoja, no mueve marcas de agua ni huellas. Se puede correr las veces
 * que haga falta.
 */
function diagnosticarSegundosNumeros() {
  const origen = SpreadsheetApp.openById(ORIGEN_ID); // ← solo lectura, ver cabecera
  const totales = nuevoConteoSegundos();
  const porPestana = [];

  origen.getSheets().forEach(function (pestana) {
    const datos = pestana.getDataRange().getDisplayValues();
    if (datos.length < 2) return;
    const col = ubicarColumnas(datos[0]);
    if (col.telefono < 0 && col.whatsapp < 0) return; // no es pestaña de leads

    const indices = celdasTelefonicas(datos[0], col);
    const cuenta = nuevoConteoSegundos();
    for (let i = 1; i < datos.length; i++) {
      const fila = datos[i];
      if (fila.every(function (c) { return String(c).trim() === ""; })) continue;
      if (esFilaDeEncabezado(fila, datos[0])) continue;
      clasificarSegundoNumero(fila, col, indices, cuenta);
    }
    porPestana.push({
      pestana: pestana.getName(),
      columnas: indices.map(function (i) { return datos[0][i] || "(col " + (i + 1) + ")"; }),
      cuenta: cuenta,
    });
    sumarConteoSegundos(totales, cuenta);
  });

  const texto = informeSegundosNumeros(porPestana, totales);
  console.log(texto);
  informar(texto);
  return { porPestana: porPestana, totales: totales };
}

/** Las celdas de la fila donde el origen pone teléfonos, por ENCABEZADO. */
function celdasTelefonicas(cabeceras, col) {
  const ES_TELEFONO = /celular|telefono|movil|whatsapp|numero|contacto|^tel\b/;
  const indices = [];
  if (col.telefono >= 0) indices.push(col.telefono);
  if (col.whatsapp >= 0 && col.whatsapp !== col.telefono) indices.push(col.whatsapp);
  cabeceras.forEach(function (bruto, i) {
    if (indices.indexOf(i) >= 0 || i === col.monto || i === col.dni) return;
    if (ES_TELEFONO.test(normalizar(bruto))) indices.push(i);
  });
  return indices;
}

function nuevoConteoSegundos() {
  return {
    filas: 0,          // filas con al menos un teléfono usable
    sinSegundo: 0,     // el origen solo dio un número
    repetido: 0,       // dio dos, pero es el mismo (WhatsApp = celular)
    celular: 0,        // segundo celular distinto → HOY YA LLEGA
    fijo: 0,           // segundo número fijo → HOY SE PIERDE
    ilegible: 0,       // había algo escrito y no es un teléfono → HOY SE PIERDE
    sinTelefono: 0,    // la fila no trae ni un número usable
  };
}

function sumarConteoSegundos(destino, origen) {
  Object.keys(destino).forEach(function (k) { destino[k] += origen[k]; });
}

/**
 * Clasifica UNA fila. `cuenta` se modifica en sitio.
 *
 * El principal se decide igual que en producción (primer celular válido en orden
 * de confianza) para que el diagnóstico hable del MISMO lead que entraría hoy.
 * Lo que cambia es el segundo: aquí se mira TODO lo que el origen escribió en
 * una celda telefónica, incluido lo que la regla actual tira.
 */
function clasificarSegundoNumero(fila, col, indices, cuenta) {
  let principal = "";
  let usadaPrincipal = -1;
  for (let k = 0; k < indices.length; k++) {
    const t = telefonoContacto(fila[indices[k]]);
    if (t) { principal = t; usadaPrincipal = indices[k]; break; }
  }
  if (!principal) { cuenta.sinTelefono++; return; }
  cuenta.filas++;

  // El MEJOR segundo que ofrece la fila, por orden de utilidad comercial:
  // otro celular > un fijo > algo escrito que no es teléfono.
  let veredicto = "sinSegundo";
  for (let k = 0; k < indices.length; k++) {
    const i = indices[k];
    if (i === usadaPrincipal) continue;
    const crudo = String(fila[i] == null ? "" : fila[i]).trim();
    if (!crudo) continue;
    const r = reconocerTelefono(crudo);
    if (r && r.e164 !== principal) {
      if (r.movil) { veredicto = "celular"; break; }
      if (veredicto !== "celular") veredicto = "fijo";
      continue;
    }
    if (r) { if (veredicto === "sinSegundo") veredicto = "repetido"; continue; }
    // Un correo metido en la columna de teléfono no es "un número ilegible":
    // es otro dato en el sitio equivocado y contarlo inflaría lo que se pierde.
    if (crudo.indexOf("@") >= 0) continue;
    if (/\d/.test(crudo) && veredicto === "sinSegundo") veredicto = "ilegible";
  }
  cuenta[veredicto]++;
}

/** El informe en el idioma del negocio: qué llega hoy y qué se está perdiendo. */
function informeSegundosNumeros(porPestana, t) {
  const pct = function (n) {
    return t.filas ? " (" + Math.round((n * 1000) / t.filas) / 10 + "%)" : "";
  };
  const lineas = [
    "DIAGNÓSTICO DE SEGUNDOS NÚMEROS — no se escribió nada",
    "",
    "Sobre " + t.filas + " filas del origen que traen un teléfono usable:",
    "",
    "  Con segundo celular distinto ....... " + t.celular + pct(t.celular) + "   ← HOY YA LLEGA",
    "  Con un fijo como segundo ........... " + t.fijo + pct(t.fijo) + "   ← hoy SE PIERDE",
    "  Con algo escrito que no es número .. " + t.ilegible + pct(t.ilegible) + "   ← hoy SE PIERDE",
    "  Repiten el mismo número ............ " + t.repetido + pct(t.repetido) + "   (no hay segundo que dar)",
    "  Solo dieron un número .............. " + t.sinSegundo + pct(t.sinSegundo),
    "",
    "  Filas sin ningún teléfono usable ... " + t.sinTelefono,
    "",
    "TECHO REAL: " + (t.celular + t.fijo) + " de " + t.filas +
      " filas pueden llegar al CRM con dos números.",
    "",
    "Por pestaña:",
  ];
  porPestana.forEach(function (p) {
    lineas.push(
      "  · " + p.pestana + " — " + p.cuenta.filas + " filas · " +
      p.cuenta.celular + " con 2.º celular · " + p.cuenta.fijo + " con fijo · " +
      p.cuenta.ilegible + " ilegibles · " + p.cuenta.repetido + " repetidos"
    );
    lineas.push("      columnas miradas: " + p.columnas.join(" | "));
  });
  return lineas.join("\n");
}

function traerLeadsDelOrigen() {
  const reloj = relojDeLima();
  const r = procesar(true);
  // Una corrida a mano cuenta como lectura completa del día: el suelo diario ya está
  // pagado y el panel no puede decir que hoy nadie miró el origen.
  anotarEstado({
    ultimaCorrida: reloj.texto,
    ultimoVeredicto: "a mano: " + r.aceptados.length + " leads traídos, " +
      r.rechazados.length + " descartados",
    pasadaCompletaEl: reloj.fecha,
    ultimaPasadaCompleta: reloj.texto,
    traidosUltimaPasada: r.aceptados.length,
    incidencias: r.incidencias.map(function (x) { return x.pestana + ": " + x.motivo; }),
    detenidas: r.incidencias.length ? mapaDetenidas(r.incidencias, medirOrigen()) : {},
    ultimoError: "",
  });
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

  // Las incidencias van ARRIBA del todo: una pestaña detenida significa que el puente
  // NO trajo lo que había ahí, y eso no puede leerse como "hoy no hubo leads".
  let t = "";
  if (r.incidencias && r.incidencias.length) {
    t += "⛔ PESTAÑAS DETENIDAS — no se trajo nada de ellas:\n";
    r.incidencias.forEach(function (x) {
      t += "   · " + x.pestana + ": " + x.motivo + "\n";
    });
    t += "\nSu marca de agua quedó intacta. Revisa el origen y, si el cambio es " +
      "legítimo, borra la fila de esa pestaña en \"_puente_marcas\" y vuelve a " +
      "ejecutar \"Inicializar marca de agua\".\n\n";
  }

  t += FECHA_CORTE
    ? "CORTE ACTIVO: se frena lo fechado ANTES del " + FECHA_CORTE +
      ", y lo que no trae fecha se frena por la marca de agua.\n\n"
    : "⚠️ SIN CORTE: entraría TODO lo fechado del origen, incluido el backlog viejo.\n\n";

  t += "Filas leídas del origen: " + r.leidas +
    "\nLeads utilizables: " + r.aceptados.length +
    "\n   · de esos, " + noAutoriza + " marcaron NO autorizar → entran como no-contactar" +
    (conPregunta ? "\n   · " + conPregunta + " traen COMENTARIO del cliente → va al inicio de la Nota" : "") +
    (sinMonto ? "\n   · " + sinMonto + " SIN MONTO → entran con " + MONTO_SI_NO_INDICA + " y aviso en la Nota" : "") +
    (sinMoneda ? "\n   · " + sinMoneda + " SIN MONEDA → entran como " + MONEDA_SI_NO_INDICA + " y aviso en la Nota" : "") +
    (sinFecha ? "\n   · " + sinFecha + " sin fecha en el origen → entran contando desde hoy" : "") +
    (r.fechasImposibles
      ? "\n   · ⚠️ " + r.fechasImposibles + " con FECHA IMPOSIBLE en el origen (filas recién " +
        "llegadas fechadas antes del corte): entran con la fecha de hoy. El origen está " +
        "guardando mal la fecha — revísalo allí"
      : "") +
    (telRescatado ? "\n   · " + telRescatado + " con el teléfono fuera de su columna → número rescatado" : "") +
    "\nYa traídos antes (se omiten): " + r.repetidosPasadas +
    (r.backlogSinFecha
      ? "\nBacklog sin fecha frenado por la marca de agua: " + r.backlogSinFecha +
        " (no van a REVISAR: son historia, no incidencias)"
      : "") +
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

/**
 * TODA pasada que ESCRIBE va con candado. No es paranoia: la corrida de las 9 y un
 * "Traer leads del origen" pulsado a mano se solapan sin esfuerzo, y como las huellas
 * se guardan al FINAL, las dos leerían la misma memoria vieja y escribirían los mismos
 * leads dos veces. El candado se toma aquí, en la puerta, y no en cada llamador: así
 * ningún camino de escritura puede olvidarse de pedirlo.
 */
function procesar(escribir) {
  if (!escribir) return procesarNucleo(false); // la vista previa no escribe: no estorba
  return conCandado(function () { return procesarNucleo(true); });
}

/** Ejecuta `fn` con el candado del proyecto tomado, o se niega a correr. */
function conCandado(fn) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) {
    throw new Error(
      "Ya hay una corrida del puente en marcha (la automática o una manual). No se " +
      "lanza una segunda: se pisarían y escribirían los mismos leads dos veces. " +
      "Espera a que termine y vuelve a intentarlo."
    );
  }
  try {
    return fn();
  } finally {
    lock.releaseLock();
  }
}

function procesarNucleo(escribir) {
  const destino = SpreadsheetApp.getActiveSpreadsheet();
  if (!destino) {
    throw new Error(
      "No hay hoja activa. Este script tiene que vivir DENTRO de la hoja " +
      "\"Leads AVANCE CORP — captura para CRM\" (Extensiones → Apps Script), " +
      "no como proyecto suelto de script.google.com."
    );
  }
  // Por NOMBRE, sin respaldo por posición: verificado el 2026-08-16 que la pestaña se
  // llama exactamente "LEADS". El respaldo `getSheets()[0]` no tapaba ninguna
  // diferencia y sí abría la puerta a escribir leads en la pestaña equivocada.
  const hojaLeads = hojaDeLeads(destino);
  console.log("Destino: " + destino.getName() + " → pestaña \"" + hojaLeads.getName() + "\"");

  const huellas = leerHuellas(destino);          // lo ya traído en pasadas previas
  const marcasPrevias = leerMarcas(destino);     // hasta qué fila ya miró cada pestaña
  const telefonosEnHoja = telefonosYaEnLaHoja(hojaLeads); // y lo ya escrito a mano
  const vistosAhora = {};
  const marcasNuevas = {};

  // SE DETIENE SI NO HAY FRONTERA. Sin marcas no se puede distinguir un lead nuevo sin
  // fecha de una fila vieja sin fecha, y adoptar la frontera aquí, en silencio, sería
  // exactamente la trampa que esta defensa vino a cerrar. Se pone a mano, una vez.
  if (!Object.keys(marcasPrevias).length) {
    throw new Error(
      "El puente NO tiene marca de agua todavía, así que no puede saber qué fila del " +
      "origen es un lead nuevo y cuál es historia.\n\n" +
      "Ejecuta UNA VEZ \"AVANCE CORP → Inicializar marca de agua\": no importa ningún " +
      "lead, solo anota dónde está hoy el final de cada pestaña. Después de eso, el " +
      "puente ya puede correr."
    );
  }

  const origen = SpreadsheetApp.openById(ORIGEN_ID); // ← solo lectura, ver cabecera
  // La zona del ORIGEN es la que decide qué día muestra una celda de fecha suya; si no
  // la declara, se supone la nuestra (ver `fechasNativas`).
  const zonaOrigen = origen.getSpreadsheetTimeZone() || ZONA_DE_CORRIDA;
  const aceptados = [];
  const rechazados = [];
  const duplicados = []; // rechazados por duplicado: se huellán para no re-listarlos
  const incidencias = []; // pestañas detenidas porque su marca dejó de ser fiable
  let leidas = 0;
  let repetidosPasadas = 0;
  let backlogSinFecha = 0;
  let fechasImposibles = 0;

  origen.getSheets().forEach(function (pestana) {
    // El tope es de la PASADA entera, no de cada pestaña: sin esto, el `break` de
    // abajo solo cortaba la pestaña en curso y la siguiente seguía sumando
    // (por eso una corrida con tope 500 devolvió 501).
    if (aceptados.length >= TOPE_POR_PASADA) return;

    const nombrePestana = pestana.getName();
    // La memoria va por sheetId: renombrar la pestaña no puede borrarla.
    const idPestana = String(pestana.getSheetId());
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
    // ¿SIGUE SIENDO VERDAD LO QUE LA MARCA SUPONE? Si el origen perdió filas, le
    // cambiaron los encabezados, la pestaña es nueva o las filas ancladas ya no dicen
    // lo mismo (se ordenó o se insertó en medio), la marca dejó de significar nada:
    // esta pestaña se detiene entera y se avisa. No se trae ni un lead de ella y su
    // marca queda intacta, para que nadie tenga que adivinar dónde estaba.
    //
    // ⚠️ VA ANTES QUE EL CHEQUEO DE TELÉFONO, Y ESE ORDEN ES LA DEFENSA. Al revés
    // —como estuvo hasta el 2026-08-16— renombrar en el origen las dos columnas de
    // teléfono hacía que la pestaña se saltara AQUÍ, en silencio: sin incidencia, sin
    // aviso, y encima apagando el aviso anterior porque la pasada terminaba "sin
    // incidencias". Dejarían de llegar leads y el panel diría que todo está bien, que
    // es exactamente el fallo que el panel existe para hacer imposible.
    const marca = marcasPrevias[idPestana];
    const veredicto = revisarPestana(
      marca,
      datos.length,
      huellaCabeceras(datos[0]),
      marca ? anclaDeFilas(datos, marca.ultimaFila) : ""
    );
    if (!veredicto.ok) {
      incidencias.push({ pestana: nombrePestana, id: idPestana, motivo: veredicto.motivo });
      console.log("   ↳ ⛔ PESTAÑA DETENIDA: " + veredicto.motivo);
      return;
    }

    // Ya sabemos que la pestaña es la MISMA de siempre. Si aun así no tiene columna de
    // teléfono, es que nunca fue una pestaña de leads (un resumen, una hoja de
    // trabajo): se salta en silencio y con razón, porque no ha cambiado nada.
    if (col.telefono < 0 && col.whatsapp < 0) {
      console.log("   ↳ omitida: no encontré columna de teléfono.");
      return;
    }

    // Lo que Sheets GUARDA en las columnas de fecha, no lo que dibuja: es lo que hace
    // al puente inmune a que el origen cambie el formato (ver `fechasNativas`).
    const nativas = fechasNativas(pestana, col.fechas, datos.length, zonaOrigen);

    const frontera = marca.ultimaFila;
    let ultimaFilaVista = frontera;
    console.log("   ↳ marca de agua: fila " + frontera + " (de ahí para abajo, leads nuevos)");

    for (let i = 1; i < datos.length; i++) {
      const fila = datos[i];
      if (i + 1 > ultimaFilaVista) ultimaFilaVista = i + 1;
      if (fila.every(function (c) { return String(c).trim() === ""; })) continue;
      if (esFilaDeEncabezado(fila, datos[0])) continue;
      leidas++;

      const lead = normalizarFila(fila, col, nombrePestana, i + 1, datos[0], frontera, nativas[i]);
      // Se cuenta ANTES de cualquier rechazo: lo que el aviso vigila es que el origen
      // esté mandando fechas imposibles, no si ese lead concreto acabó entrando.
      if (lead.fechaImposible) fechasImposibles++;

      if (lead.motivo) {
        if (lead.motivo === MOTIVO_BACKLOG) backlogSinFecha++;
        rechazados.push(lead);
        continue;
      }

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

    // La marca avanza SOLO hasta donde de verdad se miró: si el tope cortó la pasada a
    // mitad de la pestaña, las filas de más abajo siguen contando como nuevas mañana.
    // El ancla se recalcula en la fila nueva: es lo que la próxima pasada comprobará.
    marcasNuevas[idPestana] = {
      sheetId: idPestana,
      nombre: nombrePestana,
      ultimaFila: ultimaFilaVista,
      filas: datos.length,
      cabeceras: huellaCabeceras(datos[0]),
      ancla: anclaDeFilas(datos, ultimaFilaVista),
    };
  });

  if (escribir) {
    // EL ORDEN ES LA DEFENSA, y la regla no tiene excepciones: LA MARCA ES LO ÚLTIMO
    // QUE SE MUEVE. Si cualquiera de las tres escrituras de arriba lanza (timeout de
    // Apps Script sobre las ~12k filas, hoja sin rejilla, permisos), no se llega a la
    // marca y la próxima corrida vuelve a ver esas filas como nuevas: repite trabajo,
    // que es infinitamente mejor que anotar un avance del que no estamos seguros.
    escribirLeads(hojaLeads, aceptados);
    // Las huellas, antes de REVISAR: si la corrida muere a mitad, lo grave es "leads
    // escritos sin huella" — pasó el 2026-07-27 y la corrida siguiente re-listó TODO
    // como "ya presente".
    guardarHuellas(destino, aceptados.concat(duplicados));
    // ⚠️ REVISAR VA ANTES QUE LA MARCA, y hasta el 2026-08-16 iba después con el
    // comentario «REVISAR es cosmético». Era falso: si esta escritura falla con la
    // marca ya movida, la fila que iba a REVISAR queda por DEBAJO de la frontera y
    // en la siguiente pasada se clasifica como historia. Ese lead no está en LEADS,
    // no está en REVISAR y nadie sabe que existió. Lo encontró Codex.
    escribirRechazos(destino, rechazados);
    // Se fusiona sobre lo previo para no perder la marca de una pestaña que esta
    // pasada no llegó a mirar (tope alcanzado, detenida por incidencia, sin teléfono).
    guardarMarcas(destino, fusionar(marcasPrevias, marcasNuevas));
  }
  return {
    leidas: leidas,
    aceptados: aceptados,
    rechazados: rechazados,
    repetidosPasadas: repetidosPasadas,
    backlogSinFecha: backlogSinFecha,
    fechasImposibles: fechasImposibles,
    incidencias: incidencias,
  };
}

/** Copia de `base` con lo de `encima` pisando. (Apps Script no trae Object.assign.) */
function fusionar(base, encima) {
  const r = {};
  Object.keys(base || {}).forEach(function (k) { r[k] = base[k]; });
  Object.keys(encima || {}).forEach(function (k) { r[k] = encima[k]; });
  return r;
}

// ── La marca de agua: sus cuatro comprobaciones ──────────────────────────────

/**
 * ¿Se puede confiar HOY en la marca de esta pestaña? Función pura: es el corazón de
 * la defensa y por eso se prueba sola, sin Hojas de Google de por medio.
 *
 * Devuelve `{ok:false, motivo}` en los cuatro casos en que la marca dejó de
 * significar lo que dice significar. Ante cualquiera de ellos la pestaña se detiene
 * ENTERA: es preferible no traer nada y avisar, a traer con una regla que ya miente.
 */
function revisarPestana(marca, filasAhora, huellaCabAhora, anclaAhora) {
  if (!marca) {
    return { ok: false, motivo: "Pestaña nueva o sin inicializar — ejecuta \"Inicializar marca de agua\"" };
  }
  if (Number(filasAhora) < Number(marca.filas)) {
    return { ok: false, motivo: "El origen PERDIÓ filas (" + marca.filas + " → " + filasAhora + "): los números de fila ya no significan lo mismo" };
  }
  if (String(huellaCabAhora) !== String(marca.cabeceras)) {
    return { ok: false, motivo: "Cambiaron los encabezados del origen: el mapeo de columnas puede haberse movido" };
  }
  if (String(anclaAhora) !== String(marca.ancla)) {
    return { ok: false, motivo: "Las filas ancladas ya no son las mismas: el origen se ordenó o le insertaron filas en medio" };
  }
  return { ok: true, motivo: "" };
}

/**
 * Huella corta y estable de un texto (djb2). A propósito NO usa Utilities.computeDigest:
 * así la misma función corre en Apps Script y en las pruebas de Node sin simular nada.
 * No es criptografía — es detección de cambios, y para eso sobra.
 */
function huellaTexto(s) {
  const t = String(s == null ? "" : s);
  let h = 5381;
  for (let i = 0; i < t.length; i++) h = (((h * 33) ^ t.charCodeAt(i)) >>> 0);
  // La "h" del principio NO es decorativa: sin ella una huella como "00123456" viaja a
  // la celda, Sheets la lee como el número 123456 y al comparar no coincide nunca —
  // una falsa alarma en cada corrida. Con la letra delante, la celda es texto siempre.
  return "h" + ("0000000" + h.toString(16)).slice(-8);
}

/**
 * Huella de los encabezados, sobre el texto NORMALIZADO: cambia exactamente cuando
 * podría cambiar el mapeo de columnas (`ubicarColumnas` compara así), y no salta por
 * un espacio de más o una mayúscula.
 */
function huellaCabeceras(cabeceras) {
  return huellaTexto((cabeceras || []).map(normalizar).join("|"));
}

/**
 * ANCLA: huella del contenido de las últimas filas miradas. Es lo que convierte «la
 * fila 6158 era la última» en algo verificable — si mañana la fila 6158 dice otra
 * cosa, el origen no creció por abajo como suponemos, y hay que mirar antes de seguir.
 */
function anclaDeFilas(datos, hastaFila, cuantas) {
  const n = cuantas || ANCLA_FILAS;
  const trozos = [];
  const fin = Math.min(Number(hastaFila) || 0, (datos || []).length);
  for (let r = Math.max(2, fin - n + 1); r <= fin; r++) {
    const f = datos[r - 1];
    if (!f) continue;
    trozos.push(r + ":" + f.join("\u0001"));
  }
  return huellaTexto(trozos.join("\u0002"));
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

/**
 * Convierte una fila del origen en una fila de nuestra hoja, o la rechaza con motivo.
 *
 * `marca` es la MARCA DE AGUA de la pestaña (última fila que el puente ya había mirado
 * en pasadas anteriores). Es opcional: sin ella el guardia de backlog no actúa, que es
 * el comportamiento de siempre.
 *
 * `nativas` son las fechas que Sheets GUARDA en esta fila, en el orden de `col.fechas`
 * (ver `fechasNativas`). También opcional: sin ellas se lee el texto de la celda.
 */
function normalizarFila(fila, col, pestana, numeroFila, cabeceras, marca, nativas) {
  const val = function (i) { return i >= 0 && i < fila.length ? String(fila[i]).trim() : ""; };

  const lead = {
    pestana: pestana, fila: numeroFila, motivo: "",
    crudo: filaLegible(fila, cabeceras),
  };

  // FECHA DE CORTE — frena solo lo que trae fecha legible Y vieja. Sin fecha legible
  // el lead ENTRA (decisión de Miguel, 2026-07-27): su fecha real es el día en que
  // ingresa; a un posible cliente no se le frena por un dato administrativo que el
  // origen olvidó llenar.
  //
  // ⚠️ "VIEJA" ES "VIEJA SE LEA COMO SE LEA" (`msTarde`). Una fecha ambigua —"09/01"
  // es el 9 de enero o el 1 de septiembre, según quién la haya escrito— no puede
  // condenar a un lead: si sus dos lecturas caen a lados distintos del corte, esta
  // función no sabe la fecha, y decirlo es más honesto que elegir una. El lead pasa a
  // tratarse como SIN FECHA y decide la POSICIÓN, que es la señal que sí controlamos.
  const fecha = fechaMasAntigua(fila, col.fechas, nativas);
  lead.fecha = fecha;
  const corte = corteEnMs();
  lead.fechaAmbigua = !!(fecha && fecha.ambigua);
  // Ambigua Y a caballo del corte: las dos lecturas dicen cosas contrarias, así que
  // esta fecha no puede decidir nada. Ambigua pero con las dos lecturas del mismo
  // lado (dos días de septiembre, pongamos) sí sirve para pasar el corte.
  lead.sinFecha = !fecha || (lead.fechaAmbigua &&
    corte !== null && fecha.ms < corte && fecha.msTarde >= corte);
  if (corte !== null && fecha && fecha.msTarde < corte) {
    if (!(marca > 0 && numeroFila > marca)) {
      lead.motivo = MOTIVO_CORTE + " (" + FECHA_CORTE + ")";
      return lead;
    }
    // Nueva por posición y vieja por fecha: se contradicen, y la que no puede mentir
    // es la posición (ver AVISO_FECHA_IMPOSIBLE). El lead entra con la fecha del
    // ingreso, y la fecha del origen se guarda SOLO para poder decirlo.
    lead.fechaImposible = fecha.texto;
    lead.fecha = null;   // no puede contaminar el desglose por mes ni la huella
    lead.sinFecha = true;
    lead.fechaAmbigua = false;
  }
  // Y la otra mitad: sin fecha que juzgar, manda la POSICIÓN. Una fila sin fecha que
  // ya estaba cuando el puente miró la vez pasada es backlog, no un lead nuevo.
  if (lead.sinFecha && marca > 0 && numeroFila <= marca) {
    lead.motivo = MOTIVO_BACKLOG;
    return lead;
  }

  // Nombre y teléfono se resuelven ANTES de cualquier rechazo: así toda fila que
  // caiga en REVISAR sale con esas dos columnas llenas cuando el dato sí existe.
  lead.nombre = [val(col.nombre), val(col.apellido)]
    .filter(String).join(" ").replace(/\s+/g, " ").trim();

  // Conserva HASTA DOS celulares distintos. El principal mantiene la prioridad
  // histórica (Celular → WhatsApp/celular 2 → rescate) porque es la identidad que
  // usa el dedup. El segundo viaja como contacto alternativo; si WhatsApp repite el
  // mismo número —el caso normal del origen— queda vacío y no ensucia el CRM.
  const telefonos = telefonosDeFila(fila, col);
  lead.telefono = telefonos[0] || "";
  lead.telefonoAlternativo = telefonos[1] || "";
  lead.telefonoRescatado = !!lead.telefono && telefonos.rescatadoPrincipal;
  // Que la ficha lo diga: un vendedor que ve el botón de WhatsApp sobre un fijo
  // escribe a nadie y da el lead por frío.
  lead.telefonoEsFijo = !!lead.telefono && telefonos.principalEsFijo;
  // Excluyente con el alternativo bueno, igual que en la base: un lead no
  // puede mostrar dos «segundos números» distintos.
  lead.telefonoAlternativoCrudo = lead.telefonoAlternativo ? "" : telefonos.crudoIlegible;

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
    lead.telefonoEsFijo ? "☎️ El teléfono principal es un FIJO — no responde WhatsApp, hay que llamar" : "",
    lead.fechaImposible
      ? "⚠️ El origen lo fechó el " + lead.fechaImposible + ", imposible en una fila " +
        "recién llegada — vale la del ingreso"
      : lead.fechaAmbigua
        ? "⚠️ Fecha ambigua en el origen (" + lead.fecha.texto + ")" +
          (lead.sinFecha ? " — vale la del ingreso" : "")
        : (lead.sinFecha ? "Sin fecha en el origen (vale la del ingreso)" : ""),
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

/**
 * LA REGLA DEL TELÉFONO en el puente. Gemela EXACTA de `telefonos.ts` del
 * conector y de `validacion.ts` del front. Si una de las tres se mueve sin las
 * otras, un número entra por un lado y se pierde por el otro sin que nadie lo
 * vea — que es exactamente cómo se perdían los segundos números.
 *
 * Decisiones de Miguel (2026-08-26): el CRM reconoce fijos peruanos y números
 * de cualquier país, y basta UN número bueno para que el lead exista.
 *
 * Devuelve { e164, clase, movil } o null.
 *   clase: "celular_pe" | "fijo_pe" | "internacional"
 *   movil: si responde WhatsApp. Un fijo, no.
 */
function reconocerTelefono(v) {
  const bruto = String(v == null ? "" : v).trim();
  if (!bruto) return null;
  // Un correo en la columna de teléfono es otro dato en el sitio equivocado,
  // no un número roto. (Las letras SÍ pasan: "p:+51910585900" es una fila real.)
  if (bruto.indexOf("@") >= 0) return null;

  const digitos = bruto.replace(/\D/g, "");
  if (!digitos) return null;

  const marcadoInternacional = bruto.charAt(0) === "+" || digitos.indexOf("00") === 0;
  const sinSalida = digitos.replace(/^00/, "");

  // Todo lo que dice ser peruano se juzga con la vara peruana: si no tiene la
  // forma exacta NO se cuela por la puerta internacional. Sin esto,
  // "+51123456789" entraría como número válido y nadie podría llamarlo.
  const nacional = sinSalida.indexOf("51") === 0 ? sinSalida.slice(2) : sinSalida;
  const declaraPeru = sinSalida.indexOf("51") === 0 && nacional.length >= 8;

  if (declaraPeru || !marcadoInternacional) {
    const n = declaraPeru ? nacional : sinSalida;
    if (/^9\d{8}$/.test(n)) return { e164: "+51" + n, clase: "celular_pe", movil: true };
    // ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho dígitos
    // (Lima 1 + siete, provincias 84 + seis)… y el DNI peruano TAMBIÉN tiene
    // ocho. Aceptar ocho dígitos pelados convertiría todo DNI del origen en un
    // teléfono. Un fijo solo se reconoce MARCADO: con "+51"/"0051", o con el 0
    // de larga distancia con el que la gente escribe su fijo (014457890).
    const marcaDeFijo = declaraPeru || n.charAt(0) === "0";
    const sinCero = n.charAt(0) === "0" ? n.slice(1) : n;
    if (marcaDeFijo && /^[1-8]\d{7}$/.test(sinCero)) {
      return { e164: "+51" + sinCero, clase: "fijo_pe", movil: false };
    }
    if (declaraPeru) return null;
    if (!marcadoInternacional) return null; // sin "+" no hay país que suponer
  }

  // E.164: de 8 a 15 dígitos, el primero 1–9. Sin lista de códigos de país:
  // mantenerla al día en tres capas es peor deuda que aceptar un número raro.
  if (sinSalida.length >= 8 && sinSalida.length <= 15 && /^[1-9]\d*$/.test(sinSalida)) {
    // Móvil o fijo es indecidible fuera de Perú sin libphonenumber. Se asume
    // móvil: esconder el único canal que hay sería peor.
    return { e164: "+" + sinSalida, clase: "internacional", movil: true };
  }
  return null;
}

/**
 * El número que puede ser IDENTIDAD del lead: un móvil (celular peruano o
 * internacional). "" si no lo hay. Es lo que responde WhatsApp, que es como
 * se trabaja aquí.
 */
function telefonoPeru(v) {
  const r = reconocerTelefono(v);
  return r && r.movil ? r.e164 : "";
}

/** Cualquier número CONTACTABLE: móvil o fijo. "" si no lo hay. */
function telefonoContacto(v) {
  const r = reconocerTelefono(v);
  return r ? r.e164 : "";
}

/**
 * Hasta dos celulares DISTINTOS de una fila, en orden de confianza:
 * Celular, WhatsApp/celular 2 y por último cualquier otra celda rescatable.
 * La propiedad `rescatadoPrincipal` conserva el aviso histórico cuando el único
 * teléfono usable apareció fuera de las columnas esperadas.
 */
function telefonosDeFila(fila, col) {
  const indices = [];
  if (col.telefono >= 0) indices.push(col.telefono);
  if (col.whatsapp >= 0 && col.whatsapp !== col.telefono) indices.push(col.whatsapp);
  for (let i = 0; i < fila.length; i++) {
    if (i === col.telefono || i === col.whatsapp || i === col.monto || i === col.dni) continue;
    indices.push(i);
  }

  // Se recogen TODOS los contactables, no solo los móviles. Hasta hoy un fijo o
  // un número extranjero se tiraba aquí mismo, en el origen, y el lead llegaba
  // al CRM con un solo número o no llegaba.
  const hallados = [];
  indices.forEach(function (i) {
    const r = reconocerTelefono(fila[i]);
    if (!r) return;
    let repetido = false;
    hallados.forEach(function (h) { if (h.e164 === r.e164) repetido = true; });
    if (!repetido && hallados.length < 2) hallados.push(r);
  });

  // El MÓVIL manda como principal: es la identidad y es quien responde WhatsApp.
  // Un fijo solo sube a principal cuando no hay ningún móvil en la fila — antes
  // de eso la alternativa era descartar al lead entero, y un lead al que se
  // puede llamar vale más que un botón de WhatsApp que funcione.
  const encontrados = [];
  let iPrincipal = -1;
  for (let k = 0; k < hallados.length; k++) {
    if (hallados[k].movil) { iPrincipal = k; break; }
  }
  if (hallados.length > 0) {
    if (iPrincipal < 0) iPrincipal = 0;
    encontrados.push(hallados[iPrincipal].e164);
    for (let k = 0; k < hallados.length; k++) {
      if (k !== iPrincipal) { encontrados.push(hallados[k].e164); break; }
    }
  }

  // El aviso histórico: el único número usable apareció FUERA de las columnas
  // esperadas, así que conviene confirmarlo al contactar.
  encontrados.rescatadoPrincipal = encontrados.length > 0 &&
    telefonoContacto(fila[col.telefono]) === "" &&
    telefonoContacto(fila[col.whatsapp]) === "";
  encontrados.principalEsFijo = hallados.length > 0 && !hallados[iPrincipal < 0 ? 0 : iPrincipal].movil;

  // LO QUE NO SE PUDO LEER TAMPOCO SE TIRA (decisión de Miguel, 2026-08-26).
  // Son 299 filas de 14.310 del origen (2,1 %) las que traen algo escrito que no
  // es un teléfono: un número a medias, con un dígito de más, con una anotación
  // pegada. Viajan crudas para que un humano las mire en el CRM.
  //
  // ⚠️ SOLO de las columnas DECLARADAS de teléfono. El rescate de arriba barre
  // TODAS las celdas de la fila, y hacer lo mismo aquí traería el distrito, el
  // nombre o la respuesta a una pregunta abierta disfrazados de «segundo número
  // sin validar». Un dato equivocado presentado como teléfono es peor que
  // ninguno.
  encontrados.crudoIlegible = "";
  if (encontrados.length < 2) {
    [col.telefono, col.whatsapp].forEach(function (i) {
      if (encontrados.crudoIlegible || i < 0) return;
      const bruto = String(fila[i] == null ? "" : fila[i]).trim();
      // Un correo mal puesto no es un número perdido: es otro dato en el sitio
      // equivocado, y mostrarlo como teléfono confundiría al vendedor.
      if (!bruto || bruto.indexOf("@") >= 0) return;
      if (reconocerTelefono(bruto)) return;
      encontrados.crudoIlegible = bruto.slice(0, 40);
    });
  }
  return encontrados;
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

/**
 * Un valor que empieza por "=" lo escribe Sheets como FÓRMULA, no como texto — y eso
 * NO lo evita el formato de texto de la celda: es la semántica de `setValues`. Un lead
 * llamado "=1+1" acabaría en la hoja como "2", y el conector subiría "2" al CRM como
 * nombre del cliente. El origen es de otra empresa, así que esto es una vía de entrada
 * real, no una hipótesis. Lo encontró Codex el 2026-08-16.
 *
 * ⚠️ A PROPÓSITO NO TOCA EL "+": todos los teléfonos empiezan por "+51", y en julio
 * entraron 158 leads con ese formato sin un solo problema. Blindar contra una hipótesis
 * rompiendo lo que se sabe que funciona es un mal negocio.
 */
function sinFormula(v) {
  return String(v == null ? "" : v).replace(/^=+/, "");
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
 *
 * `nativas` (opcional) trae, EN EL MISMO ORDEN que `indices`, lo que Sheets guarda de
 * verdad en esa celda, ya pasado a "AAAA-MM-DD" (lo prepara `fechasNativas`). Cuando
 * está, MANDA: es el único dato que no depende de cómo el origen decida DIBUJAR la
 * fecha. El texto de la celda es el respaldo, para las columnas que el formulario
 * escribe como texto plano.
 *
 * Devuelve { ms, msTarde, texto, mes, ambigua } | null. En una fecha cierta
 * `ms === msTarde`; en una ambigua son las dos lecturas posibles (ver `fechaDeCelda`).
 */
function fechaMasAntigua(fila, indices, nativas) {
  let mejor = null;
  (indices || []).forEach(function (i, j) {
    const cand = fechaDeCelda(String(fila[i] || "").trim(), (nativas || [])[j]);
    if (!cand) return;
    if (mejor === null || cand.ms < mejor.ms) mejor = cand;
  });
  return mejor;
}

/**
 * Una celda de fecha → { ms, msTarde, texto, mes, ambigua } | null. Pura.
 *
 * ⚠️ "09/01/2026" NO DICE QUÉ DÍA ES. El 2026-09-01, a media mañana, el origen dejó de
 * escribir DD/MM/AAAA y empezó a escribir MM/DD/AAAA, sin avisar. Esta función leía
 * siempre el primer número como el día, así que ese "09/01/2026" pasó a significar el
 * 9 de ENERO: anterior al corte, descartado en silencio. 34 leads reales se quedaron
 * fuera del CRM durante un día entero mientras el puente corría en verde.
 *
 * La lección no es "ahora léelo al revés" —mañana puede volver a cambiar—, es que el
 * texto de una fecha que escribe OTRO no es una fuente de verdad:
 *
 *   1. Si Sheets guardó una fecha DE VERDAD en la celda, esa manda (`nativas`): el
 *      formato de pantalla ya no pinta nada.
 *   2. Si no, se prueban LAS DOS LECTURAS del texto. Si solo una existe en el
 *      calendario ("31/08" o "09/15"), no hay duda: esa es.
 *   3. Si las dos existen y son días distintos, la fecha es AMBIGUA y se dice: se
 *      devuelven las dos (`ms` la más antigua, `msTarde` la más reciente) para que
 *      quien decide —el corte— pueda ser honesto sobre lo que sabe y lo que no.
 */
function fechaDeCelda(texto, nativa) {
  // 1) Lo que Sheets GUARDA, no lo que dibuja.
  const dn = piezasDeIso(String(nativa || ""));
  if (dn) return fechaCierta(dn);

  const t = String(texto || "");
  // 2) El texto ya en ISO (así llega la pestaña de Facebook).
  const di = piezasDeIso(t);
  if (di) return fechaCierta(di);

  // 3) "d1/d2/AAAA": las dos lecturas, y que el calendario descarte lo que pueda.
  const lat = t.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/);
  if (!lat) return null;
  const anio = +lat[3];
  const comoLatina = diaDelCalendario(anio, +lat[2], +lat[1]);  // DD/MM/AAAA
  const comoInglesa = diaDelCalendario(anio, +lat[1], +lat[2]); // MM/DD/AAAA
  if (!comoLatina && !comoInglesa) return null;
  if (!comoInglesa) return fechaCierta(comoLatina);
  if (!comoLatina) return fechaCierta(comoInglesa);
  if (comoLatina.ms === comoInglesa.ms) return fechaCierta(comoLatina); // 05/05/2026
  return {
    ms: Math.min(comoLatina.ms, comoInglesa.ms),
    msTarde: Math.max(comoLatina.ms, comoInglesa.ms),
    texto: pad(+lat[1]) + "/" + pad(+lat[2]) + "/" + anio + " (ambigua)",
    mes: "fecha ambigua", // en el desglose del reporte se ven de un vistazo
    ambigua: true,
  };
}

/** Una fecha sin dudas, en la forma que espera el resto del puente. */
function fechaCierta(d) {
  return {
    ms: d.ms,
    msTarde: d.ms,
    texto: pad(d.dd) + "/" + pad(d.m) + "/" + d.a,
    mes: d.a + "-" + pad(d.m), // para el desglose del reporte
    ambigua: false,
  };
}

/** "AAAA-MM-DD…" → sus piezas, o null. Pura. */
function piezasDeIso(t) {
  const m = String(t).match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? diaDelCalendario(+m[1], +m[2], +m[3]) : null;
}

/**
 * { a, m, dd, ms } si esa fecha EXISTE en el calendario; null si no.
 *
 * `Date.UTC` no valida: "99/99/2026" lo normaliza a una fecha FUTURA, con lo que
 * superaba el corte y, al tener fecha, tampoco lo frenaba la marca de agua por
 * posición — una fecha basura era un salvoconducto. Se comprueba con la vuelta: si el
 * día o el mes cambiaron al construirla, no era una fecha (cubre el 31 de febrero).
 * Y es además lo que desempata las dos lecturas de "31/08/2026": no hay mes 31.
 */
function diaDelCalendario(a, m, dd) {
  if (!(a > 0) || !(m >= 1 && m <= 12) || !(dd >= 1)) return null;
  const ms = Date.UTC(a, m - 1, dd);
  const vuelta = new Date(ms);
  if (vuelta.getUTCMonth() !== m - 1 || vuelta.getUTCDate() !== dd) return null;
  return { a: a, m: m, dd: dd, ms: ms };
}

/**
 * Las columnas de fecha del origen TAL Y COMO SHEETS LAS GUARDA, no como las dibuja.
 *
 * `getDisplayValues()` devuelve el texto ya pintado con el formato y el locale del
 * DOCUMENTO DE ORIGEN, que no controlamos: el día que a alguien le da por cambiarlo,
 * el mismo dato de siempre llega escrito al revés (pasó el 2026-09-01). `getValues()`
 * sobre esas mismas celdas devuelve la fecha REAL cuando la celda es una fecha de
 * verdad, y ahí no hay formato que valga.
 *
 * Se lee SOLO las columnas de fecha (una o dos), no la pestaña entera, y solo cuando
 * ya se decidió que la pestaña se procesa: es una columna más sobre las once que la
 * pasada ya se descarga, no una segunda pasada.
 *
 * Devuelve una matriz [fila][posición dentro de `indices`] con "AAAA-MM-DD", o "" si
 * esa celda no era una fecha (el formulario la escribió como texto). Se formatea en la
 * zona del ORIGEN, que es la que decide qué día muestra esa celda.
 */
function fechasNativas(pestana, indices, filas, zona) {
  if (!indices || !indices.length || !(filas > 1)) return [];
  const columnas = indices.map(function (i) {
    return pestana.getRange(1, i + 1, filas, 1).getValues();
  });
  const salida = [];
  for (let r = 0; r < filas; r++) {
    salida.push(columnas.map(function (columna) {
      const v = columna[r][0];
      return Object.prototype.toString.call(v) === "[object Date]"
        ? Utilities.formatDate(v, zona, "yyyy-MM-dd")
        : "";
    }));
  }
  return salida;
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
  const primera = hoja.getLastRow() + 1;
  // La hoja crece ANTES de escribir, con formato incluido. Escribir más allá de la
  // rejilla lanza "out of bounds" y mata la pasada DESPUÉS de haber leído las 12.000
  // filas del origen (y antes de guardar la marca). `asegurarCapacidadLeads` vive en
  // el conector, que es quien define la forma de esta hoja: los dos archivos son un
  // solo proyecto de Apps Script y comparten ámbito global.
  asegurarCapacidadLeads(hoja, primera + leads.length - 1);
  const filas = leads.map(function (l) {
    return [
      sinFormula(l.nombre),   // A Nombre completo *
      l.telefono,             // B Teléfono *
      l.capital,              // C Capital estimado *
      l.moneda,               // D Moneda *
      l.canal,                // E Canal de origen *
      sinFormula(l.correo),   // F Correo
      l.dni,                  // G DNI
      "",                     // H Género          — el origen no lo trae
      "",                     // I Fecha nacimiento— el origen no lo trae
      sinFormula(l.distrito), // J Distrito
      l.interes,              // K Interés
      sinFormula(l.nota),     // L Nota
      "",                     // M Vendedor asignado — se reparte DENTRO del CRM
      l.autorizo,             // N ¿Autorizó contacto?
      l.fuenteConsentimiento, // O Fuente del consentimiento
      "",                     // P Estado: vacío = el conector la toma en el próximo ciclo
      // Q Teléfono alternativo. Si no hubo uno legible viaja el texto CRUDO: el
      // conector ya distingue por sí mismo si puede leerlo, así que no hace falta
      // una columna nueva en la hoja —y añadirla obligaría a re-preparar la hoja
      // viva, que es una operación con mucho más riesgo que este cambio.
      l.telefonoAlternativo || l.telefonoAlternativoCrudo,
    ];
  });
  hoja.getRange(primera, 1, filas.length, 17).setValues(filas);
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
    return !esDescartePorDiseno(r.motivo);
  });
  // Lo accionable arriba (préstamo, sin teléfono, sin nombre); los duplicados al
  // final — solo aparecen la pasada en que se descubren (quedan huellados).
  rechazados = rechazados.slice().sort(function (a, b) {
    return ordenRevision(a.motivo) - ordenRevision(b.motivo);
  });
  let hoja = libro.getSheetByName(HOJA_REVISAR);
  if (!hoja) hoja = libro.insertSheet(HOJA_REVISAR, libro.getNumSheets()); // al final: ver hojaDeMarcas

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
    return [r.motivo, r.pestana, r.fila, sinFormula(r.nombre || ""),
      sinFormula(r.telefono || ""), sinFormula(r.crudo)];
  });
  asegurarFilas(hoja, 1 + filas.length); // REVISAR también puede desbordar la rejilla
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
    hoja = libro.insertSheet(HOJA_HUELLAS, libro.getNumSheets()); // al final: ver hojaDeMarcas
    hoja.appendRow(["Huella (no tocar)", "Teléfono", "Origen", "Registrado el", "Traído el"]);
    hoja.hideSheet();
  }
  // Aquí la trampa está LATENTE, no viva: hoy `leerHuellas` solo mira la columna A,
  // así que las dos columnas de fecha no muerden a nadie. Se blinda igual, porque el
  // día que alguien lea "Traído el" para un informe, la trampa ya estaría puesta.
  forzarTexto(hoja, 5);
  protegerHuellas(hoja);
  if (!leads.length) return;
  const traidoEl = Utilities.formatDate(new Date(), ZONA_DE_CORRIDA, "dd/MM/yyyy HH:mm");
  const primera = hoja.getLastRow() + 1;
  asegurarFilas(hoja, primera + leads.length - 1); // la memoria también se queda sin rejilla
  hoja.getRange(primera, 1, leads.length, 5)
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
  protegerMemoria(hoja, "Memoria del puente — solo el dueño");
}

function protegerMemoria(hoja, descripcion) {
  if (hoja.getProtections(SpreadsheetApp.ProtectionType.SHEET).length) return;
  const p = hoja.protect().setDescription(descripcion);
  const yo = Session.getEffectiveUser();
  p.addEditor(yo);
  p.removeEditors(p.getEditors().filter(function (u) {
    return u.getEmail() !== yo.getEmail();
  }));
  if (p.canDomainEdit()) p.setDomainEdit(false);
}

/** Crece la hoja lo justo para que quepan `filasNecesarias` sin salirse de la rejilla. */
function asegurarFilas(hoja, filasNecesarias) {
  const faltan = Number(filasNecesarias) - hoja.getMaxRows();
  if (faltan > 0) hoja.insertRowsAfter(hoja.getMaxRows(), faltan);
}

// ── La marca de agua: memoria en disco ───────────────────────────────────────

const CABECERA_MARCAS = [
  "sheetId (no tocar)", "Pestaña", "Última fila vista", "Filas al cerrar",
  "Huella de encabezados", "Ancla de contenido", "Actualizado",
];

/**
 * Lee las marcas. NO crea la pestaña: si no existe, devuelve vacío y el puente se
 * detiene solo (ver § MOTIVO_BACKLOG). Leer nunca debe tener efectos.
 */
function leerMarcas(libro) {
  const hoja = libro.getSheetByName(HOJA_MARCAS);
  const mapa = {};
  if (!hoja || hoja.getLastRow() < 2) return mapa;
  hoja.getRange(2, 1, hoja.getLastRow() - 1, CABECERA_MARCAS.length)
    .getValues()
    .forEach(function (f) {
      const id = String(f[0]).trim();
      if (!id) return;
      mapa[id] = {
        sheetId: id,
        nombre: String(f[1]),
        ultimaFila: Number(f[2]) || 0,
        filas: Number(f[3]) || 0,
        cabeceras: String(f[4]),
        ancla: String(f[5]),
        actualizado: momentoDeCelda(f[6]),
      };
    });
  return mapa;
}

/**
 * Una celda que Sheets convirtió en fecha, de vuelta al texto de LIMA.
 *
 * ⚠️ NO usar `String(fecha)`: eso re-renderiza en la zona horaria del PROYECTO de
 * Apps Script y reintroduce exactamente la dependencia que `relojDeLima` vino a
 * matar — con el proyecto en hora del Pacífico, una frontera puesta a las 00:30 de
 * Lima se mostraría con la fecha del DÍA ANTERIOR. Además devuelve un texto en
 * inglés ("Sun Aug 16 2026 16:48:00 GMT-0500") dentro de un panel en español.
 *
 * Visto en producción el 2026-08-16, la primera vez que se leyó el panel de verdad:
 * escribimos el texto "16/08/2026 16:48", Sheets lo reconoció como fecha y lo guardó
 * como fecha. `forzarTexto()` impide que vuelva a pasar; esto cura lo ya guardado.
 */
function momentoDeCelda(v) {
  if (Object.prototype.toString.call(v) === "[object Date]") {
    return Utilities.formatDate(v, ZONA_DE_CORRIDA, "dd/MM/yyyy HH:mm");
  }
  return String(v == null ? "" : v);
}

/**
 * Toda la rejilla de una pestaña de memoria, en formato TEXTO.
 *
 * Es el mismo blindaje que `prepararTramo()` le da a LEADS, y por el mismo motivo:
 * lo que escribimos aquí son huellas, identificadores y sellos de hora, y Sheets
 * interpreta lo que le escriben — una fecha vuelve como fecha, y un "00123456"
 * volvería como el número 123456.
 *
 * Cubre `getMaxRows()`, no solo las filas escritas: `insertRowsAfter` (ver
 * `asegurarFilas`) hereda el formato de la fila de arriba, así que sin esto las filas
 * nuevas nacerían otra vez con formato de fecha. Y va FUERA del `if` que crea la
 * pestaña, para que también desintoxique la que ya existe en la hoja de producción.
 */
function forzarTexto(hoja, columnas) {
  hoja.getRange(1, 1, hoja.getMaxRows(), columnas).setNumberFormat("@");
}

/**
 * Guarda las marcas. Se reescribe entera: es UNA fila por pestaña, la foto de dónde
 * quedó el puente, no un histórico. Pestaña oculta y protegida como las huellas.
 */
function guardarMarcas(libro, marcas) {
  const hoja = hojaDeMarcas(libro);
  const claves = Object.keys(marcas || {});
  // Sin marcas que escribir NO se toca nada. Vaciar la pestaña aquí sería borrar la
  // memoria del puente para no escribir nada a cambio.
  if (!claves.length) return;

  // UNA SOLA ESCRITURA. Antes se borraba primero y se escribía después: si la segunda
  // fallaba habiendo funcionado la primera, la memoria quedaba VACÍA — el puente se
  // planta (bien) pero al re-inicializar la frontera se pone al final de hoy, y todo
  // lo llegado entretanto se convierte en historia. Ahí sí se pierden leads. Con un
  // único setValues que cubre lo nuevo Y lo que sobra, o se hace entero o no se hace.
  const filasPrevias = Math.max(hoja.getLastRow() - 1, 0);
  const alto = Math.max(claves.length, filasPrevias);
  asegurarFilas(hoja, 1 + alto);
  const cuando = Utilities.formatDate(new Date(), ZONA_DE_CORRIDA, "dd/MM/yyyy HH:mm");
  const bloque = claves.map(function (k) {
    const m = marcas[k];
    // `cuando` SOLO para las marcas que esta pasada tocó de verdad. Las que vienen
    // de fusionar() —pestañas detenidas, o que el tope no llegó a mirar— conservan
    // su sello anterior: poner la hora de hoy en una frontera que no se movió es
    // una mentira pequeña, pero en la única columna que sirve para diagnosticar
    // "esta pestaña lleva días sin mirarse".
    return [m.sheetId, m.nombre, m.ultimaFila, m.filas, m.cabeceras, m.ancla,
      m.actualizado || cuando];
  });
  // Las filas sobrantes de una pasada anterior se limpian en la MISMA escritura.
  while (bloque.length < alto) {
    bloque.push(CABECERA_MARCAS.map(function () { return ""; }));
  }
  hoja.getRange(2, 1, alto, CABECERA_MARCAS.length).setValues(bloque);
}

function hojaDeMarcas(libro) {
  let hoja = libro.getSheetByName(HOJA_MARCAS);
  if (!hoja) {
    // AL FINAL, SIEMPRE. `insertSheet(nombre)` a secas la mete junto a la pestaña
    // activa, que puede ser la primera — y el conector importa de getSheets()[0]:
    // una pestaña de memoria colocada delante lo pondría a leer huellas como si
    // fueran leads. Fijar el índice cuesta un argumento y cierra el caso.
    hoja = libro.insertSheet(HOJA_MARCAS, libro.getNumSheets());
    hoja.getRange(1, 1, 1, CABECERA_MARCAS.length)
      .setValues([CABECERA_MARCAS]).setFontWeight("bold");
    hoja.setFrozenRows(1);
    hoja.hideSheet();
  }
  forzarTexto(hoja, CABECERA_MARCAS.length);
  protegerMemoria(hoja, "Marca de agua del puente — solo el dueño");
  return hoja;
}

/**
 * PONER LA FRONTERA. Se ejecuta A MANO, una vez, ANTES de encender el horario.
 *
 * No importa NI UN LEAD: solo anota dónde termina hoy cada pestaña del origen. A
 * partir de ahí, lo que aparezca por debajo es un lead nuevo y entra; lo que ya
 * estaba, sin fecha que lo defienda, es historia y se queda fuera.
 *
 * NO mueve una marca que ya existe. Es deliberado: si volviera a correrla alguien por
 * costumbre, empujaría la frontera hacia abajo y los leads llegados entretanto
 * desaparecerían sin dejar rastro. Para rehacer la marca de una pestaña hay que borrar
 * su fila de `_puente_marcas` a conciencia. Sí añade las pestañas que aún no tienen.
 */
function inicializarMarcas() {
  return conCandado(function () {
    const destino = SpreadsheetApp.getActiveSpreadsheet();
    if (!destino) {
      throw new Error(
        "No hay hoja activa. Este script tiene que vivir DENTRO de la hoja " +
        "\"Leads AVANCE CORP — captura para CRM\" (Extensiones → Apps Script)."
      );
    }
    const previas = leerMarcas(destino);
    const marcas = fusionar(previas, {});
    const origen = SpreadsheetApp.openById(ORIGEN_ID); // solo lectura
    const puestas = [];
    const respetadas = [];

    origen.getSheets().forEach(function (pestana) {
      const id = String(pestana.getSheetId());
      const nombre = pestana.getName();
      const datos = pestana.getDataRange().getDisplayValues();
      if (previas[id]) {
        respetadas.push("   · " + nombre + ": se respeta la frontera en la fila " +
          previas[id].ultimaFila + " (puesta el " + previas[id].actualizado + ")");
        return;
      }
      marcas[id] = {
        sheetId: id,
        nombre: nombre,
        ultimaFila: datos.length,
        filas: datos.length,
        cabeceras: huellaCabeceras(datos[0] || []),
        ancla: anclaDeFilas(datos, datos.length),
      };
      puestas.push("   · " + nombre + " (id " + id + "): " + datos.length +
        " filas → frontera en la " + datos.length + "; nuevo = de la " +
        (datos.length + 1) + " hacia abajo");
    });

    guardarMarcas(destino, marcas);

    const texto =
      "Marca de agua puesta — NO se importó ningún lead\n\n" +
      (puestas.length ? "Fronteras nuevas:\n" + puestas.join("\n") + "\n" : "") +
      (respetadas.length ? "\nYa tenían frontera (no se tocan):\n" + respetadas.join("\n") + "\n" : "") +
      "\nDesde ahora el puente ya puede correr: traerá lo que aparezca por debajo de " +
      "esas filas, y lo fechado desde el " + FECHA_CORTE + ".\n\n" +
      "Comprueba con \"Vista previa\" que no entra nada antes de encender el horario.";
    informar(texto);
    return { puestas: puestas.length, respetadas: respetadas.length };
  });
}

/**
 * RETROCEDER LA MARCA DE AGUA — el rescate de las filas que el puente YA MIRÓ y
 * descartó por error.
 *
 * POR QUÉ EXISTE. La marca avanza en cada pasada aunque no acepte ni un lead: es
 * "hasta aquí he mirado", no "hasta aquí he traído". Así que cuando el puente descarta
 * mal —el 2026-09-01 el origen cambió el formato de fecha y 34 leads reales cayeron
 * como "Anterior al corte"—, arreglar el descarte NO los rescata: para entonces la
 * frontera ya pasó por encima y esas filas cuentan como historia. Hay que desandarla.
 *
 * NO IMPORTA NADA. Solo mueve la frontera hacia atrás; después hay que pasar la Vista
 * previa y decidir. Y solo hacia ATRÁS: adelantarla a mano es la forma de hacer
 * desaparecer leads sin dejar rastro, y para eso no hay atajo (se adelanta sola).
 *
 * Pregunta pestaña y fila, enseña las dos filas de la frontera (la última que se da
 * por buena y la primera que se volverá a mirar) y cuántas de las que se recuperan NO
 * traen fecha —que son las que entrarían por posición— antes de tocar nada.
 */
function retrocederMarca() {
  let ui;
  try {
    ui = SpreadsheetApp.getUi();
  } catch (e) {
    throw new Error(
      "Esto se ejecuta desde el menú AVANCE CORP con la hoja abierta, no desde el " +
      "editor: necesita preguntarte la pestaña y la fila, y que confirmes."
    );
  }
  const destino = SpreadsheetApp.getActiveSpreadsheet();
  const marcas = leerMarcas(destino);
  if (!Object.keys(marcas).length) {
    throw new Error("El puente todavía no tiene marca de agua: no hay nada que retroceder.");
  }

  const origen = SpreadsheetApp.openById(ORIGEN_ID); // solo lectura
  const nombres = origen.getSheets().map(function (h) { return h.getName(); });
  const p1 = ui.prompt(
    "Rescatar filas ya miradas (1 de 2)",
    "¿De qué pestaña del origen?\n\nPestañas: " + nombres.join(", "),
    ui.ButtonSet.OK_CANCEL
  );
  if (p1.getSelectedButton() !== ui.Button.OK) return null;
  const nombre = String(p1.getResponseText()).trim();
  const pestana = origen.getSheets().filter(function (h) { return h.getName() === nombre; })[0];
  if (!pestana) throw new Error("No hay ninguna pestaña \"" + nombre + "\" en el origen. Hay: " + nombres.join(", "));
  const marca = marcas[String(pestana.getSheetId())];
  if (!marca) throw new Error("La pestaña \"" + nombre + "\" no tiene marca de agua todavía.");

  const p2 = ui.prompt(
    "Rescatar filas ya miradas (2 de 2)",
    "La marca de \"" + nombre + "\" está hoy en la fila " + marca.ultimaFila + ".\n\n" +
    "¿Cuál es la ÚLTIMA fila que doy por buena? De la siguiente hacia abajo, el " +
    "puente volverá a mirar.",
    ui.ButtonSet.OK_CANCEL
  );
  if (p2.getSelectedButton() !== ui.Button.OK) return null;

  const datos = pestana.getDataRange().getDisplayValues();
  const nueva = marcaRetrocedida(marca, datos, p2.getResponseText(), nombre);
  const recuperadas = datos.length - nueva.ultimaFila;

  // Cuántas de las que vuelven NO traen fecha: esas entran por POSICIÓN, sin que el
  // corte pueda decir nada. Es el número que hay que mirar antes de aceptar.
  const col = ubicarColumnas(datos[0]);
  let sinFecha = 0;
  for (let r = nueva.ultimaFila + 1; r <= datos.length; r++) {
    if (!fechaMasAntigua(datos[r - 1], col.fechas)) sinFecha++;
  }

  const confirmar = ui.alert(
    "Confirma el retroceso",
    "Pestaña \"" + nombre + "\": la marca pasa de la fila " + marca.ultimaFila +
    " a la " + nueva.ultimaFila + ".\n" +
    "Se volverán a mirar " + recuperadas + " filas, de las que " + sinFecha +
    " no traen fecha (esas entrarían por posición).\n\n" +
    "ÚLTIMA fila que se da por buena (" + nueva.ultimaFila + "):\n" +
    filaLegible(datos[nueva.ultimaFila - 1] || [], datos[0]) + "\n\n" +
    "PRIMERA que se volverá a mirar (" + (nueva.ultimaFila + 1) + "):\n" +
    filaLegible(datos[nueva.ultimaFila] || [], datos[0]) + "\n\n" +
    "No se importa nada ahora: después hay que pasar la Vista previa.",
    ui.ButtonSet.OK_CANCEL
  );
  if (confirmar !== ui.Button.OK) return null;

  return conCandado(function () {
    // Se RELEEN las marcas dentro del candado: entre la pregunta y el OK ha podido
    // correr una pasada y mover otras fronteras. Solo se pisa la de esta pestaña.
    guardarMarcas(destino, fusionar(leerMarcas(destino), unaMarca(nueva)));
    informar(
      "Marca de agua retrocedida — NO se importó ningún lead\n\n" +
      "Pestaña \"" + nombre + "\": fila " + marca.ultimaFila + " → " + nueva.ultimaFila + "\n" +
      "Vuelven a mirarse " + recuperadas + " filas (" + sinFecha + " sin fecha).\n\n" +
      "Ahora: \"Vista previa\" para ver qué entraría, y solo entonces \"Traer leads " +
      "del origen\"."
    );
    return { pestana: nombre, de: marca.ultimaFila, a: nueva.ultimaFila, recuperadas: recuperadas };
  });
}

/** Un mapa de marcas con una sola dentro, para `fusionar`. */
function unaMarca(marca) {
  const uno = {};
  uno[marca.sheetId] = marca;
  return uno;
}

/**
 * La marca que quedaría al retroceder `marca` hasta la fila `hasta`. Pura: valida y
 * devuelve, o LANZA con el motivo. Todo lo que puede salir mal se decide aquí.
 *
 * El ancla y la huella de cabeceras se recalculan EN LA FILA NUEVA: sin eso, la
 * siguiente pasada compararía el ancla vieja (calculada al final de la pestaña) contra
 * la nueva y detendría la pestaña por "se reordenó", que es justo lo contrario de
 * rescatar. Por eso esto no se puede hacer editando `_puente_marcas` a mano.
 */
function marcaRetrocedida(marca, datos, hasta, nombre) {
  if (!marca) throw new Error("La pestaña \"" + nombre + "\" no tiene marca de agua todavía.");
  const n = Number(String(hasta).trim());
  if (!isFinite(n) || n !== Math.floor(n) || n < 1) {
    throw new Error("\"" + hasta + "\" no es un número de fila.");
  }
  if (n === 1) {
    throw new Error(
      "La fila 1 es la de los encabezados: dejar ahí la frontera es reprocesar el " +
      "origen ENTERO. Si de verdad es lo que quieres, borra la fila de esta pestaña " +
      "en \"" + HOJA_MARCAS + "\" a conciencia."
    );
  }
  if (n >= Number(marca.ultimaFila)) {
    throw new Error(
      "Esto solo RETROCEDE. La marca de \"" + nombre + "\" está en la fila " +
      marca.ultimaFila + " y has pedido la " + n + ". Adelantar la frontera a mano " +
      "haría desaparecer leads sin dejar rastro; se adelanta sola al procesar."
    );
  }
  if (n > datos.length) {
    throw new Error("La pestaña \"" + nombre + "\" tiene " + datos.length +
      " filas: la " + n + " no existe.");
  }
  if (Number(marca.ultimaFila) - n > TOPE_RETROCESO) {
    throw new Error(
      "Retroceso demasiado grande: " + (Number(marca.ultimaFila) - n) + " filas, y el " +
      "tope son " + TOPE_RETROCESO + ". Por debajo de la frontera hay filas viejas SIN " +
      "fecha que volverían a contar como leads nuevos y entrarían con la fecha de hoy. " +
      "Retrocede hasta donde de verdad haga falta, o cambia TOPE_RETROCESO a conciencia."
    );
  }
  return {
    sheetId: marca.sheetId,
    nombre: nombre,
    ultimaFila: n,
    filas: datos.length,
    cabeceras: huellaCabeceras(datos[0] || []),
    ancla: anclaDeFilas(datos, n),
    actualizado: "", // lo sella `guardarMarcas` con la hora de ahora
  };
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
