---
tags: [crm, hoy, analista, ux, pantalla]
fecha: 2026-09-28
estado: en local, sin publicar
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

Pendiente: Miguel lo mira en local (`npm run dev` en `app/`, demo como Analista) y publica con
`/release-crm`; luego se fusiona a `main` y va a GitHub por PR de integración. Tarea aparte: el P2 de
teclado en `FilaAgenda`.
