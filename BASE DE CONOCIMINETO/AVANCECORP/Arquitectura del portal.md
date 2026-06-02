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
`perfiles` · `asesores` · `contratos` · `cronograma_pagos` · `documentos` · `novedades` · `novedades_leidas` · `suscripciones_push` · `audit_log`.

- **`perfiles`**: usuarios con rol `cliente|admin|superadmin`. FK `perfiles.id → auth.users.id ON DELETE CASCADE`.
- Relación central: `contratos → cronograma_pagos` (cuotas) → ver [[Interés compuesto]] y [[Notificaciones de pagos]].

## Seguridad — RLS
- **RLS activo en las 9 tablas.** El cliente solo ve/edita lo suyo; admin/superadmin gestionan vía `es_admin()`/`es_superadmin()`.
- Escalada de roles **cerrada**: cambiar un rol ≠ cliente exige `es_superadmin()`; un admin no puede tocar filas de otros admins/superadmins.
- **Mutaciones privilegiadas van por Edge Functions con `service_role`** (omiten RLS y revalidan rol en código). El `service_role` **solo vive en el servidor** (Deno env), nunca en el frontend — verificado 2026-06-01.

## Edge Functions (`_supabase_functions/functions/`)
`crear-cliente` · `crear-admin` · `resetear-password` · `eliminar-cliente` · `importar-clientes` ([[Importador de clientes]]) · `enviar-comunicado` · `enviar-push` · `notificar-pagos` ([[Notificaciones de pagos]]).

## Notas relacionadas
[[Clave temporal = DNI]] · [[Bug de fechas UTC]] · [[Auditorías del portal]] · [[Inicio]]
