import { assert } from "jsr:@std/assert@1";
import { etiquetaPropia } from "./catalogo.ts";

const CANALES: Record<string, string> = { landing: "landing", otro: "otro" };

Deno.test("catálogo: una etiqueta propia se resuelve", () => {
  assert(etiquetaPropia(CANALES, "landing") === "landing");
});

Deno.test("catálogo: «constructor» y «__proto__» NO se resuelven por el prototipo", () => {
  assert(etiquetaPropia(CANALES, "constructor") === undefined, "constructor");
  assert(etiquetaPropia(CANALES, "__proto__") === undefined, "__proto__");
  assert(etiquetaPropia(CANALES, "tostring") === undefined, "tostring");
  assert(etiquetaPropia(CANALES, "toString") === undefined, "toString");
});
