# Tipo de cambio BCRP: septiembre llega como «Set» (2026-09-18)

**Síntoma.** Desde el 1 de septiembre de 2026 la Edge Function `crm-tipo-cambio` respondía
502 («BCRP sin datos en la ventana consultada») para cualquier `fecha_corte` de septiembre.
El ranking mensual de Gerencia y las pantallas que convierten US$ degradaban a solo-PEN con el
aviso ámbar «Tipo de cambio no disponible» + «Reintentar», sin que nadie pudiera saber si la
culpa era del BCRP o nuestra.

**Causa raíz (verificada contra la API en vivo el 18/09).** La API pública del BCRP
(`.../series/api/{serie}/json/{desde}/{hasta}/ing`) rotula los períodos con el mes abreviado en
inglés para casi todos los meses (`30.Jul.26`, `03.Aug.26`, `31.Dec.25`) **pero septiembre lo
devuelve en español: `02.Set.26`**. El mapa de meses del handler solo conocía `Jan..Dec`, así que
`clavePeriodo()` devolvía 0, el filtro `timestamp > 0` tiraba TODAS las filas de septiembre y el
resultado era indistinguible de «el BCRP no publicó nada». Se habría «arreglado solo» el 1 de
octubre, por eso parecía intermitente.

**Arreglo.**
- Mapa `MESES` con las dos variantes de TODOS los meses (`ene/jan … set/sep/sept … dic/dec`),
  normalizando la clave (trim + minúsculas) antes de buscar.
- `clavePeriodo()` devuelve `null` (no 0) cuando no reconoce el formato, y el cálculo distingue
  dos silencios: si el BCRP devolvió períodos y NINGUNO se pudo leer → 502 con
  `BCRP: formato de período no reconocido: <período literal>`; si devolvió cero períodos o todo
  «n.d.» → se conserva `BCRP sin datos en la ventana consultada`.
- Tests Deno con las respuestas LITERALES del BCRP (septiembre con el «n.d.» del 18, jul/ago en
  inglés con «n.d.»), período basura, todo «n.d.» y mezcla parcial.
- Front: el hook `useTipoCambio` lee el `{ error }` que responde la edge (desde
  `FunctionsHttpError.context`) para el aviso `crm.tipo_cambio_no_disponible`; los textos de UI
  de Gerencia, ranking y detalle dicen ahora «Tipo de cambio no disponible (fuente BCRP)».

**Dato de control.** Con corte 2026-09-18 el promedio esperado es **3.3685** (punto medio
compra/venta de los 7 días hábiles del 09 al 17 de septiembre; solo-compra daría 3.3644).

**Regla que deja.** Un período ilegible de una fuente externa NUNCA se descarta en silencio: se
falla nombrándolo. Cuando un fallo de parseo y un fallo de la fuente producen el mismo mensaje,
el bug se disfraza de «problema del proveedor» durante semanas.

Relacionado: [[Inventario de indicadores de Gerencia - Contrato de lectura]] ·
[[Descuadre Ranking vs Mi cartera por cierres en cooperativas (2026-09-02)]] · [[Deploy a Hostinger]]
