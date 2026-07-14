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

## Usuarios de prueba por rol — PENDIENTE (Miguel: "el servidor lo dejamos de último")

- El conector Supabase de claude.ai YA apunta a la cuenta correcta (org `fzxtxnkvslpcsscxqfbr`,
  proyecto `dctqcbznekcyxhjujuci`); el bloqueo de "cuenta equivocada" quedó resuelto el 2026-07-11.
- Al 2026-07-11 **aún no existen** usuarios reales del CRM en prod. F0 está aplicada, así que
  crear uno = Auth confirmado + `public.perfiles` activo (rol `comercial` para vendedores) +
  fila en `crm.equipo` (`rol_crm` activo). La RPC gerencia-gated de alta llega en F1; por ahora
  es SQL de superadmin.
- Emails sugeridos (plus-addressing, llegan al buzón real): `avancecorp26+crm-vendedor@gmail.com`, `+crm-supervisor`, `+crm-gerencia`, `+crm-directorio`.
- **Antes de que el frontend funcione contra prod**: exponer el esquema `crm` en Settings → API →
  Exposed schemas (`public, graphql_public, crm`). Sin eso, todo `schema('crm')` falla.
- Tras crearlos: probar login real de los 4 en crm.miavance.com.

## Ver las vistas SIN servidor: modo demo local

`npm run dev` en `CRM-Avance-Corp/app` → http://localhost:5173 → en el login, **"Explorar en modo demo"** → 4 botones (uno por rol). Datos ficticios en sessionStorage; no toca la BD.

- Gate: `DEMO_HABILITADO = import.meta.env.DEV && VITE_ENABLE_DEMO === 'true'` (`lib/config.ts`); el flag ya está en el `.env` local. Al ser `DEV`-only, **el demo no existe en el build de producción** (fail-closed, verificado en el deploy 2026-07-10).
- Los E2E de Playwright (`e2e/demo-roles.spec.ts`) recorren los 4 roles por esta misma vía.

## Notas relacionadas

[[Deuda técnica CRM fuera de DB 2026-07-10]] · [[Auditoría CRM 2026-07-10]] · [[Rol Directorio]] · [[Deploy a Hostinger]] · [[Inicio]]
