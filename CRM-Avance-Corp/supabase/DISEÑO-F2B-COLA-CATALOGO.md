# F2.b — la cola del Catálogo F0 (Contrato-F2, parte 2) — diseño **v3** (04/09/2026)

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

## Entrega
Tres entregas, cada una = migraciones + reversa + oráculos + auditor-rls + Codex + ensayo en `banco-f7` + suite RLS + reversa ×2 + `!` de Miguel
(bandera OFF): **E1 = b1+b2**, **E2 = b3+b4** (con los dos OK de `public`), **E3 = b5**. Edges con la activación.
Decisiones que Miguel puede cambiar: offboarding (b2), OK a `public.crear_contrato` y trigger en `public.perfiles` (b3), alcance acotado de fusión (b5).

## Fuera de F2.b
Contrato-F3 (métrica por inversionista/mes; hasta entonces la fusión no toca cifras), F4 (`crm.inversiones` desde contratos), F5 (N inversiones,
`UNIQUE(lead_id)`, fusiones con dos leads/dos perfiles), activación de la bandera y front.
