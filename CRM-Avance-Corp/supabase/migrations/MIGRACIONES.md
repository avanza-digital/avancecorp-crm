# Ledger de migraciones — esquema `crm`

Proyecto: `dctqcbznekcyxhjujuci` (el MISMO del portal — ver condiciones §5 del plan).
Ciclo obligatorio: **branch de Supabase → aplicar → `scripts/test-rls.mjs` → advisors → merge**.
Prohibido `apply_migration` directo a producción. Ninguna migración del CRM altera objetos
de `public` (única excepción documentada: `20260711000001`, con OK explícito de Miguel).

## Prehistoria: squash del historial del portal (2026-07-11)

El historial del portal (63 migraciones) empezaba en fixes de abril: el esquema base se creó
por dashboard y nunca fue migración → **ningún branch podía replicarse** (la #1 fallaba sobre
una BD vacía). Con OK de Miguel se hizo **squash**: las 63 filas de
`supabase_migrations.schema_migrations` se reemplazaron por una sola baseline
(`20260708000000_baseline_squash_portal` = dump schema-only de `public` con pg_dump 18.4 +
extras: buckets/policies de storage, publicación realtime, secreto Vault, cron job).
- Respaldo íntegro de las 63 filas: `_DEV_NO_SUBIR/respaldo-schema-migrations-2026-07-11.json`.
- El baseline NO se re-ejecuta en prod (solo replica branches); validado con BEGIN…ROLLBACK
  sobre un branch vacío y luego con rebase real: réplica idéntica (11 contadores de catálogo).
- El esquema real de prod NO se tocó: solo la tabla de bookkeeping.

## Migraciones del ciclo F0

| # | Version | Nombre | Qué hace | Estado |
|---|---------|--------|----------|--------|
| 1 | 20260709000001 | cimientos_crm | Esquemas `crm`+`private`; `crm.equipo` (jerarquía 3 roles + directorio externo); helpers `private.*` (CTE recursivo, lector global); `crm.leads` (dedup vivo tel/DNI, FKs a perfiles/contratos); `crm.actividades` (log inmutable); triggers (inmutabilidad, conversión gated por `crm.op_privilegiada`, normalizar teléfono, timeline, bloquear reasignación, auditoría→audit_log); RLS deny-by-default sin DELETE; vista `crm.clientes_basicos`; `crm.existe_cliente_por_dni` gated; grants+hardening. 11 fixes de revisión adversarial (2026-07-09) | ✅ aplicada en branch `crm-f0` · gate 128/128 · **pendiente de merge** |
| 2 | 20260711000001 | portal_rol_comercial | **[PORTAL — excepción con OK de Miguel]** extiende `perfiles_rol_check` con `'comercial'`: rol de portal NEUTRO (deny-by-default, solo su propia fila) para la fuerza de ventas del CRM. Motivo: el gate demostró que enrolar CRM como 'analista' hereda las policies del portal y filtra columnas bancarias de clientes asignados | ✅ aplicada en branch · **pendiente de merge** |
| 3 | 20260711000002 | fix_clientes_basicos_gate_propio | La vista `security_invoker` quedaba VACÍA para rol comercial (hallazgo del gate). Se pasa a vista de owner con gate interno de staff CRM/lector global | ✅ aplicada en branch (superada en parte por la #4) · **pendiente de merge** |
| 4 | 20260711000003 | hardening_advisors_f0 | Cierra los 3 hallazgos nuevos de advisors: `clientes_basicos` pasa a **función definer gateada (`crm.clientes_basicos_fn`) + vista invoker** (mata el ERROR `security_definer_view`, mismo patrón aceptado que `existe_cliente_por_dni`); `search_path` fijo en `private.normalizar_telefono`; índices FK `creado_por` en las 3 tablas crm | ✅ aplicada en branch · gate re-verificado 128/128 · **pendiente de merge** |
| 5 | 20260711000004 | scope_clientes_y_equipo_desactivado | Cierra 2 hallazgos del **panel adversarial** (2026-07-11): (a) `clientes_basicos_fn` se **scopea por cartera** (gerencia/lector global ven todos; supervisor/vendedor solo clientes cuyo `asesor_perfil_id` ∈ su subárbol) — la 000003 lo había dejado global, exponiendo PII de los 139 clientes a cualquier vendedor; (b) `equipo_select` exige `activo=true` en la rama self → un miembro desactivado ya no lee su propia fila | ✅ aplicada en branch · gate 130/130 · **pendiente de merge** |
| 6 | 20260714000001 | perfiles_tipo_documento | **[PORTAL — excepción con OK de Miguel, 2ª]** agrega `perfiles.tipo_documento` (`text NOT NULL DEFAULT 'DNI'` + CHECK de dominio `DNI/CE/PASAPORTE`) y backfill 9–12 dígitos→CE. SIN CHECK de formato (diferido: los writers viejos lo violarían durante la ventana de deploy). Aplicada DIRECTO a prod por el carril del portal (QA tx revertida + advisors sin hallazgos nuevos), no por el gate del CRM: no toca RLS ni objetos `crm` | ✅ **aplicada en PROD 2026-07-14** (166 DNI + 7 CE) |

## Gate RLS (2026-07-11, branch `crm-f0`)

`seed:demo` + `test:rls`: **130/130 aserciones** (12 sesiones reales, jerarquía recursiva de
2 niveles, frontera bancaria con rol comercial, scope de cartera de clientes, inmutabilidad, anon).
Iteraciones: 4 fallas de frontera bancaria → #2 (rol comercial); 1 falla (vista vacía) → #3;
2 aserciones nuevas del panel adversarial → #5 (scope de cartera + equipo desactivado).
Advisors del branch: **sin ERROR**; registros nuevos del CRM = 2 WARN
`authenticated_security_definer_function_executable` (`crm.clientes_basicos_fn` y
`crm.existe_cliente_por_dni`), clase ya aceptada en el portal para RPCs gateadas (gate interno
exige staff CRM/lector global). Los 16 WARN de `public.*` con `anon EXECUTE` que aparecen en el
branch eran **drift del baseline**, no de prod (ver abajo).

## Verificación adversarial (panel de 5 escépticos, 2026-07-11)

5 agentes intentaron refutar las garantías del branch antes del merge (seguridad de
`clientes_basicos`, rol comercial, fidelidad del baseline, lógica de F0, completitud del ciclo).
Hallazgos accionados: scope de PII (#5), equipo desactivado (#5), y el drift de grants del
baseline (corregido, ver abajo). Confirmado sin refutar: rol comercial es deny-by-default,
`op_privilegiada` no es fijable por PostgREST, timeline inmutable, CTE recursivo estable.
Hallazgo PRE-EXISTENTE del portal **fuera de alcance CRM** (no se toca por regla): `novedades_update`
permite a cualquier authenticated modificar novedades broadcast (`destinatario_id IS NULL`).

## Fidelidad del baseline (corregido 2026-07-11)

El panel detectó que el branch concedía `EXECUTE` a `anon`/`authenticated` en 16 funciones de
`public` donde prod las revoca (causa: los DEFAULT PRIVILEGES de Supabase conceden EXECUTE en
cada `CREATE FUNCTION` y `REVOKE ... FROM PUBLIC` de pg_dump no borra el grant por-rol). **No es
riesgo de prod** (el merge no toca esas funciones; prod conserva sus ACL). Se corrigió el baseline
(`_DEV_NO_SUBIR/baseline-full.sql` + fila `20260708000000` en prod) con 18 REVOKE explícitos
tomados de las ACL reales de prod, para que **los branches futuros (F1–F5) nazcan fieles**.

## Pasos manuales asociados (una vez, tras el merge)

1. **Exposed schemas en prod**: Dashboard → Settings → API → añadir `crm`
   (queda `public, graphql_public, crm`) — o `PATCH /v1/projects/{ref}/postgrest`.
   En el branch ya se hizo vía API (necesario para el gate).
2. Verificar con `get_advisors` (security + performance) en prod que no aparece nada nuevo.
3. Usuarios reales del CRM: crear con **rol de portal `comercial`** (Auth + `public.perfiles`
   activo + fila en `crm.equipo`). Los analistas reales del portal PUEDEN enrolarse
   conservando su rol analista, sabiendo que mantienen sus poderes de portal.
4. Borrar el branch `crm-f0` (deja de facturar ~$0.32/día).

## Deuda/decisiones anotadas

- El alta/edición de `crm.equipo` no tiene policies a propósito: va por RPC/edge gerencia-gated (F1). Mientras no exista, se administra por SQL de superadmin.
- La conversión lead→cliente (edge `crm-convertir-lead`) llega en F3; el guard de conversión en trigger (`crm.op_privilegiada`) ya la protege.
- Realtime/notificaciones del CRM: F2 (no se añadió nada a la publicación `supabase_realtime`).
- La fila PROPIA de `public.perfiles` es visible para cualquier authenticated (policy
  `perfiles_select` del portal, incluye sus propias columnas bancarias — vacías para staff).
  Es semántica del portal, documentada en el gate; la frontera protegida es la CARTERA.
