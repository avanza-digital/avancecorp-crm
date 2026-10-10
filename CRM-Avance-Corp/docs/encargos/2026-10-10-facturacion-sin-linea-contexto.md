# Encargo a Codex (IMPLEMENTADOR) — Facturación: fuera la línea de contexto y la frase del tipo de cambio

ROLE: IMPLEMENTER delegado por Claude (PRIMARY).
- Escribes SOLO dentro de este worktree:
  `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop-worktrees/facturacion-sin-contexto-20261010`.
- Sin commit, red, Docker, dependencias nuevas ni otros agentes. En español.
- Al final, `npm run check` en VERDE en `app/`.

## Decisión de Miguel (10/10/2026), literal

Sobre la línea bajo las pastillas: «octubre de 2026 · S/ 2,118,800 + US$ 136,690 al tipo de cambio S/ 3.4401
(Superintendencia de Banca, Seguros y Pensiones, promedio de 7 días hábiles) · −32.4 % respecto del mismo tramo del mes
anterior · Mejor día: … · 8 días hábiles corridos — el domingo no cuenta», dijo: «todo este texto me parece pura mierda,
elimina eso».

Sobre «Los dólares se suman convertidos al tipo de cambio S/ 3.4401 (Superintendencia de Banca, Seguros y Pensiones,
promedio de 7 días hábiles).», dijo: «pura mierda».

## Lo que ya hizo el PRIMARY en `app/src/screens/facturacion.tsx` (no lo deshagas)

- Quitó el párrafo visible `<p className="facturacion-contexto …">` bajo las pastillas, con su botón del porcentaje.
- Quitó las variables `mejorCorto`, `promedioCorto` y `contextoResumen`, con su comentario.
- Quitó el párrafo «Los dólares se suman convertidos al …».
- Se CONSERVAN los `title` de las pastillas: `contextoTotal` (tramo, composición con tasa y comparación),
  `contextoMejor` y `contextoPromedio`. La lógica de la comparación, del tramo y de los días hábiles sigue calculándose
  y viviendo ahí.

## Lo que falta

1. **Código muerto:** si algo quedó sin uso tras quitar el párrafo (por ejemplo `delta`, `comparacionPendiente`,
   `comparacionFallida` o el `abrirNumero` en modo porcentaje), quítalo SOLO si de verdad no se usa. `npm run check`
   (oxlint y `tsc -b`) te lo dirá.
   - El modo `porcentaje` de `lista-operaciones.tsx` y `parametros-de-cifra.ts` deja de abrirse desde la pantalla. Si
     queda sin ningún llamador, retíralo con sus tests, para no dejar código muerto.
   - Si retirarlo complica, déjalo y explícalo.
   - Quita también la regla CSS `.facturacion-contexto` si existe y ya no se usa.
2. **Tests** (`src/screens/facturacion.test.tsx` y otros que fallen; hoy fallan 24): cada uno que verificaba LÓGICA a
   través de la línea visible se ADAPTA para verificar lo mismo en el `title` de la pastilla correspondiente:
   - comparación con el mes anterior, mismo tipo, mismo tramo, equipo elegido, monedas, mes cerrado o en curso y
     comparación pendiente o con error → «Facturado»;
   - mejor día → «Mejor día…»;
   - días hábiles, domingo y semana que cruza de mes → «Promedio por día hábil»;
   - rótulos que siguen al tramo y tasa sin siglas o en singular → el `title` de «Facturado».

   NO se debilita ninguna aserción de lógica. Los tests que solo probaban la UI retirada (el botón del porcentaje y sus
   separadores, «todas las cifras globales abren su lista, incluido el porcentaje» en lo tocante al %) se BORRAN o se
   reducen a lo que siga existiendo.
3. **Ningún test** puede exigir ya, en el texto visible, la frase «Los dólares se suman convertidos» ni la línea de
   contexto. Añade UN test que fije su AUSENCIA, para que no vuelvan.
4. **e2e** (`e2e/facturacion-realidad.spec.ts` y `e2e/facturacion-lista.spec.ts`): ajusta lo que dependiera de esos
   textos. No los puedes correr; lo hace el PRIMARY.

## Fuera de alcance

El rótulo de la fila «Total del día en soles», que también muestra el tipo de cambio largo: el PRIMARY lo está
preguntando a Miguel. NO lo toques.

Informe final breve: tests adaptados y borrados (con nombres), código muerto retirado y PASS/FAIL de `npm run check`.
