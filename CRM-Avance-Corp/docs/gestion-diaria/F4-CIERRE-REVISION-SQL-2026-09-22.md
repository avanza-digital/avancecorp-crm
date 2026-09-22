# F4 etapas 4–5 — revisión SQL recuperada

Estado: revisión previa al gate, CHANGES_REQUESTED. No equivale a instalación ni activación.

VERDICT:
CHANGES_REQUESTED

SUMMARY:
No encontré fugas de datos entre supervisores ni bypass de escritura en las rutas RPC y de INSERT directo. La identidad queda atada por `v_id`, que incluye `auth.uid()`, y porque el aviso se busca en la lista propia. El candado por usuario y el índice parcial cubren la carrera de aplazamiento. La entrega del popup queda separada del reconocimiento y es idempotente. Grants y RLS de las tablas nuevas son deny-by-default.

Sí hay hallazgos accionables antes del gate:
- el camino DEFINER anula la RLS que F4.3 declaraba como defensa en profundidad;
- los objetos nuevos no quedan sellados en `assert_*` (patrón de la casa);
- la publicación permite activar cortes y fijar una vigencia lejana que bloquea publicaciones futuras;
- el formato del id depende de `DateStyle`;
- hay detalles de errores, UX y tipos.

No hay P0 ni P1 demostrables con la evidencia adjunta.

FINDINGS:

[P2] El camino DEFINER anula la RLS del cómputo de cortes, contra el contrato escrito de F4.3
File: `20260922184459_crm_gestion_diaria_avisos.sql`; `20260921214018_crm_gestion_diaria_cortes.sql`
Lines: avisos 62-63, 89; cortes 137-139, 191-202
Problem:
- `private.gestion_diaria_avisos` es `SECURITY DEFINER` (owner `postgres`) y llama a `private.gestion_diaria_cortes` (INVOKER). Dentro, `crm.leads` (l.201) y `private.gestion_diaria_llamadas` se ejecutan como owner. Con RLS no forzada, la RLS no se aplica.
- F4.3 dice textualmente «El helper vuelve a filtrar identidades y usa RLS».
Evidence: l.62-63 (definer) → l.89 → cortes l.140-141 (invoker) → l.191 y l.201.
Impact:
- Hoy el alcance queda acotado por `v_ids` (subárbol activo), así que no veo fuga de filas.
- Se pierde la capa RLS. Además, el popup puede diferir del tablero (`gestion_diaria_equipo_fn` → `equipo_core`, cuyo modo desconozco): si RLS oculta actividades o leads al supervisor, el tablero diría «incumplido» y el popup no, o al revés.
- Hipótesis: falta la definición de `gestion_diaria_llamadas` y `equipo_core`.
Recommendation:
1. Confirmar el modo de ambas funciones.
2. Añadir una prueba de paridad: los miembros de `avisos_fn` deben ser iguales a los vendedores con `aviso_pendiente` en `equipo_fn` para el mismo supervisor e instante.
3. Actualizar el comentario de F4.3, o hacer que el DEFINER solo lea `entregas`/`control` y delegue el cómputo a una ruta invoker.

[P2] Los objetos nuevos no quedan sellados por el gate de asserts
File: ambas migraciones
Lines: avisos 263; configuración 137
Problem:
- F4.3 creó `assert_gestion_diaria_cortes` con hash de cuerpo, `prosecdef`, `proconfig`, owner, matriz EXECUTE, RLS, grants por columna y triggers.
- F4.4 y F4.5 añaden 7 funciones, 5 de ellas DEFINER expuestas a `authenticated`, 2 tablas, 1 trigger extendido y 1 CHECK reescrito. Ninguno entra al assert: el postflight solo re-ejecuta el existente.
Evidence: postflight `perform private.assert_gestion_diaria();` sin extender `assert_gestion_diaria()` (comparar con F4.3 l.353-362).
Impact: una deriva no se detecta. Ejemplos:
- un `grant select` heredado sobre `gestion_diaria_entregas`;
- EXECUTE a `anon` por default privileges;
- un `create or replace` que quite el gate de rol;
- la pérdida de la rama nueva en `alertas_reconocimientos_sellar`.
Recommendation: añadir `private.assert_gestion_diaria_avisos()` (y su equivalente de configuración) encadenado en `assert_gestion_diaria()`. Debe verificar:
- `relrowsecurity` y ausencia de privilegios de tabla/columna para `anon`, `authenticated` y `service_role` en ambas tablas;
- `prosecdef`/`proconfig`/owner/md5 de las funciones;
- EXECUTE solo para `authenticated` en las 5 públicas, y para nadie en las `private.*`;
- la presencia de `sellar_reconocimiento_corte` en el cuerpo del trigger;
- los triggers `trg_inmutable`/`trg_audit` habilitados (`'O'`);
- la existencia de la fila v1 de control.

[P2] Riesgo de huellas sobre el trigger y el CHECK de `alertas_reconocimientos`: otros asserts no se re-ejecutan
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 47-57, 172-186, 263
Problem:
- Se reescriben `crm.alertas_reconocimientos_sellar()` y `alertas_reconocimientos_alerta_id_check`.
- F4.3 corría en pre/postflight `assert_sla_nucleo/operacion/comandos/avisos`; F4.4 solo corre `assert_gestion_diaria`.
Evidence: F4.3 l.7-11 y l.372-376, contra F4.4 l.6 y l.263.
Impact: si algún assert existente hashea ese trigger o ese CHECK (hipótesis, no adjunto), F4.4 se instala bien pero rompe el preflight de la siguiente migración o un gate de CI.
Recommendation: incluir los `assert_sla_*` en pre/postflight de F4.4 y adjuntar cualquier assert que referencie `alertas_reconocimientos`.

[P2] Activación accidental: la puerta de publicación acepta `cortes_activos=true` y el canal nace habilitado
File: `20260922185138_crm_gestion_diaria_configuracion.sql`; `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: configuración 70-73 y 97; avisos 27-28
Problem:
- El objetivo de la etapa es «cortes productivos OFF».
- Tras F4.5, una sola llamada de gerencia vía PostgREST, con o sin UI, publica `cortes_activos:true` para mañana.
- El control v1 es `habilitados=true`, así que los popups salen solos al día siguiente. No existe un segundo interruptor independiente.
Evidence: la validación solo exige boolean (l.72-73). El seed del control está en l.27-28.
Impact: activación productiva por un clic o un script sin release explícito. Una vez publicada, la fila es inmutable: solo se revierte con otra versión futura, y el día ya publicado no se puede apagar salvo con el kill switch.
Recommendation: elegir una de dos opciones.
- Sembrar el control v1 con `habilitados=false`, lo que exige un acto separado para encender el canal.
- Rechazar en `publicar` `cortes_activos=true` hasta una migración de activación.

Cualquiera de las dos debe documentarse en el ledger.

[P2] Una vigencia lejana bloquea toda publicación posterior sin vía de corrección
File: `20260922185138_crm_gestion_diaria_configuracion.sql`; `20260921214018_crm_gestion_diaria_cortes.sql`
Lines: configuración 64; cortes 80-82
Problem:
- `publicar` solo exige `isfinite(p_vigente_desde)`.
- El trigger rechaza `new.vigente_desde < v_ultima.vigente_desde`.
Evidence: un typo como `2099-10-01` es válido: es medianoche Lima y es futuro.
Impact: desde ese momento ninguna revisión puede tener vigencia anterior a 2099. La tabla es inmutable (`trg_config_inmutable`), así que la única salida es una migración de owner que desactive triggers.
Recommendation: acotar el horizonte en `publicar`, por ejemplo `p_vigente_desde <= inicio_de_hoy + 90 días`, y probarlo.

[P3] El id del corte depende de `DateStyle`
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 105 (contra CHECK l.56)
Problem: `v_uid || ':' || v_dia` usa `date::text`, que respeta `DateStyle`. La función no fija `datestyle` en `proconfig`.
Impact:
- Si el rol o la base (o el pooler) tienen `DateStyle='SQL, DMY'`, el id sería `22/09/2026`.
- El listado seguiría consistente, pero todo INSERT fallaría con `23514` contra el CHECK `YYYY-MM-DD`.
Recommendation: usar `to_char(v_dia, 'YYYY-MM-DD')`.

[P3] La foto de `miembros` se guarda pero no gobierna el estado
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 111-112, 164-165
Problem:
- `v_estado` depende solo de la última acción.
- Si un vendedor nuevo entra en incumplido (reasignación al subárbol, o cartera que pasa a abierta), una alerta ya reconocida o entregada no reaparece.
- El contrato F4.1 dice «AMBOS ceden si el grupo EMPEORA». Para cortes, ese estado lo calcula el servidor y el front no puede revivirlo.
Recommendation: definir si en cortes basta con «una vez por día y corte». Si no, comparar `miembros` actuales contra `v_ultimo.miembros` en l.111 y documentar la decisión.

[P3] 42501 para una carrera normal
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 151-153
Problem: si todos los miembros se recuperan entre el render y el clic, reconocer devuelve `42501`. Ese mismo código se usa para «ajeno».
Impact: el front puede tratarlo como pérdida de acceso.
Recommendation: validar primero que el uuid del id sea `auth.uid()` (`42501`). Para «ya no pendiente», usar `22023` o `P0002`.

[P3] `LIKE 'grupo:corte_%'`: el `_` es comodín
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 52, 179, 208
Impact: nulo hoy, porque el CHECK regex acota los ids, pero es frágil ante tipos futuros.
Recommendation: usar `starts_with(alerta_id, 'grupo:corte_')` o escapar el `_` (`'grupo:corte\_%'`).

[P3] Enteros como `3.0` fallan con 22P02 en lugar de 22023
File: `20260922185138_crm_gestion_diaria_configuracion.sql`
Lines: 80-82, 97-101
Problem: `3.0` pasa la guarda `= trunc`, pero `('3.0')::integer` lanza `22P02`.
Recommendation: castear con `::numeric::integer`. Validar rangos antes del INSERT para devolver `22023` en lugar de `23514`.

[P3] `puede_editar` puede ser `null`
File: `20260922185138_crm_gestion_diaria_configuracion.sql`
Lines: 39
Problem: para directorio sin membresía, `rol_crm` es null.
Recommendation: `coalesce(... , false)`.

[P3] Precedencia implícita en la revalidación de `presentar`
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 240-241
Problem: el resultado es correcto (`AND` antes que `OR`), pero la intención depende de esa precedencia implícita.
Recommendation: agregar paréntesis explícitos alrededor de `(not ... and v_anterior.id is null)`.

[P3] Aplazamiento dentro de la última hora
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 117, 162
Problem: a las 17:30 L-V, `pospuesto_hasta` es 18:30 y nunca habrá reaviso. Cumple «sin reaviso al cierre», pero la UI mostraría una hora posterior al cierre.
Recommendation: exponer `least(hasta, fin_jornada)` o un flag `sin_reaviso`, y documentarlo.

[P3] Reconocer repetido y cómputo doble
File: `20260922184459_crm_gestion_diaria_avisos.sql`
Lines: 154, 188-214
Problem:
- Se puede reconocer indefinidamente con nuevas solicitudes, lo que genera filas y audit_log.
- `reconocer` calcula `gestion_diaria_avisos` dos veces bajo candado (sellado y retorno).
Impact: ruido en el ledger y latencia.
Recommendation: tratar `reconocer` sobre `estado='reconocido'` como no-op idempotente. Es opcional.

TEST GAPS:
Escenarios concretos para `test-rls.mjs` y el ensayo:
- **Ajeno:**
  - supervisor A llama `reconocer_corte`/`presentar_corte` con el id de B, y hace POST directo a `alertas_reconocimientos` con el id de B → `42501`;
  - A no ve filas de B en SELECT.
- **INSERT directo con campos forjados:** `hasta` a +7d, `creado_en` pasado, `severidad='critica'`, `miembros` inventados y `solicitud_corte_id` arbitrario → todo sobrescrito, `hasta = creado_en + 1h`.
- **Legacy con `solicitud_corte_id`:** POST legacy → `22023`. Las 4 rutas legacy siguen iguales: owner-check, tope de 7 días, miembros regex.
- **Carrera de aplazamiento:** dos conexiones pospusieron a la vez, una por RPC y otra por INSERT directo → exactamente 1 fila; la otra recibe `22023` o `23505`.
- **Presentar concurrente:** dos sesiones con `solicitud_id` distinto → exactamente un `aviso` no nulo y 1 fila en `entregas`.
- **Reintento de presentar con la misma solicitud:**
  - tras pérdida de respuesta → mismo aviso, sin fila nueva;
  - tras apagar el canal, tras `fin_jornada`, tras pospuesto o reconocido → `aviso: null`;
  - con otra alerta → `22023`;
  - la misma solicitud reutilizada para entrega 1 → `null` (documentar que el cliente genera la solicitud por alerta y entrega).
- **Reintento de reconocer:** la misma solicitud con otra acción o alerta → `22023`; la misma solicitud idéntica → sin fila nueva.
- **Bordes de calendario (hora de servidor forzada vía banco):**
  - L-V 09:00, `corte_1_hora ± 1µs`, `corte_2_hora`, 17:59:59 y 18:00;
  - sábado 12:59/13:00 sin `corte_tarde`;
  - domingo → `[]`;
  - posponer a las 17:30 → sin reaviso;
  - intento el día siguiente con el id de ayer → `42501`.
- **Cartera vacía:** vendedor sin leads abiertos → no es miembro; en cartera abierta a mitad de día → comportamiento documentado.
- **Jerarquía:**
  - un vendedor de un sub-supervisor aparece en ambos popups (confirmar que se desea);
  - vendedor con `equipo.activo=false`, con `perfiles.activo=false` o movido de subárbol → excluido;
  - supervisor inactivo y superadmin con membresía supervisor → `42501`.
- **Roles:**
  - gerencia, directorio, coordinador y vendedor → `42501` en `avisos_fn`, `reconocer` y `presentar`;
  - anon → `permission denied` al ejecutar;
  - authenticated no puede ejecutar ninguna `private.*` nueva.
- **Control:**
  - con el canal OFF, los cálculos y estados de `avisos_fn` son idénticos y solo cambian `puede_*`;
  - reconocer sigue permitido con el canal OFF (confirmar que se desea);
  - el efecto es inmediato en la siguiente llamada;
  - `expected_version` desactualizada → `40001`.
- **Publicación:**
  - claves extra o faltantes; `"3"` como string; `3.0`; `3.5`; `null` fuera de `tasa`;
  - `24:00`, `9:30`, `corte_2 ≤ corte_1`;
  - vigencia hoy, ayer, no-medianoche y a 10 años;
  - dos publicaciones concurrentes con el mismo `expected` → una `40001`;
  - la revisión pendiente se lista, y la de hoy aparece como vigente y no como pendiente.
- **`DateStyle`:** `set datestyle='SQL, DMY'` y luego avisos más reconocer.
- **Paridad:** miembros de `avisos_fn` = vendedores con `aviso_pendiente` en `gestion_diaria_equipo_fn` en el mismo instante.
- **Caducidad:** `caducar_alertas_reconocimientos()` sigue borrando filas de corte de más de 90 días; `entregas` y `control` rechazan UPDATE/DELETE, incluso como owner.

ARCHITECTURE RISKS:
- `gestion_diaria_entregas` crece sin caducidad, a diferencia del ledger de 90 días. La diferencia de retención debería documentarse en el ledger.
- El candado `hashtext(uid)` puede colisionar entre usuarios: solo serializa, no afecta la corrección. Conviene confirmar que las claves 194203/194204 no se reusan en otro lugar.

SECURITY RISKS:
- Los DEFINER tienen gates de rol correctos y `search_path=''`. El principal riesgo es la deriva no sellada (ver P2 de asserts).
- `service_role` pierde todo sobre las tablas nuevas. Debe quedar documentado en `MIGRACIONES.md`, que no se adjuntó, así que no pude verificar el estado honesto del ledger.

REGRESSION RISKS:
- F4.2 lee `alertas_reconocimientos` directamente y aplica la regla de 7 días en el front. Las filas nuevas con `grupo:corte_*` aparecerán en su SELECT y en la vista de gerencia. Hay que verificar que `lib/alertas.ts` ignora ids desconocidos (hipótesis).
- La reescritura del CHECK revalida filas existentes y toma ACCESS EXCLUSIVE brevemente.

RECOMMENDED NEXT ACTIONS:
1. Extender `assert_gestion_diaria()` con un `assert_*_avisos` y `_configuracion` que selle grants, RLS, DEFINER, hashes, triggers y la rama del trigger extendido. Correr los `assert_sla_*` en F4.4.
2. Decidir el doble interruptor de activación (control v1 OFF o bloqueo de `cortes_activos=true`) y acotar el horizonte de `vigente_desde`.
3. Aclarar la RLS del camino DEFINER con la definición de `gestion_diaria_llamadas` y `equipo_core`, y añadir la prueba de paridad.
4. Fijar el formato del id con `to_char`, y corregir los P3 de códigos de error, casts y `coalesce`.
5. Adjuntar `MIGRACIONES.md` y los asserts que referencien `alertas_reconocimientos` para la segunda revisión, si procede.

CONFIDENCE:
MEDIUM. El análisis es alto sobre el SQL adjunto, pero no se adjuntaron `gestion_diaria_llamadas`, `equipo_core`, `trg_config_versionada_inmutable`, los `assert_sla_*`, el ledger ni el front F4.2.
