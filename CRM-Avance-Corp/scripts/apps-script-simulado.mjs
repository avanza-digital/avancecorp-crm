/**
 * Apps Script simulado, lo justo para ejecutar los .gs del puente y el conector.
 * ─────────────────────────────────────────────────────────────────────────────
 * POR QUÉ EXISTE. Las pruebas del puente solo podían tocar funciones PURAS: todo lo
 * que de verdad puede romperse en producción —la marca de agua leída y escrita, dos
 * corridas pisándose, una escritura que falla a mitad, la hoja quedándose sin filas—
 * vive en `procesar()`, y `procesar()` no se puede llamar sin Hojas de Google.
 *
 * Esto NO pretende ser Apps Script. Pretende ser lo bastante fiel en los sitios donde
 * el código real se rompe:
 *
 *  · `getRange` LANZA si se sale de la rejilla. Es el fallo exacto que mató a la
 *    quinta pasada llena (escribir en la fila 2002 de una hoja de 2001), y una
 *    simulación permisiva lo habría escondido para siempre.
 *  · `getDisplayValues` devuelve SIEMPRE texto, como la de verdad: es la diferencia
 *    entre leer "00123456" y leer el número 123456.
 *  · `getLastRow` mira contenido, no rejilla.
 *  · Los disparadores se cuentan de verdad, para poder exigir que preparar la hoja
 *    NO encienda nada.
 *  · Cada hoja CUENTA sus lecturas de datos. Es lo que permite exigir que el
 *    pre-chequeo de la cadencia no descargue ni una celda del origen: sin ese
 *    contador, "es barato" sería una afirmación de comentario, no una prueba.
 *  · El RELOJ se pone a mano y el código solo puede leerlo por `Utilities.formatDate`
 *    en la zona de Lima — pedir otra zona LANZA, porque leer la hora en la zona del
 *    proyecto de Apps Script es justo el fallo que se quiere hacer imposible.
 *
 * Lo que no se usa, no está. Si un día el código llama a algo que falta, el error
 * será "no es una función", que es un fallo honesto y fácil de leer.
 */

const texto = (v) => (v === null || v === undefined ? "" : String(v));

class Rango {
  constructor(hoja, fila, columna, numFilas, numColumnas) {
    this.hoja = hoja;
    this.fila = fila;
    this.columna = columna;
    this.numFilas = numFilas;
    this.numColumnas = numColumnas;
  }
  getValues() {
    this.hoja.lecturas++;
    this.hoja.celdasLeidas += this.numFilas * this.numColumnas;
    const out = [];
    for (let f = 0; f < this.numFilas; f++) {
      const fila = [];
      for (let c = 0; c < this.numColumnas; c++) {
        fila.push(this.hoja._leer(this.fila + f, this.columna + c));
      }
      out.push(fila);
    }
    return out;
  }
  /** El valor de la celda de arriba a la izquierda del rango, como la de verdad. */
  getValue() {
    this.hoja.lecturas++;
    this.hoja.celdasLeidas++;
    return this.hoja._leer(this.fila, this.columna);
  }
  getDisplayValues() {
    this.hoja.lecturas++;
    this.hoja.celdasLeidas += this.numFilas * this.numColumnas;
    const out = [];
    for (let f = 0; f < this.numFilas; f++) {
      const fila = [];
      for (let c = 0; c < this.numColumnas; c++) {
        fila.push(this.hoja._mostrar(this.fila + f, this.columna + c));
      }
      out.push(fila);
    }
    return out;
  }
  setValues(valores) {
    if (valores.length !== this.numFilas) {
      throw new Error(`setValues: se esperaban ${this.numFilas} filas y llegaron ${valores.length}`);
    }
    this.hoja._alEscribir(this);
    valores.forEach((fila, f) => {
      if (fila.length !== this.numColumnas) {
        throw new Error(`setValues: se esperaban ${this.numColumnas} columnas y llegaron ${fila.length}`);
      }
      fila.forEach((v, c) => this.hoja._escribir(this.fila + f, this.columna + c, v));
    });
    return this;
  }
  setValue(v) {
    this.hoja._alEscribir(this);
    this.hoja._escribir(this.fila, this.columna, v);
    return this;
  }
  clearContent() {
    for (let f = 0; f < this.numFilas; f++) {
      for (let c = 0; c < this.numColumnas; c++) this.hoja._escribir(this.fila + f, this.columna + c, "");
    }
    return this;
  }
  setNumberFormat(f) {
    for (let i = 0; i < this.numFilas; i++) {
      for (let c = 0; c < this.numColumnas; c++) {
        this.hoja.formatos.set(`${this.fila + i},${this.columna + c}`, f);
      }
    }
    return this;
  }
  setDataValidation(v) {
    for (let i = 0; i < this.numFilas; i++) {
      for (let c = 0; c < this.numColumnas; c++) {
        this.hoja.validaciones.set(`${this.fila + i},${this.columna + c}`, v);
      }
    }
    return this;
  }
  // Cosmética: se acepta y se ignora, pero encadenando como la de verdad.
  setFontWeight() { return this; }
  setBackground() { return this; }
  setFontColor() { return this; }
  setWrap() { return this; }
  setVerticalAlignment() { return this; }

  // Lo que necesita `onEdit(e)`: `e.range` es un Range de verdad, con estos getters.
  getSheet() { return this.hoja; }
  getRow() { return this.fila; }
  getColumn() { return this.columna; }
  getLastRow() { return this.fila + this.numFilas - 1; }
  getLastColumn() { return this.columna + this.numColumnas - 1; }
}

class Hoja {
  constructor(nombre, id, filas = []) {
    this.nombre = nombre;
    this.id = id;
    this.celdas = new Map(); // "fila,col" → valor
    this.formatos = new Map();
    this.formatoFecha = new Map(); // celdas que Sheets convirtió en fecha, y cómo se ven
    this.validaciones = new Map();
    this.maxFilas = Math.max(filas.length, 1000); // como una hoja nueva de Google
    this.maxColumnas = 26;
    this.oculta = false;
    this.protecciones = [];
    this.reglasCondicionales = [];
    this.filaCongelada = 0;
    this.fallarAlEscribir = null; // gancho para probar el fallo parcial
    this.lecturas = 0;            // cuántas veces se descargaron datos de esta hoja
    this.celdasLeidas = 0;        // y cuántas celdas: el coste que el pre-chequeo evita
    filas.forEach((fila, f) =>
      fila.forEach((v, c) => {
        if (texto(v) !== "") this.celdas.set(`${f + 1},${c + 1}`, v);
      })
    );
    if (filas.length) this.maxColumnas = Math.max(this.maxColumnas, ...filas.map((f) => f.length));
  }
  _leer(f, c) {
    const v = this.celdas.get(`${f},${c}`);
    return v === undefined ? "" : v;
  }
  /**
   * SHEETS INTERPRETA LO QUE LE ESCRIBES. Esta es la parte que faltaba y por la que
   * un fallo real de producción salía verde en las pruebas: el simulador guardaba el
   * texto tal cual y lo devolvía idéntico, así que la ida y vuelta nunca deformaba
   * nada. En la hoja de verdad, escribir el texto "16/08/2026 16:48" en una celda sin
   * formato de texto guarda una FECHA — y `getValues` la devuelve como objeto Date.
   *
   * Se modela solo lo que este proyecto escribe (fechas dd/MM/yyyy con y sin hora).
   * El blindaje real es `setNumberFormat("@")`: con la celda en formato texto, Sheets
   * guarda la cadena intacta, y aquí igual.
   */
  _escribir(f, c, v) {
    const clave = `${f},${c}`;
    if (texto(v) === "") {
      this.celdas.delete(clave);
      this.formatoFecha.delete(clave);
      return;
    }
    // Una cadena que empieza por "=" se guarda como FÓRMULA, y esto NO lo evita el
    // formato de texto: es la semántica de setValues. Lo que vuelve al leer es el
    // RESULTADO, nunca el texto escrito. No sabemos calcular fórmulas —ni falta—:
    // basta con devolver algo que no sea lo que se escribió, que es justo el fallo.
    if (typeof v === "string" && v.charAt(0) === "=") {
      this.formatoFecha.delete(clave);
      this.celdas.set(clave, "#FÓRMULA");
      return;
    }
    if (typeof v === "string" && this.formatos.get(clave) !== "@") {
      const m = v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?: (\d{1,2}):(\d{2}))?$/);
      if (m) {
        this.celdas.set(clave, new Date(+m[3], +m[2] - 1, +m[1], +(m[4] || 0), +(m[5] || 0)));
        // La celda se queda con formato de fecha: es lo que decide cómo se MUESTRA.
        this.formatoFecha.set(clave, m[4] === undefined ? "dd/MM/yyyy" : "dd/MM/yyyy HH:mm");
        return;
      }
    }
    this.formatoFecha.delete(clave);
    this.celdas.set(clave, v);
  }

  /** Lo que se VE en la celda: una fecha se muestra con el formato de la celda. */
  _mostrar(f, c) {
    const clave = `${f},${c}`;
    const v = this.celdas.get(clave);
    if (v === undefined) return "";
    const patron = this.formatoFecha.get(clave);
    if (patron && Object.prototype.toString.call(v) === "[object Date]") {
      const dd = String(v.getDate()).padStart(2, "0");
      const MM = String(v.getMonth() + 1).padStart(2, "0");
      const hh = String(v.getHours()).padStart(2, "0");
      const mi = String(v.getMinutes()).padStart(2, "0");
      return patron === "dd/MM/yyyy"
        ? `${dd}/${MM}/${v.getFullYear()}`
        : `${dd}/${MM}/${v.getFullYear()} ${hh}:${mi}`;
    }
    return texto(v);
  }
  _alEscribir(rango) {
    if (this.fallarAlEscribir) this.fallarAlEscribir(rango);
  }

  getName() { return this.nombre; }
  setName(n) { this.nombre = n; return this; }
  getSheetId() { return this.id; }
  getMaxRows() { return this.maxFilas; }
  getMaxColumns() { return this.maxColumnas; }

  getLastRow() {
    let ultima = 0;
    for (const clave of this.celdas.keys()) {
      const f = Number(clave.split(",")[0]);
      if (f > ultima) ultima = f;
    }
    return ultima;
  }
  getLastColumn() {
    let ultima = 0;
    for (const clave of this.celdas.keys()) {
      const c = Number(clave.split(",")[1]);
      if (c > ultima) ultima = c;
    }
    return ultima;
  }

  getRange(fila, columna, numFilas = 1, numColumnas = 1) {
    // FIEL A PROPÓSITO: Apps Script lanza si el rango se sale de la rejilla. Es el
    // fallo que dejaba la quinta pasada llena muerta a mitad; si esto no lanzara,
    // la prueba de capacidad pasaría siempre y no probaría nada.
    if (fila < 1 || columna < 1) throw new Error("getRange: fila y columna empiezan en 1");
    if (fila + numFilas - 1 > this.maxFilas) {
      throw new Error(
        `Those rows are out of bounds: pidió hasta la fila ${fila + numFilas - 1} y la hoja "${this.nombre}" tiene ${this.maxFilas}`
      );
    }
    if (columna + numColumnas - 1 > this.maxColumnas) {
      throw new Error(`Those columns are out of bounds: la hoja "${this.nombre}" tiene ${this.maxColumnas}`);
    }
    return new Rango(this, fila, columna, numFilas, numColumnas);
  }
  getDataRange() {
    return new Rango(this, 1, 1, Math.max(this.getLastRow(), 1), Math.max(this.getLastColumn(), 1));
  }

  insertRowsAfter(despues, cuantas) {
    this.maxFilas += cuantas;
    return this;
  }
  appendRow(valores) {
    const f = this.getLastRow() + 1;
    if (f > this.maxFilas) this.maxFilas = f;
    valores.forEach((v, c) => this._escribir(f, c + 1, v));
    return this;
  }
  hideSheet() { this.oculta = true; return this; }
  showSheet() { this.oculta = false; return this; }
  setFrozenRows(n) { this.filaCongelada = n; return this; }
  setRowHeight() { return this; }
  setColumnWidth() { return this; }
  setConditionalFormatRules(r) { this.reglasCondicionales = r; return this; }
  getProtections() { return this.protecciones; }
  protect() {
    const p = {
      descripcion: "",
      editores: [{ getEmail: () => "duenio@avancecorp.pe" }],
      setDescription(d) { p.descripcion = d; return p; },
      addEditor() { return p; },
      removeEditors() { return p; },
      getEditors() { return p.editores; },
      canDomainEdit() { return false; },
      setDomainEdit() { return p; },
    };
    this.protecciones.push(p);
    return p;
  }
}

class Libro {
  constructor(nombre, hojas) {
    this.nombre = nombre;
    this.hojas = hojas;
    this.avisos = [];
    this.siguienteId = 9000;
  }
  getName() { return this.nombre; }
  /**
   * La zona del DOCUMENTO — la que decide qué día muestra una celda de fecha suya.
   * El puente se la pide al ORIGEN para leer sus fechas nativas; aquí los dos
   * documentos están en Lima, que es la única zona que este doble sabe formatear.
   */
  getSpreadsheetTimeZone() { return "America/Lima"; }
  getSheets() { return this.hojas.slice(); }
  getNumSheets() { return this.hojas.length; }
  getSheetByName(n) { return this.hojas.find((h) => h.getName() === n) || null; }
  insertSheet(nombre, indice) {
    const hoja = new Hoja(nombre, this.siguienteId++);
    if (indice === undefined) this.hojas.splice(1, 0, hoja); // como la de verdad: junto a la activa
    else this.hojas.splice(indice, 0, hoja);
    return hoja;
  }
  toast(mensaje, titulo) { this.avisos.push({ mensaje, titulo }); }
}

/**
 * Monta el juego de dobles. Devuelve los globales que hay que inyectar en los .gs y
 * los cabos para espiar desde las pruebas (disparadores creados, peticiones HTTP,
 * si se pidió el candado…).
 */
export function crearEntorno({
  destino,
  origen,
  candadoLibre = true,
  propiedades = {},
  respuestaHttp,
  ahora = "2026-08-17 09:20", // lunes 17 de agosto, dentro de la ventana
  sinInterfaz = false,
} = {}) {
  const espia = {
    disparadores: [],
    peticiones: [],
    candadoPedido: 0,
    candadoSoltado: 0,
    avisos: [],
    ventanas: [],   // lo que `informar()` habría enseñado en pantalla
    respuestas: [], // el guion de lo que contesta quien mira: [{ boton, texto }, …]
    menu: [],       // los ítems del menú AVANCE CORP, en orden
    menuNombre: "",
    propiedades: { ...propiedades },
    // Se puede cambiar A MITAD de una prueba: hay escenarios que necesitan preparar
    // el mundo con el candado libre y solo DESPUÉS simular la corrida solapada.
    candadoLibre: candadoLibre,
    reloj: ahora,
    /** Mueve el reloj simulado: "AAAA-MM-DD HH:MM". */
    ponerReloj(cuando) { espia.reloj = cuando; },
  };

  const SpreadsheetApp = {
    getActiveSpreadsheet: () => destino,
    openById: (id) => {
      if (!origen) throw new Error("openById: no hay origen simulado");
      return origen;
    },
    ProtectionType: { SHEET: "SHEET" },
    newDataValidation() {
      const v = {
        requireValueInList() { return v; },
        setAllowInvalid() { return v; },
        setHelpText() { return v; },
        build() { return { tipo: "lista" }; },
      };
      return v;
    },
    newConditionalFormatRule() {
      const r = {
        whenTextStartsWith() { return r; },
        setBackground() { return r; },
        setFontColor() { return r; },
        setRanges() { return r; },
        build() { return { tipo: "condicional" }; },
      };
      return r;
    },
    /**
     * Con `sinInterfaz: true` LANZA, como en el editor con la hoja cerrada (ahí es
     * `informar()` quien lo captura y deja el reporte en el Registro). Por defecto
     * hay interfaz: es el caso normal —alguien con la hoja abierta— y es el único en
     * el que se puede comprobar que abrir la hoja saca los avisos a la cara.
     */
    getUi() {
      if (sinInterfaz) throw new Error("No hay interfaz de usuario disponible");
      const menu = {
        addItem: (titulo, fn) => { espia.menu.push({ titulo, fn }); return menu; },
        addSeparator: () => menu,
        addToUi: () => menu,
      };
      /**
       * PREGUNTAR ES DISTINTO DE AVISAR. `alert(texto)` solo informa; `alert(título,
       * texto, botones)` y `prompt(...)` PREGUNTAN, y su respuesta sale del guion
       * (`respuestas`, en orden). Un guion agotado responde CANCELAR: una prueba que
       * se olvide de guionizar una pregunta se para, en vez de aceptar a ciegas algo
       * que el usuario nunca dijo.
       */
      const Button = { OK: "OK", CANCEL: "CANCEL", CLOSE: "CLOSE" };
      const ButtonSet = { OK: "OK", OK_CANCEL: "OK_CANCEL" };
      const responder = () =>
        (espia.respuestas.length ? espia.respuestas.shift() : { boton: Button.CANCEL, texto: "" });
      return {
        createMenu: (nombre) => { espia.menu = []; espia.menuNombre = nombre; return menu; },
        Button,
        ButtonSet,
        alert: (...args) => {
          espia.ventanas.push(args.length > 1 ? args[1] : args[0]);
          if (args.length < 3) return Button.OK; // solo informaba
          return responder().boton;
        },
        prompt: (...args) => {
          espia.ventanas.push(args.length > 2 ? args[1] : args[0]);
          const r = responder();
          return {
            getResponseText: () => String(r.texto == null ? "" : r.texto),
            getSelectedButton: () => r.boton || Button.OK,
          };
        },
      };
    },
  };

  const LockService = {
    getScriptLock: () => ({
      tryLock: () => { espia.candadoPedido++; return espia.candadoLibre; },
      releaseLock: () => { espia.candadoSoltado++; },
    }),
  };

  const Utilities = {
    /**
     * El reloj simulado ya es hora de pared de LIMA. Pedir otra zona lanza a
     * propósito: el .gs solo puede saber la hora por aquí y solo en esta zona —
     * heredar la zona del proyecto de Apps Script (que puede estar en el Pacífico)
     * es el fallo que hace correr al puente de madrugada sin que nadie lo note.
     */
    formatDate: (fecha, zona, patron) => {
      if (zona !== "America/Lima") {
        throw new Error(`formatDate simulado: solo se admite "America/Lima", llegó "${zona}"`);
      }
      // Una fecha CONCRETA (la que salió de una celda) se formatea tal cual; solo
      // `new Date()` —el "ahora" del código— se sustituye por el reloj simulado. Sin
      // esta distinción, formatear una fecha guardada devolvería la hora actual y una
      // prueba de ida y vuelta pasaría aunque el arreglo estuviera mal.
      const esAhora = !fecha || Math.abs(fecha.getTime() - Date.now()) < 5000;
      if (esAhora) return formatearMomento(espia.reloj, patron);
      const p = (n) => String(n).padStart(2, "0");
      return formatearMomento(
        `${fecha.getFullYear()}-${p(fecha.getMonth() + 1)}-${p(fecha.getDate())} ` +
        `${p(fecha.getHours())}:${p(fecha.getMinutes())}`,
        patron
      );
    },
  };

  const Session = { getEffectiveUser: () => ({ getEmail: () => "duenio@avancecorp.pe" }) };

  const ScriptApp = {
    WeekDay: { MONDAY: 1, TUESDAY: 2, WEDNESDAY: 3, THURSDAY: 4, FRIDAY: 5, SATURDAY: 6, SUNDAY: 7 },
    getProjectTriggers: () => espia.disparadores.slice(),
    deleteTrigger: (t) => {
      const i = espia.disparadores.indexOf(t);
      if (i >= 0) espia.disparadores.splice(i, 1);
    },
    newTrigger(fn) {
      const b = {
        _fn: fn,
        timeBased() { return b; },
        everyMinutes(n) { b._cada = n; return b; },
        onWeekDay(d) { b._dia = d; return b; },
        atHour(h) { b._hora = h; return b; },
        inTimezone(z) { b._zona = z; return b; },
        forSpreadsheet() { return b; },
        onOpen() { return b; },
        create() {
          const t = { getHandlerFunction: () => fn, cada: b._cada, dia: b._dia, hora: b._hora, zona: b._zona };
          espia.disparadores.push(t);
          return t;
        },
      };
      return b;
    },
  };

  const PropertiesService = {
    getScriptProperties: () => ({
      getProperty: (k) => (k in espia.propiedades ? espia.propiedades[k] : null),
      setProperty: (k, v) => { espia.propiedades[k] = String(v); },
      deleteProperty: (k) => { delete espia.propiedades[k]; },
    }),
  };

  const UrlFetchApp = {
    fetch(url, opciones) {
      espia.peticiones.push({ url, opciones });
      const r = respuestaHttp || { codigo: 200, cuerpo: JSON.stringify({ resultados: [] }) };
      if (r.error) throw r.error;
      return { getResponseCode: () => r.codigo, getContentText: () => r.cuerpo };
    },
  };

  const consola = {
    log: (...a) => espia.avisos.push(a.join(" ")),
    error: (...a) => espia.avisos.push(a.join(" ")),
    warn: (...a) => espia.avisos.push(a.join(" ")),
  };

  return {
    globales: {
      SpreadsheetApp, LockService, Utilities, Session, ScriptApp,
      PropertiesService, UrlFetchApp, console: consola,
    },
    espia,
  };
}

/**
 * Formatea el instante simulado según el patrón que pida el .gs. Solo entiende los
 * trozos que el código usa de verdad; cualquier otro se queda tal cual, que es un
 * fallo visible en la aserción y no un valor plausible pero falso.
 */
function formatearMomento(cuando, patron) {
  const m = String(cuando).match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) throw new Error(`Reloj simulado inválido: "${cuando}" (formato "AAAA-MM-DD HH:MM")`);
  return String(patron)
    .replace(/yyyy/g, m[1])
    .replace(/MM/g, m[2])
    .replace(/dd/g, m[3])
    .replace(/HH/g, m[4])
    .replace(/mm/g, m[5])
    .replace(/ss/g, m[6] || "00");
}

export { Hoja, Libro, Rango };
