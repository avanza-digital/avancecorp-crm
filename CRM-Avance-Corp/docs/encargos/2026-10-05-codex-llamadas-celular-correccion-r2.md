ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (transcrito al final).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí (los
archivos llevan número de línea). Formato: VERDICT (PASS/BLOCK), SUMMARY, RESPUESTA a cada pregunta P1–P10 (sí/no +
por qué, con evidencia archivo:línea del texto transcrito), FINDINGS P0–P3 nuevos, RIESGOS y test gaps, NEXT ACTIONS,
CONFIDENCE. Pídete REFUTAR: busca lo que el diff no cierra o lo que rompe, no lo que está bien.

# Encargo: «Llamadas desde el celular» — DIFF de la corrección de F2 + F3 (quinta migración, F4-a y Edge) — LEVEL 3
(datos, permisos, autenticación por credencial de dispositivo, migraciones, concurrencia).
**Ronda 2 de máx. 2 (la última de la tarea).** La ronda 1 revisó el diseño (BLOCK, 6 P2 + 1 P3); esta revisa el
código. Generado el 2026-10-05 desde `aa67d856` (rama `crm/llamadas-quinta-migracion-20261005`, PR #190) con
`supabase/scripts/llamadas-celular/generar-encargo-r2.mjs`. Lo corre Miguel con `scripts/codex-review-mcp`.

## Qué es
CRM interno (Supabase/Postgres 17). Esquema `crm` expuesto por PostgREST (puertas = funciones no trigger de `crm`),
núcleo en `private`, tablas con RLS sin policies ni grants. Un celular corporativo (Android + MacroDroid) avisa cada
llamada del analista: POST a la Edge `crm-llamadas-ingesta` (verify_jwt=false) con la clave del celular en
`x-celular-credencial`; la Edge llama con service_role a `crm.ingerir_llamada_celular_servicio`. El analista registra
el resultado con su sesión (encuesta v4 en producción; con F4-a, la v5). Seis migraciones SIN aplicar: las cuatro de
F2 + F3 (en `main`), la quinta (corrección) y F4-a. Se publican juntas con la Edge.

## Commits que se revisan (sobre `origin/main`)
- aa67d856 CRM: llamadas desde el celular — el encargo r2 incluye el bloque del gate y sus riesgos
- 14f82382 CRM: llamadas desde el celular — el gate prueba la quinta y F4-a (sin correr)
- 835c25c5 CRM: llamadas desde el celular — guías de publicación y de la macro sin Pro; el alta muestra la clave (sin publicar)
- ccbeb1db CRM: llamadas desde el celular — Edge con el contrato nuevo: la base valida, la Edge solo revisa el transporte (sin desplegar)
- 260c0a4a CRM: llamadas desde el celular — las reversas solo corren antes de dar de alta celulares (revisión de Miguel, #190)
- 4f5e2597 CRM: llamadas desde el celular — F4-a, enlace exacto encuesta ↔ llamada (sin aplicar)
- 2f1d5f99 CRM: llamadas desde el celular — tablero: la quinta va en el PR #190 (borrador)
- 3cd72e1b CRM: llamadas desde el celular — quinta migración, corrección de F2 + F3 (sin aplicar)

## Decisiones de negocio vigentes
**Miguel (03/10, PR #175):** (1) F2 + F3 se publican junto con el enlace exacto F4-a; (2) entrantes bloqueadas, la #14
después; (3) llamada a un lead de otro analista = número sin lead; (4) sin resultado → 30 días desde `recibido_en`,
registradas se conservan como historial; (5) la pista por tiempo de respuesta es riesgo aceptado por escrito; (6) se
retira la bandeja vieja; (7) leads sin dueño y descartados reutilizables son candidatos (por revisar; quien llamó no
la ve; le aparece a quien lo tome). Confirmaciones: al deshacer, el enlace pasa al resultado corregido; la regla
«resultado posterior a la llamada» solo vale para el enlace manual; #12 = «la respuesta, el cupo y el estado no delatan;
el tiempo es riesgo aceptado».
**Jhosep (05/10):** la fusión del plan v2 (#179) cuenta como el OK de Miguel, con la N1 según la recomendación (la salud
del celular sin `envios_hoy` ni `ultimo_envio_en`); en F4-a un enlace imposible NO impide guardar el resultado
(responde `no_enlazado` con su motivo) y una llamada ambigua no se une por el camino exacto; las reversas solo corren
antes de dar de alta celulares (respuesta al [P2] del agente de Miguel, abajo).

## Calibración: dentro del CRM, saber si un teléfono existe NO es secreto
«Nuevo lead» le dice a cualquier analista con sesión si un teléfono ya es de un lead (en bolsa, tomado por alguien,
en enfriamiento o reutilizable). La protección del #12 es frente a quien tiene la clave de un celular SIN sesión del
CRM (una macro exportada, un exempleado). Transcrito más abajo: `app/src/lib/disponibilidad-lead.ts` y la regla de la
base `private.verificar_disponibilidad_lead_impl`.

## Preguntas para el revisor
- **P1 (fallo 1, #12).** Con la recepción antes de buscar el lead, el contrato `{resultado, mensaje}` y el cupo gastado
  por todo inválido (también el JSON mal formado que la Edge reenvía con la carga en null), ¿queda algún observable
  —código HTTP, cuerpo, cupo, estado o salud visibles— que distinga un número de lead de uno sin lead, aparte del
  tiempo (riesgo aceptado, incluido el 503 por espera de candado)?
- **P2 (id, P2-2/P2-3 de tu r1).** ¿La forma `C<n>-<10 dígitos>`, la etiqueta de la asignación, la ventana
  [−30 días, +1 día] y la recepción de 32 días cierran el teléfono en el id, la etiqueta reutilizada y la reaceptación
  de un id viejo? ¿Algún borde con la purga, la rotación o el cierre?
- **P3 (§2 candidatos).** ¿La identidad temporal del dueño vuelve en todos los caminos (éxito, error, dentro del bloque
  que atrapa 22023)? ¿Las condiciones (b) «en bolsa» y (c) «reutilizable» reproducen las de
  `verificar_disponibilidad_lead_impl`? ¿El efecto aceptado de (c) —el antiguo dueño de un descartado reutilizable ve
  la llamada de otro analista hasta que alguien lo tome— abre algo más?
- **P4 (§3 candados, P2-4/P10).** Con los órdenes de asociar, enlazar y descartar (quinta), de la v5 y del cumplimiento
  de la intención en la ingesta (F4-a), de Deshacer, de la v4, de la purga y de rotar/cerrar: ¿hay un ciclo posible?
  ¿El 40001 cubre el cambio de lead? ¿Falta alguna revalidación tras los candados?
- **P5 (F4-a).** ¿La v5 compone la v4 sellada sin alterar su semántica (replay por operación, recibo, candado del
  lead)? ¿La intención y su cumplimiento pueden perder o duplicar un enlace, o unir un resultado a la llamada
  equivocada? ¿Guardar el resultado cuando el enlace es imposible deja algún estado incoherente?
- **P6 (§5 retención).** ¿La purga respeta: sin resolver (identificadas sin enlace y ambiguas) a 30 días desde
  `recibido_en`; registradas (con enlace, aunque deshechas) se conservan; descartadas por su plazo; recepciones e
  intenciones a 32 días? ¿Está bien cubierto el caso de un enlace concurrente con la purga (relectura de la fila)?
- **P7 (reversas, [P2] del agente de Miguel).** ¿La guarda «sin asignaciones (ni cerradas), estado, recepciones,
  llamadas, enlaces ni intenciones, bajo candado» basta y es atómica? ¿Alguna ruta borra asignaciones o estado?
- **P8 (Edge, P2-1 de tu r1).** ¿El contrato de transporte deja algún inválido sin gastar cupo, alguna respuesta que
  dependa de lo que pasó dentro de la base, o algún orden 401/413 que distinga más de lo aceptado?
- **P9 (lecturas).** Salud, bandeja, detalle y asignaciones: ¿alguna deja ver llamadas personales, llamadas de leads dados
  de baja o de otro equipo?
- **P10 (pruebas).** El banco reducido usa la v4 como DOBLE declarado. El bloque `testLlamadasCelular` del gate
  (transcrito) usa la v4 REAL y sesiones reales, pero todavía NO SE CORRIÓ. ¿Qué prueba mal o le falta antes de
  publicar? Riesgos que el PRIMARY no pudo descartar sin correrlo: `tomar_lead_libre` sobre un reutilizable (nunca
  corrió en el gate; con `resolver_en_puertas` encendida decide el juicio de reapertura), la v4 real sobre un lead
  creado por inserción de admin y el descarte vencido fechado fuera de banda en `replica`.

## Tu r1 (BLOCK, 6 P2 + 1 P3) → dónde se cierra en el código
| Hallazgo r1 | Dónde mirar |
| --- | --- |
| P2-1 La Edge no acompaña el arreglo | `handler.ts` (contrato de transporte) y las puertas de servicio de la quinta |
| P2-2 El sha256 no protege un teléfono | quinta: id `C<n>-<10 dígitos>`, ventana y etiqueta (`private.llamada_celular_ingerir`) |
| P2-3 Etiqueta e id reutilizados | quinta: unicidad por id, recepción de 32 días, ventana |
| P2-4 Candados incompletos | quinta: asociar, enlazar, descartar; F4-a: v5, `llamada_celular_cumplir_intencion`, ingesta |
| P2-5 Reloj adelantado | F4-a: `llamada_celular_enlazar_exacto` sin la regla de 10 minutos |
| P2-6 Sin barrera si falla la quinta | precondiciones (tablas vacías bajo candado) y reversas |
| P3-7 Rotar reinicia el cupo | documentado (estado por asignación; solo gerencia rota) |

## Revisión puntual del agente de Miguel (05/10, sobre `22e46f5b`): CHANGES_REQUESTED, [P2] reproducido
La reversa de la quinta solo miraba recepciones y llamadas; la purga retira las recepciones a los 32 días, así que tras
un aviso ignorado y su caducidad la reversa volvía a correr con claves vigentes. Corregido en `260c0a4a` con su opción
conservadora: las reversas de la quinta y de F4-a exigen bajo candado que no haya asignaciones (ni cerradas), estado,
recepciones ni llamadas (y en F4-a, tampoco enlaces ni intenciones). Regresión (aviso ignorado → purga real → claves
rotadas y cerradas → la reversa se niega) y un mutante por reversa.

## Verificación ejecutada por el PRIMARY (no la repites: no tienes shell)
- `npm run test:llamadas:local` (PostgreSQL 17, banco reducido con copias reales de auditoría, ámbito, canonización
  e idempotencia, y la v4 como doble declarado): pasadas de las cuatro (160), de la quinta (oráculo, reversa con huella
  exacta del catálogo, 41 mutantes, 9 carreras con dos sesiones + 4 mutantes de candados) y de F4-a (oráculo, reversa
  con huella exacta, 26 mutantes, 4 carreras), más la regresión del [P2] — todo en verde en el commit generado.
- Edge: `handler.test.ts` 15/15 y 15 mutantes cazados; receptor de pruebas del PC 10/10.
- Gate: bloque `testLlamadasCelular` cotejado a mano con las migraciones (firmas, códigos, mensajes y formas de
  respuesta); `node --check` y oxlint limpios. La limpieza entre corridas, probada en un Postgres local.
- NOT RUN: gate `test-rls.mjs` con el esquema de producción, advisors, la v4 real y `banco/verificar-hallazgos.sql`
  (los corre Miguel en su banco).

## Archivo: .ai/REVIEW_PROTOCOL.md (10 líneas) — protocolo de revisión
```
   1| commit aa67d8561525fd29ab6a1b0628e3479f72c09c4f
   2| Author: Jhosep <jhosep@miavance.com>
   3| Date:   Mon Oct 5 12:33:21 2026 -0500
   4| 
   5|     CRM: llamadas desde el celular — el encargo r2 incluye el bloque del gate y sus riesgos
   6|     
   7|     P10 pregunta por el bloque testLlamadasCelular (v4 real, sin correr) y
   8|     nombra los tres riesgos que no se pudieron descartar sin correrlo. La
   9|     verificación del PRIMARY suma el cotejo del gate y la limpieza entre
  10|     corridas; el tramo del gate lleva su comentario de cabecera.
```

## Archivo: docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md (380 líneas) — el plan v2 que el código implementa
```
   1| # Corrección de la revisión de F2 + F3 — plan corto v2 (para el OK de Miguel)
   2| 
   3| Escrito el 03/10/2026 en la sesión de Jhosep, que escribe la corrección (confirmación 1 de Miguel). **Solo análisis:
   4| sin SQL ni código.** Reemplaza la v1 (PR #171). Responde a:
   5| - la revisión de Miguel (`REVISION-2026-10-02.md`);
   6| - la ronda 1 de Codex sobre la v1: **BLOCK**, 6 P2 y 1 P3
   7|   (`docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1-respuesta.md`);
   8| - los tres comentarios de Miguel en el #175: la séptima decisión, las observaciones de su sesión y su respuesta.
   9| 
  10| Base: `origin/main` `00a482a3`. Las 4 migraciones están en `main` y **sin aplicar**.
  11| 
  12| ## Qué cambió desde la v1
  13| 
  14| - Miguel decidió las seis decisiones y una séptima: los leads sin dueño y los descartados reutilizables también son
  15|   candidatos (tabla al final).
  16| - Cada hallazgo de Codex tiene su arreglo; la tabla del final dice dónde.
  17| - El id de la llamada tiene **una forma fija** (`C1-<segundos>`) y se guarda tal cual, sin hash.
  18| - La recepción va en `private` y caduca a los 32 días: ya no es permanente.
  19| - La Edge deja de validar el contenido: la base es la única que valida, y todo inválido gasta cupo.
  20| - Los candados siguen **un solo orden**, sacado de las rutas reales de Deshacer y de la encuesta.
  21| - **Nuevo, para tu OK:** la salud del celular deja de mostrar `envios_hoy` y `ultimo_envio_en` (§6).
  22| - Lo imprescindible para publicar va separado de lo que es mejora (tabla antes de las pruebas).
  23| 
  24| ## En una línea
  25| 
  26| Una quinta migración cierra los fallos 1–4 y los menores sin editar las cuatro fusionadas. Se publica junto con F4-a,
  27| que une cada encuesta con su llamada (decisión 1).
  28| 
  29| ## Cómo se aplica
  30| 
  31| - **Orden:** datos → núcleo → ingesta → elegibilidad → quinta, cada una con su registrador **justo después**. Así
  32|   `registrar-nucleo` y `registrar-elegibilidad` no chocan con lo que la quinta retira (corrección 3 de Miguel al
  33|   #173). F4-a va después, con su propia migración.
  34| - **Tablas vacías:** la precondición de la quinta lo exige y, si encuentra filas, se niega. Por eso puede cambiar
  35|   tablas sin migrar datos.
  36| - **Barrera (Codex P2-6):** no se despliega la Edge ni se da de alta ningún celular hasta verificar la quinta. Sin Edge
  37|   y sin claves, las puertas de las cuatro no exponen nada: las tablas están vacías.
  38| - **Reversa (Codex P11):**
  39|   - antes del primer aviso, la reversa de la quinta vuelve al estado de las cuatro;
  40|   - después, la quinta no se revierte, porque reinstalaría las fugas: se apaga (retirar la Edge, cerrar las
  41|     asignaciones), se corrige hacia adelante y se conservan los hechos.
  42| - La v4 de la encuesta (sellada por md5) no se toca: F4-a la envuelve.
  43| 
  44| ## 1. El id, la recepción y el orden de la puerta (fallo 1; menores 6, 7, 9, 11, 12, 13 y 15)
  45| 
  46| ### El id de la llamada (Codex P2-2 y P2-3)
  47| 
  48| - **Forma única:** `C<n>-<10 dígitos>`, la etiqueta del celular más los segundos de su reloj. Es lo que la macro ya
  49|   genera, una vez por llamada, al colgar (`macrodroid.md:130, 141`). Ejemplo: `C1-1790980958`.
  50| - La etiqueta del id tiene que ser **la de la asignación** de la clave.
  51| - Los segundos tienen que caer entre **hace 30 días y dentro de 1 día**, con la hora del servidor.
  52| - Fuera de eso → «inválido» (400). La macro lo aparta en `errores_llamadas` sin trabar la cola (`macrodroid.md:71`).
  53| - **Por qué basta, sin hash, HMAC ni id aleatorio:**
  54|   - no puede llevar un teléfono: un móvil peruano tiene 9 dígitos, y la ventana solo deja valores cercanos a la hora
  55|     actual;
  56|   - una etiqueta reutilizada no choca: cada llamada tiene su segundo;
  57|   - un id de hace más de 30 días no vuelve a entrar.
  58| - Se guarda tal cual. F4 encuentra la llamada por el id completo (Codex P11).
  59| 
  60| ### La recepción
  61| 
  62| - Tabla nueva **`private.llamadas_celular_recepciones`**: una fila por cada llamada aceptada, **antes** de buscar el
  63|   lead, también si después se ignora. Única por id.
  64| - **En `private`, no en `crm` (Codex P11):** es una tabla técnica sin bitácora, como `private.celulares_estado`.
  65| - **Caduca a los 32 días** (30 de ventana + 1 de tolerancia + 1 de margen): pasado ese plazo, su id ya no puede volver
  66|   a aceptarse. Así no queda un registro eterno de a qué hora llamaba el analista, llamadas personales incluidas
  67|   (Codex P9).
  68| - **Recepción y llamada se confirman en la misma transacción.** Nada atrapa un fallo al guardar la llamada para
  69|   confirmar solo la recepción (Codex P1).
  70| - La llamada (`crm.llamadas_celular_eventos`) conserva su `evento_origen_id`, ahora **único por id**. Antes era único
  71|   por asignación + id, y rotar la clave duplicaba (menor 9).
  72| - Se retira `hash_payload`: solo servía para el 409, que desaparece.
  73| 
  74| ### El orden de la puerta (llamadas y latidos)
  75| 
  76| 1. **Clave** → asignación `FOR SHARE`, revalidada: vigente y analista activo. Si no, 401 (menor 6).
  77| 2. **Estado del celular** `FOR UPDATE`. Recién ahí se toma la hora (`clock_timestamp()`), una sola vez (Codex P2):
  78|    - la ventana del cupo nunca retrocede (menor 7);
  79|    - el `Retry-After` sale de esa hora;
  80|    - las marcas de salud usan esa hora, no `now()`.
  81| 3. **Cupo.** Sin fila de política, error explícito (menor 13).
  82| 4. **Validación**, forma del id incluida. Un inválido devuelve el resultado «inválido» y el cupo gastado queda
  83|    (menor 11, Codex P3).
  84| 5. **Recepción**, solo en llamadas. Si ya existía → «aceptado», sin buscar nada: el primer envío gana. Los latidos no
  85|    tienen id y no pasan por aquí (Codex P11).
  86| 6. Solo si es nueva: política, búsqueda del lead (§2) y la llamada, si corresponde.
  87| 
  88| El `P0409` desaparece de la ingesta, y con él el 409 de la Edge.
  89| 
  90| ### El contrato entre la Edge y la base (Codex P2-1)
  91| 
  92| - **La base es la única que valida el contenido** y devuelve un resultado con forma fija: `aceptado` o `invalido`, con
  93|   un mensaje para quien arma la macro.
  94| - Errores esperados: `42501` → 401; `P0429` → 429 con `Retry-After`. Lo inesperado → 503, que revierte todo, el cupo
  95|   incluido.
  96| - **La Edge lee ese resultado:** `aceptado` → 202 (llamada) o 200 (latido); `invalido` → 400.
  97| - **Lo que la Edge contesta sin tocar la base** (no gasta cupo y no depende de ningún lead):
  98|   - método distinto de POST → 405;
  99|   - tipo distinto de JSON → 415;
 100|   - cabecera de clave sin forma válida → 401;
 101|   - cuerpo de más de 4 KB → 413, cortando la lectura.
 102| - **Todo lo demás llega a la base**, también el JSON mal formado y el sobre inválido. La Edge solo elige la puerta por
 103|   `accion`; la base autentica, gasta cupo y devuelve `invalido`.
 104| - En la base, la validación va en un bloque que atrapa **solo** `22023`, con el cupo ya gastado antes del bloque
 105|   (Codex P3: sin `WHEN OTHERS`).
 106| - **Fecha estricta:** ISO 8601 con zona, validada en la base (menor 15). Acepta el espacio que usa `{datetime}`.
 107| - Guardada, repetida o ignorada: el mismo 202, con la URL de la encuesta.
 108| 
 109| ### Lo que no cierra
 110| 
 111| - **El tiempo de respuesta:** riesgo aceptado por escrito (decisión 5). La #12 queda así: «la respuesta, el cupo y el
 112|   estado no delatan si un número es de un lead; el tiempo es riesgo aceptado» (confirmación 4).
 113| - Un 503 por esperar un candado solo puede darse cuando hay lead. Es la misma pista de tiempo, rara y fuera del control
 114|   de quien envía: queda dentro del riesgo aceptado (Codex P1).
 115| - **Calibración** (sesión de Miguel, #175): dentro del CRM, saber si un teléfono existe no es secreto. «Nuevo lead» se
 116|   lo dice a cualquier analista (`app/src/lib/disponibilidad-lead.ts:8-59`). Esto protege frente a quien tiene la clave
 117|   de un celular **sin** sesión del CRM: una macro exportada, un exempleado.
 118| 
 119| ## 2. Qué lead puede ser de la llamada (fallos 2 y 4; decisiones 3 y 7; Codex P5)
 120| 
 121| **Candidatos:** leads activos con el número (las dos formas canónicas, `nucleo:87-113`) que cumplan una de tres:
 122| - **(a) Del ámbito del dueño del celular**, evaluado **como el dueño** con el mecanismo de identidad de
 123|   `private.llamada_celular_elegible_dueno` (`elegibilidad:41-57`).
 124|   - Se reutiliza el mecanismo, **no el predicado** (Codex P5): ese excluye etapas terminales y «no contactar», y esos
 125|     leads propios tienen que seguir identificándose.
 126| - **(b) Sin dueño** (decisión 7): `vendedor_id is null and asignado_supervisor_id is null`, en etapa abierta. Es la
 127|   condición de «en bolsa» de la disponibilidad (`20260906200000:3633-3641`).
 128| - **(c) Descartado reutilizable** (respuesta de Miguel). Es la condición de «reutilizable» de la disponibilidad
 129|   (`20260906200000:3677-3727`):
 130|   - etapa `descartado`, `activo` y con `descartado_en`;
 131|   - ya pasó su espera: los días de `crm.enfriamiento_politica` para su motivo, o 24 horas si son 0.
 132| 
 133| **Resultado:**
 134| - **Uno** → identificada.
 135|   - Si es (a): pide resultado si es elegible como el dueño; si no, por revisar.
 136|   - Si es (b) o (c): por revisar.
 137| - **Dos o más** → ambigua, sin guardar cuántos (`calidad.candidatos` desaparece).
 138| - **Ninguno** → igual que un número sin lead: no se guarda (decisión 3), aunque sea de un lead de otro analista.
 139| 
 140| **Quién la ve:**
 141| - Lo de hoy: gerencia, o quien tiene hoy ámbito sobre el lead (decisión 7 de F2).
 142| - Más una condición para todos, gerencia incluida: **el lead tiene que estar activo** (fallo 2).
 143| - Por eso la llamada a un lead en bolsa no la ve quien llamó mientras el lead no sea suyo. Le aparece a quien lo tome
 144|   (`crm.tomar_lead_libre`). Si nadie lo toma, se borra a los 30 días (§5).
 145| 
 146| **Efectos aceptados** (Codex P5; ratificados por Miguel):
 147| - La llamada a un lead de otro analista ya no le llega a su equipo.
 148| - Un número de un lead propio y de uno ajeno con dueño queda identificado con el propio: significa «coincidencia única
 149|   en su cartera», no identidad global.
 150| 
 151| Con la #13 (clientes), la búsqueda sumará los clientes del ámbito del dueño con la misma regla.
 152| 
 153| ## 3. Candados con un solo orden (menores 8 y 10; Codex P2-4 y P10)
 154| 
 155| **Las rutas reales** que cambian lo que se valida:
 156| - **Reasignar** un lead escribe su fila en `crm.leads`: `vendedor_id`, `asignado_supervisor_id` y `activo` son columnas
 157|   suyas. Un `UPDATE` toma un candado incompatible con `FOR SHARE` (Codex P10). La regla de ámbito
 158|   (`private.sla_gestion_permitida`, `20260907025220:81-92`) solo lee esa fila, el rol y el equipo.
 159| - **Deshacer** (`crm.deshacer_resultado_llamada`): bloquea primero el resultado y después el lead, los dos
 160|   `FOR UPDATE`, y revalida el ámbito bajo el candado (`20260920005000:649, 682-685`).
 161| - **La encuesta v4** bloquea el lead `FOR UPDATE` (`20260921153654:148`). F4-a la envuelve y bloquea la llamada después.
 162| 
 163| **Orden único para todo lo de llamadas: resultado → lead(s) → llamada → enlace.** Con dos leads, por id.
 164| - **Descartar y asociar:**
 165|   - leen la llamada sin candado;
 166|   - bloquean su lead y, al asociar, también el destino, por id;
 167|   - bloquean la llamada y comprueban que su lead no cambió. Si cambió, 40001 «vuelve a intentarlo» (Codex P10).
 168| - **Enlazar (manual):** resultado `FOR SHARE` → lead → llamada → enlace. Rechaza un resultado deshecho (menor 10).
 169|   Empieza por el mismo candado que Deshacer, así que no se cruzan.
 170| - **v5 (F4-a):** lead (núcleo de v4) → llamada → enlace. No bloquea un resultado anterior: si tuviera que mover el
 171|   enlace, lo lee y, si no está deshecho, se niega.
 172| - **Purga:** llamada → enlace (cascada). No toca leads.
 173| - Todas revalidan el ámbito **después** de tomar los candados, como Deshacer.
 174| 
 175| **Límite aceptado:** un cambio en `crm.equipo` o una baja en `public.perfiles` no se serializa con estos candados
 176| (Codex P2). Pasa lo mismo en el resto del CRM: Deshacer tampoco lo bloquea. La ventana dura una transacción.
 177| 
 178| ## 4. Entrantes (fallo 3; decisión 2)
 179| 
 180| - **Perilla bloqueada:** un `check` la fija en falso y `crm.fijar_politica_llamadas_celular` rechaza encenderla con
 181|   un mensaje claro. La #14 llega después, como paso propio.
 182| - **`direccion = 'desconocida'` se ignora**, igual que una entrante (Codex P6). La macro siempre manda la dirección; un
 183|   aviso sin ella no debe pedir resultado.
 184| - **Límite (Codex P6):** la base no detecta una entrante que la macro marque como saliente. Se prueba en el celular,
 185|   con las pruebas de la guía.
 186| 
 187| ## 5. Retención (decisión 4; Codex P4 y P7)
 188| 
 189| | Qué | Plazo | Desde |
 190| | --- | --- | --- |
 191| | Identificadas sin resultado: sin enlace, piden resultado o están por revisar | **30 días (nuevo)** | `recibido_en` |
 192| | Ambiguas y sin identificar | 30 días, como hoy | `recibido_en` |
 193| | Descartadas | Su plazo de hoy | `descartado_en` |
 194| | Registradas: con enlace, aunque su resultado se haya deshecho | **Se conservan** como historial del lead (Miguel) | — |
 195| | Recepciones | **32 días (nuevo)** | `recibido_en` |
 196| 
 197| - Deshacer no convierte una llamada en «sin resultado»: el enlace permanece por contrato. La purga mira el enlace, no
 198|   la atención.
 199| - Las registradas de un lead dado de baja quedan ocultas (§2) y se conservan como el resto de su historial: el CRM no
 200|   borra historial. Es un plazo **decidido**, no «indefinido por omisión» (`PLAN.md:647`).
 201| 
 202| ## 6. Salud del celular (nuevo, para tu OK)
 203| 
 204| - Hoy supervisión y gerencia ven `envios_hoy` y `ultimo_envio_en` (`ingesta:278-290, 370`).
 205| - Los dos cuentan **todo** lo que manda el celular, también las llamadas a números que no son leads
 206|   (`ingesta:308, 315`). `envios_hoy` suma además los latidos (`ingesta:335`).
 207| - Restando, se sabría cuántas llamadas personales hizo el analista y a qué hora.
 208| - **Propuesta:** la lectura de salud muestra solo el latido, la versión de la macro y la cola. Los contadores siguen
 209|   por dentro, solo para el límite.
 210| - Cierra además, sin más trabajo, la pista que la v1 cerraba actualizando esos datos siempre.
 211| - La cola (`eventos_en_cola`) también cuenta llamadas personales hechas sin red. Se mantiene: soporte la necesita y es
 212|   pasajera.
 213| - Salió del análisis adelantado de F5–F7 (PR #178).
 214| 
 215| ## 7. Lo que va con F4-a (decisión 1: se publica junto)
 216| 
 217| - **Puerta v5 por id exacto** (`F4-PLAN-CORTO.md` §1), con intención de enlace si el aviso todavía no llegó.
 218| - **Sin la regla de los 10 minutos** en el camino exacto (confirmación 3 de Miguel; Codex P2-5). La encuesta suele
 219|   guardarse antes de que llegue el aviso, y un reloj adelantado la rechazaría (`nucleo:423-425`). La regla queda solo
 220|   para el enlace manual.
 221| - **Guardar por qué vía se hizo el enlace:** al colgar, desde la pestaña o a mano. Sin ese dato no se mide «encuesta
 222|   abierta al colgar» por celular, que es el objetivo (`F4-PLAN-CORTO.md` §2). Hoy el enlace no lo guarda
 223|   (`datos:403-413`).
 224| - **Al deshacer, el enlace pasa al resultado corregido** (confirmación 2).
 225| - El detalle va en `F4-PLAN-CORTO.md`, que se pone al día con esta sección.
 226| 
 227| ## 8. Lo demás
 228| 
 229| - **Bandeja duplicada:** se retiran `crm.llamadas_celular_pendientes_fn` y su núcleo (decisión 6).
 230| - **Rotar reinicia el límite de envíos** (Codex P3-7): el estado va por asignación. Se documenta; solo gerencia rota.
 231| - **Guía de publicación** (correcciones de Miguel al #173):
 232|   - cada registrador, justo después de su migración;
 233|   - una fila final de veredicto después del `commit`, como `anexo-cronograma/registrar-20260929151350.sql`: los
 234|     `raise notice` no se ven por `db query --linked`;
 235|   - en una copia Docker, `psql -f`: `db query --local --file` falla con varias sentencias;
 236|   - la barrera de «Cómo se aplica»;
 237|   - el prefijo del id en la macro es la etiqueta del celular (`C2-…`), no siempre `C1-`, y la hora del celular es
 238|     automática;
 239|   - **antes de pasar un celular a otro analista, cola en 0** según su latido. La llamada se atribuye a la clave con la
 240|     que llega (`elegibilidad:128-133, 200`): una cola vieja quedaría a nombre del analista nuevo. Salió del análisis
 241|     de F5–F7.
 242| - **Guía de la macro, sin Pro** (Miguel): las 3 macros de hoy y el latido dentro de «Enviar cola»; la sección de
 243|   entrantes (§3d) queda para la #14. Va en su propio PR.
 244| 
 245| ## Imprescindible para publicar o mejora
 246| 
 247| | Pieza | Tipo | Por qué |
 248| | --- | --- | --- |
 249| | §1 Id, recepción, orden y contrato de la Edge | Imprescindible | Fallo 1; Codex P2-1 a P2-3 |
 250| | §2 Qué lead puede ser | Imprescindible | Fallos 2 y 4; decisiones 3 y 7 |
 251| | §3 Candados | Imprescindible | Menores 8 y 10; Codex P2-4 |
 252| | §4 Entrantes | Imprescindible | Fallo 3 |
 253| | §5 Retención | Imprescindible | Decisión 4 |
 254| | §6 Salud | Imprescindible | Llamadas personales a la vista de supervisión |
 255| | §7 Enlace exacto, sin la regla de 10 minutos | Imprescindible | Decisión 1; Codex P2-5 |
 256| | Guía: barrera, registradores, veredicto, `psql`, prefijo y hora | Imprescindible | Publicar sin sorpresas; Codex P2-6 |
 257| | §7 Vía del enlace | Mejora barata | Mide el objetivo; no se recupera después |
 258| | Retirar la bandeja vieja | Mejora | Nadie la usa |
 259| | Cola en 0 antes de cambiar de analista | Mejora | Caso raro; es una línea de la guía |
 260| 
 261| ## Pruebas
 262| 
 263| | Dónde | Qué demuestra |
 264| | --- | --- |
 265| | Banco reducido (`npm run test:llamadas:local`), oráculo nuevo | La lista de abajo |
 266| | Banco reducido, dos sesiones | Carreras con barreras: cierre durante un latido; reasignación durante descartar, asociar y enlazar; Deshacer durante enlazar, sin interbloqueo; medianoche de Lima |
 267| | Edge (`test:llamadas-ingesta` y mutantes) | Contrato nuevo: inválido → 400 con cupo gastado; JSON mal formado llega a la base; 405, 415 y 413 sin base; sin 409 |
 268| | Gate `testLlamadasCelular` | Ya no exige `P0409`: exigirlo es exigir la fuga (punto 22 de la revisión). Añade lead borrado, entrantes, bolsa y reutilizable, un enlace real con su encuesta y rotación |
 269| | Banco de Miguel (esquema de producción) | `banco/verificar-hallazgos.sql` con los fallos cerrados, gate completo, advisors y la quinta forzada a fallar (barrera) |
 270| 
 271| **El oráculo nuevo comprueba:**
 272| - **Sin pistas:** número sin lead, lead ajeno con dueño, ajeno en enfriamiento y varios ajenos dan la misma respuesta,
 273|   el mismo cupo y el mismo estado visible.
 274| - **Bolsa:** se guarda por revisar; quien llamó no la ve; al tomar el lead la ve y puede enlazar; si nadie lo toma, la
 275|   purga la borra a los 30 días.
 276| - **Reutilizable:** igual que la bolsa.
 277| - **Propios terminales o con «no contactar»:** identificada, por revisar.
 278| - **Id:**
 279|   - forma inválida, etiqueta de otro celular o fuera de la ventana → 400, con el cupo gastado;
 280|   - el mismo id con otro contenido → aceptado, sin cambios;
 281|   - ignorado y después el mismo id con lead → sigue ignorado;
 282|   - rotar no duplica;
 283|   - con la etiqueta reutilizada, un id nuevo entra.
 284| - **Purga:**
 285|   - no libera un id dentro de la ventana;
 286|   - recepciones a los 32 días e identificadas sin enlace a los 30;
 287|   - las registradas y las de resultado deshecho se quedan;
 288|   - las descartadas, por su plazo.
 289| - **Cupo:** la ventana no retrocede, `Retry-After` ≥ 1 y, sin política, error claro.
 290| - **Identidad:** vuelve a la anterior en éxito y en error, también dentro del bloque que atrapa `22023`.
 291| - **Otros:** lead borrado (nadie lo ve ni lo toca, gerencia incluida); entrantes y desconocidas ignoradas, con la
 292|   perilla bloqueada; fecha sin zona rechazada; salud sin envíos ni último envío.
 293| - **F4-a (en su banco):** reloj adelantado con enlace exacto, aviso tardío, intención sin aviso y aviso caducado.
 294| 
 295| ## Orden de trabajo (con tu OK)
 296| 
 297| 1. Quinta migración, con su reversa, su registrador y sus oráculos. Banco reducido en verde.
 298| 2. F4-a, según `F4-PLAN-CORTO.md` puesto al día con §7.
 299| 3. Edge y sus pruebas.
 300| 4. Bloque del gate.
 301| 5. Guías de publicación y de la macro; `MIGRACIONES.md`.
 302| 6. Encargo de Codex r2 sobre el diff, con el dato de «Nuevo lead», y auditor-rls. Los corre Miguel.
 303| 7. Ensayo en tu banco y publicación: las cinco, F4-a y la Edge, con la barrera.
 304| 
 305| ## Decisiones
 306| 
 307| ### Ya decididas por Miguel (03/10, PR #175)
 308| 
 309| | # | Decisión |
 310| | --- | --- |
 311| | 1 | **A:** F2 + F3 se publican junto con el enlace exacto de F4-a |
 312| | 2 | Entrantes bloqueadas; la #14 después, como paso propio |
 313| | 3 | La llamada a un lead de otro analista = número sin lead |
 314| | 4 | Sin resultado → 30 días; las registradas se conservan como historial del lead |
 315| | 5 | Pista por tiempo: riesgo aceptado por escrito |
 316| | 6 | Retirar la bandeja vieja |
 317| | 7 | Leads sin dueño y descartados reutilizables: candidatos, por revisar; le aparecen a quien los tome |
 318| 
 319| Confirmaciones:
 320| - escribe esta sesión; tu sesión verifica en tu banco y corre Codex r2;
 321| - al deshacer, el enlace pasa al resultado corregido;
 322| - la regla «resultado posterior a la llamada» solo vale para el enlace manual;
 323| - la #12, con la redacción de §1;
 324| - MacroDroid Pro no se compra todavía.
 325| 
 326| ### Para tu OK
 327| 
 328| | # | Decisión | Recomendación | Alternativa y su costo |
 329| | --- | --- | --- | --- |
 330| | N1 | Salud del celular (§6) | **Quitar `envios_hoy` y `ultimo_envio_en`** de la lectura | Dejarlos: supervisión ve cuántas llamadas personales hace el analista y a qué hora |
 331| 
 332| ### Criterio de Claude (PRIMARY), para que lo veas
 333| 
 334| - La forma del id y su ventana. Se guarda tal cual, sin hash.
 335| - La recepción en `private`, con 32 días.
 336| - La Edge solo revisa el transporte; la base valida todo lo demás.
 337| - `desconocida` se ignora.
 338| - Rotar reinicia el cupo: se documenta, no se cambia.
 339| - Registradores intercalados, en vez de relajar sus comprobaciones.
 340| - Descartar y asociar revalidan la llamada después de bloquear los leads.
 341| - El inválido se resuelve dentro de la base, con un bloque que atrapa solo `22023`.
 342| 
 343| ## Hallazgos de Codex r1 (03/10) → dónde se cierran
 344| 
 345| | Hallazgo | Dónde |
 346| | --- | --- |
 347| | P2-1 La Edge no acompaña el arreglo | §1, contrato |
 348| | P2-2 El sha256 no protege un teléfono | §1, el id |
 349| | P2-3 Etiqueta e id reutilizados | §1, el id |
 350| | P2-4 Candados incompletos | §3 |
 351| | P2-5 Reloj adelantado | §7 |
 352| | P2-6 Sin barrera si falla la quinta | Cómo se aplica; guía (§8) |
 353| | P3-7 Rotar reinicia el cupo | §8 |
 354| | P1: recepción y llamada juntas; duplicados con cupo; hora tras el estado; 503 por candado | §1 |
 355| | P4: ocultar no es caducar | §5 |
 356| | P6: dirección desconocida; entrante mal marcada | §4 |
 357| | P11: recepción en `private`; latidos sin id; F4 por id completo; reversa | §1; Cómo se aplica |
 358| 
 359| ## Riesgos y límites
 360| 
 361| - Tiempo de respuesta: riesgo aceptado (decisión 5).
 362| - `crm.equipo` y `public.perfiles` no se serializan, como en el resto del CRM (§3).
 363| - Una entrante que la macro marque como saliente solo se detecta probando en el celular (§4).
 364| - Un celular con la hora muy mal (más de 1 día adelantada o 30 días atrasada) ve sus avisos rechazados: la guía exige
 365|   hora automática y las pruebas del alta lo detectan.
 366| - Cola vieja tras cambiar de analista: la evita la regla de la guía (§8).
 367| - Aplicar las cuatro sin la quinta: lo frena la barrera.
 368| - Las carreras se prueban con barreras en el banco reducido; tu ensayo con el esquema de producción lo completa.
 369| 
 370| ## En llano
 371| 
 372| Miguel ya decidió todo lo que estaba pendiente, y su revisor encontró siete huecos en el diseño. Este plan cierra cada
 373| uno:
 374| - el CRM anota cada aviso antes de mirar si el número es de un lead, y contesta siempre igual;
 375| - el id de cada llamada tiene una forma fija que no puede esconder un teléfono;
 376| - las operaciones se bloquean en un solo orden, para no trabarse entre sí;
 377| - las llamadas a leads libres no se pierden: le aparecen a quien tome el lead.
 378| 
 379| Hay una propuesta nueva: que el panel de los celulares deje de mostrar datos que cuentan llamadas personales. Nada de
 380| esto se programa hasta que Miguel diga que sí.
```

## Archivo: supabase/migrations/20261005143843_crm_llamadas_celular_correccion.sql (1198 líneas) — la quinta (lo que se revisa)
```
   1| -- Llamadas desde el celular · QUINTA MIGRACIÓN: corrección de la revisión de F2 + F3.
   2| -- Plan: docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md (v2, PR #179, fusionado por Miguel el 04/10/2026;
   3| -- Jhosep confirmó el 05/10 que esa fusión es el OK, con la N1 según la recomendación). Responde a la revisión
   4| -- de Miguel (REVISION-2026-10-02.md: fallos 1–4 y menores 6–15) y a la ronda 1 de Codex sobre el plan
   5| -- (docs/encargos/2026-10-03-codex-llamadas-celular-correccion-r1-respuesta.md: P2-1 a P2-6, P3-7).
   6| -- No edita las cuatro migraciones de F2 + F3 (20261001145242, 20261001160219, 20261001212258, 20261001222431):
   7| -- las enmienda. El fallo 5 (enlace encuesta ↔ llamada) va en F4-a, con su propia migración, y se publica junto.
   8| --
   9| -- Qué hace:
  10| --   §1 El id, la recepción y el orden de la puerta.
  11| --     · El id de cada llamada tiene una forma fija, C<n>-<10 dígitos>: la etiqueta del celular y los segundos de
  12| --       su reloj, como lo genera la macro al colgar. Su etiqueta tiene que ser la de la asignación de la clave y
  13| --       sus segundos, caer entre hace 30 días y dentro de 1 día (hora del servidor). No puede llevar un teléfono.
  14| --     · private.llamadas_celular_recepciones: una fila por cada llamada aceptada, ANTES de buscar el lead, también
  15| --       si después se ignora. Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada.
  16| --       Caduca a los 32 días (30 de ventana + 1 de tolerancia + 1 de margen): después, ese id ya no entra.
  17| --     · crm.llamadas_celular_eventos: evento_origen_id único por id (antes por asignación + id: rotar duplicaba,
  18| --       menor 9) y sin hash_payload (solo servía para el 409, que desaparece).
  19| --     · Orden de la puerta: clave (asignación FOR SHARE, revalidada) → estado FOR UPDATE y recién ahí la hora,
  20| --       una sola vez → cupo (sin política, error explícito) → validación (bloque que atrapa SOLO 22023: un
  21| --       inválido devuelve «invalido» y el cupo gastado queda) → recepción → lead y llamada, si corresponde.
  22| --     · Contrato con la Edge: la base devuelve {resultado: aceptado | invalido, mensaje}. Sin P0409.
  23| --   §2 Qué lead puede ser: activos con el número que sean (a) del ámbito del dueño, evaluado COMO el dueño;
  24| --     (b) sin dueño, en etapa abierta; o (c) descartados reutilizables (la regla de «Nuevo lead»). Uno →
  25| --     identificada; dos o más → ambigua, sin guardar cuántos; ninguno → como un número sin lead.
  26| --     Para verla, el lead tiene que estar activo, también para gerencia (fallo 2).
  27| --   §3 Candados en un solo orden: resultado → lead(s) → llamada → enlace. Descartar, asociar y enlazar
  28| --     revalidan el ámbito después de bloquear; si el lead de la llamada cambió mientras esperaban, 40001.
  29| --     Enlazar rechaza un resultado deshecho (menor 10).
  30| --   §4 Entrantes bloqueadas: un CHECK fija la perilla en falso y la puerta rechaza encenderla. Entrantes y
  31| --     direcciones desconocidas se ignoran.
  32| --   §5 Retención: identificadas sin enlace y ambiguas, 30 días desde recibido_en; descartadas, su plazo; las
  33| --     registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones, 32 días.
  34| --   §6 Salud del celular sin envios_hoy ni ultimo_envio_en (N1): cuentan llamadas personales.
  35| --   §8 Se retira la bandeja duplicada (crm.llamadas_celular_pendientes_fn y su núcleo, decisión 6).
  36| --
  37| -- Decisiones de criterio de Claude (PRIMARY, 05/10/2026), para que Miguel las vea:
  38| --   · private.celulares_estado pierde ultimo_envio_en: la N1 lo saca de la lectura y nada más lo usa; guardarlo
  39| --     sin leerlo conservaría la hora de la última llamada, personal incluida.
  40| --   · dias_retencion_sin_resolver cubre las ambiguas Y las identificadas sin enlace (las dos son «sin resolver»):
  41| --     sin columna nueva ni cambio de firma de crm.fijar_politica_llamadas_celular.
  42| --   · Los 32 días de las recepciones son una constante, no una perilla: dependen de la ventana del id.
  43| --   · La recepción guarda el id y la asignación, sin número ni hash.
  44| --   · Descartar, asociar y enlazar bloquean los leads FOR SHARE: basta contra la reasignación (un UPDATE de
  45| --     crm.leads) y no se estorban entre sí.
  46| --   · La purga devuelve cuántas filas retiró, llamadas y recepciones juntas.
  47| --
  48| -- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
  49| --
  50| -- Cómo se aplica (guía PUBLICAR-F2-F3.md): las cuatro, cada una con su registrador justo después, y esta al
  51| -- final. Precondición: las tablas de llamadas VACÍAS, comprobado bajo candado; si hay filas, se niega. Barrera:
  52| -- no se despliega la Edge ni se da de alta ningún celular hasta verificar esta migración.
  53| --
  54| -- Reversión: ../scripts/llamadas-celular/reversa-correccion.sql, SOLO antes del primer aviso (sin recepciones
  55| -- ni llamadas): vuelve exactamente al estado de las cuatro. Después del primer aviso no se revierte, porque
  56| -- reinstalaría las fugas: se apaga (retirar la Edge, cerrar las asignaciones) y se corrige hacia adelante.
  57| -- Verificación: npm run test:llamadas:local (oráculo tests/llamadas-celular/oraculo-correccion.sql, reversa con
  58| -- huella del catálogo, mutantes y concurrencia con dos sesiones).
  59| begin;
  60| set local lock_timeout = '5s';
  61| set local statement_timeout = '60s';
  62| 
  63| do $precondicion$
  64| begin
  65|   if to_regclass('private.llamadas_celular_recepciones') is not null
  66|      or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null then
  67|     raise exception 'LLAMADAS_CORRECCION: los objetos ya existen; no se sobrescriben';
  68|   end if;
  69|   if to_regclass('crm.llamadas_celular_politica') is null or to_regclass('crm.celulares_asignaciones') is null
  70|      or to_regclass('crm.llamadas_celular_eventos') is null or to_regclass('crm.llamadas_celular_enlaces') is null
  71|      or to_regclass('private.celulares_estado') is null
  72|      or to_regprocedure('private.llamada_celular_elegible_dueno(uuid,uuid)') is null
  73|      or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null
  74|      or to_regprocedure('crm.ingerir_llamada_celular_servicio(text,jsonb)') is null
  75|      or to_regprocedure('crm.registrar_salud_celular_servicio(text,jsonb)') is null then
  76|     raise exception 'LLAMADAS_CORRECCION: faltan las cuatro migraciones de F2 + F3 (o alguna de sus piezas)';
  77|   end if;
  78|   if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb)'::regprocedure),
  79|                        'private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)') = 0 then
  80|     raise exception 'LLAMADAS_CORRECCION: la ingesta no tiene la forma de 20261001222431';
  81|   end if;
  82|   if to_regclass('crm.enfriamiento_politica') is null
  83|      or (select count(*) from pg_catalog.pg_attribute a
  84|          where a.attrelid = 'crm.leads'::regclass and not a.attisdropped
  85|            and a.attname in ('descartado_en', 'motivo_descarte', 'vendedor_id', 'asignado_supervisor_id')) <> 4
  86|      or to_regprocedure('private.sla_gestion_permitida(uuid,uuid)') is null then
  87|     raise exception 'LLAMADAS_CORRECCION: faltan dependencias (enfriamiento_politica, columnas de descarte de leads o ámbito)';
  88|   end if;
  89| end;
  90| $precondicion$;
  91| 
  92| -- La comprobación de vacío solo vale bajo candado (Codex, riesgos de r1).
  93| lock table crm.llamadas_celular_politica, crm.celulares_asignaciones, crm.llamadas_celular_eventos,
  94|            crm.llamadas_celular_enlaces, private.celulares_estado in access exclusive mode;
  95| 
  96| do $vacias$
  97| begin
  98|   if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from crm.llamadas_celular_eventos)
  99|      or exists (select 1 from crm.llamadas_celular_enlaces) or exists (select 1 from private.celulares_estado) then
 100|     raise exception 'LLAMADAS_CORRECCION: hay filas en las tablas de llamadas; esta migración solo se aplica con las tablas vacías (barrera de «Cómo se aplica»)';
 101|   end if;
 102| end;
 103| $vacias$;
 104| 
 105| -- ── 1. Recepciones (private, sin auditoría, 32 días) ─────────────────────────────────────────
 106| create table private.llamadas_celular_recepciones (
 107|   id               uuid primary key default gen_random_uuid(),
 108|   evento_origen_id text not null
 109|                    constraint llamadas_celular_recepciones_origen_valido
 110|                    check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
 111|                    constraint llamadas_celular_recepciones_origen_uq unique,
 112|   asignacion_id    uuid not null references crm.celulares_asignaciones(id) on delete restrict,
 113|   recibido_en      timestamptz not null,
 114|   creado_en        timestamptz not null default now(),
 115|   actualizado_en   timestamptz not null default now()
 116| );
 117| alter table private.llamadas_celular_recepciones enable row level security;
 118| revoke all on private.llamadas_celular_recepciones from public, anon, authenticated, service_role;
 119| create index llamadas_celular_recepciones_asignacion_idx on private.llamadas_celular_recepciones (asignacion_id);
 120| create index llamadas_celular_recepciones_recibido_idx on private.llamadas_celular_recepciones (recibido_en);
 121| 
 122| create function private.trg_llamadas_celular_recepciones_candado()
 123| returns trigger
 124| language plpgsql
 125| security definer
 126| set search_path to ''
 127| as $function$
 128| begin
 129|   if tg_op = 'DELETE' then
 130|     if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on' then
 131|       return old;
 132|     end if;
 133|     raise exception using errcode = '42501',
 134|       message = 'Una recepción de llamada no se borra a mano: la retira la retención programada';
 135|   end if;
 136|   raise exception using errcode = '42501', message = 'Una recepción de llamada es inmutable';
 137| end;
 138| $function$;
 139| create trigger trg_llamadas_celular_recepciones_00_candado
 140|   before update or delete on private.llamadas_celular_recepciones
 141|   for each row execute function private.trg_llamadas_celular_recepciones_candado();
 142| create trigger trg_llamadas_celular_recepciones_00_sin_vaciar
 143|   before truncate on private.llamadas_celular_recepciones
 144|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 145| 
 146| -- ── 2. Política: entrantes bloqueadas (fallo 3, decisión 2) ──────────────────────────────────
 147| alter table crm.llamadas_celular_politica
 148|   add constraint llamadas_celular_politica_entrantes_bloqueadas check (not entrantes_activas);
 149| 
 150| -- ── 3. Eventos: id con forma fija y único por id; sin hash_payload ───────────────────────────
 151| create or replace function private.trg_llamadas_celular_eventos_candado()
 152| returns trigger
 153| language plpgsql
 154| security definer
 155| set search_path to ''
 156| as $function$
 157| begin
 158|   if tg_op = 'DELETE' then
 159|     -- Solo la purga programada (GUC de transacción) o una cascada (el lead se elimina: la
 160|     -- evidencia de su número se va con él) pueden borrar. Un DELETE directo muere aquí.
 161|     if coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
 162|        or pg_catalog.pg_trigger_depth() > 1 then
 163|       return old;
 164|     end if;
 165|     raise exception using errcode = '42501',
 166|       message = 'Una llamada del celular no se borra a mano: la retira la retención programada';
 167|   end if;
 168| 
 169|   -- El payload es la evidencia: inmutable aunque lo escriba el núcleo.
 170|   if new.id <> old.id or new.asignacion_id <> old.asignacion_id or new.analista_id <> old.analista_id
 171|      or new.evento_origen_id <> old.evento_origen_id
 172|      or new.numero_canonico is distinct from old.numero_canonico
 173|      or new.direccion <> old.direccion or new.estado_tecnico <> old.estado_tecnico
 174|      or new.duracion_seg is distinct from old.duracion_seg
 175|      or new.ocurrio_en is distinct from old.ocurrio_en or new.recibido_en <> old.recibido_en
 176|      or new.calidad <> old.calidad or new.creado_en <> old.creado_en then
 177|     raise exception using errcode = '42501',
 178|       message = 'El contenido de una llamada del celular es inmutable; solo cambian su identificación y su atención';
 179|   end if;
 180| 
 181|   -- Identificación: solo avanza (sin_identificar → ambiguo → identificado). El lead se fija una
 182|   -- vez; se corrige únicamente mientras la llamada esté por atender (antes de registrar o descartar).
 183|   if (case new.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end)
 184|      < (case old.identificacion when 'sin_identificar' then 0 when 'ambiguo' then 1 else 2 end) then
 185|     raise exception using errcode = '42501',
 186|       message = pg_catalog.format('La identificación de una llamada solo avanza: %s → %s',
 187|                                   old.identificacion, new.identificacion);
 188|   end if;
 189|   if old.lead_id is not null and new.lead_id is distinct from old.lead_id
 190|      and old.atencion not in ('por_revisar', 'requiere_resultado', 'requiere_devolucion') then
 191|     raise exception using errcode = '42501',
 192|       message = 'Una llamada registrada o descartada no cambia de lead';
 193|   end if;
 194| 
 195|   -- Atención: transiciones permitidas. registrado y descartado_con_motivo son finales.
 196|   if new.atencion <> old.atencion then
 197|     if (old.atencion = 'por_revisar'
 198|           and new.atencion in ('requiere_resultado', 'requiere_devolucion', 'descartado_con_motivo'))
 199|        or (old.atencion in ('requiere_resultado', 'requiere_devolucion')
 200|           and new.atencion in ('registrado', 'descartado_con_motivo', 'por_revisar')) then
 201|       null;
 202|     else
 203|       raise exception using errcode = '42501',
 204|         message = pg_catalog.format('Transición no permitida de la llamada: %s → %s', old.atencion, new.atencion);
 205|     end if;
 206|   end if;
 207|   -- Un descarte sellado no se reescribe (motivo, quién, cuándo).
 208|   if old.atencion = 'descartado_con_motivo'
 209|      and (new.motivo_descarte is distinct from old.motivo_descarte
 210|           or new.motivo_descarte_detalle is distinct from old.motivo_descarte_detalle
 211|           or new.descartado_en is distinct from old.descartado_en) then
 212|     raise exception using errcode = '42501', message = 'El motivo de un descarte no se reescribe';
 213|   end if;
 214| 
 215|   new.actualizado_en := pg_catalog.now();
 216|   return new;
 217| end;
 218| $function$;
 219| 
 220| drop trigger trg_audit_llamadas_celular_eventos on crm.llamadas_celular_eventos;
 221| alter table crm.llamadas_celular_eventos
 222|   drop constraint llamadas_celular_eventos_origen_unico,
 223|   drop constraint llamadas_celular_eventos_origen_valido,
 224|   drop column hash_payload,
 225|   add constraint llamadas_celular_eventos_origen_valido check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'),
 226|   add constraint llamadas_celular_eventos_origen_uq unique (evento_origen_id);
 227| -- Sin hash_payload, solo el número se enmascara en la bitácora. El id ya no puede llevar un teléfono (menor 12).
 228| create trigger trg_audit_llamadas_celular_eventos
 229|   after insert or update or delete on crm.llamadas_celular_eventos
 230|   for each row execute function private.log_audit_sin_secretos('numero_canonico');
 231| 
 232| -- ── 4. Estado del celular sin ultimo_envio_en (N1) ───────────────────────────────────────────
 233| alter table private.celulares_estado drop column ultimo_envio_en;
 234| 
 235| -- ── 5. Núcleo (INVOKER, sin EXECUTE para nadie; lo llaman las puertas DEFINER) ───────────────
 236| 
 237| -- Clave → asignación vigente, bloqueada FOR SHARE y revalidada bajo el candado (menor 6): un cierre o una
 238| -- rotación que gana espera a este envío; uno que llegó antes ya se ve, y la clave deja de valer.
 239| create or replace function private.celular_por_credencial(p_credencial text)
 240| returns uuid
 241| language plpgsql
 242| volatile
 243| set search_path = ''
 244| as $function$
 245| declare
 246|   v_asig crm.celulares_asignaciones%rowtype;
 247| begin
 248|   select a.* into v_asig
 249|   from crm.celulares_asignaciones a
 250|   where a.credencial_hash = private.celular_credencial_hash(p_credencial)
 251|     and a.vigente_hasta is null
 252|   for share;
 253|   if not found or v_asig.vigente_hasta is not null
 254|      or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 255|     return null;
 256|   end if;
 257|   return v_asig.id;
 258| end;
 259| $function$;
 260| 
 261| drop function private.celular_consumir_envio(uuid);
 262| create function private.celular_consumir_envio(p_asignacion_id uuid)
 263| returns timestamptz
 264| language plpgsql
 265| volatile
 266| set search_path = ''
 267| as $function$
 268| declare
 269|   v_pol crm.llamadas_celular_politica%rowtype;
 270|   v_est private.celulares_estado%rowtype;
 271|   v_ahora timestamptz;
 272|   v_minuto timestamptz;
 273|   v_dia date;
 274|   v_min integer;
 275|   v_dia_n integer;
 276| begin
 277|   insert into private.celulares_estado (asignacion_id) values (p_asignacion_id)
 278|   on conflict (asignacion_id) do nothing;
 279|   select * into v_est from private.celulares_estado s where s.asignacion_id = p_asignacion_id for update;
 280|   -- La hora se toma UNA vez y recién con el estado bloqueado (Codex P2): de ella salen la ventana, la espera
 281|   -- y las marcas de salud de este envío.
 282|   v_ahora := pg_catalog.clock_timestamp();
 283|   select * into v_pol from crm.llamadas_celular_politica p where p.singleton;
 284|   if not found then
 285|     raise exception using errcode = '55000',
 286|       message = 'Falta la política de llamadas del celular: no se puede contar el envío';
 287|   end if;
 288|   v_minuto := pg_catalog.date_trunc('minute', v_ahora);
 289|   v_dia := (v_ahora at time zone 'America/Lima')::date;
 290|   -- Ventanas fijas (minuto de reloj y día de Lima) que nunca retroceden (menor 7): si la hora quedara detrás
 291|   -- de la ventana guardada, se sigue contando en la guardada.
 292|   if v_est.minuto_desde is not null and v_est.minuto_desde >= v_minuto then
 293|     v_minuto := v_est.minuto_desde;
 294|     v_min := v_est.envios_minuto;
 295|   else
 296|     v_min := 0;
 297|   end if;
 298|   if v_est.dia is not null and v_est.dia >= v_dia then
 299|     v_dia := v_est.dia;
 300|     v_dia_n := v_est.envios_dia;
 301|   else
 302|     v_dia_n := 0;
 303|   end if;
 304|   -- Primero el día: si los dos están agotados, la espera que cuenta es la más larga.
 305|   if v_dia_n >= v_pol.limite_envios_dia then
 306|     raise exception using errcode = 'P0429',
 307|       message = 'Este celular llegó a su límite de envíos del día',
 308|       detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
 309|         extract(epoch from (((v_dia + 1)::timestamp at time zone 'America/Lima') - v_ahora)))::integer));
 310|   end if;
 311|   if v_min >= v_pol.limite_envios_minuto then
 312|     raise exception using errcode = 'P0429',
 313|       message = 'Demasiados envíos de este celular en un minuto',
 314|       detail = pg_catalog.format('reintentar_en_seg=%s', greatest(1, pg_catalog.ceil(
 315|         extract(epoch from (v_minuto + interval '1 minute' - v_ahora)))::integer));
 316|   end if;
 317|   update private.celulares_estado
 318|      set minuto_desde = v_minuto, envios_minuto = v_min + 1, dia = v_dia, envios_dia = v_dia_n + 1
 319|    where id = v_est.id;
 320|   return v_ahora;
 321| end;
 322| $function$;
 323| 
 324| -- Fecha estricta (menor 15): ISO 8601 con zona; acepta el espacio que usa {datetime} de MacroDroid.
 325| create function private.llamada_celular_fecha(p_texto text)
 326| returns timestamptz
 327| language plpgsql
 328| stable
 329| set search_path = ''
 330| as $function$
 331| declare
 332|   v_t timestamptz;
 333| begin
 334|   if p_texto is null then
 335|     return null;
 336|   end if;
 337|   if p_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
 338|     raise exception using errcode = '22023',
 339|       message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
 340|   end if;
 341|   begin
 342|     v_t := p_texto::timestamptz;
 343|   exception when invalid_datetime_format or datetime_field_overflow or invalid_time_zone_displacement_value then
 344|     raise exception using errcode = '22023',
 345|       message = 'ocurrio_en debe ser una fecha ISO 8601 con zona (p. ej. 2026-10-05 09:30:00-05:00)';
 346|   end;
 347|   if v_t < timestamptz '2026-01-01 00:00Z' or v_t >= timestamptz '2100-01-01 00:00Z' then
 348|     raise exception using errcode = '22023', message = 'ocurrio_en fuera de rango';
 349|   end if;
 350|   return v_t;
 351| end;
 352| $function$;
 353| 
 354| drop function private.celular_registrar_salud(uuid, jsonb);
 355| create function private.celular_registrar_salud(p_asignacion_id uuid, p_latido jsonb, p_ahora timestamptz)
 356| returns jsonb
 357| language plpgsql
 358| volatile
 359| set search_path = ''
 360| as $function$
 361| declare
 362|   v_claves constant text[] := array['v', 'version_macro', 'en_cola', 'ocurrio_en'];
 363|   v_version text;
 364|   v_cola integer;
 365|   v_ocurrio timestamptz;
 366| begin
 367|   -- Validación: un latido inválido responde «invalido» y el cupo gastado antes queda (Codex P3).
 368|   begin
 369|     if p_latido is null or pg_catalog.jsonb_typeof(p_latido) <> 'object' then
 370|       raise exception using errcode = '22023', message = 'El latido debe ser un objeto JSON';
 371|     end if;
 372|     if exists (select 1 from pg_catalog.jsonb_object_keys(p_latido) k where k <> all(v_claves)) then
 373|       raise exception using errcode = '22023', message = 'El latido trae claves no previstas';
 374|     end if;
 375|     if coalesce(p_latido ->> 'v', '') <> '1' then
 376|       raise exception using errcode = '22023', message = 'Versión de latido no soportada (se espera v = 1)';
 377|     end if;
 378|     v_version := p_latido ->> 'version_macro';
 379|     if v_version is null or v_version !~ '^[A-Za-z0-9._ -]{1,40}$' then
 380|       raise exception using errcode = '22023',
 381|         message = 'version_macro inválida (1 a 40 caracteres: letras, dígitos, espacio y . _ -)';
 382|     end if;
 383|     if coalesce(pg_catalog.jsonb_typeof(p_latido -> 'en_cola'), '') <> 'number'
 384|        or (p_latido ->> 'en_cola') !~ '^[0-9]{1,6}$' or (p_latido ->> 'en_cola')::integer > 100000 then
 385|       raise exception using errcode = '22023', message = 'en_cola es obligatorio: un entero de 0 a 100000';
 386|     end if;
 387|     v_cola := (p_latido ->> 'en_cola')::integer;
 388|     v_ocurrio := private.llamada_celular_fecha(p_latido ->> 'ocurrio_en');
 389|   exception when sqlstate '22023' then
 390|     return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
 391|   end;
 392|   update private.celulares_estado
 393|      set ultimo_latido_en = p_ahora, latido_celular_en = v_ocurrio,
 394|          version_macro = v_version, eventos_en_cola = v_cola
 395|    where asignacion_id = p_asignacion_id;
 396|   if not found then
 397|     -- La puerta cuenta el envío antes (y eso crea la fila): llegar aquí sin estado es un error de orden.
 398|     raise exception using errcode = '55000', message = 'El celular no tiene estado: el envío no se contó antes del latido';
 399|   end if;
 400|   return pg_catalog.jsonb_build_object('resultado', 'aceptado');
 401| end;
 402| $function$;
 403| 
 404| -- §2. Candidatos de una llamada: activos con el número y (a) del ámbito del dueño, evaluado COMO el dueño
 405| -- con el mecanismo de private.llamada_celular_elegible_dueno (no su predicado: los propios terminales o en
 406| -- «no contactar» también se identifican, Codex P5); (b) sin dueño, en etapa abierta (la «bolsa» de
 407| -- private.verificar_disponibilidad_lead_impl); o (c) descartados reutilizables (la misma regla: activo,
 408| -- descartado_en y la espera de crm.enfriamiento_politica cumplida; con 0 días, 24 horas).
 409| create function private.llamada_celular_candidatos_dueno(p_dueno uuid, p_formas text[], p_ahora timestamptz)
 410| returns uuid[]
 411| language plpgsql
 412| volatile
 413| set search_path = ''
 414| as $function$
 415| declare
 416|   v_previo text := pg_catalog.current_setting('request.jwt.claim.sub', true);
 417|   v_cand uuid[];
 418| begin
 419|   if p_dueno is null or pg_catalog.cardinality(coalesce(p_formas, '{}'::text[])) = 0 then
 420|     return '{}'::uuid[];
 421|   end if;
 422|   perform pg_catalog.set_config('request.jwt.claim.sub', p_dueno::text, true);
 423|   select coalesce(pg_catalog.array_agg(distinct l.id), '{}'::uuid[]) into v_cand
 424|   from crm.leads l
 425|   left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
 426|   where l.activo
 427|     and (l.telefono = any(p_formas) or l.telefono_alternativo = any(p_formas))
 428|     and (coalesce(private.sla_gestion_permitida(p_dueno, l.id), false)
 429|          or (l.vendedor_id is null and l.asignado_supervisor_id is null
 430|              and l.etapa not in ('convertido', 'descartado'))
 431|          or (l.etapa = 'descartado' and l.descartado_en is not null
 432|              and l.descartado_en + case when coalesce(ep.dias, 0) > 0
 433|                                         then pg_catalog.make_interval(days => ep.dias)
 434|                                         else interval '24 hours' end <= p_ahora));
 435|   -- La identidad vuelve ANTES de que la ingesta escriba: la bitácora no atribuye la llamada a nadie.
 436|   perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_previo, ''), true);
 437|   return v_cand;
 438| end;
 439| $function$;
 440| 
 441| drop function private.llamada_celular_ingerir(uuid, jsonb);
 442| create function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
 443| returns jsonb
 444| language plpgsql
 445| volatile
 446| set search_path = ''
 447| as $function$
 448| declare
 449|   v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
 450|                                     'duracion_seg', 'ocurrio_en'];
 451|   v_asig crm.celulares_asignaciones%rowtype;
 452|   v_pol crm.llamadas_celular_politica%rowtype;
 453|   v_origen text;
 454|   v_numero text;
 455|   v_dir text;
 456|   v_estado text;
 457|   v_dur integer;
 458|   v_ocurrio timestamptz;
 459|   v_hora_id timestamptz;
 460|   v_recepcion uuid;
 461|   v_formas text[];
 462|   v_e164 text;
 463|   v_cand uuid[];
 464|   v_lead uuid;
 465|   v_ident text;
 466|   v_aten text;
 467|   v_metodo text;
 468|   v_calidad jsonb := '{}'::jsonb;
 469|   v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
 470| begin
 471|   -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
 472|   select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
 473|   if not found or v_asig.vigente_hasta is not null
 474|      or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 475|     raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
 476|   end if;
 477| 
 478|   -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
 479|   -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
 480|   begin
 481|     if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
 482|       raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
 483|     end if;
 484|     if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
 485|       raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
 486|     end if;
 487|     if coalesce(p_evento ->> 'v', '') <> '1' then
 488|       raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
 489|     end if;
 490|     v_origen := p_evento ->> 'evento_origen_id';
 491|     if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
 492|       raise exception using errcode = '22023',
 493|         message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
 494|     end if;
 495|     if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
 496|       raise exception using errcode = '22023',
 497|         message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
 498|     end if;
 499|     v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
 500|     if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
 501|       raise exception using errcode = '22023',
 502|         message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
 503|     end if;
 504|     v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
 505|     if pg_catalog.length(v_numero) > 40 then
 506|       raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
 507|     end if;
 508|     v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
 509|     if v_dir not in ('saliente', 'entrante', 'desconocida') then
 510|       raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
 511|     end if;
 512|     v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
 513|     if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
 514|       raise exception using errcode = '22023', message = 'estado_tecnico inválido';
 515|     end if;
 516|     if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
 517|       if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
 518|          or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
 519|         raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
 520|       end if;
 521|       v_dur := (p_evento ->> 'duracion_seg')::integer;
 522|     end if;
 523|     v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
 524|   exception when sqlstate '22023' then
 525|     return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
 526|   end;
 527| 
 528|   -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
 529|   -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
 530|   -- ella: nada lo atrapa (Codex P1).
 531|   insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
 532|   values (v_origen, v_asig.id, p_ahora)
 533|   on conflict (evento_origen_id) do nothing
 534|   returning id into v_recepcion;
 535|   if v_recepcion is null then
 536|     return v_aceptado;
 537|   end if;
 538| 
 539|   -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
 540|   if v_dir <> 'saliente' then
 541|     return v_aceptado;
 542|   end if;
 543| 
 544|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 545|   if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
 546|     v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
 547|   end if;
 548|   v_formas := private.llamada_celular_formas(v_numero);
 549|   v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
 550|   if v_e164 is null and v_numero is not null then
 551|     v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
 552|   elsif v_numero is null then
 553|     v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
 554|   end if;
 555|   v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);
 556| 
 557|   if pg_catalog.cardinality(v_cand) = 1 then
 558|     v_lead := v_cand[1];
 559|     v_ident := 'identificado';
 560|     v_metodo := 'exacto';
 561|     -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
 562|     v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
 563|                    then 'requiere_resultado' else 'por_revisar' end;
 564|   elsif pg_catalog.cardinality(v_cand) > 1 then
 565|     -- Ambigua, sin guardar cuántos (fallo 4).
 566|     v_ident := 'ambiguo';
 567|     v_aten := 'por_revisar';
 568|   elsif coalesce(v_pol.guardar_sin_identificar, false) then
 569|     v_ident := 'sin_identificar';
 570|     v_aten := 'por_revisar';
 571|   else
 572|     -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
 573|     return v_aceptado;
 574|   end if;
 575| 
 576|   insert into crm.llamadas_celular_eventos
 577|     (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
 578|      ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
 579|   values
 580|     -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
 581|     -- volver a buscar candidatos al asociar.
 582|     (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
 583|      v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end);
 584|   return v_aceptado;
 585| end;
 586| $function$;
 587| 
 588| -- Quién ve una llamada: con lead, el lead tiene que estar ACTIVO para todos, gerencia incluida (fallo 2), y
 589| -- además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena.
 590| create or replace function private.llamada_celular_visible(p_actor uuid, p_lead uuid, p_analista uuid)
 591| returns boolean
 592| language sql
 593| stable
 594| set search_path = ''
 595| as $function$
 596|   select p_actor is not null and case
 597|     when p_lead is not null then
 598|       exists (select 1 from crm.leads l where l.id = p_lead and l.activo)
 599|       and (coalesce(private.rol_crm(p_actor) = 'gerencia', false)
 600|            or coalesce(private.sla_gestion_permitida(p_actor, p_lead), false))
 601|     else
 602|       coalesce(private.rol_crm(p_actor) = 'gerencia', false)
 603|       or p_analista = p_actor
 604|       or p_analista in (select private.vendedor_ids_visibles(p_actor))
 605|   end
 606| $function$;
 607| 
 608| -- §3. Candados en el orden resultado → lead(s) → llamada → enlace. La llamada se lee primero SIN candado solo
 609| -- para saber qué leads bloquear; después de bloquearla se comprueba que su lead no cambió y se revalida el ámbito.
 610| create or replace function private.llamada_celular_asociar(p_actor uuid, p_evento_id uuid, p_lead_id uuid)
 611| returns jsonb
 612| language plpgsql
 613| volatile
 614| set search_path = ''
 615| as $function$
 616| declare
 617|   v_ev crm.llamadas_celular_eventos%rowtype;
 618|   v_lead_leido uuid;
 619|   v_aten text;
 620| begin
 621|   if p_evento_id is null or p_lead_id is null then
 622|     raise exception using errcode = '22023', message = 'Faltan la llamada o el lead';
 623|   end if;
 624|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 625|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 626|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 627|   end if;
 628|   -- El lead anterior y el destino, por id (Codex P10): la autorización depende de los dos.
 629|   perform 1 from crm.leads l where l.id in (v_ev.lead_id, p_lead_id) order by l.id for share;
 630|   v_lead_leido := v_ev.lead_id;
 631|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 632|   if not found or v_ev.lead_id is distinct from v_lead_leido then
 633|     raise exception using errcode = '40001', message = 'La llamada cambió mientras la asociabas; vuelve a intentarlo';
 634|   end if;
 635|   if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 636|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 637|   end if;
 638|   if v_ev.atencion in ('registrado', 'descartado_con_motivo') then
 639|     raise exception using errcode = '22023', message = 'La llamada ya está registrada o descartada';
 640|   end if;
 641|   if v_ev.lead_id = p_lead_id then
 642|     return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', v_ev.lead_id, 'repetido', true,
 643|       'atencion', private.llamada_celular_atencion_efectiva(p_actor, v_ev.atencion, v_ev.identificacion, v_ev.lead_id));
 644|   end if;
 645|   if not coalesce(private.sla_gestion_permitida(p_actor, p_lead_id), false) then
 646|     raise exception using errcode = '42501', message = 'Ese lead no es de tu ámbito';
 647|   end if;
 648|   -- Nunca fabrica gestión: el lead elegido tiene que tener el número de la llamada.
 649|   if not (p_lead_id = any(private.llamada_celular_candidatos(private.llamada_celular_formas(v_ev.numero_canonico)))) then
 650|     raise exception using errcode = '22023', message = 'Ese lead no tiene el número de la llamada';
 651|   end if;
 652|   v_aten := case when private.llamada_celular_elegible(p_actor, p_lead_id)
 653|                  then 'requiere_resultado' else 'por_revisar' end;
 654|   update crm.llamadas_celular_eventos
 655|      set identificacion = 'identificado', lead_id = p_lead_id, metodo_asociacion = 'manual',
 656|          asociado_por = p_actor, asociado_en = pg_catalog.now(), atencion = v_aten
 657|    where id = v_ev.id;
 658|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'lead_id', p_lead_id, 'repetido', false,
 659|     'atencion', v_aten);
 660| end;
 661| $function$;
 662| 
 663| -- Enlace MANUAL: resultado FOR SHARE (el mismo primer candado que Deshacer, que lo toma FOR UPDATE: no se
 664| -- cruzan) → lead → llamada → enlace. Conserva la regla de los 10 minutos: solo vale para este camino; el enlace
 665| -- exacto por id (F4-a) no la usa (confirmación 3 de Miguel, Codex P2-5).
 666| create or replace function private.llamada_celular_enlazar(p_actor uuid, p_evento_id uuid, p_actividad_id uuid)
 667| returns jsonb
 668| language plpgsql
 669| volatile
 670| set search_path = ''
 671| as $function$
 672| declare
 673|   v_ev crm.llamadas_celular_eventos%rowtype;
 674|   v_act crm.actividades%rowtype;
 675|   v_enl crm.llamadas_celular_enlaces%rowtype;
 676|   v_lead_leido uuid;
 677|   v_deshecha boolean;
 678|   v_movido boolean := false;
 679| begin
 680|   if p_evento_id is null or p_actividad_id is null then
 681|     raise exception using errcode = '22023', message = 'Faltan la llamada o el resultado';
 682|   end if;
 683|   -- Decisión 7: con lead, «visible» ES tener hoy ámbito sobre él; quien ya no lo tiene no registra por él.
 684|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 685|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 686|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 687|   end if;
 688|   if v_ev.identificacion <> 'identificado' then
 689|     raise exception using errcode = '22023', message = 'Primero asocia la llamada a un lead';
 690|   end if;
 691|   select * into v_act from crm.actividades a where a.id = p_actividad_id for share;
 692|   if not found or v_act.lead_id <> v_ev.lead_id then
 693|     raise exception using errcode = '22023', message = 'El resultado no es del lead de la llamada';
 694|   end if;
 695|   perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
 696|   v_lead_leido := v_ev.lead_id;
 697|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 698|   if not found or v_ev.lead_id is distinct from v_lead_leido then
 699|     raise exception using errcode = '40001', message = 'La llamada cambió mientras la enlazabas; vuelve a intentarlo';
 700|   end if;
 701|   if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 702|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 703|   end if;
 704|   if v_ev.atencion = 'descartado_con_motivo' then
 705|     raise exception using errcode = '22023', message = 'La llamada fue descartada';
 706|   end if;
 707|   if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 708|      or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 709|     raise exception using errcode = '22023', message = 'Solo se enlaza un resultado de llamada registrado en la encuesta';
 710|   end if;
 711|   if v_act.metadata ? 'deshecho_en' then
 712|     raise exception using errcode = '22023', message = 'Ese resultado se deshizo: enlaza el resultado corregido';
 713|   end if;
 714|   if v_act.creado_en < coalesce(v_ev.ocurrio_en, v_ev.recibido_en) - interval '10 minutes' then
 715|     raise exception using errcode = '22023', message = 'El resultado se registró antes de la llamada';
 716|   end if;
 717| 
 718|   select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
 719|   if found then
 720|     if v_enl.actividad_id = p_actividad_id then
 721|       return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
 722|         'repetido', true, 'movido', false);
 723|     end if;
 724|     select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
 725|     if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
 726|       raise exception using errcode = '23505', message = 'La llamada ya tiene su resultado registrado';
 727|     end if;
 728|     begin
 729|       update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
 730|        where id = v_enl.id;
 731|     exception when unique_violation then
 732|       raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
 733|     end;
 734|     v_movido := true;
 735|   else
 736|     begin
 737|       insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
 738|       values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor);
 739|     exception when unique_violation then
 740|       raise exception using errcode = '23505', message = 'Ese resultado ya está enlazado a otra llamada';
 741|     end;
 742|   end if;
 743| 
 744|   -- La máquina de estados de la tabla exige pasar por «requiere resultado».
 745|   if v_ev.atencion = 'por_revisar' then
 746|     update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
 747|   end if;
 748|   if v_ev.atencion <> 'registrado' then
 749|     update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
 750|   end if;
 751|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'actividad_id', p_actividad_id,
 752|     'repetido', false, 'movido', v_movido);
 753| end;
 754| $function$;
 755| 
 756| create or replace function private.llamada_celular_descartar(p_actor uuid, p_evento_id uuid, p_motivo text, p_detalle text)
 757| returns jsonb
 758| language plpgsql
 759| volatile
 760| set search_path = ''
 761| as $function$
 762| declare
 763|   v_ev crm.llamadas_celular_eventos%rowtype;
 764|   v_lead_leido uuid;
 765|   v_detalle text := nullif(pg_catalog.btrim(coalesce(p_detalle, '')), '');
 766| begin
 767|   if p_evento_id is null then
 768|     raise exception using errcode = '22023', message = 'Falta la llamada';
 769|   end if;
 770|   if p_motivo is null or p_motivo not in ('no_comercial', 'personal', 'numero_de_prueba', 'error_captura', 'otro') then
 771|     raise exception using errcode = '22023',
 772|       message = 'Motivo inválido (no_comercial, personal, numero_de_prueba, error_captura u otro)';
 773|   end if;
 774|   if p_motivo = 'otro' and pg_catalog.length(coalesce(v_detalle, '')) < 3 then
 775|     raise exception using errcode = '22023', message = 'Con «otro», escribe el motivo (al menos 3 caracteres)';
 776|   end if;
 777|   if pg_catalog.length(coalesce(v_detalle, '')) > 300 then
 778|     raise exception using errcode = '22023', message = 'El detalle no puede pasar de 300 caracteres';
 779|   end if;
 780|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id;
 781|   if not found or not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 782|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 783|   end if;
 784|   perform 1 from crm.leads l where l.id = v_ev.lead_id for share;
 785|   v_lead_leido := v_ev.lead_id;
 786|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 787|   if not found or v_ev.lead_id is distinct from v_lead_leido then
 788|     raise exception using errcode = '40001', message = 'La llamada cambió mientras la descartabas; vuelve a intentarlo';
 789|   end if;
 790|   if not private.llamada_celular_visible(p_actor, v_ev.lead_id, v_ev.analista_id) then
 791|     raise exception using errcode = '42501', message = 'Llamada no encontrada o fuera de tu ámbito';
 792|   end if;
 793|   if v_ev.atencion = 'descartado_con_motivo' then
 794|     if v_ev.motivo_descarte = p_motivo and v_ev.motivo_descarte_detalle is not distinct from v_detalle then
 795|       return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', true, 'motivo', p_motivo);
 796|     end if;
 797|     raise exception using errcode = '23505', message = 'La llamada ya fue descartada con otro motivo';
 798|   end if;
 799|   if v_ev.atencion = 'registrado' then
 800|     raise exception using errcode = '22023', message = 'La llamada ya tiene su resultado registrado';
 801|   end if;
 802|   update crm.llamadas_celular_eventos
 803|      set atencion = 'descartado_con_motivo', motivo_descarte = p_motivo, motivo_descarte_detalle = v_detalle,
 804|          descartado_por = p_actor, descartado_en = pg_catalog.now()
 805|    where id = v_ev.id;
 806|   return pg_catalog.jsonb_build_object('evento_id', v_ev.id, 'repetido', false, 'motivo', p_motivo);
 807| end;
 808| $function$;
 809| 
 810| create or replace function private.llamadas_celular_politica_fijar(
 811|   p_actor uuid, p_guardar_sin_identificar boolean, p_entrantes_activas boolean,
 812|   p_dias_descartados integer, p_dias_sin_resolver integer, p_dias_sin_identificar integer)
 813| returns jsonb
 814| language plpgsql
 815| volatile
 816| set search_path = ''
 817| as $function$
 818| declare
 819|   v_pol crm.llamadas_celular_politica%rowtype;
 820| begin
 821|   if coalesce(private.rol_crm(p_actor), '') <> 'gerencia' then
 822|     raise exception using errcode = '42501', message = 'Solo gerencia ajusta la política de llamadas';
 823|   end if;
 824|   if p_entrantes_activas then
 825|     raise exception using errcode = '22023',
 826|       message = 'Las llamadas entrantes siguen bloqueadas: llegan con la propuesta #14, como paso propio';
 827|   end if;
 828|   if (p_dias_descartados is not null and p_dias_descartados not between 1 and 365)
 829|      or (p_dias_sin_resolver is not null and p_dias_sin_resolver not between 1 and 365)
 830|      or (p_dias_sin_identificar is not null and p_dias_sin_identificar not between 1 and 365) then
 831|     raise exception using errcode = '22023', message = 'Los días de retención van de 1 a 365';
 832|   end if;
 833|   update crm.llamadas_celular_politica
 834|      set guardar_sin_identificar = coalesce(p_guardar_sin_identificar, guardar_sin_identificar),
 835|          entrantes_activas = coalesce(p_entrantes_activas, entrantes_activas),
 836|          dias_retencion_descartados = coalesce(p_dias_descartados, dias_retencion_descartados),
 837|          dias_retencion_sin_resolver = coalesce(p_dias_sin_resolver, dias_retencion_sin_resolver),
 838|          dias_retencion_sin_identificar = coalesce(p_dias_sin_identificar, dias_retencion_sin_identificar),
 839|          actualizado_por = p_actor
 840|    where singleton
 841|   returning * into v_pol;
 842|   return pg_catalog.to_jsonb(v_pol) - 'singleton';
 843| end;
 844| $function$;
 845| 
 846| -- §5. Retención (decisión 4; Codex P4 y P7). La purga mira el ENLACE, no la atención: una registrada se
 847| -- conserva como historial del lead aunque su resultado se haya deshecho; las de un lead dado de baja quedan
 848| -- ocultas y se conservan como el resto de su historial.
 849| create or replace function private.caducar_llamadas_celular()
 850| returns integer
 851| language plpgsql
 852| security definer
 853| set search_path to ''
 854| as $function$
 855| declare
 856|   v_pol crm.llamadas_celular_politica%rowtype;
 857|   v_n integer := 0;
 858|   v_parcial integer;
 859| begin
 860|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 861|   if not found then
 862|     return 0;
 863|   end if;
 864|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);
 865| 
 866|   -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
 867|   delete from crm.llamadas_celular_eventos e
 868|    where e.atencion = 'descartado_con_motivo'
 869|      and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
 870|   get diagnostics v_parcial = row_count;
 871|   v_n := v_n + v_parcial;
 872| 
 873|   -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
 874|   -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
 875|   delete from crm.llamadas_celular_eventos e
 876|    where e.identificacion in ('identificado', 'ambiguo')
 877|      and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 878|      and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
 879|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
 880|   get diagnostics v_parcial = row_count;
 881|   v_n := v_n + v_parcial;
 882| 
 883|   -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
 884|   delete from crm.llamadas_celular_eventos e
 885|    where e.identificacion = 'sin_identificar'
 886|      and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 887|      and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
 888|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
 889|   get diagnostics v_parcial = row_count;
 890|   v_n := v_n + v_parcial;
 891| 
 892|   -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
 893|   -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
 894|   delete from private.llamadas_celular_recepciones r
 895|    where r.recibido_en < pg_catalog.now() - interval '32 days';
 896|   get diagnostics v_parcial = row_count;
 897|   v_n := v_n + v_parcial;
 898| 
 899|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
 900|   return v_n;
 901| end;
 902| $function$;
 903| 
 904| -- §6. Salud sin envíos (N1): solo el latido, la versión de la macro y la cola.
 905| create or replace function private.celulares_salud_listar(p_actor uuid)
 906| returns jsonb
 907| language sql
 908| stable
 909| set search_path = ''
 910| as $function$
 911|   select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
 912|            'asignacion_id', a.id, 'etiqueta', a.etiqueta, 'analista_id', a.analista_id,
 913|            'analista_nombre', p.nombre_completo, 'vigente_desde', a.vigente_desde,
 914|            'ultimo_latido_en', s.ultimo_latido_en, 'latido_celular_en', s.latido_celular_en,
 915|            'version_macro', s.version_macro, 'eventos_en_cola', s.eventos_en_cola)
 916|          order by a.etiqueta), '[]'::jsonb)
 917|   from crm.celulares_asignaciones a
 918|   left join private.celulares_estado s on s.asignacion_id = a.id
 919|   left join public.perfiles p on p.id = a.analista_id
 920|   where a.vigente_hasta is null
 921|     and (private.rol_crm(p_actor) = 'gerencia'
 922|          or (private.rol_crm(p_actor) = 'supervisor'
 923|              and a.analista_id in (select private.vendedor_ids_visibles(p_actor))))
 924| $function$;
 925| 
 926| -- §8. Bandeja duplicada retirada (decisión 6): la paginada (crm.llamadas_celular_bandeja_fn) es la única.
 927| drop function crm.llamadas_celular_pendientes_fn(integer);
 928| drop function private.llamadas_celular_pendientes(uuid, integer);
 929| 
 930| -- ── 6. Puertas de servicio con el orden y el contrato nuevos ─────────────────────────────────
 931| create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
 932| returns jsonb
 933| language plpgsql
 934| volatile
 935| security definer
 936| set search_path = ''
 937| as $function$
 938| declare
 939|   v_asig uuid := private.celular_por_credencial(p_credencial);
 940|   v_ahora timestamptz;
 941|   v_r jsonb;
 942| begin
 943|   if v_asig is null then
 944|     raise exception using errcode = '42501', message = 'No autorizado';
 945|   end if;
 946|   v_ahora := private.celular_consumir_envio(v_asig);
 947|   begin
 948|     v_r := private.llamada_celular_ingerir(v_asig, p_evento, v_ahora);
 949|   exception when insufficient_privilege then
 950|     -- La misma respuesta que una clave mala, sin el mensaje del núcleo.
 951|     raise exception using errcode = '42501', message = 'No autorizado';
 952|   end;
 953|   -- A la Edge, solo el resultado: guardada, repetida o ignorada responden igual (#12).
 954|   return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
 955|     'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
 956| end;
 957| $function$;
 958| 
 959| create or replace function crm.registrar_salud_celular_servicio(p_credencial text, p_latido jsonb)
 960| returns jsonb
 961| language plpgsql
 962| volatile
 963| security definer
 964| set search_path = ''
 965| as $function$
 966| declare
 967|   v_asig uuid := private.celular_por_credencial(p_credencial);
 968|   v_ahora timestamptz;
 969|   v_r jsonb;
 970| begin
 971|   if v_asig is null then
 972|     raise exception using errcode = '42501', message = 'No autorizado';
 973|   end if;
 974|   v_ahora := private.celular_consumir_envio(v_asig);
 975|   v_r := private.celular_registrar_salud(v_asig, p_latido, v_ahora);
 976|   return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
 977|     'resultado', v_r ->> 'resultado', 'mensaje', v_r ->> 'mensaje'));
 978| end;
 979| $function$;
 980| 
 981| -- ── 7. Permisos: el núcleo nuevo sin EXECUTE para nadie (las puertas conservan los suyos) ────
 982| do $permisos$
 983| declare
 984|   v_f text;
 985| begin
 986|   foreach v_f in array array[
 987|     'private.trg_llamadas_celular_recepciones_candado()', 'private.celular_consumir_envio(uuid)',
 988|     'private.llamada_celular_fecha(text)', 'private.celular_registrar_salud(uuid,jsonb,timestamptz)',
 989|     'private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)',
 990|     'private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'] loop
 991|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 992|   end loop;
 993| end;
 994| $permisos$;
 995| 
 996| -- ── 8. Comentarios ───────────────────────────────────────────────────────────────────────────
 997| comment on table private.llamadas_celular_recepciones is
 998|   'Una fila por cada llamada del celular ACEPTADA (id válido), registrada antes de buscar el lead, también si después se ignora (fallo 1 de la revisión del 02/10). Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada. Caduca a los 32 días (la purga diaria), cuando su id ya no puede volver a entrar por la ventana. Tabla técnica de private, sin acceso para la API y sin auditoría (como private.celulares_estado): guarda el id y la asignación, sin número ni hash; aun así dice a qué hora llamaba el analista, por eso caduca. Sin columna de tenant: CRM de una sola empresa.';
 999| comment on column private.llamadas_celular_recepciones.id is 'Identificador de la recepción.';
1000| comment on column private.llamadas_celular_recepciones.evento_origen_id is 'Id de la llamada tal como lo genera la macro: C<n>-<segundos del reloj del celular>. Único.';
1001| comment on column private.llamadas_celular_recepciones.asignacion_id is 'Asignación cuya clave trajo el aviso (crm.celulares_asignaciones).';
1002| comment on column private.llamadas_celular_recepciones.recibido_en is 'Hora del servidor al aceptarla (la que toma la puerta tras bloquear el estado del celular). De aquí corren los 32 días.';
1003| comment on column private.llamadas_celular_recepciones.creado_en is 'Alta de la fila.';
1004| comment on column private.llamadas_celular_recepciones.actualizado_en is 'Igual a creado_en: la fila es inmutable.';
1005| comment on constraint llamadas_celular_politica_entrantes_bloqueadas on crm.llamadas_celular_politica is
1006|   'Entrantes bloqueadas (fallo 3, decisión 2 de Miguel del 03/10): la #14 llega después, como paso propio, y retira este CHECK.';
1007| comment on column crm.llamadas_celular_politica.entrantes_activas is 'Siempre false: entrantes bloqueadas por el CHECK llamadas_celular_politica_entrantes_bloqueadas y por la puerta (decisión 2 de Miguel, 03/10). La ingesta ignora toda llamada que no sea saliente.';
1008| comment on column crm.llamadas_celular_politica.dias_retencion_sin_resolver is 'Días que vive una llamada sin resolver desde recibido_en: identificada sin enlace (pide resultado o está por revisar) o ambigua (30, decisión 4 de Miguel del 03/10). Las registradas no caducan: son historial del lead.';
1009| comment on column crm.llamadas_celular_eventos.evento_origen_id is 'Id de la llamada generado por la macro al colgar: C<n>-<segundos del reloj del celular>, con la etiqueta de la asignación. Único (rotar la clave ya no duplica). No puede llevar un teléfono. F4 encuentra la llamada por este id completo.';
1010| comment on table crm.llamadas_celular_eventos is
1011|   'Evidencia de cada llamada saliente hecha desde un celular corporativo a un número de lead candidato (F2, corregida en 20261005143843). Payload inmutable (celular, id, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración). Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene; el lead tiene que estar activo); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría; retención por crm.llamadas_celular_politica, las registradas se conservan). Sin columna de tenant: CRM de una sola empresa.';
1012| comment on table private.celulares_estado is
1013|   'Estado técnico de cada celular asignado: último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima, ventanas que nunca retroceden). Una fila por asignación. Desde 20261005143843 no guarda la hora del último envío y la salud no muestra los contadores (N1): cuentan llamadas personales. Tabla técnica de private, sin acceso para la API y sin auditoría. Sin columna de tenant: CRM de una sola empresa.';
1014| comment on column private.celulares_estado.ultimo_latido_en is 'Cuándo llegó el último latido (hora del servidor tomada por la puerta tras bloquear este estado). Un latido solo prueba que el celular habla, no que capture bien.';
1015| comment on column private.celulares_estado.minuto_desde is 'Inicio del minuto de reloj al que corresponde envios_minuto. Nunca retrocede.';
1016| comment on column private.celulares_estado.dia is 'Día de Lima al que corresponde envios_dia. Nunca retrocede.';
1017| comment on column private.celulares_estado.envios_minuto is 'Envíos contados en el minuto minuto_desde (válidos, repetidos o inválidos: todo gasta cupo). Solo para el límite; la salud no lo muestra.';
1018| comment on column private.celulares_estado.envios_dia is 'Envíos contados en el día dia. Solo para el límite; la salud no lo muestra (N1).';
1019| 
1020| comment on function private.trg_llamadas_celular_recepciones_candado() is
1021|   'Candado de private.llamadas_celular_recepciones: inmutable; DELETE solo bajo el GUC crm.op_purga_llamadas=on (la purga). SECURITY DEFINER por coherencia con los demás candados; no lee datos.';
1022| comment on function private.trg_llamadas_celular_eventos_candado() is
1023|   'Candado de crm.llamadas_celular_eventos: payload inmutable; identificación que solo avanza; lead fijado una vez (corregible solo por atender); transiciones de atención permitidas y finales; descarte no reescribible; DELETE solo bajo el GUC crm.op_purga_llamadas=on o en cascada. Desde 20261005143843 sin hash_payload. SECURITY DEFINER por coherencia; no lee otras tablas.';
1024| comment on function private.celular_por_credencial(text) is
1025|   'Resuelve la clave de un celular: la asignación vigente cuyo credencial_hash es el sha256 de la clave, BLOQUEADA FOR SHARE y revalidada bajo el candado (vigente y con analista o supervisor activo); null en cualquier otro caso. Un cierre o una rotación concurrente se serializa con el envío (menor 6). DATO SENSIBLE: recibe la clave en claro y no la guarda.';
1026| comment on function private.celular_consumir_envio(uuid) is
1027|   'Límite por celular, compartido por llamadas y latidos: bloquea la fila de estado, toma la hora UNA vez (clock_timestamp, después del candado) y la devuelve; ventanas fijas que nunca retroceden (minuto de reloj, día de Lima); sin política, 55000; al pasarse, P0429 con DETAIL reintentar_en_seg=N (≥ 1). El cupo queda gastado aunque el aviso resulte inválido.';
1028| comment on function private.llamada_celular_fecha(text) is
1029|   'Fecha estricta del celular (menor 15): ISO 8601 con segundos y zona (Z o ±HH:MM), con T o espacio, entre 2026 y 2100; si no, 22023. Null si no vino.';
1030| comment on function private.celular_registrar_salud(uuid,jsonb,timestamptz) is
1031|   'Latido v1 con claves exactas (version_macro y en_cola obligatorios, ocurrio_en opcional y estricto). Inválido → {resultado: invalido, mensaje} sin tocar el estado (el cupo ya gastado queda). Válido → guarda versión, cola y la hora de la puerta. Un latido no demuestra captura sana.';
1032| comment on function private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz) is
1033|   'Candidatos de una llamada (§2 del plan v2): leads activos con el número y (a) del ámbito del dueño del celular, evaluado COMO el dueño (fija request.jwt.claim.sub y lo devuelve antes de escribir); (b) sin dueño en etapa abierta; o (c) descartados reutilizables (regla de «Nuevo lead»: espera de crm.enfriamiento_politica cumplida, 24 h si son 0 días). Sin dueño o sin número, ninguno. DATO PERSONAL: recibe el número.';
1034| comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
1035|   'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número.';
1036| comment on function private.llamada_celular_visible(uuid,uuid,uuid) is
1037|   'Quién ve una llamada: con lead, solo si el lead está activo (para todos, gerencia incluida: fallo 2) y además gerencia o quien hoy tiene ámbito sobre él (decisión 7); sin lead, gerencia, quien llamó y su cadena de supervisión.';
1038| comment on function private.llamada_celular_asociar(uuid,uuid,uuid) is
1039|   'Asocia una llamada a un lead del ámbito del actor que tenga el número de la llamada (nunca fabrica gestión). Candados: el lead anterior y el destino FOR SHARE por id, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito bajo los candados. Idempotente.';
1040| comment on function private.llamada_celular_enlazar(uuid,uuid,uuid) is
1041|   'Enlace MANUAL de la llamada con el resultado que la encuesta registró para el mismo lead. Candados: resultado FOR SHARE → lead → llamada → enlace (el orden de Deshacer); si su lead cambió, 40001; revalida el ámbito. Rechaza un resultado deshecho (menor 10) y uno anterior a la llamada (10 min, solo en este camino). Si el enlazado fue deshecho, el enlace se mueve. Deja la llamada en «registrado». Idempotente.';
1042| comment on function private.llamada_celular_descartar(uuid,uuid,text,text) is
1043|   'Descarta una llamada con motivo de catálogo («otro» con detalle). Candados: su lead FOR SHARE, después la llamada FOR UPDATE; si su lead cambió, 40001; revalida el ámbito. Idempotente con el mismo motivo, 23505 con otro.';
1044| comment on function private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer) is
1045|   'Gerencia ajusta las perillas de la política de llamadas; los parámetros nulos conservan su valor. Encender las entrantes se rechaza con 22023: siguen bloqueadas hasta la #14.';
1046| comment on function private.caducar_llamadas_celular() is
1047|   'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API.';
1048| comment on function private.celulares_salud_listar(uuid) is
1049|   'Salud de los celulares vigentes: gerencia todos, supervisión los de su equipo. Solo latido, versión de la macro y cola: sin envíos ni último envío (N1, cuentan llamadas personales). Sin hash de credencial.';
1050| comment on function private.llamadas_celular_bandeja(uuid,integer,timestamptz,uuid) is
1051|   'Bandeja paginada (la única desde 20261005143843) de llamadas no finales visibles para el actor, por cursor (recibido_en, evento_id) descendente, con la atención efectiva. DATO PERSONAL: número y nombre del lead (el actor ya tiene ámbito sobre ellos).';
1052| comment on function crm.ingerir_llamada_celular_servicio(text,jsonb) is
1053|   'Puerta de SERVICIO (DEFINER, solo service_role: la llama la Edge crm-llamadas-ingesta). Orden: clave (asignación FOR SHARE, revalidada; si no, el mismo 42501 «No autorizado») → cupo (P0429 con la espera) → núcleo. Devuelve solo {resultado: aceptado | invalido, mensaje}: la Edge responde 202 o 400. Guardada, repetida o ignorada responden igual (#12). DATO SENSIBLE: recibe la clave; DATO PERSONAL: el número.';
1054| comment on function crm.registrar_salud_celular_servicio(text,jsonb) is
1055|   'Puerta de SERVICIO (DEFINER, solo service_role) para el latido de un celular: misma clave revalidada bajo candado y mismo cupo que la ingesta; devuelve {resultado: aceptado | invalido, mensaje} (la Edge responde 200 o 400). DATO SENSIBLE: recibe la clave.';
1056| comment on function crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer) is
1057|   'Puerta (DEFINER) para ajustar la política de llamadas del celular: solo gerencia; los nulos conservan el valor; encender las entrantes se rechaza (bloqueadas hasta la #14).';
1058| 
1059| -- ── 9. Postflight ────────────────────────────────────────────────────────────────────────────
1060| do $postflight$
1061| declare
1062|   v_f record;
1063|   v_t text := 'private.llamadas_celular_recepciones';
1064| begin
1065|   -- La recepción: RLS, cerrada a la API, sin policies, con sus candados, FK que no desatribuye y comentada.
1066|   if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
1067|     raise exception 'LLAMADAS_CORRECCION: % quedó sin RLS', v_t;
1068|   end if;
1069|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
1070|              where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
1071|     raise exception 'LLAMADAS_CORRECCION: % quedó accesible desde la API', v_t;
1072|   end if;
1073|   if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
1074|     raise exception 'LLAMADAS_CORRECCION: % no debe tener policies (todo va por puertas)', v_t;
1075|   end if;
1076|   if (select count(*) from pg_catalog.pg_trigger t
1077|       where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
1078|         and t.tgname in ('trg_llamadas_celular_recepciones_00_candado', 'trg_llamadas_celular_recepciones_00_sin_vaciar')) <> 2 then
1079|     raise exception 'LLAMADAS_CORRECCION: % quedó sin sus candados', v_t;
1080|   end if;
1081|   if exists (select 1 from pg_catalog.pg_constraint c
1082|              where c.contype = 'f' and c.conrelid = v_t::regclass and c.confdeltype <> 'r') then
1083|     raise exception 'LLAMADAS_CORRECCION: la FK de % no es RESTRICT', v_t;
1084|   end if;
1085|   if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
1086|      or exists (select 1 from pg_catalog.pg_attribute a
1087|                 where a.attrelid = v_t::regclass and a.attnum > 0 and not a.attisdropped
1088|                   and pg_catalog.col_description(a.attrelid, a.attnum) is null) then
1089|     raise exception 'LLAMADAS_CORRECCION: % tiene la tabla o alguna columna sin COMMENT', v_t;
1090|   end if;
1091| 
1092|   -- Los eventos: único por id, forma fija, sin hash y con la bitácora enmascarando el número.
1093|   if not exists (select 1 from pg_catalog.pg_constraint c
1094|                  where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.contype = 'u'
1095|                    and c.conname = 'llamadas_celular_eventos_origen_uq'
1096|                    and c.conkey = array[(select a.attnum from pg_catalog.pg_attribute a
1097|                                          where a.attrelid = c.conrelid and a.attname = 'evento_origen_id')]::smallint[])
1098|      or exists (select 1 from pg_catalog.pg_constraint c
1099|                 where c.conrelid = 'crm.llamadas_celular_eventos'::regclass and c.conname = 'llamadas_celular_eventos_origen_unico') then
1100|     raise exception 'LLAMADAS_CORRECCION: la llamada no quedó única por id';
1101|   end if;
1102|   if exists (select 1 from pg_catalog.pg_attribute a
1103|              where a.attnum > 0 and not a.attisdropped
1104|                and ((a.attrelid = 'crm.llamadas_celular_eventos'::regclass and a.attname = 'hash_payload')
1105|                     or (a.attrelid = 'private.celulares_estado'::regclass and a.attname = 'ultimo_envio_en'))) then
1106|     raise exception 'LLAMADAS_CORRECCION: quedó hash_payload o ultimo_envio_en';
1107|   end if;
1108|   if not exists (select 1 from pg_catalog.pg_trigger t
1109|                  where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and t.tgname = 'trg_audit_llamadas_celular_eventos'
1110|                    and t.tgenabled in ('O', 'A') and t.tgfoid = 'private.log_audit_sin_secretos()'::regprocedure
1111|                    and t.tgnargs = 1 and pg_catalog.encode(t.tgargs, 'escape') = 'numero_canonico\000')
1112|      or (select count(*) from pg_catalog.pg_trigger t
1113|          where t.tgrelid = 'crm.llamadas_celular_eventos'::regclass and not t.tgisinternal) <> 3
1114|      or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_eventos') then
1115|     raise exception 'LLAMADAS_CORRECCION: la bitácora de las llamadas no quedó con el número enmascarado';
1116|   end if;
1117|   if not exists (select 1 from pg_catalog.pg_constraint c
1118|                  where c.conrelid = 'crm.llamadas_celular_politica'::regclass
1119|                    and c.conname = 'llamadas_celular_politica_entrantes_bloqueadas' and c.contype = 'c') then
1120|     raise exception 'LLAMADAS_CORRECCION: las entrantes no quedaron bloqueadas';
1121|   end if;
1122| 
1123|   -- Lo retirado ya no está.
1124|   if to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is not null
1125|      or to_regprocedure('private.celular_registrar_salud(uuid,jsonb)') is not null
1126|      or to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null
1127|      or to_regprocedure('private.llamadas_celular_pendientes(uuid,integer)') is not null then
1128|     raise exception 'LLAMADAS_CORRECCION: quedó una pieza retirada (ingesta vieja, latido viejo o bandeja duplicada)';
1129|   end if;
1130| 
1131|   for v_f in
1132|     select * from (values
1133|       ('private.trg_llamadas_celular_recepciones_candado()', true, null),
1134|       ('private.trg_llamadas_celular_eventos_candado()', true, null),
1135|       ('private.caducar_llamadas_celular()', true, null),
1136|       ('private.celular_por_credencial(text)', false, null),
1137|       ('private.celular_consumir_envio(uuid)', false, null),
1138|       ('private.llamada_celular_fecha(text)', false, null),
1139|       ('private.celular_registrar_salud(uuid,jsonb,timestamptz)', false, null),
1140|       ('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)', false, null),
1141|       ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
1142|       ('private.llamada_celular_visible(uuid,uuid,uuid)', false, null),
1143|       ('private.llamada_celular_asociar(uuid,uuid,uuid)', false, null),
1144|       ('private.llamada_celular_enlazar(uuid,uuid,uuid)', false, null),
1145|       ('private.llamada_celular_descartar(uuid,uuid,text,text)', false, null),
1146|       ('private.llamadas_celular_politica_fijar(uuid,boolean,boolean,integer,integer,integer)', false, null),
1147|       ('private.celulares_salud_listar(uuid)', false, null),
1148|       ('crm.ingerir_llamada_celular_servicio(text,jsonb)', true, 'service_role'),
1149|       ('crm.registrar_salud_celular_servicio(text,jsonb)', true, 'service_role'),
1150|       ('crm.llamadas_celular_bandeja_fn(integer,timestamptz,uuid)', true, 'authenticated'),
1151|       ('crm.celulares_salud_fn()', true, 'authenticated'),
1152|       ('crm.fijar_politica_llamadas_celular(boolean,boolean,integer,integer,integer)', true, 'authenticated')
1153|     ) as f(firma, definer, rol)
1154|   loop
1155|     if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
1156|       raise exception 'LLAMADAS_CORRECCION: % debería ser %', v_f.firma,
1157|         case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
1158|     end if;
1159|     if exists (
1160|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
1161|       where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
1162|         and a.grantee <> p.proowner
1163|         and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
1164|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
1165|       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
1166|       raise exception 'LLAMADAS_CORRECCION: EXECUTE inesperado en %', v_f.firma;
1167|     end if;
1168|     if not exists (select 1 from pg_catalog.pg_proc p
1169|                    where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
1170|       raise exception 'LLAMADAS_CORRECCION: search_path inesperado en %', v_f.firma;
1171|     end if;
1172|     if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
1173|       raise exception 'LLAMADAS_CORRECCION: % sin COMMENT', v_f.firma;
1174|     end if;
1175|     -- El 409 desapareció de la ingesta (fallo 1): ninguna pieza de llamadas lo lanza.
1176|     if pg_catalog.strpos(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure), 'P0409') > 0 then
1177|       raise exception 'LLAMADAS_CORRECCION: % todavía lanza P0409', v_f.firma;
1178|     end if;
1179|     -- Ningún bloque atrapa cualquier error (Codex P3): un fallo inesperado no se disfraza de «invalido».
1180|     if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
1181|       raise exception 'LLAMADAS_CORRECCION: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
1182|     end if;
1183|   end loop;
1184| 
1185|   -- Las tablas siguen cerradas a la API.
1186|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol),
1187|                     (values ('crm.llamadas_celular_politica'), ('crm.celulares_asignaciones'),
1188|                             ('crm.llamadas_celular_eventos'), ('crm.llamadas_celular_enlaces'),
1189|                             ('private.celulares_estado')) t(tabla)
1190|              where pg_catalog.has_table_privilege(r.rol, t.tabla,
1191|                      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
1192|     raise exception 'LLAMADAS_CORRECCION: alguna tabla de llamadas quedó accesible desde la API';
1193|   end if;
1194| end;
1195| $postflight$;
1196| 
1197| notify pgrst, 'reload schema';
1198| commit;
```

## Archivo: supabase/migrations/20261005155914_crm_llamadas_celular_enlace_exacto.sql (794 líneas) — F4-a (lo que se revisa)
```
   1| -- Llamadas desde el celular · F4-a: ENLACE EXACTO encuesta ↔ llamada (sexta migración; se publica JUNTO con las cinco
   2| -- de F2 + F3, decisión 1 de Miguel del 03/10). Plan: CORRECCION-PLAN-CORTO.md §7 (v2, PR #179) y F4-PLAN-CORTO.md §1.
   3| -- Cierra el fallo 5 de la revisión del 02/10 (nada unía la encuesta con su llamada) del lado de la base; la pantalla
   4| -- que lleva el id hasta la encuesta y llama a la v5 es F4-b.
   5| --
   6| -- Qué hace (sobre 20261005143843; no toca la v4 sellada):
   7| --   1. crm.registrar_llamada_v5: la misma operación que la v4 (llama a su núcleo sellado private.llamada_registrar_v4,
   8| --      que bloquea el lead y crea el resultado) y, en la MISMA transacción, une ese resultado a la llamada por su id
   9| --      exacto (C<n>-<segundos>, el que la macro pone en la URL al colgar):
  10| --        · si la llamada ya llegó (del celular del mismo analista, identificada con ese lead) → el enlace;
  11| --        · si todavía no llegó → una intención de enlace, que la ingesta cumple sola al llegar el aviso;
  12| --        · si no se puede unir (id mal formado, celular ajeno, otro lead, descartada, ya tenía otro resultado no
  13| --          deshecho) → el resultado se guarda IGUAL y la respuesta dice «no_enlazado» y por qué: la llamada queda en
  14| --          la pestaña para unirla a mano (decisión de Jhosep, 05/10).
  15| --      Sin la regla de los 10 minutos: en el camino exacto un reloj adelantado no rechaza nada (confirmación 3 de
  16| --      Miguel, Codex P2-5). Al registrar el resultado corregido tras Deshacer, el enlace (o la intención) pasa al
  17| --      corregido (confirmación 2). Una llamada ambigua no se une por este camino: va a la pestaña (Jhosep, 05/10).
  18| --   2. private.llamadas_celular_intenciones: la intención de enlace por id. Única por id y por resultado; caduca a los
  19| --      32 días (si el aviso nunca llega). Tabla técnica de private, sin auditoría (como las recepciones).
  20| --   3. crm.llamadas_celular_enlaces.via: al_colgar, pestana o manual. Sin ella no se mide «encuesta abierta al colgar»
  21| --      por celular, el objetivo de Jhosep. Inmutable.
  22| --   4. La ingesta (cuerpo de 20261005143843 con dos cambios): bloquea el lead FOR SHARE antes de guardar la llamada (el
  23| --      orden lead → llamada → enlace de la v5) y, guardada, cumple la intención si la hay.
  24| --   5. La purga (cuerpo de 20261005143843 con un cambio): retira las intenciones de más de 32 días.
  25| --
  26| -- Candados: v5 = lead (núcleo de v4, FOR UPDATE) → llamada → enlace o intención; ingesta = lead FOR SHARE → llamada →
  27| -- intención → enlace. Los dos empiezan por el lead: un aviso que llega mientras se guarda la encuesta espera, y la
  28| -- encuesta que llega mientras se guarda el aviso también; ninguno pierde el enlace. La ingesta lee el resultado sin
  29| -- candado: Deshacer toma resultado → lead, y bloquearlo después del lead invertiría ese orden.
  30| --
  31| -- Decisiones de criterio de Claude (05/10/2026), para Miguel:
  32| --   · La intención va en private, sin auditoría: es transitoria y no guarda datos personales (id, lead, resultado).
  33| --   · via nace con valor por defecto «manual»: el enlace manual (crm.enlazar_llamada_celular) no cambia; la v5 y la
  34| --     intención la fijan siempre.
  35| --   · La v5 exige que la etiqueta del id sea de un celular del analista que registra (vigente, o cerrado después de
  36| --     la llamada). Un supervisor que registra por el lead de su analista no enlaza: la llamada queda en la pestaña.
  37| --   · Si el aviso ya llegó y se ignoró (recepción sin llamada), no se guarda intención: nunca se cumpliría.
  38| --   · «Qué pasó hoy» (la lectura de lo ya resuelto, hallazgo 1 de F4) pasa a F4-b, con la pantalla.
  39| --
  40| -- Excepción single-tenant (estándar de 4 capas, F2.3.3): el CRM es de una sola empresa; no hay columna de tenant.
  41| -- Reversión: ../scripts/llamadas-celular/reversa-enlace-exacto.sql, SOLO antes del primer aviso (sin enlaces ni
  42| -- intenciones): vuelve exactamente al estado de las cinco. Verificación: npm run test:llamadas:local (oráculo
  43| -- tests/llamadas-celular/oraculo-enlace-exacto.sql, huella del catálogo, mutantes y carreras con dos sesiones).
  44| begin;
  45| set local lock_timeout = '5s';
  46| set local statement_timeout = '60s';
  47| 
  48| do $precondicion$
  49| begin
  50|   if to_regclass('private.llamadas_celular_intenciones') is not null
  51|      or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null then
  52|     raise exception 'LLAMADAS_ENLACE_EXACTO: los objetos ya existen; no se sobrescriben';
  53|   end if;
  54|   if to_regclass('private.llamadas_celular_recepciones') is null
  55|      or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is null
  56|      or to_regprocedure('private.llamada_celular_candidatos_dueno(uuid,text[],timestamptz)') is null then
  57|     raise exception 'LLAMADAS_ENLACE_EXACTO: falta la quinta migración (20261005143843)';
  58|   end if;
  59|   if to_regprocedure('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is null then
  60|     raise exception 'LLAMADAS_ENLACE_EXACTO: falta el núcleo de la encuesta v4 (20260921153654)';
  61|   end if;
  62|   -- La v5 compone la v4 SELLADA: si su gate existe (producción), tiene que pasar antes de instalar.
  63|   if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
  64|     perform private.assert_gestion_diaria_resultado_v4();
  65|   end if;
  66| end;
  67| $precondicion$;
  68| 
  69| lock table crm.llamadas_celular_eventos, crm.llamadas_celular_enlaces in access exclusive mode;
  70| 
  71| -- ── 1. Intenciones de enlace (private, sin auditoría, 32 días) ───────────────────────────────
  72| create table private.llamadas_celular_intenciones (
  73|   id               uuid primary key default gen_random_uuid(),
  74|   evento_origen_id text not null
  75|                    constraint llamadas_celular_intenciones_origen_valido
  76|                    check (evento_origen_id ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$')
  77|                    constraint llamadas_celular_intenciones_origen_uq unique,
  78|   analista_id      uuid not null references crm.equipo(perfil_id) on delete restrict,
  79|   lead_id          uuid not null references crm.leads(id) on delete cascade,
  80|   actividad_id     uuid not null references crm.actividades(id) on delete cascade
  81|                    constraint llamadas_celular_intenciones_actividad_uq unique,
  82|   via              text not null
  83|                    constraint llamadas_celular_intenciones_via_valida check (via in ('al_colgar', 'pestana')),
  84|   creado_en        timestamptz not null default now(),
  85|   actualizado_en   timestamptz not null default now()
  86| );
  87| alter table private.llamadas_celular_intenciones enable row level security;
  88| revoke all on private.llamadas_celular_intenciones from public, anon, authenticated, service_role;
  89| create index llamadas_celular_intenciones_analista_idx on private.llamadas_celular_intenciones (analista_id);
  90| create index llamadas_celular_intenciones_lead_idx on private.llamadas_celular_intenciones (lead_id);
  91| create index llamadas_celular_intenciones_creado_idx on private.llamadas_celular_intenciones (creado_en);
  92| 
  93| create function private.trg_llamadas_celular_intenciones_candado()
  94| returns trigger
  95| language plpgsql
  96| security definer
  97| set search_path to ''
  98| as $function$
  99| declare
 100|   v_deshecha boolean;
 101| begin
 102|   if tg_op = 'DELETE' then
 103|     -- La cumple la ingesta (GUC de enlace), la retira la purga (su GUC) o se va con su lead o su resultado (cascada).
 104|     if coalesce(pg_catalog.current_setting('crm.op_enlace_llamadas', true), 'off') = 'on'
 105|        or coalesce(pg_catalog.current_setting('crm.op_purga_llamadas', true), 'off') = 'on'
 106|        or pg_catalog.pg_trigger_depth() > 1 then
 107|       return old;
 108|     end if;
 109|     raise exception using errcode = '42501', message = 'Una intención de enlace no se borra a mano';
 110|   end if;
 111|   if new.id <> old.id or new.evento_origen_id <> old.evento_origen_id or new.analista_id <> old.analista_id
 112|      or new.lead_id <> old.lead_id or new.via <> old.via or new.creado_en <> old.creado_en then
 113|     raise exception using errcode = '42501',
 114|       message = 'De una intención de enlace solo cambia el resultado, cuando el anterior se deshizo';
 115|   end if;
 116|   if new.actividad_id <> old.actividad_id then
 117|     select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = old.actividad_id;
 118|     if not coalesce(v_deshecha, false) then
 119|       raise exception using errcode = '42501',
 120|         message = 'La intención solo pasa a otro resultado si el anterior se deshizo';
 121|     end if;
 122|   end if;
 123|   new.actualizado_en := pg_catalog.now();
 124|   return new;
 125| end;
 126| $function$;
 127| create trigger trg_llamadas_celular_intenciones_00_candado
 128|   before update or delete on private.llamadas_celular_intenciones
 129|   for each row execute function private.trg_llamadas_celular_intenciones_candado();
 130| create trigger trg_llamadas_celular_intenciones_00_sin_vaciar
 131|   before truncate on private.llamadas_celular_intenciones
 132|   for each statement execute function private.trg_llamadas_celular_sin_vaciar();
 133| 
 134| -- ── 2. Vía del enlace (inmutable) ────────────────────────────────────────────────────────────
 135| alter table crm.llamadas_celular_enlaces
 136|   add column via text not null default 'manual'
 137|     constraint llamadas_celular_enlaces_via_valida check (via in ('al_colgar', 'pestana', 'manual'));
 138| 
 139| -- Candado de los enlaces: el cuerpo de 20261001145242 con un cambio (la vía no cambia).
 140| create or replace function private.trg_llamadas_celular_enlaces_candado()
 141| returns trigger
 142| language plpgsql
 143| security definer
 144| set search_path to ''
 145| as $function$
 146| declare
 147|   v_act crm.actividades%rowtype;
 148|   v_ev  crm.llamadas_celular_eventos%rowtype;
 149|   v_deshecha boolean;
 150| begin
 151|   if tg_op = 'DELETE' then
 152|     if pg_catalog.pg_trigger_depth() > 1 then
 153|       return old; -- cascada: se fue el evento o el lead
 154|     end if;
 155|     raise exception using errcode = '42501', message = 'El enlace de una llamada no se borra';
 156|   end if;
 157| 
 158|   if tg_op = 'UPDATE' then
 159|     -- La actividad se eliminó (cascada del lead → ON DELETE SET NULL): única escritura anidada
 160|     -- aceptada, y solo si no cambia nada más.
 161|     if pg_catalog.pg_trigger_depth() > 1 and new.actividad_id is null and old.actividad_id is not null
 162|        and (pg_catalog.to_jsonb(new) - 'actividad_id' - 'actualizado_en')
 163|          = (pg_catalog.to_jsonb(old) - 'actividad_id' - 'actualizado_en') then
 164|       new.actualizado_en := pg_catalog.now();
 165|       return new;
 166|     end if;
 167|     if new.id <> old.id or new.evento_id <> old.evento_id or new.lead_id <> old.lead_id
 168|        or new.creado_en <> old.creado_en or new.via <> old.via then
 169|       raise exception using errcode = '42501', message = 'El enlace de una llamada no cambia de evento, de lead ni de vía';
 170|     end if;
 171|     if new.actividad_id is distinct from old.actividad_id then
 172|       if new.actividad_id is null then
 173|         raise exception using errcode = '42501', message = 'Un enlace no se desenlaza: el resultado deshecho se marca, no se borra';
 174|       end if;
 175|       if old.actividad_id is not null then
 176|         select (a.metadata ? 'deshecho_en') into v_deshecha
 177|         from crm.actividades a where a.id = old.actividad_id;
 178|         if not coalesce(v_deshecha, false) then
 179|           raise exception using errcode = '42501',
 180|             message = 'El enlace solo cambia de actividad si el resultado anterior fue deshecho';
 181|         end if;
 182|       end if;
 183|     end if;
 184|   elsif new.actividad_id is null then
 185|     raise exception using errcode = '22023', message = 'Un enlace nace con la actividad registrada';
 186|   end if;
 187| 
 188|   if new.actividad_id is not null and (tg_op = 'INSERT' or new.actividad_id is distinct from old.actividad_id) then
 189|     select * into v_act from crm.actividades a where a.id = new.actividad_id;
 190|     if not found then
 191|       raise exception using errcode = '22023', message = 'La actividad enlazada no existe';
 192|     end if;
 193|     if v_act.lead_id <> new.lead_id then
 194|       raise exception using errcode = '22023', message = 'La actividad enlazada es de otro lead';
 195|     end if;
 196|     if v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 197|        or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 198|       raise exception using errcode = '22023',
 199|         message = 'Solo se enlaza un resultado de llamada registrado por la encuesta';
 200|     end if;
 201|   end if;
 202| 
 203|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = new.evento_id;
 204|   if not found then
 205|     raise exception using errcode = '22023', message = 'La llamada enlazada no existe';
 206|   end if;
 207|   if v_ev.lead_id is distinct from new.lead_id then
 208|     raise exception using errcode = '22023', message = 'El enlace debe apuntar al lead de la llamada';
 209|   end if;
 210| 
 211|   if tg_op = 'UPDATE' then
 212|     new.actualizado_en := pg_catalog.now();
 213|   end if;
 214|   return new;
 215| end;
 216| $function$;
 217| 
 218| -- ── 3. Núcleo del enlace exacto (INVOKER, sin EXECUTE para nadie) ────────────────────────────
 219| 
 220| -- Une un resultado que la v5 acaba de registrar (o reconfirmar) con la llamada de ese id. Nunca lanza por un enlace
 221| -- imposible: devuelve {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}.
 222| create function private.llamada_celular_enlazar_exacto(
 223|   p_actor uuid, p_lead_id uuid, p_actividad_id uuid, p_origen text, p_via text, p_ahora timestamptz)
 224| returns jsonb
 225| language plpgsql
 226| volatile
 227| set search_path = ''
 228| as $function$
 229| declare
 230|   v_act crm.actividades%rowtype;
 231|   v_ev crm.llamadas_celular_eventos%rowtype;
 232|   v_enl crm.llamadas_celular_enlaces%rowtype;
 233|   v_int private.llamadas_celular_intenciones%rowtype;
 234|   v_hora timestamptz;
 235|   v_deshecha boolean;
 236|   v_restriccion text;
 237|   v_estado text;
 238| begin
 239|   -- 1. El id: forma fija, dentro de la ventana de la ingesta y de un celular del analista que registra.
 240|   if p_origen is null or p_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
 241|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
 242|   end if;
 243|   v_hora := pg_catalog.to_timestamp(pg_catalog.split_part(p_origen, '-', 2)::bigint);
 244|   if v_hora < p_ahora - interval '30 days' or v_hora > p_ahora + interval '1 day' then
 245|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'id_invalido');
 246|   end if;
 247|   if not exists (select 1 from crm.celulares_asignaciones a
 248|                  where a.etiqueta = pg_catalog.split_part(p_origen, '-', 1) and a.analista_id = p_actor
 249|                    and (a.vigente_hasta is null or a.vigente_hasta >= v_hora)) then
 250|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
 251|   end if;
 252| 
 253|   -- 2. El resultado: lo creó o reconfirmó la v4 en esta transacción, con el lead ya bloqueado.
 254|   select * into v_act from crm.actividades a where a.id = p_actividad_id;
 255|   if not found or v_act.lead_id <> p_lead_id or v_act.tipo not in ('llamada_realizada', 'llamada_no_contestada')
 256|      or coalesce(v_act.metadata ->> 'evento', '') <> 'resultado_llamada' then
 257|     raise exception using errcode = '23514', message = 'El servidor no confirmó el resultado de la llamada';
 258|   end if;
 259|   if v_act.metadata ? 'deshecho_en' then
 260|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_deshecho');
 261|   end if;
 262| 
 263|   -- 3. ¿La llamada ya llegó? Candado: lead (v4) → llamada → enlace.
 264|   select * into v_ev from crm.llamadas_celular_eventos e where e.evento_origen_id = p_origen for update;
 265|   if found then
 266|     if v_ev.analista_id <> p_actor then
 267|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'celular_ajeno');
 268|     end if;
 269|     if v_ev.atencion = 'descartado_con_motivo' then
 270|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'descartada');
 271|     end if;
 272|     if v_ev.identificacion <> 'identificado' or v_ev.lead_id is distinct from p_lead_id then
 273|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
 274|     end if;
 275|     select * into v_enl from crm.llamadas_celular_enlaces l where l.evento_id = v_ev.id for update;
 276|     if found then
 277|       if v_enl.actividad_id = p_actividad_id then
 278|         return pg_catalog.jsonb_build_object('estado', 'repetido');
 279|       end if;
 280|       select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_enl.actividad_id;
 281|       if v_enl.actividad_id is not null and not coalesce(v_deshecha, false) then
 282|         return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
 283|       end if;
 284|       begin
 285|         update crm.llamadas_celular_enlaces set actividad_id = p_actividad_id, enlazado_por = p_actor
 286|          where id = v_enl.id;
 287|       exception when unique_violation then
 288|         return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
 289|       end;
 290|       v_estado := 'movido';
 291|     else
 292|       begin
 293|         insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
 294|         values (v_ev.id, p_actividad_id, v_ev.lead_id, p_actor, p_via);
 295|       exception when unique_violation then
 296|         return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
 297|       end;
 298|       v_estado := 'enlazado';
 299|     end if;
 300|     -- La máquina de estados de la tabla exige pasar por «requiere resultado».
 301|     if v_ev.atencion = 'por_revisar' then
 302|       update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
 303|     end if;
 304|     if v_ev.atencion <> 'registrado' then
 305|       update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
 306|     end if;
 307|     return pg_catalog.jsonb_build_object('estado', v_estado);
 308|   end if;
 309| 
 310|   -- 4. Todavía no llegó. Si el aviso llegó y se ignoró, no se guarda nada: nunca se cumpliría.
 311|   if exists (select 1 from private.llamadas_celular_recepciones r where r.evento_origen_id = p_origen) then
 312|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'sin_llamada');
 313|   end if;
 314|   if exists (select 1 from crm.llamadas_celular_enlaces l where l.actividad_id = p_actividad_id) then
 315|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
 316|   end if;
 317|   select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = p_origen for update;
 318|   if found then
 319|     if v_int.actividad_id = p_actividad_id then
 320|       return pg_catalog.jsonb_build_object('estado', 'pendiente');
 321|     end if;
 322|     if v_int.analista_id <> p_actor or v_int.lead_id <> p_lead_id then
 323|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'otro_lead');
 324|     end if;
 325|     select (a.metadata ? 'deshecho_en') into v_deshecha from crm.actividades a where a.id = v_int.actividad_id;
 326|     if not coalesce(v_deshecha, false) then
 327|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'ya_tiene_resultado');
 328|     end if;
 329|     begin
 330|       update private.llamadas_celular_intenciones set actividad_id = p_actividad_id where id = v_int.id;
 331|     exception when unique_violation then
 332|       return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo', 'resultado_ya_enlazado');
 333|     end;
 334|     return pg_catalog.jsonb_build_object('estado', 'pendiente');
 335|   end if;
 336|   begin
 337|     insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via)
 338|     values (p_origen, p_actor, p_lead_id, p_actividad_id, p_via);
 339|   exception when unique_violation then
 340|     get stacked diagnostics v_restriccion = constraint_name;
 341|     return pg_catalog.jsonb_build_object('estado', 'no_enlazado', 'motivo',
 342|       case when v_restriccion = 'llamadas_celular_intenciones_origen_uq' then 'ya_tiene_resultado'
 343|            else 'resultado_ya_enlazado' end);
 344|   end;
 345|   return pg_catalog.jsonb_build_object('estado', 'pendiente');
 346| end;
 347| $function$;
 348| 
 349| -- La ingesta, guardada la llamada, cumple la intención de su id. La intención se retira se cumpla o no: si no
 350| -- coincide (otro analista, otro lead, resultado deshecho o ya unido a otra llamada), la llamada queda pendiente.
 351| create function private.llamada_celular_cumplir_intencion(p_evento_id uuid)
 352| returns void
 353| language plpgsql
 354| volatile
 355| set search_path = ''
 356| as $function$
 357| declare
 358|   v_ev crm.llamadas_celular_eventos%rowtype;
 359|   v_int private.llamadas_celular_intenciones%rowtype;
 360|   v_act crm.actividades%rowtype;
 361| begin
 362|   select * into v_ev from crm.llamadas_celular_eventos e where e.id = p_evento_id for update;
 363|   if not found then
 364|     return;
 365|   end if;
 366|   select * into v_int from private.llamadas_celular_intenciones i where i.evento_origen_id = v_ev.evento_origen_id for update;
 367|   if not found then
 368|     return;
 369|   end if;
 370|   perform pg_catalog.set_config('crm.op_enlace_llamadas', 'on', true);
 371|   delete from private.llamadas_celular_intenciones where id = v_int.id;
 372|   perform pg_catalog.set_config('crm.op_enlace_llamadas', 'off', true);
 373|   if v_int.analista_id <> v_ev.analista_id or v_ev.identificacion <> 'identificado'
 374|      or v_ev.lead_id is distinct from v_int.lead_id then
 375|     return;
 376|   end if;
 377|   -- Sin candado sobre el resultado: Deshacer lo toma ANTES que el lead, y aquí el lead ya está bloqueado.
 378|   select * into v_act from crm.actividades a where a.id = v_int.actividad_id;
 379|   if not found or v_act.metadata ? 'deshecho_en' then
 380|     return;
 381|   end if;
 382|   begin
 383|     insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por, via)
 384|     values (v_ev.id, v_int.actividad_id, v_ev.lead_id, v_int.analista_id, v_int.via);
 385|   exception when unique_violation then
 386|     return;  -- ese resultado ya quedó unido a otra llamada
 387|   end;
 388|   if v_ev.atencion = 'por_revisar' then
 389|     update crm.llamadas_celular_eventos set atencion = 'requiere_resultado' where id = v_ev.id;
 390|   end if;
 391|   update crm.llamadas_celular_eventos set atencion = 'registrado' where id = v_ev.id;
 392| end;
 393| $function$;
 394| 
 395| -- La ingesta: el cuerpo de 20261005143843 con dos cambios (candado del lead antes de guardar; cumplir la intención).
 396| create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
 397| returns jsonb
 398| language plpgsql
 399| volatile
 400| set search_path = ''
 401| as $function$
 402| declare
 403|   v_claves constant text[] := array['v', 'evento_origen_id', 'numero', 'direccion', 'estado_tecnico',
 404|                                     'duracion_seg', 'ocurrio_en'];
 405|   v_asig crm.celulares_asignaciones%rowtype;
 406|   v_pol crm.llamadas_celular_politica%rowtype;
 407|   v_origen text;
 408|   v_numero text;
 409|   v_dir text;
 410|   v_estado text;
 411|   v_dur integer;
 412|   v_ocurrio timestamptz;
 413|   v_hora_id timestamptz;
 414|   v_recepcion uuid;
 415|   v_formas text[];
 416|   v_e164 text;
 417|   v_cand uuid[];
 418|   v_lead uuid;
 419|   v_ident text;
 420|   v_aten text;
 421|   v_metodo text;
 422|   v_calidad jsonb := '{}'::jsonb;
 423|   v_aceptado constant jsonb := '{"resultado": "aceptado"}'::jsonb;
 424|   v_evento uuid;
 425| begin
 426|   -- La puerta ya bloqueó la asignación FOR SHARE y la revalidó; aquí se relee bajo el mismo candado.
 427|   select * into v_asig from crm.celulares_asignaciones a where a.id = p_asignacion_id for share;
 428|   if not found or v_asig.vigente_hasta is not null
 429|      or coalesce(private.rol_crm(v_asig.analista_id), '') not in ('vendedor', 'supervisor') then
 430|     raise exception using errcode = '42501', message = 'Celular sin asignación vigente o analista inactivo';
 431|   end if;
 432| 
 433|   -- Validación: todo inválido responde «invalido» y el cupo ya gastado queda (menor 11, Codex P3). El bloque
 434|   -- atrapa SOLO 22023: un error inesperado sigue siendo un error (503, que revierte todo, el cupo incluido).
 435|   begin
 436|     if p_evento is null or pg_catalog.jsonb_typeof(p_evento) <> 'object' then
 437|       raise exception using errcode = '22023', message = 'El evento debe ser un objeto JSON';
 438|     end if;
 439|     if exists (select 1 from pg_catalog.jsonb_object_keys(p_evento) k where k <> all(v_claves)) then
 440|       raise exception using errcode = '22023', message = 'El evento trae claves no previstas';
 441|     end if;
 442|     if coalesce(p_evento ->> 'v', '') <> '1' then
 443|       raise exception using errcode = '22023', message = 'Versión de evento no soportada (se espera v = 1)';
 444|     end if;
 445|     v_origen := p_evento ->> 'evento_origen_id';
 446|     if v_origen is null or v_origen !~ '^C[1-9][0-9]{0,2}-[0-9]{10}$' then
 447|       raise exception using errcode = '22023',
 448|         message = 'evento_origen_id inválido: se espera la etiqueta del celular y los segundos de su reloj (p. ej. C1-1790980958)';
 449|     end if;
 450|     if pg_catalog.split_part(v_origen, '-', 1) <> v_asig.etiqueta then
 451|       raise exception using errcode = '22023',
 452|         message = pg_catalog.format('evento_origen_id con la etiqueta de otro celular (esta clave es de %s)', v_asig.etiqueta);
 453|     end if;
 454|     v_hora_id := pg_catalog.to_timestamp(pg_catalog.split_part(v_origen, '-', 2)::bigint);
 455|     if v_hora_id < p_ahora - interval '30 days' or v_hora_id > p_ahora + interval '1 day' then
 456|       raise exception using errcode = '22023',
 457|         message = 'evento_origen_id fuera de la ventana: su hora debe caer entre hace 30 días y mañana (¿hora automática en el celular?)';
 458|     end if;
 459|     v_numero := nullif(pg_catalog.btrim(coalesce(p_evento ->> 'numero', '')), '');
 460|     if pg_catalog.length(v_numero) > 40 then
 461|       raise exception using errcode = '22023', message = 'El número no puede pasar de 40 caracteres';
 462|     end if;
 463|     v_dir := coalesce(p_evento ->> 'direccion', 'desconocida');
 464|     if v_dir not in ('saliente', 'entrante', 'desconocida') then
 465|       raise exception using errcode = '22023', message = 'direccion inválida (saliente, entrante o desconocida)';
 466|     end if;
 467|     v_estado := coalesce(p_evento ->> 'estado_tecnico', 'desconocido');
 468|     if v_estado not in ('conectada', 'no_atendida', 'rechazada', 'cancelada', 'desconocido') then
 469|       raise exception using errcode = '22023', message = 'estado_tecnico inválido';
 470|     end if;
 471|     if coalesce(pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg'), 'null') <> 'null' then
 472|       if pg_catalog.jsonb_typeof(p_evento -> 'duracion_seg') <> 'number'
 473|          or (p_evento ->> 'duracion_seg') !~ '^[0-9]{1,5}$' or (p_evento ->> 'duracion_seg')::integer > 86400 then
 474|         raise exception using errcode = '22023', message = 'duracion_seg debe ser un entero de 0 a 86400';
 475|       end if;
 476|       v_dur := (p_evento ->> 'duracion_seg')::integer;
 477|     end if;
 478|     v_ocurrio := private.llamada_celular_fecha(p_evento ->> 'ocurrio_en');
 479|   exception when sqlstate '22023' then
 480|     return pg_catalog.jsonb_build_object('resultado', 'invalido', 'mensaje', sqlerrm);
 481|   end;
 482| 
 483|   -- Recepción ANTES de mirar leads, también si después se ignora (fallo 1). El primer envío gana: un reenvío
 484|   -- del mismo id responde lo mismo sin buscar nada. Si guardar la llamada fallara, la recepción se revierte con
 485|   -- ella: nada lo atrapa (Codex P1).
 486|   insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en)
 487|   values (v_origen, v_asig.id, p_ahora)
 488|   on conflict (evento_origen_id) do nothing
 489|   returning id into v_recepcion;
 490|   if v_recepcion is null then
 491|     return v_aceptado;
 492|   end if;
 493| 
 494|   -- Solo salientes (decisión 2): la entrante y la dirección desconocida se ignoran (Codex P6).
 495|   if v_dir <> 'saliente' then
 496|     return v_aceptado;
 497|   end if;
 498| 
 499|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 500|   if v_ocurrio is not null and v_ocurrio > p_ahora + interval '5 minutes' then
 501|     v_calidad := v_calidad || '{"reloj": "adelantado"}'::jsonb;
 502|   end if;
 503|   v_formas := private.llamada_celular_formas(v_numero);
 504|   v_e164 := (select c.e164 from private.canonizar_contacto(v_numero) c limit 1);
 505|   if v_e164 is null and v_numero is not null then
 506|     v_calidad := v_calidad || '{"numero": "no_canonizable"}'::jsonb;
 507|   elsif v_numero is null then
 508|     v_calidad := v_calidad || '{"numero": "oculto"}'::jsonb;
 509|   end if;
 510|   v_cand := private.llamada_celular_candidatos_dueno(v_asig.analista_id, v_formas, p_ahora);
 511| 
 512|   if pg_catalog.cardinality(v_cand) = 1 then
 513|     v_lead := v_cand[1];
 514|     v_ident := 'identificado';
 515|     v_metodo := 'exacto';
 516|     -- Solo un lead del ámbito del dueño puede ser elegible; los de la bolsa y los reutilizables quedan por revisar.
 517|     v_aten := case when private.llamada_celular_elegible_dueno(v_asig.analista_id, v_lead)
 518|                    then 'requiere_resultado' else 'por_revisar' end;
 519|   elsif pg_catalog.cardinality(v_cand) > 1 then
 520|     -- Ambigua, sin guardar cuántos (fallo 4).
 521|     v_ident := 'ambiguo';
 522|     v_aten := 'por_revisar';
 523|   elsif coalesce(v_pol.guardar_sin_identificar, false) then
 524|     v_ident := 'sin_identificar';
 525|     v_aten := 'por_revisar';
 526|   else
 527|     -- Decisión 3: sin candidato, la llamada no pertenece al CRM, aunque el número sea de un lead de otro analista.
 528|     return v_aceptado;
 529|   end if;
 530| 
 531|   -- F4-a: el lead se bloquea ANTES de guardar la llamada, el orden de la v5 (lead → llamada → enlace): un aviso que
 532|   -- llega mientras se guarda la encuesta de esa llamada espera y encuentra su intención.
 533|   if v_lead is not null then
 534|     perform 1 from crm.leads l where l.id = v_lead for share;
 535|   end if;
 536|   insert into crm.llamadas_celular_eventos
 537|     (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion, estado_tecnico, duracion_seg,
 538|      ocurrio_en, recibido_en, calidad, identificacion, atencion, lead_id, metodo_asociacion, asociado_en)
 539|   values
 540|     -- Sin forma E.164 se guarda la del trigger de leads (la que encontró el lead), para poder
 541|     -- volver a buscar candidatos al asociar.
 542|     (v_asig.id, v_asig.analista_id, v_origen, coalesce(v_e164, v_formas[1]), v_dir, v_estado, v_dur,
 543|      v_ocurrio, p_ahora, v_calidad, v_ident, v_aten, v_lead, v_metodo, case when v_lead is not null then p_ahora end)
 544|   returning id into v_evento;
 545|   -- F4-a: si la encuesta llegó antes, la llamada se une ya a su resultado.
 546|   perform private.llamada_celular_cumplir_intencion(v_evento);
 547|   return v_aceptado;
 548| end;
 549| $function$;
 550| 
 551| -- La purga: el cuerpo de 20261005143843 con un cambio (intenciones de más de 32 días).
 552| create or replace function private.caducar_llamadas_celular()
 553| returns integer
 554| language plpgsql
 555| security definer
 556| set search_path to ''
 557| as $function$
 558| declare
 559|   v_pol crm.llamadas_celular_politica%rowtype;
 560|   v_n integer := 0;
 561|   v_parcial integer;
 562| begin
 563|   select * into v_pol from crm.llamadas_celular_politica where singleton;
 564|   if not found then
 565|     return 0;
 566|   end if;
 567|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'on', true);
 568| 
 569|   -- Descartadas con motivo: su plazo, desde descartado_en. El motivo y quién lo dio quedan en la auditoría.
 570|   delete from crm.llamadas_celular_eventos e
 571|    where e.atencion = 'descartado_con_motivo'
 572|      and e.descartado_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_descartados);
 573|   get diagnostics v_parcial = row_count;
 574|   v_n := v_n + v_parcial;
 575| 
 576|   -- Sin resolver: identificadas sin enlace y ambiguas, desde recibido_en. La atención también se mira: si una
 577|   -- encuesta enlaza la llamada mientras la purga espera su candado, la fila vuelve con «registrado» y se queda.
 578|   delete from crm.llamadas_celular_eventos e
 579|    where e.identificacion in ('identificado', 'ambiguo')
 580|      and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 581|      and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
 582|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_resolver);
 583|   get diagnostics v_parcial = row_count;
 584|   v_n := v_n + v_parcial;
 585| 
 586|   -- Sin identificar (solo existen si la perilla guardar_sin_identificar estuvo encendida).
 587|   delete from crm.llamadas_celular_eventos e
 588|    where e.identificacion = 'sin_identificar'
 589|      and e.atencion in ('por_revisar', 'requiere_resultado', 'requiere_devolucion')
 590|      and not exists (select 1 from crm.llamadas_celular_enlaces l where l.evento_id = e.id)
 591|      and e.recibido_en < pg_catalog.now() - pg_catalog.make_interval(days => v_pol.dias_retencion_sin_identificar);
 592|   get diagnostics v_parcial = row_count;
 593|   v_n := v_n + v_parcial;
 594| 
 595|   -- Recepciones: 32 días (30 de ventana + 1 de tolerancia + 1 de margen). Pasado ese plazo, su id ya no entra
 596|   -- por la ventana, así que no queda un registro eterno de a qué hora llamaba el analista (Codex P9).
 597|   delete from private.llamadas_celular_recepciones r
 598|    where r.recibido_en < pg_catalog.now() - interval '32 days';
 599|   get diagnostics v_parcial = row_count;
 600|   v_n := v_n + v_parcial;
 601| 
 602|   -- F4-a: intenciones de enlace cuyo aviso nunca llegó (32 días, como las recepciones).
 603|   delete from private.llamadas_celular_intenciones i
 604|    where i.creado_en < pg_catalog.now() - interval '32 days';
 605|   get diagnostics v_parcial = row_count;
 606|   v_n := v_n + v_parcial;
 607| 
 608|   perform pg_catalog.set_config('crm.op_purga_llamadas', 'off', true);
 609|   return v_n;
 610| end;
 611| $function$;
 612| 
 613| -- ── 4. Puerta v5 (DEFINER, EXECUTE solo authenticated) ───────────────────────────────────────
 614| create function crm.registrar_llamada_v5(
 615|   p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text default null, p_detalle text default null,
 616|   p_siguiente jsonb default null, p_tarea_id uuid default null, p_descartar boolean default false,
 617|   p_no_insista boolean default false, p_evento_origen_id text default null, p_via text default null)
 618| returns jsonb
 619| language plpgsql
 620| volatile
 621| security definer
 622| set search_path = ''
 623| as $function$
 624| declare
 625|   v_uid uuid := (select auth.uid());
 626|   v_rol text := private.rol_crm((select auth.uid()));
 627|   v_resp jsonb;
 628| begin
 629|   -- Mismos roles que la v4; el ámbito lo decide su núcleo.
 630|   if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
 631|     raise exception using errcode = '42501', message = 'No autorizado';
 632|   end if;
 633|   if p_operacion_id is null or p_lead_id is null or p_resultado is null then
 634|     raise exception using errcode = '22023', message = 'Operacion, lead y resultado son obligatorios';
 635|   end if;
 636|   if p_evento_origen_id is not null and (p_via is null or p_via not in ('al_colgar', 'pestana')) then
 637|     raise exception using errcode = '22023', message = 'Con el id de la llamada, la vía es al_colgar o pestana';
 638|   end if;
 639|   v_resp := private.llamada_registrar_v4(
 640|     v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
 641|     nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
 642|     p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
 643|   if p_evento_origen_id is null then
 644|     return v_resp || pg_catalog.jsonb_build_object('enlace', null);
 645|   end if;
 646|   return v_resp || pg_catalog.jsonb_build_object('enlace', private.llamada_celular_enlazar_exacto(
 647|     v_uid, p_lead_id, (v_resp ->> 'actividad_id')::uuid, p_evento_origen_id, p_via, pg_catalog.clock_timestamp()));
 648| end;
 649| $function$;
 650| 
 651| -- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
 652| do $permisos$
 653| declare
 654|   v_f text;
 655| begin
 656|   foreach v_f in array array[
 657|     'private.trg_llamadas_celular_intenciones_candado()',
 658|     'private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)',
 659|     'private.llamada_celular_cumplir_intencion(uuid)'] loop
 660|     execute pg_catalog.format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
 661|   end loop;
 662|   revoke all on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
 663|     from public, anon, authenticated, service_role;
 664|   grant execute on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)
 665|     to authenticated;
 666| end;
 667| $permisos$;
 668| 
 669| -- ── 6. Comentarios ───────────────────────────────────────────────────────────────────────────
 670| comment on table private.llamadas_celular_intenciones is
 671|   'Intención de enlace (F4-a): la encuesta se guardó con el id de su llamada ANTES de que llegara el aviso del celular. La ingesta la cumple al llegar el aviso (crea el enlace con su vía) y la retira, se cumpla o no. Única por id y por resultado; caduca a los 32 días (la purga diaria) si el aviso nunca llega. Tabla técnica de private, sin acceso para la API y sin auditoría: transitoria, sin número ni datos personales. Sin columna de tenant: CRM de una sola empresa.';
 672| comment on column private.llamadas_celular_intenciones.id is 'Identificador de la intención.';
 673| comment on column private.llamadas_celular_intenciones.evento_origen_id is 'Id de la llamada que llegó en la URL de la encuesta: C<n>-<segundos del reloj del celular>. Único.';
 674| comment on column private.llamadas_celular_intenciones.analista_id is 'Quién registró el resultado: tiene que ser el analista del celular de la llamada para cumplirse. FK con RESTRICT.';
 675| comment on column private.llamadas_celular_intenciones.lead_id is 'Lead del resultado: la llamada tiene que quedar identificada con este lead para cumplirse. Se va con el lead.';
 676| comment on column private.llamadas_celular_intenciones.actividad_id is 'Resultado registrado por la encuesta (único). Cambia solo si se deshizo y se registró el corregido. Se va con la actividad.';
 677| comment on column private.llamadas_celular_intenciones.via is 'Por dónde se abrió la encuesta: al_colgar (la URL de la macro) o pestana (la pestaña «Llamadas del celular»). Pasa al enlace.';
 678| comment on column private.llamadas_celular_intenciones.creado_en is 'Cuándo se guardó la encuesta. De aquí corren los 32 días.';
 679| comment on column private.llamadas_celular_intenciones.actualizado_en is 'Último cambio (solo al pasar al resultado corregido; lo sella el trigger).';
 680| comment on column crm.llamadas_celular_enlaces.via is 'Por dónde se hizo el enlace: al_colgar (encuesta abierta por la URL de la macro), pestana (desde «Llamadas del celular») o manual (crm.enlazar_llamada_celular). Mide «encuesta abierta al colgar» por celular. Inmutable.';
 681| comment on function private.trg_llamadas_celular_intenciones_candado() is
 682|   'Candado de private.llamadas_celular_intenciones: solo cambia el resultado, y solo si el anterior se deshizo; DELETE solo al cumplirse (GUC crm.op_enlace_llamadas), en la purga (GUC crm.op_purga_llamadas) o en cascada. SECURITY DEFINER por coherencia con los demás candados; lee la actividad anterior.';
 683| comment on function private.trg_llamadas_celular_enlaces_candado() is
 684|   'Candado de crm.llamadas_celular_enlaces: nace con actividad; la actividad es de llamada, con metadata.evento = resultado_llamada y del mismo lead que la llamada; el enlace cambia de actividad solo si la anterior fue deshecha (metadata.deshecho_en); la vía no cambia (20261005155914); sin DELETE salvo cascada. SECURITY DEFINER porque lee crm.actividades y crm.llamadas_celular_eventos sin privilegios para la API.';
 685| comment on function private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz) is
 686|   'Enlace EXACTO (F4-a) de un resultado recién registrado por la v5 con la llamada de su id: id con forma y ventana de un celular del analista; llamada ya llegada, del mismo analista, identificada con ese lead → enlace (o lo mueve si el anterior se deshizo); no llegada → intención de enlace (o la mueve); sin la regla de los 10 minutos. Nunca lanza por un enlace imposible: {estado: enlazado | movido | repetido | pendiente | no_enlazado, motivo}. Candados: lead (ya bloqueado por la v4) → llamada → enlace o intención.';
 687| comment on function private.llamada_celular_cumplir_intencion(uuid) is
 688|   'La ingesta, guardada una llamada, cumple la intención de su id: la retira y, si coincide (mismo analista, llamada identificada con ese lead, resultado vigente y sin otra llamada), crea el enlace con su vía y deja la llamada en «registrado». Lee el resultado sin candado (Deshacer toma resultado → lead).';
 689| comment on function private.llamada_celular_ingerir(uuid,jsonb,timestamptz) is
 690|   'Núcleo de la ingesta (lo llama crm.ingerir_llamada_celular_servicio tras la clave y el cupo, con la hora de la puerta): valida el evento v1 en un bloque que atrapa SOLO 22023 (inválido → {resultado: invalido, mensaje}); id C<n>-<segundos> con la etiqueta de la asignación y dentro de la ventana (30 días atrás, 1 adelante); registra la recepción antes de mirar leads (repetido → aceptado sin buscar nada); solo salientes; candidatos del dueño (uno → identificada, pide resultado si es elegible como el dueño; varios → ambigua sin conteo; ninguno → no se guarda salvo guardar_sin_identificar). Recepción y llamada confirman juntas. Siempre {resultado: aceptado} si es válido. DATO PERSONAL: el número. Desde 20261005155914 bloquea el lead antes de guardar la llamada y cumple la intención de enlace de su id (F4-a).';
 691| comment on function private.caducar_llamadas_celular() is
 692|   'Retención de llamadas del celular (decisión 4 de Miguel, 03/10): descartadas por su plazo desde descartado_en; identificadas sin enlace y ambiguas a dias_retencion_sin_resolver desde recibido_en; sin identificar a dias_retencion_sin_identificar; las registradas (con enlace, aunque su resultado se haya deshecho) se conservan; recepciones a los 32 días. Devuelve cuántas filas retiró (llamadas y recepciones). Fija el GUC crm.op_purga_llamadas para pasar los candados. La invoca pg_cron (crm-llamadas-celular-caducidad). SECURITY DEFINER: borra sin privilegios de la API. Desde 20261005155914 retira también las intenciones de enlace de más de 32 días.';
 693| comment on function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text) is
 694|   'PUERTA v5 (F4-a): la operación de la v4 (su núcleo sellado private.llamada_registrar_v4: rol, ámbito, candado del lead, resultado, agenda y recibo) y, en la misma transacción, el enlace exacto con la llamada de p_evento_origen_id (vía al_colgar o pestana). Sin id, igual que la v4 con enlace null. Un enlace imposible no impide guardar el resultado: devuelve enlace.estado = no_enlazado con su motivo. DEFINER para componer el núcleo privado, no para ampliar el ámbito.';
 695| 
 696| -- ── 7. Postflight ────────────────────────────────────────────────────────────────────────────
 697| do $postflight$
 698| declare
 699|   v_f record;
 700|   v_t text := 'private.llamadas_celular_intenciones';
 701| begin
 702|   if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = v_t::regclass) then
 703|     raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin RLS', v_t;
 704|   end if;
 705|   if exists (select 1 from (values ('anon'), ('authenticated'), ('service_role')) r(rol)
 706|              where pg_catalog.has_table_privilege(r.rol, v_t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) then
 707|     raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó accesible desde la API', v_t;
 708|   end if;
 709|   if exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_t::regclass) then
 710|     raise exception 'LLAMADAS_ENLACE_EXACTO: % no debe tener policies (todo va por puertas)', v_t;
 711|   end if;
 712|   if (select count(*) from pg_catalog.pg_trigger t
 713|       where t.tgrelid = v_t::regclass and not t.tgisinternal and t.tgenabled in ('O', 'A')
 714|         and t.tgname in ('trg_llamadas_celular_intenciones_00_candado', 'trg_llamadas_celular_intenciones_00_sin_vaciar')) <> 2 then
 715|     raise exception 'LLAMADAS_ENLACE_EXACTO: % quedó sin sus candados', v_t;
 716|   end if;
 717|   if exists (select 1 from pg_catalog.pg_constraint c
 718|              where c.contype = 'f' and c.conrelid = v_t::regclass
 719|                and c.confrelid in ('public.perfiles'::regclass, 'crm.equipo'::regclass) and c.confdeltype <> 'r') then
 720|     raise exception 'LLAMADAS_ENLACE_EXACTO: una FK hacia personas de % no es RESTRICT', v_t;
 721|   end if;
 722|   if exists (select 1 from pg_catalog.pg_constraint c
 723|              where c.contype = 'f' and c.conrelid = v_t::regclass
 724|                and not exists (select 1 from pg_catalog.pg_index i
 725|                                where i.indrelid = c.conrelid
 726|                                  and (pg_catalog.string_to_array(i.indkey::text, ' ')::smallint[])[1:pg_catalog.array_length(c.conkey, 1)]
 727|                                      = c.conkey)) then
 728|     raise exception 'LLAMADAS_ENLACE_EXACTO: hay una FK de % sin índice que la cubra', v_t;
 729|   end if;
 730|   if pg_catalog.obj_description(v_t::regclass, 'pg_class') is null
 731|      or exists (select 1 from pg_catalog.pg_attribute a
 732|                 where a.attnum > 0 and not a.attisdropped and pg_catalog.col_description(a.attrelid, a.attnum) is null
 733|                   and (a.attrelid = v_t::regclass
 734|                        or (a.attrelid = 'crm.llamadas_celular_enlaces'::regclass and a.attname = 'via'))) then
 735|     raise exception 'LLAMADAS_ENLACE_EXACTO: falta COMMENT en las intenciones o en la vía del enlace';
 736|   end if;
 737|   if (select count(*) from pg_catalog.pg_trigger t
 738|       where t.tgrelid = 'crm.llamadas_celular_enlaces'::regclass and not t.tgisinternal) <> 3
 739|      or exists (select 1 from private.tablas_sin_rastro() s where s.tabla = 'crm.llamadas_celular_enlaces') then
 740|     raise exception 'LLAMADAS_ENLACE_EXACTO: los enlaces perdieron un trigger o su rastro de auditoría';
 741|   end if;
 742| 
 743|   for v_f in
 744|     select * from (values
 745|       ('private.trg_llamadas_celular_intenciones_candado()', true, null),
 746|       ('private.trg_llamadas_celular_enlaces_candado()', true, null),
 747|       ('private.caducar_llamadas_celular()', true, null),
 748|       ('private.llamada_celular_enlazar_exacto(uuid,uuid,uuid,text,text,timestamptz)', false, null),
 749|       ('private.llamada_celular_cumplir_intencion(uuid)', false, null),
 750|       ('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)', false, null),
 751|       ('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', true, 'authenticated')
 752|     ) as f(firma, definer, rol)
 753|   loop
 754|     if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure) is distinct from v_f.definer then
 755|       raise exception 'LLAMADAS_ENLACE_EXACTO: % debería ser %', v_f.firma,
 756|         case when v_f.definer then 'SECURITY DEFINER' else 'SECURITY INVOKER' end;
 757|     end if;
 758|     if exists (
 759|       select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
 760|       where p.oid = v_f.firma::regprocedure and a.privilege_type = 'EXECUTE'
 761|         and a.grantee <> p.proowner
 762|         and (v_f.rol is null or a.grantee <> v_f.rol::regrole::oid)
 763|     ) or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = v_f.firma::regprocedure)
 764|       or (v_f.rol is not null and not pg_catalog.has_function_privilege(v_f.rol, v_f.firma, 'EXECUTE')) then
 765|       raise exception 'LLAMADAS_ENLACE_EXACTO: EXECUTE inesperado en %', v_f.firma;
 766|     end if;
 767|     if not exists (select 1 from pg_catalog.pg_proc p
 768|                    where p.oid = v_f.firma::regprocedure and p.proconfig @> array['search_path=""']) then
 769|       raise exception 'LLAMADAS_ENLACE_EXACTO: search_path inesperado en %', v_f.firma;
 770|     end if;
 771|     if pg_catalog.obj_description(v_f.firma::regprocedure, 'pg_proc') is null then
 772|       raise exception 'LLAMADAS_ENLACE_EXACTO: % sin COMMENT', v_f.firma;
 773|     end if;
 774|     if pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(v_f.firma::regprocedure)), 'when others') > 0 then
 775|       raise exception 'LLAMADAS_ENLACE_EXACTO: % atrapa cualquier error (WHEN OTHERS)', v_f.firma;
 776|     end if;
 777|   end loop;
 778|   if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)'::regprocedure),
 779|                        'private.llamada_celular_cumplir_intencion(') = 0 then
 780|     raise exception 'LLAMADAS_ENLACE_EXACTO: la ingesta no cumple las intenciones de enlace';
 781|   end if;
 782|   if pg_catalog.strpos(pg_catalog.pg_get_functiondef('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)'::regprocedure),
 783|                        'private.llamada_registrar_v4(') = 0 then
 784|     raise exception 'LLAMADAS_ENLACE_EXACTO: la v5 no compone el núcleo sellado de la v4';
 785|   end if;
 786|   -- La v4 sigue sellada (si su gate existe): la v5 no la tocó.
 787|   if to_regprocedure('private.assert_gestion_diaria_resultado_v4()') is not null then
 788|     perform private.assert_gestion_diaria_resultado_v4();
 789|   end if;
 790| end;
 791| $postflight$;
 792| 
 793| notify pgrst, 'reload schema';
 794| commit;
```

## Archivo: supabase/functions/crm-llamadas-ingesta/handler.ts (132 líneas) — la Edge (lo que se revisa)
```
   1| // crm-llamadas-ingesta — recibe del celular corporativo el aviso de cada llamada y su latido de salud.
   2| //
   3| // Seguridad (F3, decisión 1 provisional de Jhosep, 01/10/2026): se despliega con verify_jwt=false
   4| // porque MacroDroid no tiene sesión de usuario. El control es la CLAVE DEL CELULAR, que viaja en la
   5| // cabecera x-celular-credencial (nunca en la URL). La base solo guarda su sha256 y la valida en una
   6| // RPC que solo puede llamar service_role; cualquier problema de clave responde el MISMO 401.
   7| //
   8| // Contrato con la base (20261005143843, plan v2 de la corrección §1): la BASE es la única que valida el
   9| // contenido. Esta función solo revisa el transporte y contesta sin tocar la base únicamente:
  10| //   método distinto de POST → 405 · tipo distinto de JSON → 415 · clave sin forma válida → 401 ·
  11| //   cuerpo de más de 4 KB → 413 (corta la lectura).
  12| // Todo lo demás llega a la base, también el JSON mal formado y el sobre inválido (con la carga en null):
  13| // la base autentica, gasta cupo y devuelve {resultado: aceptado | invalido, mensaje}. Esta función elige la
  14| // puerta por `accion` y traduce: aceptado → 202 (llamada) o 200 (latido); invalido → 400 con el mensaje de
  15| // la base; 42501 → 401; P0429 → 429 con Retry-After; cualquier otra cosa → 503 (la base revirtió todo).
  16| //
  17| // La respuesta al celular es la misma para una llamada guardada, repetida o ignorada (propuesta #12):
  18| // no delata si un número es de un lead. El celular abre la encuesta de F1 por número (decisión 4), que
  19| // busca con la sesión del analista y solo en su cartera.
  20| //
  21| // Núcleo verificable sin red ni credenciales: las RPC llegan inyectadas desde index.ts.
  22| // Nunca registra cabeceras, cuerpo ni la clave.
  23| 
  24| type Json = Record<string, unknown>;
  25| export type ErrorRpc = { code?: unknown; message?: unknown; details?: unknown };
  26| export type Dependencias = {
  27|   /** Raíz del CRM, sin barra final (https://crm.miavance.com). */
  28|   urlCrm: string;
  29|   ingerir: (credencial: string, evento: unknown) => Promise<unknown>;
  30|   registrarSalud: (credencial: string, latido: unknown) => Promise<unknown>;
  31| };
  32| 
  33| const TOPE_BYTES = 4096;
  34| const CREDENCIAL = /^[0-9a-f]{64}$/;
  35| 
  36| const esObjeto = (x: unknown): x is Json => typeof x === 'object' && x !== null && !Array.isArray(x);
  37| 
  38| /** La URL que abre el celular tras enviar: la encuesta de F1 por número (decisión 4); sin número, Mi día. */
  39| export function urlAbrir(base: string, numero: unknown): string {
  40|   const raiz = `${base.replace(/\/+$/, '')}/#/gestion-diaria`;
  41|   return typeof numero === 'string' && numero.trim() !== ''
  42|     ? `${raiz}/llamada/${encodeURIComponent(numero.trim())}`
  43|     : raiz;
  44| }
  45| 
  46| /** Los segundos que la base pide esperar (DETAIL «reintentar_en_seg=N»); 60 si no los dice. */
  47| export function segundosDeEspera(detalle: unknown): number {
  48|   const m = typeof detalle === 'string' ? /^reintentar_en_seg=(\d{1,6})$/.exec(detalle) : null;
  49|   const n = m ? Number(m[1]) : Number.NaN;
  50|   return Number.isInteger(n) && n >= 1 ? n : 60;
  51| }
  52| 
  53| /** Lo que devolvió la RPC: aceptado, inválido con su mensaje (recortado) o null si no tiene la forma pactada. */
  54| export function leerResultado(dato: unknown): { aceptado: true } | { aceptado: false; mensaje: string } | null {
  55|   if (!esObjeto(dato)) return null;
  56|   if (dato.resultado === 'aceptado') return { aceptado: true };
  57|   if (dato.resultado === 'invalido') {
  58|     return { aceptado: false, mensaje: typeof dato.mensaje === 'string' && dato.mensaje !== '' ? dato.mensaje.slice(0, 200) : 'Petición inválida' };
  59|   }
  60|   return null;
  61| }
  62| 
  63| // Marcas que ningún JSON puede producir: cuerpo demasiado grande y cuerpo que no es JSON.
  64| const GRANDE = Symbol('grande');
  65| const MAL_FORMADO = Symbol('mal formado');
  66| async function leerJson(req: Request): Promise<unknown> {
  67|   const lector = req.body?.getReader();
  68|   const partes: Uint8Array<ArrayBuffer>[] = [];
  69|   let longitud = 0;
  70|   if (lector) for (;;) {
  71|     const { done, value } = await lector.read();
  72|     if (done) break;
  73|     longitud += value.byteLength;
  74|     if (longitud > TOPE_BYTES) { await lector.cancel(); return GRANDE; }
  75|     partes.push(new Uint8Array(value));
  76|   }
  77|   try {
  78|     return JSON.parse(await new Blob(partes).text());
  79|   } catch {
  80|     return MAL_FORMADO;
  81|   }
  82| }
  83| 
  84| export function crearHandler(d: Dependencias) {
  85|   return async (req: Request): Promise<Response> => {
  86|     const respuesta = (estado: number, cuerpo: Json, extra: Record<string, string> = {}) =>
  87|       new Response(JSON.stringify(cuerpo), {
  88|         status: estado,
  89|         headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  90|       });
  91|     // Una sola respuesta para todo problema de clave: no se distingue ausente, mal formada,
  92|     // desconocida, revocada o de un analista de baja.
  93|     const noAutorizado = () => respuesta(401, { error: 'No autorizado' });
  94| 
  95|     // Sin CORS: no la llama un navegador, la llama la macro del celular.
  96|     if (req.method !== 'POST') return respuesta(405, { error: 'Método no admitido' }, { Allow: 'POST' });
  97|     const tipo = (req.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
  98|     if (tipo !== 'application/json') return respuesta(415, { error: 'El cuerpo debe ser JSON' });
  99|     // La clave se mira antes que el cuerpo: sin una clave con forma válida no se revela nada más.
 100|     const credencial = req.headers.get('x-celular-credencial') ?? '';
 101|     if (!CREDENCIAL.test(credencial)) return noAutorizado();
 102| 
 103|     const cuerpo = await leerJson(req);
 104|     if (cuerpo === GRANDE) return respuesta(413, { error: 'Petición demasiado grande' });
 105| 
 106|     // La puerta se elige por `accion`; un sobre que no es exactamente {accion, evento|latido} llega con la
 107|     // carga en null y la base lo responde «invalido» (después de autenticar y gastar cupo).
 108|     const esLatido = esObjeto(cuerpo) && cuerpo.accion === 'latido';
 109|     const sobre = esObjeto(cuerpo) && Object.keys(cuerpo).length === 2 ? cuerpo : null;
 110|     const carga = esLatido
 111|       ? (sobre && 'latido' in sobre ? sobre.latido : null)
 112|       : (sobre && sobre.accion === 'llamada' && 'evento' in sobre ? sobre.evento : null);
 113| 
 114|     try {
 115|       const resultado = leerResultado(esLatido ? await d.registrarSalud(credencial, carga) : await d.ingerir(credencial, carga));
 116|       if (resultado === null) return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
 117|       if (!resultado.aceptado) return respuesta(400, { error: resultado.mensaje });
 118|       if (esLatido) return respuesta(200, { registrado: true });
 119|       // Guardada, repetida o ignorada: la misma respuesta (propuesta #12).
 120|       return respuesta(202, { recibido: true, abrir: urlAbrir(d.urlCrm, esObjeto(carga) ? carga.numero : null) });
 121|     } catch (error) {
 122|       const e: ErrorRpc = esObjeto(error) ? error : {};
 123|       if (e.code === '42501') return noAutorizado();
 124|       if (e.code === 'P0429') {
 125|         const espera = segundosDeEspera(e.details);
 126|         return respuesta(429, { error: 'Demasiados envíos de este celular', reintentar_en_seg: espera },
 127|           { 'Retry-After': String(espera) });
 128|       }
 129|       return respuesta(503, { error: 'No se pudo guardar; vuelve a intentarlo' });
 130|     }
 131|   };
 132| }
```

## Archivo: supabase/functions/crm-llamadas-ingesta/index.ts (24 líneas)
```
   1| import { createClient } from 'npm:@supabase/supabase-js@2.110.2';
   2| import { crearHandler } from './handler.ts';
   3| 
   4| // La clave de servicio vive en los secretos de Supabase y no sale de esta función: solo la usan las
   5| // dos RPC de servicio (F3-a 20261001212258, con el contrato de 20261005143843), que validan la clave del
   6| // celular y el contenido en la base y devuelven {resultado, mensaje}.
   7| const fetchAcotado: typeof fetch = (entrada, opciones) => fetch(entrada, {
   8|   ...opciones, signal: AbortSignal.timeout(8000),
   9| });
  10| const servicio = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
  11|   global: { fetch: fetchAcotado },
  12|   auth: { persistSession: false, autoRefreshToken: false },
  13| });
  14| async function rpc(nombre: string, argumentos: Record<string, unknown>): Promise<unknown> {
  15|   const { data, error } = await servicio.schema('crm').rpc(nombre, argumentos);
  16|   if (error) throw error;
  17|   return data;
  18| }
  19| 
  20| Deno.serve(crearHandler({
  21|   urlCrm: 'https://crm.miavance.com',
  22|   ingerir: (credencial, evento) => rpc('ingerir_llamada_celular_servicio', { p_credencial: credencial, p_evento: evento }),
  23|   registrarSalud: (credencial, latido) => rpc('registrar_salud_celular_servicio', { p_credencial: credencial, p_latido: latido }),
  24| }));
```

## Tramo: supabase/scripts/llamadas-celular/reversa-correccion.sql:1–50 — cabecera y guarda de la reversa de la quinta (el resto son los cuerpos de las cuatro, copiados con un guion desde el blob y comprobados con la huella del catálogo)
```
   1| -- Reversa de 20261005143843_crm_llamadas_celular_correccion.sql (la QUINTA). SOLO ANTES DE DAR DE ALTA CELULARES: sin
   2| -- asignaciones (ni cerradas), sin estado técnico, sin recepciones ni llamadas, comprobado bajo candado. Es más estricto
   3| -- que «antes del primer aviso» a propósito (revisión de Miguel en el #190, 05/10): la purga borra las recepciones a los
   4| -- 32 días, así que «ahora está vacío» no prueba «nunca se usó»; una asignación, en cambio, no se borra nunca (ni al
   5| -- cerrarla ni al rotarla). Vuelve EXACTAMENTE al estado de las cuatro migraciones: los
   6| -- cuerpos y los COMMENT se copiaron con un guion desde el blob de git de cada migración (nada a mano), y el banco
   7| -- reducido compara la huella del catálogo (tests/llamadas-celular/huella-catalogo.sql) antes de la quinta y después
   8| -- de esta reversa.
   9| -- Después del primer aviso la quinta NO se revierte (reinstalaría las fugas de la revisión del 02/10): se apaga
  10| -- (retirar la Edge, cerrar las asignaciones) y se corrige hacia adelante, conservando los hechos.
  11| --
  12| -- Orden de las reversas: enlace exacto (F4-a) → esta → elegibilidad → ingesta → núcleo → datos (esta se niega con F4-a;
  13| -- las de elegibilidad e ingesta se niegan
  14| -- mientras la quinta siga instalada).
  15| --
  16| --   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-correccion.sql
  17| begin;
  18| set local lock_timeout = '5s';
  19| set local statement_timeout = '60s';
  20| 
  21| do $precondicion$
  22| begin
  23|   if to_regclass('private.llamadas_celular_recepciones') is null
  24|      or to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is null then
  25|     raise exception 'REVERSA_CORRECCION: la migración 20261005143843 no está aplicada';
  26|   end if;
  27|   if to_regclass('private.llamadas_celular_intenciones') is not null then
  28|     raise exception 'REVERSA_CORRECCION: F4-a (20261005155914) sigue instalada; primero reversa-enlace-exacto.sql';
  29|   end if;
  30| end;
  31| $precondicion$;
  32| 
  33| lock table crm.llamadas_celular_politica, crm.celulares_asignaciones, crm.llamadas_celular_eventos,
  34|            private.celulares_estado, private.llamadas_celular_recepciones in access exclusive mode;
  35| 
  36| do $sin_avisos$
  37| begin
  38|   -- Las asignaciones no se borran (ni cerradas ni rotadas) y el estado nace con el primer envío: si existe alguna, un
  39|   -- celular pudo avisar aunque la purga ya haya retirado sus recepciones.
  40|   if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from private.celulares_estado)
  41|      or exists (select 1 from private.llamadas_celular_recepciones) or exists (select 1 from crm.llamadas_celular_eventos) then
  42|     raise exception 'REVERSA_CORRECCION: ya se dio de alta algún celular (asignaciones, estado, recepciones o llamadas): la quinta no se revierte; se apaga y se corrige hacia adelante';
  43|   end if;
  44| end;
  45| $sin_avisos$;
  46| 
  47| -- ── 1. Puertas de servicio con los cuerpos de las cuatro; el núcleo nuevo, fuera ─────────────
  48| create or replace function crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)
  49| returns jsonb
  50| language plpgsql
```

## Tramo: supabase/scripts/llamadas-celular/reversa-enlace-exacto.sql:1–45 — cabecera y guarda de la reversa de F4-a
```
   1| -- Reversa de 20261005155914_crm_llamadas_celular_enlace_exacto.sql (F4-a). SOLO ANTES DE DAR DE ALTA CELULARES: sin
   2| -- asignaciones (ni cerradas), sin estado técnico, recepciones, llamadas, enlaces ni intenciones, comprobado bajo candado.
   3| -- Más estricto que «antes del primer aviso» a propósito (revisión de Miguel en el #190, 05/10): las intenciones y las
   4| -- recepciones caducan a los 32 días, así que «ahora está vacío» no prueba «nunca se usó». Vuelve EXACTAMENTE al estado de las cinco: los cuerpos y los COMMENT de
   5| -- la ingesta y la purga (de 20261005143843) y del candado de enlaces (de 20261001145242) se copiaron con un guion desde
   6| -- el blob de git (nada a mano), y el banco reducido compara la huella del catálogo antes de F4-a y después de esta
   7| -- reversa. Después del primer aviso no se revierte: se apaga y se corrige hacia adelante.
   8| --
   9| -- Orden de las reversas: esta → corrección (reversa-correccion.sql) → elegibilidad → ingesta → núcleo → datos.
  10| --
  11| --   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/scripts/llamadas-celular/reversa-enlace-exacto.sql
  12| begin;
  13| set local lock_timeout = '5s';
  14| set local statement_timeout = '60s';
  15| 
  16| do $precondicion$
  17| begin
  18|   if to_regclass('private.llamadas_celular_intenciones') is null
  19|      or to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is null then
  20|     raise exception 'REVERSA_ENLACE_EXACTO: la migración 20261005155914 no está aplicada';
  21|   end if;
  22| end;
  23| $precondicion$;
  24| 
  25| lock table crm.celulares_asignaciones, crm.llamadas_celular_eventos, crm.llamadas_celular_enlaces, private.celulares_estado,
  26|   private.llamadas_celular_recepciones, private.llamadas_celular_intenciones in access exclusive mode;
  27| 
  28| do $sin_avisos$
  29| begin
  30|   if exists (select 1 from crm.celulares_asignaciones) or exists (select 1 from private.celulares_estado)
  31|      or exists (select 1 from private.llamadas_celular_recepciones) or exists (select 1 from crm.llamadas_celular_eventos)
  32|      or exists (select 1 from private.llamadas_celular_intenciones) or exists (select 1 from crm.llamadas_celular_enlaces) then
  33|     raise exception 'REVERSA_ENLACE_EXACTO: ya se dio de alta algún celular (asignaciones, estado, recepciones, llamadas, enlaces o intenciones): F4-a no se revierte; se apaga y se corrige hacia adelante';
  34|   end if;
  35| end;
  36| $sin_avisos$;
  37| 
  38| -- ── 1. La puerta v5 y el núcleo del enlace exacto, fuera ─────────────────────────────────────
  39| drop function crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text);
  40| 
  41| -- ── 2. La ingesta y la purga de la quinta; el candado de enlaces de F2-b ─────────────────────
  42| create or replace function private.llamada_celular_ingerir(p_asignacion_id uuid, p_evento jsonb, p_ahora timestamptz)
  43| returns jsonb
  44| language plpgsql
  45| volatile
```

## Archivo: supabase/migrations/20261001145242_crm_llamadas_celular_datos.sql (748 líneas) — tablas, candados y purga original de F2-b (la quinta los enmienda)
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

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:87–100 — private.llamada_celular_formas (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:102–113 — private.llamada_celular_candidatos (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:117–127 — private.llamada_celular_elegible (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:146–160 — private.llamada_celular_atencion_efectiva (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:163–177 — private.llamadas_celular_actor (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:669–699 — private.llamada_celular_detalle (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:510–542 — private.celular_asignar (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:544–574 — private.celular_cerrar (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:576–609 — private.celular_rotar_credencial (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:701–717 — private.celulares_asignaciones_listar (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:737–749 — crm.llamada_celular_detalle_fn (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:751–763 — crm.asociar_llamada_celular (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:765–777 — crm.enlazar_llamada_celular (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001160219_crm_llamadas_celular_nucleo.sql:779–791 — crm.descartar_llamada_celular (dependencia sin cambios; de 20261001160219_crm_llamadas_celular_nucleo.sql)
```
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
```

## Tramo: supabase/migrations/20261001212258_crm_llamadas_celular_ingesta.sql:231–267 — private.llamadas_celular_bandeja (dependencia sin cambios; de 20261001212258_crm_llamadas_celular_ingesta.sql)
```
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
```

## Tramo: supabase/migrations/20261001212258_crm_llamadas_celular_ingesta.sql:341–360 — crm.llamadas_celular_bandeja_fn (dependencia sin cambios; de 20261001212258_crm_llamadas_celular_ingesta.sql)
```
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
```

## Tramo: supabase/migrations/20261001212258_crm_llamadas_celular_ingesta.sql:362–374 — crm.celulares_salud_fn (dependencia sin cambios; de 20261001212258_crm_llamadas_celular_ingesta.sql)
```
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
```

## Tramo: supabase/migrations/20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql:41–57 — private.llamada_celular_elegible_dueno (dependencia sin cambios; de 20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql)
```
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
```

## Tramo: supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:23–341 — private.llamada_registrar_v4 (dependencia sin cambios; de 20260921153654_crm_resultado_llamada_seguimiento.sql)
```
  23| CREATE OR REPLACE FUNCTION private.llamada_registrar_v4(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text, p_detalle text, p_siguiente jsonb, p_tarea_id uuid, p_descartar boolean, p_no_insista boolean)
  24|  RETURNS jsonb
  25|  LANGUAGE plpgsql
  26|  SECURITY DEFINER
  27|  SET search_path TO ''
  28| AS $function$
  29| declare
  30|   v_tipo text;
  31|   v_motivo text;
  32|   v_descartar boolean := coalesce(p_descartar, false);
  33|   v_no_insista boolean := coalesce(p_no_insista, false);
  34|   v_sig_tipo text;
  35|   v_vence timestamptz;
  36|   v_vence_lima timestamp;
  37|   v_previa jsonb;
  38|   v_resp jsonb;
  39|   v_actividad uuid;
  40|   v_siguiente uuid;
  41|   v_etapa_antes text;
  42|   v_etapa_al_descartar text;
  43|   v_descartado_en timestamptz;
  44|   v_meta jsonb;
  45|   v_n integer;
  46|   v_intentos integer;
  47|   v_tarea_tipo text;
  48|   v_vendedor uuid;
  49|   v_bloqueo jsonb;
  50|   v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  51| begin
  52|   -- ── 1. Validación PURA del input: antes de bloquear ni escribir nada ───────
  53|   if p_actor is null or p_operacion_id is null or p_lead_id is null then
  54|     raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  55|   end if;
  56|   if p_resultado is null or p_resultado not in (
  57|     'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
  58|     'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
  59|     raise exception 'Resultado de llamada invalido' using errcode = '22023';
  60|   end if;
  61|   v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
  62|                  then 'llamada_no_contestada' else 'llamada_realizada' end;
  63| 
  64|   -- Submotivo: obligatorio en estos resultados, haya seguimiento o descarte;
  65|   -- prohibido en el resto. Elige el motivo REAL del catálogo existente.
  66|   if p_resultado = 'no_interesado' then
  67|     if p_submotivo is null or p_submotivo not in (
  68|       'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir', 'otro') then
  69|       raise exception 'Indica por que no le interesa (submotivo)' using errcode = '22023';
  70|     end if;
  71|     v_motivo := case p_submotivo when 'sin_fondos_ahora' then 'sin_fondos'
  72|                                  when 'ya_invirtio_con_otro' then 'competencia'
  73|                                  else 'sin_interes' end;
  74|     -- El resultado no descarta: decide p_descartar (contrato v4).
  75|   elsif p_resultado = 'pide_otro_producto' then
  76|     if p_submotivo is null or p_submotivo not in ('prestamo', 'credito', 'otro') then
  77|       raise exception 'Indica que producto pide (submotivo)' using errcode = '22023';
  78|     end if;
  79|     v_motivo := 'pide_credito';
  80|     -- El resultado no descarta: decide p_descartar (contrato v4).
  81|   elsif p_submotivo is not null then
  82|     raise exception 'El submotivo solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  83|   end if;
  84| 
  85|   -- Descarte por decisión del analista (decisión #6 de Miguel) o «no responde».
  86|   if v_descartar and p_resultado in ('volver_a_llamar', 'agendo_reunion') then
  87|     raise exception 'Este resultado no descarta al lead' using errcode = '22023';
  88|   end if;
  89|   if v_descartar and p_resultado in ('numero_errado', 'no_es_la_persona') then v_motivo := 'datos_invalidos'; end if;
  90|   if v_descartar and p_resultado = 'no_contesto' then v_motivo := 'no_responde'; end if;
  91|   if v_no_insista and p_resultado not in ('no_interesado', 'pide_otro_producto') then
  92|     raise exception '"No insistir" solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  93|   end if;
  94| 
  95|   -- Tarea siguiente: obligatoria en volver_a_llamar (llamada) y agendo_reunion
  96|   -- (reunion); opcional en no_contesto (llamada/whatsapp) y en numero errado /
  97|   -- no es la persona (llamada al 2.º número o reintento); prohibida al descartar.
  98|   if p_siguiente is not null and jsonb_typeof(p_siguiente) <> 'object' then
  99|     raise exception 'La tarea siguiente debe ser un objeto' using errcode = '22023';
 100|   end if;
 101|   v_sig_tipo := p_siguiente->>'tipo';
 102|   if p_siguiente is not null and (v_sig_tipo is null or v_sig_tipo not in ('llamada','whatsapp','reunion','tarea')) then
 103|     raise exception 'Tipo de proxima accion invalido' using errcode = '22023';
 104|   end if;
 105|   if v_no_insista and p_siguiente is not null then
 106|     raise exception 'No volver a contactar impide agendar una proxima accion' using errcode = '22023';
 107|   end if;
 108|   if v_descartar and p_siguiente is not null then
 109|     raise exception 'Un lead descartado no recibe tarea siguiente' using errcode = '22023';
 110|   end if;
 111|   if p_resultado = 'volver_a_llamar' and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
 112|     raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
 113|   elsif p_resultado = 'agendo_reunion' and p_siguiente is not null and v_sig_tipo is distinct from 'reunion' then
 114|     raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
 115|   elsif p_resultado = 'no_contesto' and p_siguiente is not null and v_sig_tipo not in ('llamada', 'whatsapp') then
 116|     raise exception 'Tras un "no contesto" el siguiente paso es una llamada o un WhatsApp' using errcode = '22023';
 117|   elsif p_resultado in ('numero_errado', 'no_es_la_persona') and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
 118|     raise exception 'Tras un numero errado el siguiente paso es una llamada' using errcode = '22023';
 119|   end if;
 120|   if p_siguiente is not null then
 121|     begin
 122|       v_vence := (p_siguiente->>'vence_en')::timestamptz;
 123|     exception when others then
 124|       raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
 125|     end;
 126|     if v_vence is null or not pg_catalog.isfinite(v_vence) or v_vence >= timestamptz '2100-01-01Z' then
 127|       raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
 128|     end if;
 129|   end if;
 130| 
 131|   -- ── 2. Ámbito y candados ANTES de delegar ──────────────────────────────────
 132|   -- Mismo predicado y mismo texto que el writer (no se revela existencia). El
 133|   -- orden es el de la casa: PERSONA (si habrá «No insistir», como hace
 134|   -- crm.marcar_no_contactar) → LEAD → (recibo, tarea), el mismo que ya usan
 135|   -- cerrar_tarea y el trigger serializado; etapa previa y evidencia se leen
 136|   -- bajo el candado del lead.
 137|   if private.sla_gestion_permitida(p_actor, p_lead_id) is distinct from true then
 138|     raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
 139|   end if;
 140|   if v_no_insista then
 141|     -- Identidad ANTES del lead, como crm.marcar_no_contactar (documento → persona).
 142|     if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
 143|       raise exception 'Registrar "No insistir" requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
 144|     end if;
 145|     perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
 146|     v_bloqueo := private.bloquear_personas_de_leads(array[p_lead_id], null);
 147|   end if;
 148|   select l.etapa, l.vendedor_id into v_etapa_antes, v_vendedor from crm.leads l where l.id = p_lead_id for update;
 149|   -- Tras esperar por el lead, la identidad bloqueada debe seguir siendo la suya
 150|   -- (D-13: documento/persona pudieron cambiar mientras se esperaba) → 40001.
 151|   if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
 152|      and not private.lead_dentro_de_bloqueo(p_lead_id, v_bloqueo) then
 153|     raise exception 'La persona del lead cambio mientras se registraba; vuelve a intentarlo' using errcode = '40001';
 154|   end if;
 155| 
 156|   -- ── 3. ¿Replay? (recibo ya confirmado para este actor y operación) ─────────
 157|   select r.respuesta into v_previa
 158|   from crm.sla_operacion_recibos r
 159|   where r.actor_id = p_actor and r.operacion_id = p_operacion_id;
 160| 
 161|   if v_previa is null then
 162|     if p_siguiente is not null and v_vendedor is distinct from p_actor then
 163|       raise exception 'Solo el analista dueno del lead puede agendar su proxima accion' using errcode = '42501';
 164|     end if;
 165|     if p_siguiente is not null and exists (select 1 from crm.leads l where l.id = p_lead_id and l.no_contactar) then
 166|       raise exception 'No volver a contactar impide agendar una proxima accion' using errcode = '22023';
 167|     end if;
 168| 
 169|     -- Lo TEMPORAL se exige solo a una operación nueva: un reintento tardío de
 170|     -- una operación ya confirmada (respuesta perdida) debe recuperar su recibo,
 171|     -- no morir con 22023 por una fecha que ya pasó (Codex, 19/09).
 172|     if v_vence is not null then
 173|       if v_vence <= pg_catalog.clock_timestamp() then
 174|         raise exception 'La tarea siguiente debe ser futura' using errcode = '22023';
 175|       end if;
 176|       -- Ventana legal de contacto (Ley 29571): L–S 07:00–20:00 Lima para llamada y
 177|       -- WhatsApp. Una cita la acuerda el cliente: solo se exige que sea futura.
 178|       if v_sig_tipo in ('llamada', 'whatsapp') then
 179|         v_vence_lima := v_vence at time zone 'America/Lima';
 180|         if extract(isodow from v_vence_lima) = 7
 181|            or v_vence_lima::time < time '07:00' or v_vence_lima::time >= time '20:00' then
 182|           raise exception 'Solo se contacta de lunes a sabado entre 07:00 y 20:00 (Lima)' using errcode = '22023';
 183|         end if;
 184|       end if;
 185|     end if;
 186|     if v_etapa_antes in ('convertido', 'descartado') then
 187|       raise exception 'El lead esta cerrado' using errcode = '22023';
 188|     end if;
 189|     -- La tarea siguiente se exige al DUEÑO del lead («volver a llamar crea la
 190|     -- tarea sola»); un supervisor registra sin agendar: la agenda es del analista.
 191|     if p_siguiente is null and v_vendedor = p_actor then
 192|       if p_resultado = 'volver_a_llamar' then
 193|         raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
 194|       elsif p_resultado = 'agendo_reunion' then
 195|         raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
 196|       end if;
 197|     end if;
 198|     if p_tarea_id is not null then
 199|       -- Solo una tarea de LLAMADA pendiente de este lead: cerrar aquí una cita
 200|       -- como «completada» la degradaría a sin_clasificar y saltaría la entrevista.
 201|       select t.tipo into v_tarea_tipo from crm.tareas t
 202|       where t.id = p_tarea_id and t.lead_id = p_lead_id and t.activo and t.estado = 'pendiente';
 203|       if v_tarea_tipo is null then
 204|         raise exception 'Tarea no encontrada, cerrada o de otro lead' using errcode = '22023';
 205|       end if;
 206|       if v_tarea_tipo <> 'llamada' then
 207|         raise exception 'Solo una tarea de llamada se cierra con el resultado de una llamada' using errcode = '22023';
 208|       end if;
 209|     end if;
 210|   end if;
 211| 
 212|   -- ── 4. Delegar SIEMPRE en el writer sellado (identidad del recibo, ámbito,
 213|   --      actividad, tarea siguiente, episodio SLA) ─────────────────────────────
 214|   if p_tarea_id is null then
 215|     v_resp := crm.registrar_actividad_v2(p_operacion_id, p_lead_id, v_tipo, p_detalle, p_siguiente);
 216|     v_actividad := p_operacion_id;
 217|   else
 218|     v_resp := crm.cerrar_tarea_v2(p_operacion_id, p_tarea_id, 'completada', v_tipo, p_detalle, p_siguiente, null, null);
 219|     v_actividad := nullif(v_resp->>'actividad_id', '')::uuid;
 220|     if v_actividad is null then
 221|       raise exception 'El cierre de la tarea no dejo actividad de llamada' using errcode = '23514';
 222|     end if;
 223|   end if;
 224|   if coalesce((v_resp->>'ok')::boolean, false) is not true
 225|      or nullif(v_resp->>'lead_id', '')::uuid is distinct from p_lead_id then
 226|     raise exception 'El servidor no confirmo la gestion' using errcode = '23514';
 227|   end if;
 228|   v_siguiente := nullif(v_resp->>'siguiente_id', '')::uuid;
 229| 
 230|   -- ── 5. Replay: sin escribir nada, el sobre se reconstruye desde la actividad ─
 231|   if v_previa is not null then
 232|     select a.metadata into v_meta from crm.actividades a where a.id = v_actividad;
 233|     -- El recibo del writer no guarda resultado, submotivo, descarte ni «No
 234|     -- insistir»: se comparan aquí con lo persistido (Codex, 19/09).
 235|     if v_meta->>'evento' is distinct from 'resultado_llamada'
 236|        or v_meta->>'resultado' is distinct from p_resultado
 237|        or v_meta->>'submotivo' is distinct from p_submotivo
 238|        or coalesce((v_meta->>'descartado')::boolean, false) is distinct from v_descartar
 239|        or coalesce((v_meta->>'no_insista')::boolean, false) is distinct from v_no_insista then
 240|       raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
 241|     end if;
 242|     return v_resp || pg_catalog.jsonb_build_object(
 243|       'comando', 'registrar_llamada',
 244|       'actividad_id', v_actividad,
 245|       'siguiente_id', nullif(v_meta->>'siguiente_id', '')::uuid,
 246|       'descartado', coalesce((v_meta->>'descartado')::boolean, false),
 247|       'no_insista', coalesce((v_meta->>'no_insista')::boolean, false),
 248|       'resultado', p_resultado,
 249|       'intento_n', (v_meta->>'intento_n')::integer,
 250|       'deshecho', (v_meta ? 'deshecho_en'),
 251|       'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
 252|       'replay', true);
 253|   end if;
 254| 
 255|   -- ── 6. Primera vez: el resultado en la actividad ───────────────────────────
 256|   -- intento_n = llamadas del lead en el ciclo actual, esta incluida (cardinality(array_agg), nunca la funcion de conteo: censo analitico).
 257|   select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_n
 258|   from crm.actividades a
 259|   where a.lead_id = p_lead_id
 260|     and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
 261|     and a.creado_en >= coalesce(private.inicio_ciclo_lead(p_lead_id), '-infinity'::timestamptz);
 262| 
 263|   perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
 264|   update crm.actividades a
 265|      set metadata = a.metadata || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
 266|        'evento', 'resultado_llamada',
 267|        'resultado', p_resultado,
 268|        'submotivo', p_submotivo,
 269|        'intento_n', v_n,
 270|        'etapa_anterior', v_etapa_antes,
 271|        'siguiente_id', v_siguiente,
 272|        'tarea_id', p_tarea_id,
 273|        'descartado', v_descartar,
 274|        'no_insista', v_no_insista))
 275|    where a.id = v_actividad;
 276|   if not found then
 277|     raise exception 'La actividad de la llamada no existe' using errcode = '23514';
 278|   end if;
 279|   perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);
 280| 
 281|   -- ── 7. Descarte en la misma operación (hacia el Centro de rescate) ─────────
 282|   if v_descartar then
 283|     if p_resultado = 'no_contesto' then
 284|       -- «No responde» afirma un HECHO: espejo de INTENTOS_MIN_NO_RESPONDE (2) del
 285|       -- front — intentos sin respuesta POSTERIORES a la última conversación,
 286|       -- esta llamada incluida.
 287|       select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_intentos
 288|       from crm.actividades a
 289|       where a.lead_id = p_lead_id
 290|         and a.tipo in ('llamada_no_contestada', 'whatsapp_enviado')
 291|         -- Un número errado no es «no responde»: no cuenta como intento sin respuesta.
 292|         and coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')
 293|         and a.creado_en > coalesce((
 294|           select pg_catalog.max(c.creado_en) from crm.actividades c
 295|           where c.lead_id = p_lead_id
 296|             and c.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')),
 297|           '-infinity'::timestamptz);
 298|       if v_intentos < 2 then
 299|         raise exception '"No responde" exige al menos 2 intentos sin respuesta registrados' using errcode = '22023';
 300|       end if;
 301|     end if;
 302|     select l.etapa into v_etapa_al_descartar from crm.leads l where l.id = p_lead_id;
 303|     -- Las columnas EXACTAS que hoy toca el store (lib/store.tsx descartar):
 304|     -- descartado_en/por los sella trg_leads_zz_sello_descarte; el ledger cierra
 305|     -- el episodio que lee crm.rescate_descartes_mes; las tareas pendientes las
 306|     -- cancela el sistema (trg_leads_sync_tareas).
 307|     update crm.leads
 308|        set etapa = 'descartado', motivo_descarte = v_motivo
 309|      where id = p_lead_id and activo = true and etapa not in ('convertido', 'descartado');
 310|     if not found then
 311|       raise exception 'El lead cambio mientras se registraba; recarga la ficha' using errcode = 'P0409';
 312|     end if;
 313|     select l.descartado_en into v_descartado_en from crm.leads l where l.id = p_lead_id;
 314|     perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
 315|     update crm.actividades a
 316|        set metadata = a.metadata || pg_catalog.jsonb_build_object(
 317|          'etapa_al_descartar', v_etapa_al_descartar,
 318|          'motivo_descarte', v_motivo,
 319|          'descartado_en', v_descartado_en)
 320|      where a.id = v_actividad;
 321|     perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);
 322|   end if;
 323| 
 324|   -- ── 8. «Pidió que no lo vuelvan a llamar» (Ley 29571): puerta existente ─────
 325|   if v_no_insista then
 326|     perform crm.marcar_no_contactar(p_lead_id, 'Pidio que no lo vuelvan a llamar (resultado de llamada)');
 327|   end if;
 328| 
 329|   return v_resp || pg_catalog.jsonb_build_object(
 330|     'comando', 'registrar_llamada',
 331|     'actividad_id', v_actividad,
 332|     'siguiente_id', v_siguiente,
 333|     'descartado', v_descartar,
 334|     'no_insista', v_no_insista,
 335|     'resultado', p_resultado,
 336|     'intento_n', v_n,
 337|     'deshecho', false,
 338|     'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
 339|     'replay', false);
 340| end;
 341| $function$;
```

## Tramo: supabase/migrations/20260921153654_crm_resultado_llamada_seguimiento.sql:346–368 — crm.registrar_llamada_v4 (dependencia sin cambios; de 20260921153654_crm_resultado_llamada_seguimiento.sql)
```
 346| CREATE OR REPLACE FUNCTION crm.registrar_llamada_v4(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text DEFAULT NULL::text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb, p_tarea_id uuid DEFAULT NULL::uuid, p_descartar boolean DEFAULT false, p_no_insista boolean DEFAULT false)
 347|  RETURNS jsonb
 348|  LANGUAGE plpgsql
 349|  SECURITY DEFINER
 350|  SET search_path TO ''
 351| AS $function$
 352| declare
 353|   v_uid uuid := (select auth.uid());
 354|   v_rol text := private.rol_crm((select auth.uid()));
 355| begin
 356|   -- Mismos roles que el writer (sla_ejecutar_comando); el ámbito lo decide el núcleo.
 357|   if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
 358|     raise exception 'No autorizado' using errcode = '42501';
 359|   end if;
 360|   if p_operacion_id is null or p_lead_id is null or p_resultado is null then
 361|     raise exception 'Operacion, lead y resultado son obligatorios' using errcode = '22023';
 362|   end if;
 363|   return private.llamada_registrar_v4(
 364|     v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
 365|     nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
 366|     p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
 367| end;
 368| $function$;
```

## Tramo: supabase/migrations/20260920005000_crm_gestion_diaria_resultado_llamada.sql:616–770 — crm.deshacer_resultado_llamada (dependencia sin cambios; de 20260920005000_crm_gestion_diaria_resultado_llamada.sql)
```
 616| create function crm.deshacer_resultado_llamada(p_actividad_id uuid) returns jsonb
 617| language plpgsql
 618| volatile
 619| security definer
 620| set search_path = ''
 621| as $function$
 622| declare
 623|   v_uid uuid := (select auth.uid());
 624|   v_rol text := private.rol_crm((select auth.uid()));
 625|   v_act crm.actividades%rowtype;
 626|   v_lead crm.leads%rowtype;
 627|   v_tarea crm.tareas%rowtype;
 628|   v_tarea_cancelada boolean := false;
 629|   v_descarte_revertido boolean := false;
 630|   v_cita_no_restaurada boolean := false;
 631|   v_restaurar text;
 632|   v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
 633|   v_nota uuid;
 634|   v_ahora timestamptz;
 635|   v_bloqueo jsonb;
 636| begin
 637|   if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
 638|     raise exception 'No autorizado' using errcode = '42501';
 639|   end if;
 640|   if p_actividad_id is null then
 641|     raise exception 'La actividad es obligatoria' using errcode = '22023';
 642|   end if;
 643|   -- Solo el AUTOR deshace lo suyo; una actividad ajena o inexistente recibe la
 644|   -- misma respuesta (fail-closed, sin revelar existencia).
 645|   -- La fila de la actividad se toma FOR UPDATE: dos «Deshacer» a la vez (doble
 646|   -- clic en el toast, dos pestañas) se serializan aquí y el segundo relee el
 647|   -- sello `deshecho_en` que dejó el primero. Ningún otro escritor actualiza
 648|   -- crm.actividades salvo el núcleo sobre su propia fila recién nacida.
 649|   select * into v_act from crm.actividades a where a.id = p_actividad_id for update;
 650|   if not found or v_act.creado_por is distinct from v_uid then
 651|     raise exception 'Resultado no encontrado o no es tuyo' using errcode = 'P0002';
 652|   end if;
 653|   v_ahora := pg_catalog.clock_timestamp();
 654|   if v_act.metadata->>'evento' is distinct from 'resultado_llamada' then
 655|     raise exception 'Esta actividad no es un resultado de llamada' using errcode = '22023';
 656|   end if;
 657|   if v_act.metadata ? 'deshecho_en' then
 658|     raise exception 'Este resultado ya se deshizo' using errcode = '22023';
 659|   end if;
 660|   if v_act.creado_en < v_ahora - interval '24 hours' then
 661|     raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
 662|   end if;
 663|   if coalesce((v_act.metadata->>'no_insista')::boolean, false) then
 664|     raise exception 'Este resultado marco "No insistir": esa restriccion solo la levanta Gerencia y no se deshace desde aqui'
 665|       using errcode = 'P0429';
 666|   end if;
 667|   -- Ámbito VIGENTE (el lead pudo cambiar de manos). Candados en el orden de la
 668|   -- casa (documento → persona → lead), el mismo que crm.reabrir_lead_fn: si el
 669|   -- descarte va a revertirse, los de identidad se toman ANTES del lead (una
 670|   -- reapertura concurrente del supervisor no puede cruzarse; Codex, 19/09).
 671|   -- Inertes con la identidad apagada. Se revalida ámbito y descarte DESPUÉS.
 672|   if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
 673|     raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
 674|   end if;
 675|   if coalesce((v_act.metadata->>'descartado')::boolean, false) then
 676|     if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
 677|       raise exception 'Deshacer requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
 678|     end if;
 679|     perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
 680|     v_bloqueo := private.bloquear_personas_de_leads(array[v_act.lead_id], null);
 681|   end if;
 682|   select * into v_lead from crm.leads l where l.id = v_act.lead_id for update;
 683|   if private.sla_gestion_permitida(v_uid, v_act.lead_id) is distinct from true then
 684|     raise exception 'El lead cambio de responsable; recarga la ficha' using errcode = '42501';
 685|   end if;
 686|   if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
 687|      and not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
 688|     raise exception 'La persona del lead cambio mientras se deshacia; vuelve a intentarlo' using errcode = '40001';
 689|   end if;
 690|   -- La ventana de 24 h se juzga con el reloj DESPUÉS de esperar los candados.
 691|   v_ahora := pg_catalog.clock_timestamp();
 692|   if v_act.creado_en < v_ahora - interval '24 hours' then
 693|     raise exception 'Solo se puede deshacer dentro de las 24 horas' using errcode = '22023';
 694|   end if;
 695| 
 696|   -- (a) La tarea que ESTE resultado creó, si sigue pendiente: se cancela por la
 697|   --     puerta de cierre (una cita cancelada retrocede la etapa sola).
 698|   if nullif(v_act.metadata->>'siguiente_id', '') is not null then
 699|     select * into v_tarea from crm.tareas t
 700|     where t.id = (v_act.metadata->>'siguiente_id')::uuid and t.lead_id = v_lead.id
 701|       and t.activo and t.estado = 'pendiente';
 702|     if found then
 703|       perform crm.cerrar_tarea(
 704|         v_tarea.id, 'cancelada', null, 'Resultado de llamada deshecho', null, null,
 705|         case when v_tarea.tipo = 'reunion' then 'otro' end);
 706|       v_tarea_cancelada := true;
 707|     end if;
 708|   end if;
 709| 
 710|   -- (b) El descarte, solo si el vigente es ESTE (mismo sello descartado_en).
 711|   if coalesce((v_act.metadata->>'descartado')::boolean, false)
 712|      and v_lead.etapa = 'descartado'
 713|      and v_lead.descartado_en is not null
 714|      and v_lead.descartado_en = nullif(v_act.metadata->>'descartado_en', '')::timestamptz then
 715|     -- Juzga persona, veto y ámbito; lleva el lead a `nuevo` (D-15) y abre un
 716|     -- ciclo nuevo. Un teléfono/documento ya vivo en OTRO lead (el enfriamiento
 717|     -- de datos_invalidos y pide_credito es de 0 días) se traduce a texto humano;
 718|     -- «ya es cliente» (P0409) y «persona vetada» (P0429) ya lo traen.
 719|     begin
 720|       perform crm.reabrir_lead_fn(v_lead.id);
 721|     exception when unique_violation then
 722|       raise exception 'Ya existe otro lead vivo con ese telefono o documento: el descarte no se puede revertir'
 723|         using errcode = '22023';
 724|     end;
 725|     v_restaurar := v_act.metadata->>'etapa_al_descartar';
 726|     if v_restaurar = 'reunion_agendada' then
 727|       -- La cita la canceló el sistema al descartar y no vuelve: sin cita viva no
 728|       -- hay «reunión agendada» (doctrina de 20260726151751).
 729|       v_restaurar := 'contactado';
 730|       v_cita_no_restaurada := true;
 731|     end if;
 732|     if v_restaurar in ('contactado', 'propuesta_enviada') then
 733|       update crm.leads set etapa = v_restaurar
 734|        where id = v_lead.id and activo = true and etapa = 'nuevo';
 735|     end if;
 736|     v_descarte_revertido := true;
 737|   end if;
 738| 
 739|   -- (c) Marca en la actividad original + nota en el historial (el log no se borra).
 740|   perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
 741|   update crm.actividades a
 742|      set metadata = a.metadata || pg_catalog.jsonb_build_object('deshecho_en', v_ahora, 'deshecho_por', v_uid)
 743|    where a.id = p_actividad_id;
 744|   insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
 745|   values (
 746|     v_lead.id, 'nota',
 747|     pg_catalog.format('Resultado de llamada deshecho (%s)%s%s',
 748|       v_act.metadata->>'resultado',
 749|       case when v_tarea_cancelada then ' · tarea siguiente cancelada' else '' end,
 750|       case when v_descarte_revertido then ' · descarte revertido' else '' end),
 751|     pg_catalog.jsonb_build_object(
 752|       'evento', 'resultado_deshecho', 'actividad_id', p_actividad_id,
 753|       'tarea_cancelada', v_tarea_cancelada, 'descarte_revertido', v_descarte_revertido,
 754|       'cita_no_restaurada', v_cita_no_restaurada),
 755|     v_uid)
 756|   returning id into v_nota;
 757|   perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);
 758| 
 759|   return pg_catalog.jsonb_build_object(
 760|     'ok', true,
 761|     'actividad_id', p_actividad_id,
 762|     'lead_id', v_lead.id,
 763|     'nota_id', v_nota,
 764|     'tarea_cancelada', v_tarea_cancelada,
 765|     'descarte_revertido', v_descarte_revertido,
 766|     'cita_no_restaurada', v_cita_no_restaurada,
 767|     'ciclo_nuevo', (select l.ciclo_actual from crm.leads l where l.id = v_lead.id) > v_lead.ciclo_actual,
 768|     'etapa', (select l.etapa from crm.leads l where l.id = v_lead.id));
 769| end;
 770| $function$;
```

## Tramo: supabase/migrations/20260906200000_crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado.sql:3620–3731 — «en bolsa» y «reutilizable» de private.verificar_disponibilidad_lead_impl (la regla de «Nuevo lead»)
```
3620|     end if;
3621|   end if;
3622| 
3623|   select
3624|     l.id,
3625|     l.tenencia_desde,
3626|     l.vendedor_id,
3627|     l.asignado_supervisor_id,
3628|     coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
3629|   into v_lead
3630|   from crm.leads l
3631|   left join public.perfiles pv on pv.id = l.vendedor_id
3632|   left join public.perfiles ps on ps.id = l.asignado_supervisor_id
3633|   where l.id is distinct from p_excluir_lead_id
3634|     and l.activo = true
3635|     and l.etapa not in ('convertido', 'descartado')
3636|     and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
3637|   limit 1;
3638| 
3639|   if found then
3640|     if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
3641|       return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
3642|     end if;
3643|     return pg_catalog.jsonb_build_object(
3644|       'estado', 'tomado',
3645|       'vendedor', v_lead.tenedor,
3646|       'tenencia_desde', v_lead.tenencia_desde,
3647|       -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
3648|       -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
3649|       -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
3650|       -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
3651|       -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
3652|       'ultima_conversacion_en', (
3653|         select pg_catalog.max(a.creado_en)
3654|         from crm.actividades a
3655|         where a.lead_id = v_lead.id
3656|           and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
3657|       )
3658|     );
3659|   end if;
3660| 
3661|   select
3662|     l.id,
3663|     l.activo,
3664|     l.motivo_descarte,
3665|     l.descartado_en,
3666|     pd.nombre_completo as descartado_por_nombre
3667|   into v_lead
3668|   from crm.leads l
3669|   left join public.perfiles pd on pd.id = l.descartado_por
3670|   where l.id is distinct from p_excluir_lead_id
3671|     and l.etapa = 'descartado'
3672|     and l.descartado_en is not null
3673|     and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
3674|   order by l.descartado_en desc
3675|   limit 1;
3676| 
3677|   if found then
3678|     select ep.dias
3679|     into v_dias
3680|     from crm.enfriamiento_politica ep
3681|     where ep.motivo = v_lead.motivo_descarte;
3682| 
3683|     v_dias := coalesce(v_dias, 0);
3684|     v_disponible_desde := v_lead.descartado_en
3685|       + pg_catalog.make_interval(days => v_dias);
3686| 
3687|     if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
3688|       return pg_catalog.jsonb_build_object(
3689|         'estado', 'enfriamiento',
3690|         'motivo_descarte', v_lead.motivo_descarte,
3691|         'disponible_desde', v_disponible_desde,
3692|         'descartado_por', v_lead.descartado_por_nombre
3693|       );
3694|     end if;
3695| 
3696|     -- ── F2: el descarte VENCIDO se parte (spec §5.6) ─────────────────────────
3697|     -- Un enfriamiento vencido ya NO cae al 'libre' genérico: el contacto es
3698|     -- REUTILIZABLE y su puerta es crm.tomar_lead_libre (el alta lo bloquea
3699|     -- desde F1 — crear duplicaría). Dos excepciones deliberadas del plan:
3700|     --   · activo=false jamás es reutilizable: un soft-borrado no se revive
3701|     --     por esta puerta — cae a 'libre' y el alta crea de cero.
3702|     --   · motivos con 0 días (pide_credito, datos_invalidos): CARENCIA de
3703|     --     24 h SOLO para tomar (Miguel 2026-08-16 — protege el «Deshacer
3704|     --     descarte 24h» del coordinador). Durante la ventana el veredicto
3705|     --     sigue 'libre': el alta manual conserva su comportamiento de hoy.
3706|     if v_lead.activo = true then
3707|       if v_dias = 0
3708|          and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
3709|         return pg_catalog.jsonb_build_object('estado', 'libre');
3710|       end if;
3711|       v_quedo_libre_en := case
3712|         when v_dias > 0 then v_disponible_desde
3713|         else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
3714|       end;
3715|       return pg_catalog.jsonb_build_object(
3716|         'estado', 'reutilizable',
3717|         'motivo_descarte', v_lead.motivo_descarte,
3718|         'descartado_en', v_lead.descartado_en,
3719|         'quedo_libre_en', v_quedo_libre_en,
3720|         'descartado_por', v_lead.descartado_por_nombre,
3721|         'ultima_conversacion_en', (
3722|           select pg_catalog.max(a.creado_en)
3723|           from crm.actividades a
3724|           where a.lead_id = v_lead.id
3725|             and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
3726|         )
3727|       );
3728|     end if;
3729|   end if;
3730| 
3731|   return pg_catalog.jsonb_build_object('estado', 'libre');
```

## Archivo: app/src/lib/disponibilidad-lead.ts (333 líneas) — «Nuevo lead» en la pantalla
```
   1| import * as v from 'valibot'
   2| import { ETAPAS, MOTIVOS_DESCARTE_LECTURA, type MotivoDescarteLectura } from './tipos'
   3| 
   4| // Catálogo de LECTURA: un contacto de base cargada (descartado con motivo `base_cargada`, E7) puede volver como
   5| // «enfriamiento» o «reutilizable». Con el catálogo cerrado, el veredicto entero fallaba y el alta quedaba sin respuesta.
   6| const MOTIVOS_DISPONIBILIDAD = MOTIVOS_DESCARTE_LECTURA.map((motivo) => motivo.k)
   7| 
   8| /** Contrato estricto de P-047. Vive junto a su presentación para que consulta
   9|  * y creación atómica compartan una sola frontera runtime, sin ciclos con API. */
  10| export const DisponibilidadLeadSchema = v.variant('estado', [
  11|   v.strictObject({ estado: v.literal('libre') }),
  12|   v.strictObject({ estado: v.literal('en_bolsa') }),
  13|   v.strictObject({
  14|     estado: v.literal('tomado'),
  15|     vendedor: v.nullable(v.string()),
  16|     tenencia_desde: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  17|     // Claves que el servidor estrena en fases posteriores del plan «lead
  18|     // libre» (F1: última conversación real; F4: fecha estimada de revisión).
  19|     // OPCIONALES a propósito: el front tolera ambas versiones del servidor
  20|     // — la lección del 2026-08-15: una clave nueva en la RESPUESTA de una
  21|     // RPC con contrato estricto apaga la pantalla entera si el front no
  22|     // salió primero. strictObject se conserva: una clave NO declarada sigue
  23|     // siendo error (caza typos y respuestas inesperadas).
  24|     ultima_conversacion_en: v.optional(v.nullable(v.pipe(v.string(), v.isoTimestamp()))),
  25|     fecha_estimada: v.optional(v.nullable(v.pipe(v.string(), v.isoTimestamp()))),
  26|   }),
  27|   v.strictObject({
  28|     estado: v.literal('enfriamiento'),
  29|     motivo_descarte: v.picklist(MOTIVOS_DISPONIBILIDAD),
  30|     disponible_desde: v.pipe(v.string(), v.isoTimestamp()),
  31|     descartado_por: v.nullable(v.string()),
  32|   }),
  33|   // F2 lead libre (§5.6): contacto con un lead descartado y enfriamiento
  34|   // VENCIDO — se RETOMA en vez de duplicarse. Forma fijada contra el emisor
  35|   // vivo (migración 20260817164745, en prod): las claves llegan SIEMPRE
  36|   // (jsonb_build_object no omite nulos), por eso nullable sin optional.
  37|   // Nulabilidad con evidencia: motivo_descarte jamás es null en un descartado
  38|   // (CHECK de cimientos) y el catálogo de lectura es el CHECK (7) + `base_cargada` (B7);
  39|   // descartado_en lo exige el WHERE del impl; quedo_libre_en siempre se
  40|   // calcula; descartado_por sale de un LEFT JOIN y ultima_conversacion_en de
  41|   // un max() — esos dos sí pueden ser null. Veneno conocido (auditoría
  42|   // 2026-08-17): un 'infinity' de PG17 en un timestamptz NO pasa isoTimestamp
  43|   // — a propósito: fail-closed antes que pintar basura (CHECK de finitud en
  44|   // el servidor = deuda anotada para F3).
  45|   v.strictObject({
  46|     estado: v.literal('reutilizable'),
  47|     motivo_descarte: v.picklist(MOTIVOS_DISPONIBILIDAD),
  48|     descartado_en: v.pipe(v.string(), v.isoTimestamp()),
  49|     quedo_libre_en: v.pipe(v.string(), v.isoTimestamp()),
  50|     descartado_por: v.nullable(v.string()),
  51|     ultima_conversacion_en: v.nullable(v.pipe(v.string(), v.isoTimestamp())),
  52|   }),
  53|   // `via: 'identidad'` (multiempresa, 20260903260000): la persona ya tiene lead
  54|   // reconocido por su documento aunque no tenga perfil. Opcional: con la bandera
  55|   // apagada el servidor no la manda y el veredicto se pinta igual.
  56|   v.strictObject({
  57|     estado: v.literal('ya_es_cliente'),
  58|     asesor: v.string(),
  59|     via: v.optional(v.literal('identidad')),
  60|   }),
  61|   v.strictObject({ estado: v.literal('no_contactar') }),
  62|   v.strictObject({ estado: v.literal('error'), detalle: v.literal('telefono_invalido') }),
  63| ])
  64| 
  65| // Del CONTRATO, no de los tipos generados: el generador typea el retorno de
  66| // una RPC jsonb como `Json` y el variant de arriba es la verdad de runtime.
  67| export type DisponibilidadLead = v.InferOutput<typeof DisponibilidadLeadSchema>
  68| 
  69| /** Respuesta de la mutación: o confirma la identidad creada, o devuelve el
  70|  * mismo veredicto bloqueante de P-047. Nunca existe «libre sin insertar». */
  71| export const ResultadoCreacionLeadAtomicaSchema = v.union([
  72|   v.strictObject({
  73|     estado: v.literal('creado'),
  74|     lead_id: v.pipe(v.string(), v.uuid()),
  75|   }),
  76|   // Resultado FUTURO (F2): el alta sobre un contacto reutilizable REABRE el
  77|   // mismo lead en vez de insertar. Tolerado desde ya por la misma razón que
  78|   // 'reutilizable' — quien lo maneja nace en la Fase 2.
  79|   v.looseObject({
  80|     estado: v.literal('reutilizado'),
  81|     lead_id: v.optional(v.pipe(v.string(), v.uuid())),
  82|   }),
  83|   DisponibilidadLeadSchema,
  84| ])
  85| 
  86| export type ResultadoCreacionLeadAtomica =
  87|   v.InferOutput<typeof ResultadoCreacionLeadAtomicaSchema>
  88| 
  89| // ── La toma directa (F2 «Tomar», spec §5.6/§5.7) ─────────────────────────────
  90| 
  91| const ETAPAS_ACTIVAS = ETAPAS.map((etapa) => etapa.k)
  92| 
  93| /** Los dos únicos veredictos con puerta de toma. El nombre del modo es el del
  94|  *  servidor ('bolsa' para en_bolsa): así la traza y el front hablan igual. */
  95| export type ModoToma = 'bolsa' | 'reutilizable'
  96| 
  97| /** ¿El veredicto habilita el botón «Tomar lead e iniciar seguimiento»?
  98|  *  SOLO en_bolsa y reutilizable (espejo exacto de los dos CAS de
  99|  *  crm.tomar_lead_libre) — jamás sobre tomado/enfriamiento/cliente, y sobre
 100|  *  'libre' tampoco: ahí no hay nada que tomar, el camino es CREAR. */
 101| export function contactoTomable(resultado: DisponibilidadLead): ModoToma | null {
 102|   switch (resultado.estado) {
 103|     case 'en_bolsa': return 'bolsa'
 104|     case 'reutilizable': return 'reutilizable'
 105|     default: return null
 106|   }
 107| }
 108| 
 109| /** Respuesta autoritativa de crm.tomar_lead_libre: o la toma confirmada, o el
 110|  *  veredicto FRESCO de disponibilidad (el perdedor de la carrera jamás roba —
 111|  *  recibe la verdad del momento). Forma fijada contra el emisor vivo
 112|  *  (migración 20260817164745): jsonb_build_object con 6 claves, todas
 113|  *  siempre presentes; etapa espejo del CHECK (bolsa conserva la suya,
 114|  *  reutilizable renace en 'nuevo' — nunca terminal tras una toma). */
 115| export const TomaLeadOkSchema = v.strictObject({
 116|   estado: v.literal('tomado_ok'),
 117|   lead_id: v.pipe(v.string(), v.uuid()),
 118|   modo: v.picklist(['bolsa', 'reutilizable']),
 119|   etapa: v.picklist(ETAPAS_ACTIVAS),
 120|   ciclo_actual: v.pipe(v.number(), v.integer()),
 121|   tenencia_desde: v.pipe(v.string(), v.isoTimestamp()),
 122| })
 123| 
 124| export const ResultadoTomaLeadSchema = v.union([
 125|   TomaLeadOkSchema,
 126|   DisponibilidadLeadSchema,
 127| ])
 128| 
 129| export type ResultadoTomaLead = v.InferOutput<typeof ResultadoTomaLeadSchema>
 130| 
 131| /**
 132|  * Único estado que la UI necesita conservar después del precheck P-047.
 133|  *
 134|  * No incluye el veredicto ni los demás campos del JSON: nombres, fechas y
 135|  * motivos se consumen una vez para redactar el mensaje y luego se descartan.
 136|  */
 137| export type PresentacionDisponibilidadLead = Readonly<{
 138|   mensaje: string | null
 139|   bloquea: boolean
 140| }>
 141| 
 142| const PRESENTACION_LIBRE: PresentacionDisponibilidadLead = Object.freeze({
 143|   mensaje: null,
 144|   bloquea: false,
 145| })
 146| 
 147| const ETIQUETA_MOTIVO = Object.fromEntries(
 148|   MOTIVOS_DESCARTE_LECTURA.map(({ k, label }) => [k, label]),
 149| ) as Readonly<Record<MotivoDescarteLectura, string>>
 150| 
 151| /** Texto de BD listo para una oración: acotado y sin caracteres de control. */
 152| function textoPresentable(valor: string | null): string | null {
 153|   const limpio = (valor ?? '')
 154|     .normalize('NFKC')
 155|     .replace(/[\p{Cc}\p{Cf}]/gu, ' ')
 156|     .replace(/\s+/g, ' ')
 157|     .trim()
 158|     .slice(0, 100)
 159|   return limpio || null
 160| }
 161| 
 162| /** Fecha del servidor expresada siempre en la zona de negocio, no la del equipo. */
 163| function fechaEnLima(iso: string): string | null {
 164|   const instante = Date.parse(iso)
 165|   if (!Number.isFinite(instante)) return null
 166|   return new Intl.DateTimeFormat('es-PE', {
 167|     timeZone: 'America/Lima',
 168|     day: 'numeric',
 169|     month: 'long',
 170|     year: 'numeric',
 171|   }).format(instante)
 172| }
 173| 
 174| function bloquear(mensaje: string): PresentacionDisponibilidadLead {
 175|   return { mensaje, bloquea: true }
 176| }
 177| 
 178| function estadoNoSoportado(_resultado: never): never {
 179|   // Mensaje deliberadamente estático: si el borde tipado se rompe, no volcamos
 180|   // el JSON recibido en consola, telemetría ni una excepción mostrable.
 181|   throw new TypeError('Estado de disponibilidad no soportado')
 182| }
 183| 
 184| /**
 185|  * Consume la respuesta ya validada de P-047 y la reduce al estado mínimo que
 186|  * puede renderizar el formulario. P-047 es consultivo: los errores de red no
 187|  * pasan por aquí y deben dejar el alta habilitada; `estado: error`, en cambio,
 188|  * es un veredicto válido del servidor para un teléfono inválido y sí bloquea.
 189|  */
 190| export function presentarDisponibilidadLead(
 191|   resultado: DisponibilidadLead,
 192| ): PresentacionDisponibilidadLead {
 193|   switch (resultado.estado) {
 194|     case 'libre':
 195|       return PRESENTACION_LIBRE
 196| 
 197|     case 'en_bolsa':
 198|       return bloquear('Este contacto ya se encuentra en la bolsa de leads.')
 199| 
 200|     case 'tomado': {
 201|       const vendedor = textoPresentable(resultado.vendedor)
 202|       return bloquear(
 203|         vendedor
 204|           ? `Este contacto ya está asignado a ${vendedor}.`
 205|           : 'Este contacto ya está asignado a otro miembro del equipo.',
 206|       )
 207|     }
 208| 
 209|     case 'enfriamiento': {
 210|       const fecha = fechaEnLima(resultado.disponible_desde)
 211|       const motivo = ETIQUETA_MOTIVO[resultado.motivo_descarte]
 212|       return bloquear(
 213|         fecha
 214|           ? `Este contacto está en periodo de enfriamiento por «${motivo}» hasta el ${fecha}.`
 215|           : `Este contacto todavía está en periodo de enfriamiento por «${motivo}».`,
 216|       )
 217|     }
 218| 
 219|     case 'ya_es_cliente': {
 220|       const asesorPresentable = textoPresentable(resultado.asesor)
 221|       // P-047 usa el campo legacy `asesor` y este sentinel histórico cuando el
 222|       // cliente no tiene analista; no es un nombre y no debe producir
 223|       // «a cargo de sin asesor asignado».
 224|       const asesor = asesorPresentable?.toLocaleLowerCase('es-PE') === 'sin asesor asignado'
 225|         ? null
 226|         : asesorPresentable
 227|       return bloquear(
 228|         asesor
 229|           ? `Esta persona ya es cliente y está a cargo de ${asesor}.`
 230|           : 'Esta persona ya es cliente de Avance Corp.',
 231|       )
 232|     }
 233| 
 234|     case 'no_contactar':
 235|       return bloquear('Este contacto está marcado como «No contactar» y no se puede registrar nuevamente.')
 236| 
 237|     case 'reutilizable':
 238|       // El alta sigue bloqueada (crear duplicaría, §5.6) — el camino es el
 239|       // botón «Tomar lead e iniciar seguimiento», que el formulario ofrece al
 240|       // analista junto a este aviso (contactoTomable decide cuándo).
 241|       return bloquear('Este contacto tiene un seguimiento anterior que puede retomarse en lugar de crear un duplicado.')
 242| 
 243|     case 'error':
 244|       return bloquear('Ingresa un teléfono válido para verificar su disponibilidad.')
 245| 
 246|     default:
 247|       return estadoNoSoportado(resultado)
 248|   }
 249| }
 250| 
 251| /**
 252|  * Presenta el veredicto fresco que devuelve una toma SIN éxito (§5.7): el
 253|  * estado cambió entre el precheck y la escritura — otro se adelantó, un
 254|  * enfriamiento renació, el lead desapareció. El prefijo avisa del cambio solo
 255|  * cuando el veredicto bloquea; un 'libre' fresco no lleva aviso: el alta se
 256|  * habilita y crear es el camino.
 257|  */
 258| export function presentarResultadoToma(
 259|   resultado: DisponibilidadLead,
 260| ): PresentacionDisponibilidadLead {
 261|   const base = presentarDisponibilidadLead(resultado)
 262|   if (!base.bloquea || base.mensaje == null) return base
 263|   return { mensaje: `La disponibilidad acaba de cambiar. ${base.mensaje}`, bloquea: true }
 264| }
 265| 
 266| // ── Tarjeta de la spec §5.2 ──────────────────────────────────────────────────
 267| 
 268| /**
 269|  * Tarjeta informativa de SOLO LECTURA para el analista que verifica: los datos
 270|  * mínimos del seguimiento, nada más (spec §8: sin notas, sin montos, sin
 271|  * detalle ajeno). Función hermana de presentarDisponibilidadLead — NO amplía
 272|  * su contrato {mensaje, bloquea}, que está fijado por prueba — y consume el
 273|  * JSON una sola vez, igual que él.
 274|  *
 275|  * «Revisable desde (estimado)» solo aparece cuando el servidor manda una fecha
 276|  * con motor real detrás (enfriamiento hoy; leads tomados recién en la F4 del
 277|  * plan): la tarjeta no inventa promesas.
 278|  */
 279| export type TarjetaDisponibilidadLead = Readonly<{
 280|   titulo: string
 281|   lineas: ReadonlyArray<Readonly<{ etiqueta: string; valor: string }>>
 282| }>
 283| 
 284| export function tarjetaDisponibilidadLead(
 285|   resultado: DisponibilidadLead,
 286| ): TarjetaDisponibilidadLead | null {
 287|   switch (resultado.estado) {
 288|     case 'tomado': {
 289|       const lineas: Array<{ etiqueta: string; valor: string }> = []
 290|       const asesor = textoPresentable(resultado.vendedor)
 291|       if (asesor) lineas.push({ etiqueta: 'Analista', valor: asesor })
 292|       const desde = resultado.tenencia_desde != null ? fechaEnLima(resultado.tenencia_desde) : null
 293|       if (desde) lineas.push({ etiqueta: 'En seguimiento desde', valor: desde })
 294|       const conversacion = resultado.ultima_conversacion_en != null
 295|         ? fechaEnLima(resultado.ultima_conversacion_en)
 296|         : null
 297|       if (conversacion) lineas.push({ etiqueta: 'Última conversación', valor: conversacion })
 298|       const estimada = resultado.fecha_estimada != null ? fechaEnLima(resultado.fecha_estimada) : null
 299|       if (estimada) lineas.push({ etiqueta: 'Revisable desde (estimado)', valor: estimada })
 300|       return { titulo: 'Seguimiento activo', lineas }
 301|     }
 302|     case 'enfriamiento': {
 303|       const lineas: Array<{ etiqueta: string; valor: string }> = [
 304|         { etiqueta: 'Motivo del descarte', valor: ETIQUETA_MOTIVO[resultado.motivo_descarte] },
 305|       ]
 306|       // Quién lo descartó NO va en la tarjeta (minimización §8); la fecha sí:
 307|       // es la única «disponible desde» con regla real detrás hoy.
 308|       const fecha = fechaEnLima(resultado.disponible_desde)
 309|       if (fecha) lineas.push({ etiqueta: 'Disponible desde', valor: fecha })
 310|       return { titulo: 'En enfriamiento', lineas }
 311|     }
 312|     case 'reutilizable': {
 313|       // La historia mínima del seguimiento anterior ya recuperable (§5.6):
 314|       // motivo, cuándo se descartó, desde cuándo está libre y la última
 315|       // conversación real. `descartado_por` llega del servidor pero NO se
 316|       // pinta — misma minimización §8 que la tarjeta de enfriamiento.
 317|       const lineas: Array<{ etiqueta: string; valor: string }> = [
 318|         { etiqueta: 'Motivo del descarte', valor: ETIQUETA_MOTIVO[resultado.motivo_descarte] },
 319|       ]
 320|       const descartado = fechaEnLima(resultado.descartado_en)
 321|       if (descartado) lineas.push({ etiqueta: 'Descartado el', valor: descartado })
 322|       const libre = fechaEnLima(resultado.quedo_libre_en)
 323|       if (libre) lineas.push({ etiqueta: 'Libre desde', valor: libre })
 324|       const conversacion = resultado.ultima_conversacion_en != null
 325|         ? fechaEnLima(resultado.ultima_conversacion_en)
 326|         : null
 327|       if (conversacion) lineas.push({ etiqueta: 'Última conversación', valor: conversacion })
 328|       return { titulo: 'Seguimiento anterior disponible', lineas }
 329|     }
 330|     default:
 331|       return null
 332|   }
 333| }
```

## Archivo: supabase/tests/llamadas-celular/oraculo-correccion.sql (574 líneas) — oráculo de la quinta
```
   1| -- Oráculo de la QUINTA migración (20261005143843, corrección de F2 + F3) sobre el banco REDUCIDO de
   2| -- supabase/tests/llamadas-celular/base.sql. Se corre como dueño después de las cuatro y la quinta; todo en una
   3| -- transacción que termina en ROLLBACK. Cubre la lista «El oráculo nuevo comprueba» de CORRECCION-PLAN-CORTO.md:
   4| -- sin pistas, bolsa, reutilizable, propios terminales, id, purga, cupo, identidad, lead borrado, entrantes,
   5| -- fecha estricta y salud sin envíos. Las carreras con dos sesiones van en la pasada de concurrencia del guion.
   6| -- Actores simulados como en Supabase: rol authenticated / service_role + request.jwt.claim.sub.
   7| -- Un SET LOCAL hecho dentro de un bloque con EXCEPTION se deshace si el bloque falla: los casos que deben fallar
   8| -- llaman a los ayudantes DENTRO de su bloque.
   9| -- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia.
  10| -- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
  11| begin;
  12| set local lock_timeout = '5s';
  13| set local statement_timeout = '120s';
  14| 
  15| -- ── Ayudantes (temporales: se van con el ROLLBACK) ──────────────────────────────────────────
  16| create function pg_temp.ev(p_id text, p_numero text, p_extra jsonb default '{}'::jsonb)
  17| returns jsonb language sql immutable as $$
  18|   select jsonb_build_object('v', 1, 'evento_origen_id', p_id, 'numero', p_numero, 'direccion', 'saliente') || p_extra
  19| $$;
  20| create function pg_temp.enviar(p_clave text, p_evento jsonb)
  21| returns jsonb language plpgsql as $$
  22| declare v jsonb;
  23| begin
  24|   perform set_config('request.jwt.claim.sub', '', true);
  25|   execute 'set local role service_role';
  26|   v := crm.ingerir_llamada_celular_servicio(p_clave, p_evento);
  27|   execute 'set local role none';
  28|   return v;
  29| end $$;
  30| create function pg_temp.latir(p_clave text, p_latido jsonb)
  31| returns jsonb language plpgsql as $$
  32| declare v jsonb;
  33| begin
  34|   perform set_config('request.jwt.claim.sub', '', true);
  35|   execute 'set local role service_role';
  36|   v := crm.registrar_salud_celular_servicio(p_clave, p_latido);
  37|   execute 'set local role none';
  38|   return v;
  39| end $$;
  40| create function pg_temp.bandeja(p_actor uuid)
  41| returns jsonb language plpgsql as $$
  42| declare v jsonb;
  43| begin
  44|   perform set_config('request.jwt.claim.sub', p_actor::text, true);
  45|   execute 'set local role authenticated';
  46|   v := crm.llamadas_celular_bandeja_fn(200) -> 'filas';
  47|   execute 'set local role none';
  48|   perform set_config('request.jwt.claim.sub', '', true);
  49|   return v;
  50| end $$;
  51| create function pg_temp.ve(p_actor uuid, p_evento uuid)
  52| returns boolean language sql as $$
  53|   select exists (select 1 from jsonb_array_elements(pg_temp.bandeja(p_actor)) x where (x ->> 'evento_id')::uuid = p_evento)
  54| $$;
  55| create function pg_temp.como(p_actor uuid)
  56| returns void language plpgsql as $$
  57| begin
  58|   perform set_config('request.jwt.claim.sub', p_actor::text, true);
  59|   execute 'set local role authenticated';
  60| end $$;
  61| create function pg_temp.yo()
  62| returns void language plpgsql as $$
  63| begin
  64|   execute 'set local role none';
  65|   perform set_config('request.jwt.claim.sub', '', true);
  66| end $$;
  67| create function pg_temp.evento(p_id text)
  68| returns crm.llamadas_celular_eventos language sql as $$
  69|   select * from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
  70| $$;
  71| 
  72| do $oraculo$
  73| declare
  74|   a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  75|   a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  76|   a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  77|   b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  78|   g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  79|   c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  80|   c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  81|   c3 constant uuid := '00000000-0000-0000-0000-0000000000c3';
  82|   c4 constant uuid := '00000000-0000-0000-0000-0000000000c4';
  83|   c5 constant uuid := '00000000-0000-0000-0000-0000000000c5';
  84|   c6 constant uuid := '00000000-0000-0000-0000-0000000000c6';
  85|   c7 constant uuid := '00000000-0000-0000-0000-0000000000c7';
  86|   cb constant uuid := '00000000-0000-0000-0000-0000000000d1';   -- en bolsa
  87|   cr constant uuid := '00000000-0000-0000-0000-0000000000d2';   -- descartado reutilizable (0 días, hace 2 días)
  88|   ce constant uuid := '00000000-0000-0000-0000-0000000000d3';   -- descartado en enfriamiento (30 días, hace 5)
  89|   cr2 constant uuid := '00000000-0000-0000-0000-0000000000d4';  -- descartado reutilizable (30 días, hace 31)
  90|   cr0 constant uuid := '00000000-0000-0000-0000-0000000000d5';  -- descartado en carencia (0 días, hace 2 h)
  91|   cv1 constant uuid := '00000000-0000-0000-0000-0000000000d6';  -- dos ajenos con el mismo número
  92|   cv2 constant uuid := '00000000-0000-0000-0000-0000000000d7';
  93|   aceptado constant jsonb := '{"resultado": "aceptado"}';
  94|   t0 bigint := floor(extract(epoch from now()))::bigint - 50000;  -- ~14 h atrás: dentro de la ventana
  95|   v_c1 uuid; v_c2 uuid; v_c4 uuid; v_c1b uuid; v_c1c uuid;
  96|   k1 text; k2 text; k4 text; k1b text; k1c text;
  97|   v_r jsonb; v_r2 jsonb; v_salud jsonb; v_salud2 jsonb;
  98|   v_ev crm.llamadas_celular_eventos%rowtype;
  99|   v_n integer; v_n2 integer; v_dia date; v_dia2 date;
 100|   v_act uuid; v_act2 uuid; v_ok integer := 0;
 101|   v_msg text; v_det text; v_t timestamptz; v_id_ignorado text;
 102|   v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_e5 uuid; v_e6 uuid; v_e7 uuid;
 103| begin
 104|   -- ═════ Preparación ═════
 105|   -- El cupo de 30 por minuto lo agotarían las pruebas: se sube aquí y la sección G lo prueba con valores fijados.
 106|   update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
 107|   perform pg_temp.como(g1);
 108|   v_r := crm.asignar_celular('C1', a1); v_c1 := (v_r ->> 'asignacion_id')::uuid; k1 := v_r ->> 'credencial';
 109|   v_r := crm.asignar_celular('C2', a3); v_c2 := (v_r ->> 'asignacion_id')::uuid; k2 := v_r ->> 'credencial';
 110|   v_r := crm.asignar_celular('C4', b1); v_c4 := (v_r ->> 'asignacion_id')::uuid; k4 := v_r ->> 'credencial';
 111|   perform pg_temp.yo();
 112|   insert into crm.leads (id, nombre_completo, telefono, etapa, vendedor_id, asignado_supervisor_id,
 113|                          motivo_descarte, descartado_en) values
 114|     (cb, 'Lead en Bolsa', '+51900000010', 'nuevo', null, null, null, null),
 115|     (cr, 'Descartado Reutilizable', '+51900000011', 'descartado', a3, null, 'pide_credito', now() - interval '2 days'),
 116|     (ce, 'Descartado en Enfriamiento', '+51900000012', 'descartado', a3, null, 'sin_interes', now() - interval '5 days'),
 117|     (cr2, 'Reutilizable de 30 Días', '+51900000013', 'descartado', a2, null, 'sin_interes', now() - interval '31 days'),
 118|     (cr0, 'Descartado en Carencia', '+51900000016', 'descartado', a3, null, 'pide_credito', now() - interval '2 hours'),
 119|     (cv1, 'Ajeno Uno', '+51900000015', 'nuevo', a3, null, null, null),
 120|     (cv2, 'Ajeno Dos', '+51900000017', 'nuevo', a2, null, null, null);
 121|   update crm.leads set telefono_alternativo = '+51900000015' where id = cv2;
 122| 
 123|   -- ═════ A. Sin pistas: sin lead, ajeno con dueño, ajeno en enfriamiento, en carencia y varios ajenos ═════
 124|   perform pg_temp.como(g1); v_salud := crm.celulares_salud_fn(); perform pg_temp.yo();
 125|   v_id_ignorado := 'C1-' || (t0 + 1);
 126|   v_r := pg_temp.enviar(k1, pg_temp.ev(v_id_ignorado, '900000099'));
 127|   select dia, envios_dia into v_dia, v_n from private.celulares_estado where asignacion_id = v_c1;
 128|   if v_r is distinct from aceptado then raise exception 'ORACULO A1: la respuesta a un número sin lead no es la uniforme (%)', v_r; end if;
 129|   foreach v_msg in array array['900000008', '900000012', '900000016', '900000015'] loop
 130|     t0 := t0 + 1;
 131|     v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 1), v_msg));
 132|     if v_r2::text is distinct from v_r::text then
 133|       raise exception 'ORACULO A2: la respuesta delata el número % (% contra %)', v_msg, v_r2, v_r;
 134|     end if;
 135|   end loop;
 136|   select dia, envios_dia into v_dia2, v_n2 from private.celulares_estado where asignacion_id = v_c1;
 137|   if v_dia2 = v_dia and v_n2 <> v_n + 4 then
 138|     raise exception 'ORACULO A3: el cupo no se gastó igual en los cinco casos (% → %)', v_n, v_n2;
 139|   end if;
 140|   if exists (select 1 from crm.llamadas_celular_eventos) then
 141|     raise exception 'ORACULO A4: se guardó una llamada sin candidato';
 142|   end if;
 143|   if (select count(*) from private.llamadas_celular_recepciones) <> 5 then
 144|     raise exception 'ORACULO A5: no hay una recepción por cada aviso aceptado';
 145|   end if;
 146|   perform pg_temp.como(g1); v_salud2 := crm.celulares_salud_fn(); perform pg_temp.yo();
 147|   if v_salud2::text is distinct from v_salud::text then
 148|     raise exception 'ORACULO A6: la salud cambió con avisos sin lead (% → %)', v_salud, v_salud2;
 149|   end if;
 150|   -- El propio responde lo mismo y sí se guarda.
 151|   t0 := t0 + 10;
 152|   v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000001'));
 153|   v_ev := pg_temp.evento('C1-' || t0);
 154|   if v_r2::text is distinct from v_r::text or v_ev.lead_id is distinct from c1
 155|      or v_ev.atencion is distinct from 'requiere_resultado' or v_ev.metodo_asociacion is distinct from 'exacto' then
 156|     raise exception 'ORACULO A7: el lead propio no respondió igual o no quedó identificado pidiendo resultado (%, %)', v_r2, row_to_json(v_ev);
 157|   end if;
 158|   v_e1 := v_ev.id;
 159| 
 160|   -- ═════ B. Bolsa: por revisar, quien llamó no la ve, le aparece a quien lo toma ═════
 161|   t0 := t0 + 1;
 162|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000010'));
 163|   v_ev := pg_temp.evento('C1-' || t0);
 164|   if v_ev.lead_id is distinct from cb or v_ev.atencion is distinct from 'por_revisar' or v_ev.analista_id is distinct from a1 then
 165|     raise exception 'ORACULO B1: la llamada a un lead en bolsa no quedó identificada por revisar (%)', row_to_json(v_ev);
 166|   end if;
 167|   v_e2 := v_ev.id;
 168|   if pg_temp.ve(a1, v_e2) or pg_temp.ve(b1, v_e2) then
 169|     raise exception 'ORACULO B2: quien llamó (o su supervisor) ve la llamada a un lead en bolsa';
 170|   end if;
 171|   begin
 172|     perform pg_temp.como(a1);
 173|     perform crm.llamada_celular_detalle_fn(v_e2);
 174|     raise exception 'ORACULO B3: quien llamó lee el detalle de la llamada a un lead en bolsa';
 175|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 176|   if not pg_temp.ve(g1, v_e2) then raise exception 'ORACULO B4: gerencia no ve la llamada a un lead en bolsa'; end if;
 177|   -- a2 toma el lead (en producción, crm.tomar_lead_libre): ahora la ve y la puede enlazar.
 178|   update crm.leads set vendedor_id = a2 where id = cb;
 179|   if not pg_temp.ve(a2, v_e2) then raise exception 'ORACULO B5: quien tomó el lead no ve su llamada'; end if;
 180|   insert into crm.actividades (lead_id, tipo, metadata, creado_por)
 181|   values (cb, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a2)
 182|   returning id into v_act;
 183|   perform pg_temp.como(a2);
 184|   v_r := crm.enlazar_llamada_celular(v_e2, v_act);
 185|   perform pg_temp.yo();
 186|   if (select atencion from crm.llamadas_celular_eventos where id = v_e2) is distinct from 'registrado' then
 187|     raise exception 'ORACULO B6: quien tomó el lead no pudo enlazar su llamada (%)', v_r;
 188|   end if;
 189| 
 190|   -- ═════ C. Reutilizables: igual que la bolsa; en enfriamiento o en carencia, como sin lead (ya en A) ═════
 191|   t0 := t0 + 1;
 192|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000011'));
 193|   v_ev := pg_temp.evento('C1-' || t0);
 194|   if v_ev.lead_id is distinct from cr or v_ev.atencion is distinct from 'por_revisar' then
 195|     raise exception 'ORACULO C1: el descartado reutilizable (0 días, pasadas 24 h) no quedó por revisar (%)', row_to_json(v_ev);
 196|   end if;
 197|   if pg_temp.ve(a1, v_ev.id) then raise exception 'ORACULO C2: quien llamó ve la llamada a un reutilizable'; end if;
 198|   t0 := t0 + 1;
 199|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000013'));
 200|   v_ev := pg_temp.evento('C1-' || t0);
 201|   if v_ev.lead_id is distinct from cr2 or v_ev.atencion is distinct from 'por_revisar' then
 202|     raise exception 'ORACULO C3: el descartado reutilizable (30 días cumplidos) no quedó por revisar (%)', row_to_json(v_ev);
 203|   end if;
 204| 
 205|   -- ═════ D. Propios terminales o en «no contactar»: identificadas, por revisar; número compartido ═════
 206|   t0 := t0 + 1;
 207|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000005'));
 208|   v_ev := pg_temp.evento('C1-' || t0);
 209|   if v_ev.lead_id is distinct from c5 or v_ev.atencion is distinct from 'por_revisar' then
 210|     raise exception 'ORACULO D1: el propio convertido no quedó identificado por revisar (%)', row_to_json(v_ev);
 211|   end if;
 212|   t0 := t0 + 1;
 213|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000004'));
 214|   v_ev := pg_temp.evento('C1-' || t0);
 215|   if v_ev.lead_id is distinct from c4 or v_ev.atencion is distinct from 'por_revisar' then
 216|     raise exception 'ORACULO D2: el propio en «no contactar» no quedó identificado por revisar (%)', row_to_json(v_ev);
 217|   end if;
 218|   -- 900000006 es de c6 (a1) y c7 (a2): para a1, coincidencia única en su cartera; para b1, ambigua.
 219|   t0 := t0 + 1;
 220|   perform pg_temp.enviar(k1, pg_temp.ev('C1-' || t0, '900000006'));
 221|   v_ev := pg_temp.evento('C1-' || t0);
 222|   if v_ev.lead_id is distinct from c6 or v_ev.atencion is distinct from 'requiere_resultado' then
 223|     raise exception 'ORACULO D3: el número compartido no quedó con el lead propio (%)', row_to_json(v_ev);
 224|   end if;
 225|   t0 := t0 + 1;
 226|   perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000006'));
 227|   v_ev := pg_temp.evento('C4-' || t0);
 228|   if v_ev.identificacion is distinct from 'ambiguo' or v_ev.lead_id is not null or v_ev.calidad ? 'candidatos' then
 229|     raise exception 'ORACULO D4: la llamada del supervisor no quedó ambigua sin conteo (%)', row_to_json(v_ev);
 230|   end if;
 231|   v_e3 := v_ev.id;
 232|   -- Asociarla (candados: los dos leads, la llamada) a c7, del equipo de b1: pide resultado.
 233|   perform pg_temp.como(b1);
 234|   v_r := crm.asociar_llamada_celular(v_e3, c7);
 235|   perform pg_temp.yo();
 236|   if v_r ->> 'atencion' is distinct from 'requiere_resultado' or (select lead_id from crm.llamadas_celular_eventos where id = v_e3) is distinct from c7 then
 237|     raise exception 'ORACULO D5: asociar la ambigua a un lead del equipo no funcionó (%)', v_r;
 238|   end if;
 239| 
 240|   -- ═════ E. El id ═════
 241|   select envios_dia, dia into v_n, v_dia from private.celulares_estado where asignacion_id = v_c1;
 242|   foreach v_msg in array array['X1-1790980958', 'C1-123', 'C1-' || (t0 + 1) || 'x', 'C2-' || (t0 + 1),
 243|                                 'C1-' || (floor(extract(epoch from now() - interval '31 days'))::bigint),
 244|                                 'C1-' || (floor(extract(epoch from now() + interval '2 days'))::bigint)] loop
 245|     v_r := pg_temp.enviar(k1, pg_temp.ev(v_msg, '900000001'));
 246|     if v_r ->> 'resultado' is distinct from 'invalido' or coalesce(v_r ->> 'mensaje', '') = '' or (v_r - 'resultado' - 'mensaje') <> '{}'::jsonb then
 247|       raise exception 'ORACULO E1: el id % no se rechazó como inválido con su mensaje (%)', v_msg, v_r;
 248|     end if;
 249|     if exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = v_msg) then
 250|       raise exception 'ORACULO E2: el id inválido % dejó recepción', v_msg;
 251|     end if;
 252|   end loop;
 253|   select envios_dia, dia into v_n2, v_dia2 from private.celulares_estado where asignacion_id = v_c1;
 254|   if v_dia2 = v_dia and v_n2 <> v_n + 6 then
 255|     raise exception 'ORACULO E3: los inválidos no gastaron cupo (% → %)', v_n, v_n2;
 256|   end if;
 257|   -- Los bordes de la ventana entran.
 258|   v_r := pg_temp.enviar(k1, pg_temp.ev('C1-' || floor(extract(epoch from now() - interval '29 days'))::bigint, '900000099'));
 259|   v_r2 := pg_temp.enviar(k1, pg_temp.ev('C1-' || floor(extract(epoch from now() + interval '23 hours'))::bigint, '900000099'));
 260|   if v_r <> aceptado or v_r2 <> aceptado then
 261|     raise exception 'ORACULO E4: un id dentro de la ventana no entró (%, %)', v_r, v_r2;
 262|   end if;
 263|   -- El mismo id con otro contenido: aceptado y sin cambios.
 264|   v_ev := pg_temp.evento((select evento_origen_id from crm.llamadas_celular_eventos where id = v_e1));
 265|   v_r := pg_temp.enviar(k1, pg_temp.ev(v_ev.evento_origen_id, '900000002', '{"duracion_seg": 99}'));
 266|   if v_r <> aceptado or (select row_to_json(e)::text from crm.llamadas_celular_eventos e where e.id = v_e1) <> row_to_json(v_ev)::text
 267|      or (select count(*) from crm.llamadas_celular_eventos where evento_origen_id = v_ev.evento_origen_id) <> 1 then
 268|     raise exception 'ORACULO E5: el mismo id con otro contenido cambió algo (%)', v_r;
 269|   end if;
 270|   -- Ignorado y después el mismo id con lead: sigue ignorado.
 271|   v_r := pg_temp.enviar(k1, pg_temp.ev(v_id_ignorado, '900000001'));
 272|   if v_r <> aceptado or exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id = v_id_ignorado) then
 273|     raise exception 'ORACULO E6: un id ignorado entró después con un lead (%)', v_r;
 274|   end if;
 275|   -- Rotar no duplica; la clave vieja deja de valer; un id nuevo entra con la asignación nueva.
 276|   perform pg_temp.como(g1);
 277|   v_r := crm.rotar_credencial_celular('C1'); v_c1b := (v_r ->> 'asignacion_id')::uuid; k1b := v_r ->> 'credencial';
 278|   perform pg_temp.yo();
 279|   v_r := pg_temp.enviar(k1b, pg_temp.ev(v_ev.evento_origen_id, '900000001'));
 280|   if v_r <> aceptado or (select count(*) from crm.llamadas_celular_eventos where evento_origen_id = v_ev.evento_origen_id) <> 1 then
 281|     raise exception 'ORACULO E7: rotar la clave duplicó la llamada (%)', v_r;
 282|   end if;
 283|   begin
 284|     perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 2), '900000001'));
 285|     raise exception 'ORACULO E8: la clave rotada siguió valiendo';
 286|   exception when insufficient_privilege then
 287|     if sqlerrm <> 'No autorizado' then raise exception 'ORACULO E8: la clave rotada dio pistas (%)', sqlerrm; end if;
 288|     v_ok := v_ok + 1;
 289|   end;
 290|   t0 := t0 + 3;
 291|   perform pg_temp.enviar(k1b, pg_temp.ev('C1-' || t0, '900000002'));
 292|   v_ev := pg_temp.evento('C1-' || t0);
 293|   if v_ev.asignacion_id is distinct from v_c1b or v_ev.lead_id is distinct from c2 then
 294|     raise exception 'ORACULO E9: un id nuevo no entró con la asignación rotada (%)', row_to_json(v_ev);
 295|   end if;
 296|   -- Etiqueta reutilizada: C1 se cierra y pasa a a2; un id nuevo entra a nombre de a2.
 297|   perform pg_temp.como(g1);
 298|   perform crm.cerrar_asignacion_celular(v_c1b, 'reemplazo');
 299|   v_r := crm.asignar_celular('C1', a2); v_c1c := (v_r ->> 'asignacion_id')::uuid; k1c := v_r ->> 'credencial';
 300|   perform pg_temp.yo();
 301|   t0 := t0 + 1;
 302|   perform pg_temp.enviar(k1c, pg_temp.ev('C1-' || t0, '900000003'));
 303|   v_ev := pg_temp.evento('C1-' || t0);
 304|   if v_ev.analista_id is distinct from a2 or v_ev.lead_id is distinct from c3 or v_ev.atencion is distinct from 'requiere_resultado' then
 305|     raise exception 'ORACULO E10: con la etiqueta reutilizada el id nuevo no entró a nombre del analista nuevo (%)', row_to_json(v_ev);
 306|   end if;
 307| 
 308|   -- ═════ F. Latido y fecha estricta ═════
 309|   v_t := clock_timestamp();
 310|   v_r := pg_temp.latir(k4, '{"v": 1, "version_macro": "llamadas-v2", "en_cola": 0, "ocurrio_en": "2026-10-05 09:30:00-05:00"}');
 311|   if v_r <> aceptado or coalesce((select ultimo_latido_en < v_t or version_macro <> 'llamadas-v2'
 312|                          from private.celulares_estado where asignacion_id = v_c4), true) then
 313|     raise exception 'ORACULO F1: el latido válido no quedó con la hora de la puerta (%)', v_r;
 314|   end if;
 315|   select envios_dia, dia into v_n, v_dia from private.celulares_estado where asignacion_id = v_c4;
 316|   foreach v_msg in array array[
 317|       '{"v": 1, "version_macro": "x"}', '{"v": 1, "version_macro": "x", "en_cola": 1.5}',
 318|       '{"v": 1, "version_macro": "x", "en_cola": 0, "ocurrio_en": "2026-10-05 09:30:00"}',
 319|       '{"v": 1, "version_macro": "x", "en_cola": 0, "ocurrio_en": "2026-02-30 09:30:00-05:00"}',
 320|       '{"v": 2, "version_macro": "x", "en_cola": 0}', 'null', '[1]'] loop
 321|     v_r := pg_temp.latir(k4, v_msg::jsonb);
 322|     if v_r ->> 'resultado' is distinct from 'invalido' then
 323|       raise exception 'ORACULO F2: el latido inválido % no respondió «invalido» (%)', v_msg, v_r;
 324|     end if;
 325|   end loop;
 326|   select envios_dia, dia into v_n2, v_dia2 from private.celulares_estado where asignacion_id = v_c4;
 327|   if (v_dia2 = v_dia and v_n2 <> v_n + 7)
 328|      or (select version_macro from private.celulares_estado where asignacion_id = v_c4) is distinct from 'llamadas-v2' then
 329|     raise exception 'ORACULO F3: el latido inválido no gastó cupo o tocó el estado (% → %)', v_n, v_n2;
 330|   end if;
 331|   t0 := t0 + 1;
 332|   v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099', '{"ocurrio_en": "2026-10-05 09:30:00"}'));
 333|   if v_r ->> 'resultado' is distinct from 'invalido' then raise exception 'ORACULO F4: una fecha sin zona se aceptó (%)', v_r; end if;
 334|   t0 := t0 + 1;
 335|   v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099', '{"ocurrio_en": "2026-10-05T14:30:00.5Z", "duracion_seg": 30}'));
 336|   v_r2 := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099', '{"duracion_seg": "30"}'));
 337|   if v_r <> aceptado or v_r2 ->> 'resultado' is distinct from 'invalido' then
 338|     raise exception 'ORACULO F5: fecha con T y Z o duración como texto mal juzgadas (%, %)', v_r, v_r2;
 339|   end if;
 340|   t0 := t0 + 2;
 341| 
 342|   -- ═════ G. Cupo: la ventana no retrocede; Retry-After ≥ 1; sin política, error claro ═════
 343|   update crm.llamadas_celular_politica set limite_envios_minuto = 30, limite_envios_dia = 600;
 344|   update private.celulares_estado
 345|      set minuto_desde = date_trunc('minute', clock_timestamp()) + interval '10 minutes', envios_minuto = 30
 346|    where asignacion_id = v_c4;
 347|   begin
 348|     perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
 349|     raise exception 'ORACULO G1: con la ventana guardada adelante y agotada, el envío pasó (la ventana retrocedió)';
 350|   exception when sqlstate 'P0429' then
 351|     get stacked diagnostics v_det = pg_exception_detail;
 352|     if coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) < 540 then
 353|       raise exception 'ORACULO G1: la espera no sale de la ventana guardada (%)', v_det;
 354|     end if;
 355|     v_ok := v_ok + 1;
 356|   end;
 357|   update private.celulares_estado
 358|      set minuto_desde = date_trunc('minute', clock_timestamp()) - interval '1 minute', envios_minuto = 30
 359|    where asignacion_id = v_c4;
 360|   v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
 361|   if v_r <> aceptado or (select envios_minuto from private.celulares_estado where asignacion_id = v_c4) <> 1 then
 362|     raise exception 'ORACULO G2: pasado el minuto, el contador no volvió a cero (%)', v_r;
 363|   end if;
 364|   -- Medianoche de Lima: el día guardado adelante no retrocede; uno pasado vuelve a cero.
 365|   update private.celulares_estado
 366|      set dia = (clock_timestamp() at time zone 'America/Lima')::date + 1, envios_dia = 600, minuto_desde = null, envios_minuto = 0
 367|    where asignacion_id = v_c4;
 368|   begin
 369|     perform pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099'));
 370|     raise exception 'ORACULO G3: con el día guardado adelante y agotado, el envío pasó';
 371|   exception when sqlstate 'P0429' then
 372|     get stacked diagnostics v_msg = message_text, v_det = pg_exception_detail;
 373|     if v_msg not like '%del día%' or coalesce(substring(v_det from '^reintentar_en_seg=([0-9]+)$')::integer, 0) < 1 then
 374|       raise exception 'ORACULO G3: freno diario mal dicho (%, %)', v_msg, v_det;
 375|     end if;
 376|     v_ok := v_ok + 1;
 377|   end;
 378|   update private.celulares_estado
 379|      set dia = (clock_timestamp() at time zone 'America/Lima')::date - 1, envios_dia = 600
 380|    where asignacion_id = v_c4;
 381|   v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000099'));
 382|   if v_r <> aceptado or (select envios_dia from private.celulares_estado where asignacion_id = v_c4) <> 1 then
 383|     raise exception 'ORACULO G4: pasada la medianoche de Lima, el día no volvió a cero (%)', v_r;
 384|   end if;
 385|   t0 := t0 + 2;
 386|   -- Sin política: error claro (se borra y se repone dentro de un bloque que se deshace).
 387|   begin
 388|     execute 'set local session_replication_role = replica';
 389|     delete from crm.llamadas_celular_politica;
 390|     execute 'set local session_replication_role = origin';
 391|     begin
 392|       perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000099'));
 393|       raise exception 'ORACULO G5: sin política, el envío pasó';
 394|     exception when sqlstate '55000' then
 395|       if sqlerrm not like 'Falta la política%' then raise exception 'ORACULO G5: sin política, error poco claro (%)', sqlerrm; end if;
 396|     end;
 397|     raise exception using errcode = 'P9999', message = 'deshacer';
 398|   exception when sqlstate 'P9999' then v_ok := v_ok + 1;
 399|   end;
 400|   if (select count(*) from crm.llamadas_celular_politica) <> 1 then raise exception 'ORACULO G6: la política no se repuso'; end if;
 401|   update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
 402| 
 403|   -- ═════ H. Identidad: vuelve a la anterior en éxito y en error, también dentro de un bloque que atrapa 22023 ═════
 404|   if coalesce(current_setting('request.jwt.claim.sub', true), '') <> '' then
 405|     raise exception 'ORACULO H1: la ingesta dejó puesta una identidad';
 406|   end if;
 407|   perform set_config('request.jwt.claim.sub', g1::text, true);
 408|   v_r := to_jsonb(private.llamada_celular_candidatos_dueno(b1, array['+51900000006'], clock_timestamp()));
 409|   if current_setting('request.jwt.claim.sub', true) is distinct from g1::text or jsonb_array_length(v_r) <> 2 then
 410|     raise exception 'ORACULO H2: los candidatos del supervisor no se evaluaron como él o la identidad no volvió (%)', v_r;
 411|   end if;
 412|   begin
 413|     perform private.llamada_celular_candidatos_dueno(b1, array['+51900000006'], clock_timestamp());
 414|     raise exception using errcode = '22023', message = 'marca';
 415|   exception when sqlstate '22023' then
 416|     if current_setting('request.jwt.claim.sub', true) is distinct from g1::text then
 417|       raise exception 'ORACULO H3: tras un 22023 la identidad no es la anterior';
 418|     end if;
 419|   end;
 420|   perform set_config('request.jwt.claim.sub', '', true);
 421|   if exists (select 1 from public.audit_log l where l.tabla = 'crm.llamadas_celular_eventos' and l.usuario_id is not null
 422|                and l.operacion = 'INSERT') then
 423|     raise exception 'ORACULO H4: la bitácora atribuyó una llamada ingerida a una persona';
 424|   end if;
 425|   if exists (select 1 from public.audit_log l where l.tabla = 'crm.llamadas_celular_eventos'
 426|                and (l.data_despues ? 'hash_payload' or l.data_despues ->> 'numero_canonico' <> '***')) then
 427|     raise exception 'ORACULO H5: la bitácora muestra el número o un hash';
 428|   end if;
 429| 
 430|   -- ═════ I. Lead borrado: nadie la ve ni la toca, gerencia incluida ═════
 431|   t0 := t0 + 1;
 432|   perform pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000002'));
 433|   v_e4 := (pg_temp.evento('C4-' || t0)).id;
 434|   if v_e4 is null or not pg_temp.ve(g1, v_e4) then raise exception 'ORACULO I1: falta la llamada a c2'; end if;
 435|   update crm.leads set activo = false where id = c2;
 436|   if pg_temp.ve(g1, v_e4) or pg_temp.ve(b1, v_e4) or pg_temp.ve(a1, v_e4) then
 437|     raise exception 'ORACULO I2: alguien ve la llamada de un lead dado de baja';
 438|   end if;
 439|   begin
 440|     perform pg_temp.como(g1);
 441|     perform crm.llamada_celular_detalle_fn(v_e4);
 442|     raise exception 'ORACULO I3: gerencia lee el detalle de la llamada de un lead dado de baja';
 443|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 444|   begin
 445|     perform pg_temp.como(g1);
 446|     perform crm.descartar_llamada_celular(v_e4, 'personal');
 447|     raise exception 'ORACULO I4: gerencia descarta la llamada de un lead dado de baja';
 448|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 449|   update crm.leads set activo = true where id = c2;
 450| 
 451|   -- ═════ J. Entrantes y desconocidas se ignoran; la perilla está bloqueada ═════
 452|   t0 := t0 + 1;
 453|   v_r := pg_temp.enviar(k4, pg_temp.ev('C4-' || t0, '900000001', '{"direccion": "entrante", "estado_tecnico": "no_atendida"}'));
 454|   v_r2 := pg_temp.enviar(k4, pg_temp.ev('C4-' || (t0 + 1), '900000001') - 'direccion');
 455|   if v_r <> aceptado or v_r2 <> aceptado
 456|      or exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id in ('C4-' || t0, 'C4-' || (t0 + 1))) then
 457|     raise exception 'ORACULO J1: una entrante o una dirección desconocida se guardó (%, %)', v_r, v_r2;
 458|   end if;
 459|   t0 := t0 + 2;
 460|   begin
 461|     perform pg_temp.como(g1);
 462|     perform crm.fijar_politica_llamadas_celular(p_entrantes_activas => true);
 463|     raise exception 'ORACULO J2: gerencia encendió las entrantes';
 464|   exception when sqlstate '22023' then v_ok := v_ok + 1; end;
 465|   begin
 466|     update crm.llamadas_celular_politica set entrantes_activas = true;
 467|     raise exception 'ORACULO J3: la tabla aceptó las entrantes encendidas';
 468|   exception when check_violation then v_ok := v_ok + 1; end;
 469| 
 470|   -- ═════ K. Salud sin envíos; la bandeja vieja ya no existe; la puerta solo devuelve resultado y mensaje ═════
 471|   perform pg_temp.como(g1); v_salud := crm.celulares_salud_fn(); perform pg_temp.yo();
 472|   if exists (select 1 from jsonb_array_elements(v_salud) x where x ? 'envios_hoy' or x ? 'ultimo_envio_en')
 473|      or not exists (select 1 from jsonb_array_elements(v_salud) x where x ->> 'etiqueta' = 'C4' and x ? 'ultimo_latido_en') then
 474|     raise exception 'ORACULO K1: la salud muestra envíos o perdió el latido (%)', v_salud;
 475|   end if;
 476|   if to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is not null then
 477|     raise exception 'ORACULO K2: la bandeja duplicada sigue';
 478|   end if;
 479| 
 480|   -- ═════ L. Candados en un solo hilo: descartar revalida; enlazar rechaza un resultado deshecho ═════
 481|   v_ev := pg_temp.evento((select evento_origen_id from crm.llamadas_celular_eventos where id = v_e1));
 482|   insert into crm.actividades (lead_id, tipo, metadata, creado_por)
 483|   values (c1, 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
 484|           'deshecho_en', now()), a1)
 485|   returning id into v_act2;
 486|   begin
 487|     perform pg_temp.como(a1);
 488|     perform crm.enlazar_llamada_celular(v_e1, v_act2);
 489|     raise exception 'ORACULO L1: se enlazó un resultado deshecho';
 490|   exception when sqlstate '22023' then
 491|     if sqlerrm not like '%se deshizo%' then raise exception 'ORACULO L1: rechazo con otro motivo (%)', sqlerrm; end if;
 492|     v_ok := v_ok + 1;
 493|   end;
 494|   -- La regla de los 10 minutos sigue en el enlace manual: un resultado de 1 hora antes de la llamada no se enlaza.
 495|   insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
 496|   values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1, now() - interval '1 hour')
 497|   returning id into v_act;
 498|   begin
 499|     perform pg_temp.como(a1);
 500|     perform crm.enlazar_llamada_celular(v_e1, v_act);
 501|     raise exception 'ORACULO L3: se enlazó a mano un resultado anterior a la llamada';
 502|   exception when sqlstate '22023' then
 503|     if sqlerrm not like '%antes de la llamada%' then raise exception 'ORACULO L3: rechazo con otro motivo (%)', sqlerrm; end if;
 504|     v_ok := v_ok + 1;
 505|   end;
 506|   perform pg_temp.como(a1);
 507|   v_r := crm.descartar_llamada_celular(v_e1, 'personal');
 508|   perform pg_temp.yo();
 509|   if (select atencion from crm.llamadas_celular_eventos where id = v_e1) is distinct from 'descartado_con_motivo' then
 510|     raise exception 'ORACULO L2: descartar no funcionó (%)', v_r;
 511|   end if;
 512| 
 513|   -- ═════ M. Purga: 30 días sin enlace, registradas se quedan, descartadas por su plazo, recepciones a 32 ═════
 514|   delete from public.audit_log;  -- solo para contar lo que la purga deja en la bitácora
 515|   insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en) values
 516|     (c3, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a2, now() - interval '100 days')
 517|   returning id into v_act;
 518|   insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en) values
 519|     (c3, 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
 520|       'deshecho_en', now() - interval '99 days'), a2, now() - interval '100 days')
 521|   returning id into v_act2;
 522|   insert into crm.llamadas_celular_eventos (asignacion_id, analista_id, evento_origen_id, numero_canonico, direccion,
 523|       recibido_en, identificacion, atencion, lead_id, metodo_asociacion, asociado_en, motivo_descarte, descartado_en, descartado_por)
 524|   values
 525|     (v_c4, b1, 'C4-1000000001', '+51900000003', 'saliente', now() - interval '31 days', 'identificado', 'por_revisar', c3, 'exacto', now(), null, null, null),
 526|     (v_c4, b1, 'C4-1000000002', '+51900000001', 'saliente', now() - interval '29 days', 'identificado', 'requiere_resultado', c1, 'exacto', now(), null, null, null),
 527|     (v_c4, b1, 'C4-1000000003', '+51900000006', 'saliente', now() - interval '31 days', 'ambiguo', 'por_revisar', null, null, null, null, null, null),
 528|     (v_c4, b1, 'C4-1000000004', '+51900000003', 'saliente', now() - interval '100 days', 'identificado', 'registrado', c3, 'exacto', now(), null, null, null),
 529|     (v_c4, b1, 'C4-1000000005', '+51900000003', 'saliente', now() - interval '100 days', 'identificado', 'registrado', c3, 'exacto', now(), null, null, null),
 530|     (v_c4, b1, 'C4-1000000006', '+51900000003', 'saliente', now() - interval '40 days', 'identificado', 'descartado_con_motivo', c3, 'exacto', now(), 'personal', now() - interval '31 days', b1),
 531|     (v_c4, b1, 'C4-1000000007', '+51900000003', 'saliente', now() - interval '40 days', 'identificado', 'descartado_con_motivo', c3, 'exacto', now(), 'personal', now() - interval '5 days', b1);
 532|   insert into crm.llamadas_celular_enlaces (evento_id, actividad_id, lead_id, enlazado_por)
 533|   select e.id, case e.evento_origen_id when 'C4-1000000004' then v_act else v_act2 end, c3, a2
 534|   from crm.llamadas_celular_eventos e where e.evento_origen_id in ('C4-1000000004', 'C4-1000000005');
 535|   insert into private.llamadas_celular_recepciones (evento_origen_id, asignacion_id, recibido_en) values
 536|     ('C4-1000000011', v_c4, now() - interval '33 days'), ('C4-1000000012', v_c4, now() - interval '31 days');
 537|   select count(*) into v_n from crm.llamadas_celular_eventos;
 538|   v_n2 := private.caducar_llamadas_celular();
 539|   if v_n2 <> 4 then raise exception 'ORACULO M1: la purga retiró % filas, se esperaban 4 (2 sin resolver, 1 descartada, 1 recepción)', v_n2; end if;
 540|   if exists (select 1 from crm.llamadas_celular_eventos where evento_origen_id in ('C4-1000000001', 'C4-1000000003', 'C4-1000000006'))
 541|      or (select count(*) from crm.llamadas_celular_eventos
 542|          where evento_origen_id in ('C4-1000000002', 'C4-1000000004', 'C4-1000000005', 'C4-1000000007')) <> 4
 543|      or (select count(*) from crm.llamadas_celular_eventos) <> v_n - 3 then
 544|     raise exception 'ORACULO M2: la purga no respetó los plazos (sin resolver 30 días; registradas, aunque deshechas, se quedan)';
 545|   end if;
 546|   if exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000011')
 547|      or not exists (select 1 from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000012') then
 548|     raise exception 'ORACULO M3: la purga no retiró la recepción de 33 días o se llevó la de 31 (liberaría un id dentro de la ventana)';
 549|   end if;
 550|   if (select count(*) from public.audit_log where tabla = 'crm.llamadas_celular_eventos' and operacion = 'DELETE'
 551|         and data_antes ->> 'numero_canonico' = '***') <> 3 then
 552|     raise exception 'ORACULO M4: la purga no dejó su rastro enmascarado en la bitácora';
 553|   end if;
 554|   if coalesce(current_setting('crm.op_purga_llamadas', true), 'off') <> 'off' then
 555|     raise exception 'ORACULO M5: la purga dejó el GUC encendido';
 556|   end if;
 557|   begin
 558|     delete from private.llamadas_celular_recepciones where evento_origen_id = 'C4-1000000012';
 559|     raise exception 'ORACULO M6: una recepción se borró a mano';
 560|   exception when insufficient_privilege then
 561|     if sqlerrm not like '%no se borra a mano%' then raise exception 'ORACULO M6: el borrado se frenó por otra regla (%)', sqlerrm; end if;
 562|     v_ok := v_ok + 1;
 563|   end;
 564|   begin
 565|     update private.llamadas_celular_recepciones set recibido_en = now() where evento_origen_id = 'C4-1000000012';
 566|     raise exception 'ORACULO M7: una recepción se editó';
 567|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 568| 
 569|   if v_ok <> 13 then raise exception 'ORACULO: % de 13 rechazos esperados', v_ok; end if;
 570|   raise notice 'ORACULO CORRECCION OK: sin pistas, bolsa, reutilizables, propios terminales, id (forma, etiqueta, ventana, reenvío, rotación, etiqueta reutilizada), latido y fecha estricta, cupo (ventanas que no retroceden, sin política), identidad, lead borrado, entrantes bloqueadas, salud sin envíos, candados en un hilo y purga comprobados';
 571| end;
 572| $oraculo$;
 573| 
 574| rollback;
```

## Archivo: supabase/tests/llamadas-celular/oraculo-enlace-exacto.sql (322 líneas) — oráculo de F4-a
```
   1| -- Oráculo de F4-a (20261005155914, enlace exacto encuesta ↔ llamada) sobre el banco REDUCIDO de
   2| -- supabase/tests/llamadas-celular/base.sql, con la v4 como DOBLE declarado (base.sql). Se corre como dueño después de
   3| -- las cinco y F4-a; todo en una transacción que termina en ROLLBACK. Cubre: sin id = v4; aviso antes y aviso tardío
   4| -- (intención cumplida por la ingesta); reloj adelantado (sin la regla de los 10 minutos en el camino exacto, que sigue
   5| -- en el manual); los enlaces imposibles guardan igual el resultado con su motivo; Deshacer → corregido (enlace e
   6| -- intención pasan al corregido); la intención que no coincide se retira sin unir; la vía; los candados de la
   7| -- intención; la purga a 32 días y la autorización. Las carreras van en la pasada de concurrencia del guion.
   8| -- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia.
   9| -- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción (y la v4 real).
  10| begin;
  11| set local lock_timeout = '5s';
  12| set local statement_timeout = '120s';
  13| 
  14| create function pg_temp.ev(p_id text, p_numero text, p_extra jsonb default '{}'::jsonb)
  15| returns jsonb language sql immutable as $$
  16|   select jsonb_build_object('v', 1, 'evento_origen_id', p_id, 'numero', p_numero, 'direccion', 'saliente') || p_extra
  17| $$;
  18| create function pg_temp.enviar(p_clave text, p_evento jsonb)
  19| returns jsonb language plpgsql as $$
  20| declare v jsonb;
  21| begin
  22|   perform set_config('request.jwt.claim.sub', '', true);
  23|   execute 'set local role service_role';
  24|   v := crm.ingerir_llamada_celular_servicio(p_clave, p_evento);
  25|   execute 'set local role none';
  26|   return v;
  27| end $$;
  28| create function pg_temp.v5(p_actor uuid, p_op uuid, p_lead uuid, p_resultado text, p_origen text, p_via text)
  29| returns jsonb language plpgsql as $$
  30| declare v jsonb;
  31| begin
  32|   perform set_config('request.jwt.claim.sub', p_actor::text, true);
  33|   execute 'set local role authenticated';
  34|   v := crm.registrar_llamada_v5(p_op, p_lead, p_resultado, null, null, null, null, false, false, p_origen, p_via);
  35|   execute 'set local role none';
  36|   perform set_config('request.jwt.claim.sub', '', true);
  37|   return v;
  38| end $$;
  39| create function pg_temp.evento(p_id text)
  40| returns crm.llamadas_celular_eventos language sql as $$
  41|   select * from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
  42| $$;
  43| create function pg_temp.deshacer(p_act uuid)
  44| returns void language sql as $$
  45|   update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = p_act
  46| $$;
  47| create function pg_temp.enlace_de(p_id text)
  48| returns crm.llamadas_celular_enlaces language sql as $$
  49|   select l.* from crm.llamadas_celular_enlaces l join crm.llamadas_celular_eventos e on e.id = l.evento_id
  50|   where e.evento_origen_id = p_id
  51| $$;
  52| 
  53| do $oraculo$
  54| declare
  55|   a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  56|   a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  57|   a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  58|   b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  59|   g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  60|   c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  61|   c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  62|   c6 constant uuid := '00000000-0000-0000-0000-0000000000c6';
  63|   t0 bigint := floor(extract(epoch from now()))::bigint - 50000;
  64|   k1 text; k2 text; k4 text;
  65|   v_r jsonb;
  66|   v_ev crm.llamadas_celular_eventos%rowtype;
  67|   v_enl crm.llamadas_celular_enlaces%rowtype;
  68|   op uuid[] := array(select gen_random_uuid() from generate_series(1, 25));
  69|   v_act uuid; v_act2 uuid;
  70|   v_id text; v_id2 text;
  71|   v_n integer;
  72|   v_ok integer := 0;
  73|   id_de constant text := 'C1-';
  74| begin
  75|   -- ═════ Preparación ═════
  76|   update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
  77|   perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  78|   k1 := crm.asignar_celular('C1', a1) ->> 'credencial';
  79|   k2 := crm.asignar_celular('C2', a3) ->> 'credencial';
  80|   k4 := crm.asignar_celular('C4', b1) ->> 'credencial';
  81|   execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
  82| 
  83|   -- ═════ A. Sin id: igual que la v4, con enlace null ═════
  84|   v_r := pg_temp.v5(a1, op[1], c1, 'volver_a_llamar', null, null);
  85|   if not (v_r ? 'enlace') or jsonb_typeof(v_r -> 'enlace') <> 'null' or (v_r ->> 'actividad_id')::uuid <> op[1]
  86|      or not exists (select 1 from crm.actividades where id = op[1]) then
  87|     raise exception 'ORACULO A1: sin id, la v5 no se comportó como la v4 (%)', v_r;
  88|   end if;
  89| 
  90|   -- ═════ B. El aviso llegó antes: la encuesta lo une al colgar; el replay no duplica ═════
  91|   v_id := id_de || (t0 + 1);
  92|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  93|   v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', v_id, 'al_colgar');
  94|   v_enl := pg_temp.enlace_de(v_id);
  95|   if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' or v_enl.actividad_id is distinct from op[2] or v_enl.via is distinct from 'al_colgar'
  96|      or (pg_temp.evento(v_id)).atencion is distinct from 'registrado' then
  97|     raise exception 'ORACULO B1: con el aviso ya llegado, la encuesta no quedó unida al colgar (%, %)', v_r, row_to_json(v_enl);
  98|   end if;
  99|   v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', v_id, 'al_colgar');
 100|   if v_r -> 'enlace' ->> 'estado' is distinct from 'repetido' or (v_r ->> 'replay')::boolean is not true
 101|      or (select count(*) from crm.llamadas_celular_enlaces) <> 1 then
 102|     raise exception 'ORACULO B2: el reintento de la encuesta no respondió «repetido» o duplicó (%)', v_r;
 103|   end if;
 104| 
 105|   -- ═════ C. Reloj del celular adelantado: el camino exacto une; el manual conserva la regla de 10 minutos ═════
 106|   v_id := id_de || floor(extract(epoch from now() + interval '20 minutes'))::bigint;
 107|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002',
 108|     jsonb_build_object('ocurrio_en', to_char(now() + interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
 109|   v_r := pg_temp.v5(a1, op[3], c2, 'volver_a_llamar', v_id, 'al_colgar');
 110|   if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then
 111|     raise exception 'ORACULO C1: con el reloj adelantado el enlace exacto se rechazó (%)', v_r;
 112|   end if;
 113|   v_id := id_de || (floor(extract(epoch from now() + interval '20 minutes'))::bigint + 1);
 114|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000006',
 115|     jsonb_build_object('ocurrio_en', to_char(now() + interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
 116|   insert into crm.actividades (lead_id, tipo, metadata, creado_por)
 117|   values (c6, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
 118|   v_ev := pg_temp.evento(v_id);
 119|   begin
 120|     perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
 121|     perform crm.enlazar_llamada_celular(v_ev.id, v_act);
 122|     raise exception 'ORACULO C2: el enlace manual perdió la regla de los 10 minutos';
 123|   exception when sqlstate '22023' then
 124|     if sqlerrm not like '%antes de la llamada%' then raise exception 'ORACULO C2: rechazo con otro motivo (%)', sqlerrm; end if;
 125|     v_ok := v_ok + 1;
 126|   end;
 127| 
 128|   -- ═════ D. Aviso tardío: la encuesta deja una intención y la ingesta la cumple sola ═════
 129|   v_id := id_de || (t0 + 4);
 130|   v_r := pg_temp.v5(a1, op[4], c1, 'no_contesto', v_id, 'pestana');
 131|   if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente'
 132|      or not exists (select 1 from private.llamadas_celular_intenciones
 133|                     where evento_origen_id = v_id and actividad_id = op[4] and via = 'pestana' and analista_id = a1) then
 134|     raise exception 'ORACULO D1: sin aviso, la encuesta no dejó su intención (%)', v_r;
 135|   end if;
 136|   v_r := pg_temp.v5(a1, op[4], c1, 'no_contesto', v_id, 'pestana');
 137|   if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente' or (select count(*) from private.llamadas_celular_intenciones) <> 1 then
 138|     raise exception 'ORACULO D2: el reintento con la intención pendiente no respondió «pendiente» (%)', v_r;
 139|   end if;
 140|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
 141|   v_enl := pg_temp.enlace_de(v_id);
 142|   if v_enl.actividad_id is distinct from op[4] or v_enl.via is distinct from 'pestana' or v_enl.enlazado_por is distinct from a1
 143|      or (pg_temp.evento(v_id)).atencion is distinct from 'registrado'
 144|      or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
 145|     raise exception 'ORACULO D3: al llegar el aviso, la intención no se cumplió (%)', row_to_json(v_enl);
 146|   end if;
 147| 
 148|   -- ═════ E. Enlaces imposibles: el resultado se guarda IGUAL y la respuesta dice por qué ═════
 149|   v_r := pg_temp.v5(a1, op[5], c1, 'volver_a_llamar', 'X1-123', 'al_colgar');
 150|   if v_r -> 'enlace' ->> 'estado' is distinct from 'no_enlazado' or v_r -> 'enlace' ->> 'motivo' is distinct from 'id_invalido'
 151|      or not exists (select 1 from crm.actividades where id = op[5]) then
 152|     raise exception 'ORACULO E1: un id mal formado no guardó el resultado o no dio su motivo (%)', v_r;
 153|   end if;
 154|   v_r := pg_temp.v5(a1, op[6], c1, 'volver_a_llamar', id_de || floor(extract(epoch from now() - interval '31 days'))::bigint, 'al_colgar');
 155|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'id_invalido' then raise exception 'ORACULO E2: un id fuera de la ventana se aceptó (%)', v_r; end if;
 156|   v_r := pg_temp.v5(a1, op[7], c1, 'volver_a_llamar', 'C2-' || (t0 + 7), 'al_colgar');
 157|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'celular_ajeno' then raise exception 'ORACULO E3: el id del celular de otro analista se aceptó (%)', v_r; end if;
 158|   v_id := id_de || (t0 + 8);
 159|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
 160|   v_r := pg_temp.v5(a1, op[8], c1, 'volver_a_llamar', v_id, 'al_colgar');
 161|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'otro_lead' or (pg_temp.evento(v_id)).atencion is distinct from 'requiere_resultado' then
 162|     raise exception 'ORACULO E4: la llamada de otro lead se unió (%)', v_r;
 163|   end if;
 164|   v_id := id_de || (t0 + 9);
 165|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
 166|   v_ev := pg_temp.evento(v_id);
 167|   perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
 168|   perform crm.descartar_llamada_celular(v_ev.id, 'personal');
 169|   execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
 170|   v_r := pg_temp.v5(a1, op[9], c1, 'volver_a_llamar', v_id, 'al_colgar');
 171|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'descartada' then raise exception 'ORACULO E5: se unió una llamada descartada (%)', v_r; end if;
 172|   v_r := pg_temp.v5(a1, op[10], c1, 'volver_a_llamar', id_de || (t0 + 1), 'al_colgar');
 173|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'ya_tiene_resultado' or not exists (select 1 from crm.actividades where id = op[10]) then
 174|     raise exception 'ORACULO E6: un segundo resultado reemplazó al vigente (%)', v_r;
 175|   end if;
 176|   -- Ambigua (900000006 es de c6 y c7, los dos del equipo de b1): no se une por este camino; va a la pestaña.
 177|   v_id := 'C4-' || (t0 + 11);
 178|   perform pg_temp.enviar(k4, pg_temp.ev(v_id, '900000006'));
 179|   v_r := pg_temp.v5(b1, op[11], c6, 'volver_a_llamar', v_id, 'al_colgar');
 180|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'otro_lead' or (pg_temp.evento(v_id)).identificacion is distinct from 'ambiguo' then
 181|     raise exception 'ORACULO E7: la ambigua se unió por el camino exacto (%)', v_r;
 182|   end if;
 183|   -- El aviso llegó y se ignoró (entrante): no se guarda intención, nunca se cumpliría.
 184|   v_id := id_de || (t0 + 12);
 185|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001', '{"direccion": "entrante"}'));
 186|   v_r := pg_temp.v5(a1, op[12], c1, 'volver_a_llamar', v_id, 'al_colgar');
 187|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'sin_llamada' or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
 188|     raise exception 'ORACULO E8: con el aviso ignorado se guardó una intención (%)', v_r;
 189|   end if;
 190|   -- El mismo resultado (replay) con otro id: ya está unido a otra llamada.
 191|   v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', id_de || (t0 + 13), 'al_colgar');
 192|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'resultado_ya_enlazado' then
 193|     raise exception 'ORACULO E9: un resultado ya unido se dejó como intención de otra llamada (%)', v_r;
 194|   end if;
 195| 
 196|   -- Una segunda encuesta con el mismo id y la primera pendiente (no deshecha): no la reemplaza.
 197|   v_id := id_de || (t0 + 22);
 198|   perform pg_temp.v5(a1, op[21], c1, 'volver_a_llamar', v_id, 'al_colgar');
 199|   v_r := pg_temp.v5(a1, op[22], c1, 'volver_a_llamar', v_id, 'pestana');
 200|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'ya_tiene_resultado'
 201|      or (select actividad_id from private.llamadas_celular_intenciones where evento_origen_id = v_id) <> op[21] then
 202|     raise exception 'ORACULO E10: una segunda encuesta reemplazó la intención vigente (%)', v_r;
 203|   end if;
 204| 
 205|   -- ═════ F. Deshacer → corregido: el enlace y la intención pasan al resultado corregido ═════
 206|   perform pg_temp.deshacer(op[2]);
 207|   v_r := pg_temp.v5(a1, op[13], c1, 'volver_a_llamar', id_de || (t0 + 1), 'al_colgar');
 208|   v_enl := pg_temp.enlace_de(id_de || (t0 + 1));
 209|   if v_r -> 'enlace' ->> 'estado' is distinct from 'movido' or v_enl.actividad_id is distinct from op[13] or v_enl.via is distinct from 'al_colgar' then
 210|     raise exception 'ORACULO F1: el enlace no pasó al resultado corregido (%, %)', v_r, row_to_json(v_enl);
 211|   end if;
 212|   v_id := id_de || (t0 + 14);
 213|   perform pg_temp.v5(a1, op[14], c2, 'volver_a_llamar', v_id, 'al_colgar');
 214|   perform pg_temp.deshacer(op[14]);
 215|   v_r := pg_temp.v5(a1, op[15], c2, 'volver_a_llamar', v_id, 'al_colgar');
 216|   if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente'
 217|      or (select actividad_id from private.llamadas_celular_intenciones where evento_origen_id = v_id) <> op[15] then
 218|     raise exception 'ORACULO F2: la intención no pasó al resultado corregido (%)', v_r;
 219|   end if;
 220|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
 221|   if (pg_temp.enlace_de(v_id)).actividad_id is distinct from op[15] then
 222|     raise exception 'ORACULO F3: el aviso no se unió al resultado corregido';
 223|   end if;
 224|   v_r := pg_temp.v5(a1, op[14], c2, 'volver_a_llamar', v_id, 'al_colgar');
 225|   if v_r -> 'enlace' ->> 'motivo' is distinct from 'resultado_deshecho' then
 226|     raise exception 'ORACULO F4: el reintento de un resultado deshecho se unió (%)', v_r;
 227|   end if;
 228| 
 229|   -- ═════ G. La intención que no coincide se retira sin unir ═════
 230|   v_id := id_de || (t0 + 16);
 231|   perform pg_temp.v5(a1, op[16], c1, 'volver_a_llamar', v_id, 'al_colgar');
 232|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
 233|   v_ev := pg_temp.evento(v_id);
 234|   if v_ev.lead_id is distinct from c2 or v_ev.atencion is distinct from 'requiere_resultado' or pg_temp.enlace_de(v_id) is not null
 235|      or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
 236|     raise exception 'ORACULO G1: la intención de otro lead se cumplió o no se retiró (%)', row_to_json(v_ev);
 237|   end if;
 238|   v_id := id_de || (t0 + 17);
 239|   perform pg_temp.v5(a1, op[17], c1, 'volver_a_llamar', v_id, 'al_colgar');
 240|   perform pg_temp.deshacer(op[17]);
 241|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
 242|   if (pg_temp.evento(v_id)).atencion is distinct from 'requiere_resultado' or pg_temp.enlace_de(v_id) is not null
 243|      or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
 244|     raise exception 'ORACULO G2: la intención con el resultado deshecho se cumplió o no se retiró';
 245|   end if;
 246| 
 247|   -- ═════ H. La vía: manual en el enlace a mano; inmutable ═════
 248|   v_id := id_de || (t0 + 18);
 249|   perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
 250|   insert into crm.actividades (lead_id, tipo, metadata, creado_por)
 251|   values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
 252|   v_ev := pg_temp.evento(v_id);
 253|   perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
 254|   perform crm.enlazar_llamada_celular(v_ev.id, v_act);
 255|   execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
 256|   if (pg_temp.enlace_de(v_id)).via is distinct from 'manual' then raise exception 'ORACULO H1: el enlace manual no quedó con vía «manual»'; end if;
 257|   begin
 258|     update crm.llamadas_celular_enlaces set via = 'al_colgar' where id = (pg_temp.enlace_de(v_id)).id;
 259|     raise exception 'ORACULO H2: la vía de un enlace cambió';
 260|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 261| 
 262|   -- ═════ I. Validaciones de la v5 (fallan sin guardar nada) y autorización ═════
 263|   begin
 264|     perform pg_temp.v5(a1, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), null);
 265|     raise exception 'ORACULO I1: con id y sin vía, la v5 guardó';
 266|   exception when sqlstate '22023' then v_ok := v_ok + 1; end;
 267|   begin
 268|     perform pg_temp.v5(a1, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), 'manual');
 269|     raise exception 'ORACULO I2: la v5 aceptó la vía «manual»';
 270|   exception when sqlstate '22023' then v_ok := v_ok + 1; end;
 271|   begin
 272|     perform pg_temp.v5(a2, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), 'al_colgar');
 273|     raise exception 'ORACULO I3: la v5 registró por un lead fuera de ámbito';
 274|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 275|   if exists (select 1 from crm.actividades where id = op[19]) then
 276|     raise exception 'ORACULO I4: una v5 rechazada dejó un resultado';
 277|   end if;
 278| 
 279|   -- ═════ J. Candados de la intención ═════
 280|   v_id := id_de || (t0 + 20);
 281|   perform pg_temp.v5(a1, op[20], c1, 'volver_a_llamar', v_id, 'al_colgar');
 282|   begin
 283|     delete from private.llamadas_celular_intenciones where evento_origen_id = v_id;
 284|     raise exception 'ORACULO J1: una intención se borró a mano';
 285|   exception when insufficient_privilege then
 286|     if sqlerrm not like '%no se borra a mano%' then raise exception 'ORACULO J1: frenado por otra regla (%)', sqlerrm; end if;
 287|     v_ok := v_ok + 1;
 288|   end;
 289|   begin
 290|     update private.llamadas_celular_intenciones set lead_id = c2 where evento_origen_id = v_id;
 291|     raise exception 'ORACULO J2: una intención cambió de lead';
 292|   exception when insufficient_privilege then v_ok := v_ok + 1; end;
 293|   begin
 294|     update private.llamadas_celular_intenciones set actividad_id = op[5] where evento_origen_id = v_id;
 295|     raise exception 'ORACULO J3: una intención pasó a otro resultado sin deshacer el anterior';
 296|   exception when insufficient_privilege then
 297|     if sqlerrm not like '%si el anterior se deshizo%' then raise exception 'ORACULO J3: frenado por otra regla (%)', sqlerrm; end if;
 298|     v_ok := v_ok + 1;
 299|   end;
 300| 
 301|   -- ═════ K. Purga: intenciones a los 32 días ═════
 302|   insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
 303|     (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
 304|   insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
 305|     (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act2;
 306|   insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via, creado_en) values
 307|     ('C1-1000000001', a1, c1, v_act, 'al_colgar', now() - interval '33 days'),
 308|     ('C1-1000000002', a1, c1, v_act2, 'al_colgar', now() - interval '31 days');
 309|   select count(*) into v_n from private.llamadas_celular_intenciones;
 310|   perform private.caducar_llamadas_celular();
 311|   if exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = 'C1-1000000001')
 312|      or not exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = 'C1-1000000002')
 313|      or (select count(*) from private.llamadas_celular_intenciones) <> v_n - 1 then
 314|     raise exception 'ORACULO K1: la purga no retiró solo la intención de más de 32 días';
 315|   end if;
 316| 
 317|   if v_ok <> 8 then raise exception 'ORACULO: % de 8 rechazos esperados', v_ok; end if;
 318|   raise notice 'ORACULO ENLACE EXACTO OK: sin id = v4, aviso antes, aviso tardío (intención cumplida), reloj adelantado (manual con 10 min), enlaces imposibles que guardan igual (id, ventana, celular ajeno, otro lead, descartada, ya con resultado, ambigua, aviso ignorado, resultado ya unido), Deshacer → corregido, intención que no coincide, vía, validaciones, candados y purga comprobados';
 319| end;
 320| $oraculo$;
 321| 
 322| rollback;
```

## Tramo: supabase/scripts/test-rls.mjs:17488–17891 — bloque testLlamadasCelular del gate (SIN CORRER)
```
17488| // Llamadas desde el celular: F2 + F3 + elegibilidad + QUINTA (20261005143843) + F4-a (20261005155914).
17489| // Especificación: F2-PLAN-CORTO.md («Verificación (F2.4)») y CORRECCION-PLAN-CORTO.md («Pruebas»). Purga, cupo con la
17490| // hora movida, carreras e identidad temporal van en los oráculos del banco reducido (supabase/tests/llamadas-celular/);
17491| // aquí: permisos, contrato y enlace con sesiones reales, la v4 REAL y el esquema de producción. Ya no exige P0409
17492| // (punto 22 de la revisión: exigirlo era exigir la fuga). Ids C<n>-<10 dígitos> desde una base al azar dentro de la
17493| // ventana de la quinta: no chocan con otra corrida. Las tablas son de solo inserción: los eventos de la corrida quedan
17494| // descartados o registrados, las asignaciones cerradas y los leads dados de baja; el branch se descarta.
17495| async function testLlamadasCelular(sessions, seed) {
17496|   console.log('\n— Llamadas desde el celular (F2 + F3 + quinta + F4-a): puertas, ámbito, ingesta y enlace —');
17497|   const id = (key) => seed.profileIdByKey[key];
17498|   const rpc = (quien, fn, args = {}) => sessions[quien].client.schema('crm').rpc(fn, args);
17499|   const servicio = (fn, args) => admin.schema('crm').rpc(fn, args);
17500|   const instalada = contarFueraDeBanda('Llamadas del celular: presencia de la migración',
17501|     "select case when to_regclass('crm.llamadas_celular_eventos') is not null then 1 else 0 end") === 1;
17502|   const corregida = instalada && contarFueraDeBanda('Llamadas del celular: quinta y F4-a',
17503|     "select case when to_regclass('private.llamadas_celular_recepciones') is not null and "
17504|     + "to_regclass('private.llamadas_celular_intenciones') is not null then 1 else 0 end") === 1;
17505|   const sonda = await rpc('gerencia', 'llamadas_celular_politica_fn');
17506|   const sondaServicio = await servicio('ingerir_llamada_celular_servicio', { p_credencial: '0'.repeat(64), p_evento: {} });
17507|   const sondaV5 = await rpc('gerencia', 'registrar_llamada_v5', { p_operacion_id: randomUUID(),
17508|     p_lead_id: '00000000-0000-4000-8000-000000000000', p_resultado: 'no_contesto' });
17509|   if (!instalada || !corregida || [sonda, sondaServicio, sondaV5].some((r) => r.error?.code === 'PGRST202')) {
17510|     const msg = instalada
17511|       ? '✗ Llamadas del celular: F2 + F3 sin la quinta o sin F4-a (o falta una puerta): la barrera no deja usarlas así'
17512|       : '⚠ Llamadas del celular no instaladas: SALTADAS (no probado)';
17513|     if (instalada || process.env.CRM_RLS_EXIGE_LLAMADAS === '1') fail(msg);
17514|     else console.log(`  ${msg}`);
17515|     return;
17516|   }
17517|   check(!sonda.error && sonda.data?.guardar_sin_identificar === false && sonda.data?.entrantes_activas === false,
17518|     'gerencia lee la política: números sin lead no se guardan y entrantes apagadas (decisiones 2 y 3)',
17519|     errorText(sonda.error));
17520|   check(sondaV5.error?.code === '42501', 'v5 sobre un lead inexistente → 42501, sin escribir', errorText(sondaV5.error));
17521| 
17522|   const ajeno = LEADS.find((l) => l.sellerKey === 'vend3');
17523|   const asignaciones = [];
17524|   const eventos = [];
17525|   const leads = [];
17526|   let claveNueva = null;
17527|   let rot = null;
17528|   let seq = 0;
17529|   const base = Math.floor(Date.now() / 1000) - randomInt(600, 7 * 86400);
17530|   const idDe = (etiqueta) => `${etiqueta}-${base + (seq += 1)}`;
17531|   const nuevoNumero = () => `9${randomInt(10000000, 99999999)}`;
17532|   // Lead transitorio de vend1 con un teléfono aleatorio: único en la base, así la coincidencia es exacta.
17533|   const numero = nuevoNumero();
17534|   const evento = (origen, extra = {}) => ({
17535|     v: 1, evento_origen_id: origen, numero, direccion: 'saliente', estado_tecnico: 'conectada',
17536|     duracion_seg: 42, ocurrio_en: new Date(Date.now() - 60_000).toISOString(), ...extra,
17537|   });
17538|   const ingerir = (credencial, ev) => servicio('ingerir_llamada_celular_servicio', { p_credencial: credencial, p_evento: ev });
17539|   const aceptado = (r) => !r.error && JSON.stringify(r.data) === '{"resultado":"aceptado"}';
17540|   const invalido = (r) => !r.error && r.data?.resultado === 'invalido' && Boolean(r.data?.mensaje)
17541|     && Object.keys(r.data).sort().join() === 'mensaje,resultado';
17542|   const q = (origen) => {
17543|     if (!/^[A-Za-z0-9-]+$/.test(origen)) throw new Error(`llamadas: id raro para la vía fuera de banda: ${origen}`);
17544|     return `'${origen}'`;
17545|   };
17546|   const cuenta = (que, sql) => contarFueraDeBanda(`llamadas: ${que}`, sql);
17547|   const recepciones = (o) => cuenta('recepciones', `select count(*) from private.llamadas_celular_recepciones where evento_origen_id = ${q(o)}`);
17548|   const eventosDe = (o) => cuenta('eventos', `select count(*) from crm.llamadas_celular_eventos where evento_origen_id = ${q(o)}`);
17549|   const intenciones = (o) => cuenta('intenciones', `select count(*) from private.llamadas_celular_intenciones where evento_origen_id = ${q(o)}`);
17550|   const eventoDe = (o) => {
17551|     const t = textoFueraDeBanda('llamadas: evento', `select concat_ws('|', e.id, e.atencion, coalesce(e.lead_id::text, ''),
17552|       e.asignacion_id) from crm.llamadas_celular_eventos e where e.evento_origen_id = ${q(o)}`);
17553|     if (!t) return null;
17554|     const [eid, atencion, leadId, asignacionId] = t.split('|');
17555|     return { id: eid, atencion, leadId, asignacionId };
17556|   };
17557|   const enlaceDe = (o) => textoFueraDeBanda('llamadas: enlace', `select concat_ws('|', l.actividad_id, l.via)
17558|     from crm.llamadas_celular_enlaces l join crm.llamadas_celular_eventos e on e.id = l.evento_id where e.evento_origen_id = ${q(o)}`);
17559|   const cupo = (asig) => (textoFueraDeBanda('llamadas: cupo', `select concat_ws('|', coalesce(dia::text, ''), envios_dia)
17560|     from private.celulares_estado where asignacion_id = '${asig}'`) ?? '|0').split('|');
17561|   async function asignar(quien) {
17562|     for (let intento = 0; intento < 3; intento += 1) {
17563|       const etiqueta = `C${randomInt(100, 1000)}`;
17564|       const r = await rpc('gerencia', 'asignar_celular', { p_etiqueta: etiqueta, p_analista_id: id(quien) });
17565|       if (r.error?.code === '23505') continue; // etiqueta vigente de otra corrida: otra al azar
17566|       if (r.error) throw new Error(`asignar celular a ${quien}: ${errorText(r.error)}`);
17567|       asignaciones.push(r.data.asignacion_id);
17568|       return { ...r.data, etiqueta };
17569|     }
17570|     throw new Error(`asignar celular a ${quien}: tres etiquetas ocupadas seguidas`);
17571|   }
17572|   const contiene = (data, eventoId) => (Array.isArray(data) ? data : data?.filas ?? []).some((f) => f.evento_id === eventoId);
17573|   const ve = async (quien, eventoId) => {
17574|     const b = await rpc(quien, 'llamadas_celular_bandeja_fn', { p_limite: 200 });
17575|     return b.error ? null : contiene(b.data, eventoId);
17576|   };
17577|   async function crearLead(nombre, telefono, vendedorKey) {
17578|     const leadId = randomUUID();
17579|     await requireAdmin(`crear ${nombre}`, admin.schema('crm').from('leads').insert({
17580|       id: leadId, nombre_completo: nombre, telefono, origen: 'oficina', etapa: 'nuevo', moneda: 'PEN', monto_estimado: 1000,
17581|       ...(vendedorKey ? { creado_por: id(vendedorKey), vendedor_id: id(vendedorKey), asignado_supervisor_id: null } : {}),
17582|     }));
17583|     leads.push(leadId);
17584|     return leadId;
17585|   }
17586| 
17587|   try {
17588|     const leadId = await crearLead('LLAMADAS CELULAR TRANSIENT', numero, 'vend1');
17589| 
17590|     // ── Tablas: sin acceso directo para nadie (todo pasa por las puertas); las de private, fuera de la API ──
17591|     const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-llamadas'));
17592|     for (const tabla of ['celulares_asignaciones', 'llamadas_celular_eventos', 'llamadas_celular_enlaces', 'llamadas_celular_politica']) {
17593|       for (const quien of ['vend1', 'sup1', 'gerencia', 'coordinador', 'directorio']) {
17594|         await expectExplicitAuthorizationDenied(`${quien}: no lee crm.${tabla} directo`,
17595|           sessions[quien].client.schema('crm').from(tabla).select('*').limit(1));
17596|       }
17597|       await expectExplicitAuthorizationDenied(`anon: no lee crm.${tabla}`, anon.schema('crm').from(tabla).select('*').limit(1));
17598|     }
17599|     for (const tabla of ['llamadas_celular_recepciones', 'llamadas_celular_intenciones', 'celulares_estado']) {
17600|       const { data, error } = await sessions.gerencia.client.schema('private').from(tabla).select('*').limit(1);
17601|       check(error?.code === 'PGRST106' && data == null,
17602|         `gerencia NO alcanza private.${tabla} por la API: esquema no expuesto, PGRST106 (recibido ${error?.code ?? 'sin error'})`);
17603|     }
17604|     for (const quien of ['vend1', 'gerencia']) {
17605|       await expectBlockedMutation(`${quien}: no actualiza eventos directo`,
17606|         sessions[quien].client.schema('crm').from('llamadas_celular_eventos').update({ atencion: 'registrado' })
17607|           .eq('lead_id', leadId).select('id'));
17608|       await expectBlockedMutation(`${quien}: no borra eventos directo`,
17609|         sessions[quien].client.schema('crm').from('llamadas_celular_eventos').delete().eq('lead_id', leadId).select('id'));
17610|     }
17611| 
17612|     // ── Puertas: quién ejecuta qué. Con argumentos de la forma exacta: sin ellos PostgREST responde
17613|     // PGRST202 (función no encontrada) y la prueba fallaría por la razón equivocada. La bandeja vieja
17614|     // (llamadas_celular_pendientes_fn) ya no existe: la quinta la retiró. ──
17615|     const argumentos = {
17616|       llamadas_celular_bandeja_fn: {},
17617|       llamada_celular_detalle_fn: { p_evento_id: randomUUID() },
17618|       asociar_llamada_celular: { p_evento_id: randomUUID(), p_lead_id: leadId },
17619|       enlazar_llamada_celular: { p_evento_id: randomUUID(), p_actividad_id: randomUUID() },
17620|       descartar_llamada_celular: { p_evento_id: randomUUID(), p_motivo: 'personal' },
17621|       registrar_llamada_v5: { p_operacion_id: randomUUID(), p_lead_id: leadId, p_resultado: 'no_contesto' },
17622|       celulares_asignaciones_fn: {},
17623|       celulares_salud_fn: {},
17624|       asignar_celular: { p_etiqueta: 'C999', p_analista_id: id('vend1') },
17625|       rotar_credencial_celular: { p_etiqueta: 'C999' },
17626|       cerrar_asignacion_celular: { p_asignacion_id: randomUUID(), p_motivo: 'otro' },
17627|       llamadas_celular_politica_fn: {},
17628|       fijar_politica_llamadas_celular: {},
17629|       ingerir_llamada_celular_servicio: { p_credencial: '0'.repeat(64), p_evento: evento('C1-0000000000') },
17630|       registrar_salud_celular_servicio: { p_credencial: '0'.repeat(64), p_latido: { v: 1, version_macro: 'gate', en_cola: 0 } },
17631|     };
17632|     const soloGerencia = ['asignar_celular', 'rotar_credencial_celular', 'cerrar_asignacion_celular',
17633|       'llamadas_celular_politica_fn', 'fijar_politica_llamadas_celular'];
17634|     for (const fn of soloGerencia) {
17635|       for (const quien of ['sup1', 'vend1', 'coordinador', 'directorio', 'vendInactive']) {
17636|         await expectExplicitAuthorizationDenied(`${quien}: ${fn} es solo de gerencia`, rpc(quien, fn, argumentos[fn]));
17637|       }
17638|     }
17639|     for (const fn of ['celulares_asignaciones_fn', 'celulares_salud_fn']) {
17640|       for (const quien of ['vend1', 'coordinador', 'directorio', 'vendInactive']) {
17641|         await expectExplicitAuthorizationDenied(`${quien}: ${fn} es de supervisión y gerencia`, rpc(quien, fn, argumentos[fn]));
17642|       }
17643|     }
17644|     for (const fn of ['llamadas_celular_bandeja_fn', 'llamada_celular_detalle_fn', 'asociar_llamada_celular',
17645|       'enlazar_llamada_celular', 'descartar_llamada_celular', 'registrar_llamada_v5']) {
17646|       for (const quien of ['coordinador', 'directorio', 'vendInactive']) {
17647|         await expectExplicitAuthorizationDenied(`${quien}: sin ${fn}`, rpc(quien, fn, argumentos[fn]));
17648|       }
17649|     }
17650|     for (const [fn, args] of Object.entries(argumentos)) {
17651|       await expectExplicitAuthorizationDenied(`anon: no ejecuta ${fn}`, anon.schema('crm').rpc(fn, args));
17652|     }
17653|     for (const fn of ['ingerir_llamada_celular_servicio', 'registrar_salud_celular_servicio']) {
17654|       for (const quien of ['vend1', 'sup1', 'gerencia']) {
17655|         await expectExplicitAuthorizationDenied(`${quien}: la puerta de servicio ${fn} es solo de service_role`,
17656|           rpc(quien, fn, argumentos[fn]));
17657|       }
17658|     }
17659| 
17660|     // ── Asignar celulares: solo gerencia; la clave sale una vez y no se vuelve a leer ──
17661|     const cel = await asignar('vend1');
17662|     check(/^[0-9a-f]{64}$/.test(cel.credencial ?? ''), 'gerencia asigna un celular a vend1: la clave sale una vez (64 hex)');
17663|     await expectExpectedFailure('gerencia: no asigna un celular a un analista dado de baja',
17664|       rpc('gerencia', 'asignar_celular', { p_etiqueta: `C${randomInt(100, 1000)}`, p_analista_id: id('vendInactive') }),
17665|       ['22023'], /activo/i);
17666|     await expectExpectedFailure('gerencia: etiqueta inválida rechazada',
17667|       rpc('gerencia', 'asignar_celular', { p_etiqueta: 'celular', p_analista_id: id('vend1') }), ['22023'], /etiqueta/i);
17668|     const lecturaG = await rpc('gerencia', 'celulares_asignaciones_fn');
17669|     check(!lecturaG.error && (lecturaG.data ?? []).some((a) => a.asignacion_id === cel.asignacion_id)
17670|       && !/[0-9a-f]{64}/.test(JSON.stringify(lecturaG.data)),
17671|     'gerencia ve la asignación y la lectura no expone ningún hash de clave', errorText(lecturaG.error));
17672|     const lecturaS1 = await rpc('sup1', 'celulares_asignaciones_fn');
17673|     const lecturaS2 = await rpc('sup2', 'celulares_asignaciones_fn');
17674|     check(!lecturaS1.error && (lecturaS1.data ?? []).some((a) => a.asignacion_id === cel.asignacion_id)
17675|       && !lecturaS2.error && !(lecturaS2.data ?? []).some((a) => a.asignacion_id === cel.asignacion_id),
17676|     'supervisión ve los celulares de su equipo (sup1 sí, sup2 no)');
17677|     // Segundo celular de vend1 (bolsa, reutilizable, baja y enlace): el cupo es de 30 por minuto y por celular.
17678|     const celB = await asignar('vend1');
17679|     const celSup = await asignar('sup1');
17680| 
17681|     // ── Ingesta: contrato {resultado, mensaje}, recepción, reenvío, sin pistas, inválidos con cupo ──
17682|     await expectExpectedFailure('servicio: clave desconocida → el mismo 42501',
17683|       ingerir('f'.repeat(64), evento(idDe(cel.etiqueta))), ['42501'], /no autorizado/i);
17684|     const id1 = idDe(cel.etiqueta);
17685|     const r1 = await ingerir(cel.credencial, evento(id1));
17686|     const ev1 = eventoDe(id1);
17687|     check(aceptado(r1) && ev1?.leadId === leadId && ev1?.atencion === 'requiere_resultado' && recepciones(id1) === 1,
17688|       'servicio: responde solo {resultado: aceptado}; recepción y llamada guardadas, pide resultado',
17689|       errorText(r1.error) || JSON.stringify(r1.data));
17690|     const eventoId = ev1?.id ?? randomUUID();
17691|     if (ev1) eventos.push(ev1.id);
17692|     const r1b = await ingerir(cel.credencial, evento(id1, { duracion_seg: 43, numero: nuevoNumero() }));
17693|     const det1 = await rpc('vend1', 'llamada_celular_detalle_fn', { p_evento_id: eventoId });
17694|     check(aceptado(r1b) && eventosDe(id1) === 1 && recepciones(id1) === 1 && det1.data?.duracion_seg === 42,
17695|       'servicio: el mismo id con otro contenido → aceptado y sin cambios (el primero gana; sin P0409)', errorText(r1b.error));
17696|     const idDoble = idDe(cel.etiqueta);
17697|     const [d1, d2] = await Promise.all([ingerir(cel.credencial, evento(idDoble)), ingerir(cel.credencial, evento(idDoble))]);
17698|     check(aceptado(d1) && aceptado(d2) && eventosDe(idDoble) === 1 && recepciones(idDoble) === 1,
17699|       'servicio: dos envíos a la vez del mismo id → una recepción y una llamada', `${errorText(d1.error)} / ${errorText(d2.error)}`);
17700|     const evDoble = eventoDe(idDoble);
17701|     if (evDoble) eventos.push(evDoble.id);
17702|     const idSinLead = idDe(cel.etiqueta);
17703|     const idAjeno = idDe(cel.etiqueta);
17704|     const sinLead = await ingerir(cel.credencial, evento(idSinLead, { numero: nuevoNumero() }));
17705|     const conAjeno = await ingerir(cel.credencial, evento(idAjeno, { numero: ajeno.phone }));
17706|     check(aceptado(sinLead) && aceptado(conAjeno) && eventosDe(idSinLead) + eventosDe(idAjeno) === 0
17707|       && recepciones(idSinLead) + recepciones(idAjeno) === 2,
17708|     'servicio: sin lead y lead de otro equipo responden igual que el propio y no se guardan (decisión 3)');
17709|     const ahora = Math.floor(Date.now() / 1000);
17710|     const [diaA, nA] = cupo(cel.asignacion_id);
17711|     const malos = ['X1-1790980958', `${cel.etiqueta}-123`, idDe(celB.etiqueta),
17712|       `${cel.etiqueta}-${ahora - 31 * 86400}`, `${cel.etiqueta}-${ahora + 2 * 86400}`];
17713|     for (const malo of malos) {
17714|       const r = await ingerir(cel.credencial, evento(malo));
17715|       check(invalido(r) && recepciones(malo) === 0, `servicio: id ${malo} → {resultado: invalido, mensaje}, sin recepción`,
17716|         errorText(r.error) || JSON.stringify(r.data));
17717|     }
17718|     const [diaD, nD] = cupo(cel.asignacion_id);
17719|     check(diaA !== diaD || Number(nD) - Number(nA) === malos.length, 'servicio: cada inválido gasta cupo', `${nA} → ${nD}`);
17720|     const idEnt = idDe(cel.etiqueta);
17721|     const idDes = idDe(cel.etiqueta);
17722|     const rEnt = await ingerir(cel.credencial, evento(idEnt, { direccion: 'entrante', estado_tecnico: 'no_atendida' }));
17723|     const sinDir = evento(idDes);
17724|     delete sinDir.direccion;
17725|     const rDes = await ingerir(cel.credencial, sinDir);
17726|     check(aceptado(rEnt) && aceptado(rDes) && eventosDe(idEnt) + eventosDe(idDes) === 0 && recepciones(idEnt) + recepciones(idDes) === 2,
17727|       'servicio: entrante y dirección desconocida al número de un lead → aceptadas e ignoradas (decisión 2)');
17728|     await expectExpectedFailure('gerencia: no enciende las entrantes (bloqueadas hasta la #14)',
17729|       rpc('gerencia', 'fijar_politica_llamadas_celular', { p_entrantes_activas: true }), ['22023'], /entrantes siguen bloqueadas/i);
17730|     check(cuenta('CHECK entrantes', "select count(*) from pg_constraint where conrelid = 'crm.llamadas_celular_politica'::regclass"
17731|       + " and conname = 'llamadas_celular_politica_entrantes_bloqueadas' and contype = 'c'") === 1,
17732|     'la tabla fija entrantes en falso (CHECK)');
17733|     const latido = await servicio('registrar_salud_celular_servicio',
17734|       { p_credencial: cel.credencial, p_latido: { v: 1, version_macro: 'gate rls', en_cola: 0 } });
17735|     const latidoMalo = await servicio('registrar_salud_celular_servicio', { p_credencial: cel.credencial, p_latido: { v: 1 } });
17736|     check(aceptado(latido) && invalido(latidoMalo), 'servicio: latido → {resultado: aceptado}; inválido → {resultado: invalido, mensaje}',
17737|       `${errorText(latido.error)} / ${JSON.stringify(latidoMalo.data)}`);
17738|     const saludG = await rpc('gerencia', 'celulares_salud_fn');
17739|     const saludS2 = await rpc('sup2', 'celulares_salud_fn');
17740|     const fila = (saludG.data ?? []).find((a) => a.asignacion_id === cel.asignacion_id);
17741|     check(!saludG.error && Boolean(fila?.ultimo_latido_en) && !('envios_hoy' in (fila ?? {})) && !('ultimo_envio_en' in (fila ?? {}))
17742|       && !saludS2.error && !JSON.stringify(saludS2.data ?? '').includes(cel.asignacion_id),
17743|     'salud: gerencia ve el latido sin envíos ni último envío (N1); sup2 (otro equipo) no ve el celular');
17744| 
17745|     // ── Ámbito de lectura (la bandeja paginada es la única): dueño, su supervisión y gerencia sí; otro equipo no ──
17746|     for (const [quien, debe] of [['vend1', true], ['sup1', true], ['gerencia', true], ['vend3', false], ['sup2', false]]) {
17747|       check(await ve(quien, eventoId) === debe, `${quien}: ${debe ? 've' : 'no ve'} la llamada en la bandeja`);
17748|     }
17749|     check(!det1.error && det1.data?.atencion === 'requiere_resultado' && det1.data?.lead_id === leadId,
17750|       'vend1: su llamada pide resultado y está asociada a su lead', errorText(det1.error));
17751|     for (const quien of ['vend3', 'sup2']) {
17752|       await expectExplicitAuthorizationDenied(`${quien}: no abre el detalle de una llamada ajena`,
17753|         rpc(quien, 'llamada_celular_detalle_fn', { p_evento_id: eventoId }));
17754|       await expectExplicitAuthorizationDenied(`${quien}: no descarta una llamada ajena`,
17755|         rpc(quien, 'descartar_llamada_celular', { p_evento_id: eventoId, p_motivo: 'personal' }));
17756|     }
17757|     await expectExplicitAuthorizationDenied('vend1: no asocia su llamada a un lead de otro equipo',
17758|       rpc('vend1', 'asociar_llamada_celular', { p_evento_id: eventoId, p_lead_id: ajeno.id }));
17759|     await expectExpectedFailure('vend1: no enlaza la llamada a un resultado que no es de ese lead',
17760|       rpc('vend1', 'enlazar_llamada_celular', { p_evento_id: eventoId, p_actividad_id: randomUUID() }), ['22023'], /no es del lead/i);
17761|     await expectExpectedFailure('vend1: descartar con «otro» exige el motivo escrito',
17762|       rpc('vend1', 'descartar_llamada_celular', { p_evento_id: eventoId, p_motivo: 'otro' }), ['22023'], /otro/i);
17763| 
17764|     // ── El celular de un SUPERVISOR evalúa la regla como su dueño (depende de que auth.uid() lea request.jwt.claim.sub) ──
17765|     const idSup = idDe(celSup.etiqueta);
17766|     const rs = await ingerir(celSup.credencial, evento(idSup));
17767|     const evSup = eventoDe(idSup);
17768|     if (evSup) eventos.push(evSup.id);
17769|     const detSup = evSup ? await rpc('sup1', 'llamada_celular_detalle_fn', { p_evento_id: evSup.id }) : null;
17770|     check(aceptado(rs) && detSup && !detSup.error && detSup.data?.atencion === 'requiere_resultado',
17771|       'sup1: su llamada a un lead de su equipo pide resultado (la ingesta evalúa como el dueño del celular)',
17772|       `${errorText(rs.error)} / ${errorText(detSup?.error)}`);
17773| 
17774|     // ── Bolsa y reutilizable (decisión 7): por revisar; quien llamó no la ve; le aparece al tomar el lead ──
17775|     const numBolsa = nuevoNumero();
17776|     const leadBolsa = await crearLead('LLAMADAS CELULAR BOLSA TRANSIENT', numBolsa, null);
17777|     const numReu = nuevoNumero();
17778|     const leadReu = await crearLead('LLAMADAS CELULAR REUTILIZABLE TRANSIENT', numReu, null);
17779|     // Un descarte VENCIDO no se fabrica por la API (nacer terminal está vetado y el sello fecha `descartado_en` con
17780|     // now()): se fecha fuera de banda con la espera real del motivo, que gerencia puede haber cambiado.
17781|     const diasAtras = Math.max(cuenta('espera de pide_credito', "select coalesce((select dias from crm.enfriamiento_politica"
17782|       + " where motivo = 'pide_credito'), 0)"), 1) + 1;
17783|     ejecutarFueraDeBanda('llamadas: descarte vencido del reutilizable', `set local session_replication_role = replica;
17784|       update crm.leads set etapa = 'descartado', motivo_descarte = 'pide_credito',
17785|         descartado_en = now() - interval '${diasAtras} days' where id = '${leadReu}';`);
17786|     for (const [modo, leadX, numX] of [['bolsa', leadBolsa, numBolsa], ['reutilizable', leadReu, numReu]]) {
17787|       const idX = idDe(celB.etiqueta);
17788|       const rX = await ingerir(celB.credencial, evento(idX, { numero: numX }));
17789|       const evX = eventoDe(idX);
17790|       check(aceptado(rX) && evX?.leadId === leadX && evX?.atencion === 'por_revisar', `${modo}: responde igual; identificada, por revisar`);
17791|       if (!evX) continue;
17792|       eventos.push(evX.id);
17793|       check(await ve('vend1', evX.id) === false && await ve('sup1', evX.id) === false && await ve('gerencia', evX.id) === true,
17794|         `${modo}: quien llamó (y su supervisor) no la ve; gerencia sí`);
17795|       await expectExplicitAuthorizationDenied(`${modo}: vend1 no abre el detalle antes de tomar el lead`,
17796|         rpc('vend1', 'llamada_celular_detalle_fn', { p_evento_id: evX.id }));
17797|       const toma = await positive(`vend1 toma el lead (${modo})`, rpc('vend1', 'tomar_lead_libre', { p_telefono: numX, p_dni: null }));
17798|       check(toma?.data?.estado === 'tomado_ok' && toma.data.lead_id === leadX,
17799|         `${modo}: tomar_lead_libre → tomado_ok con ese lead`, JSON.stringify(toma?.data));
17800|       check(await ve('vend1', evX.id) === true, `${modo}: al tomar el lead, vend1 ve su llamada`);
17801|     }
17802| 
17803|     // ── Lead dado de baja: nadie ve ni toca sus llamadas, gerencia incluida (fallo 2) ──
17804|     const numBaja = nuevoNumero();
17805|     const leadBaja = await crearLead('LLAMADAS CELULAR BAJA TRANSIENT', numBaja, 'vend1');
17806|     const idBaja = idDe(celB.etiqueta);
17807|     await ingerir(celB.credencial, evento(idBaja, { numero: numBaja }));
17808|     const evBaja = eventoDe(idBaja);
17809|     check(evBaja?.atencion === 'requiere_resultado' && await ve('vend1', evBaja?.id) === true, 'baja: antes, vend1 ve su llamada');
17810|     await requireAdmin('dar de baja el lead', admin.schema('crm').from('leads').update({ activo: false }).eq('id', leadBaja));
17811|     if (evBaja) {
17812|       for (const quien of ['vend1', 'sup1', 'gerencia']) check(await ve(quien, evBaja.id) === false, `baja: ${quien} ya no la ve`);
17813|       for (const quien of ['vend1', 'gerencia']) {
17814|         await expectExplicitAuthorizationDenied(`baja: ${quien} no abre el detalle`,
17815|           rpc(quien, 'llamada_celular_detalle_fn', { p_evento_id: evBaja.id }));
17816|       }
17817|       await expectExplicitAuthorizationDenied('baja: gerencia no la descarta',
17818|         rpc('gerencia', 'descartar_llamada_celular', { p_evento_id: evBaja.id, p_motivo: 'personal' }));
17819|     }
17820| 
17821|     // ── Enlace exacto con la v4 REAL (F4-a). «no_contesto»: sin p_siguiente obligatorio ──
17822|     const v5 = (op, origen, via) => rpc('vend1', 'registrar_llamada_v5', { p_operacion_id: op, p_lead_id: leadId,
17823|       p_resultado: 'no_contesto', p_evento_origen_id: origen, p_via: via });
17824|     const idAntes = idDe(celB.etiqueta);
17825|     const rAntes = await ingerir(celB.credencial, evento(idAntes));
17826|     const opA = randomUUID();
17827|     const vA = await v5(opA, idAntes, 'al_colgar');
17828|     const evA = eventoDe(idAntes);
17829|     const detA = evA ? await rpc('vend1', 'llamada_celular_detalle_fn', { p_evento_id: evA.id }) : null;
17830|     check(aceptado(rAntes) && !vA.error && vA.data?.ok === true && vA.data?.actividad_id === opA && vA.data?.enlace?.estado === 'enlazado'
17831|       && enlaceDe(idAntes) === `${opA}|al_colgar` && detA?.data?.atencion === 'registrado' && detA?.data?.actividad_id === opA,
17832|     'v5: aviso antes → la encuesta queda unida a su llamada, vía al_colgar', errorText(vA.error) || JSON.stringify(vA.data?.enlace));
17833|     const vA2 = await v5(opA, idAntes, 'al_colgar');
17834|     check(!vA2.error && vA2.data?.replay === true && vA2.data?.enlace?.estado === 'repetido',
17835|       'v5: el reintento de la misma operación → repetido', errorText(vA2.error) || JSON.stringify(vA2.data?.enlace));
17836|     const idDespues = idDe(celB.etiqueta);
17837|     const opD = randomUUID();
17838|     const vD = await v5(opD, idDespues, 'pestana');
17839|     check(!vD.error && vD.data?.enlace?.estado === 'pendiente' && intenciones(idDespues) === 1,
17840|       'v5: aviso después → intención de enlace', errorText(vD.error) || JSON.stringify(vD.data?.enlace));
17841|     const rDespues = await ingerir(celB.credencial, evento(idDespues));
17842|     check(aceptado(rDespues) && eventoDe(idDespues)?.atencion === 'registrado' && enlaceDe(idDespues) === `${opD}|pestana`
17843|       && intenciones(idDespues) === 0, 'ingesta: al llegar el aviso cumple la intención (vía pestana) y la retira');
17844|     for (const [motivo, origen] of [['id_invalido', 'X1-123'], ['celular_ajeno', idDe(celSup.etiqueta)], ['ya_tiene_resultado', idAntes]]) {
17845|       const op = randomUUID();
17846|       const r = await v5(op, origen, 'al_colgar');
17847|       check(!r.error && r.data?.ok === true && r.data?.actividad_id === op && r.data?.enlace?.estado === 'no_enlazado'
17848|         && r.data?.enlace?.motivo === motivo, `v5: ${motivo} → guarda el resultado igual y dice no_enlazado`,
17849|       errorText(r.error) || JSON.stringify(r.data?.enlace));
17850|     }
17851|     await expectExpectedFailure('v5: con id y sin vía → 22023', rpc('vend1', 'registrar_llamada_v5', { p_operacion_id: randomUUID(),
17852|       p_lead_id: leadId, p_resultado: 'no_contesto', p_evento_origen_id: idDe(celB.etiqueta) }), ['22023'], /al_colgar o pestana/i);
17853|     await expectExplicitAuthorizationDenied('v5: vend3 no registra por el lead de vend1', rpc('vend3', 'registrar_llamada_v5', {
17854|       p_operacion_id: randomUUID(), p_lead_id: leadId, p_resultado: 'no_contesto', p_evento_origen_id: idAntes, p_via: 'al_colgar' }));
17855| 
17856|     // ── Rotar: la clave vieja no entra; el mismo id no duplica; un id nuevo entra con la asignación nueva ──
17857|     rot = await rpc('gerencia', 'rotar_credencial_celular', { p_etiqueta: cel.etiqueta });
17858|     check(!rot.error && /^[0-9a-f]{64}$/.test(rot.data?.credencial ?? '') && rot.data?.credencial !== cel.credencial,
17859|       'gerencia rota la clave del celular', errorText(rot.error));
17860|     if (rot.data?.asignacion_id) {
17861|       // La rotación ya cerró la anterior: solo queda por cerrar la nueva.
17862|       asignaciones.splice(asignaciones.indexOf(cel.asignacion_id), 1, rot.data.asignacion_id);
17863|       claveNueva = rot.data.credencial;
17864|     }
17865|     await expectExpectedFailure('servicio: la clave rotada ya no entra', ingerir(cel.credencial, evento(idDe(cel.etiqueta))), ['42501'], /no autorizado/i);
17866|     const reenvio = await ingerir(claveNueva ?? '', evento(id1));
17867|     const idRot = idDe(cel.etiqueta);
17868|     const conNueva = await ingerir(claveNueva ?? '', evento(idRot));
17869|     const evRot = eventoDe(idRot);
17870|     if (evRot) eventos.push(evRot.id);
17871|     check(aceptado(reenvio) && eventosDe(id1) === 1 && recepciones(id1) === 1 && aceptado(conNueva)
17872|       && evRot?.asignacionId === rot.data?.asignacion_id, 'servicio: tras rotar no se duplica; el id nuevo entra con la asignación nueva');
17873|   } finally {
17874|     // Deja las llamadas de la corrida sin pendientes para nadie (las descarta gerencia: también ve las de bolsa),
17875|     // cierra los celulares y da de baja los leads. 22023 = ya tenía resultado; 23505 = ya descartada con otro motivo.
17876|     // Las del lead dado de baja no se tocan: nadie las alcanza (es lo que se prueba).
17877|     for (const eventoId of eventos) {
17878|       const r = await rpc('gerencia', 'descartar_llamada_celular', { p_evento_id: eventoId, p_motivo: 'numero_de_prueba' });
17879|       if (r.error && !['22023', '23505'].includes(r.error.code)) fail(`llamadas: no se pudo descartar el evento de prueba — ${errorText(r.error)}`);
17880|     }
17881|     for (const asignacionId of asignaciones) {
17882|       const r = await rpc('gerencia', 'cerrar_asignacion_celular', { p_asignacion_id: asignacionId, p_motivo: 'reemplazo' });
17883|       if (r.error) fail(`llamadas: no se pudo cerrar un celular de prueba — ${errorText(r.error)}`);
17884|     }
17885|     for (const lead of leads) await admin.schema('crm').from('leads').update({ activo: false }).eq('id', lead);
17886|   }
17887|   if (claveNueva) {
17888|     await expectExpectedFailure('servicio: con el celular cerrado, su clave ya no entra',
17889|       ingerir(claveNueva, evento(idDe('C1'))), ['42501'], /no autorizado/i);
17890|   }
17891| }
```

## Archivo: supabase/scripts/banco/limpiar-entre-corridas.sql (26 líneas) — limpieza del banco entre corridas del gate
```
   1| -- Limpieza entre corridas del gate, punto 3 de supabase/scripts/LEEME-seed.md.
   2| -- El seed NO es re-ejecutable a medias: sin esto, la segunda corrida se atasca.
   3| -- Solo banco local.
   4| begin;
   5| set local session_replication_role = replica;  -- el ledger es append-only
   6| truncate crm.actividades, crm.tareas, crm.lead_asignaciones, crm.leads cascade;
   7| -- Bases cargadas (B7/B8): el gate deja bases y recibos (sin DELETE por diseño; los recibos rechazan TRUNCATE salvo en replica).
   8| do $bases$ begin
   9|   if to_regclass('crm.bases_carga') is not null then
  10|     truncate crm.base_carga_operaciones, crm.base_carga_leads, crm.bases_carga;
  11|   end if;
  12| end $bases$;
  13| -- Llamadas del celular: el gate deja asignaciones cerradas que apuntan a crm.equipo. En replica la FK no se
  14| -- comprueba: sin esto quedarían huérfanas (las llamadas y las intenciones ya cayeron con crm.leads). CASCADE
  15| -- arrastra recepciones y estado de private.
  16| do $llamadas$ begin
  17|   if to_regclass('crm.celulares_asignaciones') is not null then
  18|     truncate crm.celulares_asignaciones cascade;
  19|   end if;
  20| end $llamadas$;
  21| delete from crm.equipo;
  22| set local session_replication_role = default;
  23| commit;
  24| 
  25| -- Punto 4 de la adenda: la sonda de domicilio exige arrancar con la columna vacia.
  26| update public.perfiles set domicilio = null where rol = 'cliente';
```

## Archivo: docs/plans/llamadas-celular/PUBLICAR-F2-F3.md (221 líneas) — guía de publicación
```
   1| # Publicar F2 + F3 + F4-a de «Llamadas desde el celular» — guía técnica (05/10/2026)
   2| 
   3| Seis migraciones, **ninguna aplicada ni desplegada**. Las cuatro primeras están en `main` (PR #169); la quinta
   4| (corrección) y la sexta (F4-a, enlace exacto) están en el PR #190. Se publican **juntas** y con la Edge del contrato
   5| nuevo (decisión 1 de Miguel). F1 (la encuesta al colgar) ya está en producción y no cambia.
   6| 
   7| Regla del proyecto (`CRM-Avance-Corp/CLAUDE.md`): rama de Supabase → aplicar → gate `test-rls.mjs` → advisors →
   8| merge. **Nunca `apply_migration` directo a producción.**
   9| 
  10| > **Barrera.** No se despliega la Edge ni se da de alta ningún celular hasta aplicar y verificar la quinta **y** F4-a
  11| > (paso 3.4). Sin Edge y sin claves, las puertas de las cuatro no exponen nada: las tablas están vacías. La Edge nueva,
  12| > además, solo entiende la respuesta de la quinta: contra las cuatro contestaría 503 a todo. **Al revés tampoco:** un
  13| > alta antes de la quinta la deja sin poder aplicarse (exige tablas vacías y una asignación no se borra nunca).
  14| 
  15| ## 0. Antes de que Miguel empiece
  16| 
  17| | # | Qué | Estado al 05/10 |
  18| | --- | --- | --- |
  19| | 0.1 | Seis migraciones, cada una con su registrador (`supabase/scripts/llamadas-celular/registrar-{datos,nucleo,ingesta,elegibilidad,correccion,enlace-exacto}.sql`); los dos últimos terminan con una fila de veredicto | Hecho. `npm run test:llamadas:local`: 281/281 |
  20| | 0.2 | Reversas de las seis (`reversa-*.sql`) | Hecho; las de la quinta y F4-a, solo antes de dar de alta celulares («Reversa») |
  21| | 0.3 | Edge con el contrato nuevo | Hecho: 15/15 y mutantes 15/15; sin desplegar |
  22| | 0.4 | Bloque `testLlamadasCelular` del gate al día con la quinta y F4-a (paso 4 del plan v2), y `banco/limpiar-entre-corridas.sql` vaciando las asignaciones | Hecho (05/10): cotejado con las migraciones; `node --check` y oxlint limpios; **sin correr** (necesita el esquema de producción) |
  23| | 0.5 | `alta-celular.sql`, `rotar-celular.sql` y `cerrar-celular.sql` | Hechos (05/10): una sola sentencia cada uno, porque `db query` solo devuelve el último resultado; probados en un Postgres local |
  24| | 0.6 | Codex r2 y `auditor-rls` sobre la quinta + F4-a + la Edge | **Pendiente; los corre Miguel** |
  25| | 0.7 | PR #190 → `main` (`main` tiene que contener lo que se aplica) | Pendiente |
  26| 
  27| ## 1. Decisiones
  28| 
  29| - Tomadas: las siete de la corrección y sus confirmaciones (`CORRECCION-PLAN-CORTO.md`, «Decisiones»), la N1 según la
  30|   recomendación (`MIGRACIONES.md`, `20261005143843`) y las de Jhosep para F4-a (`MIGRACIONES.md`, `20261005155914`).
  31|   MacroDroid Pro: todavía no.
  32| - Para que Miguel las vea: los «criterios de Claude» de esas dos entradas de `MIGRACIONES.md`.
  33| - Las migraciones no modifican nada de `public`: solo lo referencian (autoría con `ON DELETE RESTRICT`, lecturas).
  34| 
  35| ## 2. Ensayo en una copia con el esquema de producción
  36| 
  37| En una copia Docker todo va con `psql "$DB_URL" -v ON_ERROR_STOP=1 -f <archivo>`: `db query --local --file` falla con
  38| varias sentencias. Con `psql` sí se ven los `raise notice`.
  39| 
  40| 1. `auth.uid()` lee `request.jwt.claim.sub` (la ingesta evalúa como el dueño del celular):
  41|    `select pg_get_functiondef('auth.uid()'::regprocedure);` → tiene que consultar
  42|    `current_setting('request.jwt.claim.sub', true)`.
  43| 2. Cada migración, seguida **justo después** de su registrador:
  44| 
  45|    | # | Migración (`supabase/migrations/`) | Registrador | Qué se ve si salió bien |
  46|    | --- | --- | --- | --- |
  47|    | 1 | `20261001145242_crm_llamadas_celular_datos.sql` | `registrar-datos.sql` | notice `REGISTRO: 20261001145242 / …` (con `psql`) |
  48|    | 2 | `20261001160219_crm_llamadas_celular_nucleo.sql` | `registrar-nucleo.sql` | ídem |
  49|    | 3 | `20261001212258_crm_llamadas_celular_ingesta.sql` | `registrar-ingesta.sql` | ídem |
  50|    | 4 | `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql` | `registrar-elegibilidad.sql` | ídem |
  51|    | 5 | `20261005143843_crm_llamadas_celular_correccion.sql` | `registrar-correccion.sql` | fila `veredicto_registro_20261005143843 = t` |
  52|    | 6 | `20261005155914_crm_llamadas_celular_enlace_exacto.sql` | `registrar-enlace-exacto.sql` | fila `veredicto_registro_20261005155914 = t` |
  53| 
  54|    - No van todos al final: `registrar-nucleo` exige `crm.llamadas_celular_pendientes_fn` y `registrar-elegibilidad`,
  55|      la ingesta de dos argumentos, y la quinta retira las dos.
  56|    - Los registradores comparan el md5 del archivo: se corren desde un checkout con finales de línea LF.
  57|    - Solo entre la 1 y la 2: `verificar-datos.sql` (oráculo de la migración 1; termina en ROLLBACK; esperado
  58|      `ORACULO F2-b OK`). **Después de la quinta ya no corre:** inserta `hash_payload` e ids que la quinta retira.
  59|      Tampoco corren con la quinta `banco/verificar-hallazgos.sql` ni `banco/medir-bandeja.sql`: son de las cuatro.
  60| 3. Verificar con V1–V5 del paso 3.4.
  61| 4. Ensayar la reversa **antes de crear ninguna asignación** (el gate y el alta las crean, y desde ahí las reversas se
  62|    niegan): `reversa-enlace-exacto.sql` → `reversa-correccion.sql` → `reversa-elegibilidad.sql` →
  63|    `reversa-ingesta.sql` → `reversa-nucleo.sql` → `reversa-datos-total.sql` (con `reversa-datos.sql` las tablas se
  64|    quedan y no se puede volver a aplicar). Fuera de orden, cada una se niega. Después, volver a aplicar las seis con sus
  65|    registradores (son idempotentes: la fila del historial se quedó).
  66| 5. Gate: `node supabase/scripts/test-rls.mjs` con `CRM_RLS_EXIGE_LLAMADAS=1` y `CRM_BANCO_PSQL_URL`. Tiene que probar:
  67|    nadie toca las tablas directo; cada puerta, solo su rol; clave desconocida → 42501; el mismo id con otro contenido →
  68|    aceptado sin cambios y sin `P0409`; inválidos con el cupo gastado; dos envíos a la vez → uno; número sin lead y lead
  69|    de otro analista → no se guardan; entrantes bloqueadas; lead dado de baja (nadie lo ve); bolsa y reutilizable; un
  70|    enlace real con su encuesta (v5); rotación. **El gate crea asignaciones: desde aquí, en esta copia, las reversas se
  71|    niegan.** Entre corridas, `banco/limpiar-entre-corridas.sql` vacía también las tablas de llamadas.
  72| 6. Ensayar el alta por la misma vía que en producción: `alta-celular.sql` con `db query --linked --file` contra una
  73|    rama de Supabase (en Docker esa vía falla). Esperado: una sola fila con la clave; con un usuario que no es gerencia,
  74|    42501. Igual con `rotar-celular.sql` y `cerrar-celular.sql`.
  75| 7. Barrera, en una copia aparte que después se descarta: las cuatro con sus registradores, un alta y la quinta → se
  76|    niega con «LLAMADAS_CORRECCION: hay filas en las tablas de llamadas…».
  77| 8. Advisors de seguridad y rendimiento: ninguna alerta nueva.
  78| 
  79| ## 3. Producción (con el `!` de Miguel)
  80| 
  81| 1. Antes, que no exista nada: `select to_regclass('crm.llamadas_celular_eventos') is null as limpio;` → `t`. Y el 2.1.
  82| 2. Las seis, en el orden del 2.2, **una por mensaje** y cada una seguida de su registrador, desde `CRM-Avance-Corp/` en
  83|    un checkout LF (la Mac de Miguel):
  84|    `npx supabase db query --linked --file supabase/migrations/<migración>.sql`, y después
  85|    `npx supabase db query --linked --file supabase/scripts/llamadas-celular/<registrador>.sql`.
  86|    - Por esta vía no se ven los `raise notice` y solo vuelve el último resultado. Una migración o uno de los cuatro
  87|      registradores viejos que sale bien **no muestra nada** (su última sentencia es `commit`). Uno que falla muestra el
  88|      error y no deja nada (cada archivo es una transacción). Los dos registradores nuevos muestran su fila de veredicto.
  89|    - Después de cada registrador viejo, V1: la fila de esa versión tiene que salir con `ok = t`.
  90|    - Si algo falla, parar ahí: la siguiente migración se niega sin la anterior.
  91| 3. Marcar las seis «EN PROD» en `MIGRACIONES.md`.
  92| 4. **Verificar (levanta la barrera).** Cada consulta es un solo `select`, para que se vea por `db query --linked`:
  93|    ```sql
  94|    -- V1 · historial: 6 filas, todas ok = t
  95|    select e.version, (m.name = e.nombre and cardinality(m.statements) = 1 and md5(m.statements[1]) = e.md5) is true as ok
  96|    from (values ('20261001145242','crm_llamadas_celular_datos','a431978920a73d38f5c8cf121ad94327'),
  97|                 ('20261001160219','crm_llamadas_celular_nucleo','4d78907164c4a77b12ea35f354aebc3e'),
  98|                 ('20261001212258','crm_llamadas_celular_ingesta','90d544e9e96c637bcab2869225333ceb'),
  99|                 ('20261001222431','crm_llamadas_celular_elegibilidad_dueno','0a4e5b9c148208cc660616bf84d585a9'),
 100|                 ('20261005143843','crm_llamadas_celular_correccion','306d706b4b8020b0a7e585300f233d14'),
 101|                 ('20261005155914','crm_llamadas_celular_enlace_exacto','69d2137ecf345dda3e8be66b3d6b44fb')) e(version, nombre, md5)
 102|    left join supabase_migrations.schema_migrations m on m.version = e.version order by e.version;
 103|    -- V2 · forma de la quinta y de F4-a: todo t
 104|    select to_regclass('private.llamadas_celular_recepciones') is not null as recepciones,
 105|           to_regclass('private.llamadas_celular_intenciones') is not null as intenciones,
 106|           to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb,timestamptz)') is not null as ingesta_nueva,
 107|           to_regprocedure('private.llamada_celular_ingerir(uuid,jsonb)') is null as sin_ingesta_vieja,
 108|           to_regprocedure('crm.llamadas_celular_pendientes_fn(integer)') is null as sin_bandeja_vieja,
 109|           to_regprocedure('crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)') is not null as v5,
 110|           exists (select 1 from pg_constraint where conrelid = 'crm.llamadas_celular_politica'::regclass
 111|                   and conname = 'llamadas_celular_politica_entrantes_bloqueadas') as entrantes_bloqueadas,
 112|           not exists (select 1 from pg_attribute where attrelid = 'crm.llamadas_celular_eventos'::regclass
 113|                       and attname = 'hash_payload' and not attisdropped) as sin_hash_payload,
 114|           exists (select 1 from pg_attribute where attrelid = 'crm.llamadas_celular_enlaces'::regclass
 115|                   and attname = 'via' and not attisdropped) as enlace_con_via;
 116|    -- V3 · vacías: todo 0
 117|    select (select count(*) from crm.celulares_asignaciones) as asignaciones, (select count(*) from private.celulares_estado) as estado,
 118|           (select count(*) from private.llamadas_celular_recepciones) as recepciones, (select count(*) from crm.llamadas_celular_eventos) as llamadas,
 119|           (select count(*) from crm.llamadas_celular_enlaces) as enlaces, (select count(*) from private.llamadas_celular_intenciones) as intenciones;
 120|    -- V4 · permisos: f, f, t, t, f
 121|    select has_function_privilege('anon', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
 122|           has_function_privilege('authenticated', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
 123|           has_function_privilege('service_role', 'crm.ingerir_llamada_celular_servicio(text,jsonb)', 'EXECUTE'),
 124|           has_function_privilege('authenticated', 'crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', 'EXECUTE'),
 125|           has_function_privilege('anon', 'crm.registrar_llamada_v5(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean,text,text)', 'EXECUTE');
 126|    -- V5 · retención y política: 23 6 * * *, t, f, f, 30, 600
 127|    select j.schedule, j.active, p.entrantes_activas, p.guardar_sin_identificar, p.limite_envios_minuto, p.limite_envios_dia
 128|    from cron.job j, crm.llamadas_celular_politica p where j.jobname = 'crm-llamadas-celular-caducidad' and p.singleton;
 129|    ```
 130| 5. Tipos: `npm run gen:types` en `app/` y commit. La pantalla todavía no usa las puertas nuevas (F4-b).
 131| 6. **Recién ahora, la Edge**, desde `CRM-Avance-Corp/` y con el commit del PR #190 o uno posterior:
 132|    ```bash
 133|    npx supabase@2.114.0 functions deploy crm-llamadas-ingesta --project-ref dctqcbznekcyxhjujuci --use-api
 134|    ```
 135|    Toma `verify_jwt = false` de `supabase/config.toml`. No pide secretos nuevos (`SUPABASE_URL` y
 136|    `SUPABASE_SERVICE_ROLE_KEY`). Contrato: 202 llamada aceptada (guardada, repetida o ignorada responden igual), 200
 137|    latido, 400 inválido con el mensaje de la base, 401 clave, 429 con `Retry-After`, 503 inesperado; 405, 415 y 413 sin
 138|    tocar la base. Ya no hay 409.
 139| 7. Comprobar el despliegue:
 140|    ```bash
 141|    curl -s -X POST https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta \
 142|      -H 'content-type: application/json' -d '{}'
 143|    curl -s -X POST https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta \
 144|      -H 'content-type: application/json' -H "x-celular-credencial: $(printf '0%.0s' {1..64})" -d '{}'
 145|    ```
 146|    Esperado, las dos veces: `{"error":"No autorizado"}`. La segunda llega a la base y no reconoce la clave. Un 503 en la
 147|    segunda: la Edge no llega a la puerta. «Invalid JWT»: `verify_jwt` quedó encendido.
 148| 
 149| ## 4. Dar de alta un celular (C1 primero)
 150| 
 151| - Solo gerencia: `crm.asignar_celular('<etiqueta>', '<uuid del analista>')`. Etiqueta de `C1` a `C999`. El dueño,
 152|   analista (`vendedor`) o supervisor activo. La `credencial` se devuelve **una sola vez**: en la base queda su sha256.
 153| - Con `supabase/scripts/llamadas-celular/alta-celular.sql` (cambiar sus tres valores) y
 154|   `npx supabase db query --linked --file supabase/scripts/llamadas-celular/alta-celular.sql`. Es una sola sentencia:
 155|   la única fila que vuelve trae la clave.
 156| - **⚠️ La salida trae la clave en claro.** Miguel lo corre en su propia terminal, nunca en una sesión de Claude ni
 157|   pegando la salida en un chat. La clave se copia directo al celular (o va a Jhosep por un canal privado) y se limpia la
 158|   terminal. Nunca va al repo ni a un chat. El archivo no se commitea con valores reales.
 159| - **La etiqueta es el prefijo del id en la macro de ESE celular** (`C2-…` en C2). Con otra, la base rechaza cada aviso
 160|   (400 «etiqueta de otro celular») y la macro los aparta en `errores_llamadas`.
 161| - Comprobar sin ver la clave:
 162|   ```sql
 163|   select a.etiqueta, a.vigente_desde, s.ultimo_latido_en, s.version_macro, s.eventos_en_cola
 164|   from crm.celulares_asignaciones a left join private.celulares_estado s on s.asignacion_id = a.id
 165|   where a.vigente_hasta is null order by a.etiqueta;
 166|   ```
 167| - Rotar la clave (`rotar-celular.sql`, misma vía y misma advertencia) reinicia el límite de envíos (el estado va por
 168|   asignación). Solo gerencia rota.
 169| 
 170| ## 5. Cambiar la macro del celular (Jhosep, con Claude): `macrodroid.md` §3c
 171| 
 172| 1. Vaciar `cola_llamadas` **y** `errores_llamadas` (MacroDroid → Variables globales). La cola de C1 tiene avisos de
 173|    prueba con números reales y con ids que todavía caben en la ventana de 30 días: entrarían como llamadas de verdad.
 174| 2. «Fecha y hora automáticas» y zona horaria de Lima. La base rechaza un id con la hora fuera de [hace 30 días, mañana].
 175| 3. En «Llamadas-Al colgar», el prefijo del id = la etiqueta del alta.
 176| 4. En «Llamadas-Enviar cola» → «Solicitud HTTP» (las dos, aviso y latido): la URL
 177|    `https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-llamadas-ingesta` y la clave en `x-celular-credencial`.
 178| 5. Pruebas con datos móviles: A1, A3, las 1 y 6 de F3.3, y L1–L4 de §3c. La encuesta tiene que abrirse en todas las
 179|    llamadas de prueba antes de entregar el celular.
 180| 6. Comprobar en la base, sin ver números:
 181|    ```sql
 182|    select (select count(*) from private.llamadas_celular_recepciones r where r.asignacion_id = a.id) as recibidas,
 183|           (select count(*) from crm.llamadas_celular_eventos e where e.asignacion_id = a.id) as guardadas
 184|    from crm.celulares_asignaciones a where a.etiqueta = 'C1' and a.vigente_hasta is null;
 185|    ```
 186|    `recibidas` cuenta todas las salientes de prueba. `guardadas`, solo las de leads del ámbito del analista, sin dueño o
 187|    reutilizables. Un número sin lead o de un lead de otro analista se recibe y no se guarda (decisión 3). En la consulta
 188|    del paso 4: latido reciente y `eventos_en_cola = 0`.
 189| 
 190| ## 6. Pasar un celular a otro analista
 191| 
 192| La llamada se atribuye a la clave con la que llega. Una cola vieja enviada con la clave nueva quedaría a nombre del
 193| analista nuevo.
 194| 1. El analista deja de llamar desde ese celular.
 195| 2. Cola en 0: `cola_llamadas` vacía en el celular y, en la consulta del paso 4, `eventos_en_cola = 0` con
 196|    `ultimo_latido_en` posterior a su última llamada (la macro manda el latido cuando la cola se vacía).
 197| 3. Vaciar `errores_llamadas` (avisos del analista anterior, con sus números).
 198| 4. Gerencia cierra la asignación con `cerrar-celular.sql` (motivo `reemplazo`; los otros: `rotacion`,
 199|    `baja_analista`, `extravio`, `otro`).
 200| 5. Alta con la misma etiqueta y el analista nuevo (paso 4), y la clave nueva en la macro.
 201| 
 202| ## Reversa
 203| 
 204| **Solo antes de dar de alta ningún celular**: sin asignaciones (ni cerradas), estado, recepciones, llamadas, enlaces ni
 205| intenciones. Cada reversa lo comprueba bajo candado y, si no se cumple, se niega.
 206| - Base, una por mensaje: `reversa-enlace-exacto.sql` → `reversa-correccion.sql` → `reversa-elegibilidad.sql` →
 207|   `reversa-ingesta.sql` → `reversa-nucleo.sql` → `reversa-datos.sql` (conserva las tablas) o `reversa-datos-total.sql`
 208|   (las borra). Fuera de orden, cada una se niega.
 209| - La fila de `supabase_migrations.schema_migrations` se queda (regla de la casa, `scripts/potencial-lead/reversa.sql`):
 210|   anotar la reversa en `MIGRACIONES.md`.
 211| - Es más estricto que «antes del primer aviso» a propósito (revisión de Miguel en el #190): recepciones e intenciones
 212|   caducan a los 32 días y una asignación no se borra nunca. Las cabeceras de las dos migraciones nuevas todavía dicen
 213|   «antes del primer aviso» (están selladas por md5); valen los scripts y `MIGRACIONES.md`.
 214| - Edge: si ya se desplegó, borrarla. No hay una versión anterior desplegada.
 215| 
 216| **Después del alta no se revierte** (reinstalaría las fugas): se apaga y se corrige hacia adelante.
 217| - Borrar la Edge.
 218| - Cerrar cada asignación (`cerrar-celular.sql`).
 219| - En el celular, volver la URL de la «Solicitud HTTP» al receptor de pruebas y quitar la acción «Iniciar macro» de
 220|   «Llamadas-Al colgar»: con «Siempre iniciar», apagar «Enviar cola» no basta.
 221| - El arreglo va en una migración nueva.
```
