# F3 · Captura, puertas y sincronización durable — plan corto (borrador para el OK de Miguel)

Claude, 01/10/2026. Solo análisis: **sin SQL ni código** hasta el OK. Sigue la §9 de `PLAN.md` (Versión 3 aprobada) y se apoya en lo que F2 ya dejó construido en `feat/llamadas-f2` (`eb73df1b`, `fda9310e`; sin aplicar). Abre un punto de entrada público con `verify_jwt = false` y una credencial por dispositivo → **LEVEL 3**: plan y OK de Miguel, banco, `auditor-rls` y Codex antes de aplicar.

**Actualización 01/10, 21:10 UTC:** con las decisiones 1–4 que Jhosep tomó como provisionales (abajo), F3-a se construye en `feat/llamadas-f2` y se prueba en el banco reducido local, como F2. Nada se aplica al Supabase compartido ni a `main` sin el OK de Miguel.

## En una línea

Con F2 la base sabe guardar y trabajar llamadas; con F3 **el celular las envía solo**: al colgar, MacroDroid guarda el evento en su cola, lo manda a una Edge Function con la credencial del celular, la base lo guarda una sola vez aunque el envío se repita, y el celular abre la encuesta. Si MacroDroid no demuestra una cola durable en C1, el plan manda documentar el límite y evaluar otro adaptador antes de prometer captura durable.

## Lo que ya existe y no se rehace

| Puerta de la §9 | Ya construida en F2-c (`fda9310e`) | Lo que añade F3 |
| --- | --- | --- |
| Ingerir evento (solo servicio) | Núcleo `private.llamada_celular_ingerir` (idempotente, `P0409`, decisiones 2 y 3) | Puerta de servicio + Edge Function |
| Listar accionables paginados | `crm.llamadas_celular_pendientes_fn` (límite 1–200) | Cursor por (`recibido_en`, `id`) en una puerta nueva, sin cambiar la de F2 |
| Obtener por UUID | `crm.llamada_celular_detalle_fn` (explica registrado, descartado y efectos deshechos) | — |
| Resolver/asociar lead | `crm.asociar_llamada_celular` | — |
| Enlazar actividad existente | `crm.enlazar_llamada_celular` | F4 lo compone con v4 en una transacción (`registrar_llamada_v5`, propuesta #4) |
| Descartar con motivo | `crm.descartar_llamada_celular` | — |
| Listar/alta/baja/rotar celular | `celulares_asignaciones_fn`, `asignar_celular`, `cerrar_asignacion_celular`, `rotar_credencial_celular` | La pantalla de gerencia llega en F4 |
| Registrar salud | — | Tabla mínima + puerta de servicio (decisión 3) |

Precedentes del repo que se copian: **`crm-agenda-ics`** (`verify_jwt=false` porque el cliente no tiene JWT; token validado por una RPC solo de servicio; respuesta uniforme cuando no autoriza) · **`crm-notificaciones-tasa`** (`index.ts` corto + `handler.ts` puro con dependencias inyectadas y `handler.test.ts`; cuerpo leído por partes con tope de 4 096 bytes → 413; `P0429` → 429) · `private.celular_credencial_hash` (F2-c) · regla de `supabase/functions/LEEME.md`: toda función desplegada tiene su fuente aquí y `service_role` jamás sale de las Functions.

## Diseño propuesto (descripción, no código)

**Edge Function `crm-llamadas-ingesta`** (solo del CRM, sin espejo en `_supabase_functions`):

- `verify_jwt = false` en `supabase/config.toml` con su comentario, como `crm-agenda-ics`: el control alternativo es la credencial del celular. Solo `POST`; sin CORS (no la llama un navegador); `Content-Type: application/json`.
- Cuerpo leído por partes con tope de 4 KB (413) y claves exactas del contrato que F2 ya valida: `v`, `evento_origen_id`, `numero`, `direccion`, `estado_tecnico`, `duracion_seg`, `ocurrio_en`.
- Credencial en la cabecera `x-celular-credencial` (64 hex). Nunca en la URL; la función no registra cabeceras ni cuerpo.
- Llama con la clave de servicio (secreto de Supabase) a una sola RPC: `crm.ingerir_llamada_celular_servicio(p_credencial text, p_evento jsonb)`.
- Respuestas: `201 {evento_id, repetido:false, abrir}` · `200 {…, repetido:true}` · `202 {ignorado:true, motivo, abrir}` (sin lead o entrante apagada: no se reintenta) · `400` cuerpo inválido · `401` **uniforme** (credencial ausente, inválida, revocada o analista de baja: no se distingue, para no dar pistas) · `409` (`P0409`) · `413` · `429` con `Retry-After` · `503` transitorio. El celular reintenta solo ante red, 429 o 5xx.
- `abrir` = la URL que el celular abre después: hoy la de F1 por número (`#/gestion-diaria/llamada/<numero>`); cuando F4 tenga la ruta por evento, la del UUID (F3.3.3: fallback manual si falta el UUID).

**Migración F3-a (base):**

- `crm.ingerir_llamada_celular_servicio(text, jsonb)`: DEFINER, `search_path` vacío, **EXECUTE solo `service_role`**. Calcula el hash, busca la asignación vigente por `credencial_hash` (único desde F2-b), aplica el límite y delega en el núcleo. Cualquier problema de credencial → el mismo 42501.
- Límite por celular: tabla mínima de ventanas por minuto y por día (`crm.celulares_ingesta_ventanas`), con su RLS sin policies, auditoría y purga; `P0429` al pasarse (decisión 2).
- Salud: tabla `crm.celulares_salud` (una fila por asignación: último contacto, versión de la macro, eventos en cola) y `crm.registrar_salud_celular_servicio(text, jsonb)` solo de servicio. Un latido no demuestra captura sana: solo dice que el celular habla.
- Bandeja paginada: puerta nueva con cursor; `llamadas_celular_pendientes_fn` queda como está (no se toca una puerta ya escrita).
- Tipos: `npm run gen:types` tras aplicar, para los consumidores de F4 (F3.1.3).

## Lo que Jhosep tiene que demostrar en C1 antes de escribir la macro (F3.3)

Cada punto con PASS/FAIL en `docs/gestion-diaria/piloto-telefonia/REGISTRO.md`, sin números reales:

1. La acción «HTTP Request» hace `POST` con la cabecera `x-celular-credencial` y un cuerpo JSON que lleva `{call_number}`, y guarda el código y el cuerpo de la respuesta en variables.
2. Un id de origen estable por llamada (por ejemplo `C1-` + la hora del sistema en milisegundos), creado UNA vez en «Call Ended» y reutilizado en cada reintento.
3. Una cola persistente: el evento se guarda en una variable global ANTES del envío y se borra solo tras 200, 201 o 202; sobrevive a reiniciar MacroDroid y el celular.
4. Reintento: sin red, 429 o 5xx espera y reintenta; al volver la conexión, vacía la cola.
5. Doble disparo: si «Call Ended» salta dos veces para una llamada, ¿mismo id o dos? (F3.3.4).
6. Dónde vive la credencial en el celular y si el registro de MacroDroid muestra las cabeceras de «HTTP Request» (no debe).

Si 3 o 4 fallan, MacroDroid no acredita durabilidad: se documenta el límite y se evalúa otro adaptador (F3.4.3) antes de seguir.

## Decisiones que necesita Miguel

Miguel no estaba disponible el 01/10. **Jhosep tomó las decisiones 1 a 4 como provisionales** (formulario, 01/10 hacia las 21:10 UTC) para que F3-a avance en el banco local; Miguel las ratifica o las cambia con él. La 5 depende de las pruebas en C1.

| # | Decisión | Recomendación | Lo que decidió Jhosep (provisional) |
| --- | --- | --- | --- |
| 1 | Excepción `verify_jwt = false` para la ingesta | Sí, como `crm-agenda-ics`: credencial por celular (solo su hash en la base), 401 uniforme, tope de cuerpo y límite | **Sí, clave por celular.** Preguntó cómo llena la encuesta un analista sin sesión: la clave solo deja el aviso de la llamada; la encuesta la llena el analista en la app con su sesión (si no la tiene, el CRM le pide entrar y el enlace sobrevive al login, F1.2.2) |
| 2 | Límite por celular | 30 eventos por minuto y 600 por día; al pasarse, 429 con `Retry-After` | **La recomendada:** 30 por minuto y 600 al día |
| 3 | Salud del celular | Tabla mínima; latido cada 6 h y al vaciar la cola | **La recomendada:** cada 6 h y al vaciar la cola |
| 4 | Qué abre el celular tras guardar | La URL de F1 por número hasta que F4 tenga la ruta por evento; también tras un 202 «ignorada», para que el analista vea el aviso de F1 | **La recomendada:** la encuesta de F1 por número |
| 5 | Adaptador si MacroDroid no es durable | Documentar el límite y evaluar Tasker o una app mínima antes de prometer captura durable | Pendiente: depende de las pruebas 3 y 4 en C1 |

## Orden de trabajo (un PR por paso, cada uno con plan aprobado)

1. **F3-a · Base**: puerta de servicio, límite, salud y bandeja paginada; oráculo y mutantes en el banco reducido (`npm run test:llamadas:local`).
2. **F3-b · Edge Function**: `handler.ts` puro + `handler.test.ts` con la RPC inyectada (401 uniforme, 413, 400, 409, 429 con `Retry-After`, 201/200/202, nunca registra secretos). Esta máquina no tiene Deno: instalarlo pide el OK de Jhosep.
3. **F3-c · Macro**: tras las pruebas de C1 de arriba; guía en `macrodroid.md`.
4. **F3-d · Recuperación en C1** (F3.4): respuesta perdida tras guardar, ráfagas, bloqueo, batería, desfase, permisos revocados, dos llamadas al mismo número, rotación y analista de baja.

## Estado de F3-a (01/10/2026, 21:35 UTC)

**Construida y probada en el banco reducido local, sin aplicar** (`11c5be43`): migración `20261001212258_crm_llamadas_celular_ingesta.sql`, reversa `scripts/llamadas-celular/reversa-ingesta.sql` y oráculo `tests/llamadas-celular/oraculo-ingesta.sql`.

- Puertas de servicio `crm.ingerir_llamada_celular_servicio(text, jsonb)` y `crm.registrar_salud_celular_servicio(text, jsonb)`, con EXECUTE solo para `service_role`. Clave ausente, desconocida, cerrada o de un analista de baja: el mismo 42501 «No autorizado», también en carrera con una rotación. A la Edge solo le devuelven `evento_id`, `repetido`, `ignorado` y `motivo`.
- Límite de la decisión 2 en la política (`limite_envios_minuto` 30 y `limite_envios_dia` 600), compartido por llamadas y latidos. Al pasarse, P0429 con `reintentar_en_seg=N` en el DETAIL, para el `Retry-After` de la Edge.
- Salud de la decisión 3: latido v1 (`version_macro`, `en_cola` y `ocurrio_en` opcional) y lectura por rol con `crm.celulares_salud_fn`.
- Bandeja paginada `crm.llamadas_celular_bandeja_fn(límite, recibido_en, evento_id)`, con las mismas filas que la de F2-c.

Verificación: `npm run test:llamadas:local` → **138/138** (oráculo con 32 defensas, 36/36 mutantes cazados y la carrera de rotación). **NOT RUN:** banco con el esquema de producción, `test-rls.mjs`, advisors reales, Codex LEVEL 3 y `gen:types`. La lista de `auditor-rls` se pasó en línea, sin agente.

**Cambios respecto al diseño de arriba (decisiones de criterio de Claude, para Miguel):**

- Límite y salud viven en una sola tabla técnica, `private.celulares_estado`, en vez de `crm.celulares_ingesta_ventanas` más `crm.celulares_salud`. Es una fila por celular y no necesita purga. Queda fuera de la regla de rastro, como las colas y los contadores del repo: en `crm` habría que auditarla, y cambia con cada envío.
- La decisión 4 (qué abre el celular) no toca la base: la resuelve la Edge en F3-b.

**Hallazgos:**

- **Propuesta #12** (`PROPUESTAS-DE-AJUSTE.md`): la respuesta al celular no debe delatar si un número es de un lead.
- **F2-c, comprobado en un banco desechable (01/10, 21:50 UTC):** la llamada del celular de un **supervisor** a un lead de su equipo entra «por revisar» y nunca pide resultado, lo que contradice la decisión 1. Con el celular del analista, la misma llamada entra «requiere resultado». Causa: `private.llamada_celular_elegible` da `true` evaluada con la sesión del supervisor y `false` sin ella, porque `private.vendedor_ids_visibles` se niega si el actor no es quien llama, y la ingesta no tiene sesión. El flujo de F1 no depende de esto: abre la encuesta por número con la sesión. **Corregido el 01/10 con el OK de Jhosep** en `20261001222431` (`3faabcd0`): la ingesta evalúa la elegibilidad con la regla real como el dueño del celular y devuelve la identidad antes de escribir. Banco local 160/160 y 7/7 mutantes cazados; sin aplicar.

**Siguiente: F3-b, la Edge Function.** Para correr `handler.test.ts` hace falta instalar Deno en esta máquina, y eso pide el OK de Jhosep. Sin Deno, el código quedaría escrito sin probar.

## Estado de F3-b (01/10/2026, 22:43 UTC)

**Construida y probada, sin desplegar** (`ad4cf226`): `supabase/functions/crm-llamadas-ingesta/` con `index.ts` (cliente de servicio y las dos RPC de F3-a), `handler.ts` (lógica pura con dependencias inyectadas, molde `crm-notificaciones-tasa`) y `handler.test.ts`; bloque en `supabase/config.toml` con `verify_jwt = false` y su motivo; entrada en `supabase/functions/LEEME.md`. Deno 2.9.4 instalado en `~/.local/deno` con el OK de Jhosep (zip oficial, sha256 verificado).

Contrato con el celular (POST con `Content-Type: application/json` y la clave en `x-celular-credencial`):

| Cuerpo | Respuesta |
| --- | --- |
| `{"accion": "llamada", "evento": {…v1…}}` | **202** `{recibido: true, abrir}`, igual si la llamada se guardó, se repitió o se ignoró (propuesta #12); `abrir` = la encuesta de F1 por número (decisión 4) o Mi día si no hay número |
| `{"accion": "latido", "latido": {v, version_macro, en_cola, ocurrio_en?}}` | **200** `{registrado: true}` |
| Clave ausente, mal formada o rechazada por la base | **401** `{error: "No autorizado"}`, siempre igual |
| Cuerpo inválido · demasiado grande · no JSON · otro método | **400** · **413** · **415** · **405** |
| Mismo origen con otro contenido · límite | **409** · **429** con `Retry-After` y `reintentar_en_seg` |
| Cualquier otro fallo | **503**: el celular reintenta |

Verificación: `npm run test:llamadas-ingesta` (deno check + 16 pruebas) en verde y `npm run test:llamadas-ingesta:mutantes` → 14/14 mutantes del handler cazados. **NOT RUN:** despliegue (Miguel), prueba contra la base real y desde C1.

Decisión de criterio de Claude, para Miguel: la Edge ya responde igual a guardada, repetida e ignorada (la variante segura de la propuesta #12) mientras él decide; con la decisión 4 el celular no necesita el UUID.

**Siguiente: F3-c, la macro**, después de las 6 pruebas de MacroDroid en C1 (sección de arriba). Las pruebas 1, 4 y 6 necesitan una URL que conteste: puede servir esta Edge cuando Miguel la despliegue, o un receptor de pruebas con datos inventados.

## Riesgos y límites

- El mayor riesgo es la durabilidad de MacroDroid: no está documentada y solo C1 puede probarla.
- Celular perdido: se rota la credencial (`rotar_credencial_celular`) y la anterior deja de entrar en el acto (F2-c ya lo prueba).
- Endpoint público: sin enumeración (401 igual para todo), tope de cuerpo, límite por celular y sin secretos en URL ni registros.
- Hasta F4 no hay pantalla de la bandeja: lo que F3 guarda se trabaja con las puertas de F2 y el aviso de F1.

---

**En llano:** F3 es la parte que hace que el celular avise solo al CRM de cada llamada, aunque no haya señal en ese momento. Antes de escribirla, hace falta que Miguel apruebe abrir esa entrada con una clave por celular, y que en el C1 se pruebe si MacroDroid puede guardar una cola que no se pierda.
