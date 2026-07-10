# Informe técnico — Edge Functions e integraciones del CRM VITANOVA (Clínica Álvarez)

Base analizada (READ-ONLY): `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova/` (en adelante `crm-vitanova/`).
Destino comparado: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/_supabase_functions/functions/` (en adelante `AVANCECORP/functions/`).

---

## 1. Edge Functions de VITANOVA (4 en repo + 1 desplegada sin fuente)

### 1.1 `admin-crear-usuario` — alta de supervisor/asesor, gerente-gated
Archivo: `crm-vitanova/supabase/functions/admin-crear-usuario/index.ts` (115 líneas).

**Qué hace:** crea un usuario (solo roles `supervisor` o `asesor`) de la clínica del gerente que llama: crea el auth user en GoTrue (`email_confirm: true`) + inserta la fila en `usuarios`; si el insert falla hace rollback borrando el auth user.

**Validación del llamador (server-side, no confía en el cliente):**
- Exige header `Authorization` (línea 17-18) y `verify_jwt` ON según `crm-vitanova/supabase/SCHEMA.md:334-337` y `crm-vitanova/supabase/migrations/MIGRACIONES.md:72`.
- Resuelve el JWT con el cliente admin: `admin.auth.getUser(token)` (línea 32) y luego consulta `usuarios` para confirmar rol (líneas 35-39):
  ```ts
  const { data: caller } = await admin.from('usuarios')
    .select('id, rol, clinica_id').eq('id', userData.user.id).maybeSingle();
  if (!caller || caller.rol !== 'gerente') {
    return json({ error: 'Solo el gerente puede crear usuarios' }, 403);
  }
  const clinicaId = caller.clinica_id; // SIEMPRE del gerente, nunca del body.
  ```
- **Anti-escalación:** `ROLES_PERMITIDOS = ['supervisor', 'asesor']` (línea 10) — prohíbe crear `gerente`. El `clinica_id` se fuerza del caller, jamás del body (línea 40).
- Valida que el `supervisor_id` de un asesor sea rol `supervisor` **de la misma clínica** (líneas 50-58).
- **Enforce de cuota por rol** (líneas 60-76): límites en `clinicas.configuracion.limites` (default 3 supervisores / 6 asesores), cuenta activos (`activo=true`) y responde 409 con `{quota: true}` si está lleno.

**Secretos:** solo `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (línea 28, auto-inyectados por Supabase). El service_role vive solo en la función.

**Password temporal:** si no viene en el body genera `'Vn' + crypto.randomUUID()...slice(0,16) + 'X7!'` (línea 80) y la devuelve como `tempPassword` en la respuesta (línea 109).

**Calidad:** alta. Rollback explícito con log del huérfano si el rollback mismo falla (líneas 103-107). Mensaje amable en email duplicado (líneas 85-88). Debilidades menores: (a) CORS `Access-Control-Allow-Origin: '*'` (línea 8) — el portal de Avance ya usa allowlist estricta (`AVANCECORP/functions/crear-admin/index.ts:4-17`); (b) TOCTOU en la cuota: dos requests concurrentes pueden pasar el conteo a la vez (sin lock/constraint); (c) la temp password viaja en el JSON de respuesta (aceptable sobre HTTPS, pero registrable en logs del cliente).

### 1.2 `admin-provisionar-clinica` — provisión de tenant, superadmin-gated
Archivo: `crm-vitanova/supabase/functions/admin-provisionar-clinica/index.ts` (74 líneas).

**Qué hace:** provisiona un tenant completo (clínica nueva del SaaS): crea el auth user del gerente y llama la RPC **atómica** `public.provisionar_clinica` (clínica + config default + SLAs/líneas/meta + fila gerente en una transacción, migración `crm-vitanova/supabase/migrations/20260625055459_provisionar_clinica_rpc.sql`). Si la RPC falla → compensación manual borrando el auth user (líneas 62-66).

**Validación del llamador:** superadmin del SaaS por claim de servidor, NO por tabla (líneas 33-35):
```ts
if (userData.user.app_metadata?.platform_role !== 'superadmin') {
  return json({ error: 'Solo el dueño del SaaS puede provisionar clínicas' }, 403);
}
```
`app_metadata` solo lo escribe el servidor (no editable por el usuario) — patrón correcto. Al gerente creado se le estampa `app_metadata: { platform_role: 'gerente' }` (línea 47).

**Validaciones dominio:** RUC peruano `^\d{11}$` (línea 39), email regex, nombre obligatorio.
**Secretos:** los mismos 2 auto-inyectados.
**Calidad:** alta; el comentario de cabecera documenta la única operación no-transaccional (el auth user vía GoTrue) y su compensación.

### 1.3 `whatsapp-enviar` — envío saliente por WhatsApp Cloud API
Archivo: `crm-vitanova/supabase/functions/whatsapp-enviar/index.ts` (51 líneas).

**Qué hace:** envía un mensaje de texto por la Cloud API de Meta y registra la actividad `whatsapp_enviado` en `actividades` con `mensaje_externo_id` (líneas 41-44).

**Validación del llamador — patrón DUAL-CLIENTE (la joya de esta función):**
1. Cliente con el **JWT del usuario** (`SUPABASE_ANON_KEY` + header Authorization reenviado, líneas 17-18): consulta el prospecto **a través de RLS** — si el asesor no puede verlo, RLS devuelve vacío y la función responde 403 (líneas 19-21). La autorización la decide la base, no código duplicado en la función.
2. Cliente **service_role** solo para lo que el usuario jamás debe leer: `whatsapp_config` (tabla con RLS `using(false)`, ver `crm-vitanova/supabase/SCHEMA.md:181-184`) y el token desde **Supabase Vault**: `admin.schema('vault').from('decrypted_secrets').select('decrypted_secret').eq('id', cfg.access_token_secret_id)` (líneas 29-31).

**Patrón "staged":** si la clínica no tiene `whatsapp_config` verificada + token en Vault, responde `503 {staged: true}` (líneas 26-28) — el código está desplegado y "dormido" hasta que Meta apruebe la verificación.

**Llamada a Meta:** `POST https://graph.facebook.com/v20.0/{phone_number_id}/messages` con `type: 'text'` (líneas 33-37); errores de Meta se devuelven como 502 con detalle.

**Calidad:** buena en autorización; carencias funcionales: (a) **solo envía `type: 'text'`** — NO implementa envío de plantillas (`plantillas_whatsapp` existe en BD pero ninguna función la usa); (b) **no verifica la ventana de 24h** (`conversaciones.ventana_vence_en`) antes de enviar — fuera de ventana Meta rechazará y el usuario verá un 502 crudo; (c) el resultado del insert en `actividades` se ignora (si falla, el mensaje salió pero no queda registrado); (d) sin límite de longitud de `texto`.

### 1.4 `whatsapp-webhook` — receptor de mensajes entrantes de Meta
Archivo: `crm-vitanova/supabase/functions/whatsapp-webhook/index.ts` (87 líneas).

**Qué hace:**
- **GET** = verificación del webhook de Meta (`hub.mode=subscribe` + `hub.verify_token` contra `WHATSAPP_WEBHOOK_VERIFY_TOKEN`, líneas 30-36) devolviendo `hub.challenge`.
- **POST** = mensajes entrantes: por cada `entry/change` con `field==='messages'` resuelve la clínica por `phone_number_id` → `whatsapp_config` (multi-tenant, líneas 46-49), verifica **firma HMAC SHA-256** (`X-Hub-Signature-256`) con el app secret de esa clínica leído de Vault (líneas 50-54), y procesa cada mensaje.
- `procesar()` (líneas 63-86): **idempotencia** por `mensaje_externo_id` (líneas 66-67); si el teléfono no matchea prospecto existente → **crea prospecto nuevo con round-robin** (`supabase.rpc('asignar_asesor_round_robin', ...)`, línea 72), línea de servicio default `categoria='consulta'`, `origen: 'whatsapp_inbound'`; inserta actividad `whatsapp_recibido`.

**Validación del llamador:** NO usa JWT (Meta no manda JWT) — la cabecera lo advierte explícitamente: *"al ir a producción, desactivar 'Verify JWT' en esta función"* (línea 5). La autenticidad se prueba por HMAC con **comparación en tiempo constante** (líneas 10-20):
```ts
if (expected.length !== signature.length) return false;
let diff = 0;
for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
return diff === 0;
```

**Secretos:** `WHATSAPP_WEBHOOK_VERIFY_TOKEN` (env, con **fallback débil hardcodeado** `'clinica-alvarez-verify'`, línea 8 — deuda), `SUPABASE_SERVICE_ROLE_KEY`, y el app secret por clínica en Vault (`whatsapp_config.app_secret_secret_id`).

**Normalización de teléfono Perú:** `normalizarTelefono()` (líneas 22-26) — strip no-dígitos, quita prefijo `51`, 9 dígitos → `+51XXXXXXXXX`. Misma lógica que la RPC SQL `normalizar_telefono` del intake.

**Calidad:** buena con 3 grietas: (a) la firma HMAC se verifica DENTRO del loop y solo si el `phone_number_id` matchea una config — un POST sin entries o con phone_number_id desconocido devuelve `200 OK` sin verificar firma (inofensivo pero desprolijo; lo correcto es verificar la firma antes de procesar nada); (b) el chequeo de idempotencia (`select` + `insert`) no es atómico ante reintentos concurrentes de Meta; (c) `procesar()` sin try/catch — una excepción tumba el batch entero con 500 (Meta reintenta, la idempotencia lo salva a medias).

### 1.5 `intake-lead` — desplegada pero SIN FUENTE en el repo (drift)
- NO existe carpeta en `crm-vitanova/supabase/functions/` (solo hay 4).
- Está documentada como desplegada: `crm-vitanova/supabase/SCHEMA.md:339` ("**`intake-lead`** — captación desde Google Sheet / Facebook Lead Ads → `crear_lead_entrante`") y `crm-vitanova/supabase/migrations/MIGRACIONES.md:71`.
- Su cliente es el Apps Script (ver §3) que manda `Authorization: Bearer ANON_KEY` + un `token: INTAKE_TOKEN` secreto en el body (`crm-vitanova/integraciones/google-sheets-leads.gs:15-18,54,63`) — es decir, valida un **shared secret propio** en vez de JWT.
- El trabajo pesado está en la RPC versionada `crear_lead_entrante` (`crm-vitanova/supabase/migrations/20260614071154_intake_lead_captacion.sql`): SECURITY DEFINER, **grant solo a `service_role`** (líneas 39-40), dedup por teléfono normalizado, mapeo `servicio → linea_servicio` con fallback a `consulta`, round-robin, consentimiento Ley 29733 estampado (`acepta_tratamiento_datos: true, canal_consentimiento: 'web'`), y el mensaje del lead como `nota_interna`.
- **Es el mismo tipo de drift que la auditoría de Avance encontró con `diagnostico-push`** (función ACTIVE sin fuente en repo — ver tombstone en `AVANCECORP/functions/diagnostico-push/index.ts:1-7`). Lección: versionar SIEMPRE la fuente de toda función desplegada.

---

## 2. Integración WhatsApp Cloud API — arquitectura completa

Fuentes: `crm-vitanova/GUIA-META-WHATSAPP.md` (83 líneas), `crm-vitanova/supabase/SCHEMA.md:160-184`, migración `crm-vitanova/supabase/migrations/20260614063630_whatsapp_bloque_3.sql`.

**Modelo:** API oficial (Cloud API / WhatsApp Business Platform), **no QR** (`GUIA-META-WHATSAPP.md:3`). Multi-tenant: 1 fila de `whatsapp_config` por clínica, ruteo entrante por `phone_number_id`.

**Piezas de datos:**
- `whatsapp_config` (PK `clinica_id`): `phone_number_id`, `waba_id`, `access_token_secret_id uuid`, `app_secret_secret_id uuid` — **los tokens viven en Supabase Vault, la tabla solo guarda los UUID del secreto**; RLS `whatsapp_config_sin_acceso` = SELECT `using(false)`: nadie la lee vía API, solo edge functions con service_role (`SCHEMA.md:181-184`).
- `conversaciones` (1 por prospecto, `prospecto_id` UNIQUE): `no_leidos`, `ultimo_entrante_en/saliente_en`, y **`ventana_vence_en`** = la ventana 24h de Meta, mantenida por trigger: `ventana_vence_en = case when new.tipo='whatsapp_recibido' then new.creada_en + interval '24 hours' ...` (`20260614063630_whatsapp_bloque_3.sql:64`).
- `plantillas_whatsapp`: `meta_template_name`, `categoria (marketing|utility|authentication)`, `estado_meta (pendiente|aprobada|rechazada)`, `variables text[]` (`SCHEMA.md:176-179`). **Solo modelo de datos: ninguna función envía plantillas todavía.**
- RPC demo `simular_whatsapp_entrante(text,text,text)` para modo demo sin Meta (`SCHEMA.md:316`).

**Trámite Meta (runbook completo en la guía):** número DEDICADO que deja de servir en la app normal (`GUIA-META-WHATSAPP.md:10-11`); Meta Business + **verificación del negocio con RUC/SUNAT que tarda 2–6 semanas** (líneas 23-26); app en developers.facebook.com → WABA; 4 credenciales: Phone Number ID, WABA ID, **token permanente vía "usuario del sistema"** con permisos `whatsapp_business_messaging` + `whatsapp_business_management`, y App Secret (líneas 39-47).

**Regla de ventana 24h (textual, `GUIA-META-WHATSAPP.md:50-51`):** "Regla de Meta: fuera de la ventana de **24h** desde el último mensaje del paciente, solo se puede escribir con **plantillas aprobadas**."

**Go-live:** token+app secret a Vault, IDs a `whatsapp_config`, desplegar las 2 functions (webhook **con Verify JWT desactivado**), configurar Callback URL + verify token + suscribir campo `messages` en Meta, y flag de front `WHATSAPP_LIVE: true` (líneas 56-66). **Costos:** Meta cobra por conversación, no por mensaje (líneas 74-77). **Estado actual:** todo "staged" en modo demo detrás del flag (líneas 79-82).

---

## 3. Integración Google Sheets / Facebook Lead Ads

Archivo: `crm-vitanova/integraciones/google-sheets-leads.gs` (78 líneas, Google Apps Script).

- Facebook Lead Ads vuelca a un Google Sheet; el script corre **cada 5 min** con trigger instalable (`instalarDisparador()`, líneas 75-78) y postea cada fila nueva a `POST .../functions/v1/intake-lead` (línea 15).
- **Mapeo de columnas flexible por aproximación de encabezados** (objeto `MAP`, líneas 23-30: variantes es/en de nombre, teléfono, email, servicio, distrito, mensaje) — robusto ante cambios del formulario del ad.
- **Idempotencia en la hoja:** marca la columna "Estado CRM" con `✓ fecha` o el error (líneas 43-44, 67); las filas marcadas se saltan.
- **Secretos:** `ANON_KEY` (pública) + `INTAKE_TOKEN` (shared secret, placeholder "NO los subas a git", líneas 17-18).
- Calidad: correcto y simple; el secreto pegado a mano en Apps Script es lo esperable en ese runtime.

---

## 4. QA harness (`crm-vitanova/qa/`)

### 4.1 `qa-vite.mjs` (305 líneas) — E2E Playwright por rol, READ-ONLY, apto CI
- Login real con 3 usuarios demo (gerente/supervisor/asesor, password `demo1234`, líneas 61-86), recorre TODAS las pantallas del NAV (líneas 48-58), captura `console.error` + `pageerror` con filtro de ruido (líneas 97-100, 123-125), screenshot por pantalla, y **exit code ≠ 0 si algo falla** (línea 305) — CI-ready.
- **Matriz de expectativas por rol derivada de `roles.ts`** (líneas 61-86): `verConfig`, `verEquipo`, `filtrarPorAsesor`, `reasignar`, `cruceInteligencia` — asevera tanto la PRESENCIA para staff como la AUSENCIA para asesor (gating positivo y negativo, p.ej. líneas 151-158, 192-223).
- Regla dura documentada: solo navega/lee/asevera; el único form que envía es el login, porque **el Supabase es compartido con producción** (líneas 9-11, README `crm-vitanova/qa/README-qa-vite.md:8-11`).
- Detalle fino: sabe que Radix desmonta tabs inactivas y activa la tab antes de buscar el contenido (líneas 211-217).
- **Limitación para Avance:** los selectores son DOM web (`aside nav`, `getByRole('tab')`, `#email`) — inservibles tal cual contra React Native nativo; el PATRÓN (matriz rol×capacidad, aserciones simétricas, captura de errores, exit code) es lo transferible. En RN: Maestro/Detox, o Playwright solo si se sirve Expo Web.

### 4.2 `qa-reportes.mjs` (231 líneas) — harness viejo, clavado a producción
URL hardcodeada `https://coral-lark-647471.hostingersite.com/` (línea 17), aserciones específicas del Centro de Reportes de la clínica (tabs Resumen/Embudo/Equipo/Dinero/Velocidad/Origen, nombres de asesores demo). Superseded por `qa-vite.mjs`. Sin valor para Avance más allá de lo que ya cubre 4.1.

### 4.3 `aislamiento-tenant.sql` (64 líneas) — auditoría server-side de RLS, la pieza más valiosa del QA
- DO block que: crea un tenant B sintético con datos en TODAS las tablas tenant-scoped (líneas 23-34), **impersona a un usuario real de A con claims JWT fieles** (`set_config('request.jwt.claims', json_build_object('sub',...,'clinica_id',...,'rol','gerente'))`, líneas 42-46), verifica que A no ve NINGUNA fila de B iterando **dinámicamente todas las tablas `public` con columna `clinica_id` y RLS activo** vía `pg_class`/`pg_attribute` (líneas 49-54), y detecta **tablas sin RLS = fuga total** (líneas 36-40).
- Termina SIEMPRE en `RAISE exception` → **ROLLBACK total, no persiste nada** (líneas 61-63); resultado esperado: `OK_AISLAMIENTO ... (rollback)`.
- Advertencia operativa clave (líneas 6-8): correr con `execute_sql`/psql, **NO el SQL Editor del dashboard** (corre como postgres con BYPASSRLS → falsos verdes).
- Para Avance: cambiar la dimensión de aislamiento de "clínica A vs B" a "vendedor A no ve clientes del vendedor B / supervisor solo ve su equipo"; el esqueleto (impersonación por claims + iteración dinámica de tablas + rollback) transfiere entero.

---

## 5. Comparación con las edge functions existentes de Avance Corp

Avance ya tiene 9 functions (`AVANCECORP/functions/`): `crear-admin`, `crear-cliente`, `eliminar-cliente`, `enviar-comunicado`, `enviar-push`, `importar-clientes`, `notificar-pagos`, `resetear-password`, `diagnostico-push` (tombstone 410).

Convenciones destino que YA superan a VITANOVA (mantenerlas en el CRM):
- **CORS allowlist estricta** con `Vary: Origin` (`AVANCECORP/functions/crear-admin/index.ts:4-17`) vs `'*'` de VITANOVA. Nota RN: el fetch nativo de React Native no manda `Origin` ni aplica CORS — la allowlist solo importa si hay build Expo Web; no bloquea al cliente móvil.
- **Auth custom con `verify_jwt: FALSE`** documentada en cabecera + secreto de cron por header `x-cron-secret` verificado contra Vault (`AVANCECORP/functions/notificar-pagos/index.ts:1-27`).
- **Idempotencia por sellos en fila** (`notif_pago_enviada_en`) + **`dry_run`** (ídem, líneas 18-24) — VITANOVA no tiene dry_run en ninguna función.
- Imports `jsr:` (más moderno que el `npm:`/`esm.sh` mixto).

Lo que VITANOVA aporta y Avance NO tiene aún: gating por rol leído de tabla con anti-escalación + cuotas (crear-admin de Avance gates superadmin, pero el patrón cuota/jerarquía de VITANOVA aplica al alta de vendedores por supervisores), patrón dual-cliente RLS, Vault por-integración con tabla config `using(false)`, webhook HMAC de terceros, y el harness QA por rol.

---

## 6. Hallazgos transversales

1. **Las edge functions son la capa que MENOS cambia con React Native**: son backend Deno puro; la premisa RN afecta al QA harness (Playwright→Maestro/Detox) y al push (Web Push VAPID de `notificar-pagos` NO funciona en RN → Expo Push/FCM/APNs), no a las functions en sí.
2. **Patrón de seguridad consistente y correcto en VITANOVA**: JWT resuelto server-side → rol desde tabla o `app_metadata` → tenant forzado del caller → service_role solo dentro de la función. Es el mismo espíritu que Avance ya usa; se fusionan bien.
3. **Drift de despliegue** (`intake-lead` sin fuente) es un anti-patrón repetido en ambos proyectos (cf. `diagnostico-push`); el CRM nuevo debe nacer con regla "toda función desplegada tiene fuente versionada".
4. **La integración WhatsApp está a medio hacer incluso en VITANOVA**: falta envío de plantillas y chequeo de ventana 24h. Para Avance (recordatorios de pago a inversores = mensajes INICIADOS por la empresa) las plantillas `utility` no son opcionales: son el caso de uso principal, porque casi nunca habrá ventana 24h abierta.
5. Jerarquía: VITANOVA gatea 3 niveles (gerente>supervisor>asesor) + superadmin de plataforma; Avance necesita 4 (vendedor→supervisor→gerencia→directorio/auditoría) — el patrón de `ROLES_PERMITIDOS` + validación de jefe-de-la-misma-unidad escala directo, agregando el nivel directorio como read-only (Avance ya tiene precedente: rol directorio en su edge `crear-admin`, commit `0ce497b`).
