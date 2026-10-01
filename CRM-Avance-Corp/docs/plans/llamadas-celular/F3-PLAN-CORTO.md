# F3 · Captura, puertas y sincronización durable — plan corto (borrador para el OK de Miguel)

Claude, 01/10/2026. Solo análisis: **sin SQL ni código** hasta el OK. Sigue la §9 de `PLAN.md` (Versión 3 aprobada) y se apoya en lo que F2 ya dejó construido en `feat/llamadas-f2` (`eb73df1b`, `fda9310e`; sin aplicar). Abre un punto de entrada público con `verify_jwt = false` y una credencial por dispositivo → **LEVEL 3**: plan y OK de Miguel, banco, `auditor-rls` y Codex antes de aplicar.

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

| # | Decisión | Recomendación |
| --- | --- | --- |
| 1 | Excepción `verify_jwt = false` para la ingesta | Sí, como `crm-agenda-ics`: credencial por celular (solo su hash en la base), 401 uniforme, tope de cuerpo y límite |
| 2 | Límite por celular | 30 eventos por minuto y 600 por día; al pasarse, 429 con `Retry-After` |
| 3 | Salud del celular | Tabla mínima; latido cada 6 h y al vaciar la cola |
| 4 | Qué abre el celular tras guardar | La URL de F1 por número hasta que F4 tenga la ruta por evento; también tras un 202 «ignorada», para que el analista vea el aviso de F1 |
| 5 | Adaptador si MacroDroid no es durable | Documentar el límite y evaluar Tasker o una app mínima antes de prometer captura durable |

## Orden de trabajo (un PR por paso, cada uno con plan aprobado)

1. **F3-a · Base**: puerta de servicio, límite, salud y bandeja paginada; oráculo y mutantes en el banco reducido (`npm run test:llamadas:local`).
2. **F3-b · Edge Function**: `handler.ts` puro + `handler.test.ts` con la RPC inyectada (401 uniforme, 413, 400, 409, 429 con `Retry-After`, 201/200/202, nunca registra secretos). Esta máquina no tiene Deno: instalarlo pide el OK de Jhosep.
3. **F3-c · Macro**: tras las pruebas de C1 de arriba; guía en `macrodroid.md`.
4. **F3-d · Recuperación en C1** (F3.4): respuesta perdida tras guardar, ráfagas, bloqueo, batería, desfase, permisos revocados, dos llamadas al mismo número, rotación y analista de baja.

## Riesgos y límites

- El mayor riesgo es la durabilidad de MacroDroid: no está documentada y solo C1 puede probarla.
- Celular perdido: se rota la credencial (`rotar_credencial_celular`) y la anterior deja de entrar en el acto (F2-c ya lo prueba).
- Endpoint público: sin enumeración (401 igual para todo), tope de cuerpo, límite por celular y sin secretos en URL ni registros.
- Hasta F4 no hay pantalla de la bandeja: lo que F3 guarda se trabaja con las puertas de F2 y el aviso de F1.

---

**En llano:** F3 es la parte que hace que el celular avise solo al CRM de cada llamada, aunque no haya señal en ese momento. Antes de escribirla, hace falta que Miguel apruebe abrir esa entrada con una clave por celular, y que en el C1 se pruebe si MacroDroid puede guardar una cola que no se pierda.
