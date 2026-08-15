---
tags: [feature, crm, cierre-mes, decision]
actualizado: 2026-08-15
---

# Cierre de mes

**Estado: 🟡 escrito, auditado y verde en banco local (17/17), SIN aplicar a producción.**
Seis migraciones `20260815*` en `CRM-Avance-Corp/supabase/migrations/`. Ni un objeto de
producción tocado todavía.

Sella el resultado de un mes para que deje de moverse. Es la pieza que faltaba desde que
existe [[Conversion mensual - definicion cerrada]]: el CRM **no guardaba** el resultado de un
mes, lo recalculaba en cada consulta.

## El problema, medido

El 14/08 se midió: **el agosto de un vendedor pasó de 38,33 % a 5,00 % en dos horas** por una
anulación de gerencia. Esa la decidió Miguel. Las que preocupan son las que no decide nadie:

- el total de empresa se calcula sobre quien está en el equipo **hoy**, así que una baja en
  octubre cambiaría agosto;
- las metas se pueden **republicar** sobre un mes pasado (agosto ya lleva 7 revisiones) y el
  cumplimiento se recalcula contra las nuevas;
- la anulación es retroactiva y de una sola dirección.

Mientras nadie cobre por esos números da igual. En cuanto deciden un pago, es un problema
contable.

## Las decisiones de Miguel

| Pregunta | Su respuesta | Fecha |
|---|---|---|
| ¿Cuándo se cierra un mes? | El **día 10** del siguiente. Del 1 al 10, ventana de ajuste. | 14/08 |
| ¿Quién lo cierra? | **Solo**. Automático. | 14/08 |
| ¿Qué se sella? | **Todo lo que decide pago**, no solo la conversión. | 14/08 |
| ¿Un mes cerrado se puede corregir? | **Nunca se reescribe.** Lo que haya que corregir se descuenta del mes vivo, como una planilla. | 14/08 |
| ¿Y si el descuento no cabe en el mes? | **Se arrastra** hasta saldarse. | 14/08 |
| ¿La deuda caduca? | **No por tiempo. Desaparece al saldarse.** | 15/08 |
| ¿Se puede cerrar antes del día 10? | **No.** Ni gerencia. | 15/08 |
| ¿Y cerrar *tarde*? | **Sí** — el candado es un suelo, no una fecha exacta. | 15/08 |
| ¿El sistema calcula comisiones? | **No.** Eso será otro apartado el día que exista. Aquí solo se muestra bien lo que lleva el asesor en capital y conversión. | 15/08 |
| Un cierre que llega tarde a un mes ya sellado | **No se construye.** No ha pasado nunca; se maneja de forma interna. | 15/08 |

## El candado del día 10 — por qué existe

Las guardias originales decían **quién** y **qué**, y ninguna decía **cuándo**. Con el momento
de cerrar libre, quien cierra elige **de qué mes sale el dinero** de una corrección:

- si el mes está **abierto**, anular recalcula ese mes ahí mismo;
- si está **cerrado**, nace una deuda que se descuenta del **mes vivo**.

Es la misma segunda puerta que cierra [[Conversion mensual - definicion cerrada]], abierta
desde el otro lado. Y además, cerrar el día 2 se comería la ventana de ajuste.

## Cómo funciona ahora

Un ciclo corre **todos los días** a las 09:20 de Lima (cron `crm-cierre-mes-diario`, justo
detrás del ciclo de contratos) y cierra los meses que ya deben cierre y cuya ventana abrió,
**del más antiguo al más nuevo**. Correr a diario —y no «el día 10»— es lo que lo hace
auto-reparable: si el 10 falla, el 11 cierra igual y el mes no queda atascado.

Y el servidor publica el estado (`crm.cierre_mes_estado_fn`) para dos cosas: el aviso del 1 al
10 («julio se cierra el 10/08, quedan 3 días») y la **alarma** de que el ciclo se atascó
(`vencido: true`). Sin esa alarma, un cron roto es invisible: nadie mira los logs.

## Lo que hay que saber antes de tocarlo

⚠️ **Un fallo de dinero que las pruebas no vieron.** La primera versión marcaba el descuento
de capital como saldado y **no lo restaba de ninguna cifra**: el asesor cobraba igual y la
deuda desaparecía. Lo cazó un análisis adversario, no el oráculo. Corregido, y el bloque 6bis
del oráculo existe para que no vuelva. Lección: se probó el camino de la conversión y se dio
por bueno el del capital sin tocarlo.

⚠️ **Dos calcos del banco local mentían** y con ellos el oráculo bendecía cosas falsas. Es
[[Ejecutar contra la forma real]] otra vez, del lado del calco.

⚠️ **Lo que encontró la auditoría del 15/08, y que yo no vi.** Tres fallos de razonamiento,
no despistes — los tres nacen de mirar una pieza sin mirar con qué convive:

1. **La puerta lateral de las metas retroactivas.** El candado del día 10 cerraba el *cuándo*,
   pero «mes que debe un cierre» se definía solo como «tiene metas publicadas» — y las metas se
   pueden publicar sobre **cualquier** mes. Publicar hoy las metas de un mes viejo lo convertía
   en pendiente con la ventana abierta hace meses, y **el cron lo sellaba solo**, por detrás de
   meses ya pagados. Nadie tenía que apretar nada. Cerrado por los dos lados.
2. **La carrera entre cerrar y anular, que pierde dinero en silencio.** Si una anulación
   arranca mientras el cierre está a medias, ve el mes todavía abierto, decide que no hay deuda
   — y la foto ya contó ese cierre. Un cierre anulado que queda pagado para siempre. Era
   teórica; el ciclo automático la convierte en una **cita fija, mensual y a hora conocida**.
   Cerrado con un cerrojo que toman las dos puertas.
3. **El ciclo no paraba: retrocedía.** Si un mes fallaba, se perdía también el sellado del
   anterior, que había ido bien. Y como esos fallos son deterministas, el sistema se habría
   quedado atascado para siempre rehaciendo y descartando el mismo trabajo bueno cada día.

⚠️ **Una prueba que solo puede correr ciertos días no prueba nada.** La ventana del mes
pasado solo está cerrada del 1 al 9, así que la rama que importa —la que **rechaza**— no se
ejercita el resto del mes. Se resolvió separando la aritmética (probada exhaustivamente, sin
reloj) del reloj, y empujando la ventana al futuro dentro de la propia prueba. Comprobado con
**mutantes**: neutralizar el candado, o quitarle el freno al ciclo, pone el oráculo en rojo.

**Quién ve el aviso.** Vendedor, supervisor, gerencia y directorio (este último por la vía del
«lector global»). **El coordinador NO** — mismo criterio que la conversión: el coordinador
reparte la cola de leads, no mira cifras de pago. Ver [[Acceso y roles del CRM]].

🔴 **Dos nombres que se parecen demasiado.** `crm.cierres_estado_fn` (existente, en producción)
es de los **cierres de venta** — es la que pinta el chip «CIERRE ANULADO» en la cartera, y en el
front vive en `app/src/lib/cierre-estado.ts`. `crm.cierre_mes_estado_fn` (nueva) es del **cierre
de mes**. Cuando la Fase 2 toque el front, su módulo NO debe llamarse `cierre-estado`: los
nombres parecidos en un esquema en español ya costaron un despliegue una vez.

## Qué pasará al aplicarlo

Comprobado contra producción el 15/08, no supuesto: el único mes con metas publicadas es
**agosto 2026**, que es el mes en curso, y el ledger arranca el 05/08. Así que **al aplicar
esto no se cierra nada de golpe**. El primer cierre real será el de agosto, el 10 de
septiembre, y nacerá marcado `mes_parcial` porque el ledger empieza a mitad de mes.

Miguel avisó de que **no van a pagar comisiones con esto hasta que el sistema esté operando**,
así que el 10 de septiembre no es una fecha comprometida con nadie.

## Falta

- **Bloque nuevo en `test-rls.mjs`** — el único trabajo de servidor que queda, y necesita una
  base que no sea producción (hoy no hay branch). Las tres tablas nuevas (`periodos_cerrados`,
  `cierre_mes_vendedor`, `ajustes_mes_cerrado`) son deny-by-default y hay que probarlo por rol,
  con sesiones reales; y el ámbito del supervisor al leer un mes cerrado (que salga del
  `supervisor_id` **sellado**, no del equipo de hoy) tampoco está probado en ningún sitio.
- **Defensa en profundidad, migración aparte**: que `crm.publicar_metas_vendedores` rechace
  publicar metas de un mes por debajo del último sellado. Hoy el daño ya está bloqueado en las
  dos puertas del cierre; esto lo cortaría en el origen.
- Ciclo branch → gate → advisors → merge.
- **Fase 2, el front**: leer `cierre` y `ajuste` en el payload, y `cierre_mes_estado_fn` para
  el aviso y la alarma.

Ver [[Conversion mensual - definicion cerrada]] · [[Anulación de cierres de Avance]] ·
[[Como se mide la conversion del asesor]] · [[Inicio]]
