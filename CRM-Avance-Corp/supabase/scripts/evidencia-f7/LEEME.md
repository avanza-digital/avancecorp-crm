# Evidencia de accesos de la F7 — el requisito D+7 / D+14

El vigía diario prueba que **la puerta sigue cerrada**. Esto prueba otra cosa distinta:
**si alguien intentó abrirla**. Hacen falta las dos antes de derribar una pieza.

```bash
npm run evidencia:f7            # cosecha los últimos 7 días y guarda un acta
npm run evidencia:f7 -- --resumen   # qué tramos hay cubiertos y dónde hay huecos
```

Cada corrida deja un acta `<sello>.json` en esta carpeta. **Son append-only**: una
cosecha nunca reescribe otra, porque el conjunto de actas es la evidencia.

---

## 🔴 La regla que manda

**«No aparece nada» NO es «nadie lo usó».** Solo vale como
**«sin evidencia de uso en la ventana [X, Y]»** — y por eso el guion mide la ventana
que de verdad se pudo mirar en vez de dar por buena la que se pidió.

---

## 🔴 Lo que se midió el 04/09/2026 montando esto

Cuatro trampas, todas medidas contra producción. Cualquiera de ellas, sola, habría
producido un acta falsa el 06/09.

### 1. Una consulta de varios días devuelve UNO SOLO, en silencio

| Cómo se pidió | Registros devueltos |
|---|---|
| Los 7 días de una vez | **12 449** |
| Los mismos 7 días en tramos de 24 h | **115 185** |

La API sirvió el **10,8 %** —el día **más viejo**— con un `200 OK` y sin marcar el
resultado como parcial. Un guion que pidiera la semana entera y viera «0 intentos»
certificaría una semana limpia **habiendo mirado un día**.

**Por eso se consulta día a día**, y cada tramo comprueba que lo observado cubre lo
pedido; si no llega al 90 %, se parte por la mitad y se reintenta.

### 2. La retención son 7 días exactos

Medido: a 7 días el suelo cae en `2026-08-28`; **a 8 días la fuente devuelve cero filas**.
Es una ventana rodante y dura (plan Pro).

**Consecuencia operativa — la que cambia el calendario:** el tramo de 14 días que exige
el método **no se puede mirar de una vez**. Se cose con lecturas sucesivas:

- La lectura de **D+7** cubre la primera semana.
- La de **D+14** ya solo alcanza a ver **la segunda**.
- **Una lectura que no se hizo a tiempo es un tramo perdido para siempre.**

Y como cada ola cerró en un día distinto, no hay una fecha, hay tres:

| Ola | Piezas | Cerrada | D+7 | Demoler no antes de |
|---|---|---|---|---|
| F5.d (las 7 gemelas) | 7 | 30/08 | **06/09** | 13/09 |
| F7.1 | 3 | 31/08 | **07/09** | 14/09 |
| F7.2 (interruptor legacy) | 1 | 01/09 | **08/09** | 15/09 |

Por eso **se cosecha seguido, no solo en D+7 y D+14**: cada corrida extra es margen
gratis contra un fallo del canal, y `--resumen` avisa de cualquier hueco.

### 3. La API rebota, y además limita el ritmo

La misma consulta devolvió `500` y, repetida, `200` con datos. Encadenar peticiones sin
pausa acaba en `429 ThrottlerException`. Un error tratado como «no hay filas» fabrica
exactamente el falso verde. **Aquí un fallo aborta**, y antes reintenta con pausas.

### 4. Los dos filtros de los registros de Postgres — y por qué hacen falta los dos

Buscar el nombre de la pieza en `postgres_logs` daba **55, 13, 9…** rastros por pieza.
Los 34 mensajes distintos eran **nuestro propio trabajo**: el texto de las migraciones
F5.b/c/d y F7.1/7.2, sus ensayos, y los mensajes de sus propias guardas.
*Una migración que **nombra** la pieza no es alguien **llamándola**.*

- **Filtro 1 — severidad.** Los registros de sentencia son `LOG` / `00000`; un intento
  denegado es `ERROR`. Bajó de 55/13/9 a 3/1/1.
- **Filtro 2 — quién redactó el mensaje.** Los 7 que quedaban seguían siendo guardas
  nuestras, y **dos de ellas con código 42501**, porque nuestro propio
  `raise … using errcode` usa ese código: **el código no distingue**.
  Una denegación de verdad la redacta **Postgres**, y solo tiene dos formas:
  - `permission denied for function X` — la pieza vive y no tiene EXECUTE
  - `function X(…) does not exist` — la pieza ya se demolió

Lo demás se guarda en `menciones_en_errores` para mirarlo a ojo, pero **no cuenta como
intento**. Contarlo haría el veredicto ilegible.

---

## ⚠️ Lo que este método NO puede afinar

**La ruta de PostgREST no distingue el esquema.** `crm.mi_acceso_fn` —que solo existe en
`crm`— entra por `/rest/v1/rpc/mi_acceso_fn`, igual que una de `public`: el esquema viaja
en una cabecera. Un intento contra `/rpc/crear_contrato_producto` **cuenta para las dos
piezas homónimas**. El acta lo declara (`nota_ambiguedad_esquema`) en vez de fingir una
precisión que no tiene.

---

## Qué hay en un acta

| Campo | Qué es |
|---|---|
| `ventana_pedida` | lo que se pidió |
| `ventana_cubierta_por_tramos` | lo que de verdad se miró |
| `tramos[]` | cada trozo de 24 h con su cobertura medida y sus registros |
| `hallazgos[].intentos` | llamadas por la ruta de PostgREST |
| `hallazgos[].intentos_postgres` | denegaciones redactadas por Postgres |
| `hallazgos[].menciones_en_errores` | errores que nombran la pieza sin serlo (a ojo) |

## Primera cosecha

**04/09/2026** — 7 tramos, **115 022 registros mirados**, ventana `28/08 → 04/09`
(incluye el día 0 de las tres olas). **Cero intentos** por ruta y **cero denegaciones**
de Postgres. Las 8 menciones son guardas propias de los ensayos.
