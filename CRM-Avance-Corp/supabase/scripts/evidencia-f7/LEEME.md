# Evidencia de accesos de la F7 — el requisito D+7 / D+14

El vigía diario prueba que **la puerta sigue cerrada**. Esto prueba otra cosa distinta:
**si alguien intentó abrirla**. Y ni siquiera eso del todo — lee primero
«[Lo que este método NO ve](#-lo-que-este-método-no-ve-la-limitación-que-manda)».
Hacen falta **las dos patas** —esta evidencia **y** el censo estructural de la
migración— antes de derribar una pieza.

```bash
npm run evidencia:f7                # cosecha los últimos 7 días y guarda un acta
npm run evidencia:f7 -- --resumen   # informativo: qué tramos hay y dónde hay huecos
npm run evidencia:f7 -- --gate      # EL FRENO: sale != 0 si una pieza que ya toca
                                    # demoler no tiene su ventana cubierta y limpia
```

Cada corrida deja un acta `<sello>.json` en esta carpeta. **Son append-only**: una
cosecha nunca reescribe otra, porque el conjunto de actas es la evidencia — se cosen
lecturas de días distintos para tapar los 14 días que la retención no deja ver de una vez.

---

## 🔴 La regla que manda

**«No aparece nada» NO es «nadie lo usó».** Solo vale como
**«sin evidencia de uso en la ventana [X, Y]»**. Por eso el gate **falla cerrado**: ante
un hueco, un truncamiento o una denegación sin explicar, dice **NO**.

---

## 🔴🔴 Lo que este método NO ve — la limitación que manda

**Solo ve al que FRACASA.** Una llamada con **éxito** no deja un `ERROR` en
`postgres_logs`, y si no entra por PostgREST tampoco aparece en `edge_logs`. Medido en
producción el 04/09: las 11 piezas son `SECURITY DEFINER`, y el servidor tiene
`track_functions = none` y `pgaudit.log = none`. **Consecuencia:** una llamada exitosa de
`postgres` / el dueño / `cli_login_postgres` por conexión directa es **invisible aquí**.

⇒ Esta acta **no basta sola**. La prueba fuerte de que nada la usa es el **censo
estructural** —quién NOMBRA la pieza en el cuerpo de otra función, en un trigger, una
vista, `pg_depend`, `cron.job`, el front, el portal, las Edge Functions— que vive en la
migración de demolición y que Codex volvió a correr entero el 04/09 dando **vacío**.
Este guion es la **segunda** pata: mide los intentos fallidos, que el censo no ve.

---

## 🔴 Lo que se midió montando y endureciendo esto (04/09/2026)

Seis trampas, todas medidas contra producción. Cualquiera, sola, habría producido un
acta falsa.

### 1. Una consulta de varios días devuelve UNO SOLO, en silencio

| Cómo se pidió | Registros devueltos |
|---|---|
| Los 7 días de una vez | **12 449** |
| Los mismos 7 días en tramos de 24 h | **~115 000** |

La API sirvió el **10,8 %** —el día **más viejo**— con un `200 OK` sin marcar el resultado
como parcial. Supabase documenta que `logs.all` acepta **como máximo 24 h** por consulta:
pedir 7 días queda fuera de contrato y el backend recorta el rango sin avisar.

**Por eso se consulta día a día.** Dentro de un tramo de ≤24 h la API sí sirve el rango
entero, así que ese tramo se da por **observado completo**. (Ojo: que el último registro
caiga a las 17:10 y no a las 17:55 **no es un hueco** — es una noche tranquila. El
min/max solo sirve de guardia contra un recorte grueso: si lo servido cubre <90 % de lo
pedido, el tramo se parte por la mitad.)

### 2. La retención son 7 días — pero **no hay una fecha, hay TRES**

Retención **documentada** para el plan Pro: 7 días rodantes (a 8 días ya no hay filas).
No es una medición viva del guion; es el valor de plan, y el acta lo dice así
(`retencion_dias_declarada`).

**Consecuencia operativa — la que cambia el calendario:** los 14 días que exige el método
**no se pueden mirar de una vez**. Se cosen con lecturas sucesivas, y **una lectura que no
se hizo a tiempo es un tramo perdido para siempre**. Y como cada ola cerró distinto:

| Ola | Piezas | Cerrada | D+7 | Demoler no antes de |
|---|---|---|---|---|
| F5.d (las 7 gemelas) | 7 | 30/08 | **06/09** | 13/09 |
| F7.1 | 3 | 31/08 | **07/09** | 14/09 |
| F7.2 (interruptor legacy) | 1 | 01/09 | **08/09** | 15/09 |

Por eso **se cosecha seguido**, no solo en D+7 y D+14: cada corrida extra es margen
gratis, y el `--gate` avisa de cualquier hueco dentro de la ventana `[cerrada, drop]`.

### 3. La API rebota, y además limita el ritmo

La misma consulta devolvió `500` y, repetida, `200` con datos; encadenar sin pausa acaba
en `429 ThrottlerException`. Un error tratado como «no hay filas» fabrica el falso verde.
**Aquí un fallo aborta**, y antes reintenta con pausas de 6 s.

### 4. Los dos filtros de `postgres_logs` — y por qué hacen falta los dos

Buscar el nombre de la pieza daba **55, 13, 9…** rastros por pieza; los 34 mensajes
distintos eran **nuestro propio trabajo** (el texto de las migraciones y sus guardas).
*Una migración que **nombra** la pieza no es alguien **llamándola**.*

- **Filtro 1 — severidad.** Las sentencias son `LOG` / `00000`; un intento denegado es
  `ERROR`. Bajó de 55/13/9 a 3/1/1.
- **Filtro 2 — quién redactó el mensaje.** Los 7 restantes seguían siendo guardas
  nuestras, **dos con código 42501**, porque nuestro propio `raise … using errcode` usa
  ese código: **el código no distingue**. Una denegación de verdad la redacta **Postgres**
  y solo tiene estas formas (con o sin el esquema calificando el nombre):
  - `permission denied for function [crm.|public.]X` — viva, sin EXECUTE
  - `function [crm.|public.]X(…) does not exist` — ya demolida

Lo demás va a `menciones_en_errores` para mirarlo a ojo; **no cuenta como intento**.

### 5. `limit 1000` podía fabricar un CERO

Las consultas de detalle traen como mucho 1000 filas. **1000 errores de ruido recientes**
pueden empujar fuera del resultado una denegación más vieja → un falso cero. Ahora, si
una consulta vuelve con exactamente 1000 filas, el tramo se marca **`truncado`** y el
gate **lo frena**. (Hoy los volúmenes reales están muy por debajo, pero el freno es
correcto, no optimista.)

### 6. Dos agujeros más que la 2ª auditoría destapó

- **La denegación de ESQUEMA no nombra la pieza.** Si un rol no tiene `USAGE` de `crm`,
  la llamada muere en `permission denied for schema crm` **antes** de resolver la función:
  el filtro por nombre jamás lo vería. Hay una **sonda aparte** para eso. **Medido el
  04/09: 472 en 7 días**, todas idénticas (`permission denied for schema crm`, sin nombre
  de función ni rol). Por eso es un **aviso, no un bloqueo**: no se puede atribuir a
  ninguna de las 11 (el mensaje no nombra función) y **no la produce nuestro cierre** —
  revocamos EXECUTE de la *función*, un cierre nuestro diría `for function`, no
  `for schema`. Es ruido de un rol sin USAGE golpeando algo de `crm`. 📌 **Vale la pena
  que Miguel sepa que hay ~470/semana de esto** (cliente mal configurado o sondeo), pero
  es ajeno a la F7.
- **La cola de ingesta.** `postgres_logs` tarda minutos en asentar. Consultar hasta
  `now()` y darlo por cubierto pierde el final de la ventana. Ahora el techo se **retrae
  10 min**.
- **edge y postgres se miden por SEPARADO.** Antes, un `edge_logs` vacío hacía saltar la
  consulta a `postgres_logs` del mismo tramo. Ya no: son dos streams independientes.

---

## ⚠️ Lo que este método NO puede afinar (y lo declara, no lo finge)

**La ruta de PostgREST no distingue el esquema.** `crm.crear_contrato_producto` entra por
`/rest/v1/rpc/crear_contrato_producto` igual que la de `public`: el esquema viaja en la
cabecera (`Accept-Profile` en GET, `Content-Profile` en el POST de un RPC), que el log
**no conserva**. Un intento cuenta para **las dos piezas homónimas** → puede dar un falso
**rojo**, nunca un falso verde. El acta lo marca (`nota_ambiguedad_esquema`).

---

## Qué hay en un acta

| Campo | Qué es |
|---|---|
| `proyecto` | ref del proyecto; el gate ignora actas de otro proyecto |
| `retencion_dias_declarada` | 7 (valor de plan, **no** medido) |
| `margen_ingesta_min` | cuánto se retrajo el techo por la cola de ingesta |
| `ventana_pedida` / `ventana_cubierta_por_tramos` | lo pedido vs. lo observado de verdad |
| `tramos[]` | cada trozo, con `filas_edge`/`filas_postgres`, `parcial` y `truncado` |
| `no_ve_exitos: true` | recordatorio de la limitación que manda |
| `denegaciones_esquema[]` | golpes de `permission denied for schema` (adjudicar a ojo) |
| `hallazgos[].intentos` / `.intentos_postgres` | llamadas por ruta / denegaciones de Postgres |
| `hallazgos[].menciones_en_errores` | errores que nombran la pieza sin serlo (a ojo) |

---

## El freno (`--gate`) y su límite

`--gate` lee el **libro vivo** y, para cada pieza cuyo `drop_no_antes_de` ya llegó,
comprueba sobre las actas de **este** proyecto que la ventana `[cerrada_en, drop]` esté
**cubierta entera** (sin huecos), **sin tramos truncados** que la solapen y **sin rastro**
dentro de ella (solo cuenta lo posterior al cierre). Cualquier fallo → **código ≠ 0**
nombrando la pieza y el motivo. Las denegaciones de esquema se **reportan como aviso**
(no bloquean, ver trampa 6).

⚠️ **No está enchufado a la migración**: las demoliciones (`20260913…`, `20260914…`) están
commiteadas y no se editan. Hoy el gate es un **paso del operador** que hay que correr —y
que tiene que salir verde— **antes** de aplicar cualquier demolición. Dejar que la propia
migración consuma la evidencia (una tabla en la base + un preflight que la lea) es una
**v3 pendiente del `!` de Miguel**.

---

## Primera cosecha

**04/09/2026** — ventana `28/08 → 04/09` (incluye el día 0 de las tres olas). **Cero
intentos** por ruta y **cero denegaciones** de Postgres; las menciones son guardas propias
de los ensayos. La primera acta se guardó con el medidor viejo (cobertura por techo); las
corridas siguientes usan el medidor corregido de arriba y tapan cualquier hueco fantasma.

**Veredicto de las dos auditorías de Codex (04/09): NO-GO al acta como prueba única** —
porque no ve éxitos y porque la demolición no la consume. **GO a demoler** se sostiene en
el censo estructural (vacío, dos veces) + el gate verde + el `!` por pieza, con la pérdida
de `metricas_altas_analista_fn` cubierta por su sustituto antes de borrar.
