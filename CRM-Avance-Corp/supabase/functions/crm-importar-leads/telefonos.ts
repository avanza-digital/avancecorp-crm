/**
 * LA REGLA DEL TELEFONO, en un solo sitio y probada.
 * ────────────────────────────────────────────────────────────────────────────
 * Vivia dentro de index.ts, que no es testeable (tiene un `Deno.serve` en el
 * ambito del modulo, asi que importarlo levanta un servidor). Este modulo es el
 * ORIGINAL; sus gemelos —`app/src/lib/validacion.ts` en el front,
 * `telefonoPeru()` en el puente y el CHECK `leads_telefono_alternativo_formato`
 * en la base— tienen que decir lo mismo. Cambiar uno sin los otros es como se
 * pierde un lead en silencio.
 *
 * DECISIONES DE MIGUEL (2026-08-26):
 *   · «que los leads vengan con sus dos numeros si o si»
 *   · «si los dos numeros estan mal, ahi si debe descartarlo» → basta UN numero
 *     bueno para que el lead entre al CRM
 *   · «debe reconocer formatos de numero a nivel mundial»
 *
 * COMO SE RECONOCE UN NUMERO DEL MUNDO. Sin libphonenumber: no existe en el
 * Apps Script del puente ni dentro de un CHECK de Postgres, y la regla tiene que
 * ser LA MISMA en las cuatro capas o vuelve el silencio. Se usa E.164, que es el
 * estandar que define que es un numero de telefono en el planeta:
 *
 *   · Si el texto trae `+` o empieza por `00` (prefijo internacional), es
 *     INTERNACIONAL: entre 8 y 15 digitos en total, primer digito 1-9.
 *   · Si no, se asume PERU, que es de donde viene el 99% del negocio: nueve
 *     digitos empezando en 9 es celular; ocho digitos es fijo.
 *   · Un numero que dice ser peruano (empieza por 51) NO se acepta a la ligera:
 *     tiene que tener la forma peruana exacta. Si no, `+51123` entraria como
 *     "internacional valido" y nadie podria llamarlo nunca.
 */

/** Tipo de numero reconocido. `null` = no es un telefono. */
export type ClaseTelefono = "celular_pe" | "fijo_pe" | "internacional";

export type TelefonoReconocido = {
  /** Canonico E.164: `+` y solo digitos. Es lo que se guarda. */
  e164: string;
  clase: ClaseTelefono;
  /** Sirve para WhatsApp y para recibir SMS. Un fijo, no. */
  movil: boolean;
};

const E164_MIN = 8;  // el numero mas corto del mundo con codigo de pais
const E164_MAX = 15; // tope del estandar E.164

/**
 * Reconoce un numero escrito de cualquier manera. Devuelve `null` si no hay
 * telefono que rescatar.
 *
 * Acepta la basura tipografica que llega de verdad desde Sheets y desde los
 * formularios: espacios, guiones, parentesis, puntos, y la COMA que mete Sheets
 * cuando trata el celular como numero ("964,262,777").
 */
export function reconocerTelefono(valor: string | null | undefined): TelefonoReconocido | null {
  const bruto = (valor ?? "").trim();
  if (!bruto) return null;
  // Un correo metido en la columna de telefono no es un telefono roto: es otro
  // dato en el sitio equivocado. Cuenta aparte y no ensucia lo que se pierde.
  if (bruto.includes("@")) return null;
  // Las letras NO descartan: "p:+51910585900" es una fila real del origen y el
  // numero esta ahi entero. Se juzga por los digitos que quedan.
  const digitos = bruto.replace(/\D/g, "");
  if (!digitos) return null;

  // ¿Viene marcado como internacional? El `+` explicito o el 00 de salida.
  const marcadoInternacional = bruto.trimStart().startsWith("+") || digitos.startsWith("00");
  const sinSalida = digitos.replace(/^00/, "");

  // ── Peru, se declare o no ────────────────────────────────────────────────
  // Todo lo que empieza por 51 se juzga con la vara peruana: si no tiene la
  // forma exacta, no es un numero peruano y tampoco vale como "internacional".
  const nacional = sinSalida.startsWith("51") ? sinSalida.slice(2) : sinSalida;
  const declaraPeru = sinSalida.startsWith("51") && nacional.length >= 8;

  if (declaraPeru || !marcadoInternacional) {
    const n = declaraPeru ? nacional : sinSalida;
    if (/^9\d{8}$/.test(n)) return { e164: `+51${n}`, clase: "celular_pe", movil: true };
    // ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho digitos
    // (Lima 1+siete, provincias 84+seis)… y el DNI peruano TAMBIEN tiene ocho.
    // Aceptar ocho digitos pelados convertia todo DNI en un telefono: el
    // buscador ofrecia «verificar disponibilidad» sobre un documento y el
    // formulario daba por bueno un DNI escrito en la casilla del celular. Lo
    // cazaron tres pruebas del front. Asi que un fijo solo se reconoce cuando
    // viene MARCADO como telefono: con `+51`/`0051`, o con el 0 de larga
    // distancia con el que la gente escribe su fijo de verdad (014457890).
    const marcaDeFijo = declaraPeru || n.startsWith("0");
    const sinCero = n.startsWith("0") ? n.slice(1) : n;
    if (marcaDeFijo && /^[1-8]\d{7}$/.test(sinCero)) {
      return { e164: `+51${sinCero}`, clase: "fijo_pe", movil: false };
    }
    // Dijo ser peruano y no lo es: se acaba aqui, no cae al cajon internacional.
    if (declaraPeru) return null;
    // Sin `+` y sin forma peruana: no hay pais que suponer. No se inventa uno.
    if (!marcadoInternacional) return null;
  }

  // ── El resto del mundo ───────────────────────────────────────────────────
  // E.164 puro. No se valida el codigo de pais contra una lista: mantenerla al
  // dia en cuatro capas es una deuda peor que aceptar un numero raro, y el
  // largo minimo ya deja fuera lo que no es un telefono.
  if (
    sinSalida.length >= E164_MIN && sinSalida.length <= E164_MAX &&
    /^[1-9]\d*$/.test(sinSalida)
  ) {
    // Movil o fijo es indecidible fuera de Peru sin libphonenumber. Se asume
    // MOVIL: equivocarse hacia "se puede escribir por WhatsApp" ofrece un boton
    // que quiza no responda; al reves, esconderia el unico canal que hay.
    return { e164: `+${sinSalida}`, clase: "internacional", movil: true };
  }
  return null;
}

/**
 * El telefono PRINCIPAL del lead: su identidad (dedup, reparto, conversion).
 *
 * Se sigue prefiriendo un MOVIL: es lo que responde WhatsApp, que es como se
 * trabaja aqui. Un fijo solo llega a principal cuando no hay ningun movil en la
 * fila — antes de eso, la alternativa era descartar al lead entero, y un lead
 * al que se puede llamar vale mas que un boton de WhatsApp que funcione.
 */
export function normalizarTelefono(valor: string): string | null {
  const r = reconocerTelefono(valor);
  return r && r.movil ? r.e164 : null;
}

/** El SEGUNDO numero: cualquier telefono reconocible, movil o fijo. */
export function normalizarTelefonoAlternativo(valor: string): string | null {
  const r = reconocerTelefono(valor);
  return r ? r.e164 : null;
}

/**
 * De todos los numeros que trae una fila, cual es el principal y cual el
 * segundo. Devuelve `{ principal: null }` solo cuando NINGUNO sirve — que es el
 * unico caso en que el lead se descarta.
 *
 * Orden: el primer MOVIL manda (identidad); el segundo es el siguiente numero
 * DISTINTO, sea movil o fijo. Si no hay ningun movil, el primer fijo se sube a
 * principal en vez de tirar el lead.
 */
export function repartirNumeros(
  candidatos: (string | null | undefined)[],
): { principal: string | null; alternativo: string | null } {
  const vistos: TelefonoReconocido[] = [];
  for (const c of candidatos) {
    const r = reconocerTelefono(c);
    if (r && !vistos.some((v) => v.e164 === r.e164)) vistos.push(r);
  }
  if (vistos.length === 0) return { principal: null, alternativo: null };

  const iPrincipal = vistos.findIndex((v) => v.movil);
  const principal = iPrincipal >= 0 ? vistos[iPrincipal] : vistos[0];
  const alternativo = vistos.find((v) => v.e164 !== principal.e164) ?? null;
  return { principal: principal.e164, alternativo: alternativo ? alternativo.e164 : null };
}
