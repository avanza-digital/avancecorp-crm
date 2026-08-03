# supabase/migrations/ — migraciones del esquema `crm`

Contiene el historial versionado del esquema `crm`; `MIGRACIONES.md` registra
la intención, verificación y estado de producción de cada cambio.

Reglas heredadas del plan (§5, condiciones no negociables):

- Formato `AAAAMMDDHHMMSS_nombre.sql` + `MIGRACIONES.md` como ledger documentado (patrón VITANOVA).
- Todas las tablas nuevas en el esquema **`crm`**; helpers de visibilidad en **`private`**.
- **Ninguna migración altera tablas/triggers/policies de `public`** (el portal en producción).
- RLS ON en el mismo statement de creación; deny-by-default; soft-delete `activo=false` sin policy DELETE.
- Ciclo: branch de Supabase → aplicar → `scripts/test-rls.mjs` → advisors → merge. Nunca directo a prod.
- Tras cada bloque funcional: migración de hardening (search_path + revokes).
- Trigger `log_audit_change` sobre toda tabla `crm.*` desde la primera migración.
