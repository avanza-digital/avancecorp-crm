---
tags: [feature, realtime, comunicados]
actualizado: 2026-06-01
---

# Realtime de novedades

**Implementado 2026-05-24.** El **badge de comunicados** sube/baja en vivo en las 7 páginas cliente, sin recargar: sube al llegar un comunicado nuevo, baja al marcar leído en otra pestaña/dispositivo.

## Cómo funciona
- **Supabase Realtime** (`postgres_changes`). Tablas `novedades` (INSERT → comunicado nuevo) y `novedades_leidas` (INSERT → acuse propio) están en la publicación `supabase_realtime`.
- El cliente se suscribe con su **JWT**, así que la **RLS SELECT filtra los eventos por usuario** (sin fuga). El front **solo escucha INSERT**.
- Lógica centralizada en `js/novedades-utils.js` (`suscribirseNovedades`, `iniciarBadgeNoLeidasRealtime`, debounce 250 ms).
- **Pendiente:** sincronizar "marcar leído" entre pestañas (hoy solo INSERT).

## Notas relacionadas
[[Notificaciones de pagos]] · [[Arquitectura del portal]] · [[Inicio]]
