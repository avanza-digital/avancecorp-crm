# Fusionar Metas/Ranking con la conversión oficial — encargo

**Escrito el 23/09/2026**, el día que se unificaron las doce puertas. Miguel
quiere fusionar las dos. Esto es lo investigado; léelo entero antes de tocar nada.

---

## El problema, en una frase

La fórmula de conversión está **escrita dos veces**: la oficial, y otra copia
dentro de Metas. Hoy dan el mismo número, pero son dos textos que alguien tiene
que mantener iguales para siempre.

| | Función | Quién la ve |
|---|---|---|
| **Oficial** | `crm.conversion_mensual_fn` → `crm.conversion_mensual_sin_cartera_fn` | El número grande, Ranking, Rendimiento, ficha del vendedor |
| **#8** | `crm.cumplimiento_metas_sin_cartera_fn` | Nadie directamente: es el motor de #7 |
| **#7** | `crm.cumplimiento_metas_fn` | **Metas y Ranking**, vía `objetivos.ts` |

🔑 **#7 HEREDA el payload de #8.** Tocar #8 es tocar Metas y Ranking, aunque #8
no aparezca en ningún `grep` del front. El 23/09 eso costó **13 minutos de Metas
y Ranking sin datos**. Antes de mover nada:
`supabase/scripts/conversion/quien-me-envuelve.sql`.

## La fórmula sí es la misma, literalmente

Mismo núcleo, mismo factor, misma tabla de deuda, mismo clamp
(`greatest(num − deuda, 0)` **por vendedor, antes de dividir**) y mismo redondeo
a dos decimales. Que #8 llame al núcleo en modo global no cambia ningún número:
`conversion_episodios` filtra estrictamente por `analista_id`.

**Medido con deuda plantada** (2 puntos, transacción que se deshace): oficial, #7
y #8 bajan las tres de 6 a 4. El camino del ajuste funciona igual en las dos.

---

## 🔴 LO QUE HAY QUE DECIDIR ANTES DE EMPEZAR (no es técnico)

### 1. La población no es la misma: 18 contra 17

La oficial lista el **roster vivo**; Metas lista las **metas publicadas** de la
revisión más alta. Medido el 23/09 sobre septiembre: roster 18, metas 17.

El que falta en Metas: **MIGUEL BRICEÑO**, vendedor activo, `divisor=0`,
`numerador=1`, estado `solo_arrastre` — cerró arrastre sin recibir leads.

**¿Un analista que cerró arrastre pero no recibió leads debe salir en Ranking?**
Si se fusiona sin decidirlo, aparece una fila nueva en la pantalla sin que nadie
la haya pedido.

### 2. El coordinador perdería el acceso

**#8 deja pasar a cualquier `rol_crm`, incluido coordinador. La oficial lo
deniega a propósito.** Hoy hay **1 coordinador** en `crm.equipo`. Si Metas
delega, ese gate se re-evalúa dentro de la función y **no se puede esquivar**:
el coordinador dejaría de ver Metas.

¿Se le mantiene el acceso (ensanchando el allowlist de la oficial, que es
cambiar su contrato escrito) o se acepta que lo pierda?

### 3. El vendedor cuyo supervisor se cae

La oficial **borra** del payload a un vendedor cuyo supervisor deje de ser
supervisor activo (`roster_metas_vendedores` exige `rol_crm(supervisor)='supervisor'`).
#8 no lo borra nunca. Hoy hay **4 filas** de `crm.equipo` con `rol_crm='vendedor'`
cuyo rol efectivo no lo es.

Hoy la diferencia va en el sentido cómodo (roster ⊃ metas), así que un LEFT JOIN
funciona. En ese escenario devolvería NULL. **Es deducción de los dos cuerpos, no
medición** — nadie lo ha provocado.

---

## Las formas, comparadas (medido)

**Primer nivel**
- **#7**: `version, periodo, revision, publicada_en, fuentes_reales, ponderacion_referido, cierre, vendedores, fuera_ranking` + `es_mes_calendario, fuente, sellado, ajuste_aplicado`
- **#8**: lo mismo **sin** `fuera_ranking`
- **Oficial**: `version, periodo, revision, generado_en, alcance, fuentes, ponderacion, cierre, responsables, total, cartera, cobertura`

**Por fila**

| Solo en Metas | Solo en la oficial |
|---|---|
| `conversion_objetivo` · `conversion_real` · `convertidos` · `resueltos` · `detalles` · `nombre` · `supervisor_nombre` | `divisor` · `conversion_pct` · `cartera` · `cierres_de_arrastre` · `procedencia` · `referidos` · `estado` |

Comparten `vendedor_id`, `supervisor_id`, `numerador`, `cierres_no_referidos`,
`cierres_referidos`, `ajuste`.

**El mapeo que funciona** (7 claves): `divisor`→`resueltos`, `numerador`→igual,
`conversion_pct`→`conversion_real`, `cierres_no_referidos`→igual,
`cierres_referidos`→igual, `ajuste.pendiente`→igual,
`cierres_no_referidos + cierres_referidos`→`convertidos`.

---

## 🔴 LA TRAMPA QUE TUMBA LA PANTALLA

El front valida #7 con **`v.strictObject`**, que falla **por clave de más Y por
clave de menos**.

**`ajuste.origenes` NO está declarado en `AjusteVendedorSchema`.** Si el LEFT
JOIN arrastra el objeto `ajuste` entero de la oficial, Metas y Ranking se caen
como el 23/09.

👉 **Copia clave a clave. Nunca hagas `||` del objeto.**

Lo que sí cabe sin tocar el front: `mensual_comparada` y `paridad_mensual`, ya
declaradas como opcionales (`objetivos.ts:355-356`), igual que las cuatro de la
declaración.

---

## Las tres opciones

### A. No delegar, y vigilar
Un test que compare vendedor a vendedor #8 contra la oficial y falle si alguien
que está en las dos poblaciones difiere.
**Coste:** un fichero de prueba, nada en producción.
**Lo que NO cubre:** la diferencia de población. Dos funciones pueden coincidir
en cada vendedor compartido y seguir enseñando listas distintas — que es
exactamente lo que pasa hoy.

### B. Delegar solo la conversión ← **la recomendada**
#8 llama a `crm.conversion_mensual_sin_cartera_fn` (no a la #4: esa ya hace la
cartera que #7 vuelve a hacer) y hace LEFT JOIN de `crm.metas_vendedor` contra
sus `responsables`, tomando las 7 claves del mapeo. Metas, objetivo, nombres,
detalles, producción, cartera y `fuera_ranking` se quedan donde están.
**Coste:** una migración sobre el cuerpo de #8, rama de mes abierto (la rama
sellada ya lee la misma foto). Las dos son SECURITY DEFINER de postgres, así que
#8 puede llamarla aunque su ACL sea solo postgres — es como la llama hoy la
oficial.
**Bloqueado por:** las decisiones 2 y 3 de arriba.

### C. Unificar también la población
Que Metas liste lo mismo que la oficial.
**Coste:** el más caro, y cambia **lo que la pantalla ES**: de «los que tienen
meta pactada» a «los que trabajan».
**Rompe:** `CumplimientoVendedorSchema` exige `conversion_objetivo` **no
nullable** y `nombre`/`supervisor_nombre` como texto no vacío. Una fila sin meta
revienta la validación. Exige tocar el front primero. Y rompe el ranking de
capital, que asume una meta por fila.

---

## Dos escenarios latentes que hoy no se notan

1. **Al sellar el primer mes**, #8 enseñará `ajuste.pendiente = 0` a todo vendedor
   con deuda y sin actividad, mientras la oficial enseñará su deuda real. El
   numerador seguirá coincidiendo; el número del ajuste no. (#8 une la deuda
   dentro del CTE de conversión, donde solo hay fila si hubo episodios; la
   oficial la une contra la fila del roster.)
2. **La rama sellada de #8 nunca se ha ejercido** (0 periodos cerrados). Al
   sellar, su población deja de ser «las metas» y pasa a ser «la foto visible»,
   que incluye supervisores con cartera propia. Es un cambio de significado de la
   misma pantalla.

## Cómo saber que no rompiste nada

1. `supabase/scripts/conversion/ensayo-cierre-unificacion.sql` — sella agosto de
   verdad, anula un cierre suyo, compara las cinco vías, y lo deshace.
2. `crm.alarma_conversion_fn()` → `cuadra: true`, 5 caminos.
3. Postflight que compare el **payload entero** y exija que ninguna cifra se mueva.
4. `npm run check` y `npm run check:scripts`.

## Orden recomendado

1. Resolver con Miguel las tres decisiones de negocio (fila 18, coordinador,
   supervisor caído).
2. Publicar el front que tolere la forma nueva. **Siempre antes que el servidor.**
3. Opción B. La C, si acaso, después y por separado.

## Lo que NO se toca sin hablarlo con Miguel

El peso del referido (0,15, decidido el 10/08 y con su motivo escrito), cartera 1,
oficina 0, la asimetría del registro manual y la definición del divisor.

## Lo que no se pudo verificar

El investigador no pudo ejecutar `cumplimiento_metas_fn` ni `conversion_mensual_fn`
como usuario concreto (bajo `db query --linked`, `auth.uid()` es NULL y las dos
lanzan 42501). Las poblaciones y los insumos sí los midió de forma independiente;
la coincidencia de las cifras la medí yo aparte, con identidad prestada.
