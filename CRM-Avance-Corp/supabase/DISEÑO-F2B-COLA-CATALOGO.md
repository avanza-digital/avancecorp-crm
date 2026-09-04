# F2.b — la cola del Catálogo F0 (Contrato-F2, parte 2) — diseño **v2** (04/09/2026)

**v1 → NO-GO de Codex (17 bloqueantes).** v2 incorpora cada arreglo (marcados `[Cx-n]`) y declara lo que queda FUERA con nombre.
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

## Sub-lote b3 — El cliente creado sin lead es una persona, atómico `[Cx-8, Cx-9, Cx-10, Cx-11]`
**Cómo:**
- Una sola RPC SQL para el alta: `crm.alta_cliente_identidad_fn(p_paso, p_payload jsonb) returns jsonb` (DEFINER; `authenticated` con gate
  `private.puede_gestionar_contratos_crm()` para `crear-cliente`, y `service_role` para `importar-clientes`), con **tres pasos** en el mismo
  contrato de saga y clave durable en `crm.multiempresa_idempotencia` (`clave='alta_cliente:'||tipo||':'||norm`, `tipo='alta_cliente'`,
  `resultado={auth_user_id, correo, hash_payload, estado, por}`):
  1. `reclamar`: validación pura (con bandera ON el documento es OBLIGATORIO aunque venga contraseña `[Cx-8]`) → documento → resolver(verificado,
     fuente `alta_cliente`) → identidad `FOR UPDATE` → si tiene perfil activo → `P0409`; si hay reclamo vivo (10 min) de OTRO actor → `P0409`
     «alta en curso»; si es el mismo actor y ya tiene `auth_user_id` sin perfil → devuelve `{reanudar:true, auth_user_id}` → guarda el reclamo.
  2. `registrar_auth`: escribe `auth_user_id` en el reclamo (el edge lo llama justo después de `createUser`).
  3. `enlazar`: documento → identidad `FOR UPDATE` → perfil `FOR SHARE` (revalida documento) → `perfil_id`, tramo de responsable SOLO si no hay
     tramo abierto (`asesor_perfil_id`, `motivo='alta_cliente'`) `[Cx-9]`, propagación de veto, cierra el reclamo. Idempotente.
  El edge: `reclamar` → (`createUser` o reutilizar `auth_user_id`) → `registrar_auth` → insert perfil → `enlazar`. Un Auth hallado SOLO por
  email nunca se adopta `[Cx-13]`: si `createUser` dice «ya registrado» y el reclamo no trae `auth_user_id` → 409 «revisión de Gerencia».
  La compensación `deleteUser` existente se COMPRUEBA y se reporta. Con bandera OFF: el edge no llama a nada nuevo (rama explícita).
- `public.crear_contrato` — **requiere OK de Miguel (tabla/función `public`)**: parche por ancla; llama `private.asegurar_identidad_perfil(v_cliente_id)`
  ANTES de su `for share` `[Cx-11]`: lee documento sin lock → documento → identidad → perfil `FOR SHARE` con revalidación → enlaza si falta;
  sin documento válido → `raise` de negocio (fail-closed). No escribe `crm.inversiones` (F4).
- Documento del perfil `[Cx-10]` — **requiere OK de Miguel (`public.perfiles`)**: trigger `BEFORE UPDATE OF dni, tipo_documento` en
  `public.perfiles`: con bandera ON, si el perfil está enlazado y no hay válvula → `P0409` «usar corrección de documento». Y
  `crm.actualizar_cliente_gerencia[_con_domicilio]` deja de aceptar cambios de documento con bandera ON (los redirige a b5). El front se adapta en la activación.
- `eliminar-cliente` (edge, ausente del catálogo): con perfil enlazado la FK ya impide el DELETE (23503) → el edge devuelve 409 con diagnóstico
  «cliente con identidad: baja lógica». No se desenlaza.
- Colaboradores (`registrar_*`, `crm-usuarios`): FUERA (rol `comercial`, no inversionistas).
**Oráculos:** alta → identidad + perfil + tramo; dos altas concurrentes mismo documento → una gana antes de Auth, la otra `P0409`; muerte tras
`createUser` → reanudación por `auth_user_id`; coop→Avance → misma identidad, tramo conservado; contrato sin enlace → enlaza; OFF → nada.

## Sub-lote b4 — La conversión Avance reserva por la persona real y no deja huérfanos `[Cx-12, Cx-13]`
**Cómo:**
- `crm.conversion_reservas` gana columnas ADITIVAS: `tipo_documento`, `documento_normalizado`, `hash_payload`, `auth_user_id`, `correo`.
- Nueva sobrecarga `crm.reservar_conversion_lead(p_lead_id, p_tipo_documento, p_documento, p_hash_payload)`: con bandera ON: validación pura →
  documento → `inversionista_por_documento` → si existe: `FOR UPDATE` y revalidar: sin veto, sin OTRO lead (cualquier estado), perfil enlazado
  compatible → lead `FOR UPDATE` → si existe reserva viva de OTRO lead con el MISMO documento → `P0409` → upsert de la reserva con el documento.
  Es el preflight: revalida DESPUÉS de esperar el advisory. La antigua de 1 argumento queda para bandera OFF (paridad).
- `crm.convertir_lead_externo` (transformación mínima): tras el advisory documental, si existe reserva viva de otro lead con ese documento →
  `P0409` «conversión Avance en curso para esta persona» `[Cx-12]`. Cierra coop↔Avance entre leads distintos en ambos sentidos.
- `crm.registrar_auth_conversion_fn(p_lead_id, p_auth_user_id, p_correo)`: el edge la llama tras `createUser`. Reintento: `reservar` devuelve
  `auth_user_id` si está y no existe perfil → el edge reutiliza ese Auth (crea el perfil con ese `id`). Pasado `vence_absoluto_en`, solo
  **Gerencia** puede retomar una reserva sellada con `auth_user_id` sin perfil (`crm.retomar_conversion_gerencia_fn`) `[Cx-13]`. Nunca se adopta
  un Auth hallado solo por email.
- El edge `crm-convertir-lead`: rama explícita por bandera; con ON usa la sobrecarga nueva y `registrar_auth`; con OFF idéntico a hoy.
**Oráculos:** coop(A)↔Avance(B) misma persona en los dos órdenes → una gana, la otra `P0409` ANTES de Auth; Auth sembrado sin perfil con reserva →
reintento lo reutiliza; Auth ajeno solo por email → 409; OFF → idéntico.

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
