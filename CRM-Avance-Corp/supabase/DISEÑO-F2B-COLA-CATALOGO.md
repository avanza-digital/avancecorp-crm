# F2.b — la cola del Catálogo F0 (Contrato-F2, parte 2) — diseño **v3** (04/09/2026) + E2 v2 + **E3 v3** (05/09)

**v1 → NO-GO de Codex (17 bloqueantes).** v2 incorporó cada arreglo (marcados `[Cx-n]`). **v2 → NO-GO de Codex (19 puntos).** v3 aplica
los que tocan lo YA construido (b1/b2, marcados `[v2-n]`) y deja los de E2/E3 como diseño pendiente con su número. Estado real: **b1 y b2
implementados y ensayados en `banco-f7`** (oráculos verdes, reversa ×2 byte a byte, auditor-rls sin bloqueantes); b3/b4/b5 sin escribir.

## v3 — qué cambió respecto a v2 (por la refutación de Codex)
- `[v2-1]` **El cambio de `dni` NUNCA enlaza ni toma locks.** Un `BEFORE UPDATE` corre con la fila del lead ya bloqueada: tomar la identidad
  ahí es lead→identidad, al revés que marcar/levantar y la conversión. El trigger `000` vuelve a ser `BEFORE INSERT`; `zz` en UPDATE solo
  RECHAZA (`P0409`) el cambio de DNI de un lead enlazado o hacia una persona reconocida (lookup sin lock). Desaparece el «enlace por edición»
  (que el auditor había marcado como decisión de negocio, N8): enlazar un lead suelto es la corrección/fusión de Gerencia (b5).
- `[v2-3]` `crm.rescatar_descartes` entra en b2 (`persona_vetada` por fila, también por documento).
- `[v2-4]` **El offboarding NO se toca.** Reasignar el responsable de relación desde `fijar_membresia_activa_fn` metía identidades en una
  puerta que empieza por `crm.equipo` (ciclo identidad↔equipo con contratos/toma). La reasignación es la puerta de Gerencia de b5, y el
  preflight de baja mostrará el conteo de personas del saliente (E3).
- `[v2-6]` `marcar/levantar_no_contactar` pasan a ser por PERSONA también sobre un lead suelto: documento exacto → advisory → canónica →
  identidad `FOR UPDATE` → leads (mismo orden). El lead suelto no se enlaza (b5).
- `[v2-7]` `cancelada_por='sistema'` (el CHECK solo admite `asesor|sistema`); la causa va en la nota de la RPC. (La implementación ya era así.)
- `[v2-8]` El gate de seguimiento bloquea solo los tipos de CONTACTO (`llamada_*`, `whatsapp_*`, `reunion_realizada`) y las tareas; las
  notas administrativas (corrección/anulación de cierre, fusión, reingreso) entran. La exención `auth.uid() is null` se conserva (writers
  internos con sus propios gates; el importador ya no puede abrir leads a vetados por `000`).
- `[v2-5]` Precisión: para un actor HUMANO, una persona con perfil cliente sigue dando `ya_es_cliente` por el perfil (regla vigente: un
  cliente no es un lead nuevo); el enlace al nacer aplica al alta sin sesión (importador) y a personas sin perfil. Los leads sueltos
  históricos con el mismo documento (pre-F2, convertidos/descartados) son la cola de clase E: no se tocan aquí.
- `[v2-2]` El ciclo contacto→índice único vs lead→contacto del importador es PREEXISTENTE (no lo introduce b1): queda anotado; la vía
  definitiva es que el importador entre por una puerta SQL (candidato para E2, no para E1).
- `[v2-17]` **Antes de ACTIVAR la bandera:** `convertir_lead_externo` (220000, ya en prod) escribe `crm.inversiones`/`inversion_titulares`
  gateado por `resolver_en_puertas` y no por `inversiones_escritura` (F4). Se corrige en una migración propia antes de la activación.
- Diferidos a E2/E3 con su número: `[v2-9,10,18]` claim único por identidad con `claim_id`/token/lease/CAS y fingerprint HMAC (b3+b4
  comparten la máquina; nada de documento crudo en claves ni columnas auditadas); `[v2-11]` capacidad `puede_alta_cliente` que reproduzca la
  unión de roles vigente; `[v2-12]` responsable inicial revalidado bajo el interlock de jerarquía; `[v2-13]` `eliminar-cliente` con preflight
  antes de cualquier borrado; `[v2-14]` colaboradores/`crm-usuarios`/registro Portal → se decide con Miguel si entran (el catálogo los
  lista; el contrato §2 los excluye como inversionistas); `[v2-15,16]` fusión: orden total entre hechos (lead antes que cierre también en
  corregir/anular cierre), huella revalidada tras bloquear TODO lo que la compone, matriz completa (puente, titulares principal/cotitular,
  responsable cuando solo la perdedora tiene tramo, sagas activas, DNI del lead enlazado en la corrección); `[v2-19]` oráculos
  diferenciales OFF por puerta (hoy: aserciones OFF en los tres oráculos, no golden por función).

Punto de partida: lote `190000`–`260000` EN PRODUCCIÓN con `resolver_en_puertas=false`. Todo F2.b es aditivo, gateado por esa
bandera (apagada = idéntico a hoy: mismas respuestas, SQLSTATE, locks y efectos `[Cx-14]`) y con reversa. Nada se activa aquí.
Spec: Contrato F0 + Catálogo F0. Corrección al catálogo: `crm-importar-leads` inserta directo con service_role (`functions/crm-importar-leads/index.ts:496`),
no por `crear_lead_si_disponible`; la copia de `_supabase_functions/` es la vieja.

## 0. Orden total de locks — UNO para todas las puertas `[Cx-2, Cx-11, Cx-15]`
```
documento(s)  → pg_advisory_xact_lock(hashtext('inv_resolver:'||tipo||':'||norm)), TODOS los documentos implicados, ordenados por texto
identidad(es) → crm.inversionistas FOR UPDATE, por id ascendente; REVALIDAR estado/canónica tras esperar
perfil        → public.perfiles FOR SHARE (revalidar que el documento no cambió)
lead(s)       → crm.leads FOR UPDATE, por id ascendente
reserva       → crm.conversion_reservas FOR UPDATE
contactos     → private.bloquear_contactos_lead (advisory por teléfono/DNI)   ← SIEMPRE el último
hechos / UPDATE bajo válvula crm.op_privilegiada
```
Hoy la conversión ya es documento→identidad→lead→(contactos por el trigger de UPDATE). **Se corrige `crear_lead_si_disponible`**, que hoy
toma contactos ANTES del INSERT (`20260826182500:225-232`): pasa a tomar el documento (helper) antes de los contactos. La conversión Avance con
perfil YA enlazado hoy salta el advisory (`210000:107-123`): pasa a tomarlo siempre y a revalidar `estado<>'fusionado'` tras el `FOR UPDATE` `[Cx-15]`.
`crm.marcar/levantar_no_contactar` (identidad→leads→contactos) ya son compatibles. Helper único: `private.identidad_bloquear_documento(tipo, doc)`.

## 1. Semántica documental, una sola `[Cx-5]`
- **Solo un identificador `vigente` Y `verificado=true` de una identidad no fusionada resuelve automáticamente** (contrato §4.2/#8). Vale para
  enlazar, para el veto y para «un solo lead». Hoy `240000` (trigger), `250000` y `260000` (lecturas) exigen solo `vigente`: **se alinean** a
  `verificado=true` (en prod las 427 identidades son `vigente+verificado`, no cambia ninguna cifra).
- Nuevo `private.inversionista_por_documento(p_tipo, p_doc) returns uuid` (stable, sin lock, NO crea, devuelve NULL, sigue `inversionista_canonico_id`).
  El resolver con `p_verificado=false` lanza `22023`; por eso el alta usa este lookup y nunca el resolver.
- `private.persona_vetada(p_lead_id) returns boolean` y `private.leads_vetados_persona(uuid[]) returns setof uuid` (stable): veto del lead
  OR veto de la persona por `inversionista_id`→canónica OR por documento exacto (verificado) del lead sin enlace. Es el helper que 250000 anunció.

## Prerrequisitos de ACTIVACIÓN (de Codex sobre lo construido, 04/09) — no bloquean aterrizar apagado
(a) trigger estrecho para el PATCH directo de asignación/reapertura; (b) marcar: bloquear TODOS los leads por id ascendente (preexistente en 240000);
(c) seguimiento por `perfil_id` (tareas de cliente, `actividades_cliente`) → E2; (d) tareas de leads sueltos con el mismo documento → E3;
(e) `[v2-17]` inversiones con `inversiones_escritura`; (f) `[v2-2]` importador por puerta SQL → E2.

## Sub-lote b1 — El alta reconoce a la persona (hoja, formulario, alta manual, edición de DNI)
**Problema:** la hoja inserta sin veredicto → puede abrir un 2.º lead a una persona convertida y no ve el veto de la persona.
**Meta (#6, #7, #8):** con bandera ON, en TODO INSERT de `crm.leads` y en TODO cambio de `dni`: documento exacto (verificado) → (a) persona vetada → `P0429`;
(b) persona con lead (cualquier estado) → `P0481` con veredicto `{estado:'ya_es_cliente', via:'identidad', lead_id}` (clave `lead_id` ADITIVA);
(c) sin lead → nace ENLAZADO. Sin coincidencia → NULL (captación §4.3). Nunca crea identidad.
**Cómo:**
- `private.trg_leads_hereda_veto_persona` (000, pasa a `BEFORE INSERT OR UPDATE OF dni`): bandera ON → `identidad_bloquear_documento` →
  `inversionista_por_documento` → `crm.inversionistas FOR UPDATE` → releer `no_contactar` `[Cx-3]` → `P0429` si vetada; si no, copia `true` como hoy.
  Bandera OFF → `return new`.
- `trg_leads_00_disponibilidad_*` (sin cambio de texto): sigue tomando contactos DESPUÉS (orden 000→00 por nombre). En UPDATE ya aplica
  `bloquear_contactos_lead` a todos.
- Nuevo `private.trg_leads_zz_enlaza_identidad` `BEFORE INSERT OR UPDATE OF dni` (corre tras `trg_leads_protege_inversionista_id` por nombre;
  el orden alfabético de triggers del mismo timing es determinista en Postgres) `[Cx-4]`: bandera ON → INSERT: identidad por documento → si
  `exists crm.leads where inversionista_id=i` → `P0481`; si no → `new.inversionista_id := i`. UPDATE OF dni: si `old.inversionista_id is not null`
  y el DNI cambia → `P0409` «documento de una persona enlazada: usar la corrección de documento (Gerencia)»; si `old.inversionista_id is null` →
  misma resolución que INSERT. Ignora el valor que traiga `new.inversionista_id` (protege ya lo restauró). Cierra la vía PostgREST directa
  (`crm-api.ts:1777`) sin tocar el GRANT por columna.
- Nuevo `private.trg_leads_zz_puente_identidad` `AFTER INSERT OR UPDATE OF inversionista_id` `[Cx-1]`: inserta `crm.inversionista_leads`
  (`rol='canonico'`) si no existe puente para la persona; si ya existe otro canónico (no debería, el zz lo impide) → `P0409`.
- `crm.crear_lead_si_disponible`: transformación mínima: llamar `private.identidad_bloquear_documento('DNI', v_dni)` ANTES de
  `bloquear_contactos_lead` `[Cx-2]`. Con bandera OFF el helper es no-op (no toma lock) → paridad.
- Importador (`crm-importar-leads`, copia viva; se sincroniza la vieja): rama explícita `[Cx-14]`: lee la bandera con `crm.bandera_activa`
  (se concede `EXECUTE` a `service_role`: es un booleano sin PII). Con ON: `P0481` cuyo DETAIL sea `ya_es_cliente` → resultado
  `"ya_cliente"` + llamada a `crm.registrar_reingreso_lead_fn(p_lead_id, p_origen, p_datos)` (DEFINER, `service_role`; actividad `nota` con
  `metadata.evento='reingreso'` en el lead canónico: el cliente que vuelve por la landing es señal de venta para su responsable, §12);
  `P0429` → `"rechazado: persona no contactable"`. Con OFF: idéntico a hoy. Se despliega con la activación.
- Corrección/anulación de cierres, descarte, retroceso y triggers de avance: **sin cambio**; oráculo de PRESERVACIÓN: ninguna deja
  `inversionista_id` distinto (protege restaura `old` en UPDATE por construcción) `[inventario]`.
**Reversa:** restaurar `240000`/`250000`/`260000` (texto previo byte a byte), soltar zz/puente/helpers, restaurar `crear_lead_si_disponible`.
Los enlaces creados se conservan (hechos).
**Oráculos (banco, 2 sesiones, ON y OFF):** insert service_role DNI convertido → P0481 + reingreso registrado; DNI vetado → P0429; DNI libre con
identidad → enlazado + puente (AFTER); sin DNI → NULL; UPDATE dni de lead enlazado → P0409; UPDATE dni de lead suelto → enlaza; carrera
alta(RPC)↔alta(directa)↔conversión mismo DNI → sin deadlock, un solo lead; alta↔marcar_no_contactar → el alta ve el veto; OFF → idéntico.

## Sub-lote b2 — El veto de la persona bloquea reparto, toma, reapertura Y seguimiento (#7) `[Cx-6, Cx-7]`
**Cómo (todo con `persona_vetada`/`leads_vetados_persona`, gateado por bandera):**
- Mutaciones: `private.repartir_lead_implementacion` (tras `FOR UPDATE` → `P0429`), `crm.derivar_leads_equipo_fn` (set-based en el cursor),
  `crm.revertir_derivacion_equipo_fn` (veto del lead Y de la persona → `P0429`), `crm.tomar_lead_libre` (precheck + 2 `FOR UPDATE` + 2 CAS),
  `private.deshacer_descarte_implementacion` (→ `P0429`), `crm.resumen_reparto_fn` (mismo predicado que la cola).
- **Seguimiento** `[Cx-6]`: `private.trg_gestion_lead_serializada` (ya bloquea el lead `FOR UPDATE` antes de cada actividad/tarea humana):
  con bandera ON, tras el lock, `persona_vetada(lead)` → `P0429` (los writers internos `auth.uid() null` y los tipos de sistema
  `cambio_etapa/reasignacion/conversion` siguen exentos, como hoy; la `nota` de `marcar_no_contactar` va bajo válvula).
  `crm.marcar_no_contactar`: además de identidad→leads, **cancela las tareas pendientes** de todos los leads de la persona
  (`estado='cancelada'`, `cancelada_por='sistema:no_contactar'`) `[Cx-6]`. Levantar el veto NO las revive.
- **Offboarding** `[Cx-7]` — DECISIÓN PARA MIGUEL (por defecto, salvo que diga otra cosa): `crm.fijar_membresia_activa_fn` SIGUE transfiriendo
  TODOS los leads (vetados incluidos: custodia administrativa ≠ contacto; el veto bloquea el seguimiento en el punto de contacto) y, con
  bandera ON, **reasigna atómicamente el responsable de relación**: cierra el tramo abierto (`motivo='offboarding'`) y abre otro al reemplazo
  en `crm.inversionista_responsables` + `inversionistas.responsable_relacion_id`, para las identidades cuyo responsable es el saliente.
- Fuera: `descartar_lead` (cerrar no es contactar, decisión 23/07), `retroceso_por_anular_reunion`, triggers de avance (solo corren tras una
  gestión que ya pasó el gate).
**Oráculos:** por cada mutación y por actividad/tarea: persona vetada (enlazada y por documento) → `P0429`; no vetada → igual; OFF → igual;
marcar → tareas pendientes canceladas; offboarding → un solo tramo abierto por persona, al reemplazo.

## E2 = b3 + b4 — diseño concreto v1 (05/09/2026), responde a `[v2-9..13, 18]`

### La SAGA de Auth, una sola máquina para el alta directa y la conversión Avance `[v2-9, v2-13, v2-18]`
PostgreSQL y Auth no comparten transacción; la máquina vive en `crm.multiempresa_idempotencia` (PK `clave`, `version` = CAS,
`resultado` jsonb = estado). **La clave es la IDENTIDAD, nunca el documento:** `clave = 'auth_persona:' || inversionista_id`
(la identidad se resuelve ANTES con `private.inversionista_resolver(tipo, doc, true, fuente)`; la alta la teclea Gerencia y la
conversión ya la trata como verificada). Cero documento en claves ni columnas auditadas.
`resultado = {claim_id, token_hash (sha256 de un token aleatorio que solo ve el edge, rotado en cada reanudación), tipo
('alta_cliente'|'conversion'), owner (auth.uid o null para service_role), estado ('reclamado'→'auth_creado'→'perfil_creado'→'enlazado'),
auth_user_id, perfil_id, lead_id (conversión), lease_hasta (10 min), hash_payload (calculado en SQL con private.idem_hash sobre los
campos canónicos), creado_en, actualizado_en}`.
Helpers privados (sin EXECUTE para la API):
- `private.saga_auth_reclamar(p_inv, p_tipo, p_payload jsonb, p_lead_id) → jsonb`: identidad ya bloqueada por el llamador. Si no hay claim →
  lo crea (estado `reclamado`, devuelve `token`). Si hay claim vivo (lease vigente) de OTRO owner → `P0409` «alta en curso». Si el lease
  venció o es el mismo owner → **reanuda**: devuelve estado, `auth_user_id`, `perfil_id` y un token NUEVO; si `hash_payload` difiere del
  reclamo en `reclamado` → `P0409` «datos distintos» (tras `auth_creado` el payload ya no manda: manda el Auth creado).
- `private.saga_auth_avanzar(p_claim_id, p_token, p_estado, p_auth_user_id, p_perfil_id, p_version) → jsonb`: verifica `sha256(token)`,
  CAS por `version` (`40001` si cambió), transición válida (`reclamado→auth_creado→perfil_creado→enlazado`), renueva el lease.
- El edge marca el Auth con `app_metadata.claim_id` al crearlo y **solo reutiliza un Auth si su `app_metadata.claim_id` coincide**; un Auth
  hallado por email sin esa marca → 409 «revisión de Gerencia», nunca se adopta.
- Ventanas de caída, todas reanudables: muerte tras `createUser` sin `registrar_auth` → el reclamo sigue en `reclamado`; el reintento
  vuelve a `createUser`, recibe «ya registrado», busca por email y **solo adopta si trae el `claim_id`** → `registrar_auth` → sigue.
  Muerte tras el perfil sin `enlazar` → `perfil_creado` (o perfil existente con `id = auth_user_id`) → `enlazar`. Muerte tras enlazar sin
  respuesta → reanudar devuelve `enlazado` + `perfil_id` (idempotente).

### Sub-lote b3 — El cliente creado sin lead es una persona, atómico
- **`private.puede_alta_cliente() → jsonb {ok, asesor_id, via}`** `[v2-11]`: reproduce EXACTAMENTE `crear-cliente/autorizacion.mjs`
  (perfil activo; `crm.mi_acceso_fn()` con `perfil_id = uid`, estado conocido y ≠ `revocado`, `puede_contratar` booleano; rol Portal en
  `admin/superadmin/analista/operaciones` → vía `portal`, asesor = uid si `analista`; si no, `estado='miembro'`, `puede_contratar=true`,
  `rol_crm` no vacío → vía `crm`, asesor = uid si `vendedor`). No se reutiliza `puede_gestionar_contratos_crm`.
- **`crm.alta_cliente_identidad_fn(p_paso text, p_payload jsonb) → jsonb`** (DEFINER; `authenticated` con `puede_alta_cliente`, y
  `service_role` para `importar-clientes`; con bandera OFF → `P0409` «apagada»: superficie inerte). Pasos:
  1. `reclamar` `{tipo_documento, documento, correo, nombre, apellidos, nombres, asesor_id}`: **documento OBLIGATORIO** `[v2-8]` →
     advisory documental → resolver(verificado, `alta_cliente`) → identidad `FOR UPDATE` → si `perfil_id` apunta a un cliente activo →
     `P0409 {ya_existia, perfil_id}` (sin Auth); si existe un perfil cliente con ese documento SIN enlace (creado con la bandera apagada) →
     se ENLAZA (documento exacto verificado, §4.2) y `P0409 {ya_existia}`; si no → `saga_auth_reclamar` → `{claim_id, token, estado, version, inversionista_id}`.
  2. `registrar_auth` `{claim_id, token, auth_user_id, version}` → `auth_creado`.
  3. `perfil_creado` `{claim_id, token, perfil_id, version}` (tras el INSERT del edge) → `perfil_creado`.
  4. `enlazar` `{claim_id, token, version}`: documento → identidad `FOR UPDATE` → perfil `FOR SHARE` (revalida `rol='cliente'`, activo y que su
     documento sea el vigente de la identidad) → `inversionistas.perfil_id` (si ya apunta a OTRO perfil → `P0409`) → **responsable de
     relación** `[v2-12]`: abre tramo con `asesor_perfil_id` SOLO si no hay tramo abierto Y el asesor es miembro CRM activo y perfil activo
     (interlock `pg_advisory_xact_lock_shared('crm.equipo.usuarios_jerarquia')` como derivar); si el asesor no está activo → no se abre tramo
     y se marca `revision_responsable=true` en la respuesta → propaga `no_contactar` → `enlazado`. Idempotente.
- **`private.asegurar_identidad_perfil(p_perfil_id) → uuid`** (para `crear_contrato` y para `enlazar`): lee el documento del perfil sin lock →
  advisory → resolver(verificado, `contrato`) → identidad `FOR UPDATE` → perfil `FOR SHARE` con revalidación del documento → enlaza si falta;
  identidad con OTRO perfil → `P0409`; sin documento válido → `raise` de negocio (fail-closed). `[v2-11]`
- **`crm.cliente_eliminable_fn(p_perfil_id) → jsonb {eliminable, motivo}`** `[v2-13]`: `eliminar-cliente` lo llama ANTES de cualquier
  borrado; perfil enlazado a una identidad → `{eliminable:false, motivo:'identidad'}` y el edge responde 409 «baja lógica» sin efectos.
- **`crm.actualizar_cliente_gerencia`** (transformación anclada): con bandera ON, un `p_patch` con `dni` o `tipo_documento` sobre un perfil
  ENLAZADO → `P0409` «corrección de documento (Gerencia, b5)`. `[v2-10]`
- **Edges** (`crear-cliente`, `importar-clientes`): rama explícita por bandera (`crm.bandera_activa`; error al leerla → 500, fail-closed).
  ON: `reclamar` → (reanudar o `createUser` con `app_metadata.claim_id`) → `registrar_auth` → INSERT perfil (`id = auth_user_id`) →
  `perfil_creado` → `enlazar`. `deleteUser` de compensación solo si el perfil falló por datos (23514/23505) y se COMPRUEBA su resultado;
  si falla, el reclamo queda en `auth_creado` (reanudable). OFF: código actual intacto.
- **`public` (migración APARTE, requiere OK de Miguel):** `public.crear_contrato` llama `private.asegurar_identidad_perfil(v_cliente_id)`
  ANTES de su `for share` (parche por ancla md5 como 181000/183000) con bandera ON; trigger `BEFORE UPDATE OF dni, tipo_documento` en
  `public.perfiles`: perfil enlazado + bandera ON + sin válvula → `P0409`. Sin ese OK, E2 aterriza sin estas dos piezas y quedan como
  prerrequisito de activación.
- Colaboradores (`registrar_*_usuario_fn`, `crm-usuarios`) y registro Portal: **decisión de Miguel** `[v2-14]`; por defecto fuera (contrato §2:
  no son inversionistas; el mismo DNI en dos roles ya está resuelto por índices parciales).
**Oráculos b3:** alta → identidad + perfil enlazado + tramo; dos altas concurrentes mismo documento → una reclama, la otra `P0409` antes de
Auth; muerte simulada tras `createUser` (Auth sembrado con `claim_id`) → reanudación adopta ese Auth; Auth sin marca → 409; asesor inactivo →
sin tramo + `revision_responsable`; perfil suelto con el documento → se enlaza; contrato sobre perfil sin enlace → enlaza (si hay OK);
`eliminar-cliente` sobre enlazado → 409 sin borrar comunicados; OFF → nada nuevo, RPC inerte.

### Sub-lote b4 — La conversión Avance reserva por la PERSONA y no deja huérfanos `[v2-12 conversión, v2-13, v2-18]`
- `crm.conversion_reservas` gana columnas ADITIVAS **sin documento**: `inversionista_id uuid`, `claim_id uuid`, `hash_payload text`.
- Nueva sobrecarga `crm.reservar_conversion_lead(p_lead_id, p_tipo_documento, p_documento, p_payload jsonb)`: bandera ON obligatoria;
  validación pura → advisory documental → resolver(verificado, `reserva_conversion`) → identidad `FOR UPDATE` → revalida: **sin veto**
  (`P0429`), **sin OTRO lead** (cualquier estado; `P0409` con `lead_id`), perfil enlazado (si lo hay) → se reutilizará → lead `FOR UPDATE`
  (ámbito, como hoy) → si hay reserva viva de OTRO lead con el mismo `inversionista_id` → `P0409` → upsert de la reserva (reglas de hoy)
  con `inversionista_id`, `hash_payload` (SQL) → `saga_auth_reclamar(inv, 'conversion', payload, lead_id)` → devuelve `{ok, expira_en, claim_id,
  token, estado, version, auth_user_id, perfil_id, inversionista_id}`. Es el preflight: revalida DESPUÉS de esperar el advisory.
  La firma antigua de 1 argumento queda para la bandera OFF (paridad).
- `crm.convertir_lead_externo` (transformación anclada): tras resolver e `inversionistas FOR UPDATE`, si existe reserva viva
  (`efectos_iniciados_en is not null or expira_en > now()`) de OTRO lead con el mismo `inversionista_id` → `P0409` «conversión Avance en
  curso para esta persona». Lectura sin lock, después del lock de identidad: no cambia el orden.
- `crm.saga_conversion_fn(p_paso, p_payload)` (DEFINER, `authenticated` con `puede_gestionar_contratos_crm`): `registrar_auth`,
  `perfil_creado`, `cerrar` (tras `convertir_lead_con_domicilio` OK → `enlazado`). Reintento del edge: `reservar` devuelve el estado y
  `auth_user_id`; el edge reutiliza el Auth SOLO si `app_metadata.claim_id` coincide.
- Pasado `vence_absoluto_en`, **solo Gerencia** retoma una reserva sellada con claim en `auth_creado`/`perfil_creado`
  (`crm.retomar_conversion_gerencia_fn(p_lead_id)`: nuevo lease + token, `reservado_por` pasa a Gerencia). `[v2-13]`
- Edge `crm-convertir-lead`: rama por bandera; ON → sobrecarga nueva; `PGRST202` con ON → **error, no degradación** `[v2-10]`; `createUser`
  con `app_metadata.claim_id`; `registrar_auth` justo después; el correo sigue siendo el último paso. OFF → código actual intacto.
- `[v2-17]` En la misma entrega: `convertir_lead_externo` escribe `crm.inversiones`/`inversion_titulares` solo con `inversiones_escritura`
  (prerrequisito de activación; el arnés del lote anterior enciende ambas banderas en su ensayo).
**Oráculos b4:** coop(A)↔Avance(B) misma persona en los dos órdenes → una gana, la otra `P0409` ANTES de Auth; Auth sembrado con `claim_id`
sin perfil → reintento lo reutiliza; Auth ajeno por email → 409; reserva de persona vetada → `P0429`; Gerencia retoma tras el tope; OFF → idéntico.

### E2 v2 — qué cambió tras la refutación de Codex (13 puntos, 05/09) y qué queda
- `[E2-1]` Reanudar exige el TOKEN vigente o el lease vencido; compartir actor no expulsa a la ejecución activa; `owner=null` (service_role) nunca cuenta como «mismo actor».
- `[E2-2]` `registrar_auth` verifica EN SERVIDOR que el Auth exista y lleve `app_metadata.claim_id` de este claim; `perfil_creado` exige `perfiles.id = auth_user_id`.
- `[E2-3]` Paso `compensar_auth` (solo si el Auth ya no existe): el claim vuelve a `reclamado`. Los edges compensan SOLO por datos inválidos (23514); un 23505 por `id` es el perfil de la misma saga y se sigue; un 23505 por documento va a revisión.
- `[E2-4]` La saga manda antes que la existencia: `reclamar`/`reservar` devuelven `enlazado` con `perfil_id` cuando la respuesta se perdió; una conversión ya consumada cierra el claim al reservar de nuevo. Reutilizar un perfil PREEXISTENTE por documento (dedup) no requiere marca de Auth: el perfil existe (`id = auth`), y no se adopta ningún Auth.
- `[E2-5]` Gerencia retoma una reserva sellada con claim en `reclamado`, `auth_creado` o `perfil_creado`.
- `[E2-6]` `marcar_efectos_conversion` bloquea la IDENTIDAD antes de sellar (+ sobrecarga con claim/token); la coop lee las reservas de la persona bajo ese lock.
- `[E2-7]` `saga_conversion_fn('cerrar')` es transaccional: convierte y comprueba que la identidad convertida es la reservada; si no, revierte.
- `[E2-8]` `crm.eliminar_cliente_fn` (service_role) comprueba y borra comunicados + perfil en UNA transacción; el edge borra el Auth después. Protege también perfiles de sagas sin enlazar.
- `[E2-9]` «Ya existe» es un RESULTADO (`estado='ya_existia'`), nunca excepción.
- `[E2-10]` Huella canónica completa y versionada (`v:1`, correo, nombre, apellidos, nombres, teléfono, domicilio, banca) SIN documento y con el uuid de la identidad como sal; se compara en toda reanudación. No hay HMAC con secreto de servidor: no existe un almacén de secretos en la base y la huella no autoriza nada (el token sí, y va hasheado); el auditor genérico solo ve `resultado` con ids y hashes.
- `[E2-11]` `revision_responsable` queda persistido como «sin responsable» (`responsable_relacion_id` null, sin tramo); bloquear operaciones comerciales a personas sin responsable es de F4/activación (ficha).
- `[E2-12]` Seguimiento por perfil (tareas de cliente, `actividades_cliente`): prerrequisito de activación, sin cambio en E2.
- `[E2-13]` Guard OFF en TODAS las RPC nuevas (`P0409` «apagada»); `cliente_eliminable_fn` no mira la identidad con OFF. Los edges se despliegan con la activación (ninguna llamada nueva mientras OFF en producción).
- Abierto para E3/activación: `[E2-11]`, `[E2-12]`, `public.crear_contrato` y trigger en `public.perfiles` (OK de Miguel), colaboradores/registro Portal, importador por puerta SQL.

**Fuera de E2 (E3):** fusión/corrección/reasignación; `[v2-2]` importador por puerta SQL (candidato para E3 o activación).

## Sub-lote b5 — Fusión, corrección documental y reasignación (Gerencia) — **alcance acotado** `[Cx-15, Cx-16, Cx-17]`
**Lo que SÍ cierra:** fusiones donde **como máximo una** de las dos identidades tiene lead y como máximo una tiene perfil. Las que tienen dos
leads o dos perfiles → `P0409` con diagnóstico y quedan en la **cola de reconciliación de clase E hasta F5** (se dice así en la ficha; no se
declara b5 «cerrado» para ellas).
- `crm.fusion_previsualizar_fn(p_perdedora, p_canonica) → jsonb`: leads, perfiles, cierres, inversiones/titulares, tramos, vetos, documentos, y
  la **huella** (`hash`) del estado; **nota explícita: la conversión mensual sigue siendo por lead/cliente hasta Contrato-F3, así que la fusión
  NO altera hoy ninguna cifra ni mes sellado** (huella de `conversion_episodios` antes/después en el oráculo) `[Cx-17]`.
- `crm.fusionar_inversionistas_fn(p_perdedora, p_canonica, p_motivo, p_hash)`: Gerencia; **advisory de TODOS los documentos de ambas** (ordenados)
  → ids ascendentes `FOR UPDATE` → revalida `hash` y `estado='activo'` de ambas `[Cx-15]` → matriz de colisiones `[Cx-16]`: perfil (uno, o `P0409`);
  responsable (canónica; cierra tramo de la perdedora `motivo='fusion'`); `no_contactar := OR`; lead (uno: reapunta `leads.inversionista_id`
  bajo válvula + puente canónico; dos → `P0409`); identificadores de la perdedora → `historico` + reemitidos vigentes en la canónica
  (`fuente='fusion'`, verificado) para que el resolver devuelva la canónica; `cierres_externos.inversionista_id`, `inversiones.inversionista_id`
  y **`inversion_titulares.inversionista_id`** reapuntados (si la canónica ya es titular de esa inversión → se conserva su fila y la de la
  perdedora se elimina SOLO si es duplicado exacto del par; principal único garantizado); fila append-only; perdedora `estado='fusionado'`.
  Auditoría: `audit_log` (sin documento en claro); actividad `nota` solo si hay lead `[Cx-17]`.
- `crm.corregir_documento_inversionista_fn(p_inversionista, p_tipo, p_documento, p_motivo)`: Gerencia; advisory de ambos documentos ordenados →
  identidad `FOR UPDATE` → el vigente → `historico`; nuevo vigente verificado; si ya pertenece a OTRA identidad → `P0409` (sugerir fusión);
  actualiza `public.perfiles.dni/tipo_documento` del perfil enlazado bajo válvula `[Cx-10]`. No toca cierres/contratos/titulares.
- `crm.reasignar_responsable_relacion_fn(p_inversionista, p_nuevo, p_motivo)`: **solo Gerencia** (una política) `[Cx-17]`; cierra/abre tramo; no mueve atribuciones.
- Conversión Avance con perfil enlazado: toma el advisory y revalida (transformación de `convertir_lead`) `[Cx-15]`.
**Oráculos:** fusión con hash viejo → aborta; fusión↔conversión concurrentes → sin deadlock, resolver devuelve la canónica; perdedora nunca borrada;
titulares coherentes; huella de episodios intacta; corrección a documento ajeno → `P0409`; dos leads → `P0409`; reasignación → dos tramos.

## E3 = b5 — diseño concreto **v3** (05/09/2026) — v2 respondió a `[E3-1..14]`; v3 a la segunda refutación (10 puntos) y ES lo implementado

### v2 → v3, qué cambió (segunda refutación de Codex, 10 puntos; aplicado en el CÓDIGO, no solo en el diseño)
- `[E3-2]` Las cuatro mutaciones REVALIDAN `es_gerencia_crm_activa()` DESPUÉS de tomar el interlock de jerarquía (el offboarding lo toma
  exclusivo y luego desactiva la membresía); la reasignación valida además el rol EFECTIVO del destinatario (`private.rol_crm`) bajo ese lock.
- `[E3-4]` La foto (`fusion_estado_jsonb`, `v:2`) incluye las **tareas pendientes** de los leads de ambas identidades; se recalcula bajo TODOS los
  locks (tareas y leads incluidos) y se compara; el impacto de la previsualización cuenta `tareas_pendientes`.
- `[E3-6]/[E3-8]` La corrección toma los **contactos** (`bloquear_contactos_lead` con el teléfono del lead y los DNI viejo/nuevo) DESPUÉS del
  lead y ANTES de comprobar terceros (otra identidad, otro cliente del Portal, otro lead vivo, otro lead enlazado a otra persona); el trigger
  los retoma reentrante. La excepción del trigger exige además la bandera y «solo DNI» (teléfono, veto, etapa, activo y motivo iguales).
- `[E3-7]` El conjunto de reservas es «por identidad **o** por lead asociado» (las de la RPC de un argumento no llevan identidad): se bloquea y
  se rechaza igual en fusión, corrección y enlace (viva, o sellada con lead aún no convertido, aunque `inversionista_id` sea nulo).
- `[E3-9]` Los leads se toman con **`FOR UPDATE NOWAIT`** cuando ya se retienen sus tareas (`private.bloquear_leads_nowait`): un conflicto con
  `derivar` (lead→tareas por el trigger de sincronización) o `cerrar_tarea` (tarea→lead) se traduce a `40001`, nunca se espera dentro del ciclo.
  La cancelación sella `crm.cancela_sistema='on'` (`private.cancelar_tareas_pendientes_lead`).
- `[E3-10]` El enlace valida por **documento** lo que completa: el cierre con `inversionista_id` nulo debe llevar un documento vigente y verificado
  de la identidad; el perfil sin identidad, también (`private.documento_es_de_identidad`). Discrepancia → `P0409` «reconciliación documental».
  El límite «un solo lead» cuenta la UNIÓN del enlace vivo y del puente (`private.leads_de_identidades`, históricos del backfill incluidos), y la
  fusión reapunta TODO el puente de P.
- `[E3-12]` Perímetro ampliado a **7 funciones vivas**: `saga_conversion_fn('cerrar')` y `alta_cliente_identidad_fn('enlazar')` comparan por la
  **canónica** (`private.inversionista_canonica`) y el cierre proyecta `inversionista_id`; `marcar_efectos_conversion` (1 y 3 argumentos)
  revalidan tras esperar que la persona no se fusionó (`40001`). La fusión bloquea las **predecesoras** de P junto con P y C (antes de las
  reservas): el aplanado ya no espera detrás de un sellador.
- `[E3-13]` Promesa acotada y explícita: **b5 garantiza que ninguno de SUS payloads** (libros, foto, impacto, `resultado`, `metadata`, mensajes)
  lleva el documento en claro. Los auditores genéricos de `leads` y `cierres_externos` (`log_audit_crm`, `to_jsonb(old/new)`) siguen copiando la
  fila entera como hoy; una corrección de DNI o un reapunte de cierre genera esas copias. Enmascararlos es deuda propia: `[D-9]`.
- `[E3-15]` La unicidad «único de su tipo» solo se exige cuando NO se indica cuál sale; si el destino ya es un vigente PROPIO (p. ej. dos DNI tras
  una fusión) y se indica el anterior, sale el anterior y se **reutiliza** el destino (`reutilizado=true`) realineando perfil/lead;
  `sin_cambios` solo cuando no hay nada que hacer.
- `[E3-16]` La tabla pasa a ser el **libro de operaciones** `crm.inversionista_operaciones` (`tipo in ('correccion','enlace')`, `lead_id`,
  identificadores, `motivo`, `detalle`, `por`): el enlace SIEMPRE escribe su fila (también con lead inactivo); la reasignación deja el motivo en
  el tramo; la fusión en su libro.
- No bloqueantes: `v_uid` y toda lectura de argumentos van después de los guards; cotitularidades de P en inversiones de terceros se reapuntan;
  OFF probado también con la válvula encendida (la excepción exige la bandera). Inventario final: 5 RPC de Gerencia + 10 helpers privados +
  1 tabla + 7 funciones vivas transformadas. Diferible nuevo: `[D-9]` enmascarar `dni`/`documento` en los auditores genéricos de leads/cierres.


### v1 → v2, qué cambió (por número de Codex)
- `[E3-1]` **Perímetro ampliado y orden documento→identidad en la saga**: `convertir_lead` en la rama «perfil ya enlazado» NO toma el advisory
  documental (tomarlo tras la identidad es lo que cerraba el ciclo con la fusión); solo RELEE `estado` tras el `FOR UPDATE` y lanza `40001` si es
  `fusionado`. `crm.saga_conversion_fn('cerrar')` (texto vivo de b4, md5 de prod `e1750c3d…`) toma `private.identidad_bloquear_documento(tipo, dni
  del perfil del claim)` ANTES del `FOR UPDATE` de la identidad reservada. Con eso ninguna puerta viva toma identidad→documento.
- `[E3-2]` Las cuatro puertas de b5 toman PRIMERO el interlock compartido de jerarquía (`pg_advisory_xact_lock_shared(hashtextextended(
  'crm.equipo.usuarios_jerarquia',0))`, como `asegurar_identidad_perfil`): el offboarding lo toma exclusivo y luego escribe leads→perfiles.
- `[E3-3]` **Cierre ANTES que lead** en fusión y enlace (`cierres_externos ... for update` del lead implicado antes del `FOR UPDATE` del lead):
  corregir/anular cierre bloquean cierre→(nota)→lead; b5 respeta ese mismo orden sin transformar las RPC de cierre.
- `[E3-4]` Protocolo de la huella: TODOS los locks primero, la foto se RECALCULA bajo ellos y se compara con `p_hash`; campos y orden de la foto
  definidos abajo (determinista, `order by id`).
- `[E3-5]` Corrección: el identificador que sale se lee SIN lock para calcular los advisories, y se REVALIDA bajo el `FOR UPDATE` de la identidad
  (vigente, de esta identidad, único de su tipo); si cambió → `40001` (nunca se descubre y bloquea otro documento después de la identidad).
- `[E3-6]/[E3-8]` La realineación del lead deja de ser «omitido_veto»: **excepción estrecha en `private.trg_leads_disponibilidad_atomica`**
  (texto vivo, md5 de prod `782e65d7…`): con `crm.op_privilegiada='on'`, `tg_op='UPDATE'`, solo cambia `dni` (teléfono igual) y el lead
  conserva su `inversionista_id` (no nulo, igual a `old`), el trigger normaliza/valida el DNI y toma los contactos como siempre pero NO aplica el
  congelado por veto/enfriamiento ni la disponibilidad (la corrección ya comprobó terceros bajo locks: otra identidad con el documento, otro
  cliente del Portal, otro lead vivo). Fuera de esa forma exacta el trigger es byte a byte el de hoy. La corrección o se confirma entera o se rechaza.
- `[E3-7]` Corrección y enlace (como la fusión) se niegan con claim `auth_persona:` no terminal o reserva viva/sellada-sin-convertir de la
  identidad (`P0409` «alta/conversión en curso»), revalidado bajo el `FOR UPDATE` del claim.
- `[E3-9]` Veto = OR de P, C y el único lead, cualquiera que sea su lado; se materializa en C y en el lead; las tareas pendientes del lead se
  cancelan (`cancelada_por='sistema'`, como `marcar`) bloqueando tareas ANTES que el lead. El UPDATE de `no_contactar` dispara
  `trg_leads_00_disponibilidad_update`, que toma los contactos (`avancecrm:lead:*`, espacio de claves distinto de `inv_resolver:`) al final:
  el orden queda «… → tareas → lead → reservas → claims → contactos (por trigger)». Se retira la frase «sin contactos».
- `[E3-10]` Enlace: valida bajo locks la UNIÓN de enlaces del lead (`leads.inversionista_id`, `perfil_id` → identidad del perfil, cierre del lead →
  `cierres_externos.inversionista_id`, puente `inversionista_leads.lead_id`, reservas del lead): identidad distinta en cualquiera → `P0409`
  «reconciliación (fusión/corrección)», nunca enlace parcial; completa `cierres_externos.inversionista_id` y `inversionistas.perfil_id` cuando están
  nulos y corresponden. El límite un-solo-lead cuenta TODOS los leads (activos o no). Fusión/enlace con lead inactivo: sin nota de actividad
  (el gate de gestión exige `activo=true`); el rastro es el libro/la tabla de correcciones y el `audit_log`.
- `[E3-11]` Ambas conversiones (rama ON) comprueban tras el lock del lead que `v_lead.inversionista_id` es nulo o igual a la identidad resuelta;
  si difiere → `P0409` «la persona del lead no es la del documento: corrección/fusión de Gerencia». `convertir_lead_externo` = texto vivo de b4
  (md5 `190b75eb…`).
- `[E3-12]` Nuevo `private.inversionista_canonica(uuid) → uuid` (stable): sigue `inversionista_canonico_id` hasta la raíz. `convertir_lead`
  proyecta `inversionista_id` por la canónica en sus DOS retornos idempotentes (el resultado guardado se conserva). La fusión **aplana** las
  predecesoras de P (`inversionista_canonico_id = P` → `C`, y `fusionado_en` intacto; el libro no se toca) para que ningún lector de un salto
  caiga en una fusionada. Claims: la fusión se niega con claims no terminales; el claim terminal de P queda como historia (nadie lo reanuda: la
  reserva reapuntada a C no encuentra claim bajo C y `reservar` responde `enlazado` por la etapa del lead).
- `[E3-13]` Promesa corregida: **b5 no añade NINGUNA copia nueva del documento en claro** (libro `impacto`, `foto`, `resultado`, `metadata` de
  actividades, tabla de correcciones y mensajes de error llevan ids o `right(doc,3)`); los auditores genéricos de `leads`/`cierres` siguen
  registrando la fila completa como hoy (preexistente, fuera de b5, anotado en el ledger). El motivo de una corrección persiste en la tabla
  nueva append-only `crm.inversionista_correcciones`; `p_motivo` se rechaza (`22023`) si contiene el documento viejo o el nuevo normalizados.
- `[E3-14]` Un único `v_ahora := clock_timestamp()` capturado DESPUÉS de los locks, usado para `hasta/desde` de tramos, `vigente_hasta/desde`,
  `fusionado_en`, `no_contactar_en`.
- No bloqueantes: fixtures del oráculo con inversiones+titulares (principal y cotitular) en ambos lados (el backfill sí insertó inversiones);
  huella de sellados = `periodos_cerrados` y `cierre_mes_vendedor` (conteo + md5 agregado) además de `conversion_episodios` del mes abierto;
  el guard OFF va ANTES de cualquier lectura dependiente de parámetros; `run_as` del oráculo hace `set local role authenticated` para probar
  los grants; frontera de reversibilidad: `rollback-f2-backfill.sql` se niega con `fuente in ('fusion','correccion')` (se documenta);
  `crm.personas_por_responsable_fn` se RETIRA (un conteo no es un interlock → `[D-2]`). Inventario (v2; ver v3 arriba): 5 RPC de Gerencia + helpers privados + 1 tabla + funciones vivas transformadas.

### Diferibles con número (de Codex; ninguno bloquea aterrizar apagado)
`[D-1]` `public.crear_contrato` + guarda de `public.perfiles` (OK de Miguel) · `[D-2]` offboarding con interlock atómico sobre tramos abiertos y
gate comercial para personas sin responsable (F4/activación) · `[D-3]` veto sobre tareas por perfil, `actividades_cliente`, leads sueltos del mismo
documento · `[D-4]` importador por puerta SQL · `[D-5]` edges/Auth con la activación · `[D-6]` métrica por inversionista/mes (Contrato-F3) ·
`[D-7]` F4 (el gate `[v2-17]` ya está en b4) · `[D-8]` F5: dos leads/dos perfiles, siguiente oportunidad, ficha.

### Regla de aterrizaje (igual que E1/E2)
Todo detrás de `resolver_en_puertas`; las 5 RPC nuevas devuelven `P0409` «Identidad unificada apagada» ANTES de leer nada dependiente de
parámetros; las 7 funciones vivas transformadas cambian SOLO dentro de su rama ON (guardas md5 del texto de PRODUCCIÓN, verificadas
iguales en banco: `convertir_lead 0327c4d7…`, `convertir_lead_externo 190b75eb…`, `saga_conversion_fn e1750c3d…`,
`trg_leads_disponibilidad_atomica 782e65d7…`, `marcar_efectos_conversion 48c4cb30…`/`c3914738…`, `alta_cliente_identidad_fn 952f1842…`). Autorización: **solo Gerencia** (`private.es_gerencia_crm_activa()`, `42501`); `authenticated`
con la capacidad dentro; `service_role`/`anon` sin EXECUTE. Alcance acotado hasta F5: **como máximo un lead y un perfil entre las dos
identidades**; lo demás es `P0409` con diagnóstico y queda en la cola de reconciliación de clase E.

### Orden total de b5 (extiende §0)
```
jerarquía   pg_advisory_xact_lock_shared('crm.equipo.usuarios_jerarquia')            ← PRIMERO, en las cuatro puertas [E3-2]
documentos  advisory 'inv_resolver:tipo:norm' de TODOS los implicados, ordenados por texto (helper identidad_bloquear_documento, reentrante)
identidades crm.inversionistas FOR UPDATE por id ascendente (fusión: P y C; corrección/enlace/reasignación: una)
perfil      public.perfiles FOR SHARE (fusión, enlace: no escribe) · FOR UPDATE (corrección: escribe; nunca SHARE→UPDATE)
cierres     crm.cierres_externos FOR UPDATE (el del lead implicado)                    ← ANTES del lead [E3-3]
inversiones crm.inversiones / inversion_titulares FOR UPDATE por id (fusión)
tramos      crm.inversionista_responsables (abiertos) FOR UPDATE
tareas      crm.tareas pendientes del lead FOR UPDATE                                   ← ANTES del lead, como marcar [E3-9]
lead        crm.leads FOR UPDATE
reservas    crm.conversion_reservas FOR UPDATE (de la persona / del lead)
claims      crm.multiempresa_idempotencia 'auth_persona:<id>' FOR UPDATE
foto        RECALCULAR y comparar con p_hash [E3-4]; v_ahora := clock_timestamp() [E3-14]
válvula     crm.op_privilegiada='on' → hechos; los triggers del lead toman los contactos (avancecrm:lead:*) al final
```

### Transformaciones de funciones VIVAS (rama ON; OFF byte a byte)
1. `crm.convertir_lead` (`0327c4d7…`): (a) tras `perform 1 from crm.inversionistas where id = v_inv for update` en la rama del perfil ya
   enlazado: releer `estado`; `fusionado` → `40001` «la persona fue fusionada mientras se convertía; vuelve a intentarlo» `[E3-1/Cx-15]`;
   (b) tras el lock del lead: `if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv → P0409` `[E3-11]`;
   (c) los dos retornos idempotentes proyectan `'inversionista_id'` por `private.inversionista_canonica(...)` `[E3-12]`.
2. `crm.convertir_lead_externo` (`190b75eb…`, texto de b4): tras el lock del lead, la misma comprobación `[E3-11]`.
3. `crm.saga_conversion_fn` (`e1750c3d…`): en `cerrar`, antes del `FOR UPDATE` de la identidad: leer `tipo_documento, dni` del perfil `v_perfil`
   (si no existe → `P0409` «el perfil del claim no existe») y `perform private.identidad_bloquear_documento(tipo, dni)` `[E3-1]`.
4. `private.trg_leads_disponibilidad_atomica` (`782e65d7…`): la excepción estrecha de `[E3-6]` justo después de `bloquear_contactos_lead` de la
   rama UPDATE: `if v_priv and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono and old.inversionista_id is
   not null and new.inversionista_id = old.inversionista_id then return new; end if;` (`v_priv` = válvula, declarado en la función).

### Objetos nuevos
- Tabla `crm.inversionista_operaciones` (v3; append-only, patrón F1: RLS ON, SELECT Gerencia, sin grants a la API, `trg_audit_*` con
  `log_audit_crm`, trigger que rechaza UPDATE/DELETE, índices en todas las FK): `id, tipo ('correccion'|'enlace'), inversionista_id, lead_id,
  identificador_anterior_id, identificador_nuevo_id, motivo (3..500, sin documento), detalle jsonb, por, creado_en`.
- `private.inversionista_canonica(p uuid) → uuid` (stable, sin lock): raíz de la cadena de `inversionista_canonico_id` (máx. 16 saltos).
- `private.fusion_estado_jsonb(p_a uuid, p_b uuid) → jsonb` (stable, sin lock; se llama bajo los locks): por identidad, ordenado por id:
  `estado, perfil_id, responsable_relacion_id, no_contactar, inversionista_canonico_id`; identificadores `(id, tipo, estado, verificado, right(doc,3))`
  order by id; leads `(id, etapa, activo, no_contactar, vendedor_id, inversionista_id, perfil_id)`; puente `(id, lead_id, rol)`; tramos abiertos
  `(id, responsable_id)`; cierres `(id, lead_id, anulado_en is null, inversionista_id)`; inversiones `(id, estado, empresa_id)`; titulares
  `(id, inversion_id, rol)`; reservas `(lead_id, viva, sellada)`; claim `(estado)`; predecesoras `(ids con canonico = esta)`. `hash = private.idem_hash(foto)`.
- 5 RPC de Gerencia (abajo).

### `crm.fusion_previsualizar_fn(p_perdedora, p_canonica) → jsonb` (solo lectura, sin locks)
`{viable, bloqueos[], advertencias[], hash, foto, impacto}`. **Bloqueos** (la fusión los repite bajo locks con el mismo texto): misma identidad;
alguna no `activo` (`fusionado` → «usa la canónica X»; `bloqueado` → revisión); dos leads (contando inactivos) `[D-8]`; dos perfiles `[D-8]`;
claim no terminal o reserva viva/sellada-sin-convertir en cualquiera `[E3-7]`. **Advertencias**: dos documentos vigentes del mismo tipo (una está
mal: corregir después); vetos distintos (resultado OR, con tareas canceladas); responsables distintos (gana C; se cierra el tramo de P);
P tiene inversiones/cierres (se reapuntan, el dinero no se toca); P es canónica de otras (se aplanan); el lead está inactivo (sin nota);
mes abierto: la conversión mensual sigue por lead/cliente hasta Contrato-F3 (`[D-6]`), la fusión no altera cifras ni sellados (huellas en el oráculo).
**Impacto**: conteos + ids por tabla (se copian al libro).

### `crm.fusionar_inversionistas_fn(p_perdedora, p_canonica, p_motivo, p_hash) → jsonb`
1. Guard OFF → Gerencia → `p_motivo` 3..500 y sin documento → `p_hash` obligatorio.
2. Locks en el orden total: jerarquía → documentos vigentes de P y C (leídos sin lock, ordenados) → P y C `FOR UPDATE` (id asc) → revalidar
   que el conjunto de documentos vigentes no cambió (si cambió → `40001`) → perfil `FOR SHARE` → cierre del lead `FOR UPDATE` → inversiones y
   titulares de P y C `FOR UPDATE` → tramos abiertos `FOR UPDATE` → tareas pendientes del lead `FOR UPDATE` → lead `FOR UPDATE` → reservas de
   P y C `FOR UPDATE` → claims de P y C `FOR UPDATE`.
3. Recalcular la foto → `p_hash` distinto → `P0409` «la previsualización caducó: vuelve a previsualizar»; repetir los bloqueos → `P0409`.
   `v_ahora := clock_timestamp()`.
4. Bajo válvula, en este orden: P `estado='fusionado', inversionista_canonico_id=C, fusionado_en=v_ahora` (libera `inversionistas_perfil_uidx`);
   predecesoras de P → `inversionista_canonico_id=C` `[E3-12]`; perfil (si solo P) → `C.perfil_id`; veto OR → C (`no_contactar_en/por` de quien
   lo tuviera); responsable: C con tramo → cerrar el de P (`hasta=v_ahora`); solo P → cerrar el de P y abrir en C (mismo `responsable_id`,
   `motivo='fusion'`, `por=uid`, `desde=v_ahora`), `C.responsable_relacion_id`; identificadores vigentes de P → `historico`
   (`vigente_hasta=v_ahora`) y REEMITIDOS en C (`vigente`, mismo `verificado`, `fuente='fusion'`, `documento_original` conservado,
   `vigente_desde=v_ahora`); lead (si es de P) → `leads.inversionista_id=C`, puente → C; veto OR al lead + cancelar tareas pendientes;
   cierre → `inversionista_id=C`; inversiones → C, luego titulares (principal/cotitular: si C ya es titular de esa inversión, la fila de P se
   elimina y la de C hereda `principal` si P lo era; si no, se reapunta); reservas de P → C; libro `inversionista_fusiones` (impacto con ids);
   actividad `nota` si el lead está activo.
5. Devuelve `{ok, fusion_id, canonico_id, fusionado_id, impacto}`.

### `crm.corregir_documento_inversionista_fn(p_inversionista, p_tipo, p_documento, p_motivo, p_identificador_anterior default null) → jsonb`
1. Guard OFF → Gerencia → tipo/formato como el resolver (`22023`) → motivo sin documento → identidad `activo` (fusionada → «corrige en X»).
2. Lectura sin lock del identificador que sale (`p_identificador_anterior` o el ÚNICO vigente del tipo; dos → `22023` «indica cuál»; ninguno
   → alta de documento) → jerarquía → advisories del viejo (si hay) y del nuevo, ordenados → identidad `FOR UPDATE` → REVALIDAR el que sale
   `[E3-5]` (sigue vigente, de esta identidad, único de su tipo; si no → `40001`) → el nuevo ya vigente en OTRA identidad (verificado o no) →
   `P0409` «pertenece a otra persona: fusiona»; ya vigente en ESTA → `sin_cambios`; histórico de esta → se reemite → claim/reserva pendientes
   → `P0409` `[E3-7]` → perfil enlazado `FOR UPDATE` → cierre del lead `FOR UPDATE` → tareas → lead `FOR UPDATE`. `v_ahora`.
3. Terceros bajo locks (la excepción del trigger confía en esto): otro perfil `cliente` con `(tipo, doc normalizado)` = nuevo y `id <>` el perfil
   de esta identidad → `P0409` «otro cliente del Portal lleva ese documento»; si `p_tipo='DNI'`, otro lead vivo con ese DNI → `P0409`.
4. Bajo válvula: viejo → `historico` (`vigente_hasta=v_ahora`); nuevo → `vigente`, `verificado=true`, `fuente='correccion'`; perfil enlazado
   cuyo `(tipo, dni normalizado)` = viejo → `dni=norm, tipo_documento=p_tipo` (`23505` de `perfiles_dni_cliente_key` → `P0409`); lead enlazado
   cuyo `dni` = viejo → `p_tipo='DNI'` ? `dni=nuevo` (`uq_leads_dni_vivo` → `23505` → `P0409`) : `dni=null` (anotado); fila en
   `inversionista_correcciones`; actividad `nota` si hay lead activo (sin el número).
5. Devuelve `{ok, inversionista_id, identificador_nuevo_id, identificador_anterior_id, perfil:'actualizado'|'sin_cambio'|'ninguno',
   lead:'dni'|'nulo'|'sin_cambio'|'sin_lead'}`.

### `crm.enlazar_lead_inversionista_fn(p_lead_id, p_inversionista, p_motivo) → jsonb` `[v2-1, v2-6, E3-10]`
Guard OFF → Gerencia → identidad `activo` → el lead debe tener DNI y ese DNI debe ser un identificador `vigente+verificado` de ESA identidad
(regla #8; DNI nulo o distinto → `P0409` «corrige el DNI del lead o el de la persona primero»). Locks: jerarquía → advisory del DNI → identidad
`FOR UPDATE` → perfil del lead (si `perfil_id`) `FOR SHARE` → cierre del lead `FOR UPDATE` → tareas → lead `FOR UPDATE` (`inversionista_id is null`)
→ reservas del lead → claim de la identidad. Validación de la unión `[E3-10]`: la identidad no tiene NINGÚN otro lead (activos o no); el perfil
del lead, si existe, no pertenece a otra identidad no fusionada (si pertenece a esta o a ninguna → OK; a ninguna → `inversionistas.perfil_id`
se completa si estaba nulo, si ya tenía otro perfil → `P0409` dos perfiles); el cierre del lead, si existe, con `inversionista_id` nulo o igual
(nulo → se completa; distinto → `P0409`); sin puente ajeno para ese lead (`inversionista_leads.lead_id` único; si existe con otra identidad →
`P0409`); reservas del lead sin otra identidad. Efectos bajo válvula: `leads.inversionista_id`, puente `canonico` (o `historico` si la identidad
ya tiene canónico… no aplica: no tenía lead), veto OR (persona↔lead, tareas canceladas), actividad `nota` si activo. Sin responsable nuevo.

### `crm.reasignar_responsable_relacion_fn(p_inversionista, p_nuevo_responsable, p_motivo) → jsonb` `[Cx-17, v2-4]`
Guard OFF → Gerencia → jerarquía → identidad `FOR UPDATE` (activa) → el nuevo: miembro activo con `rol_crm in ('vendedor','supervisor','gerencia')`
y perfil activo (`22023`) → tramo abierto `FOR UPDATE` → mismo responsable → `sin_cambios` → `v_ahora` → cerrar (`hasta=v_ahora`), abrir
(`desde=v_ahora`, `motivo=p_motivo`, `por=uid`), `responsable_relacion_id`. **No toca** `leads.vendedor_id`, contratos, cierres ni atribuciones
(§6). Que el nuevo responsable reciba capacidad operativa (tenencia del lead, tareas) es `[D-2]`. Actividad `nota` si hay lead activo.

### Reversa `scripts/rollback-f2b-b5.sql`
Restaura byte a byte (md5 de prod) las 4 funciones vivas; DROP de las 5 RPC + 2 helpers; **conserva** `crm.inversionista_correcciones` (tabla
aditiva con hechos; se documenta). Se niega con la bandera ON. No deshace fusiones/correcciones/enlaces/tramos (append-only con rastro; el libro,
los históricos y las canónicas quedan coherentes sin las funciones). Frontera documentada: `rollback-f2-backfill.sql` se niega con
`fuente in ('fusion','correccion')`.

### Oráculo `oraculo-f2b-b5.sh` (banco-f7; dos sesiones psql; `run_as` con `set local role authenticated` + claims; RUN de 6 dígitos)
Fixtures por RUN: P y C creadas por `alta_cliente_identidad_fn` (saga completa) y por conversión coop (identidad sin perfil), con inversiones y
titulares (principal y cotitular) en ambos lados vía `inversiones_escritura` encendida solo para sembrar; tramos; un lead en P; cierre coop.
Fusión: hash viejo → P0409 · dos leads → P0409 · dos perfiles → P0409 · claim vivo → P0409 · reserva viva → P0409 · OK → P `fusionado`, no borrada;
`inversionista_por_documento(doc P)` = C y `resolver` = C; perfil/lead/puente/cierre/inversiones/titulares/reservas en C; principal único;
veto OR en C y lead, tareas canceladas; un solo tramo abierto; predecesora aplanada (A→B→C: `A.canonico = C`); libro con impacto sin documento;
`audit_log` de las tablas de identidad sin documento en claro; actividad en el lead activo · huellas ANTES/DESPUÉS: `conversion_episodios`
(mes abierto), `periodos_cerrados` y `cierre_mes_vendedor` (conteo + md5 agregado) · **intercalados** (dos psql): fusión ‖ `convertir_lead`
(perfil de P) → sin deadlock, termina en C o `40001`; fusión ‖ `saga cerrar` → sin deadlock; fusión ‖ corregir cierre (nota) → sin deadlock;
fusión ‖ `marcar_no_contactar` → sin deadlock; reintento idempotente de `convertir_lead` tras P→C → `inversionista_id = C`.
Corrección: a documento ajeno → P0409 · a histórico propio → reemite · DNI→DNI realinea perfil y lead (lead vetado incluido) · DNI→CE deja
`leads.dni` nulo · otro cliente del Portal con el nuevo → P0409 · otro lead vivo con el nuevo DNI → P0409 · claim vivo → P0409 · identificador
que dejó de ser vigente entre la lectura y el lock → 40001 · motivo con el documento → 22023 · fila en `inversionista_correcciones` ·
`convertir_lead` de ese lead a un perfil de OTRA persona → P0409 `[E3-11]`. Enlace: DNI nulo → P0409 · DNI ajeno → P0409 · identidad con lead
(inactivo) → P0409 · perfil del lead de otra identidad → P0409 · OK → puente + veto OR + cierre completado. Reasignación: inactivo → 22023 ·
OK → dos tramos (`hasta >= desde`), `leads.vendedor_id` intacto · mismo → `sin_cambios` · vendedor llama → 42501 (rol SQL + claims).
**OFF**: 5 RPC → P0409 «apagada» sin leer parámetros; las 4 vivas OFF → mismas respuestas/SQLSTATE que hoy (casos diferenciales: conversión
Avance y coop, saga apagada, UPDATE de `dni` por Gerencia sin válvula → P0481 como hoy) + md5 de las reversas = prod.

## E4 = las dos piezas de `public` (OK de Miguel 05/09) — diseño concreto v1 `[D-1]`
**Qué.** (a) **Crear un contrato reconoce a la persona:** `public.crear_contrato` (texto vivo, md5 de prod `a538aa6f…`), SOLO con
`resolver_en_puertas` encendida y SOLO si el cliente existe activo, llama a `private.asegurar_identidad_perfil(cliente, 'contrato')`
ANTES de su `for share` del perfil: jerarquía compartida → documento → identidad `FOR UPDATE` → perfil `FOR SHARE` (reentrante con el
`for share` de siempre) → resto de la función intacto (equipo `FOR SHARE` → contrato → advisory de cartera). Sin documento válido o con
documento de otra persona reconocida → `P0409` (contrato §4.3, fail-closed). Con OFF, byte a byte. **Colaboradores y registros del Portal
fuera** (decisión de Miguel): la identidad es de inversionistas; el equipo y los registrados sin invertir no tienen ficha de persona.
(b) **Candado del documento en el Portal:** trigger `trg_perfiles_zz_documento_protegido` (`BEFORE UPDATE OF dni, tipo_documento ON
public.perfiles`, función `private.trg_perfiles_documento_protegido()` definer, `search_path=''`): con la bandera encendida, si el perfil
está enlazado a una identidad no fusionada y el documento normalizado cambia, rechaza `P0409` «solo se corrige desde el CRM (Gerencia)»,
salvo que la GUC `crm.correccion_documento='on'` esté fijada (solo la fija `crm.corregir_documento_inversionista_fn`, b5). Con OFF o sin
cambio real (mismo documento con otro formato) devuelve `new`. No toca `public.proteger_campos_inmutables` (que congela otras columnas).
**Orden de locks:** el parche añade jerarquía→documento→identidad→perfil al PRINCIPIO de `crear_contrato`; ninguna puerta viva toma
equipo/contrato/cartera antes de la jerarquía (el offboarding la toma exclusiva primero; `derivar` jerarquía/equipo→lead), así que no
aparece un orden inverso. El trigger no toma locks.
**Censo de activación (prod, 05/09):** 420 clientes activos, 413 con identidad, 1 sin documento y 1 con documento inválido: con ON no
podrían firmar contratos nuevos hasta corregirlos (Gerencia, b5); los 5 restantes sin identidad la recibirían al primer contrato
(o `P0409` si su documento colisiona → fusión/corrección).
**Efectos ON que cambian respecto a hoy (solo con la bandera):** un contrato a un cliente sin documento válido se rechaza; el primer
contrato de un cliente sin identidad lo enlaza (y le abre tramo de responsable con su asesor activo); la administración del Portal no puede cambiar el DNI de un cliente reconocido (mensaje `P0409`; el Portal lo mostrará tal cual
hasta que se mapee → nota de activación `[D-12]`); `crear-cliente` e `importar-clientes` solo insertan y no se ven afectados.
**Reversa** `rollback-f2b-e4.sql`: restaura `crear_contrato` byte a byte (md5 de prod), suelta trigger y función; se niega con bandera ON.
**Oráculo** `oraculo-f2b-e4.sh`: ON: contrato a cliente con documento → contrato creado + identidad enlazada + tramo; cliente SIN documento →
`P0409` y sin contrato; cliente ya reconocido → mismo contrato de siempre; UPDATE de `dni` de un perfil enlazado sin GUC (como el Portal)
→ `P0409`; mismo DNI con otro formato → pasa; perfil no enlazado → pasa; `corregir_documento_inversionista_fn` (b5) sigue realineando el
perfil (GUC) → el oráculo b5 completo se repite encima. OFF: `crear_contrato` md5 = prod y un UPDATE de `dni` de perfil enlazado pasa.

## Entrega
Tres entregas, cada una = migraciones + reversa + oráculos + auditor-rls + Codex + ensayo en `banco-f7` + suite RLS + reversa ×2 + `!` de Miguel
(bandera OFF): **E1 = b1+b2**, **E2 = b3+b4** (con los dos OK de `public`), **E3 = b5**. Edges con la activación.
Decisiones que Miguel puede cambiar: offboarding (b2), OK a `public.crear_contrato` y trigger en `public.perfiles` (b3), alcance acotado de fusión (b5).

## Fuera de F2.b
Contrato-F3 (métrica por inversionista/mes; hasta entonces la fusión no toca cifras), F4 (`crm.inversiones` desde contratos), F5 (N inversiones,
`UNIQUE(lead_id)`, fusiones con dos leads/dos perfiles), activación de la bandera y front.

---

## `[D-13]` — «un solo lead» y «el puente manda» en TODAS las puertas con la bandera encendida (bloque 2 de activación) — v1, 05/09

**Origen:** auditor D-10 M2 y Codex D-10 #2/#3/#5 (ledger `## 20260905150000`). **Invariante:** contrato F0 #6 «un solo lead TOTAL por persona» y #8 «solo el documento vincula». **Censo prod 05/09:** 30 puentes, todos con enlace vivo; 0 históricos sin enlace vivo (hoy no muerde; b5 sí puede crearlos y la bandera no se enciende sin esto).

**Regla única (rama ON):** «los leads de una persona» = `private.leads_de_identidades(array[I])` (enlace vivo ∪ puente, canónicos e históricos; b5). «Una persona en conversión» = tiene una reserva de conversión por persona viva o sellada cuyo lead aún no está convertido (mismo predicado que `private.fusion_bloqueos`, b5:1375-1381): nuevo helper `private.persona_en_conversion(p_inv uuid, p_excluir_lead_id uuid default null) → boolean` (SQL stable, definer, `search_path ''`, sin EXECUTE a la API). Los claims NO cuentan a propósito: un claim en `reclamado` con lease vencido y sin reserva es un intento abandonado (lo retoma Gerencia con reserva sellada) y bloquearía a la persona para siempre.

**Decisión sobre la carrera de la saga (Codex #3): la reserva NO enlaza el lead (opción A).** Enlazar al reservar convertiría un DNI mal tecleado en un caso de Gerencia (corrección/enlace); dejarlo caducar es la cura de hoy (auditor b4 A1). En su lugar, las puertas de ALTA ven la reserva por persona. Serialización: TODA inserción de lead con DNI toma `private.identidad_bloquear_documento('DNI', dni)` en el trigger `trg_leads_000_hereda_veto` (b2; el primero en disparar) y `crear_lead_si_disponible` lo toma antes de sus contactos (b1:154) — la misma clave `inv_resolver:DNI:<doc>` que la reserva toma primero; así el alta lee las reservas DESPUÉS de que la reserva confirme o aborte. Orden total conservado: documento → identidad → contactos/lead. Leads sin DNI: fuera del invariante hasta que llegue el documento (contrato #8).

**Transformaciones (todas desde el texto VIVO de producción = banco por md5; generador `scripts/f2b/gen-d13.py`, guardas EXACTAS, postflight byte a byte, reversa que restaura y desregistra):**
- **T1** `private.verificar_disponibilidad_lead_impl(text,text,uuid)` (md5 `5f99912d…`), rama «un solo lead TOTAL por persona» (b1:417-442): en vez de `join crm.leads li on li.inversionista_id = i.id … li.id is distinct from p_excluir_lead_id`, la persona del DNI (identificador vigente y verificado, no fusionada) «ya es cliente» si `exists (leads_de_identidades(array[i.id]) x where x is distinct from p_excluir_lead_id)` **o** `persona_en_conversion(i.id, p_excluir_lead_id)`. `asesor` = responsable de relación, o quien reservó (`reservado_por` → `perfiles.nombre_completo`), o `'sin asesor asignado'`. Contrato del front intacto (`DisponibilidadLeadSchema` es `strictObject`: sin claves ni estados nuevos; `via: 'identidad'`). La sobrecarga de 2 args solo delega (md5 `742d44ff…`): sin cambio.
- **T2** `private.trg_leads_zz_enlaza_identidad()` (md5 `7986b01a…`), rama INSERT (b1:265-279): el «otro lead» sale de `leads_de_identidades(array[v_inv])` (excluido `new.id`), y si no hay otro pero `persona_en_conversion(v_inv, new.id)` → mismo `P0481` con `detail {estado ya_es_cliente, asesor (responsable o reservador), via identidad}` (solo lo ve service_role, b1 M2). Rama UPDATE OF dni: sin cambio (ya rechaza si la persona está reconocida).
- **T3** `crm.tomar_lead_libre(text,text)` (md5 `045d22cf…`): tras el lock del blanco y la revalidación de membresía (viva:139) y ANTES de «otro lead vivo con dueño» (viva:142): si la bandera está encendida y `coalesce(p_dni normalizado, v_lead.dni)` no es nulo, `v := verificar_disponibilidad_lead_impl(v_tel, ese dni, v_lead.id)`; si `v->>'via' = 'identidad'` → `return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni, v)` sin tomar. Cubre Codex #5 (descartado legado del mismo DNI con un convertido solo en el puente) y el brazo telefónico (el DNI del blanco). Solo lecturas dentro del lock del lead: sin arista nueva.
- **T4** `crm.convertir_lead(uuid,uuid)` (md5 `c30a0ac9…`) y **T5** `crm.convertir_lead_externo(…)` (md5 `0272febe…`): tras `[E3-11]`, «el puente del propio lead manda» (Codex D-10 #2), idéntico a D-10 v3: `if v_flag and v_inv is not null and exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) → P0409 «corrección o fusión de Gerencia»`.
- Sin cambio: `crm.crear_lead_si_disponible` (usa T1 y T2), `crm.verificar_disponibilidad_lead` (delega en T1), `trg_leads_zz_puente_identidad` (ya rechaza el puente discrepante fuera de válvula), `crm.reservar_conversion_lead` (D-10). Independiente de D-10 (no comparte función): puede aplicarse antes o después.

**Guardas:** b5 presente (`leads_de_identidades`, md5 `2421b2b7…`), b2 presente, bandera OFF, md5 EXACTO de las 5 (prod o D-13). **Postflight:** md5 de las 5 = D-13, la 2-args intacta, grants intactos (impl y trigger sin EXECUTE a la API; `tomar_lead_libre` y las conversiones como hoy), helper nuevo sin EXECUTE, bandera OFF. **OFF:** las cinco responden byte a byte como hoy (todo dentro de `v_flag`/bandera).

**Oráculo `scripts/oraculo-f2b-d13.sh` (banco, ON):** (1) persona con lead SOLO en el puente: `verificar_disponibilidad_lead` → `ya_es_cliente/identidad`; `crear_lead_si_disponible` con ese DNI → `ya_es_cliente`; INSERT directo con ese DNI (rol authenticated) → `P0481` con el detalle. (2) enlace vivo (regresión). (3) carrera: reserva por persona de un lead SIN DNI → INSERT de otro lead con ese DNI → `P0481`; `verificar` → `ya_es_cliente` con `asesor` = quien reservó; reserva caducada y no sellada → el INSERT pasa; reserva sellada con lead sin convertir → sigue bloqueando aunque caduque la ventana. (4) `tomar_lead_libre`: descartado legado (insertado con la bandera apagada, sin `inversionista_id`) del mismo DNI que una persona con un convertido solo en el puente → veredicto `ya_es_cliente/identidad` y el lead NO cambia; sin el puente → `tomado_ok` (par mutante). (5) conversiones: lead solo-puente con documento de OTRA persona → `P0409` en `convertir_lead_externo` y en `convertir_lead`; con su propio documento → convierte. (6) OFF: paridad (el INSERT pasa, `verificar` → `libre`, tomar como hoy). Encima: b1/b2 (si existen sus oráculos), b4, b5, E4, D-10. Bloque D-13 en `test-rls.mjs` (grants del helper y de las 5, OFF inerte).

**Preguntas abiertas para la refutación:** ¿basta la reserva (sin claims) como «en conversión»? ¿`asesor` = nombre de quien reservó es aceptable (misma clase de exposición que el responsable)? ¿T3 dentro del lock del blanco puede abrazarse con algo (solo lee)? ¿Falta alguna puerta ON (importador `crm-importar-leads` → INSERT → T2; `registrar_reingreso_lead_fn`; `rescatar_descartes`; `derivar_leads_equipo_fn`)? ¿El UPDATE OF dni de un lead solo-puente hacia un documento sin dueño debe rechazarse (hoy pasa; propuesto: sin cambio, es corrección de Gerencia si el lead ya tiene puente)?

### `[D-13]` v2 (05/09, tras la refutación de Codex —6 bloqueantes, 3 medios, 1 menor— y el auditor —2 medios, 10 notas—)

**Qué cambió respecto a la v1 (todo en la rama ON):**
- **«Reabrir o tomar ENLAZA» (Codex #5/#6, auditor M1).** Un lead vivo con el DNI de una persona reconocida queda enlazado (`leads.inversionista_id`, bajo válvula; el trigger zz escribe el puente canónico) al tomarse (`tomar_lead_libre`, T3), al rescatarse (`rescatar_descartes`, T7) y al deshacer un descarte (`private.deshacer_descarte_implementacion`, T8), igual que al nacer. Así la reserva, el sellado y las conversiones lo ven por identidad. Si el lead ya está en el puente de OTRA persona, no se reabre (`P0409`, corrección o fusión de Gerencia). Las tres puertas juzgan antes con el verificador (`estado = 'ya_es_cliente'` con o sin vía).
- **El sellado revalida «un solo lead» bajo el lock de la persona (Codex #1), T6** `crm.marcar_efectos_conversion(uuid,uuid,text)`: si la persona tiene otro lead (enlace vivo ∪ puente) distinto del reservado, no se sella (`P0409`) y no nace cuenta de portal. Cierra la carrera aunque el sellado arranque con un `now()` viejo, y el brazo telefónico de la toma que lee sin candado.
- **T3 (Codex #3/#4/#5, auditor M2/N2):** el candado documental del DNI tecleado se toma ANTES de bloquear filas (orden documento → lead, el de la reserva y el de marcar/levantar); se juzgan los DOS documentos (tecleado y del blanco, si difieren) y cualquier `ya_es_cliente` (con o sin `via`). El DNI del blanco se conoce tras su lock: ese brazo lee sin candado (residual documentado; lo cubre T6).
- **T4 (Codex #2):** `convertir_lead` rechaza convertir un lead con reserva viva o sellada de OTRA persona por la puerta directa (`P0409`); el cierre de la saga trae la misma persona y pasa.
- **T2 (Codex #7/#8, auditor N5):** rama UPDATE OF dni: un lead que está en un puente también es de una persona reconocida (solo Gerencia lo corrige); el `detail` de la rama «en conversión» lleva `lead_id` del lead reservado (el importador registra el reingreso).
- **T1 (auditor N3):** `asesor` = quien reservó solo mientras su reserva sigue vigente.
- **Guardas (auditor N1):** la premisa de serialización se comprueba en guarda y postflight: `trg_leads_000_hereda_veto` existe, habilitado, `BEFORE INSERT`, y su función toma `identidad_bloquear_documento` (es de **b1**, no de b2). **Registrador (Codex #9):** toma el mismo advisory que la ida y la reversa.
- Corrección de la v1: el INSERT directo del oráculo corre como el usuario del pooler (los triggers disparan igual); el camino «vendedor inserta por PostgREST» no aplica (grants por columna).

**Residuales que quedan escritos (no bloquean aterrizar apagado; cuentan para el encendido):**
- **`[D-14]` re-backfill al encender:** un lead vivo con DNI y sin enlace (nació con la bandera apagada, o el DNI llegó por UPDATE) es invisible a la identidad hasta que se reabre/toma/convierte. Antes del `!` de la bandera: censo y enlace masivo de leads vivos con DNI de personas reconocidas (misma regla que al nacer), como hizo el backfill de F2 el 03/09.
- Una reserva sellada cuyo lead se descarta o soft-borra sin convertir deja a la persona «en conversión» indefinidamente (bloquea alta y fusión; `verificar` nombra al reservador mientras esté vigente). Sin herramienta de limpieza hoy: vía de Gerencia o censo (auditor N6). Un claim abandonado sin reserva tampoco tiene herramienta (`retomar` exige reserva sellada; Codex #10): no bloquea nada porque los claims no cuentan como «en conversión».
- Reparto y derivación asignan leads vivos sin juzgar «un solo lead» (Codex #6): no crean ni reabren leads; con las puertas de alta/reapertura cerradas, un lead vivo ya es de su persona. Sin cambio.

### `[D-13]` v3 (05/09 noche, tras la refutación de Codex sobre la v2.1 construida: 8 bloqueantes, 4 medios, 1 menor)

**El hueco de fondo que la v2 no veía:** «solo el documento vincula» dejaba invisibles a la identidad los leads con DNI pero SIN enlace (nacieron con la bandera apagada, o antes de que existiera la persona, o su DNI llegó por UPDATE): ninguna comprobación «un solo lead» los contaba, así que una reserva, un sellado o una conversión podían seguir adelante con un segundo lead vivo de la misma persona a la vista. Además, la reapertura se podía hacer por UPDATE directo de `etapa` saltándose las tres puertas, y la toma/reapertura enlazaba DESPUÉS de que el sellado revalidara.

**Decisiones de la v3:**
1. **«Los leads de una persona» = enlace vivo ∪ puente ∪ SUELTOS vivos con un documento vigente de la persona** (`private.leads_de_personas`; los descartados sueltos no cuentan: los ofrece el camino «reutilizable» y los juzga la reapertura). Cuenta en el verificador, el nacimiento, la toma, el rescate, el deshacer, el sellado, las dos conversiones y la reserva por persona (texto de D-10, que por eso es REQUISITO de D-13). Regla estricta: un lead vivo suelto con el DNI de la persona impide convertir OTRO lead sin DNI de esa persona (la reserva lo dice de entrada, con el `lead_id` del suelto: se trabaja ese).
2. **Reabrir un descarte con la bandera encendida solo por sus puertas** (tomar, rescatar, deshacer): trigger `trg_leads_zz_reapertura_solo_rpc` (BEFORE UPDATE OF etapa, activo) con el GUC `crm.reapertura_identidad` que fijan las tres RPC alrededor de su UPDATE; Gerencia bajo válvula pasa. Mismo patrón que `trg_leads_00_devolucion_equipo_solo_rpc`.
3. **Candados ANTES de la fila** en tomar/rescatar/deshacer, en el orden total documento → persona → lead (el de la reserva, el sellado y la fusión): `private.bloquear_personas_de_leads` toma todos los documentos implicados (de los leads, el tecleado y los vigentes de sus personas) en orden de texto `tipo:doc` (como `identidad_bloquear_documentos_de` de la fusión) y las personas FOR SHARE por id; el blanco de la toma se localiza SIN lock con el mismo criterio y, tras tomar la fila, se verifica que sea el candidato y que su persona esté entre las bloqueadas (si no, veredicto fresco / `40001`). Así el enlace posterior (FK KEY SHARE sobre la persona) no puede abrazarse con `marcar_no_contactar` (persona → lead), y el sellado y la toma por el mismo documento se serializan.
4. **Juicio único** `private.juicio_reapertura(lead, tel, dni_tecleado)`: verificador con el documento tecleado y con el del blanco (cualquier `ya_es_cliente`, con o sin `via`); las personas halladas (enlace, documento tecleado, documento del blanco, puente) deben ser UNA; la persona no puede tener otro lead (`leads_de_personas`), ni estar en conversión, ni ser ya cliente (perfil enlazado, activo o no —Codex #9—). Solo lecturas.
5. **El sellado (T6)** toma los documentos vigentes de la persona antes de su FOR UPDATE; bajo el lock revalida la pareja (lead, claim, persona) con la reserva FOR UPDATE (`40001` si cambió: Codex #5), el lead FOR SHARE (vivo, no convertido/descartado, sin otra persona: Codex #4) y «un solo lead» con `leads_de_personas` (Codex #1/#3).
6. **Enlazar al tomar/reabrir** (`private.enlazar_lead_reabierto`): bajo válvula restaurada; un puente histórico del propio lead pasa a canónico si la persona no tiene otro (Codex 13).
7. **T2, rama UPDATE OF dni (Codex #2):** sin candado documental (evita el orden fila → documento); si la persona nace después, el suelto cuenta por documento en reserva, sellado y conversiones.

**Residuales (para el encendido):** `[D-5]` cierra las RPC de 1 argumento (Codex #8; la garantía «sin cuentas huérfanas» vale solo tras D-5). `[D-14]` re-backfill al encender sigue siendo higiene (ya no seguridad): enlaza los sueltos con DNI para que la operación los vea como de su persona. Reserva sellada sin cuenta creada (Auth falló tras sellar) deja a la persona «en conversión» hasta que Gerencia actúe (Codex 12; herramienta pendiente en D-5). Importador: la copia de `_supabase_functions` no registra reingresos y el duplicado por teléfono devuelve antes (Codex 11; `[D-4]`).

### `[D-13]` v4 (05/09 noche, tras Codex sobre la v3.1 construida: B1..B4 de integridad, B5 = D-15, M1..M3, N1)

- **B1 — el DNI de un lead se FIJA por su puerta** (`crm.fijar_dni_lead_fn(lead, dni)`, EXECUTE `authenticated`, ámbito de la policy `leads_update`): candado del documento nuevo y persona FOR SHARE ANTES de la fila (orden documento → persona → lead), `juicio_persona` (veto → `P0429`; otro lead / conversión / ya cliente → `P0409`), un lead ya enlazado o en un puente → corrección de Gerencia, un lead con reserva viva o sellada → «conversión en curso», UPDATE bajo el GUC `crm.dni_por_puerta` y enlace si la persona existe (con puente canónico). El trigger de nacimiento, rama UPDATE OF dni, rechaza con la bandera encendida cualquier cambio de DNI sin ese GUC ni válvula (el UPDATE directo llega con la fila bloqueada y no puede serializarse con una reserva en vuelo). Con la bandera apagada la puerta es el UPDATE de hoy. **El front (edición del DNI en la ficha del lead) pasa a llamar la puerta: va con `[D-15]`.** Mejora colateral: fijar el DNI de una persona reconocida que no tiene lead ahora ENLAZA (antes b1 lo rechazaba).
- **B2 —** el sellado (T6) exige además que el DNI actual del lead sea nulo o resuelva a la persona reservada; y la puerta del DNI no cambia el documento de un lead con reserva viva/sellada.
- **B3 —** el sellado relee el `token_hash` del claim DESPUÉS de los locks (`40001` si una reanudación rotó el token).
- **B4 —** `convertir_lead` rechaza también una conversión Avance en curso en OTRO lead de la persona (`persona_en_conversion`), como ya hacía `convertir_lead_externo`.
- **M1 —** `juicio_persona` (nuevo helper, usado por `juicio_reapertura` y por la puerta del DNI) devuelve `no_contactar` si la persona —también la hallada solo por puente— está vetada; tomar → veredicto `no_contactar`; rescatar/deshacer → `P0429`.
- **M2 —** un cliente del Portal con ese documento, aunque esté inactivo y sin ficha, «ya es cliente» en el juicio; el trigger de nacimiento también rechaza un lead nuevo para una persona con perfil enlazado sin otros leads.
- **M3 —** `leads_de_personas` atribuye sueltos solo por identificadores `verificado = true` (alineado con `inversionista_por_documento`).
- **N1 —** el oráculo declara D-10 como requisito; las pruebas con `service_role` viven en la suite.
- Sin cambio frente a la v3: helpers, candados antes de la fila, trigger «reabrir solo por RPC», enlace al reabrir, reserva por documento.

### `[D-13]` v4.1 / v4.2 (05/09, tras el auditor sobre la v4 y Codex sobre la v4.1)
- **v4.1:** el trigger de nacimiento (rama UPDATE OF dni) rechaza enlace/puente siempre, deja pasar por la puerta (GUC), y solo entonces juzga el UPDATE directo (persona reconocida → «solo Gerencia lo corrige»; documento libre → «por su puerta»): sin esto la puerta nunca podía enlazar (auditor v4 A1). La puerta comprueba el ámbito ANTES de tomar candados (sin sondeo temporal, auditor M1). El sellado bloquea el claim FOR SHARE tras la reserva antes de releer el token (N1). El cliente por documento del juicio filtra por tipo DNI (N3).
- **v4.2:** la puerta del DNI bloquea el documento ANTERIOR y el nuevo (en orden de texto), y toma/rescate/deshacer verifican tras tomar la fila que el DNI sigue siendo el que bloquearon (Codex v4.1: un cambio de DNI en medio dejaba obsoleto el candado de una toma en vuelo, y una conversión coop con el documento nuevo podía crear a la persona sin que la toma la viera). Fixture M3 del oráculo corregido (el resolver no crea identidades sin verificar).

### `[D-13]` v4.3 (05/09, tras Codex sobre la v4.2: un bloqueante ABA y un menor)
- **El hallazgo (Codex, estático):** en toma, rescate y deshacer, el DNI que se guardaba para comparar (`v_dni_candidato` / `v_dnis_antes` / `v_dni_antes`) y los documentos que bloqueaba `private.bloquear_personas_de_leads` salían de **dos lecturas distintas**. Con la puerta del DNI corriendo en medio (A→B→A), la reapertura bloqueaba B, releía A, comparaba A = A y **aprobaba reteniendo solo el candado de B**: una conversión coop concurrente con A podía crear la persona sin que nadie la viera. Menor: la propia puerta calculaba {anterior, nuevo} antes de esperar y, tras el `FOR UPDATE`, solo comparaba con el destino, así que dos llamadas concurrentes podían escribir C sin haber bloqueado B.
- **La corrección (v4.3): se compara contra lo que REALMENTE se bloqueó, no contra una foto.** `bloquear_personas_de_leads` devuelve ahora `{personas, claves}` (lo que bloqueó, en orden). Nuevo helper `private.lead_dentro_de_bloqueo(lead, bloqueo)`: con la fila ya bloqueada por el llamador, lee el DNI y la persona ACTUALES del lead en esa misma consulta y exige que `'DNI:'||dni` esté entre las claves bloqueadas y la persona (`lead_persona_reabrir`) entre las personas bloqueadas (nulos pasan: sin documento no hay carrera por documento). Toma: `v_lead.id = v_candidato and lead_dentro_de_bloqueo(...)`, si no → veredicto fresco. Rescate y deshacer: dentro del bucle `FOR UPDATE`, si no → `40001` («vuelve a intentarlo»). La puerta del DNI acumula en `v_claves` lo que bloqueó y, tras el `FOR UPDATE`, con bandera encendida, si el DNI actual no está entre ellas → `40001`. Con esto, cualquier secuencia de cambios de documento entre la foto y la fila deja al lead FUERA del conjunto bloqueado y la reapertura no escribe; y si está dentro, el candado del documento vigente se sostiene en el momento de la escritura (la coop con ese documento espera o ya confirmó y su persona se ve).
- **Orden de candados intacto:** documento advisory (todos, ordenados) → personas `FOR SHARE` (por id) → fila → reservas → claims. El helper nuevo es `STABLE`, sin candados propios.
- **Ensayo:** el ensayo v4.2 dejó una lección de arnés: la bandera se apagó a mitad del oráculo (los rojos posteriores decían «Identidad unificada apagada») porque `flag()` escribía sin releer; ahora relee y reintenta 5 veces, y si no lo consigue lo cuenta como rojo. El resumen de ese ensayo («68/74») venía de un log viejo por un nombre de archivo mal cambiado en el script de banco; el log real era 43/31 en cascada desde N3. Ninguno de los dos era un fallo de la migración.

### `[D-13]` v4.4 (05/09, tras Codex sobre la v4.3: sin ABA; cuatro menores)
- **Codex no encontró** ningún intercalado (ABA ni A→B→C) que escriba sin el candado del documento vigente con la bandera encendida y READ COMMITTED, ni deadlock nuevo, ni consumidor de la firma vieja; huellas, reversa y registrador consistentes (md5 `aa1bda20…` de la v4.3).
- **[1] La bandera apagada a mitad de la operación:** `identidad_bloquear_documento` (b1) es un no-op con la bandera apagada; si alguien la apagaba entre la primera lectura y los candados, el helper devolvía claves «bloqueadas» sin candado real. **v4.4:** el helper relee la bandera DESPUÉS de los candados y, si está apagada, devuelve conjuntos vacíos (toma → veredicto fresco; rescate/deshacer → `40001`); la puerta del DNI relee la bandera tras el `FOR UPDATE` y levanta `40001` si se apagó.
- **[2] Aislamiento:** la comprobación «sigue dentro de lo bloqueado» relee tras esperar, y eso solo vale en READ COMMITTED (en REPEATABLE READ el snapshot viejo esconde a una persona confirmada por otra transacción; el resolver de F1 ya asume READ COMMITTED). **v4.4:** helper y puerta exigen `transaction_isolation = 'read committed'` (si no, `0A000` con mensaje claro). PostgREST, las edges y psql van en READ COMMITTED por defecto: no cambia nada para la app.
- **[4] Puerta de la suite:** ya gateaba por `lead_dentro_de_bloqueo` desde la nota N1 del auditor v4.3.
- **[5] El registrador solo comprobaba las 9 funciones transformadas:** **v4.4:** exige además los 9 helpers y la puerta vivos con su forma (definer + `search_path` vacío) y el trigger de reapertura montado.
- **Oráculo:** nueva sección (11) con los asertos directos que pidió el auditor (N2): `lead_dentro_de_bloqueo` con el documento bloqueado → dentro; con OTRO documento (el ABA) → fuera; persona no bloqueada → fuera; lead sin DNI ni persona con bloqueo vacío → dentro; y la guarda de aislamiento en el helper y en la puerta (REPEATABLE READ → `0A000`, DNI intacto). Total **81 asertos**.

## Bloque 2 de activación — `[D-9]`, `[D-3]`, `[D-2]` — diseño v1 (05/09/2026, noche)

Tres migraciones independientes, una por ítem (cada una con su reversa byte a byte, su registrador y su oráculo bash; generadas desde el texto
VIVO de producción por `scripts/f2b/gen-d9.py`, `gen-d3.py`, `gen-d2.py` sobre `vivas/bloque2/` y `huellas-bloque2-prod.txt`). D-3 y D-2
aterrizan APAGADAS (rama ON = todo lo nuevo; con OFF las funciones responden byte a byte como hoy); D-9 no va detrás de la bandera.

### `[D-9]` (`20260906100000`) — los auditores genéricos de `crm.leads` y `crm.cierres_externos` no copian el documento
`private.log_audit_crm()` copia la fila entera a `public.audit_log`; en `leads` va `dni` y en `cierres_externos` `documento` ([E3-13]).
Los dos triggers (`trg_audit_leads`, `trg_audit_cierres_externos`, MISMO nombre ⇒ mismo orden entre los AFTER) pasan a
`private.log_audit_sin_secretos('dni')` / `('documento')`: auditor ya vivo (suscripciones_push, agenda_ics, inversionista_identificadores),
enmascara con `"***"` sin huella, conserva `null`, y **omite el UPDATE que solo mueve `actualizado_en`** (regla de ruido: documentada; con
`log_audit_crm` ese UPDATE dejaba una fila idéntica salvo el reloj). El trinquete (`private.tablas_sin_rastro`) reconoce ese auditor por
OID; el sello de exenciones no cambia. **Decisión para Miguel:** las filas HISTÓRICAS con documento en claro (05/09: 163 de leads, 33 de
cierres) no se tocan —la auditoría no se reescribe sola—; enmascararlas sería una migración aparte con su OK. Lectores de `audit_log`
comprobados: `bandeja_actividad` (nombre/contrato/creado_por), `corregir_fecha_cierre_comercial` y `marcar_contrato_demo` (escriben), el
front (`store.tsx` solo comenta) y `eliminar-cliente` (comenta): ninguno lee `dni`/`documento` de esas filas.

### `[D-3]` (`20260906110000`) — el veto de la persona es coherente (contrato §7.3)
- **Regla:** «los leads de una persona» para el VETO = enlace vivo ∪ puente ∪ SUELTOS con su DNI vigente y verificado, en cualquier etapa
  (`private.leads_de_persona_veto(uuid)`); su perfil cliente (`inversionistas.perfil_id`) lleva las tareas de cliente. Se calcula BAJO el
  lock de la persona (la corrección documental y la fusión de b5 también lo toman): el conjunto es estable hasta el commit. Ojo de forma:
  `uq_leads_dni_vivo` solo admite UN lead vivo por DNI, así que un suelto vivo con el documento existe solo cuando el enlazado está cerrado.
- **`crm.marcar_no_contactar`:** identidad → tareas (de esos leads + las de CLIENTE del perfil) `FOR UPDATE` → leads (el conjunto entero,
  `order by id`, `FOR UPDATE`): todos heredan `no_contactar`; todas las pendientes se cancelan como sistema; `leads_afectados` cuenta el
  conjunto. **`levantar`:** simétrico sobre los leads (no revive tareas). Con OFF: solo el lead (byte a byte hoy).
- **Gate de seguimiento (`private.trg_gestion_lead_serializada`):** la tarea de PERFIL (`lead_id null`, `perfil_id`) → con ON y fuera de la
  válvula, `private.persona_vetada_perfil(perfil)` → `P0429`. Writers internos (`auth.uid null`) siguen exentos.
- **`private.persona_vetada_perfil(uuid)`:** por el enlace perfil↔identidad (canónica) o por el documento exacto del perfil (identificador
  vigente y verificado); OFF ⇒ false.
- **Ficha del cliente:** trigger nuevo `trg_actividades_cliente_01_veto_persona` (BEFORE INSERT en `crm.actividades_cliente`): tipos de
  CONTACTO de una persona vetada → `P0429`; `nota`/`reasignacion` entran; `auth.uid null` y válvula exentos. Cubre `crm.cerrar_tarea` y
  cualquier escritor futuro.
- **`private.leads_vetados_persona(uuid[])`** (el gate por lead) ve además el PUENTE (un histórico sin enlace vivo de una persona vetada).
- Sin cambio: `rescatar_descartes`/`derivar` (ya usan `persona_vetada`), `trg_leads_000_hereda_veto` (b1).

### `[D-2]` (`20260906120000`) — salida de un analista sin personas sin responsable; capacidad operativa del nuevo responsable
- **`crm.impacto_desactivacion_usuario_fn`:** con ON cuenta `personas_a_cargo` (identidades ACTIVAS con tramo abierto del saliente en
  `inversionista_responsables` o `responsable_relacion_id` = saliente) y las suma a `requiere_reemplazo`. La clave nueva aparece SOLO con
  ON: el front valida con `v.strictObject` (`ImpactoDesactivacionUsuarioSchema`) ⇒ **prerrequisito del bloque 4 (front): añadir
  `personas_a_cargo` opcional al esquema y una tarjeta en `ResumenImpacto` ANTES del encendido** (con OFF la respuesta es byte a byte hoy).
- **`crm.fijar_membresia_activa_fn` (offboarding):** lee la bandera BAJO el interlock exclusivo de jerarquía (las puertas de b5 lo toman
  compartido: no se cruzan). Con reemplazo: bloquea las personas del saliente ANTES que sus leads (`FOR NO KEY UPDATE`, que serializa contra
  el `FOR UPDATE` de reasignar/marcar/convertir sin chocar con los `KEY SHARE` de las FK del puente) y sus tramos abiertos `FOR UPDATE`; tras
  los traslados de hoy (equipo → leads → tareas → perfiles) cierra cada tramo abierto (`hasta = v_ahora`) y abre otro al reemplazo
  (`motivo 'offboarding'`, `por` = Gerencia, `desde = v_ahora`, un único reloj tras los locks [E3-14]) y mueve `responsable_relacion_id`;
  el evento `membresia_desactivada` lleva `personas_transferidas` (solo con ON). Sin reemplazo y con personas a cargo → se niega con el
  mensaje de hoy, aunque la bandera cambiara entre las dos lecturas. Orden de aristas persona → lead = el de conversiones y veto.
- **`crm.reasignar_responsable_relacion_fn` (b5):** tras el tramo, si el nuevo responsable puede tener cartera (`rol_crm` efectivo
  vendedor/supervisor): los leads VIVOS en tenencia operativa (`private.leads_de_personas` de D-13: enlace ∪ puente ∪ sueltos vivos
  verificados; `activo` y etapa abierta) se bloquean (tareas pendientes `FOR UPDATE` → leads `FOR UPDATE`) y pasan a `vendedor_id = nuevo`,
  `asignado_supervisor_id = null` (los triggers de leads llevan el ledger `lead_asignaciones` —cierre `transferido`/`parqueado`, apertura
  `reasignado`/`asignado`—, la actividad «reasignacion», `tenencia_desde` y las tareas pendientes); el perfil cliente de la persona pasa a
  `asesor_perfil_id = nuevo` (el trigger del perfil mueve las tareas de cliente y deja la actividad de cliente «reasignacion»). Con Gerencia
  como nuevo responsable solo cambia el tramo. Respuesta: `+ tenencia {estado movida|sin_cambios, leads_movidos, perfil_movido}`.
  `sin_cambios` (tramo ya en el destino) no mueve cartera. Un lead cerrado nunca se mueve.
- Retirado sin construir: `crm.personas_por_responsable_fn` (un conteo no es un interlock; nunca llegó a producción).

**Oráculos:** `scripts/oraculo-f2b-d9.sh` (18), `oraculo-f2b-d3.sh` (36), `oraculo-f2b-d2.sh` (≈50; crea V2/V3 bajo S; incluye el
interlock con una baja en curso → `55P03`). Cada uno sale ROJO sin su migración (mutante).

### Bloque 2 v2 (06/09 madrugada) — respuesta al auditor-rls (sin bloqueantes; medios M1..M7)
- **D-3 M1** documento → persona en `marcar`/`levantar` (`identidad_bloquear_documentos_de` antes del `FOR UPDATE` de la persona, relectura → `40001`): la puerta del DNI (D-13) ya no puede llevarse un suelto mientras se propaga el veto. Residual: persona con 2+ DNI vigentes en la rama del suelto → posible `40P01` reintentable.
- **D-3 M3** `v_perfiles` = perfil enlazado ∪ perfiles cliente con un DNI vigente de la persona (simetría con `persona_vetada_perfil`).
- **D-2 M2** el UPDATE de leads revalida `activo`, etapa abierta y pertenencia (`leads_de_personas`) bajo los locks. **M5** con ON, el offboarding bloquea las tareas pendientes del saliente antes de sus leads (tareas → leads). **N4** personas no fusionadas (no solo `activo`). **N5** `movida` solo si se movió algo. **M4** front: `personas_a_cargo` opcional + tarjeta (hecho, sin publicar). **M7** oráculo: supervisor como nuevo responsable.
- **D-9 M6** (decisión de Miguel): enmascarar también teléfono/fecha de nacimiento/género/monto en el rastro de leads. **N1**: `fijar_dni_lead_fn` no deja actividad del hecho.

### Bloque 2 v3 (06/09 madrugada) — respuesta a Codex (refutó la v1: NO-GO para encender; 14 hallazgos, 4 bloqueantes)
| # | Hallazgo (Codex) | Respuesta v3 |
|---|---|---|
| 1 | BLOQUEANTE · ciclo tareas → lead de `reasignar`/`marcar` frente a `derivar`/`repartir` (lead → tareas por el trigger de sincronización); b5 ya usaba NOWAIT por esto | **HECHO**: `reasignar`, `marcar` y `levantar` toman los leads del conjunto `FOR UPDATE NOWAIT` → `55P03` se convierte en `40001` («otra sesión está trabajando uno de los leads»); solo con ON (con OFF no hay tareas bloqueadas). Oráculos: lead retenido por otra sesión → `40001` en ≤ 3 s. |
| 2 | MEDIO · offboarding leads → tareas frente a `cerrar_tarea` (heredado, también OFF) | Con ON el offboarding bloquea las tareas pendientes del saliente ANTES de sus leads (auditor M5); con OFF queda el orden heredado (documentado, no lo introduce D-2). |
| 3 | BLOQUEANTE · una conversión en vuelo (no toma el interlock de jerarquía) abre un tramo al saliente DESPUÉS del censo | **HECHO**: recenso tras los dos UPDATE de leads (que dejan bloqueados todos los leads vivos del saliente: ninguna conversión suya sigue en vuelo); lo que apareció se bloquea `FOR NO KEY UPDATE NOWAIT` (persona tras lead es la arista inversa → `40001`, Gerencia reintenta) y se suma al traslado. |
| 4 | BLOQUEANTE · conjunto de leads no estable (`fijar_dni_lead_fn(Ls, NULL)` no bloquea a la persona vieja) | **Ya en v2** (auditor M1): documento → persona en `marcar`/`levantar` (advisories de los documentos vigentes antes del `FOR UPDATE` de la persona, relectura → `40001`); en `reasignar` el UPDATE revalida pertenencia/etapa bajo los locks (M2). |
| 5 | MEDIO · una tarea de perfil insertada en paralelo al veto sobrevive (el gate no bloqueaba a la persona) | **HECHO**: el gate de perfil pasa a un trigger propio `trg_tareas_00_0_veto_persona` (corre primero) que bloquea a las personas del perfil `FOR SHARE` (persona → perfil, el orden de reasignar) antes de juzgar: o nace antes del veto y `marcar` la cancela, o nace después y se rechaza. |
| 6 | MEDIO · perfil reconocido solo por documento fuera de la cancelación; `cerrar_tarea` de una reunión sin `resultado_tipo` no pasa por el gate | Cancelación por documento **ya en v2** (M3). El cierre de una reunión ya agendada sin resultado de contacto no es seguimiento nuevo: se documenta como alcance (una vez vetada, no quedan pendientes salvo la carrera #5, cerrada). |
| 7 | BLOQUEANTE · `marcar`/`levantar` desde un lead SOLO-PUENTE no resuelven a la persona | **HECHO**: la persona se resuelve por el puente (canónica) antes que por documento; revalidación propia tras bloquear el lead (`40001` si el puente cambió). Oráculo: marcar(LP) veta a P y su conjunto; levantar(LP) lo levanta y el gate deja de ver a LP. |
| 8 | MEDIO · `reasignar` mueve un lead cerrado tras capturarlo | **Ya en v2** (M2). |
| 9 | MEDIO · reloj del ledger (`statement_timestamp`) vs un episodio abierto por `derivar` en paralelo → CHECK y abort | Aceptado como residual: con NOWAIT (#1) el caso exige que `derivar` confirme entre el cálculo y el bloqueo; el resultado es un abort limpio (`lead_asignaciones_intervalo_valido`), nunca un intervalo corrupto; Gerencia reintenta. |
| 10 | MEDIO · paridad OFF: `new.perfil_id` en el trigger compartido con `actividades` → `42703` en vez de `42501` | **HECHO**: `private.trg_gestion_lead_serializada` vuelve a ser byte a byte (ya no se transforma; el postflight lo exige); el gate de perfil vive en el trigger propio de tareas (#5). Oráculo: actividad sin lead con OFF → `42501`. |
| 11 | BLOQUEANTE (front) · `personas_a_cargo` rompe el esquema estricto | **HECHO** (v2): `personas_a_cargo: v.optional(...)` + tarjeta en `ResumenImpacto`. |
| 12 | MEDIO · documentos en motivos (`marcar`/`levantar` no sanean; `reasignar` valida antes del lock) | **HECHO**: `marcar`/`levantar` rechazan (`22023`) un motivo con un documento vigente de la persona (regla documental de b5, sin su largo mínimo); `reasignar` revalida el motivo BAJO el lock de la persona. Los auditores genéricos de `actividades` y tramos siguen copiando la fila (heredado; el motivo ya no puede llevar el documento). |
| 13 | MEDIO · registradores sin advisory (pueden registrar tras una reversa) | **HECHO**: los tres toman el mismo advisory que migración y reversa. |
| 14 | MEDIO · registradores no certifican cuerpos/`tgenabled`/grants | **HECHO**: D-3 exige `md5(prosrc)` de los 5 helpers, triggers habilitados y grants; D-2 grants/definer; D-9 huellas del auditor sin secretos y `enmascarar_claves`, y auditores habilitados. |
| — | Negocio: mover `asesor_perfil_id` desde el CRM requiere OK de Miguel; `sin_cambios` no reconcilia cartera | Para Miguel (el offboarding vivo ya lo mueve; D-2 lo extiende a `reasignar`). Checklist del encendido (`[D-14]`): reconciliar cartera ↔ responsable antes del `!` de la bandera. |

### Bloque 2 v4 (06/09 madrugada) — respuesta a la segunda ronda de Codex (sobre la v3: **GO para aterrizar apagadas las tres**; NO-GO para encender)
Codex cerró #1, #4, #7, #8, #10, #11, #13 y dejó abiertos #2 (heredado con OFF), #3, #5, #6, #9, #12, #14 y cinco hallazgos nuevos (N1–N5) más N6.
| # | Hallazgo | v4 |
|---|---|---|
| N1 | BLOQUEANTE (para encender) · el `FOR SHARE` del gate de tareas de perfil crea el ciclo persona ↔ tarea con `cerrar_tarea` → `crear_siguiente_tarea` (retiene la tarea y agenda la siguiente del mismo perfil) frente a `marcar` (retiene la persona y espera la tarea) | **HECHO**: el gate toma a las personas `FOR SHARE NOWAIT` → `40001` («la persona está siendo actualizada»); nunca se espera con una tarea en la mano. Y `marcar` toma las tareas `FOR UPDATE NOWAIT` → `40001`. |
| #5 | la tarea de perfil insertada en paralelo a una fusión bloquea una persona que ya no es la del perfil | **HECHO**: tras el lock se revalida que las personas del perfil sigan siendo las bloqueadas (`40001` si cambió). |
| N2 | ciclo persona ↔ equipo: el alta de tarea (persona → equipo del asesor) frente al offboarding (equipo → personas) | **HECHO**: el primer censo del offboarding toma a las personas `FOR NO KEY UPDATE NOWAIT` → `40001` («vuelve a intentar la baja»). |
| N3 | la relectura de documentos volvía a tomar candados con la persona ya bloqueada (persona → documento) | **HECHO**: la relectura es una lectura pura (sin candados); si el juego cambió → `40001`. |
| N4 | `reasignar` iba tareas → perfil mientras el Portal va perfil → tareas (trigger) | **HECHO**: `reasignar` toma tareas y perfil `NOWAIT` → `40001`; con persona y tramo en la mano no espera nada más. |
| #6 | la cancelación por documento solo miraba perfiles DNI (el gate reconoce CE/Pasaporte) | **HECHO**: `v_perfiles` compara `tipo:documento` con cualquier tipo. |
| #12 | el motivo se contrastaba solo con los documentos vigentes (un DNI histórico pasaba) | **HECHO**: se contrasta con TODOS los identificadores de la persona (vigentes e históricos). |
| #14 / N5 | registradores: `proconfig` solo «contiene» `search_path`; funciones de trigger sin comprobación de EXECUTE; registro con `statements` nulo o de más de un elemento | **HECHO**: `proconfig` EXACTO (`{search_path=""}`), EXECUTE de anon/authenticated/service_role en los 5 objetos, y el registro exige `statements` de exactamente 1 elemento no nulo con la huella. |
| #3 | una conversión cuyo ASESOR DE PERFIL es el saliente (y el lead es de otro vendedor) abre el tramo tras el recenso (lee `equipo.activo` sin candado) | **Abierto para el encendido**: hay que endurecer `convertir_lead` (D-13/D-5): tomar el perfil `FOR SHARE` y revalidar `equipo.activo` bajo el interlock compartido de jerarquía antes de abrir el tramo. Hasta entonces la baja no puede garantizarlo. |
| N6 | la fusión hereda el veto pero solo cancela tareas de LEAD (b5) | **Abierto para el encendido** (escritor de b5): que la fusión cancele también las tareas de cliente de los perfiles de la canónica. |
| #9 | reloj del ledger vs `derivar` en paralelo → abort limpio | Residual aceptado (documentado). |
| #2 | offboarding leads → tareas con OFF (heredado) | Residual heredado (documentado); con ON lo cubre M5. |
| — | puentes históricos desnormalizados (P fusionada conserva puentes) y gate del puente a un salto | Hipótesis sin datos: la fusión vigente aplana y mueve puentes; `[D-14]` (re-backfill) debe verificar que no haya puentes bajo identidades fusionadas. |

**Decisiones de Miguel (06/09 madrugada):** (1) sí: `reasignar` mueve `public.perfiles.asesor_perfil_id` (una sola verdad CRM↔Portal); (2) la bitácora de leads tacha también `fecha_nacimiento` y `genero` (teléfono y monto en claro, son lo que se investiga) → D-9 v2 del trigger; (3) las filas históricas de `audit_log` se dejan.

## Bloque 3 de activación — `[D-4]` el importador entra por la puerta SQL — diseño v2 (06/09/2026)
**Problema.** El edge `crm-importar-leads` inserta directo con service_role y adivina el veredicto parseando errores; el orden de candados del INSERT directo es fila → contactos (el ciclo preexistente de [v2-2]); con la identidad encendida leía la bandera y pedía el reingreso aparte.
**Regla.** El contrato del importador NO es el de la puerta del front (`crear_lead_si_disponible` consulta el veredicto comercial); es el de la fila al nacer SIN sesión humana (`trg_leads_disponibilidad_atomica`): formato + candados; mandan el índice único de contacto vivo y, con ON, los triggers de nacimiento. Por eso `crm.importar_lead_fn(jsonb)` (solo service_role, `auth.uid()` nulo) toma documento → persona → contactos y hace el MISMO INSERT, traduciendo `23505` → `duplicado`, `P0481` → `ya_cliente` (por identidad, con `lead_id` y reingreso en la misma transacción) o `rechazado` (veredicto íntegro), `P0429` → `rechazado` (`no_contactar`/identidad). Todo lo demás sube tal cual. Con OFF = el INSERT de hoy.
**Edge.** Una llamada por fila (`rpc importar_lead_fn`), sin bandera ni reingreso aparte; `clasificarRespuestaPuerta` conserva los textos de la hoja; respuesta inesperada = temporal. Deploy: servidor primero, edge después (ventana muerta, versión anterior a mano).
**Oráculo** `oraculo-f2b-d4.sh` (30): autorización, paridad fila a fila OFF/ON contra el INSERT directo, reingreso, candados.
