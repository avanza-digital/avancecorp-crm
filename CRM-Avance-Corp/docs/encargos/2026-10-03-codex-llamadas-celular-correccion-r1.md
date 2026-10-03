ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí (los archivos llevan número de línea). Formato: VERDICT (PASS/BLOCK), SUMMARY,
RESPUESTA a cada pregunta P1–P11 (sí/no + por qué, con evidencia archivo:línea del texto
transcrito), FINDINGS P0–P3 nuevos, RIESGOS y test gaps, NEXT ACTIONS, CONFIDENCE. Pídete
REFUTAR: busca lo que el plan no cierra o lo que rompe, no lo que está bien.

# Encargo: «Llamadas desde el celular» — PLAN de la corrección de F2 + F3 (diseño, SIN código) — LEVEL 3
(datos, permisos, autenticación por credencial de dispositivo, migraciones, concurrencia).
**Tarea nueva: la corrección. Ronda 1 de máx. 2.** Esta ronda revisa el DISEÑO antes de escribir SQL; la ronda 2
queda para el diff de la quinta migración. Preparado el 03/10/2026 por la sesión de Jhosep (PRIMARY de la
corrección); lo corre Miguel con `scripts/codex-review-mcp`, que es quien tiene Codex.

## Qué es
CRM interno (Supabase/Postgres 17.6). Esquema `crm` expuesto por PostgREST (puertas = funciones no trigger de
`crm`), núcleo en `private`, tablas con RLS sin policies ni grants. Un celular corporativo (Android + MacroDroid)
avisa al CRM de cada llamada del analista: POST a la Edge `crm-llamadas-ingesta` (verify_jwt=false) con la clave
del celular en `x-celular-credencial`. La Edge llama con service_role a `crm.ingerir_llamada_celular_servicio`, que
valida la clave (sha256), aplica el límite (30/min, 600/día) y delega en el núcleo
`private.llamada_celular_ingerir`. El analista registra el resultado con su sesión (encuesta F1, en producción).

## Estado
- **Ronda 1 de la tarea anterior (02/10): BLOCK** — tu respuesta y la revisión de Miguel están transcritas abajo.
- Nada aplicado en ningún entorno. Las 4 migraciones se fusionaron a `main` sin corregir y **no se editan**: la
  corrección va en una **quinta migración**, aplicada en el mismo despliegue que las cuatro (las tablas estarán
  vacías: su precondición lo exigirá).
- El plan (transcrito abajo) propone el diseño y deja **seis decisiones** al dueño (Miguel). Jhosep ya respaldó la 3.

## Decisiones de negocio RATIFICADAS por el dueño (Miguel) el 02/10/2026
F2: (1) pide resultado si el lead está activo, etapa no terminal, sin no_contactar y en el ámbito
del dueño del celular; si no, `por_revisar`. (2) Entrantes definidas pero apagadas (perilla
`entrantes_activas=false`). (3) Número que no es de ningún lead: NO se guarda (perilla
`guardar_sin_identificar=false`). (4) Deshacer no borra ni desenlaza. (5) Hora del celular si viene;
analista = el de la asignación vigente. (6) Retención 30 días para descartados y ambiguos sin
resolver; `numero_crudo` no se guarda. (7) Lead reasignado: la llamada la ve y trabaja el dueño
ACTUAL del lead; quien marcó queda como dato histórico.
F3: (1) verify_jwt=false con credencial por celular (solo su hash en la base), 401 uniforme.
(2) Límite 30/min y 600/día, 429 con Retry-After. (3) Latido de salud cada 6 h. (4) El celular abre
la encuesta de F1 por número. (5) MacroDroid es durable (probado).
Criterio de Claude aceptado: solo gerencia asigna celulares; llamada a lead fuera del ámbito de
quien llama → `por_revisar` para la cadena del dueño; el celular es de analista (`vendedor`) o
supervisor activo; elegibilidad evaluada COMO el dueño del celular (migración 4).
Propuesta #12 (aceptada): la respuesta al celular NO debe delatar si un número es de un lead.

## Preguntas para el revisor
P1. **Fallo 1 (oráculo de existencia).** La recepción única por `(etiqueta, sha256(evento_origen_id))`, registrada
    ANTES de buscar leads, con el mismo 202, el cupo consumido para todo envío aceptado y `ultimo_envio_en`
    actualizado siempre (plan §1): ¿cierra los oráculos deterministas que listaste (respuesta, cupo, `envios_hoy`,
    `ultimo_envio_en`, aparición en la bandeja, ataque compuesto con un ignorado previo)? ¿Queda alguno además
    del tiempo? ¿Es correcta la clave por `etiqueta` (rotación: misma etiqueta, otra asignación; reutilización de
    una etiqueta tras cerrar) o debería ser otra?
P2. **Orden de la puerta (menores 6 y 7).** Autorizar con la asignación `FOR SHARE` → cupo con una sola
    `clock_timestamp()` tomada tras el `FOR UPDATE` de `private.celulares_estado` y ventana que nunca retrocede →
    validar → recepción → lead. ¿Cierra las carreras de tu r1 (latido tras el cierre, retroceso de ventana, 429
    antes que 401) sin abrir un interbloqueo con cerrar/rotar (`FOR UPDATE` de la asignación)?
P3. **Menor 11 (inválidos sin cupo).** Para que un envío inválido gaste cupo, el plan valida DESPUÉS de consumir y
    devuelve un resultado (no una excepción). ¿Es la forma correcta en plpgsql, o un bloque `EXCEPTION` (que
    abre una subtransacción) tiene costes o riesgos que lo desaconsejan aquí?
P4. **Fallo 2.** Exigir lead activo en `private.llamada_celular_visible` para todos, gerencia incluida: ¿rompe algún
    caso legítimo (auditoría de llamadas de leads dados de baja)? ¿Esas llamadas deberían caducar, y con qué
    regla?
P5. **Fallo 4 + decisión 3.** Buscar candidatos SOLO en el ámbito del dueño del celular, evaluado como el dueño
    (mismo mecanismo que `private.llamada_celular_elegible_dueno`, E:41–57): ¿cierra la revelación de leads
    ajenos, incluida la de una llamada «ambiguo» y la que aparece con `guardar_sin_identificar` encendida? ¿Qué
    caso legítimo se pierde?
P6. **Fallo 3 + decisión 2.** Bloquear `entrantes_activas` con un `check` más el rechazo en
    `crm.fijar_politica_llamadas_celular`, y construir la #14 después: ¿suficiente, o deja datos falsos por otra
    vía?
P7. **Fallo 5 + decisiones 1 y 4.** Opción A (publicar con el enlace exacto de F4-a) frente a B (publicar ya y
    recuperar después). ¿Qué riesgo de datos tiene B? ¿Es correcta la retención de 30 días para las identificadas
    sin resultado, o hace falta otra regla?
P8. **Decisión 5 (#12, tiempo).** ¿Es aceptable medir la diferencia de tiempo entre «con lead» y «sin lead» y
    aceptarla si es pequeña frente a la latencia de red (Edge + PostgREST), o el #12 exige desacoplar el acuse? Si
    se mide, ¿cómo, para que la cifra sirva?
P9. **Menor 12.** Guardar `sha256(evento_origen_id)` sin pimienta en la recepción y en el evento, y sacarlo de la
    bitácora: ¿suficiente si el id contuviera un teléfono (fuerza bruta de 9 dígitos)? ¿Conviene además restringir
    su forma?
P10. **Menor 8.** ¿`FOR SHARE` sobre la fila de `crm.leads` en descartar/asociar/enlazar es el candado que se
    serializa con las escrituras de reasignación (qué toman ellas sobre `crm.leads`), o hace falta otro?
P11. ¿Algo del plan contradice las decisiones ratificadas, o deja un hueco que no está en su tabla de decisiones?
    Evalúa también las «decisiones de criterio de Claude» del final del plan.

## Plan de la corrección (lo que se revisa): `docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md`

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
  - Cuando llegue la #13 (clientes, aprobada), la búsqueda incluirá los clientes de la cartera del dueño con la
    misma regla.
- Objetivo de negocio (Jhosep, 03/10): registrar y medir la gestión de cada analista sobre **sus** leads, y más
  adelante sobre sus clientes.
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
| 3 | Llamada a un lead fuera del ámbito del dueño | **Tratarla como número sin lead** (Jhosep está de acuerdo, 03/10) | Guardarla para el equipo del lead, como hoy con un candidato: con la perilla de «sin identificar» encendida, reabre una pista |
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

## Revisión de Miguel del 02/10: `docs/plans/llamadas-celular/REVISION-2026-10-02.md`

# Revisión de F2 + F3 antes de publicar — 02/10/2026 (Claude, sesión de Miguel)

**Veredicto: NO PUBLICAR TODAVÍA.** Ningún camino deja leer datos de otro analista con la clave de un
celular, pero hay 5 fallos que hay que corregir (o decidir) antes de aplicar en producción.

Fuentes: lectura línea por línea de las 4 migraciones, la Edge, las reversas y la macro (Claude);
`auditor-rls` (CHANGES_REQUESTED); Codex LEVEL 3 r1 (**BLOCK**, encargo y respuesta en
`docs/encargos/2026-10-02-codex-llamadas-celular-f2-f3-r1*.md`). **REPRODUCIDO** = ejecutado el 02/10 en
el stack propio con el esquema de producción al byte (`supabase/scripts/llamadas-celular/banco/verificar-hallazgos.sql`).

## Decisiones de Miguel tomadas el 02/10

- **Ratifica** las 7 decisiones provisionales de F2 y las 5 de F3 («Ratificar todas»).
  ⚠️ La pregunta fue incompleta: no se le mostraron la regla extra de Jhosep en la decisión 4 (el enlace se
  mueve al resultado nuevo), los 8 criterios de Claude de `MIGRACIONES.md` ni la #12. Confirmarlos con él.
- **Aprueba las propuestas #13 (clientes), #14 (entrantes) y #15 (métricas aparte).** La #14 implica
  comprar **MacroDroid Pro** (acción de Miguel).

## A. Bloquean la publicación (P2)

| # | Fallo | Evidencia | Arreglo propuesto |
|---|---|---|---|
| 1 | El reenvío delata si un número es de un lead (#12). Guardado → reenviar el mismo id con otro contenido da 409; ignorado → crea llamada nueva. El conflicto no gasta cupo y el ignorado sí. | **REPRODUCIDO** (H1a: sin lead → luego juan = llamada nueva; H1b: juan → luego otro = `P0409`). Auditor P2-1, Codex 1. | Registrar TODA recepción por `(asignacion_id, evento_origen_id)` antes de buscar leads (lápida sin número ni hash; no caduca mientras la clave pueda reutilizarse); primer envío gana; conflicto y repetido terminan normal con el mismo 202 y el mismo cupo. |
| 2 | Gerencia ve y modifica llamadas de leads borrados (nombre y número; puede descartar). El dueño no. | **REPRODUCIDO** (H3: gerencia ve 4 de «JUAN PEREZ DEMO» borrado y descarta; vend1 ve 0). Auditor P2-2, Codex 2. | En `private.llamada_celular_visible`: con lead, exigir lead activo también para gerencia. Anotar la función en la lista de espejos de `leads_select`. |
| 3 | La perilla de entrantes da datos falsos: una entrante perdida queda «pide resultado»; `requiere_devolucion` no lo produce ningún código. | **REPRODUCIDO** (H2: entrante `no_atendida` → `requiere_resultado`). Claude. | Bloquear la perilla hasta construir la #14, o construir la lógica de entrantes en la corrección. |
| 4 | Las ambiguas revelan leads ajenos: quien llama ve que el número es de ≥ 2 leads de TODO el CRM (y cuántos). | Código: `calidad.candidatos` (E:180–183) y `llamada_celular_visible` sin lead (N:140–141). Codex 6 (sube a P2). | Resolver candidatos dentro del ámbito de quien llama; no guardar ni mostrar el conteo global. |
| 5 | Hasta F4 nada enlaza la encuesta con la llamada: toda llamada a un lead queda «pide resultado» para siempre aunque el analista llene la encuesta, y nunca caduca (la retención no cubre identificadas). | Código: solo la puerta `enlazar` crea el enlace; F1 (en prod) no la llama. Auditor P3-1. | **Decisión de Miguel**: enlace automático (p. ej. al registrar con v4) o recuperación de lo acumulado al llegar F4, más retención para identificadas sin enlace. |

## B. Menores (P3)

6. Latido aceptado aunque cierren el celular a mitad; con cupo agotado da 429 antes que 401 (Codex 3).
7. El contador del límite puede retroceder de ventana: `now()` calculado antes del candado (Codex 4). Usar `clock_timestamp()` tras el candado.
8. Reasignación a mitad de descartar/asociar/enlazar sin revalidar: no se bloquea el lead (Codex 5).
9. Rotar la clave puede duplicar llamadas: el origen es único POR asignación (Claude, Codex).
10. `enlazar` acepta un resultado ya deshecho (`deshecho_en`) (Claude).
11. Envíos inválidos o en conflicto no gastan cupo: sin límite para peticiones malas (Claude).
12. `evento_origen_id` admite un teléfono y la auditoría no lo enmascara (auditor P3-6, Codex 7).
13. Límite con NULL si faltara la fila de política (teórico; la fila no se puede borrar) (auditor P3-4).
14. Dos copias de la bandeja (`pendientes` y `bandeja`) (auditor P3-3).
15. Edge: `Date.parse` más permisivo que la base; 400/413 antes que 401 distingue clave bien formada (Codex).
16. Macro: si «Llamada terminada» no dispara, `en_saliente` queda Verdadero y la siguiente ENTRANTE entra como saliente; el latido de salud no está armado (Claude).

## C. Guía de publicación (`PUBLICAR-F2-F3.md`)

17. La clave del celular saldría en la salida de `db query` al asignar: si se corre desde Claude queda en la conversación. Miguel la corre en su terminal, fuera de Claude.
18. No hay registradores de las 4 migraciones (`registrar-*.sql`, como `scripts/potencial-lead/`).
19. El SQL de asignar como gerencia (`set local role authenticated`) no está probado por la vía de producción.
20. El paso 0.4 (espejo en `_supabase_functions/`) contradice `supabase/functions/LEEME.md` («sin espejo legado»).

## D. Fallos del trabajo de Claude del 02/10

21. Banco incompleto: faltaba la fila de `crm.sla_operacion_control` (P0002 en `private.sla_conceder_prorroga` línea 23, vía `trg_actividades_avance_etapa`). Los 80 rojos del gate son en buena parte del banco, no del CRM: registrar llamada, descartar/deshacer y cola v3 quedaron sin probar.
22. El bloque `testLlamadasCelular` exige el 409 (la fuga #1); no prueba lead borrado, entrantes ni un enlace real con su encuesta.
23. No se corrieron `verificar-datos.sql` ni las reversas en el banco con esquema de producción.
24. Cifra errónea «18 puertas» (son 15 nuevas), también en el encargo a Codex (línea 28).
25. La ratificación de Miguel se pidió incompleta (ver arriba).
26. El duplicado al rotar (#9) se descubrió escribiendo el test y no se reportó en el momento.
27. Migraciones aplicadas con `psql -f` y sin registrar (producción: `db query --file` en un mensaje + registrador); configuración cargada sin llaves foráneas; limpieza entre corridas distinta del guion oficial.

## E. Comprobado y SIN fallo

- Bandeja con 20 000 llamadas acumuladas: ~0,1 s (`banco/medir-bandeja.sql`).
- Suplantación temporal de identidad (`set_config` de la migración 4): no se filtra (Codex) y funciona (supervisor → `requiere_resultado`, gate).
- Purga por GUC: no explotable desde la API.
- Cron: quedará con rol `postgres`, como los 6 de producción (leído 02/10).
- `auth.uid()` de producción lee `request.jwt.claim.sub` primero (leído 02/10).
- Tablas sin policies ni privilegios para la API; EXECUTE exacto; DEFINER con `search_path` vacío; clave solo como sha256.
- Locales en verde: `test:llamadas:local` 160/160, `test:llamadas-ingesta` 16/16, mutantes de la Edge 14/14.
- Gate con las 4 migraciones: mismos rojos que sin ellas (ninguno nuevo) y el bloque nuevo 124/124 — con la salvedad del punto 21.

## Tu respuesta de la ronda anterior (r1, BLOCK): `docs/encargos/2026-10-02-codex-llamadas-celular-f2-f3-r1-respuesta.md`

codex
**VERDICT: BLOCK**

**SUMMARY**

Confirmo los oráculos de existencia y el acceso de gerencia a llamadas de leads borrados. Además, encuentro carreras en la revocación del latido, las ventanas del contador y la autorización durante una reasignación.

No encuentro una fuga persistente de identidad por `set_config`, ni un bypass mediante el GUC de purga accesible desde las puertas transcritas. Las escrituras de ingesta en bandejas ajenas están expresamente autorizadas por el negocio.

Revisión estática: pruebas **NOT RUN**. La aplicación limpia en Docker es evidencia aportada, no verificación de estos comportamientos.

Para abreviar las citas: **D** = migración `20261001145242…datos.sql`; **N** = `20261001160219…nucleo.sql`; **I** = `20261001212258…ingesta.sql`; **E** = `20261001222431…elegibilidad_dueno.sql`; **H** = `handler.ts`.

**FINDINGS P0–P3**

1. **P2 — A-P2-1 confirmado: el conflicto revela existencia; ocultarlo solamente en la Edge deja otros oráculos.**

   `E:141–149` compara el contenido únicamente cuando existe un evento guardado y lanza `P0409`. El número sin lead retorna sin guardar identidad (`E:187–190`). La Edge distingue ambos resultados mediante 409/202 (`H:129,141`).

   Además, el contador se incrementa antes de invocar el núcleo, pero el conflicto escapa de la RPC y revierte la transacción (`I:308–315`). Si únicamente se transforma ese error en 202 en la Edge, **el conflicto sigue sin consumir cupo**, mientras que el ignorado sí consume. Se puede distinguir agotando el límite; supervisión también dispone de `envios_hoy` y `ultimo_envio_en` (`I:278–282`).

   Confirmo igualmente el ataque compuesto con `(X, número_prueba)` seguido de `(X, lead_propio)`: la aparición en la bandeja depende de que el primer envío haya sido ignorado.

2. **P2 — A-P2-2 confirmado y ampliado: gerencia puede leer y modificar llamadas de leads soft-borrados.**

   La primera alternativa de `llamada_celular_visible` concede acceso a gerencia sin comprobar `lead.activo` (`N:137–142`). Las bandejas incorporan nombre y número sin otro filtro de actividad (`N:653–663`; `I:239–246`).

   El mismo helper autoriza `descartar` (`N:488–504`) y `enlazar` (`N:405–458`), por lo que el defecto también permite escrituras sobre esas llamadas.

   La corrección debe estar en el predicado compartido: para cualquier llamada con lead, exigir ámbito sobre un **lead activo**, incluida gerencia. Filtrar únicamente las bandejas dejaría abiertos detalle y operaciones.

3. **P2 — Nuevo: el latido puede confirmarse después del cierre o baja que debía invalidarlo.**

   `registrar_salud_celular_servicio` resuelve la credencial una vez y después consume cupo y escribe salud, sin bloquear ni revalidar la asignación (`I:330–336`). El contador puede esperar en su `FOR UPDATE` (`I:159`).

   Intercalado: resolver credencial → esperar contador → otra transacción cierra la asignación → continuar y guardar el latido. La respuesta será 200. La ingesta de llamadas sí dispone de una comprobación posterior bajo `FOR SHARE` (`E:129–133`).

   También hay una variante en llamadas: si el cupo está agotado, puede producirse 429 **antes** de alcanzar esa revalidación (`I:308–310`). Ambas puertas necesitan un criterio común de bloqueo y autorización anterior al límite.

4. **P2 — Nuevo: el contador puede retroceder de ventana y reiniciar cupos bajo concurrencia.**

   `v_ahora`, `v_minuto` y `v_dia` utilizan `now()`, que representa el inicio de la transacción, y se calculan antes del bloqueo (`I:150–159`). Cualquier desigualdad de ventana reinicia el contador, incluso cuando la ventana solicitada es anterior (`I:161–177`).

   Una transacción antigua que se ejecute después de otra del minuto siguiente puede sobrescribir la ventana nueva con la antigua. La siguiente petición vuelve a reiniciarla. El mismo problema existe al cambiar el día de Lima.

   El bloqueo evita incrementos perdidos dentro de una misma ventana; **no evita este retroceso**. Calcular una única hora real con `clock_timestamp()` después de adquirir el bloqueo y derivar ambas ventanas de ella.

5. **P2 — Nuevo: bloquear el evento no protege la autorización frente a una reasignación del lead.**

   `descartar` bloquea el evento, comprueba visibilidad y posteriormente escribe (`N:488–504`). No bloquea el lead que contiene la asignación utilizada para autorizar. Lo mismo sucede al asociar (`N:358–381`) y enlazar (`N:405–458`).

   El código permite este intercalado: A obtiene autorización → el lead se reasigna a B → A modifica la llamada. Para garantizar la decisión 7 durante la operación, hace falta coordinarse con las escrituras de asignación mediante un bloqueo apropiado del lead y una revalidación bajo ese bloqueo.

   La ausencia de esa protección está en el código; falta reproducir el intercalado contra los triggers reales de reasignación.

6. **P2 — A-P3-2 confirmado: la fuga de ambiguas supera el contador mostrado.**

   La ingesta guarda el número global de candidatos (`E:180–183`); una llamada sin lead resulta visible para quien llamó (`N:140–141`), y el detalle devuelve `calidad` (`N:688–694`).

   **Eliminar `calidad.candidatos` no basta** si la garantía incluye lo observable con la sesión del analista: la aparición de una llamada marcada `ambiguo` ya revela que existen múltiples leads activos con ese teléfono, aunque todos sean ajenos.

   La resolución global y la información mostrada al analista deben respetar su ámbito. Elevo este hallazgo de P3 a P2 por tratarse de información de leads ajenos.

7. **P3 — A-P3-6 confirmado: el identificador permite conservar un teléfono fuera de su retención.**

   `evento_origen_id` admite un teléfono completo (`D:237–239`; `E:99–101`). El trigger de auditoría solo solicita enmascarar `numero_canonico` y `hash_payload` (`D:398–400`).

   Por tanto, un identificador construido con el teléfono puede terminar conservado en la auditoría. Este problema también afecta a la propuesta de «lápidas sin número»: el identificador recibido no garantiza esa propiedad. Generar identificadores opacos independientes del teléfono y excluir el identificador original de la auditoría.

Los restantes hallazgos previos quedan así:

| Hallazgo | Evaluación |
|---|---|
| **A-P2-4** | **Refutado como fallo actual.** La definición aportada de `auth.uid()` sí prioriza `request.jwt.claim.sub`. Un precheck de comportamiento evita depender silenciosamente de que siga haciéndolo. |
| **A-P3-1** | **Confirmado como riesgo de abuso.** La purga no incluye identificados pendientes (`D:528–544`). Sin embargo, esto no contradice la retención ratificada, que solo exige caducar descartados y ambiguos sin resolver. |
| **A-P3-3** | **Confirmado como deuda**, sin divergencia de autorización demostrada: ambas bandejas reutilizan `llamada_celular_visible` (`N:644–667`; `I:231–267`). |
| **A-P3-4** | **Confirmado condicionalmente.** Sin política, las comparaciones con NULL dejan pasar (`I:156–175`). No encuentro una vía API para eliminar esa fila: está sembrada, protegida contra DELETE/TRUNCATE y sin grants (`D:121–152`). Añadir rechazo explícito si falta. |

**RIESGOS y test gaps**

**Identidad temporal y excepciones.** En la ruta normal, el helper restaura el valor anterior antes de insertar el evento (`E:48–55,178–193`). Las dependencias transcritas utilizadas durante la suplantación solo leen.

Si la evaluación lanza y la excepción alcanza un bloque `EXCEPTION` exterior que contiene la invocación, PostgreSQL revierte la subtransacción, incluidos sus cambios de GUC. Ese es el caso del bloque de servicio (`I:309–314`). Si el error continúa propagándose, se revierte la transacción. `set_config(..., true)` tampoco persiste en otra transacción. Restaurar NULL como cadena vacía conserva el comportamiento de la definición aportada de `auth.uid()`.

No encuentro aquí un defecto de identidad. Falta probar éxito y excepción capturada, con identidad inicial ausente, presente y obtenida desde `request.jwt.claims`, comprobando también la auditoría posterior.

**GUC de purga.** Un GUC personalizado no es una credencial: quien disponga de ejecución SQL podría fijarlo. Pero eso no concede DELETE ni EXECUTE sobre la purga. Las tablas y la función están revocadas para la API (`D:305–306,552`), y el GUC solo abre la rama DELETE del candado (`D:328–349`). No encuentro una puerta transcrita que permita explotarlo. `pg_trigger_depth()>1` tampoco demuestra por sí solo una cascada, aunque aquí no hay una ruta API para instalar o ejecutar otro trigger que aproveche esa excepción.

**Idempotencia y rotación.** Para eventos guardados, el contador serializa los envíos de una misma asignación y la unicidad protege el origen (`I:159–178`; `D:288`; `E:203–216`). El `FOR SHARE` de la ingesta se coordina con el cierre/rotación mediante `FOR UPDATE`: una vez adquirido, el cierre espera; si el cierre ganó, la ingesta revalida y rechaza. Las excepciones son las descritas en el hallazgo 3.

La rotación crea otra asignación (`N:601–607`): cambia tanto el ámbito de idempotencia como el contador. Reenviar el mismo origen con la clave nueva puede crear otro evento. Es una consecuencia del diseño que debe probarse con la cola durable.

**Edge.** El límite de 4096 bytes se aplica al flujo recibido, sin depender de `Content-Length` (`H:79–90`). El campo `abrir` solo reproduce información enviada por el cliente; no revela una coincidencia.

El 401 uniforme se cumple para solicitudes bien formadas, salvo las carreras indicadas. Con cuerpo inválido, una clave de forma válida pero desconocida recibe 400/413 antes de autenticarse, mientras que una clave ausente recibe 401 (`H:109–122`). Esto distingue forma sintáctica, no existencia de leads. Además, `Date.parse` no constituye un contrato estricto de fecha ni aplica el rango de la base (`H:39`; `E:124–125`).

Las pruebas prioritarias, todas **NOT RUN** en esta revisión, son:

- Comparar secuencias idénticas cambiando únicamente la existencia de un lead ajeno: respuestas, cupo, salud y bandeja.
- Ejecutar carreras con barreras entre autenticación/cierre, autorización/reasignación y ventanas del contador, incluido medianoche de Lima.
- Repetir eventos ignorados, guardados y purgados; incluir envíos concurrentes con contenido distinto.
- Verificar restauración de identidad y actor de auditoría tras éxito y excepciones.
- Comprobar aislamiento por rol y lead activo/inactivo, más cuerpos de 4096/4097 bytes enviados por fragmentos.

**NEXT ACTIONS**

La corrección mínima del oráculo necesita estas propiedades conjuntamente:

1. **Registrar una recepción única para todo origen aceptado**, antes de consultar leads, incluidas llamadas ignoradas y entrantes apagadas. Reservarla atómicamente por `(asignacion_id, evento_origen_id)`.
2. **Aplicar “primer envío gana” a todos los casos.** Los duplicados y conflictos deben terminar normalmente en la base y compartir el 202 externo. El contador y `ultimo_envio_en` deben confirmarse con el mismo criterio para todos.
3. **Conservar esa identidad mientras pueda reutilizarse la credencial.** Purgar un evento no debe liberar su origen. Expirar únicamente las lápidas de ignorados reabriría el ataque compuesto. No guardar número ni hash del payload de los ignorados.
4. Corregir el predicado de leads activos, la autorización del latido, el reloj del contador y la coordinación con reasignaciones. Resolver también la exposición global de ambiguas.
5. Ejecutar los casos anteriores antes de aplicar.

Esto cierra los oráculos deterministas descritos. **No acredita indistinguibilidad temporal:** el primer envío todavía realiza trabajo diferente según las coincidencias y escrituras. Hay que medirlo; si #12 exige ocultar también ese canal, el acuse debe desacoplarse del procesamiento dependiente del lead, con un diseño compatible con la regla de no conservar números sin identificar.

**CONFIDENCE**

Alta en los oráculos, el acceso a soft-borrados y el análisis del GUC. Media en la incidencia práctica de las carreras hasta reproducirlas con los triggers y aislamiento reales.

## Definiciones VIVAS de producción de las que dependen las migraciones
(leídas hoy del banco con huellas idénticas a producción; `auth.uid()` leída de producción)

```sql
-- auth.uid() (PRODUCCIÓN, leída hoy por db query --linked)
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$

CREATE OR REPLACE FUNCTION private.canonizar_contacto(p text)
 RETURNS TABLE(e164 text, clase text, movil boolean)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_bruto text := pg_catalog.btrim(coalesce(p, ''));
  v_digitos text;
  v_internacional boolean;
  v_sin_salida text;
  v_nacional text;
  v_declara_peru boolean;
  v_n text;
  v_sin_cero text;
begin
  if v_bruto = '' then return; end if;
  -- Un correo metido en la casilla del telefono es otro dato en el sitio
  -- equivocado, no un numero roto.
  if pg_catalog.strpos(v_bruto, '@') > 0 then return; end if;

  v_digitos := pg_catalog.regexp_replace(v_bruto, '[^0-9]', '', 'g');
  if v_digitos = '' then return; end if;

  v_internacional := pg_catalog.left(v_bruto, 1) = '+'
                     or pg_catalog.left(v_digitos, 2) = '00';
  v_sin_salida := pg_catalog.regexp_replace(v_digitos, '^00', '');

  v_nacional := case when pg_catalog.left(v_sin_salida, 2) = '51'
                     then pg_catalog.substr(v_sin_salida, 3)
                     else v_sin_salida end;
  -- Todo lo que dice ser peruano se juzga con la vara peruana: si no tiene la
  -- forma exacta NO se cuela por la puerta internacional. Sin esto,
  -- '+51123456789' entraria como numero valido y nadie podria llamarlo nunca.
  v_declara_peru := pg_catalog.left(v_sin_salida, 2) = '51'
                    and pg_catalog.length(v_nacional) >= 8;

  if v_declara_peru or not v_internacional then
    v_n := case when v_declara_peru then v_nacional else v_sin_salida end;

    if v_n ~ '^9[0-9]{8}$' then
      return query select '+51' || v_n, 'celular_pe'::text, true;
      return;
    end if;

    -- ⚠️ UN FIJO EXIGE MARCA. El nacional de un fijo peruano tiene ocho digitos
    -- (Lima 1+siete, provincias 84+seis)… y el DNI peruano TAMBIEN tiene ocho.
    -- Aceptar ocho digitos pelados convertiria todo DNI en un telefono.
    v_sin_cero := case when pg_catalog.left(v_n, 1) = '0'
                       then pg_catalog.substr(v_n, 2) else v_n end;
    if (v_declara_peru or pg_catalog.left(v_n, 1) = '0')
       and v_sin_cero ~ '^[1-8][0-9]{7}$' then
      return query select '+51' || v_sin_cero, 'fijo_pe'::text, false;
      return;
    end if;

    -- Dijo ser peruano y no lo es: se acaba aqui. Y sin `+` no hay pais que
    -- suponer: no se inventa uno.
    if v_declara_peru or not v_internacional then return; end if;
  end if;

  -- E.164 puro. No se valida el codigo de pais contra una lista: mantenerla al
  -- dia en seis capas es peor deuda que aceptar un numero raro.
  if pg_catalog.length(v_sin_salida) between 8 and 15
     and v_sin_salida ~ '^[1-9][0-9]*$' then
    -- Movil o fijo es indecidible fuera de Peru sin libphonenumber. Se asume
    -- MOVIL: esconder el unico canal que hay seria peor que ofrecer uno que
    -- quiza no conteste.
    return query select '+' || v_sin_salida, 'internacional'::text, true;
  end if;
  return;
end;
$function$

CREATE OR REPLACE FUNCTION private.es_lector_global()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with actor as materialized (
    select (select auth.uid()) as uid
  )
  select coalesce(private.rol_crm(a.uid) = 'directorio', false)
    or exists (
      select 1
      from public.perfiles p
      where p.id = a.uid
        and p.activo is true
        and p.rol = 'directorio'
        -- El fallback histórico solo aplica sin membresía. Una fila CRM
        -- inactiva o desalineada es revocación, nunca una segunda puerta.
        and not exists (
          select 1 from crm.equipo e where e.perfil_id = p.id
        )
    )
  from actor a;
$function$

CREATE OR REPLACE FUNCTION private.idem_hash(p_payload jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_payload::text, 'utf8')), 'hex')
$function$

CREATE OR REPLACE FUNCTION private.rol_crm(p_perfil_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo is true and p.activo is true
    and e.rol_crm in (
      'vendedor','supervisor','gerencia','coordinador','directorio'
    )
    -- Directorio es una capacidad de lectura, no un alias operativo de
    -- Gerencia. Una pareja desalineada no recibe ningún rol efectivo.
    and (
      (p.rol = 'directorio' and e.rol_crm = 'directorio')
      or (p.rol is distinct from 'directorio' and e.rol_crm <> 'directorio')
    )
    -- Superadmin Portal gobierna roles CRM; solo una membresía de Gerencia le
    -- suma autoridad operativa. Cualquier otro rol queda fuera del gate global.
    and (p.rol is distinct from 'superadmin' or e.rol_crm = 'gerencia');
$function$

CREATE OR REPLACE FUNCTION private.sla_gestion_permitida(p_actor uuid, p_lead uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p_actor is not null and exists (
    select 1 from crm.leads l
    where l.id=p_lead and l.activo
      and private.rol_crm(p_actor) in ('vendedor','supervisor','gerencia')
      and (private.rol_crm(p_actor)='gerencia' or l.vendedor_id=p_actor
        or (private.rol_crm(p_actor)='supervisor'
          and (l.vendedor_id in (select private.vendedor_ids_visibles(p_actor))
            or (l.vendedor_id is null and l.asignado_supervisor_id in
              (select private.vendedor_ids_visibles(p_actor))))))
  );
$function$

CREATE OR REPLACE FUNCTION private.vendedor_ids_visibles(p_perfil_id uuid)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  v_rol := private.rol_crm(p_perfil_id);

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select e.perfil_id from crm.equipo e; -- incluye históricos
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select e.perfil_id
        from crm.equipo e
        where e.perfil_id = p_perfil_id
        union -- corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select s.perfil_id from subarbol s;
  elsif v_rol = 'vendedor' then
    return next p_perfil_id;
  else
    return; -- coordinador/rol futuro: deny-by-default
  end if;
end;
$function$

-- policy crm_actor_activo_gate (*) on crm.leads: USING ( SELECT private.puede_acceder_crm() AS puede_acceder_crm) WITH CHECK ( SELECT private.puede_acceder_crm() AS puede_acceder_crm)
-- policy leads_select (r) on crm.leads: USING ((activo = true) AND ((vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR ( SELECT private.es_lector_global() AS es_lector_global))) WITH CHECK -
-- policy leads_update (w) on crm.leads: USING ((activo = true) AND ((private.rol_crm(( SELECT auth.uid() AS uid)) = 'gerencia'::text) OR (vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles)) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))))) WITH CHECK (((vendedor_id IS NULL) OR (vendedor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) AND ((asignado_supervisor_id IS NULL) OR (asignado_supervisor_id IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))) AND ((activo = true) OR (private.rol_crm(( SELECT auth.uid() AS uid)) = ANY (ARRAY['supervisor'::text, 'gerencia'::text]))))

```

## Archivo: supabase/migrations/20261001145242_crm_llamadas_celular_datos.sql (748 líneas)
```
   1| -- Llamadas desde el celular · F2-b: DATOS (asignaciones de celulares, eventos de llamada, enlaces
   2| -- a la actividad registrada y política de retención). Plan aprobado (Versión 3), fase F2.2.
   3| --
   4| -- Qué hace:
   5| --   1. crm.llamadas_celular_politica: fila única con las perillas del contrato (guardar o no las
   6| --      llamadas a números sin lead, entrantes activas, días de retención por estado). Las
   7| --      decisiones del 30/09 son DATOS, no código: cambiarlas no exige migración.
   8| --   2. crm.celulares_asignaciones: qué analista tenía cada celular corporativo (C1, C2…) y desde
   9| --      cuándo. La credencial con la que F3 ingerirá llamadas se guarda SOLO como hash sha256 (modelo
  10| --      private.saga_token_hash); la clave en claro se muestra una vez al asignar (F2-c) y no se
  11| --      almacena. Una sola vigencia por etiqueta (índice único parcial + exclusión por rango, el par
  12| --      de crm.lead_asignaciones). Una asignación cerrada es inmutable; rotar = cerrar y abrir otra.
  13| --   3. crm.llamadas_celular_eventos: la evidencia de cada llamada: qué celular, qué número (E.164),
  14| --      cuándo según el celular (ocurrio_en) y según el servidor (recibido_en), dirección, estado
  15| --      técnico y duración. El PAYLOAD es inmutable y la identidad es estable (asignación + id de
  16| --      origen) con hash para la idempotencia (mismo contenido → mismo evento; distinto → conflicto,
  17| --      en F2-c). Aparte va lo que SÍ cambia, con transiciones vigiladas por trigger: identificación
  18| --      (sin_identificar / ambiguo / identificado), atención (por_revisar / requiere_resultado /
  19| --      requiere_devolucion / registrado / descartado_con_motivo), lead, método de asociación y
  20| --      descarte motivado con catálogo cerrado.
  21| --   4. crm.llamadas_celular_enlaces: uno a uno entre un evento y la actividad de llamada que la
  22| --      encuesta registró (tipo llamada_*, metadata.evento = resultado_llamada, mismo lead). Si ese
  23| --      resultado se deshace (metadata.deshecho_en) el enlace puede moverse al resultado corregido;
  24| --      el evento sigue en «registrado»: la encuesta nunca vuelve a saltar sola.
  25| --   5. private.caducar_llamadas_celular + pg_cron: retención por estado según la política. El
  26| --      candado de inmutabilidad solo deja pasar el DELETE bajo el GUC de la purga o en cascada.
  27| --
  28| -- Decisiones provisionales de Jhosep (30/09/2026), que Miguel ratifica o cambia antes de aplicar
  29| -- esto fuera del banco: docs/plans/llamadas-celular/F2-PLAN-CORTO.md, contrato F2.1 (elegibilidad,
  30| -- solo salientes, sin lead no se guarda, descarte con motivo, Deshacer no desenlaza, hora del
  31| -- celular + analista fijo, 30 días, la llamada la trabaja quien hoy tiene el lead).
  32| --
  33| -- Vocabulario: «analista» (rol técnico `vendedor` de crm.equipo; no se renombra).
  34| --
  35| -- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay
  36| -- columna de tenant. El ámbito lo dan crm.equipo y los helpers de private, como en el resto.
  37| --
  38| -- Sin consumidores todavía: ni puertas (F2-c) ni pantalla (F4). RLS activa y SIN policies, sin
  39| -- privilegios para la API (anon, authenticated, service_role): todo acceso llegará por puertas
  40| -- DEFINER con search_path vacío. Auditoría SIN secretos: la purga copia la fila borrada a
  41| -- public.audit_log (que no tiene retención), así que el hash de credencial, el número de teléfono y
  42| -- el hash del payload (que revelaría el número por fuerza bruta) van enmascarados.
  43| --
  44| -- Personas: toda FK hacia public.perfiles o crm.equipo es RESTRICT y tiene su índice. La baja de
  45| -- usuarios (private.usuario_tiene_historial, 20260925180145) detecta el historial por esas FK y
  46| -- conserva la identidad; un SET NULL desatribuiría la llamada. El postflight lo exige.
  47| --
  48| -- Verificación local: npm run test:llamadas:local (banco reducido + oráculo + reversas + mutantes).
  49| --
  50| -- Reversión: ../scripts/llamadas-celular/reversa-datos.sql (conserva los hechos: revoca,
  51| -- desprograma el cron, retira triggers y funciones; las tablas quedan) y
  52| -- ../scripts/llamadas-celular/reversa-datos-total.sql (borra las tablas; se niega si hay filas).
  53| begin;
  54| set local lock_timeout = '5s';
  55| set local statement_timeout = '60s';
  56| 
  57| do $precondicion$
  58| begin
  59|   if to_regclass('crm.equipo') is null or to_regclass('crm.leads') is null
  60|      or to_regclass('crm.actividades') is null or to_regclass('public.perfiles') is null
  61|      or to_regclass('public.audit_log') is null
  62|      or to_regprocedure('private.log_audit_crm()') is null
  63|      or to_regprocedure('private.log_audit_sin_secretos()') is null
  64|      or to_regprocedure('private.enmascarar_claves(jsonb,text[])') is null
  65|      or to_regprocedure('private.tablas_sin_rastro()') is null
  66|      or to_regprocedure('private.normalizar_telefono(text)') is null
  67|      or to_regprocedure('private.canonizar_contacto(text)') is null
  68|      or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null
  69|      or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
  70|      or to_regprocedure('private.rol_crm(uuid)') is null
  71|      or to_regprocedure('auth.uid()') is null then
  72|     raise exception 'LLAMADAS_CELULAR: faltan dependencias del catálogo (equipo, leads, actividades, auditoría, canonización o ámbito)';
  73|   end if;
  74|   if not exists (select 1 from pg_catalog.pg_extension where extname = 'btree_gist') then
  75|     raise exception 'LLAMADAS_CELULAR: falta la extensión btree_gist (la instaló 20260717212639)';
  76|   end if;
  77|   if to_regclass('crm.llamadas_celular_politica') is not null
  78|      or to_regclass('crm.celulares_asignaciones') is not null
  79|      or to_regclass('crm.llamadas_celular_eventos') is not null
  80|      or to_regclass('crm.llamadas_celular_enlaces') is not null
  81|      or to_regprocedure('private.caducar_llamadas_celular()') is not null
  82|      or to_regprocedure('private.trg_llamadas_celular_sin_vaciar()') is not null then
  83|     raise exception 'LLAMADAS_CELULAR: los objetos ya existen; no se sobrescriben';
  84|   end if;
  85| end;
  86| $precondicion$;
  87| 
  88| -- ── 0. Candado común contra TRUNCATE (por sentencia) ────────────────────────────────────────
  89| create function private.trg_llamadas_celular_sin_vaciar()
  90| returns trigger
  91| language plpgsql
  92| security definer
  93| set search_path to ''
  94| as $function$
  95| begin
  96|   raise exception using errcode = '42501',
  97|     message = pg_catalog.format('%s no se vacía: es evidencia de llamadas', tg_table_name);
  98| end;
  99| $function$;
 100| revoke all on function private.trg_llamadas_celular_sin_vaciar() from public, anon, authenticated, service_role;
 101| 
 102| -- ── 1. Política (fila única) ─────────────────────────────────────────────────────────────────
 103| create table crm.llamadas_celular_politica (
 104|   singleton                      boolean primary key default true
 105|                                  constraint llamadas_celular_politica_unica check (singleton),
 106|   guardar_sin_identificar        boolean not null default false,
 107|   entrantes_activas              boolean not null default false,
 108|   dias_retencion_descartados     integer not null default 30
 109|                                  constraint llamadas_celular_politica_descartados_rango
 110|                                  check (dias_retencion_descartados between 1 and 365),
 111|   dias_retencion_sin_resolver    integer not null default 30
 112|                                  constraint llamadas_celular_politica_sin_resolver_rango
 113|                                  check (dias_retencion_sin_resolver between 1 and 365),
 114|   dias_retencion_sin_identificar integer not null default 30
 115|                                  constraint llamadas_celular_politica_sin_identificar_rango
 116|                                  check (dias_retencion_sin_identificar between 1 and 365),
 117|   actualizado_por                uuid references public.perfiles(id) on delete restrict,
 118|   creado_en                      timestamptz not null default now(),
 119|   actualizado_en                 timestamptz not null default now()
 120| );
 121| alter table crm.llamadas_celular_politica enable row level security;
 122| revoke all on crm.llamadas_celular_politica from public, anon, authenticated, service_role;
 123| create index llamadas_celular_politica_actualizado_por_idx on crm.llamadas_celular_politica (actualizado_por);
 124| 
 125| create function private.trg_llamadas_celular_politica_candado()
 126| returns trigger
 127| language plpgsql
 128| security definer
 129| set search_path to ''
 130| as $function$
 131| begin
 132|   if tg_op = 'DELETE' then
 133|     raise exception using errcode = '42501', message = 'La política de llamadas no se borra: se ajusta';
 134|   end if;
 135|   new.singleton := true;
 136|   new.creado_en := old.creado_en;
 137|   new.actualizado_en := pg_catalog.now();
 138|   return new;
 139| end;
 140| $function$;
 141| revoke all on function private.trg_llamadas_celular_politica_candado() from public, anon, authenticated, service_role;
 142| create trigger trg_llamadas_celular_politica_00_candado
 143|   before update or delete on crm.llamadas_celular_politica
 144|   for each row execute function private.trg_llamadas_celular_politica_candado();
 145| create trigger trg_llamadas_celular_politica_00_sin_vaciar
 146|   before truncate on crm.llamadas_celular_politica
 147|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 148| create trigger trg_audit_llamadas_celular_politica
 149|   after insert or update or delete on crm.llamadas_celular_politica
 150|   for each row execute function private.log_audit_crm();
 151| 
 152| insert into crm.llamadas_celular_politica (singleton) values (true);
 153| 
 154| -- ── 2. Asignaciones de celulares ─────────────────────────────────────────────────────────────
 155| create table crm.celulares_asignaciones (
 156|   id               uuid primary key default gen_random_uuid(),
 157|   etiqueta         text not null
 158|                    constraint celulares_asignaciones_etiqueta_valida check (etiqueta ~ '^C[1-9][0-9]{0,2}$'),
 159|   analista_id      uuid not null references crm.equipo(perfil_id) on delete restrict,
 160|   credencial_hash  text not null
 161|                    constraint celulares_asignaciones_credencial_hash_valido check (credencial_hash ~ '^[0-9a-f]{64}$'),
 162|   vigente_desde    timestamptz not null default now(),
 163|   vigente_hasta    timestamptz,
 164|   motivo_cierre    text
 165|                    constraint celulares_asignaciones_motivo_cierre_valido
 166|                    check (motivo_cierre is null
 167|                           or motivo_cierre in ('rotacion', 'baja_analista', 'extravio', 'reemplazo', 'otro')),
 168|   creado_por       uuid references public.perfiles(id) on delete restrict,
 169|   creado_en        timestamptz not null default now(),
 170|   actualizado_en   timestamptz not null default now(),
 171|   constraint celulares_asignaciones_vigencia_coherente
 172|     check (vigente_hasta is null or vigente_hasta > vigente_desde),
 173|   constraint celulares_asignaciones_cierre_coherente
 174|     check ((vigente_hasta is null) = (motivo_cierre is null)),
 175|   -- El par de crm.lead_asignaciones: una sola vigencia abierta y ningún solape histórico.
 176|   constraint celulares_asignaciones_sin_solape
 177|     exclude using gist (
 178|       etiqueta with =,
 179|       tstzrange(vigente_desde, coalesce(vigente_hasta, 'infinity'::timestamptz), '[)') with &&
 180|     )
 181| );
 182| alter table crm.celulares_asignaciones enable row level security;
 183| revoke all on crm.celulares_asignaciones from public, anon, authenticated, service_role;
 184| create unique index celulares_asignaciones_etiqueta_vigente_uq
 185|   on crm.celulares_asignaciones (etiqueta) where vigente_hasta is null;
 186| create unique index celulares_asignaciones_credencial_uq
 187|   on crm.celulares_asignaciones (credencial_hash);
 188| create index celulares_asignaciones_analista_idx
 189|   on crm.celulares_asignaciones (analista_id, vigente_desde desc);
 190| create index celulares_asignaciones_creado_por_idx
 191|   on crm.celulares_asignaciones (creado_por);
 192| 
 193| create function private.trg_celulares_asignaciones_candado()
 194| returns trigger
 195| language plpgsql
 196| security definer
 197| set search_path to ''
 198| as $function$
 199| begin
 200|   if tg_op = 'DELETE' then
 201|     raise exception using errcode = '42501',
 202|       message = 'Una asignación de celular no se borra: se cierra su vigencia';
 203|   end if;
 204|   if old.vigente_hasta is not null then
 205|     raise exception using errcode = '42501', message = 'Una asignación de celular cerrada es inmutable';
 206|   end if;
 207|   if new.id <> old.id or new.etiqueta <> old.etiqueta or new.analista_id <> old.analista_id
 208|      or new.credencial_hash <> old.credencial_hash or new.vigente_desde <> old.vigente_desde
 209|      or new.creado_por is distinct from old.creado_por or new.creado_en <> old.creado_en then
 210|     raise exception using errcode = '42501',
 211|       message = 'De una asignación de celular solo se cierra la vigencia; lo demás es inmutable';
 212|   end if;
 213|   if new.vigente_hasta is null then
 214|     raise exception using errcode = '22023',
 215|       message = 'Para cambiar una asignación de celular se cierra la vigente y se abre otra';
 216|   end if;
 217|   new.actualizado_en := pg_catalog.now();
 218|   return new;
 219| end;
 220| $function$;
 221| revoke all on function private.trg_celulares_asignaciones_candado() from public, anon, authenticated, service_role;
 222| create trigger trg_celulares_asignaciones_00_candado
 223|   before update or delete on crm.celulares_asignaciones
 224|   for each row execute function private.trg_celulares_asignaciones_candado();
 225| create trigger trg_celulares_asignaciones_00_sin_vaciar
 226|   before truncate on crm.celulares_asignaciones
 227|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 228| create trigger trg_audit_celulares_asignaciones
 229|   after insert or update or delete on crm.celulares_asignaciones
 230|   for each row execute function private.log_audit_sin_secretos('credencial_hash');
 231| 
 232| -- ── 3. Eventos de llamada ────────────────────────────────────────────────────────────────────
 233| create table crm.llamadas_celular_eventos (
 234|   id                      uuid primary key default gen_random_uuid(),
 235|   asignacion_id           uuid not null references crm.celulares_asignaciones(id) on delete restrict,
 236|   analista_id             uuid not null references crm.equipo(perfil_id) on delete restrict,
 237|   evento_origen_id        text not null
 238|                           constraint llamadas_celular_eventos_origen_valido
 239|                           check (evento_origen_id ~ '^[A-Za-z0-9._:+-]{4,120}$'),
 240|   hash_payload            text not null
 241|                           constraint llamadas_celular_eventos_hash_valido check (hash_payload ~ '^[0-9a-f]{64}$'),
 242|   numero_canonico         text
 243|                           constraint llamadas_celular_eventos_numero_e164
 244|                           check (numero_canonico is null or numero_canonico ~ '^\+[1-9][0-9]{7,14}$'),
 245|   direccion               text not null default 'desconocida'
 246|                           constraint llamadas_celular_eventos_direccion_valida
 247|                           check (direccion in ('saliente', 'entrante', 'desconocida')),
 248|   estado_tecnico          text not null default 'desconocido'
 249|                           constraint llamadas_celular_eventos_estado_tecnico_valido
 250|                           check (estado_tecnico in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido')),
 251|   duracion_seg            integer
 252|                           constraint llamadas_celular_eventos_duracion_valida
 253|                           check (duracion_seg is null or duracion_seg between 0 and 86400),
 254|   ocurrio_en              timestamptz
 255|                           constraint llamadas_celular_eventos_ocurrio_en_cuerdo
 256|                           check (ocurrio_en is null
 257|                                  or (ocurrio_en >= timestamptz '2026-01-01 00:00Z'
 258|                                      and ocurrio_en < timestamptz '2100-01-01 00:00Z')),
 259|   recibido_en             timestamptz not null default now(),
 260|   calidad                 jsonb not null default '{}'::jsonb
 261|                           constraint llamadas_celular_eventos_calidad_acotada
 262|                           check (jsonb_typeof(calidad) = 'object' and length(calidad::text) <= 2000),
 263|   identificacion          text not null
 264|                           constraint llamadas_celular_eventos_identificacion_valida
 265|                           check (identificacion in ('sin_identificar', 'ambiguo', 'identificado')),
 266|   atencion                text not null
 267|                           constraint llamadas_celular_eventos_atencion_valida
 268|                           check (atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion',
 269|                                               'registrado', 'descartado_con_motivo')),
 270|   lead_id                 uuid references crm.leads(id) on delete cascade,
 271|   metodo_asociacion       text
 272|                           constraint llamadas_celular_eventos_metodo_valido
 273|                           check (metodo_asociacion is null
 274|                                  or metodo_asociacion in ('exacto', 'manual', 'propuesto_confirmado')),
 275|   asociado_por            uuid references public.perfiles(id) on delete restrict,
 276|   asociado_en             timestamptz,
 277|   motivo_descarte         text
 278|                           constraint llamadas_celular_eventos_motivo_descarte_valido
 279|                           check (motivo_descarte is null
 280|                                  or motivo_descarte in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro')),
 281|   motivo_descarte_detalle text
 282|                           constraint llamadas_celular_eventos_detalle_acotado
 283|                           check (motivo_descarte_detalle is null or length(motivo_descarte_detalle) <= 300),
 284|   descartado_por          uuid references public.perfiles(id) on delete restrict,
 285|   descartado_en           timestamptz,
 286|   creado_en               timestamptz not null default now(),
 287|   actualizado_en          timestamptz not null default now(),
 288|   constraint llamadas_celular_eventos_origen_unico unique (asignacion_id, evento_origen_id),
 289|   constraint llamadas_celular_eventos_identificado_con_lead
 290|     check ((identificacion = 'identificado') = (lead_id is not null)),
 291|   constraint llamadas_celular_eventos_asociacion_coherente
 292|     check ((lead_id is null) = (metodo_asociacion is null)
 293|            and (lead_id is null) = (asociado_en is null)
 294|            and (metodo_asociacion is null or metodo_asociacion = 'exacto' or asociado_por is not null)),
 295|   constraint llamadas_celular_eventos_atencion_coherente
 296|     check ((atencion in ('requiere_resultado', 'registrado') and identificacion = 'identificado')
 297|            or (atencion = 'requiere_devolucion' and identificacion = 'identificado' and direccion = 'entrante')
 298|            or atencion in ('por_revisar', 'descartado_con_motivo')),
 299|   constraint llamadas_celular_eventos_descarte_coherente
 300|     check ((atencion = 'descartado_con_motivo') = (motivo_descarte is not null)
 301|            and (atencion = 'descartado_con_motivo') = (descartado_en is not null)
 302|            and (motivo_descarte is distinct from 'otro'
 303|                 or length(btrim(coalesce(motivo_descarte_detalle, ''))) >= 3))
 304| );
 305| alter table crm.llamadas_celular_eventos enable row level security;
 306| revoke all on crm.llamadas_celular_eventos from public, anon, authenticated, service_role;
 307| create index llamadas_celular_eventos_analista_atencion_idx
 308|   on crm.llamadas_celular_eventos (analista_id, atencion, recibido_en desc);
 309| create index llamadas_celular_eventos_lead_idx
 310|   on crm.llamadas_celular_eventos (lead_id, recibido_en desc);
 311| create index llamadas_celular_eventos_numero_idx
 312|   on crm.llamadas_celular_eventos (numero_canonico) where numero_canonico is not null;
 313| create index llamadas_celular_eventos_recibido_idx
 314|   on crm.llamadas_celular_eventos (recibido_en);
 315| -- Cada FK con su índice (convención de la casa: sin INFO unindexed_foreign_keys).
 316| create index llamadas_celular_eventos_asociado_por_idx
 317|   on crm.llamadas_celular_eventos (asociado_por);
 318| create index llamadas_celular_eventos_descartado_por_idx
 319|   on crm.llamadas_celular_eventos (descartado_por);
 320| 
 321| create function private.trg_llamadas_celular_eventos_candado()
 322| returns trigger
 323| language plpgsql
 324| security definer
 325| set search_path to ''
 326| as $function$
 327| begin
 328|   if tg_op = 'DELETE' then
 329|     -- Solo la purga programada (GUC de transacción) o una cascada (el lead se elimina: la
 330|     -- evidencia de su número se va con él) pueden borrar. Un DELETE directo muere aquí.
 331|     if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
 332|        or pg_catalog.pg_trigger_depth() > 1 then
 333|       return old;
 334|     end if;
 335|     raise exception using errcode = '42501',
 336|       message = 'Una llamada del celular no se borra a mano: la retira la retención programada';
 337|   end if;
 338| 
 339|   -- El payload es la evidencia: inmutable aunque lo escriba el núcleo.
 340|   if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.analista_id <> old.analista_id
 341|      or new.evento_origen_id <> old.evento_origen_id or new.hash_payload <> old.hash_payload
 342|      or new.numero_canonico is distinct from old.numero_canonico
 343|      or new.direccion <> old.direccion or new.estado_tecnico <> old.estado_tecnico
 344|      or new.duracion_seg is distinct from old.duracion_seg
 345|      or new.ocurrio_en is distinct from old.ocurrio_en or new.recibido_en <> old.recibido_en
 346|      or new.calidad <> old.calidad or new.creado_en <> old.creado_en then
 347|     raise exception using errcode = '42501',
 348|       message = 'El contenido de una llamada del celular es inmutable; solo cambian su identificación y su atención';
 349|   end if;
 350| 
 351|   -- Identificación: solo avanza (sin_identificar → ambiguo → identificado). El lead se fija una
 352|   -- vez; se corrige únicamente mientras la llamada esté por atender (antes de registrar o descartar).
 353|   if (case new.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end)
 354|      < (case old.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end) then
 355|     raise exception using errcode = '42501',
 356|       message = pg_catalog.format('La identificación de una llamada solo avanza: %s → %s',
 357|                                   old.identificacion, new.identificacion);
 358|   end if;
 359|   if old.lead_id is not null and new.lead_id is distinct from old.lead_id
 360|      and old.atencion not in ('por_revisar', 'requiere_resultado', 'requiere_devolucion') then
 361|     raise exception using errcode = '42501',
 362|       message = 'Una llamada registrada o descartada no cambia de lead';
 363|   end if;
 364| 
 365|   -- Atención: transiciones permitidas. registrado y descartado_con_motivo son finales.
 366|   if new.atencion <> old.atencion then
 367|     if (old.atencion = 'por_revisar'
 368|           and new.atencion in ('requiere_resultado', 'requiere_devolucion', 'descartado_con_motivo'))
 369|        or (old.atencion in ('requiere_resultado', 'requiere_devolucion')
 370|           and new.atencion in ('registrado', 'descartado_con_motivo', 'por_revisar')) then
 371|       null;
 372|     else
 373|       raise exception using errcode = '42501',
 374|         message = pg_catalog.format('Transición no permitida de la llamada: %s → %s', old.atencion, new.atencion);
 375|     end if;
 376|   end if;
 377|   -- Un descarte sellado no se reescribe (motivo, quién, cuándo).
 378|   if old.atencion = 'descartado_con_motivo'
 379|      and (new.motivo_descarte is distinct from old.motivo_descarte
 380|           or new.motivo_descarte_detalle is distinct from old.motivo_descarte_detalle
 381|           or new.descartado_en is distinct from old.descartado_en) then
 382|     raise exception using errcode = '42501', message = 'El motivo de un descarte no se reescribe';
 383|   end if;
 384| 
 385|   new.actualizado_en := pg_catalog.now();
 386|   return new;
 387| end;
 388| $function$;
 389| revoke all on function private.trg_llamadas_celular_eventos_candado() from public, anon, authenticated, service_role;
 390| create trigger trg_llamadas_celular_eventos_00_candado
 391|   before update or delete on crm.llamadas_celular_eventos
 392|   for each row execute function private.trg_llamadas_celular_eventos_candado();
 393| create trigger trg_llamadas_celular_eventos_00_sin_vaciar
 394|   before truncate on crm.llamadas_celular_eventos
 395|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 396| -- El hash del payload también se enmascara: con el resto de la fila a la vista, el número es el
 397| -- único dato desconocido y un sha256 de nueve dígitos se revierte por fuerza bruta en segundos.
 398| create trigger trg_audit_llamadas_celular_eventos
 399|   after insert or update or delete on crm.llamadas_celular_eventos
 400|   for each row execute function private.log_audit_sin_secretos('numero_canonico', 'hash_payload');
 401| 
 402| -- ── 4. Enlace evento ↔ actividad registrada (uno a uno) ─────────────────────────────────────
 403| create table crm.llamadas_celular_enlaces (
 404|   id             uuid primary key default gen_random_uuid(),
 405|   evento_id      uuid not null references crm.llamadas_celular_eventos(id) on delete cascade
 406|                  constraint llamadas_celular_enlaces_evento_uq unique,
 407|   actividad_id   uuid references crm.actividades(id) on delete set null
 408|                  constraint llamadas_celular_enlaces_actividad_uq unique,
 409|   lead_id        uuid not null references crm.leads(id) on delete cascade,
 410|   enlazado_por   uuid references public.perfiles(id) on delete restrict,
 411|   creado_en      timestamptz not null default now(),
 412|   actualizado_en timestamptz not null default now()
 413| );
 414| alter table crm.llamadas_celular_enlaces enable row level security;
 415| revoke all on crm.llamadas_celular_enlaces from public, anon, authenticated, service_role;
 416| create index llamadas_celular_enlaces_lead_idx
 417|   on crm.llamadas_celular_enlaces (lead_id);
 418| create index llamadas_celular_enlaces_enlazado_por_idx
 419|   on crm.llamadas_celular_enlaces (enlazado_por);
 420| 
 421| create function private.trg_llamadas_celular_enlaces_candado()
 422| returns trigger
 423| language plpgsql
 424| security definer
 425| set search_path to ''
 426| as $function$
 427| declare
 428|   v_act crm.actividades%rowtype;
 429|   v_ev  crm.llamadas_celular_eventos%rowtype;
 430|   v_deshecha boolean;
 431| begin
 432|   if tg_op = 'DELETE' then
 433|     if pg_catalog.pg_trigger_depth() > 1 then
 434|       return old; -- cascada: se fue el evento o el lead
 435|     end if;
 436|     raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
 437|   end if;
 438| 
 439|   if tg_op = 'UPDATE' then
 440|     -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
 441|     -- aceptada, y solo si no cambia nada más.
 442|     if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
 443|        and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
 444|          = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
 445|       new.actualizado_en := pg_catalog.now();
 446|       return new;
 447|     end if;
 448|     if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
 449|        or new.creado_en <> old.creado_en then
 450|       raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento ni de lead';
 451|     end if;
 452|     if new.actividad_id is distinct from old.actividad_id then
 453|       if new.actividad_id is null then
 454|         raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
 455|       end if;
 456|       if old.actividad_id is not null then
 457|         select (a.metadata ? 'deshecho_en') into v_deshecha
 458|         from crm.actividades a where a.id = old.actividad_id;
 459|         if not coalesce(v_deshecha, false) then
 460|           raise exception using errcode = '42501',
 461|             message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
 462|         end if;
 463|       end if;
 464|     end if;
 465|   elsif new.actividad_id is null then
 466|     raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
 467|   end if;
 468| 
 469|   if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
 470|     select * into v_act from crm.actividades a where a.id = new.actividad_id;
 471|     if not found then
 472|       raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
 473|     end if;
 474|     if v_act.lead_id <> new.lead_id then
 475|       raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
 476|     end if;
 477|     if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 478|        or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 479|       raise exception using errcode = '22023',
 480|         message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
 481|     end if;
 482|   end if;
 483| 
 484|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
 485|   if not found then
 486|     raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
 487|   end if;
 488|   if v_ev.lead_id is distinct from new.lead_id then
 489|     raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
 490|   end if;
 491| 
 492|   if tg_op = 'UPDATE' then
 493|     new.actualizado_en := pg_catalog.now();
 494|   end if;
 495|   return new;
 496| end;
 497| $function$;
 498| revoke all on function private.trg_llamadas_celular_enlaces_candado() from public, anon, authenticated, service_role;
 499| create trigger trg_llamadas_celular_enlaces_00_candado
 500|   before insert or update or delete on crm.llamadas_celular_enlaces
 501|   for each row execute function private.trg_llamadas_celular_enlaces_candado();
 502| create trigger trg_llamadas_celular_enlaces_00_sin_vaciar
 503|   before truncate on crm.llamadas_celular_enlaces
 504|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 505| create trigger trg_audit_llamadas_celular_enlaces
 506|   after insert or update or delete on crm.llamadas_celular_enlaces
 507|   for each row execute function private.log_audit_crm();
 508| 
 509| -- ── 5. Retención programada ──────────────────────────────────────────────────────────────────
 510| create function private.caducar_llamadas_celular()
 511| returns integer
 512| language plpgsql
 513| security definer
 514| set search_path to ''
 515| as $function$
 516| declare
 517|   v_pol crm.llamadas_celular_politica%rowtype;
 518|   v_n integer := 0;
 519|   v_parcial integer;
 520| begin
 521|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 522|   if not found then
 523|     return 0;
 524|   end if;
 525|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);
 526| 
 527|   -- Descartadas con motivo: el motivo y quién lo dio quedan en la auditoría (sin el número).
 528|   delete from crm.llamadas_celular_eventos e
 529|    where e.atencion = 'descartado_con_motivo'
 530|      and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
 531|   get diagnostics v_parcial = row_count;
 532|   v_n := v_n + v_parcial;
 533| 
 534|   -- Ambiguas (varios leads con el mismo número) que nadie resolvió.
 535|   delete from crm.llamadas_celular_eventos e
 536|    where e.identificacion = 'ambiguo' and e.atencion = 'por_revisar'
 537|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
 538|   get diagnostics v_parcial = row_count;
 539|   v_n := v_n + v_parcial;
 540| 
 541|   -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
 542|   delete from crm.llamadas_celular_eventos e
 543|    where e.identificacion = 'sin_identificar' and e.atencion = 'por_revisar'
 544|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
 545|   get diagnostics v_parcial = row_count;
 546|   v_n := v_n + v_parcial;
 547| 
 548|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
 549|   return v_n;
 550| end;
 551| $function$;
 552| revoke all on function private.caducar_llamadas_celular() from public, anon, authenticated, service_role;
 553| 
 554| do $reloj$
 555| begin
 556|   if to_regprocedure('cron.schedule(text,text,text)') is null then
 557|     -- Banco local sin pg_cron: no es un fallo, aquí no hay reloj que programar.
 558|     raise notice 'pg_cron no está disponible: no se programa la retención de llamadas del celular.';
 559|     return;
 560|   end if;
 561|   -- `cron.schedule` reemplaza por nombre: reaplicar es idempotente. 06:23 UTC ≈ 01:23 Lima.
 562|   perform cron.schedule(
 563|     'crm-llamadas-celular-caducidad',
 564|     '23 6 * * *',
 565|     'select private.caducar_llamadas_celular();'
 566|   );
 567| end;
 568| $reloj$;
 569| 
 570| -- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
 571| comment on table crm.llamadas_celular_politica is
 572|   'Perillas del contrato de llamadas desde el celular (F2, decisiones provisionales de Jhosep 30/09/2026, pendientes de Miguel). Fila única. Solo gerencia la ajusta, por puerta (F2-c). Sin columna de tenant: CRM de una sola empresa (excepción documentada).';
 573| comment on column crm.llamadas_celular_politica.singleton is 'Siempre true: garantiza una sola fila.';
 574| comment on column crm.llamadas_celular_politica.guardar_sin_identificar is 'false (decisión 3): una llamada a un número que no es de ningún lead no se guarda; la ingesta responde «ignorado». true: se guarda como sin_identificar y vive dias_retencion_sin_identificar (lo que pide F5 del plan).';
 575| comment on column crm.llamadas_celular_politica.entrantes_activas is 'false (decisión 2, propuesta #8): solo salientes en el piloto; una entrante perdida no pasa a requiere_devolucion.';
 576| comment on column crm.llamadas_celular_politica.dias_retencion_descartados is 'Días que vive una llamada descartada con motivo antes de la purga (30, decisión 6).';
 577| comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada ambigua (varios leads con el mismo número) que nadie resolvió (30, decisión 6).';
 578| comment on column crm.llamadas_celular_politica.dias_retencion_sin_identificar is 'Días que vive una llamada sin identificar, solo si guardar_sin_identificar está encendida.';
 579| comment on column crm.llamadas_celular_politica.actualizado_por is 'Quién ajustó la política por última vez (perfil de gerencia). FK con RESTRICT: la baja de usuarios (private.usuario_tiene_historial) detecta el historial y conserva la identidad; nunca SET NULL.';
 580| comment on column crm.llamadas_celular_politica.creado_en is 'Sembrada por la migración.';
 581| comment on column crm.llamadas_celular_politica.actualizado_en is 'Último ajuste (lo sella el trigger).';
 582| 
 583| comment on table crm.celulares_asignaciones is
 584|   'Qué analista tenía cada celular corporativo (C1, C2…) y en qué periodo. Actor histórico de las llamadas: no se sobrescribe; rotar = cerrar la vigencia y abrir otra fila. Una sola vigencia por etiqueta (índice parcial + exclusión por rango). DATO SENSIBLE: credencial_hash (hash de la credencial de ingesta; la clave en claro nunca se guarda). Sin columna de tenant: CRM de una sola empresa.';
 585| comment on column crm.celulares_asignaciones.id is 'Identificador de la asignación.';
 586| comment on column crm.celulares_asignaciones.etiqueta is 'Etiqueta del celular en el piloto: C1, C2… (C + número).';
 587| comment on column crm.celulares_asignaciones.analista_id is 'Analista que tenía el celular (crm.equipo). Histórico e inmutable.';
 588| comment on column crm.celulares_asignaciones.credencial_hash is 'sha256 en hex de la credencial que el celular presenta al ingerir (F3). Única. DATO SENSIBLE: enmascarado en la auditoría.';
 589| comment on column crm.celulares_asignaciones.vigente_desde is 'Inicio de la vigencia.';
 590| comment on column crm.celulares_asignaciones.vigente_hasta is 'Fin de la vigencia; null = vigente. Se fija una sola vez.';
 591| comment on column crm.celulares_asignaciones.motivo_cierre is 'Por qué se cerró: rotacion, baja_analista, extravio, reemplazo u otro. Obligatorio al cerrar.';
 592| comment on column crm.celulares_asignaciones.creado_por is 'Quién asignó el celular (gerencia). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
 593| comment on column crm.celulares_asignaciones.creado_en is 'Alta de la fila.';
 594| comment on column crm.celulares_asignaciones.actualizado_en is 'Último cambio (solo el cierre).';
 595| 
 596| comment on table crm.llamadas_celular_eventos is
 597|   'Evidencia de cada llamada hecha desde un celular corporativo (F2). Payload inmutable (celular, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración, hash) e identidad estable (asignación + id de origen) para la idempotencia. Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría junto con hash_payload, que lo revelaría por fuerza bruta; retención por crm.llamadas_celular_politica). Sin columna de tenant: CRM de una sola empresa.';
 598| comment on column crm.llamadas_celular_eventos.id is 'Identificador del evento.';
 599| comment on column crm.llamadas_celular_eventos.asignacion_id is 'Asignación de celular vigente cuando se recibió (crm.celulares_asignaciones).';
 600| comment on column crm.llamadas_celular_eventos.analista_id is 'Analista que tenía el celular en ese momento (resuelto de la asignación). Histórico: no cambia aunque el lead se reasigne (decisiones 5 y 7).';
 601| comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Identificador estable que genera el celular para esta llamada; con asignacion_id forma la identidad del evento.';
 602| comment on column crm.llamadas_celular_eventos.hash_payload is 'sha256 en hex del payload canónico: mismo origen + mismo hash → mismo evento; distinto hash → conflicto (núcleo, F2-c).';
 603| comment on column crm.llamadas_celular_eventos.numero_canonico is 'Número marcado en E.164 (las dos reglas canónicas del CRM); null si el celular no lo entregó o no es un teléfono. DATO PERSONAL.';
 604| comment on column crm.llamadas_celular_eventos.direccion is 'saliente, entrante o desconocida. En el piloto solo salientes (perilla entrantes_activas).';
 605| comment on column crm.llamadas_celular_eventos.estado_tecnico is 'conectada, no_atendida, rechazada, cancelada o desconocido: lo que el celular supo decir; nunca se infiere del cero.';
 606| comment on column crm.llamadas_celular_eventos.duracion_seg is 'Duración en segundos si el celular la entregó; null = desconocida (cero no prueba nada).';
 607| comment on column crm.llamadas_celular_eventos.ocurrio_en is 'Hora de la llamada según el celular (decisión 5); null si no vino. recibido_en la contrasta.';
 608| comment on column crm.llamadas_celular_eventos.recibido_en is 'Hora del servidor al recibir el evento. SLA y retención se miden con esta.';
 609| comment on column crm.llamadas_celular_eventos.calidad is 'Observaciones acotadas de la ingesta (número inválido u oculto, reloj desfasado…). Objeto JSON ≤ 2000 caracteres.';
 610| comment on column crm.llamadas_celular_eventos.identificacion is 'sin_identificar (ningún lead; solo si la perilla lo permite), ambiguo (varios leads vivos con el número) o identificado (lead_id fijado). Solo avanza.';
 611| comment on column crm.llamadas_celular_eventos.atencion is 'por_revisar, requiere_resultado, requiere_devolucion, registrado o descartado_con_motivo. Las dos últimas son finales; la elegibilidad real se re-evalúa al leer (decisión 1).';
 612| comment on column crm.llamadas_celular_eventos.lead_id is 'Lead al que se asoció la llamada; se fija una vez y solo se corrige mientras está por atender. Se va con el lead si este se elimina.';
 613| comment on column crm.llamadas_celular_eventos.metodo_asociacion is 'exacto (match por número al ingerir), manual (el analista eligió) o propuesto_confirmado (sugerencia aceptada).';
 614| comment on column crm.llamadas_celular_eventos.asociado_por is 'Quién asoció manualmente o confirmó la propuesta; null en el match exacto. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
 615| comment on column crm.llamadas_celular_eventos.asociado_en is 'Cuándo quedó asociada al lead.';
 616| comment on column crm.llamadas_celular_eventos.motivo_descarte is 'Catálogo cerrado (decisión 3): no_comercial, personal, numero_de_prueba, error_captura u otro (con detalle).';
 617| comment on column crm.llamadas_celular_eventos.motivo_descarte_detalle is 'Texto del motivo cuando es otro (≥ 3 caracteres visibles); opcional en los demás.';
 618| comment on column crm.llamadas_celular_eventos.descartado_por is 'Quién descartó la llamada. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
 619| comment on column crm.llamadas_celular_eventos.descartado_en is 'Cuándo se descartó; a partir de aquí corre dias_retencion_descartados.';
 620| comment on column crm.llamadas_celular_eventos.creado_en is 'Alta de la fila (igual a recibido_en salvo cargas históricas).';
 621| comment on column crm.llamadas_celular_eventos.actualizado_en is 'Último cambio de identificación o atención (lo sella el trigger).';
 622| 
 623| comment on table crm.llamadas_celular_enlaces is
 624|   'Enlace uno a uno entre una llamada del celular y la actividad de llamada que la encuesta registró (tipo llamada_*, metadata.evento = resultado_llamada, mismo lead). Si ese resultado se deshace (metadata.deshecho_en) el enlace puede moverse al resultado corregido; nunca se desenlaza ni se borra a mano. Sin columna de tenant: CRM de una sola empresa.';
 625| comment on column crm.llamadas_celular_enlaces.id is 'Identificador del enlace.';
 626| comment on column crm.llamadas_celular_enlaces.evento_id is 'La llamada enlazada (única: un evento tiene a lo sumo un enlace).';
 627| comment on column crm.llamadas_celular_enlaces.actividad_id is 'La actividad registrada por la encuesta (única entre enlaces). null solo si la actividad se eliminó.';
 628| comment on column crm.llamadas_celular_enlaces.lead_id is 'Lead de la llamada y de la actividad (coinciden por trigger).';
 629| comment on column crm.llamadas_celular_enlaces.enlazado_por is 'Quién registró el resultado que creó o movió el enlace (con ámbito sobre el lead en ese momento). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';
 630| comment on column crm.llamadas_celular_enlaces.creado_en is 'Cuándo se enlazó por primera vez.';
 631| comment on column crm.llamadas_celular_enlaces.actualizado_en is 'Último movimiento del enlace (lo sella el trigger).';
 632| 
 633| comment on function private.trg_llamadas_celular_sin_vaciar() is
 634|   'Candado contra TRUNCATE de las tablas de llamadas del celular. SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
 635| comment on function private.trg_llamadas_celular_politica_candado() is
 636|   'Candado de crm.llamadas_celular_politica: sin DELETE; el UPDATE conserva singleton y creado_en y sella actualizado_en. SECURITY DEFINER por coherencia; no lee datos.';
 637| comment on function private.trg_celulares_asignaciones_candado() is
 638|   'Candado de crm.celulares_asignaciones: sin DELETE; de una asignación abierta solo se cierra la vigencia (vigente_hasta + motivo_cierre); una cerrada es inmutable. SECURITY DEFINER por coherencia; no lee datos.';
 639| comment on function private.trg_llamadas_celular_eventos_candado() is
 640|   'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. SECURITY DEFINER por coherencia; no lee otras tablas.';
 641| comment on function private.trg_llamadas_celular_enlaces_candado() is
 642|   'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';
 643| comment on function private.caducar_llamadas_celular() is
 644|   'Retención de llamadas del celular según crm.llamadas_celular_politica: borra descartadas con motivo, ambiguas sin resolver y sin identificar vencidas; fija el GUC crm.op_purga_llamadas para pasar el candado. La invoca pg_cron (crm-llamadas-celular-caducidad) con auth.uid() nulo; la auditoría conserva la fila con el número enmascarado. SECURITY DEFINER: borra sin privilegios de la API.';
 645| 
 646| -- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
 647| do $postflight$
 648| declare
 649|   v_t text;
 650|   v_f record;
 651|   v_n integer;
 652| begin
 653|   foreach v_t in array array['crm.llamadas_celular_politica', 'crm.celulares_asignaciones',
 654|                              'crm.llamadas_celular_eventos', 'crm.llamadas_celular_enlaces'] loop
 655|     if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
 656|       raise exception 'LLAMADAS_CELULAR: % quedó sin RLS', v_t;
 657|     end if;
 658|     if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
 659|                where pg_catalog.has_table_privilege(r.rol, v_t,
 660|                        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
 661|       raise exception 'LLAMADAS_CELULAR: % quedó accesible desde la API', v_t;
 662|     end if;
 663|     if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
 664|       raise exception 'LLAMADAS_CELULAR: % no debe tener policies (todo va por puertas)', v_t;
 665|     end if;
 666|     if (select count(*) from pg_catalog.pg_trigger t where t.tgrelid = v_t::regclass and not t.tgisinternal) <> 3 then
 667|       raise exception 'LLAMADAS_CELULAR: % no tiene sus 3 triggers (candado, sin vaciar, auditoría)', v_t;
 668|     end if;
 669|     if exists (select 1 from private.tablas_sin_rastro() s where s.tabla = v_t) then
 670|       raise exception 'LLAMADAS_CELULAR: % quedó sin rastro de auditoría válido', v_t;
 671|     end if;
 672|     if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
 673|        or exists (select 1 from pg_catalog.pg_attribute a
 674|                   where a.attrelid = v_t::regclass and a.attnum > 0 and not a.attisdropped
 675|                     and pg_catalog.col_description(a.attrelid, a.attnum) is null) then
 676|       raise exception 'LLAMADAS_CELULAR: % tiene la tabla o alguna columna sin COMMENT', v_t;
 677|     end if;
 678|   end loop;
 679| 
 680|   for v_f in
 681|     select * from (values
 682|       ('private.trg_llamadas_celular_sin_vaciar()'),
 683|       ('private.trg_llamadas_celular_politica_candado()'),
 684|       ('private.trg_celulares_asignaciones_candado()'),
 685|       ('private.trg_llamadas_celular_eventos_candado()'),
 686|       ('private.trg_llamadas_celular_enlaces_candado()'),
 687|       ('private.caducar_llamadas_celular()')
 688|     ) as f(firma)
 689|   loop
 690|     if exists (
 691|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
 692|       where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
 693|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) then
 694|       raise exception 'LLAMADAS_CELULAR: EXECUTE inesperado en %', v_f.firma;
 695|     end if;
 696|     if not exists (select 1 from pg_catalog.pg_proc p
 697|                    where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
 698|       raise exception 'LLAMADAS_CELULAR: search_path inesperado en %', v_f.firma;
 699|     end if;
 700|     if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
 701|       raise exception 'LLAMADAS_CELULAR: % sin COMMENT', v_f.firma;
 702|     end if;
 703|   end loop;
 704| 
 705|   -- Ninguna FK hacia personas desatribuye: siempre RESTRICT (la baja de usuarios detecta el
 706|   -- historial por estas FK y conserva la identidad; nunca SET NULL ni CASCADE).
 707|   if exists (select 1 from pg_catalog.pg_constraint c
 708|              where c.contype = 'f'
 709|                and c.conrelid in ('crm.llamadas_celular_politica'::regclass, 'crm.celulares_asignaciones'::regclass,
 710|                                   'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass)
 711|                and c.confrelid in ('public.perfiles'::regclass, 'crm.equipo'::regclass)
 712|                and c.confdeltype <> 'r') then
 713|     raise exception 'LLAMADAS_CELULAR: una FK hacia personas no es RESTRICT';
 714|   end if;
 715|   -- Toda FK con un índice que empiece por sus columnas (convención de la casa).
 716|   if exists (select 1 from pg_catalog.pg_constraint c
 717|              where c.contype = 'f'
 718|                and c.conrelid in ('crm.llamadas_celular_politica'::regclass, 'crm.celulares_asignaciones'::regclass,
 719|                                   'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass)
 720|                and not exists (
 721|                  select 1 from pg_catalog.pg_index i
 722|                  where i.indrelid = c.conrelid
 723|                    and (pg_catalog.string_to_array(i.indkey::text, ' ')::smallint[])[1:pg_catalog.array_length(c.conkey, 1)]
 724|                        = c.conkey)) then
 725|     raise exception 'LLAMADAS_CELULAR: hay una FK sin índice que la cubra';
 726|   end if;
 727| 
 728|   if not exists (select 1 from pg_catalog.pg_constraint c
 729|                  where c.conrelid = 'crm.celulares_asignaciones'::regclass
 730|                    and c.conname = 'celulares_asignaciones_sin_solape' and c.contype = 'x') then
 731|     raise exception 'LLAMADAS_CELULAR: falta la exclusión de solape de asignaciones';
 732|   end if;
 733|   if (select count(*) from crm.llamadas_celular_politica) <> 1 then
 734|     raise exception 'LLAMADAS_CELULAR: la política debe tener exactamente una fila';
 735|   end if;
 736|   if to_regprocedure('cron.schedule(text,text,text)') is not null then
 737|     select count(*) into v_n from cron.job j
 738|     where j.jobname = 'crm-llamadas-celular-caducidad' and j.active
 739|       and pg_catalog.strpos(j.command, 'caducar_llamadas_celular') > 0;
 740|     if v_n <> 1 then
 741|       raise exception 'LLAMADAS_CELULAR: la retención quedó con % jobs activos, se esperaba 1', v_n;
 742|     end if;
 743|   end if;
 744| end;
 745| $postflight$;
 746| 
 747| notify pgrst, 'reload schema';
 748| commit;
```

## Archivo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql (1044 líneas)
```
   1| -- Llamadas desde el celular · F2-c: NÚCLEO Y PUERTAS. Plan aprobado (Versión 3), fase F2.3.
   2| --
   3| -- Qué hace (sobre las tablas de 20261001145242):
   4| --   Núcleo en private — SECURITY INVOKER, sin EXECUTE para nadie: solo lo invocan las puertas
   5| --   DEFINER de abajo y, en F3, la puerta de servicio de la ingesta (excepción documentada del
   6| --   estándar: un núcleo que solo llaman definers puede ser invoker). Cada operación bloquea la
   7| --   fila que toca, revalida el ámbito del actor bajo ese bloqueo y es idempotente:
   8| --     · llamada_celular_ingerir(asignación, evento): claves exactas y versión 1; asignación
   9| --       vigente con analista activo (si no, 42501); número canonizado con las DOS reglas del CRM
  10| --       (canonizar_contacto y normalizar_telefono); coincidencia exacta entre los leads activos.
  11| --       Un lead → identificado; varios → ambiguo; ninguno → no se guarda (decisión 3, salvo la
  12| --       perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda
  13| --       (decisión 2). Mismo origen + mismo contenido → mismo evento (repetido); mismo origen con
  14| --       otro contenido → P0409. La hora va normalizada a UTC dentro del hash (si no, el mismo
  15| --       instante con otra zona sería «otro contenido»).
  16| --     · llamada_celular_asociar (solo a un lead que tenga el número de la llamada: nunca fabrica
  17| --       gestión), _enlazar (uno a uno con un resultado de llamada del mismo lead, posterior a la
  18| --       llamada; si el enlazado fue deshecho, el enlace se MUEVE al nuevo: decisión 4) y
  19| --       _descartar (motivo de catálogo; «otro» con detalle).
  20| --     · celular_asignar / _cerrar / _rotar_credencial: solo gerencia. La credencial (32 bytes
  21| --       aleatorios en hex) se devuelve UNA vez y solo se guarda su sha256.
  22| --     · llamadas_celular_politica_fijar: solo gerencia.
  23| --   Lecturas: bandeja de pendientes y detalle con la atención EFECTIVA calculada al leer
  24| --   (decisión 1): una llamada que pedía resultado deja de pedirlo si el lead ya no es elegible
  25| --   para quien mira; tras una reasignación la ve y la trabaja el analista nuevo (decisión 7),
  26| --   y quién marcó (analista_id) no cambia.
  27| --   Puertas en crm — SECURITY DEFINER (indispensable: las tablas no tienen privilegios para la
  28| --   API), search_path vacío, EXECUTE solo authenticated: resuelven auth.uid(), exigen rol CRM
  29| --   activo y delegan. No hay puerta de ingesta para el celular: llega en F3.
  30| --
  31| -- Decisiones de criterio de Claude (01/10/2026), para que Miguel las confirme o cambie:
  32| --   · Asignar, cerrar y rotar celulares, y fijar la política: solo gerencia. Supervisión LEE las
  33| --     asignaciones de su equipo.
  34| --   · Llamada de un analista a un lead que no es de su ámbito: se guarda identificada y «por
  35| --     revisar» (sin encuesta); la ve la cadena del dueño del lead, no quien llamó.
  36| --   · Un resultado solo se enlaza si se registró después de la llamada (tolerancia de 10 min por
  37| --     relojes desfasados).
  38| --   · Celular para analistas y supervisores (rol vendedor o supervisor activos).
  39| --
  40| -- Reversión: ../scripts/llamadas-celular/reversa-nucleo.sql (retira puertas y núcleo; las
  41| -- tablas y sus filas quedan). Verificación: npm run test:llamadas:local.
  42| begin;
  43| set local lock_timeout = '5s';
  44| set local statement_timeout = '60s';
  45| 
  46| do $precondicion$
  47| begin
  48|   if to_regclass('crm.llamadas_celular_eventos') is null
  49|      or to_regclass('crm.llamadas_celular_enlaces') is null
  50|      or to_regclass('crm.celulares_asignaciones') is null
  51|      or to_regclass('crm.llamadas_celular_politica') is null
  52|      or to_regprocedure('private.caducar_llamadas_celular()') is null then
  53|     raise exception 'LLAMADAS_NUCLEO: falta la migración de datos 20261001145242';
  54|   end if;
  55|   if to_regprocedure('private.idem_hash(jsonb)') is null
  56|      or to_regprocedure('private.canonizar_contacto(text)') is null
  57|      or to_regprocedure('private.normalizar_telefono(text)') is null
  58|      or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null
  59|      or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
  60|      or to_regprocedure('private.rol_crm(uuid)') is null
  61|      or to_regprocedure('extensions.gen_random_bytes(integer)') is null
  62|      or to_regprocedure('auth.uid()') is null then
  63|     raise exception 'LLAMADAS_NUCLEO: faltan dependencias (idem_hash, canonización, ámbito, pgcrypto o auth.uid)';
  64|   end if;
  65|   if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is not null
  66|      or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null
  67|      or to_regprocedure('crm.asignar_celular(text,uuid)') is not null then
  68|     raise exception 'LLAMADAS_NUCLEO: los objetos ya existen; no se sobrescriben';
  69|   end if;
  70| end;
  71| $precondicion$;
  72| 
  73| -- ── 1. Ayudantes del núcleo (INVOKER, sin EXECUTE para nadie) ─────────────────────────────
  74| 
  75| create function private.celular_credencial_hash(p_credencial text)
  76| returns text
  77| language sql
  78| immutable
  79| set search_path = ''
  80| as $function$
  81|   select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(p_credencial, ''), 'utf8')), 'hex')
  82| $function$;
  83| 
  84| -- Las dos formas canónicas con las que el CRM guarda teléfonos: la de canonizar_contacto (E.164
  85| -- con fijo e internacional; telefono_alternativo) y la del trigger de crm.leads.telefono
  86| -- (normalizar_telefono). Nunca se recortan dígitos: solo igualdad exacta.
  87| create function private.llamada_celular_formas(p_numero text)
  88| returns text[]
  89| language sql
  90| immutable
  91| set search_path = ''
  92| as $function$
  93|   select coalesce(pg_catalog.array_agg(distinct s.f) filter (where s.f is not null), '{}'::text[])
  94|   from (
  95|     select (select c.e164 from private.canonizar_contacto(p_numero) c limit 1) as f
  96|     union all
  97|     select case when private.normalizar_telefono(p_numero) ~ '^\+[1-9][0-9]{7,14}$'
  98|                 then private.normalizar_telefono(p_numero) end
  99|   ) s
 100| $function$;
 101| 
 102| create function private.llamada_celular_candidatos(p_formas text[])
 103| returns uuid[]
 104| language sql
 105| stable
 106| set search_path = ''
 107| as $function$
 108|   select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[])
 109|   from crm.leads l
 110|   where l.activo
 111|     and pg_catalog.cardinality(p_formas) > 0
 112|     and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
 113| $function$;
 114| 
 115| -- Decisión 1: pide resultado si el lead está activo, en etapa abierta, sin «no contactar» y
 116| -- dentro del ámbito de quien lo trabaja.
 117| create function private.llamada_celular_elegible(p_actor uuid, p_lead uuid)
 118| returns boolean
 119| language sql
 120| stable
 121| set search_path = ''
 122| as $function$
 123|   select coalesce((
 124|            select l.activo and l.etapa not in ('convertido', 'descartado') and not l.no_contactar
 125|            from crm.leads l where l.id = p_lead), false)
 126|      and coalesce(private.sla_gestion_permitida(p_actor, p_lead), false)
 127| $function$;
 128| 
 129| -- Quién ve una llamada: gerencia, todas; con lead, quien hoy tiene ámbito sobre el lead
 130| -- (decisión 7); sin lead (ambigua), quien llamó y su cadena de supervisión.
 131| create function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
 132| returns boolean
 133| language sql
 134| stable
 135| set search_path = ''
 136| as $function$
 137|   select p_actor is not null and (
 138|     coalesce(private.rol_crm(p_actor) = 'gerencia', false)
 139|     or (p_lead is not null and coalesce(private.sla_gestion_permitida(p_actor, p_lead), false))
 140|     or (p_lead is null and (p_analista = p_actor
 141|           or p_analista in (select private.vendedor_ids_visibles(p_actor))))
 142|   )
 143| $function$;
 144| 
 145| -- La atención que se MUESTRA (decisión 1): se recalcula al leer con quien mira.
 146| create function private.llamada_celular_atencion_efectiva(
 147|   p_actor uuid, p_atencion text, p_identificacion text, p_lead uuid)
 148| returns text
 149| language sql
 150| stable
 151| set search_path = ''
 152| as $function$
 153|   select case
 154|     when p_atencion in ('registrado', 'descartado_con_motivo', 'requiere_devolucion') then p_atencion
 155|     when p_identificacion <> 'identificado' then 'por_revisar'
 156|     when p_atencion = 'requiere_resultado' and private.llamada_celular_elegible(p_actor, p_lead)
 157|       then 'requiere_resultado'
 158|     else 'por_revisar'
 159|   end
 160| $function$;
 161| 
 162| -- Resuelve y autoriza al actor de una puerta. Lanza 42501 si no tiene un rol permitido.
 163| create function private.llamadas_celular_actor(p_roles text[])
 164| returns uuid
 165| language plpgsql
 166| stable
 167| set search_path = ''
 168| as $function$
 169| declare
 170|   v_actor uuid := (select auth.uid());
 171| begin
 172|   if v_actor is null or coalesce(private.rol_crm(v_actor), '') <> all(p_roles) then
 173|     raise exception using errcode = '42501', message = 'Sin acceso a las llamadas del celular';
 174|   end if;
 175|   return v_actor;
 176| end;
 177| $function$;
 178| 
 179| -- ── 2. Ingesta (la invocará la puerta de servicio de F3) ─────────────────────────────────
 180| create function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb)
 181| returns jsonb
 182| language plpgsql
 183| volatile
 184| set search_path = ''
 185| as $function$
 186| declare
 187|   v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
 188|                                     'duracion_seg', 'ocurrio_en'];
 189|   v_asig crm.celulares_asignaciones%rowtype;
 190|   v_pol crm.llamadas_celular_politica%rowtype;
 191|   v_previo crm.llamadas_celular_eventos%rowtype;
 192|   v_origen text;
 193|   v_numero text;
 194|   v_dir text;
 195|   v_estado text;
 196|   v_dur integer;
 197|   v_ocurrio timestamptz;
 198|   v_hash text;
 199|   v_formas text[];
 200|   v_e164 text;
 201|   v_cand uuid[];
 202|   v_lead uuid;
 203|   v_ident text;
 204|   v_aten text;
 205|   v_metodo text;
 206|   v_calidad jsonb := '{}'::jsonb;
 207|   v_id uuid;
 208| begin
 209|   -- Forma del evento: objeto, claves exactas, versión 1.
 210|   if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
 211|     raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
 212|   end if;
 213|   if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
 214|     raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
 215|   end if;
 216|   if coalesce(p_evento ->> 'v', '') <> '1' then
 217|     raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
 218|   end if;
 219|   v_origen := p_evento ->> 'evento_origen_id';
 220|   if v_origen is null or v_origen !~ '^[A-Za-z0-9._:+-]{4,120}$' then
 221|     raise exception using errcode = '22023', message = 'evento_origen_id inválido (4 a 120 caracteres: letras, dígitos y . _ : + -)';
 222|   end if;
 223|   v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
 224|   if pg_catalog.length(v_numero) > 40 then
 225|     raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
 226|   end if;
 227|   v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
 228|   if v_dir not in ('saliente', 'entrante', 'desconocida') then
 229|     raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
 230|   end if;
 231|   v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
 232|   if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
 233|     raise exception using errcode = '22023', message = 'estado_tecnico inválido';
 234|   end if;
 235|   begin
 236|     v_dur := (p_evento ->> 'duracion_seg')::integer;
 237|     v_ocurrio := (p_evento ->> 'ocurrio_en')::timestamptz;
 238|   exception when others then
 239|     raise exception using errcode = '22023', message = 'duracion_seg u ocurrio_en con formato inválido';
 240|   end;
 241|   if v_dur is not null and v_dur not between 0 and 86400 then
 242|     raise exception using errcode = '22023', message = 'duracion_seg fuera de rango (0 a 86400)';
 243|   end if;
 244|   if v_ocurrio is not null and (v_ocurrio < timestamptz '2026-01-01 00:00Z' or v_ocurrio >= timestamptz '2100-01-01 00:00Z') then
 245|     raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
 246|   end if;
 247| 
 248|   -- Asignación vigente con analista activo (F3: credencial revocada o analista dado de baja).
 249|   select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
 250|   if not found or v_asig.vigente_hasta is not null
 251|      or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 252|     raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
 253|   end if;
 254| 
 255|   -- Contenido canónico (la hora en UTC: el mismo instante con otra zona es el MISMO contenido).
 256|   v_hash := private.idem_hash(pg_catalog.jsonb_build_object(
 257|     'v', 1, 'evento_origen_id', v_origen, 'numero', v_numero, 'direccion', v_dir,
 258|     'estado_tecnico', v_estado, 'duracion_seg', v_dur,
 259|     'ocurrio_en', pg_catalog.to_char(v_ocurrio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 260| 
 261|   select * into v_previo from crm.llamadas_celular_eventos e
 262|   where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
 263|   if found then
 264|     if v_previo.hash_payload <> v_hash then
 265|       raise exception using errcode = 'P0409',
 266|         message = 'Esta llamada ya llegó con otro contenido; no se puede reenviar así';
 267|     end if;
 268|     return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
 269|       'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
 270|   end if;
 271| 
 272|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 273| 
 274|   -- Decisión 2: con las entrantes apagadas, una entrante no se guarda.
 275|   if v_dir = 'entrante' and not coalesce(v_pol.entrantes_activas, false) then
 276|     return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true, 'motivo', 'entrante_apagada');
 277|   end if;
 278|   if v_dir = 'desconocida' then
 279|     v_calidad := v_calidad || '{"direccion": "desconocida"}'::jsonb;
 280|   end if;
 281|   if v_ocurrio is not null and v_ocurrio > pg_catalog.now() + interval '5 minutes' then
 282|     v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
 283|   end if;
 284| 
 285|   v_formas := private.llamada_celular_formas(v_numero);
 286|   v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
 287|   if v_e164 is null and v_numero is not null then
 288|     v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
 289|   elsif v_numero is null then
 290|     v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
 291|   end if;
 292|   v_cand := private.llamada_celular_candidatos(v_formas);
 293| 
 294|   if pg_catalog.cardinality(v_cand) = 1 then
 295|     v_lead := v_cand[1];
 296|     v_ident := 'identificado';
 297|     v_metodo := 'exacto';
 298|     v_aten := case when private.llamada_celular_elegible(v_asig.analista_id, v_lead)
 299|                    then 'requiere_resultado' else 'por_revisar' end;
 300|   elsif pg_catalog.cardinality(v_cand) > 1 then
 301|     v_ident := 'ambiguo';
 302|     v_aten := 'por_revisar';
 303|     v_calidad := v_calidad || pg_catalog.jsonb_build_object('candidatos', pg_catalog.cardinality(v_cand));
 304|   elsif coalesce(v_pol.guardar_sin_identificar, false) then
 305|     v_ident := 'sin_identificar';
 306|     v_aten := 'por_revisar';
 307|   else
 308|     -- Decisión 3: si el número no es de ningún lead, la llamada no pertenece al CRM.
 309|     return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true,
 310|       'motivo', case when pg_catalog.cardinality(v_formas) = 0 then 'numero_no_valido' else 'sin_lead' end);
 311|   end if;
 312| 
 313|   insert into crm.llamadas_celular_eventos
 314|     (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, direccion,
 315|      estado_tecnico, duracion_seg, ocurrio_en, calidad, identificacion, atencion, lead_id,
 316|      metodo_asociacion, asociado_en)
 317|   values
 318|     -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
 319|     -- volver a buscar candidatos al asociar.
 320|     (v_asig.id, v_asig.analista_id, v_origen, v_hash, coalesce(v_e164, v_formas[1]), v_dir,
 321|      v_estado, v_dur, v_ocurrio, v_calidad, v_ident, v_aten, v_lead,
 322|      v_metodo, case when v_lead is not null then pg_catalog.now() end)
 323|   on conflict on constraint llamadas_celular_eventos_origen_unico do nothing
 324|   returning id into v_id;
 325| 
 326|   if v_id is null then
 327|     -- Dos envíos a la vez del mismo origen: gana el primero; el segundo responde como repetido
 328|     -- (o conflicto si su contenido es otro).
 329|     select * into v_previo from crm.llamadas_celular_eventos e
 330|     where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
 331|     if v_previo.hash_payload <> v_hash then
 332|       raise exception using errcode = 'P0409',
 333|         message = 'Esta llamada llegó a la vez con otro contenido; no se puede reenviar así';
 334|     end if;
 335|     return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
 336|       'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
 337|   end if;
 338| 
 339|   return pg_catalog.jsonb_build_object('evento_id', v_id, 'repetido', false, 'ignorado', false,
 340|     'identificacion', v_ident, 'atencion', v_aten, 'lead_id', v_lead);
 341| end;
 342| $function$;
 343| 
 344| -- ── 3. Operaciones sobre una llamada ─────────────────────────────────────────────────────
 345| create function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
 346| returns jsonb
 347| language plpgsql
 348| volatile
 349| set search_path = ''
 350| as $function$
 351| declare
 352|   v_ev crm.llamadas_celular_eventos%rowtype;
 353|   v_aten text;
 354| begin
 355|   if p_evento_id is null or p_lead_id is null then
 356|     raise exception using errcode = '22023', message = 'Faltan la llamada o el lead';
 357|   end if;
 358|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 359|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 360|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 361|   end if;
 362|   if v_ev.atencion in ('registrado', 'descartado_con_motivo') then
 363|     raise exception using errcode = '22023', message = 'La llamada ya está registrada o descartada';
 364|   end if;
 365|   if v_ev.lead_id = p_lead_id then
 366|     return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', v_ev.lead_id, 'repetido', true,
 367|       'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id));
 368|   end if;
 369|   if not coalesce(private.sla_gestion_permitida(p_actor, p_lead_id), false) then
 370|     raise exception using errcode = '42501', message = 'Ese lead no es de tu ámbito';
 371|   end if;
 372|   -- Nunca fabrica gestión: el lead elegido tiene que tener el número de la llamada.
 373|   if not (p_lead_id = any(private.llamada_celular_candidatos(private.llamada_celular_formas(v_ev.numero_canonico)))) then
 374|     raise exception using errcode = '22023', message = 'Ese lead no tiene el número de la llamada';
 375|   end if;
 376|   v_aten := case when private.llamada_celular_elegible(p_actor, p_lead_id)
 377|                  then 'requiere_resultado' else 'por_revisar' end;
 378|   update crm.llamadas_celular_eventos
 379|      set identificacion = 'identificado', lead_id = p_lead_id, metodo_asociacion = 'manual',
 380|          asociado_por = p_actor, asociado_en = pg_catalog.now(), atencion = v_aten
 381|    where id = v_ev.id;
 382|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', p_lead_id, 'repetido', false,
 383|     'atencion', v_aten);
 384| end;
 385| $function$;
 386| 
 387| create function private.llamada_celular_enlazar(p_actor uuid, p_evento_id uuid, p_actividad_id uuid)
 388| returns jsonb
 389| language plpgsql
 390| volatile
 391| set search_path = ''
 392| as $function$
 393| declare
 394|   v_ev crm.llamadas_celular_eventos%rowtype;
 395|   v_act crm.actividades%rowtype;
 396|   v_enl crm.llamadas_celular_enlaces%rowtype;
 397|   v_deshecha boolean;
 398|   v_movido boolean := false;
 399| begin
 400|   if p_evento_id is null or p_actividad_id is null then
 401|     raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
 402|   end if;
 403|   -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no
 404|   -- registra por él (gerencia ve todo y tiene ámbito sobre todo).
 405|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 406|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 407|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 408|   end if;
 409|   if v_ev.identificacion <> 'identificado' then
 410|     raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
 411|   end if;
 412|   if v_ev.atencion = 'descartado_con_motivo' then
 413|     raise exception using errcode = '22023', message = 'La llamada fue descartada';
 414|   end if;
 415|   select * into v_act from crm.actividades a where a.id = p_actividad_id;
 416|   if not found or v_act.lead_id <> v_ev.lead_id then
 417|     raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
 418|   end if;
 419|   if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 420|      or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 421|     raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
 422|   end if;
 423|   if v_act.creado_en < coalesce(v_ev.ocurrio_en, v_ev.recibido_en) - interval '10 minutes' then
 424|     raise exception using errcode = '22023', message = 'El resultado se registró antes de la llamada';
 425|   end if;
 426| 
 427|   select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
 428|   if found then
 429|     if v_enl.actividad_id = p_actividad_id then
 430|       return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
 431|         'repetido', true, 'movido', false);
 432|     end if;
 433|     select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
 434|     if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
 435|       raise exception using errcode = '23505', message = 'La llamada ya tiene su resultado registrado';
 436|     end if;
 437|     begin
 438|       update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
 439|        where id = v_enl.id;
 440|     exception when unique_violation then
 441|       raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
 442|     end;
 443|     v_movido := true;
 444|   else
 445|     begin
 446|       insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
 447|       values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor);
 448|     exception when unique_violation then
 449|       raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
 450|     end;
 451|   end if;
 452| 
 453|   -- La máquina de estados de la tabla exige pasar por «requiere resultado».
 454|   if v_ev.atencion = 'por_revisar' then
 455|     update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
 456|   end if;
 457|   if v_ev.atencion <> 'registrado' then
 458|     update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
 459|   end if;
 460|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
 461|     'repetido', false, 'movido', v_movido);
 462| end;
 463| $function$;
 464| 
 465| create function private.llamada_celular_descartar(p_actor uuid, p_evento_id uuid, p_motivo text, p_detalle text)
 466| returns jsonb
 467| language plpgsql
 468| volatile
 469| set search_path = ''
 470| as $function$
 471| declare
 472|   v_ev crm.llamadas_celular_eventos%rowtype;
 473|   v_detalle text := nullif(pg_catalog.btrim(coalesce(p_detalle, '')), '');
 474| begin
 475|   if p_evento_id is null then
 476|     raise exception using errcode = '22023', message = 'Falta la llamada';
 477|   end if;
 478|   if p_motivo is null or p_motivo not in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro') then
 479|     raise exception using errcode = '22023',
 480|       message = 'Motivo inválido (no_comercial, personal, numero_de_prueba, error_captura u otro)';
 481|   end if;
 482|   if p_motivo = 'otro' and pg_catalog.length(coalesce(v_detalle, '')) < 3 then
 483|     raise exception using errcode = '22023', message = 'Con «otro», escribe el motivo (al menos 3 caracteres)';
 484|   end if;
 485|   if pg_catalog.length(coalesce(v_detalle, '')) > 300 then
 486|     raise exception using errcode = '22023', message = 'El detalle no puede pasar de 300 caracteres';
 487|   end if;
 488|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 489|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 490|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 491|   end if;
 492|   if v_ev.atencion = 'descartado_con_motivo' then
 493|     if v_ev.motivo_descarte = p_motivo and v_ev.motivo_descarte_detalle is not distinct from v_detalle then
 494|       return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', true, 'motivo', p_motivo);
 495|     end if;
 496|     raise exception using errcode = '23505', message = 'La llamada ya fue descartada con otro motivo';
 497|   end if;
 498|   if v_ev.atencion = 'registrado' then
 499|     raise exception using errcode = '22023', message = 'La llamada ya tiene su resultado registrado';
 500|   end if;
 501|   update crm.llamadas_celular_eventos
 502|      set atencion = 'descartado_con_motivo', motivo_descarte = p_motivo, motivo_descarte_detalle = v_detalle,
 503|          descartado_por = p_actor, descartado_en = pg_catalog.now()
 504|    where id = v_ev.id;
 505|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', false, 'motivo', p_motivo);
 506| end;
 507| $function$;
 508| 
 509| -- ── 4. Celulares y política (gerencia) ───────────────────────────────────────────────────
 510| create function private.celular_asignar(p_actor uuid, p_etiqueta text, p_analista_id uuid)
 511| returns jsonb
 512| language plpgsql
 513| volatile
 514| set search_path = ''
 515| as $function$
 516| declare
 517|   v_credencial text;
 518|   v_id uuid;
 519| begin
 520|   if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
 521|     raise exception using errcode = '42501', message = 'Solo gerencia asigna celulares';
 522|   end if;
 523|   if p_etiqueta is null or p_etiqueta !~ '^C[1-9][0-9]{0,2}$' then
 524|     raise exception using errcode = '22023', message = 'Etiqueta inválida (C1, C2…)';
 525|   end if;
 526|   if coalesce(private.rol_crm(p_analista_id), '') not in ('vendedor', 'supervisor') then
 527|     raise exception using errcode = '22023', message = 'El celular se asigna a un analista o supervisor activo';
 528|   end if;
 529|   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('celular:' || p_etiqueta, 0));
 530|   if exists (select 1 from crm.celulares_asignaciones a where a.etiqueta = p_etiqueta and a.vigente_hasta is null) then
 531|     raise exception using errcode = '23505',
 532|       message = pg_catalog.format('%s ya está asignado: ciérralo o rota su credencial', p_etiqueta);
 533|   end if;
 534|   v_credencial := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
 535|   insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde, creado_por)
 536|   values (p_etiqueta, p_analista_id, private.celular_credencial_hash(v_credencial), pg_catalog.clock_timestamp(), p_actor)
 537|   returning id into v_id;
 538|   -- La credencial se devuelve UNA vez; solo queda su hash.
 539|   return pg_catalog.jsonb_build_object('asignacion_id', v_id, 'etiqueta', p_etiqueta,
 540|     'analista_id', p_analista_id, 'credencial', v_credencial);
 541| end;
 542| $function$;
 543| 
 544| create function private.celular_cerrar(p_actor uuid, p_asignacion_id uuid, p_motivo text)
 545| returns jsonb
 546| language plpgsql
 547| volatile
 548| set search_path = ''
 549| as $function$
 550| declare
 551|   v_asig crm.celulares_asignaciones%rowtype;
 552| begin
 553|   if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
 554|     raise exception using errcode = '42501', message = 'Solo gerencia cierra asignaciones de celular';
 555|   end if;
 556|   if p_motivo is null or p_motivo not in ('rotacion', 'baja_analista', 'extravio', 'reemplazo', 'otro') then
 557|     raise exception using errcode = '22023', message = 'Motivo inválido (rotacion, baja_analista, extravio, reemplazo u otro)';
 558|   end if;
 559|   select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for update;
 560|   if not found then
 561|     raise exception using errcode = '22023', message = 'Asignación no encontrada';
 562|   end if;
 563|   if v_asig.vigente_hasta is not null then
 564|     if v_asig.motivo_cierre = p_motivo then
 565|       return pg_catalog.jsonb_build_object('asignacion_id', v_asig.id, 'repetido', true);
 566|     end if;
 567|     raise exception using errcode = '23505', message = 'La asignación ya estaba cerrada con otro motivo';
 568|   end if;
 569|   update crm.celulares_asignaciones
 570|      set vigente_hasta = pg_catalog.clock_timestamp(), motivo_cierre = p_motivo
 571|    where id = v_asig.id;
 572|   return pg_catalog.jsonb_build_object('asignacion_id', v_asig.id, 'repetido', false);
 573| end;
 574| $function$;
 575| 
 576| create function private.celular_rotar_credencial(p_actor uuid, p_etiqueta text)
 577| returns jsonb
 578| language plpgsql
 579| volatile
 580| set search_path = ''
 581| as $function$
 582| declare
 583|   v_asig crm.celulares_asignaciones%rowtype;
 584|   v_t timestamptz;
 585|   v_credencial text;
 586|   v_id uuid;
 587| begin
 588|   if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
 589|     raise exception using errcode = '42501', message = 'Solo gerencia rota credenciales de celular';
 590|   end if;
 591|   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('celular:' || coalesce(p_etiqueta, ''), 0));
 592|   select * into v_asig from crm.celulares_asignaciones a
 593|   where a.etiqueta = p_etiqueta and a.vigente_hasta is null for update;
 594|   if not found then
 595|     raise exception using errcode = '22023', message = 'Ese celular no tiene una asignación vigente';
 596|   end if;
 597|   if coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 598|     raise exception using errcode = '22023', message = 'El analista del celular ya no está activo: ciérralo y asígnalo a otro';
 599|   end if;
 600|   v_t := pg_catalog.clock_timestamp();
 601|   update crm.celulares_asignaciones set vigente_hasta = v_t, motivo_cierre = 'rotacion' where id = v_asig.id;
 602|   v_credencial := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
 603|   insert into crm.celulares_asignaciones (etiqueta, analista_id, credencial_hash, vigente_desde, creado_por)
 604|   values (v_asig.etiqueta, v_asig.analista_id, private.celular_credencial_hash(v_credencial), v_t, p_actor)
 605|   returning id into v_id;
 606|   return pg_catalog.jsonb_build_object('asignacion_id', v_id, 'etiqueta', v_asig.etiqueta,
 607|     'analista_id', v_asig.analista_id, 'credencial', v_credencial, 'anterior_id', v_asig.id);
 608| end;
 609| $function$;
 610| 
 611| create function private.llamadas_celular_politica_fijar(
 612|   p_actor uuid, p_guardar_sin_identificar boolean, p_entrantes_activas boolean,
 613|   p_dias_descartados integer, p_dias_sin_resolver integer, p_dias_sin_identificar integer)
 614| returns jsonb
 615| language plpgsql
 616| volatile
 617| set search_path = ''
 618| as $function$
 619| declare
 620|   v_pol crm.llamadas_celular_politica%rowtype;
 621| begin
 622|   if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
 623|     raise exception using errcode = '42501', message = 'Solo gerencia ajusta la política de llamadas';
 624|   end if;
 625|   if (p_dias_descartados is not null and p_dias_descartados not between 1 and 365)
 626|      or (p_dias_sin_resolver is not null and p_dias_sin_resolver not between 1 and 365)
 627|      or (p_dias_sin_identificar is not null and p_dias_sin_identificar not between 1 and 365) then
 628|     raise exception using errcode = '22023', message = 'Los días de retención van de 1 a 365';
 629|   end if;
 630|   update crm.llamadas_celular_politica
 631|      set guardar_sin_identificar = coalesce(p_guardar_sin_identificar, guardar_sin_identificar),
 632|          entrantes_activas = coalesce(p_entrantes_activas, entrantes_activas),
 633|          dias_retencion_descartados = coalesce(p_dias_descartados, dias_retencion_descartados),
 634|          dias_retencion_sin_resolver = coalesce(p_dias_sin_resolver, dias_retencion_sin_resolver),
 635|          dias_retencion_sin_identificar = coalesce(p_dias_sin_identificar, dias_retencion_sin_identificar),
 636|          actualizado_por = p_actor
 637|    where singleton
 638|   returning * into v_pol;
 639|   return pg_catalog.to_jsonb(v_pol) - 'singleton';
 640| end;
 641| $function$;
 642| 
 643| -- ── 5. Lecturas ──────────────────────────────────────────────────────────────────────────
 644| create function private.llamadas_celular_pendientes(p_actor uuid, p_limite integer)
 645| returns jsonb
 646| language sql
 647| stable
 648| set search_path = ''
 649| as $function$
 650|   select coalesce(pg_catalog.jsonb_agg(f.fila order by f.recibido_en desc), '[]'::jsonb)
 651|   from (
 652|     select e.recibido_en,
 653|            pg_catalog.jsonb_build_object(
 654|              'evento_id', e.id, 'recibido_en', e.recibido_en, 'ocurrio_en', e.ocurrio_en,
 655|              'numero', e.numero_canonico, 'direccion', e.direccion, 'estado_tecnico', e.estado_tecnico,
 656|              'duracion_seg', e.duracion_seg, 'identificacion', e.identificacion,
 657|              'atencion', private.llamada_celular_atencion_efectiva(p_actor, e.atencion, e.identificacion, e.lead_id),
 658|              'lead_id', e.lead_id, 'lead_nombre', l.nombre_completo,
 659|              'analista_id', e.analista_id, 'es_propia', e.analista_id = p_actor) as fila
 660|     from crm.llamadas_celular_eventos e
 661|     left join crm.leads l on l.id = e.lead_id
 662|     where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 663|       and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
 664|     order by e.recibido_en desc
 665|     limit p_limite
 666|   ) f
 667| $function$;
 668| 
 669| create function private.llamada_celular_detalle(p_actor uuid, p_evento_id uuid)
 670| returns jsonb
 671| language plpgsql
 672| stable
 673| set search_path = ''
 674| as $function$
 675| declare
 676|   v_ev crm.llamadas_celular_eventos%rowtype;
 677|   v_enl crm.llamadas_celular_enlaces%rowtype;
 678|   v_deshecha boolean;
 679| begin
 680|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 681|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 682|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 683|   end if;
 684|   select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id;
 685|   if found and v_enl.actividad_id is not null then
 686|     select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
 687|   end if;
 688|   return pg_catalog.jsonb_build_object(
 689|     'evento_id', v_ev.id, 'recibido_en', v_ev.recibido_en, 'ocurrio_en', v_ev.ocurrio_en,
 690|     'numero', v_ev.numero_canonico, 'direccion', v_ev.direccion, 'estado_tecnico', v_ev.estado_tecnico,
 691|     'duracion_seg', v_ev.duracion_seg, 'calidad', v_ev.calidad, 'identificacion', v_ev.identificacion,
 692|     'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id),
 693|     'lead_id', v_ev.lead_id, 'metodo_asociacion', v_ev.metodo_asociacion, 'analista_id', v_ev.analista_id,
 694|     'motivo_descarte', v_ev.motivo_descarte, 'motivo_descarte_detalle', v_ev.motivo_descarte_detalle,
 695|     'actividad_id', v_enl.actividad_id,
 696|     -- Decisión 4: los efectos deshechos se DERIVAN del resultado, no se copian.
 697|     'efectos_anulados', coalesce(v_deshecha, false));
 698| end;
 699| $function$;
 700| 
 701| create function private.celulares_asignaciones_listar(p_actor uuid)
 702| returns jsonb
 703| language sql
 704| stable
 705| set search_path = ''
 706| as $function$
 707|   select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 708|            'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
 709|            'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
 710|            'vigente_hasta', a.vigente_hasta, 'motivo_cierre', a.motivo_cierre)
 711|          order by a.etiqueta, a.vigente_desde desc), '[]'::jsonb)
 712|   from crm.celulares_asignaciones a
 713|   left join public.perfiles p on p.id = a.analista_id
 714|   where private.rol_crm(p_actor) = 'gerencia'
 715|      or (private.rol_crm(p_actor) = 'supervisor'
 716|          and a.analista_id in (select private.vendedor_ids_visibles(p_actor)))
 717| $function$;
 718| 
 719| -- ── 6. Puertas (crm, DEFINER, EXECUTE solo authenticated) ─────────────────────────────────
 720| create function crm.llamadas_celular_pendientes_fn(p_limite integer default 50)
 721| returns jsonb
 722| language plpgsql
 723| stable
 724| security definer
 725| set search_path = ''
 726| as $function$
 727| declare
 728|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 729| begin
 730|   if p_limite is null or p_limite not between 1 and 200 then
 731|     raise exception using errcode = '22023', message = 'El límite va de 1 a 200';
 732|   end if;
 733|   return private.llamadas_celular_pendientes(v_actor, p_limite);
 734| end;
 735| $function$;
 736| 
 737| create function crm.llamada_celular_detalle_fn(p_evento_id uuid)
 738| returns jsonb
 739| language plpgsql
 740| stable
 741| security definer
 742| set search_path = ''
 743| as $function$
 744| declare
 745|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 746| begin
 747|   return private.llamada_celular_detalle(v_actor, p_evento_id);
 748| end;
 749| $function$;
 750| 
 751| create function crm.asociar_llamada_celular(p_evento_id uuid, p_lead_id uuid)
 752| returns jsonb
 753| language plpgsql
 754| volatile
 755| security definer
 756| set search_path = ''
 757| as $function$
 758| declare
 759|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 760| begin
 761|   return private.llamada_celular_asociar(v_actor, p_evento_id, p_lead_id);
 762| end;
 763| $function$;
 764| 
 765| create function crm.enlazar_llamada_celular(p_evento_id uuid, p_actividad_id uuid)
 766| returns jsonb
 767| language plpgsql
 768| volatile
 769| security definer
 770| set search_path = ''
 771| as $function$
 772| declare
 773|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 774| begin
 775|   return private.llamada_celular_enlazar(v_actor, p_evento_id, p_actividad_id);
 776| end;
 777| $function$;
 778| 
 779| create function crm.descartar_llamada_celular(p_evento_id uuid, p_motivo text, p_detalle text default null)
 780| returns jsonb
 781| language plpgsql
 782| volatile
 783| security definer
 784| set search_path = ''
 785| as $function$
 786| declare
 787|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 788| begin
 789|   return private.llamada_celular_descartar(v_actor, p_evento_id, p_motivo, p_detalle);
 790| end;
 791| $function$;
 792| 
 793| create function crm.celulares_asignaciones_fn()
 794| returns jsonb
 795| language plpgsql
 796| stable
 797| security definer
 798| set search_path = ''
 799| as $function$
 800| declare
 801|   v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
 802| begin
 803|   return private.celulares_asignaciones_listar(v_actor);
 804| end;
 805| $function$;
 806| 
 807| create function crm.asignar_celular(p_etiqueta text, p_analista_id uuid)
 808| returns jsonb
 809| language plpgsql
 810| volatile
 811| security definer
 812| set search_path = ''
 813| as $function$
 814| declare
 815|   v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
 816| begin
 817|   return private.celular_asignar(v_actor, p_etiqueta, p_analista_id);
 818| end;
 819| $function$;
 820| 
 821| create function crm.cerrar_asignacion_celular(p_asignacion_id uuid, p_motivo text)
 822| returns jsonb
 823| language plpgsql
 824| volatile
 825| security definer
 826| set search_path = ''
 827| as $function$
 828| declare
 829|   v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
 830| begin
 831|   return private.celular_cerrar(v_actor, p_asignacion_id, p_motivo);
 832| end;
 833| $function$;
 834| 
 835| create function crm.rotar_credencial_celular(p_etiqueta text)
 836| returns jsonb
 837| language plpgsql
 838| volatile
 839| security definer
 840| set search_path = ''
 841| as $function$
 842| declare
 843|   v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
 844| begin
 845|   return private.celular_rotar_credencial(v_actor, p_etiqueta);
 846| end;
 847| $function$;
 848| 
 849| create function crm.llamadas_celular_politica_fn()
 850| returns jsonb
 851| language plpgsql
 852| stable
 853| security definer
 854| set search_path = ''
 855| as $function$
 856| declare
 857|   v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
 858| begin
 859|   return (select pg_catalog.to_jsonb(p) - 'singleton' from crm.llamadas_celular_politica p where p.singleton);
 860| end;
 861| $function$;
 862| 
 863| create function crm.fijar_politica_llamadas_celular(
 864|   p_guardar_sin_identificar boolean default null, p_entrantes_activas boolean default null,
 865|   p_dias_retencion_descartados integer default null, p_dias_retencion_sin_resolver integer default null,
 866|   p_dias_retencion_sin_identificar integer default null)
 867| returns jsonb
 868| language plpgsql
 869| volatile
 870| security definer
 871| set search_path = ''
 872| as $function$
 873| declare
 874|   v_actor uuid := private.llamadas_celular_actor(array['gerencia']);
 875| begin
 876|   return private.llamadas_celular_politica_fijar(v_actor, p_guardar_sin_identificar, p_entrantes_activas,
 877|     p_dias_retencion_descartados, p_dias_retencion_sin_resolver, p_dias_retencion_sin_identificar);
 878| end;
 879| $function$;
 880| 
 881| -- ── 7. Permisos: núcleo sin EXECUTE para nadie; puertas solo authenticated ───────────────
 882| do $permisos$
 883| declare
 884|   v_f text;
 885| begin
 886|   foreach v_f in array array[
 887|     'private.celular_credencial_hash(text)', 'private.llamada_celular_formas(text)',
 888|     'private.llamada_celular_candidatos(text[])', 'private.llamada_celular_elegible(uuid,uuid)',
 889|     'private.llamada_celular_visible(uuid,uuid,uuid)',
 890|     'private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)', 'private.llamadas_celular_actor(text[])',
 891|     'private.llamada_celular_ingerir(uuid,jsonb)', 'private.llamada_celular_asociar(uuid,uuid,uuid)',
 892|     'private.llamada_celular_enlazar(uuid,uuid,uuid)', 'private.llamada_celular_descartar(uuid,uuid,text,text)',
 893|     'private.celular_asignar(uuid,text,uuid)', 'private.celular_cerrar(uuid,uuid,text)',
 894|     'private.celular_rotar_credencial(uuid,text)',
 895|     'private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)',
 896|     'private.llamadas_celular_pendientes(uuid,integer)', 'private.llamada_celular_detalle(uuid,uuid)',
 897|     'private.celulares_asignaciones_listar(uuid)'] loop
 898|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 899|   end loop;
 900|   foreach v_f in array array[
 901|     'crm.llamadas_celular_pendientes_fn(integer)', 'crm.llamada_celular_detalle_fn(uuid)',
 902|     'crm.asociar_llamada_celular(uuid,uuid)', 'crm.enlazar_llamada_celular(uuid,uuid)',
 903|     'crm.descartar_llamada_celular(uuid,text,text)', 'crm.celulares_asignaciones_fn()',
 904|     'crm.asignar_celular(text,uuid)', 'crm.cerrar_asignacion_celular(uuid,text)',
 905|     'crm.rotar_credencial_celular(text)', 'crm.llamadas_celular_politica_fn()',
 906|     'crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)'] loop
 907|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 908|     execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
 909|   end loop;
 910| end;
 911| $permisos$;
 912| 
 913| -- ── 8. Comentarios ───────────────────────────────────────────────────────────────────────
 914| comment on function private.celular_credencial_hash(text) is
 915|   'sha256 en hex de la credencial de un celular (mismo modelo que private.saga_token_hash). La credencial en claro nunca se guarda.';
 916| comment on function private.llamada_celular_formas(text) is
 917|   'Las dos formas canónicas de un número con las que el CRM guarda teléfonos (canonizar_contacto y normalizar_telefono); solo formas E.164 válidas, sin recortar dígitos.';
 918| comment on function private.llamada_celular_candidatos(text[]) is
 919|   'Leads activos cuyo teléfono principal o alternativo es EXACTAMENTE una de las formas dadas.';
 920| comment on function private.llamada_celular_elegible(uuid,uuid) is
 921|   'Decisión 1 (provisional, Jhosep 30/09): la llamada pide resultado si el lead está activo, en etapa abierta, sin «no contactar» y en el ámbito del actor (sla_gestion_permitida).';
 922| comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
 923|   'Quién ve una llamada: gerencia todas; con lead, quien hoy tiene ámbito sobre el lead (decisión 7); sin lead, quien llamó y su cadena de supervisión.';
 924| comment on function private.llamada_celular_atencion_efectiva(uuid,text,text,uuid) is
 925|   'Atención que se muestra, recalculada al leer (decisión 1): «requiere resultado» solo si así entró y el lead sigue siendo elegible para quien mira; si no, «por revisar». Registrado, descartado y devolución se muestran tal cual.';
 926| comment on function private.llamadas_celular_actor(text[]) is
 927|   'Resuelve auth.uid() y exige un rol CRM activo de la lista; si no, 42501. Lo usan las puertas de llamadas del celular.';
 928| comment on function private.llamada_celular_ingerir(uuid,jsonb) is
 929|   'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número.';
 930| comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
 931|   'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Bloquea la llamada, revalida el ámbito; idempotente.';
 932| comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
 933|   'Enlaza la llamada con el resultado de llamada que la encuesta registró para el mismo lead, después de la llamada (tolerancia 10 min). Si el enlazado fue deshecho, el enlace se mueve (decisión 4). Revalida el ámbito (decisión 7: si el lead ya no es del actor, 42501). Deja la llamada en «registrado». Idempotente.';
 934| comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
 935|   'Descarta una llamada con motivo de catálogo (decisión 3; «otro» con detalle). Revalida el ámbito; idempotente con el mismo motivo, 23505 con otro.';
 936| comment on function private.celular_asignar(uuid,text,uuid) is
 937|   'Gerencia asigna un celular (etiqueta) a un analista o supervisor activo. Genera una credencial de 32 bytes, la devuelve UNA vez y guarda solo su sha256. 23505 si la etiqueta ya está asignada.';
 938| comment on function private.celular_cerrar(uuid,uuid,text) is
 939|   'Gerencia cierra una asignación vigente con motivo de catálogo; idempotente con el mismo motivo.';
 940| comment on function private.celular_rotar_credencial(uuid,text) is
 941|   'Gerencia rota la credencial de un celular: cierra la asignación vigente (motivo rotacion) y abre otra al mismo analista, contigua en el tiempo, con credencial nueva devuelta UNA vez.';
 942| comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
 943|   'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor.';
 944| comment on function private.llamadas_celular_pendientes(uuid,integer) is
 945|   'Bandeja: llamadas no finales visibles para el actor, más recientes primero, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
 946| comment on function private.llamada_celular_detalle(uuid,uuid) is
 947|   'Detalle de una llamada visible para el actor, con su enlace y efectos_anulados derivado de metadata.deshecho_en del resultado (decisión 4).';
 948| comment on function private.celulares_asignaciones_listar(uuid) is
 949|   'Asignaciones de celulares: gerencia todas, supervisión las de su equipo. Nunca devuelve el hash de la credencial.';
 950| comment on function crm.llamadas_celular_pendientes_fn(integer) is
 951|   'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200.';
 952| comment on function crm.llamada_celular_detalle_fn(uuid) is
 953|   'Puerta (DEFINER) del detalle de una llamada del celular. Analista, supervisión y gerencia, con ámbito.';
 954| comment on function crm.asociar_llamada_celular(uuid,uuid) is
 955|   'Puerta (DEFINER) para asociar una llamada a un lead con su número. Analista, supervisión y gerencia, con ámbito.';
 956| comment on function crm.enlazar_llamada_celular(uuid,uuid) is
 957|   'Puerta (DEFINER) para enlazar una llamada con su resultado registrado (actividad_id de registrar_llamada_v4). Analista, supervisión y gerencia, con ámbito.';
 958| comment on function crm.descartar_llamada_celular(uuid,text,text) is
 959|   'Puerta (DEFINER) para descartar una llamada con motivo. Analista, supervisión y gerencia, con ámbito.';
 960| comment on function crm.celulares_asignaciones_fn() is
 961|   'Puerta (DEFINER) de lectura de asignaciones de celulares: gerencia y supervisión (su equipo).';
 962| comment on function crm.asignar_celular(text,uuid) is
 963|   'Puerta (DEFINER) para asignar un celular: solo gerencia. Devuelve la credencial una sola vez. DATO SENSIBLE en la respuesta.';
 964| comment on function crm.cerrar_asignacion_celular(uuid,text) is
 965|   'Puerta (DEFINER) para cerrar una asignación de celular: solo gerencia.';
 966| comment on function crm.rotar_credencial_celular(text) is
 967|   'Puerta (DEFINER) para rotar la credencial de un celular: solo gerencia. Devuelve la nueva una sola vez. DATO SENSIBLE en la respuesta.';
 968| comment on function crm.llamadas_celular_politica_fn() is
 969|   'Puerta (DEFINER) de lectura de la política de llamadas del celular: solo gerencia.';
 970| comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
 971|   'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor.';
 972| 
 973| -- ── 9. Postflight ────────────────────────────────────────────────────────────────────────
 974| do $postflight$
 975| declare
 976|   v_f record;
 977| begin
 978|   for v_f in
 979|     select * from (values
 980|       ('private.celular_credencial_hash(text)', false, null),
 981|       ('private.llamada_celular_formas(text)', false, null),
 982|       ('private.llamada_celular_candidatos(text[])', false, null),
 983|       ('private.llamada_celular_elegible(uuid,uuid)', false, null),
 984|       ('private.llamada_celular_visible(uuid,uuid,uuid)', false, null),
 985|       ('private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)', false, null),
 986|       ('private.llamadas_celular_actor(text[])', false, null),
 987|       ('private.llamada_celular_ingerir(uuid,jsonb)', false, null),
 988|       ('private.llamada_celular_asociar(uuid,uuid,uuid)', false, null),
 989|       ('private.llamada_celular_enlazar(uuid,uuid,uuid)', false, null),
 990|       ('private.llamada_celular_descartar(uuid,uuid,text,text)', false, null),
 991|       ('private.celular_asignar(uuid,text,uuid)', false, null),
 992|       ('private.celular_cerrar(uuid,uuid,text)', false, null),
 993|       ('private.celular_rotar_credencial(uuid,text)', false, null),
 994|       ('private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)', false, null),
 995|       ('private.llamadas_celular_pendientes(uuid,integer)', false, null),
 996|       ('private.llamada_celular_detalle(uuid,uuid)', false, null),
 997|       ('private.celulares_asignaciones_listar(uuid)', false, null),
 998|       ('crm.llamadas_celular_pendientes_fn(integer)', true, 'authenticated'),
 999|       ('crm.llamada_celular_detalle_fn(uuid)', true, 'authenticated'),
1000|       ('crm.asociar_llamada_celular(uuid,uuid)', true, 'authenticated'),
1001|       ('crm.enlazar_llamada_celular(uuid,uuid)', true, 'authenticated'),
1002|       ('crm.descartar_llamada_celular(uuid,text,text)', true, 'authenticated'),
1003|       ('crm.celulares_asignaciones_fn()', true, 'authenticated'),
1004|       ('crm.asignar_celular(text,uuid)', true, 'authenticated'),
1005|       ('crm.cerrar_asignacion_celular(uuid,text)', true, 'authenticated'),
1006|       ('crm.rotar_credencial_celular(text)', true, 'authenticated'),
1007|       ('crm.llamadas_celular_politica_fn()', true, 'authenticated'),
1008|       ('crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)', true, 'authenticated')
1009|     ) as f(firma, definer, rol)
1010|   loop
1011|     if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
1012|       raise exception 'LLAMADAS_NUCLEO: % debería ser %', v_f.firma,
1013|         case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
1014|     end if;
1015|     if exists (
1016|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
1017|       where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
1018|         and a.grantee <> p.proowner
1019|         and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
1020|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
1021|       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
1022|       raise exception 'LLAMADAS_NUCLEO: EXECUTE inesperado en %', v_f.firma;
1023|     end if;
1024|     if not exists (select 1 from pg_catalog.pg_proc p
1025|                    where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
1026|       raise exception 'LLAMADAS_NUCLEO: search_path inesperado en %', v_f.firma;
1027|     end if;
1028|     if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
1029|       raise exception 'LLAMADAS_NUCLEO: % sin COMMENT', v_f.firma;
1030|     end if;
1031|   end loop;
1032|   -- Las tablas siguen cerradas a la API: el núcleo no abrió ningún privilegio.
1033|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
1034|                     (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
1035|                             ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces')) t(tabla)
1036|              where pg_catalog.has_table_privilege(r.rol, t.tabla,
1037|                      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
1038|     raise exception 'LLAMADAS_NUCLEO: alguna tabla de llamadas quedó accesible desde la API';
1039|   end if;
1040| end;
1041| $postflight$;
1042| 
1043| notify pgrst, 'reload schema';
1044| commit;
```

## Archivo: supabase/migrations/20261001212258_crm_llamadas_celular_ingesta.sql (529 líneas)
```
   1| -- Llamadas desde el celular · F3-a: PUERTAS DE SERVICIO, LÍMITE, SALUD Y BANDEJA PAGINADA.
   2| -- Plan aprobado (Versión 3), fases F3.1 y F3.2 (la parte de la base; la Edge Function es F3-b).
   3| --
   4| -- Qué hace (sobre 20261001145242 y 20261001160219):
   5| --   1. Límite por celular como DATO de la política: limite_envios_minuto (30) y limite_envios_dia
   6| --      (600). Cambiarlo no exige migración.
   7| --   2. private.celulares_estado: una fila por asignación con lo que el SERVIDOR sabe del celular:
   8| --      último envío, último latido (versión de la macro, eventos en cola) y los contadores del
   9| --      límite (minuto de reloj y día de Lima). Tabla técnica en private, como las colas y los
  10| --      contadores del repo (private.agenda_reparto_diaria, private.contrato_pdf_jobs): fuera de la
  11| --      API y fuera de la regla de rastro, que cubre las tablas de negocio de crm y public. Cambia
  12| --      con cada envío; auditarla copiaría una fila por llamada a public.audit_log, que no tiene
  13| --      retención. La evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos.
  14| --   3. Núcleo (INVOKER, sin EXECUTE para nadie; solo lo llaman las puertas de abajo):
  15| --      · celular_por_credencial(clave): la asignación vigente con analista activo cuyo hash
  16| --        coincide, o null. La clave en claro nunca se guarda ni se compara: solo su sha256.
  17| --      · celular_consumir_envio(asignación): cuenta el envío o lanza P0429 con los segundos de
  18| --        espera en el DETAIL («reintentar_en_seg=N»). Lo comparten llamadas y latidos (F3.2.2).
  19| --      · celular_registrar_salud(asignación, latido): latido v1 con claves exactas.
  20| --      · llamadas_celular_bandeja(actor, límite, cursor) y celulares_salud_listar(actor).
  21| --   4. Puertas de SERVICIO (DEFINER, EXECUTE solo service_role; las llamará la Edge Function de F3-b
  22| --      con la clave de servicio, como crm.agenda_ics_feed_fn): ingerir_llamada_celular_servicio y
  23| --      registrar_salud_celular_servicio. Clave ausente, desconocida, de una asignación cerrada o de
  24| --      un analista de baja → el MISMO 42501 «No autorizado», sin pistas, también si la asignación
  25| --      se cierra mientras la llamada espera su candado. A la Edge solo le devuelven lo que el
  26| --      celular necesita (evento_id, repetido, ignorado, motivo): nunca el lead ni su atención.
  27| --   5. Puertas de lectura (DEFINER, EXECUTE solo authenticated): llamadas_celular_bandeja_fn (la
  28| --      bandeja paginada por cursor recibido_en + evento_id, con las mismas filas que la de F2-c) y
  29| --      celulares_salud_fn (gerencia, todos los celulares vigentes; supervisión, los de su equipo).
  30| --
  31| -- Decisiones provisionales de Jhosep (01/10/2026, F3-PLAN-CORTO.md), que Miguel ratifica o cambia
  32| -- antes de aplicar esto fuera del banco: clave por celular con verify_jwt=false en la Edge (1);
  33| -- 30 envíos por minuto y 600 al día (2); latido cada 6 h y al vaciar la cola (3); el celular
  34| -- abre la encuesta de F1 por número (4, lo resuelve la Edge).
  35| --
  36| -- Decisiones de criterio de Claude (01/10/2026), para Miguel:
  37| --   · La tabla técnica va en private y sin auditoría (punto 2).
  38| --   · Solo cuenta para el límite lo que se confirma: un envío que muere con error (cuerpo
  39| --     inválido, conflicto) se deshace entero, contador incluido. La Edge filtra los cuerpos
  40| --     inválidos antes de llegar aquí.
  41| --   · Ventanas fijas: el minuto de reloj y el día calendario de Lima.
  42| --   · Los límites no tienen todavía puerta para cambiarlos: llegará con la pantalla de gerencia (F4).
  43| --
  44| -- Reversión: ../scripts/llamadas-celular/reversa-ingesta.sql (retira puertas, núcleo, la tabla
  45| -- técnica y las dos columnas de la política; la evidencia queda). Verificación: npm run
  46| -- test:llamadas:local (banco reducido + oráculo + mutantes + concurrencia).
  47| begin;
  48| set local lock_timeout = '5s';
  49| set local statement_timeout = '60s';
  50| 
  51| do $precondicion$
  52| begin
  53|   if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
  54|      or to_regprocedure('private.celular_credencial_hash(text)') is null
  55|      or to_regprocedure('private.llamadas_celular_actor(text[])') is null
  56|      or to_regprocedure('private.llamada_celular_visible(uuid,uuid,uuid)') is null
  57|      or to_regprocedure('private.llamada_celular_atencion_efectiva(uuid,text,text,uuid)') is null
  58|      or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
  59|      or to_regprocedure('private.rol_crm(uuid)') is null then
  60|     raise exception 'LLAMADAS_INGESTA: falta el núcleo de 20261001160219 (F2-c)';
  61|   end if;
  62|   if to_regclass('private.celulares_estado') is not null
  63|      or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is not null
  64|      or exists (select 1 from pg_catalog.pg_attribute a
  65|                 where a.attrelid = 'crm.llamadas_celular_politica'::regclass
  66|                   and a.attname in ('limite_envios_minuto', 'limite_envios_dia') and not a.attisdropped) then
  67|     raise exception 'LLAMADAS_INGESTA: los objetos ya existen; no se sobrescriben';
  68|   end if;
  69| end;
  70| $precondicion$;
  71| 
  72| -- ── 1. Límite por celular en la política ─────────────────────────────────────────────────────
  73| alter table crm.llamadas_celular_politica
  74|   add column limite_envios_minuto integer not null default 30
  75|     constraint llamadas_celular_politica_limite_minuto_rango check (limite_envios_minuto between 1 and 600),
  76|   add column limite_envios_dia integer not null default 600
  77|     constraint llamadas_celular_politica_limite_dia_rango check (limite_envios_dia between 1 and 20000),
  78|   add constraint llamadas_celular_politica_limites_coherentes check (limite_envios_minuto <= limite_envios_dia);
  79| 
  80| -- ── 2. Estado técnico de cada celular ────────────────────────────────────────────────────────
  81| create table private.celulares_estado (
  82|   id                uuid primary key default gen_random_uuid(),
  83|   asignacion_id     uuid not null references crm.celulares_asignaciones(id) on delete restrict
  84|                     constraint celulares_estado_asignacion_uq unique,
  85|   ultimo_envio_en   timestamptz,
  86|   ultimo_latido_en  timestamptz,
  87|   latido_celular_en timestamptz,
  88|   version_macro     text
  89|                     constraint celulares_estado_version_valida
  90|                     check (version_macro is null or version_macro ~ '^[A-Za-z0-9._ -]{1,40}$'),
  91|   eventos_en_cola   integer
  92|                     constraint celulares_estado_cola_rango
  93|                     check (eventos_en_cola is null or eventos_en_cola between 0 and 100000),
  94|   minuto_desde      timestamptz,
  95|   envios_minuto     integer not null default 0
  96|                     constraint celulares_estado_envios_minuto_validos check (envios_minuto >= 0),
  97|   dia               date,
  98|   envios_dia        integer not null default 0
  99|                     constraint celulares_estado_envios_dia_validos check (envios_dia >= 0),
 100|   creado_en         timestamptz not null default now(),
 101|   actualizado_en    timestamptz not null default now()
 102| );
 103| alter table private.celulares_estado enable row level security;
 104| revoke all on private.celulares_estado from public, anon, authenticated, service_role;
 105| 
 106| create function private.trg_celulares_estado_candado()
 107| returns trigger
 108| language plpgsql
 109| security definer
 110| set search_path to ''
 111| as $function$
 112| begin
 113|   if tg_op = 'DELETE' then
 114|     raise exception using errcode = '42501', message = 'El estado de un celular no se borra: guarda su límite de envíos';
 115|   end if;
 116|   if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.creado_en <> old.creado_en then
 117|     raise exception using errcode = '42501', message = 'El estado de un celular no cambia de asignación';
 118|   end if;
 119|   new.actualizado_en := pg_catalog.now();
 120|   return new;
 121| end;
 122| $function$;
 123| create trigger trg_celulares_estado_00_candado
 124|   before update or delete on private.celulares_estado
 125|   for each row execute function private.trg_celulares_estado_candado();
 126| 
 127| -- ── 3. Núcleo (INVOKER, sin EXECUTE para nadie) ──────────────────────────────────────────────
 128| create function private.celular_por_credencial(p_credencial text)
 129| returns uuid
 130| language sql
 131| stable
 132| set search_path = ''
 133| as $function$
 134|   select a.id
 135|   from crm.celulares_asignaciones a
 136|   where a.credencial_hash = private.celular_credencial_hash(p_credencial)
 137|     and a.vigente_hasta is null
 138|     and coalesce(private.rol_crm(a.analista_id), '') in ('vendedor', 'supervisor')
 139| $function$;
 140| 
 141| create function private.celular_consumir_envio(p_asignacion_id uuid)
 142| returns void
 143| language plpgsql
 144| volatile
 145| set search_path = ''
 146| as $function$
 147| declare
 148|   v_pol crm.llamadas_celular_politica%rowtype;
 149|   v_est private.celulares_estado%rowtype;
 150|   v_ahora timestamptz := pg_catalog.now();
 151|   v_minuto timestamptz := pg_catalog.date_trunc('minute', pg_catalog.now());
 152|   v_dia date := (pg_catalog.now() at time zone 'America/Lima')::date;
 153|   v_min integer;
 154|   v_dia_n integer;
 155| begin
 156|   select * into v_pol from crm.llamadas_celular_politica p where p.singleton;
 157|   insert into private.celulares_estado (asignacion_id) values (p_asignacion_id)
 158|   on conflict (asignacion_id) do nothing;
 159|   select * into v_est from private.celulares_estado s where s.asignacion_id = p_asignacion_id for update;
 160|   -- Ventanas fijas: el minuto de reloj y el día de Lima. Si la ventana cambió, se cuenta desde cero.
 161|   v_min := case when v_est.minuto_desde = v_minuto then v_est.envios_minuto else 0 end;
 162|   v_dia_n := case when v_est.dia = v_dia then v_est.envios_dia else 0 end;
 163|   -- Primero el día: si los dos están agotados, la espera que cuenta es la más larga.
 164|   if v_dia_n >= v_pol.limite_envios_dia then
 165|     raise exception using errcode = 'P0429',
 166|       message = 'Este celular llegó a su límite de envíos del día',
 167|       detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
 168|         extract(epoch from (((v_dia + 1)::timestamp at time zone 'America/Lima') - v_ahora)))::integer));
 169|   end if;
 170|   if v_min >= v_pol.limite_envios_minuto then
 171|     raise exception using errcode = 'P0429',
 172|       message = 'Demasiados envíos de este celular en un minuto',
 173|       detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
 174|         extract(epoch from (v_minuto + interval '1 minute' - v_ahora)))::integer));
 175|   end if;
 176|   update private.celulares_estado
 177|      set minuto_desde = v_minuto, envios_minuto = v_min + 1, dia = v_dia, envios_dia = v_dia_n + 1
 178|    where id = v_est.id;
 179| end;
 180| $function$;
 181| 
 182| create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb)
 183| returns jsonb
 184| language plpgsql
 185| volatile
 186| set search_path = ''
 187| as $function$
 188| declare
 189|   v_claves constant text[] := array['v', 'version_macro', 'en_cola', 'ocurrio_en'];
 190|   v_version text;
 191|   v_cola integer;
 192|   v_ocurrio timestamptz;
 193| begin
 194|   if p_latido is null or pg_catalog.jsonb_typeof(p_latido) <> 'object' then
 195|     raise exception using errcode = '22023', message = 'El latido debe ser un objeto JSON';
 196|   end if;
 197|   if exists (select 1 from pg_catalog.jsonb_object_keys(p_latido) k where k <> all(v_claves)) then
 198|     raise exception using errcode = '22023', message = 'El latido trae claves no previstas';
 199|   end if;
 200|   if coalesce(p_latido ->> 'v', '') <> '1' then
 201|     raise exception using errcode = '22023', message = 'Versión de latido no soportada (se espera v = 1)';
 202|   end if;
 203|   v_version := p_latido ->> 'version_macro';
 204|   if v_version is null or v_version !~ '^[A-Za-z0-9._ -]{1,40}$' then
 205|     raise exception using errcode = '22023', message = 'version_macro inválida (1 a 40 caracteres: letras, dígitos, espacio y . _ -)';
 206|   end if;
 207|   begin
 208|     v_cola := (p_latido ->> 'en_cola')::integer;
 209|     v_ocurrio := (p_latido ->> 'ocurrio_en')::timestamptz;
 210|   exception when others then
 211|     raise exception using errcode = '22023', message = 'en_cola u ocurrio_en con formato inválido';
 212|   end;
 213|   if v_cola is null or v_cola not between 0 and 100000 then
 214|     raise exception using errcode = '22023', message = 'en_cola es obligatorio y va de 0 a 100000';
 215|   end if;
 216|   if v_ocurrio is not null and (v_ocurrio < timestamptz '2026-01-01 00:00Z' or v_ocurrio >= timestamptz '2100-01-01 00:00Z') then
 217|     raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
 218|   end if;
 219|   update private.celulares_estado
 220|      set ultimo_latido_en = pg_catalog.now(), latido_celular_en = v_ocurrio,
 221|          version_macro = v_version, eventos_en_cola = v_cola
 222|    where asignacion_id = p_asignacion_id;
 223|   if not found then
 224|     -- La puerta cuenta el envío antes (y eso crea la fila): llegar aquí sin estado es un error de orden.
 225|     raise exception using errcode = '55000', message = 'El celular no tiene estado: el envío no se contó antes del latido';
 226|   end if;
 227|   return pg_catalog.jsonb_build_object('registrado', true);
 228| end;
 229| $function$;
 230| 
 231| create function private.llamadas_celular_bandeja(
 232|   p_actor uuid, p_limite integer, p_antes_recibido_en timestamptz, p_antes_id uuid)
 233| returns jsonb
 234| language sql
 235| stable
 236| set search_path = ''
 237| as $function$
 238|   with limitada as (
 239|     select e.id, e.recibido_en, e.ocurrio_en, e.numero_canonico, e.direccion, e.estado_tecnico,
 240|            e.duracion_seg, e.identificacion, e.atencion, e.lead_id, e.analista_id,
 241|            l.nombre_completo as lead_nombre
 242|     from crm.llamadas_celular_eventos e
 243|     left join crm.leads l on l.id = e.lead_id
 244|     where e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 245|       and (p_antes_recibido_en is null or (e.recibido_en, e.id) < (p_antes_recibido_en, p_antes_id))
 246|       and private.llamada_celular_visible(p_actor, e.lead_id, e.analista_id)
 247|     order by e.recibido_en desc, e.id desc
 248|     limit p_limite + 1
 249|   ), pagina as (
 250|     select x.*, pg_catalog.row_number() over (order by x.recibido_en desc, x.id desc) as n
 251|     from limitada x
 252|   )
 253|   select pg_catalog.jsonb_build_object(
 254|     -- La misma forma de fila que private.llamadas_celular_pendientes (F2-c).
 255|     'filas', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 256|                'evento_id', p.id, 'recibido_en', p.recibido_en, 'ocurrio_en', p.ocurrio_en,
 257|                'numero', p.numero_canonico, 'direccion', p.direccion, 'estado_tecnico', p.estado_tecnico,
 258|                'duracion_seg', p.duracion_seg, 'identificacion', p.identificacion,
 259|                'atencion', private.llamada_celular_atencion_efectiva(p_actor, p.atencion, p.identificacion, p.lead_id),
 260|                'lead_id', p.lead_id, 'lead_nombre', p.lead_nombre,
 261|                'analista_id', p.analista_id, 'es_propia', p.analista_id = p_actor)
 262|              order by p.n) filter (where p.n <= p_limite), '[]'::jsonb),
 263|     'siguiente', (select pg_catalog.jsonb_build_object('recibido_en', u.recibido_en, 'evento_id', u.id)
 264|                   from pagina u
 265|                   where u.n = p_limite and exists (select 1 from pagina m where m.n > p_limite)))
 266|   from pagina p
 267| $function$;
 268| 
 269| create function private.celulares_salud_listar(p_actor uuid)
 270| returns jsonb
 271| language sql
 272| stable
 273| set search_path = ''
 274| as $function$
 275|   select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 276|            'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
 277|            'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
 278|            'ultimo_envio_en', s.ultimo_envio_en, 'ultimo_latido_en', s.ultimo_latido_en,
 279|            'latido_celular_en', s.latido_celular_en, 'version_macro', s.version_macro,
 280|            'eventos_en_cola', s.eventos_en_cola,
 281|            'envios_hoy', case when s.dia = (pg_catalog.now() at time zone 'America/Lima')::date
 282|                               then s.envios_dia else 0 end)
 283|          order by a.etiqueta), '[]'::jsonb)
 284|   from crm.celulares_asignaciones a
 285|   left join private.celulares_estado s on s.asignacion_id = a.id
 286|   left join public.perfiles p on p.id = a.analista_id
 287|   where a.vigente_hasta is null
 288|     and (private.rol_crm(p_actor) = 'gerencia'
 289|          or (private.rol_crm(p_actor) = 'supervisor'
 290|              and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
 291| $function$;
 292| 
 293| -- ── 4. Puertas de servicio (crm, DEFINER, EXECUTE solo service_role) ─────────────────────────
 294| create function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
 295| returns jsonb
 296| language plpgsql
 297| volatile
 298| security definer
 299| set search_path = ''
 300| as $function$
 301| declare
 302|   v_asig uuid := private.celular_por_credencial(p_credencial);
 303|   v_r jsonb;
 304| begin
 305|   if v_asig is null then
 306|     raise exception using errcode = '42501', message = 'No autorizado';
 307|   end if;
 308|   perform private.celular_consumir_envio(v_asig);
 309|   begin
 310|     v_r := private.llamada_celular_ingerir(v_asig, p_evento);
 311|   exception when insufficient_privilege then
 312|     -- Cerrada o dada de baja mientras esperaba el candado: la misma respuesta, sin pistas.
 313|     raise exception using errcode = '42501', message = 'No autorizado';
 314|   end;
 315|   update private.celulares_estado set ultimo_envio_en = pg_catalog.now() where asignacion_id = v_asig;
 316|   -- A la Edge, solo lo que el celular necesita: nunca el lead ni su atención.
 317|   return pg_catalog.jsonb_build_object('evento_id', v_r -> 'evento_id', 'repetido', v_r -> 'repetido',
 318|     'ignorado', v_r -> 'ignorado', 'motivo', v_r -> 'motivo');
 319| end;
 320| $function$;
 321| 
 322| create function crm.registrar_salud_celular_servicio(p_credencial text, p_latido jsonb)
 323| returns jsonb
 324| language plpgsql
 325| volatile
 326| security definer
 327| set search_path = ''
 328| as $function$
 329| declare
 330|   v_asig uuid := private.celular_por_credencial(p_credencial);
 331| begin
 332|   if v_asig is null then
 333|     raise exception using errcode = '42501', message = 'No autorizado';
 334|   end if;
 335|   perform private.celular_consumir_envio(v_asig);
 336|   return private.celular_registrar_salud(v_asig, p_latido);
 337| end;
 338| $function$;
 339| 
 340| -- ── 5. Puertas de lectura (crm, DEFINER, EXECUTE solo authenticated) ─────────────────────────
 341| create function crm.llamadas_celular_bandeja_fn(
 342|   p_limite integer default 50, p_antes_recibido_en timestamptz default null, p_antes_id uuid default null)
 343| returns jsonb
 344| language plpgsql
 345| stable
 346| security definer
 347| set search_path = ''
 348| as $function$
 349| declare
 350|   v_actor uuid := private.llamadas_celular_actor(array['vendedor', 'supervisor', 'gerencia']);
 351| begin
 352|   if p_limite is null or p_limite not between 1 and 200 then
 353|     raise exception using errcode = '22023', message = 'El límite va de 1 a 200';
 354|   end if;
 355|   if (p_antes_recibido_en is null) <> (p_antes_id is null) then
 356|     raise exception using errcode = '22023', message = 'El cursor lleva recibido_en y evento_id juntos';
 357|   end if;
 358|   return private.llamadas_celular_bandeja(v_actor, p_limite, p_antes_recibido_en, p_antes_id);
 359| end;
 360| $function$;
 361| 
 362| create function crm.celulares_salud_fn()
 363| returns jsonb
 364| language plpgsql
 365| stable
 366| security definer
 367| set search_path = ''
 368| as $function$
 369| declare
 370|   v_actor uuid := private.llamadas_celular_actor(array['supervisor', 'gerencia']);
 371| begin
 372|   return private.celulares_salud_listar(v_actor);
 373| end;
 374| $function$;
 375| 
 376| -- ── 6. Permisos ──────────────────────────────────────────────────────────────────────────────
 377| do $permisos$
 378| declare
 379|   v_f text;
 380| begin
 381|   foreach v_f in array array[
 382|     'private.trg_celulares_estado_candado()', 'private.celular_por_credencial(text)',
 383|     'private.celular_consumir_envio(uuid)', 'private.celular_registrar_salud(uuid,jsonb)',
 384|     'private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)',
 385|     'private.celulares_salud_listar(uuid)'] loop
 386|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 387|   end loop;
 388|   foreach v_f in array array[
 389|     'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'crm.registrar_salud_celular_servicio(text,jsonb)'] loop
 390|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 391|     execute pg_catalog.format('grant execute on function %s to service_role', v_f);
 392|   end loop;
 393|   foreach v_f in array array[
 394|     'crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', 'crm.celulares_salud_fn()'] loop
 395|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 396|     execute pg_catalog.format('grant execute on function %s to authenticated', v_f);
 397|   end loop;
 398| end;
 399| $permisos$;
 400| 
 401| -- ── 7. Comentarios ───────────────────────────────────────────────────────────────────────────
 402| comment on column crm.llamadas_celular_politica.limite_envios_minuto is 'Envíos que acepta un celular por minuto de reloj (30, decisión 2 de F3, provisional de Jhosep 01/10). Lo comparten las llamadas y los latidos; al pasarse, P0429 con la espera.';
 403| comment on column crm.llamadas_celular_politica.limite_envios_dia is 'Envíos que acepta un celular por día de Lima (600, decisión 2 de F3). No menor que limite_envios_minuto.';
 404| 
 405| comment on table private.celulares_estado is
 406|   'Estado técnico de cada celular asignado (F3-a): último envío, último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima). Una fila por asignación. Tabla técnica de private, sin acceso para la API y sin auditoría: cambia con cada envío, no guarda datos personales ni secretos, y la evidencia de cada llamada ya vive, auditada, en crm.llamadas_celular_eventos. Sin columna de tenant: CRM de una sola empresa.';
 407| comment on column private.celulares_estado.id is 'Identificador de la fila.';
 408| comment on column private.celulares_estado.asignacion_id is 'Asignación de celular a la que pertenece (una fila por asignación; no cambia).';
 409| comment on column private.celulares_estado.ultimo_envio_en is 'Cuándo llegó y se confirmó la última llamada de este celular (hora del servidor).';
 410| comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor). Un latido solo prueba que el celular habla, no que capture bien.';
 411| comment on column private.celulares_estado.latido_celular_en is 'Hora del celular en el último latido, si la mandó; contrasta con ultimo_latido_en.';
 412| comment on column private.celulares_estado.version_macro is 'Versión de la macro que declaró el último latido (texto corto del celular, no confiable).';
 413| comment on column private.celulares_estado.eventos_en_cola is 'Llamadas que el celular dijo tener pendientes de enviar en su último latido (no confiable).';
 414| comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto.';
 415| comment on column private.celulares_estado.envios_minuto is 'Envíos confirmados en el minuto minuto_desde.';
 416| comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia.';
 417| comment on column private.celulares_estado.envios_dia is 'Envíos confirmados en el día dia.';
 418| comment on column private.celulares_estado.creado_en is 'Alta de la fila (primer envío del celular).';
 419| comment on column private.celulares_estado.actualizado_en is 'Último cambio (lo sella el trigger).';
 420| 
 421| comment on function private.trg_celulares_estado_candado() is
 422|   'Candado de private.celulares_estado: sin DELETE (borrar la fila reiniciaría el límite) y sin cambiar de asignación; sella actualizado_en. SECURITY DEFINER por coherencia con los candados de F2-b; no lee datos.';
 423| comment on function private.celular_por_credencial(text) is
 424|   'Resuelve la clave de un celular: la asignación vigente, con analista o supervisor activo, cuyo credencial_hash es el sha256 de la clave; null en cualquier otro caso. DATO SENSIBLE: recibe la clave en claro y no la guarda.';
 425| comment on function private.celular_consumir_envio(uuid) is
 426|   'Límite por celular (F3.2.2, compartido por llamadas y latidos): bloquea la fila de estado, reinicia las ventanas fijas (minuto de reloj, día de Lima) y cuenta el envío; al pasarse, P0429 con DETAIL reintentar_en_seg=N. Se deshace con el envío si este falla.';
 427| comment on function private.celular_registrar_salud(uuid,jsonb) is
 428|   'Latido v1 del celular con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional): guarda versión, cola y hora en private.celulares_estado. Un latido no demuestra captura sana.';
 429| comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
 430|   'Bandeja paginada de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente; filas con la misma forma que private.llamadas_celular_pendientes y la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
 431| comment on function private.celulares_salud_listar(uuid) is
 432|   'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Sin hash de credencial.';
 433| comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
 434|   'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge Function crm-llamadas-ingesta de F3-b) para ingerir la llamada de un celular con su clave. Clave ausente, desconocida, cerrada o de un analista de baja: el mismo 42501 «No autorizado». Cuenta el envío (P0429 al pasarse) y delega en private.llamada_celular_ingerir. Devuelve solo evento_id, repetido, ignorado y motivo. DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
 435| comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
 436|   'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular con su clave: misma autorización uniforme y mismo límite que la ingesta. DATO SENSIBLE: recibe la clave.';
 437| comment on function crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid) is
 438|   'Puerta (DEFINER: las tablas no tienen privilegios para la API) de la bandeja paginada de llamadas del celular. Analista, supervisión y gerencia; límite 1 a 200; el cursor (recibido_en y evento_id juntos) es el campo siguiente de la página anterior.';
 439| comment on function crm.celulares_salud_fn() is
 440|   'Puerta (DEFINER) de lectura de la salud de los celulares: gerencia y supervisión (su equipo).';
 441| 
 442| -- ── 8. Postflight ────────────────────────────────────────────────────────────────────────────
 443| do $postflight$
 444| declare
 445|   v_f record;
 446| begin
 447|   if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'private.celulares_estado'::regclass) then
 448|     raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin RLS';
 449|   end if;
 450|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
 451|              where pg_catalog.has_table_privilege(r.rol, 'private.celulares_estado',
 452|                      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
 453|     raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó accesible desde la API';
 454|   end if;
 455|   if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'private.celulares_estado'::regclass) then
 456|     raise exception 'LLAMADAS_INGESTA: private.celulares_estado no debe tener policies (todo va por puertas)';
 457|   end if;
 458|   if not exists (select 1 from pg_catalog.pg_trigger t
 459|                  where t.tgrelid = 'private.celulares_estado'::regclass and not t.tgisinternal
 460|                    and t.tgname = 'trg_celulares_estado_00_candado' and t.tgenabled in ('O', 'A')) then
 461|     raise exception 'LLAMADAS_INGESTA: private.celulares_estado quedó sin su candado';
 462|   end if;
 463|   if exists (select 1 from pg_catalog.pg_constraint c
 464|              where c.contype = 'f' and c.conrelid = 'private.celulares_estado'::regclass and c.confdeltype <> 'r') then
 465|     raise exception 'LLAMADAS_INGESTA: la FK de private.celulares_estado no es RESTRICT';
 466|   end if;
 467|   if pg_catalog.obj_description('private.celulares_estado'::regclass, 'pg_class') is null
 468|      or exists (select 1 from pg_catalog.pg_attribute a
 469|                 where a.attnum > 0 and not a.attisdropped
 470|                   and pg_catalog.col_description(a.attrelid, a.attnum) is null
 471|                   and (a.attrelid = 'private.celulares_estado'::regclass
 472|                        or (a.attrelid = 'crm.llamadas_celular_politica'::regclass
 473|                            and a.attname in ('limite_envios_minuto', 'limite_envios_dia')))) then
 474|     raise exception 'LLAMADAS_INGESTA: falta COMMENT en la tabla técnica o en los límites de la política';
 475|   end if;
 476|   if (select p.limite_envios_minuto <> 30 or p.limite_envios_dia <> 600
 477|       from crm.llamadas_celular_politica p where p.singleton) is distinct from false then
 478|     raise exception 'LLAMADAS_INGESTA: los límites de la política no quedaron en 30 por minuto y 600 al día';
 479|   end if;
 480| 
 481|   for v_f in
 482|     select * from (values
 483|       ('private.trg_celulares_estado_candado()', true, null),
 484|       ('private.celular_por_credencial(text)', false, null),
 485|       ('private.celular_consumir_envio(uuid)', false, null),
 486|       ('private.celular_registrar_salud(uuid,jsonb)', false, null),
 487|       ('private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid)', false, null),
 488|       ('private.celulares_salud_listar(uuid)', false, null),
 489|       ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
 490|       ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
 491|       ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
 492|       ('crm.celulares_salud_fn()', true, 'authenticated')
 493|     ) as f(firma, definer, rol)
 494|   loop
 495|     if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
 496|       raise exception 'LLAMADAS_INGESTA: % debería ser %', v_f.firma,
 497|         case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
 498|     end if;
 499|     if exists (
 500|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
 501|       where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
 502|         and a.grantee <> p.proowner
 503|         and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
 504|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
 505|       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
 506|       raise exception 'LLAMADAS_INGESTA: EXECUTE inesperado en %', v_f.firma;
 507|     end if;
 508|     if not exists (select 1 from pg_catalog.pg_proc p
 509|                    where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
 510|       raise exception 'LLAMADAS_INGESTA: search_path inesperado en %', v_f.firma;
 511|     end if;
 512|     if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
 513|       raise exception 'LLAMADAS_INGESTA: % sin COMMENT', v_f.firma;
 514|     end if;
 515|   end loop;
 516| 
 517|   -- Las tablas de F2 siguen cerradas a la API: esta migración no abrió ningún privilegio.
 518|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
 519|                     (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
 520|                             ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces')) t(tabla)
 521|              where pg_catalog.has_table_privilege(r.rol, t.tabla,
 522|                      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
 523|     raise exception 'LLAMADAS_INGESTA: alguna tabla de llamadas quedó accesible desde la API';
 524|   end if;
 525| end;
 526| $postflight$;
 527| 
 528| notify pgrst, 'reload schema';
 529| commit;
```

## Archivo: supabase/migrations/20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql (265 líneas)
```
   1| -- Llamadas desde el celular · corrección de F2-c: LA ELEGIBILIDAD SE EVALÚA COMO EL DUEÑO DEL CELULAR.
   2| -- Plan aprobado (Versión 3); decisión 1 del contrato de F2 (provisional de Jhosep, 30/09/2026).
   3| --
   4| -- El fallo (comprobado en un banco desechable el 01/10/2026): la ingesta llega sin sesión (la Edge
   5| -- entrará con la clave de servicio) y la regla de ámbito del CRM (private.sla_gestion_permitida →
   6| -- private.vendedor_ids_visibles) solo responde a quien pregunta por sí mismo. Resultado: la llamada
   7| -- del celular de un SUPERVISOR a un lead de su equipo entraba «por revisar» y nunca pedía resultado.
   8| -- La del analista a su propio lead no fallaba, porque se reconoce por vendedor_id.
   9| --
  10| -- Qué hace:
  11| --   1. private.llamada_celular_elegible_dueno(dueño, lead): evalúa la decisión 1 con la regla REAL
  12| --      (private.llamada_celular_elegible) COMO el dueño del celular. Fija request.jwt.claim.sub al
  13| --      dueño solo durante esa consulta y devuelve la identidad anterior en el acto, antes de que la
  14| --      ingesta escriba nada: la bitácora del evento sigue sin atribuirse a nadie.
  15| --   2. private.llamada_celular_ingerir: el cuerpo de 20261001160219, copiado tal cual, con UNA línea
  16| --      cambiada: la atención inicial usa el ayudante de arriba.
  17| --
  18| -- Decisión de criterio de Claude (01/10/2026), para Miguel: reutilizar la regla de ámbito real
  19| -- evaluándola como el dueño, en vez de copiarla en un ayudante propio que podría desviarse de ella.
  20| -- El dueño sale de la asignación vigente del celular (servidor), nunca del cliente.
  21| --
  22| -- Reversión: ../scripts/llamadas-celular/reversa-elegibilidad.sql (devuelve el cuerpo de F2-c y retira
  23| -- el ayudante). Verificación: npm run test:llamadas:local (oráculo tests/llamadas-celular/oraculo-elegibilidad.sql).
  24| begin;
  25| set local lock_timeout = '5s';
  26| set local statement_timeout = '60s';
  27| 
  28| do $precondicion$
  29| begin
  30|   if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
  31|      or to_regprocedure('private.llamada_celular_elegible(uuid,uuid)') is null then
  32|     raise exception 'LLAMADAS_ELEGIBILIDAD: falta el núcleo de 20261001160219 (F2-c)';
  33|   end if;
  34|   if to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is not null then
  35|     raise exception 'LLAMADAS_ELEGIBILIDAD: los objetos ya existen; no se sobrescriben';
  36|   end if;
  37| end;
  38| $precondicion$;
  39| 
  40| -- ── 1. Elegibilidad como el dueño del celular ────────────────────────────────────────────────
  41| create function private.llamada_celular_elegible_dueno(p_dueno uuid, p_lead uuid)
  42| returns boolean
  43| language plpgsql
  44| volatile
  45| set search_path = ''
  46| as $function$
  47| declare
  48|   v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
  49|   v_elegible boolean;
  50| begin
  51|   perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_dueno::text, ''), true);
  52|   v_elegible := coalesce(private.llamada_celular_elegible(p_dueno, p_lead), false);
  53|   -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
  54|   perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
  55|   return v_elegible;
  56| end;
  57| $function$;
  58| 
  59| -- ── 2. Ingesta con la elegibilidad del dueño (cuerpo de 20261001160219, una línea cambiada) ──
  60| create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb)
  61| returns jsonb
  62| language plpgsql
  63| volatile
  64| set search_path = ''
  65| as $function$
  66| declare
  67|   v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
  68|                                     'duracion_seg', 'ocurrio_en'];
  69|   v_asig crm.celulares_asignaciones%rowtype;
  70|   v_pol crm.llamadas_celular_politica%rowtype;
  71|   v_previo crm.llamadas_celular_eventos%rowtype;
  72|   v_origen text;
  73|   v_numero text;
  74|   v_dir text;
  75|   v_estado text;
  76|   v_dur integer;
  77|   v_ocurrio timestamptz;
  78|   v_hash text;
  79|   v_formas text[];
  80|   v_e164 text;
  81|   v_cand uuid[];
  82|   v_lead uuid;
  83|   v_ident text;
  84|   v_aten text;
  85|   v_metodo text;
  86|   v_calidad jsonb := '{}'::jsonb;
  87|   v_id uuid;
  88| begin
  89|   -- Forma del evento: objeto, claves exactas, versión 1.
  90|   if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
  91|     raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
  92|   end if;
  93|   if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
  94|     raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
  95|   end if;
  96|   if coalesce(p_evento ->> 'v', '') <> '1' then
  97|     raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
  98|   end if;
  99|   v_origen := p_evento ->> 'evento_origen_id';
 100|   if v_origen is null or v_origen !~ '^[A-Za-z0-9._:+-]{4,120}$' then
 101|     raise exception using errcode = '22023', message = 'evento_origen_id inválido (4 a 120 caracteres: letras, dígitos y . _ : + -)';
 102|   end if;
 103|   v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
 104|   if pg_catalog.length(v_numero) > 40 then
 105|     raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
 106|   end if;
 107|   v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
 108|   if v_dir not in ('saliente', 'entrante', 'desconocida') then
 109|     raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
 110|   end if;
 111|   v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
 112|   if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
 113|     raise exception using errcode = '22023', message = 'estado_tecnico inválido';
 114|   end if;
 115|   begin
 116|     v_dur := (p_evento ->> 'duracion_seg')::integer;
 117|     v_ocurrio := (p_evento ->> 'ocurrio_en')::timestamptz;
 118|   exception when others then
 119|     raise exception using errcode = '22023', message = 'duracion_seg u ocurrio_en con formato inválido';
 120|   end;
 121|   if v_dur is not null and v_dur not between 0 and 86400 then
 122|     raise exception using errcode = '22023', message = 'duracion_seg fuera de rango (0 a 86400)';
 123|   end if;
 124|   if v_ocurrio is not null and (v_ocurrio < timestamptz '2026-01-01 00:00Z' or v_ocurrio >= timestamptz '2100-01-01 00:00Z') then
 125|     raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
 126|   end if;
 127| 
 128|   -- Asignación vigente con analista activo (F3: credencial revocada o analista dado de baja).
 129|   select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
 130|   if not found or v_asig.vigente_hasta is not null
 131|      or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 132|     raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
 133|   end if;
 134| 
 135|   -- Contenido canónico (la hora en UTC: el mismo instante con otra zona es el MISMO contenido).
 136|   v_hash := private.idem_hash(pg_catalog.jsonb_build_object(
 137|     'v', 1, 'evento_origen_id', v_origen, 'numero', v_numero, 'direccion', v_dir,
 138|     'estado_tecnico', v_estado, 'duracion_seg', v_dur,
 139|     'ocurrio_en', pg_catalog.to_char(v_ocurrio at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
 140| 
 141|   select * into v_previo from crm.llamadas_celular_eventos e
 142|   where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
 143|   if found then
 144|     if v_previo.hash_payload <> v_hash then
 145|       raise exception using errcode = 'P0409',
 146|         message = 'Esta llamada ya llegó con otro contenido; no se puede reenviar así';
 147|     end if;
 148|     return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
 149|       'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
 150|   end if;
 151| 
 152|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 153| 
 154|   -- Decisión 2: con las entrantes apagadas, una entrante no se guarda.
 155|   if v_dir = 'entrante' and not coalesce(v_pol.entrantes_activas, false) then
 156|     return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true, 'motivo', 'entrante_apagada');
 157|   end if;
 158|   if v_dir = 'desconocida' then
 159|     v_calidad := v_calidad || '{"direccion": "desconocida"}'::jsonb;
 160|   end if;
 161|   if v_ocurrio is not null and v_ocurrio > pg_catalog.now() + interval '5 minutes' then
 162|     v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
 163|   end if;
 164| 
 165|   v_formas := private.llamada_celular_formas(v_numero);
 166|   v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
 167|   if v_e164 is null and v_numero is not null then
 168|     v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
 169|   elsif v_numero is null then
 170|     v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
 171|   end if;
 172|   v_cand := private.llamada_celular_candidatos(v_formas);
 173| 
 174|   if pg_catalog.cardinality(v_cand) = 1 then
 175|     v_lead := v_cand[1];
 176|     v_ident := 'identificado';
 177|     v_metodo := 'exacto';
 178|     v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
 179|                    then 'requiere_resultado' else 'por_revisar' end;
 180|   elsif pg_catalog.cardinality(v_cand) > 1 then
 181|     v_ident := 'ambiguo';
 182|     v_aten := 'por_revisar';
 183|     v_calidad := v_calidad || pg_catalog.jsonb_build_object('candidatos', pg_catalog.cardinality(v_cand));
 184|   elsif coalesce(v_pol.guardar_sin_identificar, false) then
 185|     v_ident := 'sin_identificar';
 186|     v_aten := 'por_revisar';
 187|   else
 188|     -- Decisión 3: si el número no es de ningún lead, la llamada no pertenece al CRM.
 189|     return pg_catalog.jsonb_build_object('repetido', false, 'ignorado', true,
 190|       'motivo', case when pg_catalog.cardinality(v_formas) = 0 then 'numero_no_valido' else 'sin_lead' end);
 191|   end if;
 192| 
 193|   insert into crm.llamadas_celular_eventos
 194|     (asignacion_id, analista_id, evento_origen_id, hash_payload, numero_canonico, direccion,
 195|      estado_tecnico, duracion_seg, ocurrio_en, calidad, identificacion, atencion, lead_id,
 196|      metodo_asociacion, asociado_en)
 197|   values
 198|     -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
 199|     -- volver a buscar candidatos al asociar.
 200|     (v_asig.id, v_asig.analista_id, v_origen, v_hash, coalesce(v_e164, v_formas[1]), v_dir,
 201|      v_estado, v_dur, v_ocurrio, v_calidad, v_ident, v_aten, v_lead,
 202|      v_metodo, case when v_lead is not null then pg_catalog.now() end)
 203|   on conflict on constraint llamadas_celular_eventos_origen_unico do nothing
 204|   returning id into v_id;
 205| 
 206|   if v_id is null then
 207|     -- Dos envíos a la vez del mismo origen: gana el primero; el segundo responde como repetido
 208|     -- (o conflicto si su contenido es otro).
 209|     select * into v_previo from crm.llamadas_celular_eventos e
 210|     where e.asignacion_id = p_asignacion_id and e.evento_origen_id = v_origen;
 211|     if v_previo.hash_payload <> v_hash then
 212|       raise exception using errcode = 'P0409',
 213|         message = 'Esta llamada llegó a la vez con otro contenido; no se puede reenviar así';
 214|     end if;
 215|     return pg_catalog.jsonb_build_object('evento_id', v_previo.id, 'repetido', true, 'ignorado', false,
 216|       'identificacion', v_previo.identificacion, 'atencion', v_previo.atencion, 'lead_id', v_previo.lead_id);
 217|   end if;
 218| 
 219|   return pg_catalog.jsonb_build_object('evento_id', v_id, 'repetido', false, 'ignorado', false,
 220|     'identificacion', v_ident, 'atencion', v_aten, 'lead_id', v_lead);
 221| end;
 222| $function$;
 223| 
 224| -- ── 3. Permisos: núcleo sin EXECUTE para nadie ───────────────────────────────────────────────
 225| revoke all on function private.llamada_celular_elegible_dueno(uuid,uuid) from public, anon, authenticated, service_role;
 226| revoke all on function private.llamada_celular_ingerir(uuid,jsonb) from public, anon, authenticated, service_role;
 227| 
 228| -- ── 4. Comentarios ───────────────────────────────────────────────────────────────────────────
 229| comment on function private.llamada_celular_elegible_dueno(uuid,uuid) is
 230|   'Decisión 1 evaluada COMO el dueño del celular: fija request.jwt.claim.sub al dueño solo durante private.llamada_celular_elegible (la regla de ámbito real, que exige que el actor sea quien pregunta) y devuelve la identidad anterior antes de que la ingesta escriba. Sin dueño, no es elegible. Solo la usa la ingesta, que llega sin sesión.';
 231| comment on function private.llamada_celular_ingerir(uuid,jsonb) is
 232|   'Núcleo de la ingesta (F3 lo llamará desde su puerta de servicio): evento v1 con claves exactas; asignación vigente con analista activo (42501); canonización con las dos reglas y coincidencia exacta; un lead → identificado (pide resultado si es elegible), varios → ambiguo, ninguno → no se guarda (decisión 3, perilla guardar_sin_identificar); entrante con entrantes apagadas → no se guarda. Idempotente: mismo origen + contenido → repetido; otro contenido → P0409. DATO PERSONAL: el número. Desde 20261001222431 la atención inicial se evalúa como el dueño del celular (private.llamada_celular_elegible_dueno).';
 233| 
 234| -- ── 5. Postflight ────────────────────────────────────────────────────────────────────────────
 235| do $postflight$
 236| declare
 237|   v_f text;
 238| begin
 239|   foreach v_f in array array['private.llamada_celular_elegible_dueno(uuid,uuid)', 'private.llamada_celular_ingerir(uuid,jsonb)'] loop
 240|     if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
 241|       raise exception 'LLAMADAS_ELEGIBILIDAD: % debería ser SECURITY INVOKER', v_f;
 242|     end if;
 243|     if exists (
 244|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
 245|       where p.oid = v_f::regprocedure and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
 246|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f::regprocedure) then
 247|       raise exception 'LLAMADAS_ELEGIBILIDAD: EXECUTE inesperado en %', v_f;
 248|     end if;
 249|     if not exists (select 1 from pg_catalog.pg_proc p
 250|                    where p.oid = v_f::regprocedure and p.proconfig @> array['search_path=""']) then
 251|       raise exception 'LLAMADAS_ELEGIBILIDAD: search_path inesperado en %', v_f;
 252|     end if;
 253|     if pg_catalog.obj_description(v_f::regprocedure, 'pg_proc') is null then
 254|       raise exception 'LLAMADAS_ELEGIBILIDAD: % sin COMMENT', v_f;
 255|     end if;
 256|   end loop;
 257|   if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
 258|                        'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0 then
 259|     raise exception 'LLAMADAS_ELEGIBILIDAD: la ingesta no evalúa la elegibilidad como el dueño del celular';
 260|   end if;
 261| end;
 262| $postflight$;
 263| 
 264| notify pgrst, 'reload schema';
 265| commit;
```

## Archivo: supabase/functions/crm-llamadas-ingesta/handler.ts (149 líneas)
```
   1| // crm-llamadas-ingesta — recibe del celular corporativo el aviso de cada llamada y su latido de salud.
   2| //
   3| // Seguridad (F3, decisión 1 provisional de Jhosep, 01/10/2026): se despliega con verify_jwt=false
   4| // porque MacroDroid no tiene sesión de usuario. El control es la CLAVE DEL CELULAR, que viaja en la
   5| // cabecera x-celular-credencial (nunca en la URL). La base solo guarda su sha256 y la valida en una
   6| // RPC que solo puede llamar service_role; cualquier problema de clave responde el MISMO 401.
   7| // Cuerpo ≤ 4 KB leído por partes, esquema estricto y límite por celular en la base (P0429 → 429 con
   8| // Retry-After).
   9| //
  10| // La respuesta al celular es la misma para una llamada guardada, repetida o ignorada (propuesta #12):
  11| // no delata si un número es de un lead. El celular abre siempre la encuesta de F1 por número
  12| // (decisión 4), que busca con la sesión del analista y solo en su cartera.
  13| //
  14| // Núcleo verificable sin red ni credenciales: las RPC llegan inyectadas desde index.ts.
  15| // Nunca registra cabeceras, cuerpo ni la clave.
  16| 
  17| type Json = Record<string, unknown>;
  18| export type ErrorRpc = { code?: unknown; message?: unknown; details?: unknown };
  19| export type Dependencias = {
  20|   /** Raíz del CRM, sin barra final (https://crm.miavance.com). */
  21|   urlCrm: string;
  22|   ingerir: (credencial: string, evento: Json) => Promise<unknown>;
  23|   registrarSalud: (credencial: string, latido: Json) => Promise<unknown>;
  24| };
  25| 
  26| const TOPE_BYTES = 4096;
  27| const CREDENCIAL = /^[0-9a-f]{64}$/;
  28| const ORIGEN = /^[A-Za-z0-9._:+-]{4,120}$/;
  29| const VERSION_MACRO = /^[A-Za-z0-9._ -]{1,40}$/;
  30| const CLAVES_EVENTO = new Set(['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico', 'duracion_seg', 'ocurrio_en']);
  31| const CLAVES_LATIDO = new Set(['v', 'version_macro', 'en_cola', 'ocurrio_en']);
  32| const DIRECCIONES = new Set(['saliente', 'entrante', 'desconocida']);
  33| const ESTADOS = new Set(['conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido']);
  34| 
  35| const esObjeto = (x: unknown): x is Json => typeof x === 'object' && x !== null && !Array.isArray(x);
  36| const opcional = (x: unknown, valido: (v: unknown) => boolean) => x === undefined || x === null || valido(x);
  37| const entero = (x: unknown, minimo: number, maximo: number) =>
  38|   typeof x === 'number' && Number.isInteger(x) && x >= minimo && x <= maximo;
  39| const fecha = (x: unknown) => typeof x === 'string' && x.length <= 40 && !Number.isNaN(Date.parse(x));
  40| 
  41| /** El mismo contrato v1 que valida la base (private.llamada_celular_ingerir): claves exactas. */
  42| export function eventoValido(e: unknown): e is Json {
  43|   if (!esObjeto(e) || Object.keys(e).some((k) => !CLAVES_EVENTO.has(k))) return false;
  44|   return e.v === 1
  45|     && typeof e.evento_origen_id === 'string' && ORIGEN.test(e.evento_origen_id)
  46|     && opcional(e.numero, (n) => typeof n === 'string' && n.length <= 40)
  47|     && opcional(e.direccion, (d) => typeof d === 'string' && DIRECCIONES.has(d))
  48|     && opcional(e.estado_tecnico, (s) => typeof s === 'string' && ESTADOS.has(s))
  49|     && opcional(e.duracion_seg, (d) => entero(d, 0, 86400))
  50|     && opcional(e.ocurrio_en, fecha);
  51| }
  52| 
  53| /** El latido v1 de private.celular_registrar_salud: versión de la macro y cola obligatorias. */
  54| export function latidoValido(l: unknown): l is Json {
  55|   if (!esObjeto(l) || Object.keys(l).some((k) => !CLAVES_LATIDO.has(k))) return false;
  56|   return l.v === 1
  57|     && typeof l.version_macro === 'string' && VERSION_MACRO.test(l.version_macro)
  58|     && entero(l.en_cola, 0, 100000)
  59|     && opcional(l.ocurrio_en, fecha);
  60| }
  61| 
  62| /** La URL que abre el celular tras enviar: la encuesta de F1 por número (decisión 4); sin número, Mi día. */
  63| export function urlAbrir(base: string, numero: unknown): string {
  64|   const raiz = `${base.replace(/\/+$/, '')}/#/gestion-diaria`;
  65|   return typeof numero === 'string' && numero.trim() !== ''
  66|     ? `${raiz}/llamada/${encodeURIComponent(numero.trim())}`
  67|     : raiz;
  68| }
  69| 
  70| /** Los segundos que la base pide esperar (DETAIL «reintentar_en_seg=N»); 60 si no los dice. */
  71| export function segundosDeEspera(detalle: unknown): number {
  72|   const m = typeof detalle === 'string' ? /^reintentar_en_seg=(\d{1,6})$/.exec(detalle) : null;
  73|   const n = m ? Number(m[1]) : Number.NaN;
  74|   return Number.isInteger(n) && n >= 1 ? n : 60;
  75| }
  76| 
  77| // Marca de «cuerpo demasiado grande»: un símbolo, que ningún JSON puede producir.
  78| const GRANDE = Symbol('grande');
  79| async function leerJson(req: Request): Promise<unknown> {
  80|   const lector = req.body?.getReader();
  81|   const partes: Uint8Array<ArrayBuffer>[] = [];
  82|   let longitud = 0;
  83|   if (lector) for (;;) {
  84|     const { done, value } = await lector.read();
  85|     if (done) break;
  86|     longitud += value.byteLength;
  87|     if (longitud > TOPE_BYTES) { await lector.cancel(); return GRANDE; }
  88|     partes.push(new Uint8Array(value));
  89|   }
  90|   return JSON.parse(await new Blob(partes).text());
  91| }
  92| 
  93| export function crearHandler(d: Dependencias) {
  94|   return async (req: Request): Promise<Response> => {
  95|     const respuesta = (estado: number, cuerpo: Json, extra: Record<string, string> = {}) =>
  96|       new Response(JSON.stringify(cuerpo), {
  97|         status: estado,
  98|         headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  99|       });
 100|     // Una sola respuesta para todo problema de clave: no se distingue ausente, mal formada,
 101|     // desconocida, revocada o de un analista de baja.
 102|     const noAutorizado = () => respuesta(401, { error: 'No autorizado' });
 103| 
 104|     // Sin CORS: no la llama un navegador, la llama la macro del celular.
 105|     if (req.method !== 'POST') return respuesta(405, { error: 'Método no admitido' }, { Allow: 'POST' });
 106|     const tipo = (req.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
 107|     if (tipo !== 'application/json') return respuesta(415, { error: 'El cuerpo debe ser JSON' });
 108|     // La clave se mira antes que el cuerpo: sin una clave con forma válida no se revela nada más.
 109|     const credencial = req.headers.get('x-celular-credencial') ?? '';
 110|     if (!CREDENCIAL.test(credencial)) return noAutorizado();
 111| 
 112|     let cuerpo: unknown;
 113|     try {
 114|       cuerpo = await leerJson(req);
 115|     } catch {
 116|       return respuesta(400, { error: 'Petición inválida' });
 117|     }
 118|     if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });
 119|     if (!esObjeto(cuerpo) || Object.keys(cuerpo).length !== 2) return respuesta(400, { error: 'Petición inválida' });
 120|     const llamada = cuerpo.accion === 'llamada' && eventoValido(cuerpo.evento);
 121|     const latido = cuerpo.accion === 'latido' && latidoValido(cuerpo.latido);
 122|     if (!llamada && !latido) return respuesta(400, { error: 'Petición inválida' });
 123| 
 124|     try {
 125|       if (llamada) {
 126|         const evento = cuerpo.evento as Json;
 127|         await d.ingerir(credencial, evento);
 128|         // Guardada, repetida o ignorada: la misma respuesta (propuesta #12).
 129|         return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, evento.numero) });
 130|       }
 131|       await d.registrarSalud(credencial, cuerpo.latido as Json);
 132|       return respuesta(200, { registrado: true });
 133|     } catch (error) {
 134|       const e: ErrorRpc = esObjeto(error) ? error : {};
 135|       if (e.code === '42501') return noAutorizado();
 136|       if (e.code === 'P0429') {
 137|         const espera = segundosDeEspera(e.details);
 138|         return respuesta(429, { error: 'Demasiados envíos de este celular', reintentar_en_seg: espera },
 139|           { 'Retry-After': String(espera) });
 140|       }
 141|       if (e.code === 'P0409') return respuesta(409, { error: 'Esta llamada ya llegó con otro contenido' });
 142|       // Los 22023 de la base son mensajes escritos para quien arma la macro: se devuelven tal cual.
 143|       if (e.code === '22023') {
 144|         return respuesta(400, { error: typeof e.message === 'string' ? e.message.slice(0, 200) : 'Petición inválida' });
 145|       }
 146|       return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
 147|     }
 148|   };
 149| }
```

## Archivo: supabase/functions/crm-llamadas-ingesta/index.ts (23 líneas)
```
   1| import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
   2| import { crearHandler } from './handler.ts';
   3| 
   4| // La clave de servicio vive en los secretos de Supabase y no sale de esta función: solo la usan las
   5| // dos RPC de servicio de F3-a (20261001212258), que validan la clave del celular en la base.
   6| const fetchAcotado: typeof fetch = (entrada, opciones) => fetch(entrada, {
   7|   ...opciones, signal: AbortSignal.timeout(8000),
   8| });
   9| const servicio = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  10|   global: { fetch: fetchAcotado },
  11|   auth: { persistSession: false, autoRefreshToken: false },
  12| });
  13| async function rpc(nombre: string, argumentos: Record<string, unknown>): Promise<unknown> {
  14|   const { data, error } = await servicio.schema('crm').rpc(nombre, argumentos);
  15|   if (error) throw error;
  16|   return data;
  17| }
  18| 
  19| Deno.serve(crearHandler({
  20|   urlCrm: 'https://crm.miavance.com',
  21|   ingerir: (credencial, evento) => rpc('ingerir_llamada_celular_servicio', { p_credencial: credencial, p_evento: evento }),
  22|   registrarSalud: (credencial, latido) => rpc('registrar_salud_celular_servicio', { p_credencial: credencial, p_latido: latido }),
  23| }));
```
