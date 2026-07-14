---
tags: [crm, db, supabase, f0, rls]
actualizado: 2026-07-11
---

# F0 — Cimientos BD del CRM (APLICADA EN PROD 2026-07-11)

La base de datos del CRM (fase **F0** del plan P-055) quedó **mergeada en producción**
(`dctqcbznekcyxhjujuci`, el mismo Supabase del portal) el 2026-07-11, vía el ciclo
obligatorio **branch → gate RLS → advisors → merge**. Ver el ledger técnico en
`CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`.

## Qué existe ahora en prod

- Esquema **`crm`**: tablas `equipo` (jerarquía comercial), `leads`, `actividades`
  (log inmutable); vista `clientes_basicos` (clientes SIN columnas bancarias, scopeada por
  cartera); funciones `clientes_basicos_fn` y `existe_cliente_por_dni` (gateadas).
- Esquema **`private`** (helpers de visibilidad, NO expuesto por API): CTE recursivo de
  jerarquía, lector global, etc.
- **RLS deny-by-default**, sin DELETE, timeline inmutable, conversión lead→cliente
  bloqueada hasta F3. Gate de seguridad: **130/130 aserciones** con 12 sesiones reales.

## Cambio en el PORTAL (excepción aprobada por Miguel)

Se añadió el rol de portal **`comercial`** a `perfiles.rol` (migración
`20260711000001`). Es un rol NEUTRO deny-by-default: la fuerza de ventas del CRM se
enrola con este rol para NO heredar las policies del portal (que filtrarían columnas
bancarias de clientes). Los analistas reales del portal pueden enrolarse conservando su
rol analista, sabiendo que mantienen sus poderes de portal. Ver [[Acceso y roles del CRM]].

## Cómo se hizo posible el branching (squash del historial)

El historial de 63 migraciones del portal no incluía el esquema base (creado por dashboard),
así que ningún branch podía replicarse. Con OK de Miguel se **squasheó** a una sola
migración baseline (dump schema-only de prod). Respaldo íntegro:
`_DEV_NO_SUBIR/respaldo-schema-migrations-2026-07-11.json`. Solo se tocó la tabla de
bookkeeping; el esquema real de prod quedó intacto.

## Verificación

- Gate RLS 130/130 en el branch.
- Advisors de prod post-merge: **sin ERROR** (solo WARN pre-existentes del portal).
- **Panel adversarial de 5 escépticos**: refutó y se corrigieron 2 hallazgos (PII sin scope,
  fila de equipo de miembro desactivado) + drift de grants del baseline.

## Pendiente (ver resumen abajo)

1. **Exposed schemas en prod**: añadir `crm` (Settings → API → Exposed schemas) — sin esto
   el frontend CRM no ve el esquema. `private` JAMÁS se expone.
2. **Usuarios reales del CRM** con rol `comercial` (Auth + perfil + fila en `crm.equipo`);
   la RPC gerencia-gated de alta llega en F1, por ahora es SQL de superadmin.
3. Borrar el branch `crm-f0` (temporal, cuesta ~$0.32/día).

## Notas relacionadas

[[Acceso y roles del CRM]] · [[Deuda técnica CRM fuera de DB 2026-07-10]] · [[Deploy a Hostinger]] · [[Inicio]]
