---
name: nueva-migracion
description: Crea una migración nueva del esquema crm siguiendo las convenciones del proyecto (timestamp, RLS deny-by-default, grants, ledger MIGRACIONES.md). Usar cuando haya que cambiar el esquema de la base de datos del CRM.
---

# Nueva migración del esquema `crm`

Reglas completas en `supabase/migrations/LEEME.md` y ledger en `supabase/migrations/MIGRACIONES.md`. Este skill NO aplica nada a producción: produce el `.sql` y deja el ciclo de gate documentado.

## Pasos

1. **Nombre**: `$(date -u +%Y%m%d%H%M%S)_crm_<tema>.sql` en `supabase/migrations/`.
   El tema en snake_case español, específico (`crm_capacidad_leads_objetivo`, no `cambios`).

2. **Nunca editar una migración ya commiteada.** Si hay que corregir una aplicada, se
   escribe una migración nueva que la enmiende (hay un hook que lo bloquea igualmente).

3. **Esqueleto obligatorio** dentro del `.sql`:
   - Comentario de cabecera: qué hace, por qué, y a qué fase/plan responde.
   - Tablas nuevas SOLO en esquema `crm` (helpers de visibilidad en `private`).
   - **RLS ON en el mismo statement de creación**; policies deny-by-default; SIN policy
     DELETE (soft-delete `activo = false`).
   - Trigger de auditoría sobre toda tabla `crm.*` nueva: `private.log_audit_crm`, o
     `private.log_audit_sin_secretos` (con las columnas a enmascarar) si guarda secretos: tokens,
     claves, contraseñas o credenciales.
   - `COMMENT ON` para tablas y columnas nuevas.
   - Funciones: `SECURITY DEFINER` solo con justificación escrita y `SET search_path` fijo.
   - **Grants explícitos**. ⚠️ `crm.leads` tiene privilegios POR COLUMNA: toda columna
     nueva necesita `GRANT SELECT/INSERT/UPDATE (columna)` o PostgREST la ignora.
   - PROHIBIDO tocar objetos de `public` (portal en prod) sin OK explícito de Miguel
     anotado en el ledger.

4. **Si toca visibilidad/policies/funciones**: actualizar la matriz de
   `supabase/scripts/test-rls.mjs` con los casos nuevos (permitido Y denegado por rol),
   y pasar el subagente `auditor-rls` sobre el `.sql`.

5. **Validar en local (sin red)**:
   ```bash
   npm run check:scripts && npm run test:rls:preflight
   ```

6. **Actualizar el ledger** `supabase/migrations/MIGRACIONES.md`: fila nueva con version,
   nombre, qué hace y estado (empieza como pendiente de branch).

7. **Tipos del front**: si cambió el esquema, en `app/`: `npm run gen:types`.

8. **Recordar el ciclo de aplicación** (lo ejecuta Miguel o una sesión con OK explícito):
   branch de Supabase → aplicar → gate `test-rls.mjs` → advisors → merge.
   **Nunca `apply_migration` directo a producción.**
