---
tags: [crm, roles, auth, acceso]
actualizado: 2026-07-10
---

# Acceso y roles del CRM (crm.miavance.com)

El CRM tiene **4 roles** — fuente única en `CRM-Avance-Corp/app/src/lib/roles.ts` (`ROLES`, `CAPS`, `can()`): **vendedor** (solo su cartera), **supervisor** (equipo, filtra/reasigna/reparte), **gerencia** (ve todo, único que edita configuración), **directorio** (ve todo en solo-lectura absoluta). `can()` es UX; la seguridad real es la RLS del esquema `crm`. Regla de oro: lo que `can()` oculta, la RLS también lo niega. Rol nulo/desconocido degrada a solo-lectura.

## Cómo se resuelve el acceso en producción (`resolverRol`, `auth.tsx`)

1. **¿Enrolado en `crm.equipo`?** Fila con `perfil_id = auth.uid()`, `rol_crm` válido y `activo = true`. Además exige `public.perfiles.activo = true` (cuenta del portal viva). Una fila CRM **inactiva es revocación explícita**: no cae al fallback.
2. **Fallback lector global:** si no hay fila en `crm.equipo` pero `perfiles.rol` ∈ {`directorio`, `admin`, `superadmin`} y activo → entra como **directorio** (solo lectura).
3. Nada de lo anterior → fase `no_enrolado` (autentica pero no pasa).

**Para crear un usuario real por rol hacen falta 3 piezas:** cuenta en Auth (email+clave confirmados) + fila en `public.perfiles` (activo) + fila en `crm.equipo` (`rol_crm`, activo). Solo se puede con acceso admin al proyecto `dctqcbznekcyxhjujuci`.

## Rol de portal `comercial` (desde F0, 2026-07-11)

La fuerza de ventas del CRM se enrola con el rol de portal **`comercial`** (añadido a
`perfiles.rol` en la migración `20260711000001`). Es NEUTRO deny-by-default: NO hereda las
policies del portal, así que un comercial no ve perfiles/contratos/banca de clientes — solo su
propia fila. Los analistas reales del portal PUEDEN enrolarse en `crm.equipo` conservando su
rol analista (mantienen sus poderes de portal). Ver [[F0 Cimientos BD del CRM]].

## Usuarios de prueba por rol — CREADOS, EXPUESTOS Y LOGIN VERIFICADO EN PROD 2026-07-15

- El conector Supabase de claude.ai apunta a la cuenta correcta (org `fzxtxnkvslpcsscxqfbr`,
  proyecto `dctqcbznekcyxhjujuci`); el bloqueo de "cuenta equivocada" quedó resuelto el 2026-07-11.
- **Creados 3 usuarios reales el 2026-07-15** (SQL de superadmin vía MCP, bloque `DO` transaccional
  — la RPC gerencia-gated de alta llega en F1). Cada uno = fila en `auth.users` (con `crypt`/bcrypt,
  `email_confirmed_at` seteado) + `auth.identities` (provider email) + `public.perfiles`
  (rol **`comercial`** neutro, activo) + `crm.equipo` (`rol_crm`, activo). DNI ficticios `9000000x`
  (staff, no chocan con clientes). Verificado en prod: `password_valida=t`, email confirmado,
  identidad, perfil activo y equipo activo en los 3.
  - **Gerente** — `avancecorp26+crm-gerente@gmail.com` · `Avance.Gerente2026` · `rol_crm=gerencia`
  - **Supervisor** — `avancecorp26+crm-supervisor@gmail.com` · `Avance.Supervisor2026` · `rol_crm=supervisor`
  - **Analista** — `avancecorp26+crm-analista@gmail.com` · `Avance.Analista2026` · `rol_crm=vendedor`
    (⚠️ "analista" de Miguel = **`vendedor`** en el CRM; la UI dirá "Vendedor")
  - Jerarquía armada: el **vendedor cuelga del supervisor** (`crm.equipo.supervisor_id`); gerencia ve todo.
    `rol_crm` solo admite `vendedor|supervisor|gerencia` (directorio entra por fallback, no por esta tabla).
- **Esquema `crm` EXPUESTO en la API (2026-07-15):** Miguel lo agregó en Settings → API → Exposed
  schemas (`public, graphql_public, crm`; `private` JAMÁS se expone). **OJO con "Exposed tables/functions":**
  las tablas/funciones `crm.*` salen en NARANJA/⚠️ ("no expuestas") porque F0 dio los grants SOLO a
  `authenticated` (NO a `anon`) — es CORRECTO y deliberado (CRM cerrado al público). **NO marcarlas en el
  dashboard** (les daría acceso `anon` y rompería la separación). Verificado: con sesión, `authenticated`
  lee `crm.equipo`/`perfiles` sin problema; el ⚠️ es cosmético.

- ⚠️ **BUG al crear usuarios de Auth por SQL — RESUELTO 2026-07-15 (aprendizaje clave):** los 3 usuarios
  se crearon con `insert into auth.users` SIN setear las columnas de token, que quedaron en **NULL**
  (`confirmation_token`, `recovery_token`, `email_change`, `email_change_token_new`). GoTrue las escanea
  como `text` y con NULL el login revienta con **HTTP 500 `"Database error querying schema"`** → el frontend
  muestra el genérico *"No pudimos iniciar sesión"*. **La clave/correo estaban BIEN.** Fix: `UPDATE auth.users
  SET <cada_token> = coalesce(<token>, '') WHERE ...`. **REGLA para futuras altas por SQL:** setear TODAS
  las columnas `*_token`/`*_change` a `''` (nunca NULL). Mejor aún: crear por la Admin API / Dashboard
  (Add user) o por una edge con `auth.admin.createUser`, que ya las inicializa bien.

- **LOGIN VERIFICADO END-TO-END (2026-07-15), contra el servidor real (curl a `/auth/v1/token`):**
  los 3 → **HTTP 200 con `access_token`**; con la sesión del gerente, `GET /rest/v1/equipo` (Accept-Profile: crm)
  → 200 y ve las 3 filas del equipo; self-read de `perfiles` → 200 (`rol=comercial, activo=true`).
  Flujo `resolverRol` completo confirmado. **Falta solo la prueba visual de Miguel en crm.miavance.com.**

## Ver las vistas SIN servidor: modo demo local

`npm run dev` en `CRM-Avance-Corp/app` → http://localhost:5173 → en el login, **"Explorar en modo demo"** → 4 botones (uno por rol). Datos ficticios en sessionStorage; no toca la BD.

- Gate: `DEMO_HABILITADO = import.meta.env.DEV && VITE_ENABLE_DEMO === 'true'` (`lib/config.ts`); el flag ya está en el `.env` local. Al ser `DEV`-only, **el demo no existe en el build de producción** (fail-closed, verificado en el deploy 2026-07-10).
- Los E2E de Playwright (`e2e/demo-roles.spec.ts`) recorren los 4 roles por esta misma vía.

## Equipo comercial REAL enrolado en crm.equipo (2026-07-15)

Bloque 1 de "CRM en producción con datos reales" (P-055). Miguel definió el organigrama; se enrolaron **20 personas reales** — asesores del portal que CONSERVAN su rol de portal `analista` (solo se les SUMA el rol CRM vía fila en `crm.equipo`). Decisión: mapear los asesores del portal.
- **Gerencia:** CARLOS VALLES (`carlosvalles@gmail.com`; ya era `directorio` en el portal).
- **Supervisores:** CARMEN JARAMILLO, JORGE MARZANO.
- **Vendedores (17):** Carmen→8 (Linda, Nayra, Lisseth, Pierina, Noelia, Antonella, Adelayda, Guillermo); Jorge→9 (Astrid, Fiorella, Miguel Briceño, Rosa, Grecia, Kelly, Vladimir, Merlys, Ivett).
- Enrolamiento por `insert ... select` resolviendo perfil por correo, **idempotente** (`ON CONFLICT (perfil_id) DO NOTHING`); gerencia+supervisores primero, luego vendedores (FK `supervisor_id`→`crm.equipo`). Verificado: 8 con Carmen, 9 con Jorge, jerarquía correcta.
- **Kirk Sánchez (gerencia) — PENDIENTE:** su única cuenta (`kirk@cacmascapital.com`) es de CLIENTE-inversionista (contrato demo US$100k); para NO mezclar sombreros (regla: separar CRM/portal), Miguel eligió que Kirk use una **cuenta de dueño APARTE** para el CRM (por definir/crear). NO enrolado aún.
- **Cuentas `+crm-*` (… DEMO) siguen en `crm.equipo`:** ahora son cuentas de **QA** (tenemos sus claves) para probar el CRM real con cada rol; **retirar antes del go-live**.
- `rol_crm` CHECK = `vendedor|supervisor|gerencia` (directorio entra por fallback lector-global, no por esta tabla). gerencia edita config; supervisor ve su equipo (recursivo); vendedor su cartera.

## Notas relacionadas

[[Deuda técnica CRM fuera de DB 2026-07-10]] · [[Auditoría CRM 2026-07-10]] · [[Rol Directorio]] · [[Deploy a Hostinger]] · [[Inicio]]
