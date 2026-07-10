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

## Usuarios de prueba por rol — PENDIENTE (Miguel: "el servidor lo dejamos de último")

- Al 2026-07-10 **no existen** usuarios de prueba del CRM en prod.
- Bloqueo operativo: el **conector Supabase de claude.ai está autenticado en otra cuenta** (solo ve el proyecto "BELYSH" `ivacfijeupgcxmzdsqnk`); el proyecto real `dctqcbznekcyxhjujuci` da "permission denied". Reconectar el conector a la cuenta correcta antes de retomar.
- Emails sugeridos (plus-addressing, llegan al buzón real): `avancecorp26+crm-vendedor@gmail.com`, `+crm-supervisor`, `+crm-gerencia`, `+crm-directorio`.
- Tras crearlos: probar login real de los 4 en crm.miavance.com.

## Ver las vistas SIN servidor: modo demo local

`npm run dev` en `CRM-Avance-Corp/app` → http://localhost:5173 → en el login, **"Explorar en modo demo"** → 4 botones (uno por rol). Datos ficticios en sessionStorage; no toca la BD.

- Gate: `DEMO_HABILITADO = import.meta.env.DEV && VITE_ENABLE_DEMO === 'true'` (`lib/config.ts`); el flag ya está en el `.env` local. Al ser `DEV`-only, **el demo no existe en el build de producción** (fail-closed, verificado en el deploy 2026-07-10).
- Los E2E de Playwright (`e2e/demo-roles.spec.ts`) recorren los 4 roles por esta misma vía.

## Notas relacionadas

[[Deuda técnica CRM fuera de DB 2026-07-10]] · [[Auditoría CRM 2026-07-10]] · [[Rol Directorio]] · [[Deploy a Hostinger]] · [[Inicio]]
