# Portal — el interés simple se devenga como el cronograma, no por días/365 (2026-09-30)

Fecha: 2026-09-30. Decisión de Miguel en sesión, afinada con el review de Codex (2 rondas). Relacionado:
[[Plan Rentabilidad server-side - tasa decidida por politica 2026-09-06]], [[project_interes_compuesto]],
[[Deploy a Hostinger]].

**✅ PUBLICADO 30/09/2026 ~17:15** (commit portal `fd3651d`, SW `avance-v137`; bitácora `d22eae6`). Subido
archivo por archivo por TUS con `_DEV_NO_SUBIR/subir-portal-archivos.mjs` (verifica sha256, SW al final,
purga servidor + CDN; token desde el llavero de macOS, entrada `hostinger-api`). Los 6 archivos coinciden en
vivo byte a byte, también en las URL versionadas (`dashboard.js?v=37`, `inversion.js?v=30`,
`devengo-simple.js?v=1`). Miguel publicó sin corregir antes los contratos del censo de abajo.

**Verificado en producción tras publicar (30/09, solo lectura):** de los 677 contratos simples vigentes
(activo/vencido), el monto final del portal (módulo publicado, TZ Lima) es igual a capital + suma de cuotas
`tipo='cuota'` del cronograma en **675**. Antes (días/365) se desviaban más de 0,50 en 258. Los 2 que no cuadran
son anteriores a este cambio:
- **2026-01-000644** (6 667 USD, 18 %, mensual): la cuota exacta es 100,005 → el portal redondea a 100,01 y el
  cronograma tiene 100. El portal enseña 1 200,12 contra 1 200: 12 céntimos.
- **2026-01-000768** (50 000 PEN, mensual): la tasa se cambió de 15 % a 20 % el 12/08/2026, con la cuota 1 ya pagada
  (625). El cronograma paga 625 + 11 × 833,33 = 9 791,63, y el portal calcula las 12 cuotas al 20 % (9 999,96):
  enseña **S/ 208,33 de más**. El portal no conoce los cambios de tasa a mitad de contrato; lo robusto sería que
  lea los montos del cronograma en vez de recalcularlos.

## El caso que lo destapó

Contrato **2026-01-001511**: 20 000 USD, 15 % anual, interés simple, mensual, 29/09/2026 → 29/03/2027
(6 meses). El cronograma (`generarCronograma` del admin) le paga **6 cuotas de 250 = 1 500** → 21 500 al
vencer. El portal del cliente devengaba `capital × tasa/100 / 365 × días` y, como 6 meses calendario son
**181 días** (no 182,5), mostraba **21 488** como monto final en la pantalla de inicio, y «21.5K» en el gráfico
(redondeo a un decimal en `premium-chart.js`). No había dos cálculos distintos entre inicio y gráfico: era el
mismo número abreviado. La divergencia real era portal (días) vs cronograma (cuotas).

Miguel también preguntó por qué el CRM «sale bien» y el portal «menos»: el CRM muestra la **tasa** pactada
(15 % anual); el portal muestra la **ganancia acumulada** hasta hoy y su % sobre el capital, que en un contrato
de 6 meses llega como máximo al 7,5 %. Son medidas distintas, no un error.

## Regla vigente: el portal reproduce el cronograma, sin interpretarlo

Para interés **simple**, `valorContratoAFecha` (dashboard e inversión) devenga con
`public_html/js/utils/devengo-simple.js`, espejo literal de la rama simple de `generarCronograma`:

- **Cuota** = `redondear2(capital × tasa/100 ÷ cuotasPorAnio)` según modalidad (mensual 12, trimestral 4,
  semestral 2, anual 1), con el mismo `redondear2` del admin. Suma cuotas enteras: 10 000 al 10 % mensual
  son 12 × 83,33 = **999,96**, no 1 000 (222 de los 677 contratos simples tienen cuota con redondeo).
- **Aniversarios** de periodo: mismo día del mes; si no existe (31-ene → feb) el último día del mes.
- **Solo hay cuota si su aniversario cae ≤ vencimiento.** Un tramo final más corto que el periodo NO devenga:
  el cronograma tampoco lo paga. El portal muestra lo que se pagará; no lo maquilla.
- Entre aniversarios devenga la **fracción de la cuota del periodo en curso** (días corridos ÷ días del
  periodo), para que la ganancia crezca día a día. Corte acotado al vencimiento y congelado en `cerrado_en`.
- El gráfico (`buildEvolution`) muestrea con `aniversarioMensual`; antes `setMonth` desbordaba (31-ene → 3-mar).

El interés **compuesto** (`saldoCompuesto`, capitalización anual) no cambia.

Primer intento (descartado por el review): «meses × capital × tasa/12» sin redondeo ni tope por cuota. Divergía
del cronograma en centavos por redondeo y en cuotas enteras cuando el plazo no es múltiplo del periodo.

## Lo que el censo de producción dejó a la vista (30/09/2026, solo lectura)

Seis contratos activos con vencimiento fuera de aniversario, donde el portal antiguo mostraba un interés que
el cronograma **no paga**:

| Contrato | Modalidad | Plazo | Cronograma | Sospecha |
|---|---|---|---|---|
| 2026-01-001035, 001060, 001131 | `anual` | 6 meses | **0 cuotas** de interés, solo retorno | modalidad o plazo mal cargados |
| 2026-01-001239 | mensual | 16/08/26 → 15/02/27 | **5 cuotas** (el 6.º aniversario es el 16/02) | vencimiento un día corto |
| 2026-01-001464 | mensual | 22/09/26 → 21/03/27 | 5 cuotas (mismo patrón) | vencimiento un día corto |
| 2026-01-000477 | mensual | 29/04 → 06/11/26 | 6 cuotas; 8 días residuales sin interés | plazo personalizado |

Con la regla nueva, esos clientes verán en el portal exactamente lo que dice su cronograma (en los tres
`anual` de 6 meses: ganancia 0). **Acción de Miguel:** revisar esos altas y corregirlas por la puerta oficial
de corrección de contratos (nunca SQL directo), idealmente antes de publicar el portal.

## Dónde vive

- `public_html/js/utils/devengo-simple.js` (`interesSimpleDevengado`, `aniversarioMensual`, `aFechaLocal`,
  `redondear2`) + `tests/devengo-simple.test.mjs` (oráculo transcrito del admin, propiedad >5 000 casos).
- `js/dashboard.js` e `js/inversion.js`: rama simple de `valorContratoAFecha` y muestreo de `buildEvolution`.
  Se retiró `rentabilidadDiaria` (días/365) de ambos.
- Bumps: `dashboard.js v37`, `inversion.js v30`, SW `avance-v137`.

## Lo que NO se tocó

Ni la base ni el generador del cronograma. El contrato 001511 está bien registrado (categoría «nuevo»,
6 cuotas). Si un cliente pactó 12 meses y quedó a 6, el error es la `fecha_vencimiento`, y se corrige por la
puerta oficial de corrección de contratos.
