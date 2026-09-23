# Fusionar Metas/Ranking con la conversión oficial — encargo para otra sesión

**Escrito el 23/09/2026**, el mismo día que se unificaron las doce puertas.
Miguel quiere **fusionar las dos**. Esto es lo que hay que saber antes de empezar.

---

## El problema, en una frase

Hay **dos implementaciones de la misma fórmula de conversión**: la oficial, y otra
dentro de Metas. Hoy dan el mismo número —medido—, pero son dos textos que alguien
tiene que mantener iguales para siempre.

## Quién es quién

| | Función | Quién la ve |
|---|---|---|
| **Oficial** | `crm.conversion_mensual_fn(date)` → `crm.conversion_mensual_sin_cartera_fn` | El número grande, Ranking, Rendimiento, ficha del vendedor |
| **#8** | `crm.cumplimiento_metas_sin_cartera_fn(date)` | Nadie directamente: es el motor de #7 |
| **#7** | `crm.cumplimiento_metas_fn(date)` | **Metas y Ranking**, vía `objetivos.ts` |

🔑 **#7 HEREDA el payload de #8.** No es una llamada cualquiera: construye su
paquete sobre el de #8 y le añade `fuera_ranking`. Eso significa que **tocar #8 es
tocar Metas y Ranking**, aunque #8 no aparezca en ningún `grep` del front. El 23/09
eso costó **13 minutos de Metas y Ranking sin datos**. Antes de mover nada:
`supabase/scripts/conversion/quien-me-envuelve.sql`.

## Que hoy coincidan está MEDIDO, no supuesto

Con una deuda de anulación de 2 puntos plantada en producción (transacción que se
deshace sola), sobre el mes abierto:

```
                 SIN deuda   CON deuda
  oficial          6            4
  #7 metas         6            4
  #8 sin cartera   6            4
```

Las dos aplican `private.conversion_con_ajuste`, que hace
`greatest(num − pend, 0)` **POR VENDEDOR**, no sobre el total. Ese detalle importa
al fusionar: el orden en que se aplica el tope cambia el resultado cuando alguien
tiene más deuda que numerador.

---

## 🔴 LA DIFERENCIA QUE HAY QUE RESOLVER ANTES DE FUSIONAR

**La población no es la misma: la oficial trae 18 filas y Metas 17.**

Medido el 23/09. El que falta en Metas:

```
MIGUEL BRICEÑO · rol=vendedor, activo · divisor=0 numerador=1 · estado='solo_arrastre'
```

Es alguien que **no recibió leads este mes pero cerró algo de arrastre**. La oficial
lo incluye con `estado: 'solo_arrastre'`; Metas lo deja fuera, porque su población
sale del roster de metas publicadas, no de quien tuvo actividad.

**Esto no es un detalle técnico: es una decisión de negocio.** ¿Un analista que
cerró arrastre pero no recibió leads debe aparecer en Ranking? Si fusionas sin
decidirlo, **aparecerá una fila nueva en la pantalla de Miguel sin que nadie lo
haya pedido**. Pregúntaselo antes.

## Las formas, comparadas

Mismo nombre de clave no significa lo mismo. Medido:

**Primer nivel**

- **#7**: `version, periodo, revision, publicada_en, fuentes_reales, ponderacion_referido, cierre, vendedores, fuera_ranking` + las cuatro de la declaración (`es_mes_calendario, fuente, sellado, ajuste_aplicado`)
- **#8**: lo mismo **sin** `fuera_ranking`
- **Oficial**: `version, periodo, revision, generado_en, alcance, fuentes, ponderacion, cierre, responsables, total, cartera, cobertura`

**Por fila de vendedor**

| Solo en Metas | Solo en la oficial |
|---|---|
| `conversion_objetivo` · `conversion_real` · `convertidos` · `resueltos` · `detalles` · `nombre` · `supervisor_nombre` | `divisor` · `conversion_pct` · `cartera` · `cierres_de_arrastre` · `procedencia` · `referidos` · `estado` |

Comparten: `vendedor_id`, `supervisor_id`, `numerador`, `cierres_no_referidos`,
`cierres_referidos`, `ajuste`.

⚠️ **`conversion_real` (Metas) y `conversion_pct` (oficial) no son la misma clave.**
Compruébalo antes de mapear una en otra: Metas publica `convertidos`/`resueltos`,
la oficial publica `divisor`. Si son dos definiciones distintas del denominador,
fusionar cambia el número aunque hoy coincida.

## Las dos ramas de Metas

Metas tiene **dos caminos** y hay que fusionar los dos:

- **Mes SELLADO**: lee la foto de `crm.periodos_cerrados`. Declara `fuente: mensual`, `sellado: true`.
- **Mes ABIERTO**: calcula sobre `private.conversion_mensual_por_vendedor` y aplica el ajuste. Declara `fuente: rango_vivo`, `sellado: false`, `ajuste_aplicado: true`.

Si pasa a delegar, esa declaración tiene que cambiar a `mensual` en ambas. El
oráculo lo comprueba.

---

## Trampas que ya están pagadas — no las repitas

1. 🔴 **El front de Metas valida con `v.strictObject`.** `CumplimientoMetasSchema`
   en `app/src/lib/objetivos.ts`. Una clave nueva **tumba la pantalla entera**, no
   la degrada. Y un `strictObject` también falla por clave **que falta**: si la
   fusión quita `convertidos` o `resueltos`, se cae igual.
   **Regla: el front se publica ANTES que el servidor.**
2. **El gate de la oficial es MÁS ANCHO** (vendedor/supervisor/gerencia/lector) que
   el de Metas, así que delegar no abre ninguna puerta nueva — pero compruébalo,
   no lo des por hecho.
3. **Ni #7 ni #8 están en el censo** de `private.contadores_crudos_leads_citas()`,
   así que no hay huella que re-sellar. Verifícalo igual: el postflight debe exigir
   que sigan fuera.
4. **Acredita el cuerpo por identidad**, no por fragmentos: fija el md5 de
   `pg_get_functiondef` en el preflight.

## Cómo saber que no rompiste nada

1. `supabase/scripts/conversion/ensayo-cierre-unificacion.sql` — sella agosto de
   verdad, anula un cierre suyo y compara las cinco vías, todo con `rollback`.
   Los cinco caminos tienen que restar lo mismo.
2. `crm.alarma_conversion_fn()` → `cuadra: true`, 5 caminos.
3. El postflight de cada migración debe comparar el **payload entero** y exigir que
   ninguna cifra se mueva mientras no haya deuda.
4. `npm run check` y `npm run check:scripts`.

## El orden que yo seguiría

1. **Preguntar a Miguel lo de la fila 18** (el de `solo_arrastre`). Sin eso, no
   empieces: define si la fusión añade o no una fila a su pantalla.
2. **Mapear `conversion_real` ↔ `conversion_pct`** y `convertidos`/`resueltos` ↔
   `divisor`. Si no son equivalentes, eso es lo primero que hay que decidir.
3. **Publicar el front** que tolere la forma nueva (opcionales), y solo después el
   servidor.
4. **Fusionar por partes**: primero que Metas delegue la conversión y conserve lo
   suyo; fusionar del todo es el paso siguiente, no el primero.

## Lo que NO se toca sin hablarlo con Miguel

El peso del referido (0,15 y su porqué), cartera 1, oficina 0, la asimetría del
registro manual y la definición del divisor.

## La regla que más caro salió hoy

**Medir gana a leer.** El 23/09, leer el código me dio dos conclusiones falsas.
Plantar una deuda de 2 puntos en una transacción que se deshace las corrigió en un
minuto.
