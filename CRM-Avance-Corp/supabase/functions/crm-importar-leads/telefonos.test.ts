import { assertEquals } from "jsr:@std/assert@1";
import {
  normalizarTelefono,
  normalizarTelefonoAlternativo,
  reconocerTelefono,
  repartirNumeros,
} from "./telefonos.ts";

const e164 = (v: string) => reconocerTelefono(v)?.e164 ?? null;
const clase = (v: string) => reconocerTelefono(v)?.clase ?? null;

Deno.test("celular peruano: como lo escribe la gente y como lo rompe Sheets", () => {
  assertEquals(e164("987654321"), "+51987654321");
  assertEquals(e164("+51987654321"), "+51987654321");
  assertEquals(e164("51987654321"), "+51987654321");
  assertEquals(e164("987 654 321"), "+51987654321");
  assertEquals(e164("987-654-321"), "+51987654321");
  // Sheets formatea el celular como numero y mete separadores de millar.
  assertEquals(e164("964,262,777"), "+51964262777");
  assertEquals(e164("(51) 987 654 321"), "+51987654321");
  // Fila REAL del origen: el numero venia con un "p:" pegado delante.
  assertEquals(e164("p:+51910585900"), "+51910585900");
  assertEquals(clase("987654321"), "celular_pe");
});

Deno.test("fijo peruano: Lima y provincias, con y sin el 0 de larga distancia", () => {
  assertEquals(e164("014457890"), "+5114457890");   // Lima con 0
  assertEquals(e164("+51 1 445 7890"), "+5114457890");
  assertEquals(e164("084 234567"), "+5184234567");  // Cusco
  assertEquals(e164("044-123456"), "+5144123456");  // Trujillo
  assertEquals(clase("014457890"), "fijo_pe");
  // Un fijo NO es movil: no sirve de identidad si hay un celular en la fila.
  assertEquals(reconocerTelefono("014457890")?.movil, false);
});

Deno.test("el mundo: E.164 de cualquier pais", () => {
  assertEquals(e164("+1 415 555 2671"), "+14155552671");      // EE. UU.
  assertEquals(e164("+34 612 345 678"), "+34612345678");      // España
  assertEquals(e164("+39 06 6982"), "+39066982");             // Vaticano (corto y real)
  assertEquals(e164("+81 90 1234 5678"), "+819012345678");    // Japón
  assertEquals(e164("+56 9 8765 4321"), "+56987654321");      // Chile
  // El 00 de salida es tan internacional como el +.
  assertEquals(e164("0034612345678"), "+34612345678");
  assertEquals(clase("+34612345678"), "internacional");
});

Deno.test("lo que NO es un telefono se rechaza", () => {
  assertEquals(e164(""), null);
  assertEquals(e164("   "), null);
  assertEquals(e164("rosa@correo.com"), null);
  assertEquals(e164("5ooooo"), null);          // fila real del origen
  assertEquals(e164("12345"), null);           // truncado
  assertEquals(e164("50,000"), null);          // un MONTO, no un telefono
  assertEquals(e164("9158903210"), null);      // 10 digitos: celular peruano malo
  // Ocho digitos PELADOS no son un fijo: son la forma exacta de un DNI peruano.
  // Aceptarlos convertia todo documento en un telefono.
  assertEquals(e164("14457890"), null);
  assertEquals(e164("46736918"), null);
  // Dice ser peruano y no tiene forma peruana: NO se cuela por la puerta
  // internacional. Si lo hiciera, nadie podria llamarlo nunca.
  assertEquals(e164("+51123456789"), null);
  assertEquals(e164("+511234567890123"), null);
  // Sin `+` y sin forma peruana no hay pais que suponer: no se inventa uno.
  assertEquals(e164("4155552671"), null);
});

Deno.test("el principal exige MOVIL; el segundo acepta tambien fijo", () => {
  assertEquals(normalizarTelefono("987654321"), "+51987654321");
  assertEquals(normalizarTelefono("+34612345678"), "+34612345678");
  assertEquals(normalizarTelefono("014457890"), null, "un fijo no es identidad por si solo");
  assertEquals(normalizarTelefonoAlternativo("014457890"), "+5114457890");
  assertEquals(normalizarTelefonoAlternativo("+14155552671"), "+14155552671");
});

Deno.test("repartir: basta UN numero bueno para que el lead entre", () => {
  // El caso que Miguel pidio: el principal esta mal, el segundo esta bien.
  // Antes esto era un lead PERDIDO; ahora entra con el numero que si sirve.
  assertEquals(repartirNumeros(["5ooooo", "987654321"]),
    { principal: "+51987654321", alternativo: null });

  // Dos buenos: identidad + canal alternativo.
  assertEquals(repartirNumeros(["987654321", "918620573"]),
    { principal: "+51987654321", alternativo: "+51918620573" });

  // El movil MANDA aunque el fijo venga primero: WhatsApp es como se trabaja.
  assertEquals(repartirNumeros(["014457890", "987654321"]),
    { principal: "+51987654321", alternativo: "+5114457890" });

  // Solo fijos: el lead entra igual. Antes se descartaba entero.
  assertEquals(repartirNumeros(["014457890", "084234567"]),
    { principal: "+5114457890", alternativo: "+5184234567" });

  // Repetido: no se duplica (decision D2).
  assertEquals(repartirNumeros(["987654321", "+51987654321"]),
    { principal: "+51987654321", alternativo: null });

  // Los DOS mal: ESTE es el unico caso que se descarta.
  assertEquals(repartirNumeros(["5ooooo", "12345"]),
    { principal: null, alternativo: null });
  assertEquals(repartirNumeros([]), { principal: null, alternativo: null });
  assertEquals(repartirNumeros([null, undefined, ""]), { principal: null, alternativo: null });
});
