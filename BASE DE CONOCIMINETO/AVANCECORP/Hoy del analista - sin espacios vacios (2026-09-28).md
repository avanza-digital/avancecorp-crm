---
tags: [crm, hoy, analista, ux, pantalla]
fecha: 2026-09-28
estado: publicado 28/09/2026 (tres releases)
---

# Hoy del analista — sin espacios vacíos (2026-09-28)

Miguel pidió el 28/09: «eliminar los espacios negativos del módulo Hoy de analista».
Cambio SOLO de presentación en `CRM-Avance-Corp/app/src/screens/hoy/vendedor.tsx`
(pantalla «Hoy» del rol analista/`vendedor`). Sin migraciones, sin consultas nuevas,
sin cambiar textos.

## De dónde salían los huecos

| Hueco | Causa | Arreglo |
|---|---|---|
| Tarjetas «Prioridad 01–03» con aire entre el capital y los botones | `min-h-52` (208 px) con contenido de ~150 px | sin altura mínima; los botones siguen alineados abajo con `mt-auto` |
| «Después en tu agenda» vacía ocupaba 273 px | estado vacío centrado con `py-10` | estado vacío en HORIZONTAL (icono a la izquierda, texto a la derecha): 147 px |
| «Después: mantén el ritmo» con 1 fila medía 273 px | el `grid lg:grid-cols-5` estiraba las dos tarjetas a la misma altura | `lg:items-start`: cada tarjeta mide lo que su contenido |
| Franja «Ahora» | `py-5` y `mt-5`; estados vacío/error centrados con `min-h-40` (160 px) | `py-4`, `mt-4`; vacío y error en HORIZONTAL: 70 px y 66 px (móvil 178/138); el enlace «Revisar Agenda» baja a su línea bajo `sm` (`basis-full sm:basis-auto`), si no aplasta el texto |
| Pie «Día con espacio…» | centrado con `pt-6` | a la izquierda, `pt-2` |

Medidas en el demo a 1512×805: franja «Ahora» 420 → 385 px; tarjetas de prioridad 208 → 185 px;
agenda vacía 273 → 147 px; cola con una fila 273 → 151 px. En móvil (390 px) no hay desbordes.

## Nombres de las tarjetas (Miguel, 28/09)

- «Después en tu agenda» → **«Tu agenda de hoy»** (el mismo nombre que ya lleva en producción, modo activo).
- «Después: mantén el ritmo» → **«Pendientes»** (los viernes p. m., «Pendientes: viernes de higiene»). Son eso:
  los leads de la cola de acción que no entraron en las tres prioridades de «Ahora» (sin responder,
  seguimiento, sin actividad), más los sin próxima acción y, los viernes, las tareas de higiene.
- Las dos tarjetas solo existen en el modo LEGADO (el demo). En producción el seguimiento corre en modo
  ACTIVO desde el 07/09 (comprobado en `crm.sla_operacion_control` el 28/09): el analista ve «Tu agenda de
  hoy» a todo el ancho y sus pendientes viven en el módulo «Seguimiento».

## El patrón que queda

`VacioCompacto` (local a la pantalla): franja `flex items-center gap-3 rounded-lg bg-muted/40 px-3 py-3`,
icono opcional con `aria-hidden`, título `text-sm font-bold`, detalle `text-xs text-muted-foreground`
y una línea extra opcional. Lo usan «Sin citas para hoy» y los tres estados de la cola
(cargando/error, «Lo pendiente está en tu agenda», «Al día ✦ sin pendientes»). Va en la línea
de [[Gestion Diaria - diseno VitaNova con colores del CRM, analisis y plan (2026-09-27)]]:
horizontal, sin apilar, sin cajas centradas con aire arriba y abajo.

## Dos modos, una pantalla

Producción corre el seguimiento en modo ACTIVO: el analista ve cabecera + «Tu agenda de hoy» a
todo el ancho + «Tu cartera en contexto» + «Tu cumplimiento del mes». El demo corre en modo
LEGADO: franja «Ahora» + agenda y cola en dos columnas. Los huecos grandes estaban en el modo
legado (demo); en el activo solo cambian el pie «Día con espacio…» y el vacío de la agenda.
Ver [[Hoy del supervisor - puesto de mando en una pantalla, plan (2026-09-27)]] (mismo hallazgo
del modo activo) y [[Hoy Analista - seguimiento solo en su modulo 2026-09-07]].

## Verificación (28/09, todo PASS)

- oxlint limpio · `tsc -b` OK · `vendedor.test.tsx` 41/41 · `npm run check` completo (exit 0).
- E2E en Docker AISLADO (contenedor/volumen propios, ya retirados): `demo-roles.spec.ts` 9/9 y
  `sla-operacion.spec.ts` 15/15 → 24/24, sin flaky.
- revisor-a11y: PASS. Dos P3 aplicados: detalle del vacío con `--muted-foreground-strong` (7,2:1 en vez de
  4,55:1) y `aria-busy` + `role="status"` en la carga/error de la cola. Un P2 PREEXISTENTE fuera del diff,
  anotado como tarea aparte: en `FilaAgenda` un Enter sobre el botón «Cerrar tarea» burbujea al
  `div[role="button"]` de la fila y abre la ficha en vez de cerrar (falta el guard `e.target !== e.currentTarget`
  que sí tienen `FilaHigiene` y `FilaAmarillo`); no hay test de teclado en `vendedor.test.tsx`.
- Codex (refutación, `scripts/codex-review-mcp`, 197 s): CHANGES_REQUESTED por un P2 real: el vacío de «Ahora»
  con `py-5` crecía de 160 a ~194 px. Aceptado y resuelto poniéndolo en horizontal (medido: 70 px). Resto: sin
  regresiones (textos, ternarios, `exactOptionalPropertyTypes`, `lg:items-start` no rompe `flex-1`/`mt-auto`).

## Publicación (28/09, `/release-crm` por Miguel)

- Commits en `main` local: `97d7609d` (pantalla + pruebas), `056f517a` (vault), merge de la PR #122 en `e486a139`.
- Artefacto `crm-20260928T191253Z-e486a139d5c4` (SHA-256 `f222caed…`), `--allow-dirty` con suciedad ajena fuera de
  `app/` registrada en el manifiesto. Preflight OK contra el vivo `build-20260928T182709910Z`/`43b3d6d0`.
- Humo: `version.json` = `build-20260928T191252679Z` a la primera, raíz 200, `index-BZvXJKOn.js` con SHA-256 idéntico
  local↔vivo, ZIP 404. Sin purga de caché.
- 🔴 El MCP de Hostinger cambió de contrato (2.3.0): ver [[Deploy a Hostinger]] («MCP 2.x: search/execute»).

## Segunda publicación (28/09, 14:45): la vista de PRODUCCIÓN

Miguel vio producción «igual»: la captura de antes era el DEMO (modo legado). En producción (modo activo) los
huecos eran otros: filas de agenda a todo el ancho con el texto en dos líneas y la cartera debajo, con medio
monitor vacío. Arreglo (`3c481f7f`): **agenda (3/5) y «Tu cartera en contexto» (2/5, cifras en 2×2) en dos
columnas** y **cada fila de agenda en una sola línea** desde `sm` (título · tipo · capital a la derecha; 58 px en
vez de ~90). El legado conserva su franja de cuatro cifras. Publicado: build `build-20260928T194323329Z`,
artefacto `crm-20260928T194324Z-3c481f7f1a4f`, check 4763 PASS, humo PASS (chunk de Hoy idéntico local↔vivo).
Lección: **antes de arreglar una pantalla, mirar la vista que corre en producción, no el demo**; el modo activo
se fuerza un momento en local con `useModoSla()` y se revierte.

## Tercera publicación (28/09, 15:20): «Tus citas» y URL limpia

Miguel, al ver las dos columnas: «eso de tu cartera en contexto bórralo, y pon un componente que sea mejor de solo
citas del analista, lo veo más útil; tu agenda de hoy que siga igual». Y aparte: «acomoda las URL del CRM, está mal
que se vea eso de version build». Hecho con dos agentes en paralelo (archivos disjuntos) y una sola release:

- **«Tus citas»** (`CitasAnalista`, en `vendedor.tsx`) sustituye a «Tu cartera en contexto» junto a «Tu agenda de
  hoy»: TODAS las citas pendientes del analista (tareas `reunion` de sus leads y de los clientes de su cartera), no
  solo las de hoy; vencidas primero y luego Hoy · Mañana · Próximas; modalidad (presencial/virtual), capital en juego,
  cerrar tarea y abrir ficha; máximo 8 y «+N más — en Agenda». Reutiliza `FilaAgenda`, que gana `modalidad`, una
  descripción accesible y el guard de teclado que le faltaba (Enter sobre «Cerrar tarea» ya no abre la ficha: deuda
  cerrada). Una cita de hoy se ve en las dos tarjetas, por diseño. Se retiraron `PulsoCartera` y sus cifras.
- **URL limpia**: la recarga por versión nueva añade `?crm_version=build-…` para saltarse la caché de `index.html`
  y se quedaba pegada. `limpiarMarcaDeVersion()` en `main.tsx`, antes del router, la retira con `replaceState`
  conservando la ruta hash y el resto de parámetros (`urlSinMarcaDeVersion`, pura, con pruebas).

Commits `3c68b0c5` y `553a447e`; build `build-20260928T201735530Z`, artefacto `crm-20260928T201736Z-553a447e8f53`;
check 4777 PASS; humo PASS (chunk de Hoy con «Tus citas» y sin «cartera en contexto»; el bundle ya limpia la URL).
El vivo previo (`5ccb30ac`, «canales concretos», de otra sesión, PR #126) quedó contenido. PR de integración **#127**.
Deuda que sigue: contraste ≈2,8:1 del `Badge` ámbar suave (compartido, `badge.tsx`) y `role="list"` en las filas.

Tarea aparte (CERRADA en esta release): el P2 de teclado en `FilaAgenda`. PR #124 FUSIONADA (squash `02242e02`, traída al local en
`865ced05`); el segundo commit fue la PR **#125** (fusionada, traída al local) (sin lo de Gloria; al fusionarla,
traer `avancecorp/main` al local). Las PR #122 y #123 ya están fusionadas en el `main` local (`e486a139`, `4a6e6609`).
