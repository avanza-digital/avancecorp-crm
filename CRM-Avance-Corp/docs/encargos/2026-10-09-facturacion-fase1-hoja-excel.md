# Encargo a Codex (IMPLEMENTADOR) — Facturación fase 1: la pantalla se lee como una hoja de Excel

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Escribes SOLO dentro de este worktree
(`/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-hoja-excel-20261009`).
Sin commit, sin push, sin red, sin Docker, sin producción y sin invocar a otros agentes. Todo en español. Al terminar:
informe breve con los archivos tocados, las decisiones, lo que quedó fuera y los resultados de `npm run check` en `app/`.

## Qué es

Fase 1 del plan de Facturación por fases (vault: «Facturacion - plan por fases auditado por Codex (2026-10-09)»).
**SOLO PANTALLA.** No se toca el servidor, ni la capa de datos (`crm-api.ts`, `crm-queries.ts` salvo la política de
refresco del punto 9), ni el cálculo de cifras. **Las cifras tienen que ser idénticas antes y después.**

**Maqueta APROBADA por Miguel:** `CRM-Avance-Corp/docs/encargos/maqueta/facturacion-hoja-excel.html`. Ábrela y léela
entera: medidas, textos y comportamiento se copian de ahí. Decisiones de Miguel del 09/10:
- **días por venir PLEGADOS** en una sola columna;
- **vista Día POR TIPO**.

La parte de las listas («todo número se abre» con la hoja lateral paginada) **NO** entra en esta fase: es la 4, y
necesita un servidor nuevo. Aquí los números siguen abriendo lo que abren hoy (el panel de desglose actual). No quites
esa apertura.

## Código de partida (HEAD = `482f3811`)

**`app/src/screens/facturacion.tsx`** (1.894 líneas)
- KPIs: `:1266-1340`, cuatro `KpiCard` sin `onClick`.
- `Celda`: `:257-323`; solo es botón si `valor > 0`.
- `FilaAnalista`: `:326-416`. El botón del nombre «Ver el mes completo de …» va en `:373-389`.
- Malla: `:1389-1811`. Panel de desglose `Sheet modal={false}`: `:1813-1891`.
- Vista Día: es la misma malla con una columna (`lib/facturacion.ts:874`, `diasDelPeriodo`).
- Celular: solo CSS (`facturacion-movil.css`), sin `useEsMovil`.

**`app/src/lib/facturacion.ts`**: `construirMallaDeDias :305`, `rosterDeEquipoYFilas :532`, filtros `:582-625`,
`desgloseDeCelda :922`. Las filas del servidor ya traen `tipo` por día (`FilaFacturacionDia`, `:34-46`): la vista Día por
tipo se arma en el front, sin servidor.

**Piezas para reutilizar** (no copies; amplía con cuidado y sin dependencias de leads)
- `Pastilla` (`components/base-gestion/filtros-base.tsx:22-57`): hoy `valor` solo admite `number`. Hay que aceptar
  también un valor ya formateado (texto) y un `title`, sin romper a sus usuarios de `rescate/` y `bases-cargadas/`.
- `CELDA` y `ENCABEZADO` de `components/base-gestion/hoja-base.tsx`. **No** uses `HojaBase`: está cableada a leads.
  Falta una columna fija a la derecha; añádela en Facturación.
- `useEsMovil` (`lib/media.ts:35`, ≤767 px). `useEsEstrecha` (≤1279) ya pliega los filtros.

## Qué se construye (pasos de la maqueta)

1. **E1 · Pastillas.** Los 4 `KpiCard` pasan a una fila de pastillas pequeñas (letra de 14 px). Cada pastilla es un
   botón y abre el desglose que ya existe para esa cifra; si hoy no existe uno, no inventes una lista: déjala como
   texto con `title` y anota en el informe que la abrirá la fase 4. El resumen de arriba ocupa ≤ 56 px de alto a 1440
   (hoy, 196).
2. **E2 · Hoja.** Columna «#» seguida y equipos como bandas. A la izquierda quedan fijos el «#» y el nombre; a la derecha,
   el total.
3. **E3 · Letra.** Nombres de 16 px. Celdas, pie, cabeceras y ayudas de 14 px o más. Ningún texto visible de 9–13 px,
   salvo el que la maqueta muestre así a propósito (dilo en el informe).
4. **E4 · Días por venir PLEGADOS.** En el tramo de hoy, los días que faltan se juntan en una columna con «10–31 oct · por
   venir» (el texto exacto, el de la maqueta). En meses pasados no aparece.
5. **E5 · Vista Día POR TIPO.** Columnas Nuevo · Renovación · Upgrade · Cooperativa · Total, por analista y por equipo,
   en las dos monedas como hoy (PEN y USD nunca se suman salvo en «Todo S/» con tipo de cambio, igual que hoy).
6. **E6 · Celular (`useEsMovil`).** Una tarjeta por analista, agrupadas por equipo: nombre de 16 px, total, operaciones y
   los días en que vendió. Las pastillas arriba. La malla no se usa en el teléfono y `facturacion-movil.css` se retira si
   queda sin uso. Supervisor y Gerencia ven su ámbito, como hoy.
7. **Accesibilidad**
   - foco visible con contraste ≥ 3:1 (hoy 1,81:1);
   - `ul` con `role="list"` donde Safari lo pierde (`:1845`);
   - títulos sin saltos (h1 → h2 → h3);
   - todo lo que se pulsa tiene un mínimo de 44 px en pantallas táctiles;
   - las reglas a11y documentadas en `app/.oxlintrc.json` se respetan, sin apagar ninguna nueva.
8. **Sueltos de la auditoría**
   - «Sin supervisor» aparece una sola vez;
   - comparar con otro mes no bloquea la malla mientras carga;
   - el formateo de cifras se memoiza (hoy unos 40 ms sin memo).
9. **Refresco.** Un mes CERRADO se refresca menos seguido, pero **no se congela**. Puede cambiar, como cambió el 09/10 con
   la regla de bajas. Propuesta: el mes en curso, cada 5 minutos como hoy; un mes cerrado, solo al volver a la pestaña o
   cada 30 minutos. Es el único cambio permitido en `crm-queries.ts` (`useFacturacionDeMeses`, `:863-873`).
10. **Sin siglas en pantalla** (regla de Miguel) y sin verde.

## Pruebas

- `app/src/screens/facturacion.test.tsx` (1.454 líneas) y `app/src/lib/facturacion.test.ts`: adáptalas. **No borres
  pruebas por comodidad.** Muchas buscan el botón «Ver el mes completo de …»: conserva esa función accesible (el nombre
  sigue siendo un botón con ese nombre accesible) o, si cambia, ajusta las pruebas manteniendo lo que comprueban.
- **Pruebas nuevas, una por paso (E1–E6, 7, 8 y 9):**
  - pastillas pulsables;
  - número de fila continuo entre bandas;
  - columnas fijas;
  - columna «por venir» plegada solo en el tramo de hoy;
  - vista Día por tipo (y que su total coincide con el de la malla);
  - tarjetas en el celular (`matchMedia` como en la prueba de tablet, `:1135`);
  - el mes cerrado no se re-pide cada 5 minutos, pero sí al volver a la pestaña.
- **Estado de PRODUCCIÓN** (regla del gate de realidad): al menos una prueba con una fila heredada. Por ejemplo, las
  cooperativas de una analista de baja que llegan a nombre de ELIZABETH (el front solo pinta lo que trae el servidor) y
  una analista activa SIN ventas en el tramo (el roster la muestra con ceros).
- **Cifras idénticas:** una prueba que, con las mismas filas, compare los totales (por analista, por día, por equipo y
  del titular) de la malla nueva con los de `lib/facturacion.ts`.
- **e2e:** `app/e2e/facturacion-realidad.spec.ts` (6 casos) solo corre en Docker local. Adapta sus selectores a la
  pantalla nueva, pero NO lo ejecutes (no tienes Docker): lo corre Claude.
- Corre `npm run check` en `app/`: lint, typecheck, cobertura, build y duplicados. Si un worker de vitest se cae sin
  motivo, reintenta una vez y dilo.
