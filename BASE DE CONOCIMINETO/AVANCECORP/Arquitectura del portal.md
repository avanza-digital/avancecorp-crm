---
tags: [arquitectura, referencia]
actualizado: 2026-06-01
---

# Arquitectura del portal

> Resumen orientativo. **Fuente de verdad:** `public_html/CLAUDE.md` (secciones §2–§8).

## Stack
- **Frontend:** HTML + CSS + **JavaScript vanilla (ES Modules)**. Sin framework, sin build step.
- **Backend:** **Supabase Pro** — PostgreSQL + Auth + Storage + Edge Functions (Deno). Project ref `dctqcbznekcyxhjujuci`.
- **Emails:** Resend (`info@miavance.com`). **Push:** Web Push (VAPID). **Tiempo real:** Supabase Realtime → ver [[Realtime de novedades]].
- **Hosting:** Hostinger (deploy manual). **PWA** (manifest + service worker).
- **Gráficos:** SVG vanilla custom. **Mercados:** TradingView. **Excel:** SheetJS (lazy).

## Base de datos — 9 tablas (schema `public`)
`perfiles` · `contratos` · `cronograma_pagos` · `documentos` · `novedades` · `novedades_leidas` · `suscripciones_push` · `audit_log` · ~~`asesores`~~ (en eliminación → ver [[Fusión asesor-analista]]).

- **`perfiles`**: usuarios con rol `cliente|analista|admin|superadmin`. FK `perfiles.id → auth.users.id ON DELETE CASCADE`. El rol **`analista`** (alta acotada de clientes+contratos, ventana de 5 h) → ver [[Rol Analista]]. El **asesor de un cliente es un analista** (`asesor_perfil_id`) → ver [[Fusión asesor-analista]].
- Relación central: `contratos → cronograma_pagos` (cuotas) → ver [[Interés compuesto]] y [[Notificaciones de pagos]].

## Seguridad — RLS
- **RLS activo en las 9 tablas.** El cliente solo ve/edita lo suyo; admin/superadmin gestionan vía `es_admin()`/`es_superadmin()`.
- Escalada de roles **cerrada**: cambiar un rol ≠ cliente exige `es_superadmin()`; un admin no puede tocar filas de otros admins/superadmins.
- **Mutaciones privilegiadas van por Edge Functions con `service_role`** (omiten RLS y revalidan rol en código). El `service_role` **solo vive en el servidor** (Deno env), nunca en el frontend — verificado 2026-06-01.

## Edge Functions (`_supabase_functions/functions/`)
`crear-cliente` · `crear-admin` · `resetear-password` · `eliminar-cliente` · `importar-clientes` ([[Importador de clientes]]) · `enviar-comunicado` · `enviar-push` · `notificar-pagos` ([[Notificaciones de pagos]]).

**Quién puede ELIMINAR un cliente (2026-08-17):** `admin` **y** `superadmin` activos (antes solo `superadmin`). El cambio se pidió para que Gloria — administradora del portal y única `admin` en producción — pueda depurar altas erróneas sin depender de AdminCorp. El blindaje que hace seguro el permiso no se tocó: el objetivo debe ser rol `cliente` (un admin **no** puede borrar a otro admin ni al superadmin), nadie puede borrarse a sí mismo, y **un cliente con contratos NO se elimina** (409 `HAS_CONTRACTS` → «desactívalo»). Tampoco se auto-propaga: crear un `admin` sigue siendo potestad exclusiva del superadmin (`crear-admin` lo revalida en el servidor). Ver [[Offboarding seguro del CRM (P04)]] para el resto del perímetro de Gloria.

## Notas relacionadas
[[Rol Analista]] · [[Fusión asesor-analista]] · [[Clave temporal = DNI]] · [[Bug de fechas UTC]] · [[Auditorías del portal]] · [[Inicio]]
