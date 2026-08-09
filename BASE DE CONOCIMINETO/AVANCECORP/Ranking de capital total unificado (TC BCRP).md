# Ranking de capital total unificado (TC BCRP)

**Pedido de Miguel (2026-08-09, tras el deploy de F1b):** «el ranking debe ser de
conversión y monto total; el tipo de cambio para estos montos en dólares el
servidor puede buscar la info y cerrarlo; OJO solo para el apartado de ranking
me interesa que salga el total unificado más el desglose como ya lo tenemos
ahora de soles y dólares».

## Qué cambió (solo front — sin migración, sin edges nuevas)

El panel **«Ranking general de vendedores»** (hoy/gerencia, sección
`ranking-vendedores`) pasó de 3 tabs (Conversión · Capital PEN · Capital USD) a
**2 tabs: Conversión general · Capital total**. El tab de capital rankea por
avance contra la meta con el **total en soles**: capital PEN + capital USD
**convertido** al TC que resuelve el servidor, con el desglose por moneda
debajo de cada total y el TC rotulado en el sub-encabezado
(`TC S/ 3.3965 (SBS · prom. 7d)`).

- Los tabs por moneda estaban degenerados: desde
  [[Configuración operativa CRM 2026-08-07]] las metas están normalizadas a
  **una sola meta mensual en soles**, así que «Capital USD» rankeaba contra
  meta 0 (todos «Sin meta»).
- Es el mismo precedente de [[Pasada de UX del CRM 2026-07-17]]: «el capital en
  USD cuenta a la meta convertido a soles… es conversión, no rompe la regla
  PEN≠USD». La regla dura sigue: **jamás una suma ciega ni una tasa inventada**.
- La meta también se unifica (`objetivo PEN + objetivo USD convertido`) para
  las metas legadas con componente USD.

## Piezas

- `lib/conversion-vendedores.ts` → `clasificarRankingCapitalTotal(vendedores,
  metas, cumplimientos, tc)`: valida el TC (finito y > 0), clasifica
  comparable / sin_meta / indisponible, ordena avance desc → total desc →
  nombre, y conserva el **split crudo** (`capitalPen/Usd`, `metaPen/Usd`) para
  que la UI rotule. Reemplazó a `clasificarRankingCapital` (por moneda,
  retirada sin dolientes).
- `lib/tipo-cambio.ts` → `useTipoCambio(habilitado)` reconectado (estaba
  huérfano desde `b03f6d5`). Ahora con **tri-estado**: `undefined` =
  consultando (el tab muestra carga — nunca afirma «no disponible» con el
  fetch en vuelo ni deja que el ranking salte al llegar el TC), `null` = no
  disponible, objeto = listo. Devuelve `{ tc, recargar }`; `recargar` va
  cableado al Reintentar del panel (un blip del BCRP ya no deja la sesión
  degradada sin salida). El TC lo sigue resolviendo el **servidor**: edge
  `crm-tipo-cambio` → BCRP series SBS compra/venta, punto medio, promedio 7
  días hábiles, caché 1 h.
- `screens/hoy/gerencia.tsx` llama `useTipoCambio(seccion ===
  'ranking-vendedores')`: las otras 6 vistas de gerencia **no** disparan la
  edge (App remonta la pantalla en cada cambio de vista — hallazgo MEDIO de la
  verificación).

## Fail-closed (sin TC)

Total y meta degradan a **solo-PEN**; el US$ se muestra **aparte** y en navy
(no muted — a11y: es el aviso que evita leer el total como si incluyera los
dólares): `+ US$ 16,000 aparte (sin TC)` en capital Y en meta. Una meta 100%
US$ sin TC se rotula **«Meta en US$ · sin TC»**, no el falso «Sin meta». El
rótulo del TC del sub-encabezado sale del MISMO `tc` que aplicó la lib
(`ranking.tc`), nunca del prop crudo: no se puede anunciar un TC que no entró
al total.

## Alcance y verificación

- **Solo el apartado de ranking** (pedido explícito): las demás superficies de
  dinero (KPIs, cumplimiento, pipeline, cartera, equipo) siguen PEN/USD
  separados sin conversión.
- Verificación ultracode 2026-08-09: 4 lentes adversariales con refutación
  (19 agentes) + revisor-a11y → 13 hallazgos confirmados, **12 corregidos**
  (los 2 MEDIO incluidos) y 1 aceptado: el panel no tiene cobertura e2e (hueco
  PRE-existente; la cobertura unitaria quedó completa: lib 3 casos nuevos +
  panel 4 escenarios + hook 7). Gates: `npm run check` exit 0 · e2e gerencia
  8/8.
- Nota a11y pendiente (pre-existente, anotada por el revisor): el tablist no
  implementa roving tabindex/flechas del patrón APG — operable por teclado
  igual; si se vuelve a tocar ese tablist, resolverlo.

## Segunda pasada: Codex como revisor independiente (post-deploy)

Pedido de Miguel («recuerda hacer que codex nos ayude»). Codex revisó el
commit `143084d` con la instrucción de NO repetir los 13 hallazgos ya triados.
Devolvió **4 nuevos (0 ALTA, 2 MEDIA, 2 BAJA) — los 4 corregidos**, y validó
que `useTipoCambio` no tiene carreras (la limpieza descarta respuestas
obsoletas al reintentar/desmontar/cambiar `habilitado`):

1. **MEDIA — edge `crm-tipo-cambio`**: la unión compra∪venta hereda el orden
   de inserción (un período que solo trae venta quedaba appendeado al final) y
   `slice(-7)` podía promediar un día viejo excluyendo uno reciente; además el
   rótulo decía `prom. 7d` aunque hubiera menos datos. Fix: orden cronológico
   explícito (`clavePeriodo` sobre "DD.MMM.YY") antes de recortar + rótulo con
   el conteo REAL (`SBS · prom. ${n}d`). **Edge v4 EN PROD** (deriva verificada
   ANTES byte a byte: la v3 remota era idéntica al HEAD commiteado; smoke: 401
   sin sesión desde nuestro código, OPTIONS 200, contenido remoto v4 = local).
2. **MEDIA — sin vía de recuperación para un fallo AISLADO del TC**:
   `ErrorRanking` solo aparece si fallan las conversiones. Fix: aviso amber con
   botón «Reintentar tipo de cambio» dentro del tab cuando `tc === null`.
3. **BAJA — cumplimiento con `detalles: []`** clasificaba comparable con
   «S/ 0 · 0%». Fix: guarda local → indisponible (la frontera RPC ya lo
   impedía; ahora el clasificador no depende de eso).
4. **BAJA — el pie de gerencia** decía «PEN y USD se muestran por separado»
   también en el Ranking, contradiciendo el total unificado. Fix: pie propio
   para la sección ranking.

⚠️ Los fixes de FRONT (2–4) están commiteados pero entran a prod recién con el
próximo `/release-crm`; el de la EDGE (1) ya está vivo (server-side, sin
dependencia del bundle: la respuesta conserva su shape).

Ver también [[Plan de escalabilidad del CRM a data gigante]] (los % del
ranking de equipo vienen de `metricas_vendedores_fn` — ese ranking NO se tocó)
y [[Deploy a Hostinger]].
