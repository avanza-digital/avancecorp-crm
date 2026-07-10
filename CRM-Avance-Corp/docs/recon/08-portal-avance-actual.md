# Informe técnico — Estado ACTUAL del portal de Avance Corp (lado destino de la integración)

Raíz analizada: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop` (READ-ONLY respetado; solo lecturas y SQL de solo lectura contra el proyecto Supabase `dctqcbznekcyxhjujuci`).

## 0. Resumen ejecutivo

- El portal `miavance.com` es un **portal de inversiones para el CLIENTE FINAL + panel admin interno**, NO un CRM. Stack: HTML/CSS/**JS vanilla ES Modules sin build** + **Supabase Pro** (Postgres/Auth/Storage/Edge Functions Deno) + Hostinger (deploy vía MCP) + PWA/Web Push/Resend (`BASE DE CONOCIMINETO/AVANCECORP/Arquitectura del portal.md:10-15`).
- BD real verificada en vivo: **9 tablas en `public`, todas con RLS ON**. `clientes_preregistro` **NO EXISTE** (0 tablas `%preregistro%` en `information_schema`, 0 referencias en el repo). No hay embrión de pipeline comercial.
- Roles reales en prod (conteo en vivo): `cliente`=127, `analista`=18, `admin`=1, `superadmin`=1, `directorio`=1 (148 perfiles, todos activos). 138 contratos, 1.410 cuotas. Escala actual ≪ objetivo de ~5.000 clientes.
- La **categorización nuevo/renovación/upgrade YA ESTÁ IMPLEMENTADA en prod** (columna `contratos.categoria`, 113/138 contratos clasificados), aunque la nota del vault (`Categorización de inversiones - Nuevo Renovación Upgrade.md:3`) todavía dice "pendiente de implementar" — el plan ejecutado está en `docs/superpowers/plans/2026-06-13-categoria-inversiones.md`.

## 1. Base de datos real (verificada con `list_tables` verbose + SQL en vivo)

Naming: **español, snake_case, valores CHECK en ascii/minúscula** — coincide exactamente con la restricción de diseño del CRM destino.

### 1.1 `perfiles` (148 filas, RLS ON) — usuarios de TODOS los roles
- `id uuid PK` → FK `auth.users.id` (ON DELETE CASCADE según vault `Arquitectura del portal.md:20`).
- `rol text default 'cliente'` con CHECK textual: `rol = ANY (ARRAY['cliente','analista','admin','superadmin','directorio'])`.
- `activo boolean default true` → **soft-delete ya es el patrón del portal**.
- Identidad: `nombre_completo`, `apellidos`, `nombres` (separados desde 2026-06-09), `dni text UNIQUE`, `correo UNIQUE`, `telefono`.
- Trazabilidad: `creado_por uuid` (FK self), `creado_en`, `actualizado_en`.
- Cartera: `asesor_perfil_id uuid` FK self (**el asesor de un cliente es un analista** — fusión asesor→analista) + `asesor_id` FK a `asesores` (LEGACY, en eliminación).
- Datos del analista visto como asesor: `whatsapp`, `cargo`.
- Bancarios PEN: `banco`, `numero_cuenta`, `tipo_cuenta` CHECK `ahorros|corriente`, `cci` CHECK `^[0-9]{20}$`, `titular_distinto`, `beneficiario_nombre`, `beneficiario_dni`; **espejo USD**: `banco_usd`, `numero_cuenta_usd`, `tipo_cuenta_usd`, `cci_usd`, `titular_distinto_usd`, `beneficiario_nombre_usd`, `beneficiario_dni_usd` (bimoneda por duplicación de columnas, no por tabla hija).
- Otros: `debe_cambiar_password` (clave temporal = DNI), `pwa_instalada_at`.

### 1.2 `contratos` (138 filas, RLS ON) — contrato de Asociación en Participación
- `numero_contrato text UNIQUE` (formato `2026-01-` + 6 dígitos transcritos, prefijo fijo del sistema; legacy `AC-AAAA-####` conservado — `Número de contrato.md:5-22`).
- `capital numeric` CHECK `>=100 AND <=100000000`; `moneda` CHECK `PEN|USD`; `tasa_anual numeric default 15.00` CHECK `>0 AND <=50`; `modalidad` CHECK `mensual|trimestral|semestral|anual`; `tipo_interes` CHECK `simple|compuesto`; `fecha_inicio`, `fecha_vencimiento` (date); `estado` CHECK `activo|vencido|renovado|retirado` default `activo`; `notas_internas`; `cliente_id`/`creado_por` FK perfiles.
- `categoria text` nullable CHECK `nuevo|renovacion|upgrade` (comentario en BD: "NULL = contrato antiguo sin clasificar"). **113/138 clasificados en prod.**

### 1.3 `cronograma_pagos` (1.410 filas, RLS ON) — cuotas
- `contrato_id`, `numero_cuota int`, `fecha_programada date`, `monto_programado numeric`, `estado` CHECK `pendiente|pagado|vencido`, `fecha_pago_real`, `monto_pagado`, `registrado_por`.
- `tipo` CHECK `cuota|retorno|devolucion` (comentario BD: cuota = interés periódico · retorno = capital al final · `devolucion` = intereses del compuesto al vencimiento; capital 7 días después — `Interés compuesto.md:11-14`).
- Sellos de idempotencia de notificación: `notif_pago_enviada_en`, `recordatorio_3d_enviado_en`.

### 1.4 Resto
- `documentos` (0 filas): `contrato_id`, `nombre`, `tipo` CHECK `contrato|estado_cuenta|otro`, `storage_path`, `subido_por`.
- `novedades` (70): `titulo`, `mensaje`, `destinatario_id` (NULL = broadcast a todos), `leido` (deprecado desde 2026-06-01), `enviado_por` (NULL = sistema), `imagen_url`.
- `novedades_leidas` (17): acuse por usuario (`novedad_id`, `usuario_id`, `leido_en`).
- `suscripciones_push` (131): Web Push (`endpoint`, `p256dh`, `auth`, `dispositivo`, `user_agent`, `activo`).
- `audit_log` (1.044): **genérico**: `tabla`, `operacion` CHECK `INSERT|UPDATE|DELETE`, `fila_id`, `usuario_id`, `ts`, `data_antes jsonb`, `data_despues jsonb`. Alimentado por trigger `log_audit_change` (SECURITY DEFINER) + `trg_audit_cronograma_pago` (solo UPDATE de `estado/monto_pagado/fecha_pago_real/registrado_por`, no la regeneración masiva — `Auditoría exhaustiva 2026-06-13.md:17`).
- `asesores` (10, LEGACY): catálogo sin login en eliminación (`Fusión asesor-analista.md:20-21`; script final `FUSION_asesor_analista_LIMPIEZA_FINAL.sql` en raíz del repo, aún sin correr).
- **`clientes_preregistro`: NO EXISTE** ni en BD ni en el repo (grep sin resultados). El encargo lo daba por existente: corregir esa premisa.

## 2. Roles: cómo se resuelven

- **Fuente única: `perfiles.rol`** (5 valores). Helpers SQL `SECURITY DEFINER`: `es_admin()`, `es_superadmin()`, `es_analista()`, `es_directorio()`, `mi_rol()` (verificados en `pg_proc`).
- **Enrutamiento frontend por rol** en `public_html/js/auth.js:84-92`: `cliente`→`/dashboard.html` · `analista`→`/admin/analista.html` (espacio acotado propio) · `directorio`→`/admin/directorio.html` (cockpit solo lectura) · `admin|superadmin`→`/admin/dashboard.html`. Guards: `verificarSesion()` (auth.js:152), `verificarAdmin()` (auth.js:207, expulsa al analista a su pantalla en :235), `verificarAnalista()` (auth.js:253), `verificarDirectorio()` (referida en vault Rol Directorio).
- **Semántica de cada rol**:
  - `cliente`: portal de solo consulta (contratos, cronograma, documentos, novedades). Primer ingreso con clave temporal = DNI → forzado a `reset-password.html` (`Clave temporal = DNI.md:8-12`).
  - `analista` (= asesor comercial, la figura más parecida a "vendedor"): alta de cliente + contrato, corrección **solo dentro de ventana anti-fraude de 5 h por registro**, no borra nada, no ve lo ajeno (`Rol Analista.md:10-23`). **Auto-asignación de cartera**: al crear un cliente queda como su asesor (`_supabase_functions/functions/crear-cliente/index.ts:127`: `asesor_perfil_id: perfil.rol === "analista" ? userRes.user.id : null`).
  - `admin`: gestiona todo el negocio vía `es_admin()`; NO puede crear otros admins ni directorio, ni tocar filas de admins/superadmins.
  - `superadmin`: único que crea admin/directorio, único DELETE de perfiles/contratos/novedades.
  - `directorio`: dueños (Kirk y Carlos), **cero policies RLS a su nombre**; todo por 4 RPCs `SECURITY DEFINER` que validan `es_directorio() OR es_admin()` por dentro (`Rol Directorio.md:14-16`).
- **Matriz de creación server-side** (`_supabase_functions/functions/crear-admin/index.ts:53-64`, transcripción literal del comentario): "superadmin: 'admin' (default), 'analista' o 'directorio' … admin normal: SOLO 'analista' (NO puede crear otros admins ni directorio → sin escalada)".

### Encaje con la jerarquía objetivo del CRM (vendedor → supervisor → gerencia → directorio)
- `analista` ≈ **vendedor** (ya tiene cartera propia vía `asesor_perfil_id`/`creado_por`, ranking por analista, alta acotada).
- **NO existe nivel `supervisor`** ni campo jerárquico (no hay `supervisor_id` en perfiles ni tabla de equipos). Es el hueco principal.
- `admin` ≈ **gerencia** (operación total). `superadmin` es rol técnico/de plataforma, queda por encima.
- `directorio` ≈ **directorio/auditoría** y ya está resuelto con el patrón más seguro del portal (RPC-only). Encaja directo.
- Si el CRM comparte `perfiles`, hay que **ampliar el CHECK de `rol`** (o mapear: vendedor=analista) y añadir la relación vendedor→supervisor.

## 3. RLS existente (dump real de `pg_policies`, 37 policies en `public`)

Patrones (todas sobre rol `authenticated`):
- **Aislamiento del cliente**: `contratos_select`: `cliente_id = auth.uid() OR es_admin()`; `cronograma_select` y `documentos_select` vía `EXISTS` contra `contratos.cliente_id = auth.uid()`; `perfiles_select`: `auth.uid() = id OR es_admin()`; `novedades_select`: `destinatario_id = auth.uid() OR destinatario_id IS NULL OR es_admin()` (broadcast); `suscripciones_push_*`: `cliente_id = auth.uid()`.
- **Analista (dueño de cartera + ventana)**: `perfiles_analista_select`: `es_analista() AND rol='cliente' AND (asesor_perfil_id = auth.uid() OR (asesor_perfil_id IS NULL AND creado_por = auth.uid()))`; `perfiles_analista_update` añade **`creado_en > (now() - '05:00:00'::interval)`** (ventana de 5 h en la propia policy); `contratos_analista_select`/`cronograma_analista_select` via JOIN al cliente asesorado. Sin policies de INSERT/DELETE para analista: escribe SOLO por RPC.
- **Admin**: `es_admin()` en INSERT/UPDATE de contratos, cronograma, documentos, novedades; `admin_crea_perfiles` INSERT con `with_check`: `es_superadmin() OR (es_admin() AND rol='cliente')`.
- **Solo superadmin**: DELETE de `perfiles` (`superadmin_elimina_perfiles`), `contratos` (`contratos_superadmin_elimina`), `novedades`; `audit_log` solo SELECT (admin y superadmin), **nadie escribe audit_log por RLS** (lo hace el trigger SECURITY DEFINER).
- **Directorio**: 0 policies lo nombran (verificado) — acceso exclusivamente vía RPC.
- **Antiescalada**: `perfiles_update` con `with_check` que impide a un no-superadmin tocar filas de rol ≥ admin; trigger `proteger_campos_inmutables` congela `id/creado_en/creado_por` y, para auto-update de no-admin, restaura desde OLD `activo/rol/asesor_id/asesor_perfil_id/cargo` (`Auditoría exhaustiva 2026-06-13.md:23`). Auditoría 2026-06-13: RLS verificada sana en las 9 tablas, sin auto-escalada posible (`Auditoría exhaustiva 2026-06-13.md:11`).

## 4. RPCs y triggers (dump real de `pg_proc`)

`SECURITY DEFINER` (revalidan rol por dentro — 14 según auditoría):
- Escritura de contratos: `crear_contrato(p_contrato jsonb, p_cronograma jsonb)` (atómica, valida categoría obligatoria), `actualizar_contrato(p_id, p_contrato, p_cronograma)` (regenera cronograma, bloquea si hay cuotas pagadas), `actualizar_numero_contrato(p_id, p_numero, p_notas, p_categoria)` (edición admin).
- Directorio: `metricas_directorio()`, `directorio_top_clientes()`, `directorio_morosidad()`, `directorio_ranking_analistas()` (agrupa por `perfiles.asesor_perfil_id`).
- Otros: `bandeja_actividad(p_limit, p_offset)` (feed de actividad de analistas para admin, con Realtime sobre `audit_log`), `obtener_mi_asesor()` (el cliente resuelve su asesor sin leer perfiles ajenos), `verificar_cron_secret(p_secret)` (compara contra Vault, solo `service_role`), helpers `es_*`/`mi_rol`, `log_audit_change()`.
- Sin SECURITY DEFINER (métricas admin bajo RLS): `dashboard_admin_metricas()`, `admin_pagos_metricas()`, `admin_pagos_resumen()`, `pagos_admin_metricas_globales()`, `pagos_admin_resumen_contratos(p_tab, p_busqueda, p_moneda, p_offset, p_limit)` (**paginada server-side** — único listado ya preparado para volumen), triggers `proteger_campos_inmutables()`, `set_actualizado_en()`, `normalizar_nombre_mayusculas()`/`normalizar_nombres_perfiles()` (norma: nombres en MAYÚSCULA).
- Extensiones: `pg_trgm` (buscador fuzzy), `pg_net` + `pg_cron` (cron → edge).

## 5. Edge Functions (9 en `_supabase_functions/functions/`, Deno + `service_role`)

Convención común: CORS allowlist `miavance.com`/`www` (`crear-admin/index.ts:4-7`), validación de identidad con `auth.getUser(token)` + lectura de `perfiles.rol/activo` con service_role, autorización EN EL SERVIDOR, errores JSON en español, rollback del `auth.user` si falla el insert de perfil (`crear-cliente/index.ts:131`).

1. **`crear-admin`** (134 líneas): crea admin/analista/directorio según la matriz del §2; clave opcional, si falta usa DNI `padStart(8,'0')` (index.ts:79).
2. **`crear-cliente`** (410): callers admin/superadmin/analista (index.ts:53); apellidos/nombres separados retrocompatible (index.ts:66-75); clave temporal = DNI + `debe_cambiar_password` (index.ts:83-96,124); **auto-asigna asesor si el caller es analista** (index.ts:127); email de bienvenida vía Resend no bloqueante con plantilla HTML institucional navy/dorado (index.ts:138-190, plantilla 223-410).
3. **`resetear-password`** (92): reseteo por admin.
4. **`eliminar-cliente`** (139): **hard-delete PERO** solo superadmin (index.ts:54), solo rol `cliente` (index.ts:76), y **bloqueado si tiene contratos** con mensaje "Desactívalo en vez de eliminarlo para conservar el historial" (index.ts:89-94) → la política soft-delete del destino ya está semi-institucionalizada.
5. **`importar-clientes`** (338): alta masiva Excel; `dry_run`, dedup contra BD case-insensitive, idempotente, lotes de 25 desde el front, sin correos (`Importador de clientes.md:10-15`).
6. **`enviar-comunicado`** (384): individual o masivo a clientes activos; personaliza con el asesor del equipo (`asesor_perfil_id` manda sobre legacy, index.ts:101-114); lotes de 10.
7. **`enviar-push`** (156): Web Push VAPID.
8. **`notificar-pagos`** (410): `verify_jwt:false` con **auth dual** — token admin O header `x-cron-secret` validado por `verificar_cron_secret` contra Vault (index.ts:131-151); eventos `pagado`/`recordatorio` (3 días antes, fecha calculada en zona `America/Lima`, index.ts:76-84); **claim atómico de idempotencia** (UPDATE condicionado `sello IS NULL` con RETURNING; corridas concurrentes no duplican — index.ts:194-214); 3 canales (novedad in-portal → Realtime, Web Push con limpieza de suscripciones 404/410, correo Resend); `dry_run`.
9. **`diagnostico-push`** (7): tombstone 410 (deuda cerrada de la auditoría 2026-06-13).

**Cron real (leído de `cron.job`)**: job `recordatorio-cuotas-3d`, schedule `0 14 * * *` (09:00 Lima), activo=true, dispara `net.http_post` a la edge con el secreto del Vault (`cron_notif_secret`).

## 6. Deploy, PWA y push existentes

- **Deploy**: desde 2026-06-10 vía **MCP de Hostinger** — ZIP de todo `public_html/` (excluyendo `CLAUDE.md`, `.git/`, `.claude/`, `.gitignore`, `.DS_Store`, artifacts `_*`, `graphify-out/`) → `hosting_deployStaticWebsite` a `miavance.com` (root `/home/u318796122/domains/miavance.com/public_html`) → verificación con curl de `service-worker.js` y spot-checks (`Deploy a Hostinger.md:5-13`). Requiere **bump de `CACHE_VERSION`** — actual: `'avance-v93'` (`public_html/service-worker.js:17`).
- **PWA**: `public_html/manifest.json` + `service-worker.js` con cache versionado; instalación medida en `perfiles.pwa_instalada_at`; guía de instalación en el email de bienvenida (`crear-cliente/index.ts:329-368`).
- **Push**: Web Push VAPID (claves en env de las edges, `notificar-pagos/index.ts:54-58`), suscripciones en `suscripciones_push` (131 filas), desactivación automática de endpoints muertos.
- **Realtime**: `novedades`/`novedades_leidas` y `audit_log` en la publicación `supabase_realtime`; el badge del cliente y la bandeja del admin son en vivo, filtrados por RLS del JWT suscrito (`Realtime de novedades.md:11-13`).
- **Auth extra**: recuperación de contraseña autoservicio vía SMTP de Supabase Auth configurado con Resend (`Recuperación de contraseña.md:11-16` + tabla de config :25-34). Pendiente conocido: HIBP/política de contraseña mínima (toggle manual de Miguel).

## 7. Frontend actual (para calibrar qué NO transfiere a React Native)

- Vanilla JS sin framework ni build; cache-busting por `?v=N` por módulo. Páginas cliente: `dashboard, inversion, documentos, novedades, mercados, beneficios, perfil, reset-password, index(login), instalar`. Admin: `dashboard, clientes, contratos, pagos, documentos, novedades, equipo, bandeja, analista, directorio` (+ espejo en `public_html/js/admin/`).
- Estética actual del portal: **navy `#0a1f4a`/`#0a0e1a` + dorado `#c8922a`/`#c9a96e`** (emails y cockpit del directorio) — OJO: el CRM destino pide navy `#111e3d` + azul `#2563eb` SIN dorado ni verde; la identidad del portal NO es la del CRM.
- Nada de este frontend es reutilizable como código en RN (es DOM/HTML); lo reutilizable es la **capa Supabase** (RLS, RPCs, edges) que es agnóstica de cliente, y las **reglas de negocio** (ventana 5h, clave=DNI, número de contrato, mayúsculas).

## 8. Solapes con un CRM (respuestas directas a las preguntas del encargo)

1. **¿`clientes_preregistro` ya es un embrión de pipeline?** NO — no existe (verificado en `information_schema` y grep del repo). El embrión de pipeline real es más débil: `perfiles.creado_por` + `asesor_perfil_id` + `contratos.categoria` (nuevo/renovación/upgrade) permiten reconstruir captación, pero no hay etapas de venta, leads ni seguimiento. Todo lo pre-contrato FALTA.
2. **¿Los roles chocan o encajan?** Encajan con 1 hueco: analista→vendedor (mapeo natural, con cartera y ranking ya operativos), admin→gerencia, directorio→directorio (patrón RPC-only listo), superadmin queda como rol plataforma. **Falta el nivel supervisor** y la relación jerárquica vendedor→supervisor (no hay campo ni policy que la exprese). El CHECK de `perfiles.rol` habría que ampliarlo si se comparte la tabla.
3. **¿`audit_log` sirve para el CRM?** SÍ, casi tal cual: es genérico (tabla/operación/antes/después jsonb), con trigger reutilizable (`log_audit_change`), lectura admin-only por RLS, feed paginado (`bandeja_actividad`) y Realtime ya montado. Para el CRM solo faltaría extender qué tablas lo disparan y una vista filtrada por supervisor.
4. **Riesgo de convivencia**: si el CRM RN usa el MISMO proyecto Supabase, las policies de analista ("solo clientes propios, ventana 5 h") aplicarían tal cual al vendedor — deseable — pero cualquier ampliación de roles/policies impacta al portal en producción (127 clientes reales). Las edges tienen CORS allowlist de `miavance.com`, irrelevante para RN nativo (no aplica CORS) pero relevante si hay build web de Expo.
5. **Escala**: hoy 127 clientes; para 5.000 solo `pagos_admin_resumen_contratos` está paginada server-side; los listados de clientes/contratos del admin habría que revisarlos (no verifiqué su paginación) y el CRM debe nacer paginado.
6. **Pendientes del portal que condicionan al CRM**: ciclo de vida de contratos (vencido/renovado/retirado — muerde oct-2026, primer vencimiento; hoy el estado existe en el CHECK pero sin flujo/job), limpieza final de `asesores`, HIBP.

## 9. Convenciones del portal que el CRM debe respetar (ya institucionalizadas)

- Español snake_case en TODO (tablas, columnas, RPCs, edges, mensajes de error).
- Soft-delete `activo=false`; hard-delete solo superadmin y solo sin historial financiero.
- Clave temporal = DNI (`padStart(8,'0')`) + `debe_cambiar_password` (decisión cerrada, NO tratar como riesgo — `Clave temporal = DNI.md:14-15`).
- Nombres en MAYÚSCULA (trigger BD) + `apellidos`/`nombres` separados, saludos por primer nombre de pila.
- Mutaciones privilegiadas SIEMPRE por edge/RPC `SECURITY DEFINER` que revalida rol server-side; `service_role` nunca en el cliente.
- Campos inmutables congelados por trigger (`id/creado_en/creado_por`).
- Fechas siempre calculadas en zona `America/Lima` (lección del [[Bug de fechas UTC]]).
- Reglas de trabajo con Miguel: no es desarrollador; SQL se muestra ANTES de aplicar; deploy verificado en vivo; máx. 3 reintentos (`Inicio.md:38-44`).
