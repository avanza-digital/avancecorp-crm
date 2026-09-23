# Tres deudas de la conversión, para otra sesión

**Escrito el 23/09/2026**, justo después de unificar las doce puertas. Ninguna de
las tres es urgente: hoy la cifra es coherente en todas las pantallas. Las tres
son **trampas que solo se notan el día que alguien toque algo**.

Léelo entero antes de empezar. El orden de abajo es el que yo seguiría.

---

## Contexto en cinco líneas

La conversión pondera los cierres: un lead **no referido pesa 1**; un **referido
pesa 0,15 y no entra en el divisor**. El peso vive en `crm.conversion_pesos`
(columna `peso_referido`), versionado por `vigente_desde`, y lo lee
`private.peso_referido_conversion(date)`. La cifra oficial la sirve
`crm.conversion_mensual_fn`; desde el 23/09 las puertas que llegan a pantalla se
la piden a ella cuando el rango es un mes calendario completo y no hay filtro de
origen.

**Por qué 0,15** (decisión de Miguel, 10/08/2026, anotada en la propia tabla): la
primera versión ponía el referido **1 abajo y 0,15 arriba**, así que registrar
referidos **bajaba** la conversión del analista. El sistema castigaba justo lo que
se quiere premiar. Con la regla actual, recibir un referido es gratis y cerrarlo
solo puede sumar.

---

## 1. El peso de la RENOVACIÓN está atado al del referido

**El problema.** La renovación se pondera con el **mismo número** que el referido.
Si alguien cambia el peso del referido —una decisión comercial perfectamente
razonable— mueve el de la renovación sin querer y sin enterarse. Son dos conceptos
distintos compartiendo una sola palanca.

**Qué hay que hacer.** Separarlos: que la renovación tenga su propio peso,
versionado igual, y que cambiar uno no toque el otro.

**Cuidado con esto:**
- `crm.conversion_pesos` está versionada por `vigente_desde`, y **eso hay que
  conservarlo**: los meses pasados se calculan con el peso que tenían. Una columna
  nueva necesita un valor para las filas viejas que **reproduzca el comportamiento
  actual** (hoy la renovación = el peso del referido), o reescribirás el histórico.
- El núcleo `private.conversion_episodios` es el que aplica el factor. Está en el
  camino de TODAS las puertas: un error ahí se ve en todas partes a la vez.
- Antes de añadir una clave al payload, correr
  `supabase/scripts/conversion/quien-me-envuelve.sql` (ver deuda 3).

**Verificación mínima:** que la cifra de hoy **no se mueva ni un decimal** con los
pesos separados pero iguales. Después, cambiar solo el de renovación y comprobar
que el referido no se inmuta.

---

## 2. «Conversión por origen» pinta los referidos al 100 %

**El problema.** En Resumen de Gerencia, la tabla por origen muestra la conversión
de los referidos **sin ponderar**, mientras el número grande de arriba los pondera
a 0,15. Dos lecturas del mismo dato en la misma pantalla, sin nada que lo explique.
Está registrado como hallazgo **H13** en la auditoría de conversiones.

**Qué hay que hacer.** Que la pantalla no se contradiga. Hay tres caminos, de menos
a más coste, y la investigación del 23/09 los dejó medidos (ver la sección de
hallazgos al final, si está rellena):
1. **Rotular**: decir en la tabla que ahí los referidos van al 100 % y en el
   héroe al 0,15. Barato, honesto, no cambia ningún número.
2. **Mostrar el ponderado** en la tabla, para que cuadre con el héroe.
3. **Publicar ambos** y dejar elegir.

**Cuidado con esto:**
- 🔴 **Mira si el esquema del front es `v.object` o `v.strictObject`.** Una clave
  nueva en un `strictObject` **tumba la pantalla entera** — pasó el 23/09 y costó
  13 minutos de Metas y Ranking sin datos.
- Regla de la casa: si la clave viaja en la RESPUESTA, **el front se publica
  ANTES** que el servidor.

---

## 3. Metas y Ranking calculan la conversión por su cuenta

**El problema.** Hay **dos implementaciones de la misma fórmula**: la oficial, y
otra dentro de `crm.cumplimiento_metas_sin_cartera_fn` (de la que
`crm.cumplimiento_metas_fn` hereda su payload). Hoy dan el mismo número —medido el
23/09 plantando una deuda de 2 puntos: las dos bajan de 6 a 4—, pero son dos textos
que alguien tiene que mantener iguales **para siempre**. El día que se corrija un
redondeo o un caso borde en una y no en la otra, divergen.

**Qué hay que hacer.** Decidir entre tres:
1. **Dejarlo.** El oráculo (`crm.alarma_conversion_fn`) avisa si divergen — pero
   avisa DESPUÉS, no lo evita.
2. **Que deleguen solo la conversión** en `crm.conversion_mensual_fn`, como ya
   hacen las puertas #4, #5, #6 y #10, y conserven lo suyo (metas, cumplimiento,
   capital). Es lo que recomiendo si la investigación dice que se puede.
3. **Fusionarlas.** Más limpio y más caro.

**Cuidado con esto:**
- `private.conversion_con_ajuste` hace `greatest(num - pend, 0)` **POR VENDEDOR**,
  no sobre el total. El orden en que se aplica importa.
- El gate de la oficial es MÁS ANCHO (vendedor/supervisor/gerencia/lector) que el
  de estas puertas, así que delegar no abre ninguna puerta nueva. Pero
  compruébalo, no lo des por hecho.
- Estas dos puertas dicen hoy `fuente: rango_vivo` **con** `ajuste_aplicado: true`,
  y está bien: calculan por su cuenta pero sí restan la deuda. Si pasan a delegar,
  tendrán que decir `mensual`.

---

## Lo que NO se toca sin hablarlo con Miguel

- **El 0,15 en sí.** Es una decisión suya del 10/08 y tiene su motivo escrito.
- Los demás pesos: cartera 1, oficina 0.
- La asimetría del registro manual (regla CERRADA: no entra al divisor y sí
  cuenta entero arriba).
- El divisor: leads NO referidos que el asesor recibió en el mes, incluidos los
  descartados.

## Herramientas que ya existen y te ahorran el susto

| Para qué | Dónde |
|---|---|
| ¿Quién HEREDA el payload de esta función? (un `grep` no lo ve) | `supabase/scripts/conversion/quien-me-envuelve.sql` |
| ¿Sigue cuadrando todo tras el cambio? Sella un mes de verdad y lo deshace | `supabase/scripts/conversion/ensayo-cierre-unificacion.sql` |
| El vigilante de las cinco vías | `crm.alarma_conversion_fn()` — tiene que decir `cuadra: true` |
| Antes de dar por bueno un arreglo de pantalla | `npm run gate:realidad` |

## La regla que más caro sale olvidar

**Medir gana a leer.** El 23/09, leer el código me dio dos conclusiones falsas
(que Metas no descontaba, y que la puerta de multiempresa era urgente). Plantar
una deuda de 2 puntos en una transacción que se deshace sola las corrigió en un
minuto. La receta está en el ensayo de cierre.

---

## Hallazgos de la investigación del 23/09

_(pendiente de rellenar: se lanzaron tres investigadores en paralelo sobre estos
tres frentes y la sesión terminó antes de recoger sus informes. Si esta sección
sigue vacía, la investigación hay que rehacerla — no des por bueno nada que no
esté aquí con su archivo:línea.)_
