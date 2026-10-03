# Corrección de la revisión de F2 + F3 — plan corto (borrador para el OK de Miguel)

Escrito el 03/10/2026 en la sesión de Jhosep. **Solo análisis: sin SQL ni código.** Responde a
`REVISION-2026-10-02.md` (PR #170) y a la respuesta de Codex r1
(`docs/encargos/2026-10-02-codex-llamadas-celular-f2-f3-r1-respuesta.md`). Base: `origin/main` `536454e3`.
Las 4 migraciones están fusionadas y **sin aplicar** en producción.

## En una línea

Una **migración nueva** (la quinta) cierra los fallos 1–4 y los menores 6–13 sin editar las cuatro fusionadas.
Antes de publicar, Miguel decide el fallo 5 y cinco cosas más (tabla al final).

## Cómo se aplica

- **Junto con las cuatro, en el mismo despliegue.** Su precondición exige las cuatro aplicadas y las tablas de
  llamadas **vacías**; si encuentra filas, se niega. Por eso puede cambiar tablas sin migrar datos.
- Un archivo para toda la corrección, con su reversa, su registrador y sus oráculos.
- La v4 de la encuesta (sellada por md5) no se toca.

## 1. Una recepción única por envío (fallo 1; menores 6, 7, 9, 11, 12 y 13)

El problema (reproducido por Miguel y confirmado por Codex):
- Reenviar el mismo id con otro contenido da `P0409` si el número era de un lead; si no, crea una llamada nueva.
- El `P0409` revierte la transacción: el conflicto **no gasta cupo** y el ignorado sí.
- Taparlo solo en la Edge no basta: el cupo, `envios_hoy` y `ultimo_envio_en` siguen delatando.

El arreglo:
- **Tabla nueva `crm.llamadas_celular_recepciones`**: una fila por cada envío aceptado, ANTES de buscar el lead,
  también para los ignorados y las entrantes apagadas. Clave única `(etiqueta, origen_hash)`.
  - La `etiqueta` (C1, C2…) y no la asignación: rotar la clave no rompe la unicidad (menor 9).
  - `origen_hash` = sha256 del id de origen. El id tal cual nunca se guarda, por si trae un teléfono (menor 12).
    Tampoco el número ni el hash del contenido.
  - RLS, sin grants, inmutable y sin bitácora (no guarda datos personales).
  - **No caduca**: purgar una llamada no libera su id; si caducara, volvería el ataque compuesto de Codex.
- **`crm.llamadas_celular_eventos` apunta a su recepción** (`recepcion_id` único) en lugar de guardar
  `evento_origen_id`. Se retira la unicidad `(asignacion_id, evento_origen_id)` y se ajusta el candado de la tabla.
- **Nuevo orden en las puertas de servicio**, el mismo para llamadas y latidos:
  1. Clave → asignación bloqueada `FOR SHARE` y revalidada (vigente y analista activo). Si no, 401 (menor 6).
  2. Cupo con **una sola hora real** (`clock_timestamp()`) tomada después del candado; la ventana nunca retrocede
     (menor 7). Sin fila de política, error explícito (menor 13).
  3. Validación del contenido: un envío inválido **también gasta cupo** (menor 11) y responde 400.
  4. Recepción: si ya existía, termina normal sin buscar nada («primer envío gana»).
  5. Solo si es nueva: política y búsqueda del lead, con los cambios de §2 y §3.
  6. `ultimo_envio_en` se actualiza siempre. La Edge responde el mismo 202 en todos los casos.
- El `P0409` desaparece de la ingesta, y con él el 409 de la Edge.
- Compatible con F4: la puerta v5 encontrará la llamada por el hash del id de origen.

Lo que NO cierra (Codex): la **pista por tiempo de respuesta**. El primer envío sigue haciendo más trabajo si
encuentra lead. Propuesta: medirla en el banco (p50/p95 con lead y sin lead) y decidir con el dato (decisión 5).

## 2. Ámbito (fallos 2 y 4; menores 8 y 10)

- **Leads borrados (fallo 2):** `private.llamada_celular_visible` exige, para toda llamada con lead, que el lead
  esté **activo**, también para gerencia. Al estar en el predicado común, lo cumplen la bandeja, el detalle,
  descartar, asociar y enlazar. Se anota en la lista de copias de `leads_select` de `MIGRACIONES.md`.
- **Ambiguas (fallo 4):** los candidatos se buscan **solo dentro del ámbito del dueño del celular**, con el mismo
  mecanismo que ya evalúa la elegibilidad como el dueño (`private.llamada_celular_elegible_dueno`):
  - uno → identificada;
  - dos o más → ambigua, solo con leads suyos y sin guardar el conteo (`calidad.candidatos` desaparece);
  - ninguno → igual que un número sin lead (decisión 3 del contrato), aunque el número sea de un lead ajeno.
- Por qué «solo su ámbito» y no «como hoy cuando hay un único candidato ajeno»: con la perilla
  `guardar_sin_identificar` encendida, un número cualquiera le aparece al analista «sin identificar» y el de un lead
  ajeno no, y esa diferencia vuelve a delatar. Costo: la llamada a un lead de otro equipo ya no le aparece a ese
  equipo (decisión 3).
- **Reasignación a mitad (menor 8):** descartar, asociar y enlazar bloquean el lead (`FOR SHARE`) y revalidan el
  ámbito bajo ese candado.
- **Resultado deshecho (menor 10):** enlazar rechaza un resultado con `deshecho_en`.

## 3. Entrantes (fallo 3)

Recomendado: **bloquear la perilla** hasta construir la #14 (ya aprobada). Un `check` fija `entrantes_activas` en
`false`, y `crm.fijar_politica_llamadas_celular` lo rechaza con un mensaje claro. La #14 llega después como paso
propio: servidor (devolución de las perdidas), macro (necesita MacroDroid Pro) y pantalla.

## 4. La encuesta y la llamada (fallo 5): decide Miguel

Hoy nada las une hasta F4: toda llamada a un lead queda «pide resultado» para siempre.
- **A (recomendada): publicar F2 + F3 corregidas junto con el enlace exacto de F4-a.** Es la puerta
  `registrar_llamada_v5` por id de origen (`F4-PLAN-CORTO.md` §1), con el cambio pequeño de F1 que lleva el id y la
  nueva dirección de la macro. Datos correctos desde el primer día. Costo: F2 + F3 esperan a F4-a.
- **B: publicar F2 + F3 ya y recuperar lo acumulado cuando llegue F4.** Llega antes a producción, pero las llamadas
  se acumulan como «pide resultado» sin que nadie las vea, y luego hay que limpiarlas.
- En las dos hace falta **retención para las identificadas sin resultado**, que hoy no caducan. Propuesta: 30 días,
  como las demás (decisión 4).

## 5. Lo demás

- **Bandeja duplicada (menor 14):** se retiran `crm.llamadas_celular_pendientes_fn` y su núcleo. Nadie las usa;
  queda la paginada, `crm.llamadas_celular_bandeja_fn`.
- **Edge (menor 15):** fecha estricta ISO 8601 con zona y el mismo rango que la base, en lugar de `Date.parse`.
  Sin la rama del 409.
- **Macro (menor 16, con el celular):** volver `en_saliente` a Falso cuando suena una entrante, y armar el latido.
  Necesita macros nuevas: va con MacroDroid Pro.
- **Guía de publicación (puntos 17–20):**
  - asignar un celular imprime su clave: Miguel lo corre en su terminal, nunca en una sesión de Claude;
  - registradores `registrar-*.sql` para las cinco migraciones (patrón de `scripts/potencial-lead/`);
  - asignar como gerencia se prueba en el banco por la misma vía que en producción;
  - se borra el espejo de la Edge en `_supabase_functions/` y el paso 0.4: `supabase/functions/LEEME.md` dice
    «sin espejo legado».

## Pruebas

| Dónde | Qué demuestra |
| --- | --- |
| Banco reducido (`npm run test:llamadas:local`), oráculo nuevo | Secuencias idénticas con y sin lead ajeno: mismas respuestas, cupo y estado. Reenvío con otro contenido: termina normal y gasta cupo. Ignorado y luego lead: sigue ignorado. La purga no libera el id. Rotar no duplica. Lead borrado: gerencia no lo ve ni lo descarta. Perilla de entrantes bloqueada. Ambiguas: solo leads propios y sin conteo. La ventana del cupo no retrocede. Enlazar rechaza un deshecho. Política ausente: error claro |
| Banco reducido, dos sesiones | Carreras con barreras: cierre durante un latido, reasignación durante un descarte, medianoche de Lima |
| Banco reducido | Tiempo de respuesta con y sin lead (p50/p95) |
| Gate `testLlamadasCelular` | Ya no exige `P0409`. Añade lead borrado, entrantes, un enlace real con su encuesta y rotación |
| Edge | `test:llamadas-ingesta` y sus mutantes, con la fecha estricta y sin 409 |
| Banco de Miguel (esquema de producción) | `banco/verificar-hallazgos.sql` con los tres fallos cerrados, gate completo y advisors |

## Decisiones que necesita Miguel

| # | Decisión | Recomendación de Claude | Alternativa y su costo |
| --- | --- | --- | --- |
| 1 | Fallo 5: unir encuesta y llamada | **A**: publicar con el enlace exacto de F4-a | B: publicar antes y limpiar después |
| 2 | Fallo 3: entrantes | **Bloquear la perilla** y hacer la #14 como paso propio | Construir la #14 dentro de la corrección: más grande y más lenta de revisar |
| 3 | Llamada a un lead fuera del ámbito del dueño | **Tratarla como número sin lead** | Guardarla para el equipo del lead, como hoy con un candidato: con la perilla de «sin identificar» encendida, reabre una pista |
| 4 | Retención de las identificadas sin resultado | **30 días**, como las demás | Otro plazo; «nunca» no, porque guardan un teléfono |
| 5 | Pista por tiempo (#12) | **Medirla y aceptarla si es pequeña** frente a la red | Desacoplar el acuse del proceso: choca con no guardar números sin identificar |
| 6 | Bandeja duplicada | **Retirar** la primera | Mantenerla: dos copias que cuidar |

Siguen pendientes de confirmar: la regla extra de la decisión 4, los criterios de Claude de `MIGRACIONES.md` y la #12.

Decisiones de criterio de Claude, para que Miguel las vea:
- La recepción se identifica por etiqueta y no por asignación, para que rotar no duplique.
- Se guarda el hash del id de origen, nunca el id.
- Las recepciones no caducan por ahora: son filas mínimas y su caducidad reabriría el fallo 1. Se revisa al año.
- Toda la corrección va en una sola migración, aplicada con las cuatro.

## Orden de trabajo (con el OK)

1. Migración 5 con su reversa y los cinco registradores; oráculos en verde en el banco reducido.
2. Edge y sus pruebas.
3. Bloque del gate.
4. Guía corregida, espejo borrado y `MIGRACIONES.md` al día (todavía dice «EN RAMA feat/llamadas-f2»).
5. Encargo para Codex r2 y auditor-rls (los corre Miguel).
6. Ensayo de Miguel en su banco y publicación según la decisión 1.

## Riesgos y límites

- La pista por tiempo queda abierta hasta medirla.
- Las carreras se prueban con barreras en el banco reducido, no con los triggers de reasignación de producción;
  el ensayo de Miguel lo completa.
- Bloquear el lead (`FOR SHARE`) añade una espera corta si a la vez se reasigna.
- Aplicar las cuatro sin la quinta publicaría las fugas: la guía las aplica juntas.

## En llano

Miguel encontró cinco fallos. Este plan arregla cuatro en una pieza nueva y deja que él elija cómo resolver el
quinto: unir la encuesta con la llamada. El arreglo principal es que el CRM anote cada aviso del celular antes de
mirar si el número es de un lead, y conteste siempre igual: así nadie puede averiguar quién está en el CRM. Además,
los leads borrados dejan de verse, cada celular solo reconoce los leads de su dueño y las entrantes quedan apagadas
hasta construirlas bien. Nada de esto se programa hasta que Miguel diga que sí.
