# F2 · Núcleo confiable y contrato de datos — plan corto (borrador para el OK de Miguel)

Claude, 30/09/2026. Solo análisis: **sin SQL, sin migraciones, sin código**. Sigue la §8 de `PLAN.md` (Versión 3 aprobada) y se apoya en el catálogo real (migraciones citadas). Se aplica el estándar de 4 capas tal como el CRM lo mapea: tablas en `crm` con RLS, núcleo en `private`, puertas = funciones no trigger de `crm`. Toca tablas, RLS y puertas → **LEVEL 3**: banco Docker, gate RLS antes y después, `auditor-rls`, revisión Codex (1, máx. 2) y OK de Miguel antes de escribir.

## En una línea

Con F1, la llamada del celular **no deja huella propia**: solo existe la actividad que el analista registra en la encuesta. F2 crea la evidencia del evento (qué celular, qué número, cuándo, con qué calidad), su asociación al lead y el enlace uno-a-uno con la actividad registrada, con las reglas en la base. Es el núcleo que F3 (captura durable desde el celular) y F4 (confirmación en pantalla) consumirán. Ninguna pantalla cambia en F2.

## Lo que ya existe y se reutiliza (catálogo real)

| Pieza existente | Dónde | Cómo la usa F2 |
| --- | --- | --- |
| `crm.equipo` (perfil_id, rol_crm, supervisor_id, activo) | `20260709000001` | Actor histórico de cada asignación de celular; roles para RLS |
| `crm.leads.telefono` (trigger `private.normalizar_telefono`) y `telefono_alternativo` (`private.canonizar_contacto`) | `20260709000001`, `20260826182000` | Match exacto en SQL con las **dos formas canónicas**, la misma regla que hoy aplica `lib/coincidencia-telefono.ts` en la pantalla |
| `crm.actividades` (log inmutable; `metadata.evento = resultado_llamada`, `resultado`, `tarea_id`, `siguiente_id`, `deshecho_en`) | `20260709000001`, `20260921153654` | Destino del enlace evento→actividad; «efectos deshechos» se leen de `deshecho_en`, no se duplica actividad |
| `private.llamada_registrar_v4` + `crm.registrar_llamada_v4` (selladas por md5) y `crm.sla_operacion_recibos` | `20260921153654`, `20260907025220` | El registro comercial sigue por ahí **sin cambios**; F2 solo enlaza el evento con la actividad que v4 deja |
| `private.sla_gestion_permitida(actor, lead)`, `private.vendedor_ids_visibles`, `private.rol_crm` | `20260907025220`, `20260709000001` | Ámbito para listar, asociar y enlazar |
| `private.log_audit_crm` / `private.log_audit_sin_secretos` | `20260829233000` | Trigger de auditoría de toda tabla nueva; la de asignaciones enmascara el hash de credencial |
| Patrón de idempotencia clave + hash SHA-256 (`crm.multiempresa_idempotencia`, `private.contrato_altas_idempotentes`) | `20260903160000`, `20260905190000` | Unicidad del evento: mismo origen + mismo hash → mismo ID; distinto hash → conflicto `23505` |
| Singleton de perillas (`crm.politica_abandono`) | `20260816221500` | Retención por estado, editable por gerencia |
| Gate `supabase/scripts/test-rls.mjs` (bloques `testGestionDiaria*`, banderas `CRM_RLS_EXIGE_*`) | `supabase/scripts/` | Bloque nuevo `testLlamadasCelular` con su bandera |

## Diseño de datos propuesto (F2.2) — descripción, no SQL

| Entidad lógica del plan | Propuesta física | Justificación |
| --- | --- | --- |
| Asignaciones de celulares | `crm.celulares_asignaciones`: id · `etiqueta` (C1, C2…) · `actor_id` → `crm.equipo` · `credencial_hash` (SHA-256; la clave nunca se guarda) · `vigente_desde` / `vigente_hasta` · `creado_por`, `creado_en`, `actualizado_en`, `activo`. **Restricción de exclusión**: una sola vigencia por etiqueta. Una rotación = cerrar la vigencia y abrir otra fila; el actor histórico **no se sobrescribe** | El plan exige actor histórico; MacroDroid no autentica, así que F3 necesitará una credencial por celular y aquí vive solo su hash |
| Eventos | `crm.llamadas_eventos`: id · `asignacion_id` → asignaciones · `origen_id` (id estable que define F3) · `hash_payload` (SHA-256 canónico) · `numero_canonico` E.164 nullable · `numero_crudo` nullable (**solo si Miguel lo autoriza**, con retención corta) · `direccion` (`saliente` / `entrante` / `desconocida`) · `estado_tecnico` (`conectada` / `no_atendida` / `rechazada` / `cancelada` / `desconocido`) · `duracion_seg` nullable · `ocurrido_en` nullable (hora del celular) · `recibido_en` not null (servidor) · `calidad_origen` · `identificacion` (`sin_identificar` / `ambiguo` / `identificado`) · `atencion` (`por_revisar` / `requiere_resultado` / `requiere_devolucion` / `registrado` / `descartado_con_motivo`) · `lead_id` nullable · `metodo_asociacion` (`exacto` / `manual` / `propuesto_confirmado`) · `asociado_por`, `asociado_en` · `motivo_descarte` (obligatorio si descartado) · `actor_id` (resuelto de la asignación al recibir) · `creado_en`. **Único** `(asignacion_id, origen_id)`. Trigger: el payload (número, dirección, estado, duración, horas, hash) es **inmutable**; solo cambian identificación, atención, lead, método y motivo, con transiciones permitidas | Todas las dimensiones del plan separadas; cero no prueba nada, duración desconocida es `null`; el payload inmutable hace honesta la idempotencia |
| Asociación y atención | Columnas de `llamadas_eventos` (arriba) + trigger de transiciones: `por_revisar → identificado/requiere_resultado` (asociar), `→ descartado_con_motivo` (descartar), `requiere_resultado → registrado` (enlazar). Cada transición queda en `public.audit_log` | El plan lo permite «agrupado en una tabla»; una tabla aparte de estados no tiene consumidor todavía |
| Enlace a actividad | `crm.llamadas_enlaces`: `evento_id` PK → eventos · `actividad_id` **único** → `crm.actividades` · `lead_id` · `actor_id` · `creado_en`. Trigger: la actividad es `llamada_realizada` / `llamada_no_contestada`, del mismo lead y de autor compatible; la inserción y el paso a `registrado` van en la misma transacción | Uno a uno en los dos sentidos y auditable sin ensuciar el evento |
| Auditoría y salud | Sin tabla nueva: `public.audit_log` por trigger + columna `salud` jsonb acotada en eventos (errores de canonización, desfase de reloj). Errores de ingesta y reintentos: tabla de control de F3 | Mínimos datos, ningún secreto |
| Retención | Singleton `crm.llamadas_politica`: días para `sin_identificar`, `descartado_con_motivo`, `numero_crudo`; cron de purga (patrón de los cron existentes) | §15 del plan: nada indefinido por omisión |

Índices mínimos: `(actor_id, atencion)` para la bandeja; `(numero_canonico)` para match e histórico; `(lead_id)`. Sin particionado: el volumen del piloto es de decenas de eventos al día.

## Núcleo y puertas (F2.3)

Núcleo en `private` (`security definer`, `set search_path = ''`, nombres calificados, verificación explícita de actor y ámbito), una operación completa y atómica cada una:

- `private.llamada_evento_ingerir(asignacion, origen_id, payload)` — idempotente por origen + hash; resuelve `actor_id` de la asignación vigente; canoniza el número con las dos reglas; intenta el match exacto entre leads vivos del actor; fija identificación y atención (único gestionable → `requiere_resultado`; varios → `ambiguo` / `por_revisar`; ninguno → `sin_identificar` / `por_revisar`; entrante perdida → `requiere_devolucion`, **desactivado si Miguel acepta la propuesta #8**).
- `private.llamada_evento_asociar(evento, lead, metodo)` — manual o propuesta confirmada; revalida `sla_gestion_permitida`; nunca fabrica gestión.
- `private.llamada_evento_enlazar(evento, actividad)` — 1:1, compatibilidad autor/lead/tipo, atómica; deja el evento en `registrado`.
- `private.llamada_evento_descartar(evento, motivo)` — motivo del catálogo, auditado; el evento no se borra.
- `private.celular_asignar / rotar / dar_de_baja` — gerencia (y supervisor para su equipo, si Miguel quiere).

Puertas en `crm` (validan input, resuelven `auth.uid()`, delegan): `crm.llamadas_eventos_pendientes_fn` (INVOKER, RLS; bandeja por actor), `crm.llamada_evento_detalle_fn`, `crm.llamada_evento_asociar`, `crm.llamada_evento_enlazar`, `crm.llamada_evento_descartar`, `crm.celulares_asignaciones_fn` + `crm.celular_asignar`. La **ingesta desde el celular no es puerta de F2**: llega en F3 como Edge Function que valida la credencial de la asignación y llama al núcleo; en F2 la ingesta solo se ejercita en el banco.

RLS y permisos: eventos y enlaces visibles por `actor_id` propio, supervisor su equipo (`vendedor_ids_visibles`), gerencia todo; asignaciones solo gerencia/supervisor; **sin policy DELETE**; `anon` sin nada; `authenticated` solo SELECT por las funciones; `EXECUTE` únicamente en las puertas; `REVOKE` del núcleo a `public, anon, authenticated, service_role` como hace `sla_gestion_permitida`. Excepción single-tenant documentada como en las demás puertas DEFINER del CRM.

## Contrato (F2.1) — decisiones que necesita Miguel

| # | Decisión | Recomendación |
| --- | --- | --- |
| 1 | Elegibilidad comercial | Lead `activo`, etapa no terminal, sin `no_contactar`, dentro del ámbito del actor → `requiere_resultado`. Con `no_contactar` → `por_revisar` sin registrar |
| 2 | Entrantes | Con la propuesta #8 (solo salientes) `requiere_devolucion` se define pero queda apagado en el piloto |
| 3 | Descarte motivado | Catálogo cerrado: `no_comercial`, `personal`, `numero_de_prueba`, `error_captura`, `otro` (con texto). Siempre auditado; el evento permanece |
| 4 | Semántica de Deshacer | Si la actividad enlazada se deshace, el enlace y el evento permanecen; el evento se marca con `efectos_anulados` y **no** vuelve a exigir registro (§8 del plan) |
| 5 | Hora y atribución | `ocurrido_en` del celular cuando venga, si no `recibido_en`; SLA y retención usan `recibido_en`; el actor es el de la asignación vigente en ese instante y no cambia después |
| 6 | Retención (§15) | `numero_crudo`: **no se guarda** salvo diagnóstico autorizado (y entonces ≤ 7 días); `sin_identificar` y `descartado`: 30 días; identificados/registrados: lo que dure la actividad enlazada |
| 7 | Lead reasignado | El evento conserva su `actor_id` histórico; asociar o enlazar revalida el ámbito y falla con `42501` y mensaje claro si ya no es suyo |

## Verificación (F2.4)

- Banco Docker con las migraciones; `test-rls.mjs` bloque `testLlamadasCelular`: aislamiento analista / supervisor / gerencia, sin acceso cruzado, `EXECUTE` denegado a `anon`, idempotencia (mismo origen + hash → mismo id; distinto hash → `23505`), dos consumidores a la vez, enlace duplicado rechazado, baja de actor → la ingesta cae en `por_revisar`, lead reasignado → `42501`.
- Advisors de seguridad y rendimiento sin alertas nuevas; `COMMENT ON` completo; `MIGRACIONES.md`; reversa SQL que conserva datos; `npm run gen:types` y typecheck; `auditor-rls` y Codex LEVEL 3 con evidencia.
- El receptor de F1 y la encuesta **no cambian** en F2; los consumidores llegan en F4.

## Orden de trabajo (un PR por paso, cada uno con plan aprobado)

1. **F2-a · Contrato**: Miguel fija las 7 decisiones de arriba; este documento pasa a definitivo y cierra F2.1.
2. **F2-b · Datos**: tablas, restricciones, RLS, auditoría, comentarios, reversa (F2.2).
3. **F2-c · Núcleo y puertas**: funciones, grants, revokes (F2.3).
4. **F2-d · Verificación**: gate RLS ampliado, concurrencia e idempotencia en el banco, ledger y evidencia (F2.4).

## Riesgos y límites

- La credencial por celular (para que F3 pueda ingerir) no existe hoy: F2 deja solo su hash y F3 define cómo se emite y se rota.
- `numero_crudo` es dato personal: la recomendación es no persistirlo; si diagnóstico lo exige, plazo corto y acceso solo gerencia.
- Antes de F2-c hay que leer `deshacerResultadoLlamada` (`data/gestion-diaria-api`) para que la decisión #4 case con lo que hoy hace Deshacer.
- Sin consumidores en pantalla hasta F4, la bandeja `por_revisar` solo se ve en el banco: F2 no promete funcionalidad visible.

## Reversa

Migración de reversa que **conserva los datos** (patrón `supabase/scripts/resultado-llamada-seguimiento/reversa.sql`): revoca `EXECUTE`, retira las puertas y el cron; las tablas quedan sin consumidores.

---

**En llano:** F1 ya hace que el celular abra la encuesta; F2 hace que cada llamada quede anotada por sí misma (qué celular, qué número, cuándo) y amarrada a lo que el analista registró, con las reglas en la base para que nada se duplique ni se pierda. Nada de esto se escribe hasta que Miguel apruebe las siete decisiones y el diseño.
