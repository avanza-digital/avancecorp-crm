# Auditoría advisors 2026-08-01 — triage y hardening

Triage de las **71 alertas** de los advisors de Supabase (47 seguridad + 24 rendimiento),
verificado contra la base real (definiciones y grants), no solo contra el reporte.
Resultado: **4 fixes reales** en una migración (`20260801092924_crm_hardening_advisors_vistas_pgnet`),
✅ **EN PROD 2026-08-01** con el ciclo completo (auditor-rls → branch → gate RLS **363/363** →
merge → verificación en prod → branch borrado). Los 2 ERROR del linter muertos en prod.
Detalle operativo en el ledger (`MIGRACIONES.md` del repo del CRM).

## Lo que el linter pintaba mal y NO era grave

- **Los 2 ERROR** (`security_definer_view` en `crm.contratos_cartera` y `crm.clientes_basicos`)
  eran falsos positivos funcionales: las vistas son envoltorios de `*_fn()` SECURITY DEFINER
  que scopean por rol adentro (`private.rol_crm`, `private.vendedor_ids_visibles`,
  `private.es_lector_global`). El patrón **función definer gateada + vista invoker** es la
  decisión de F0 (migraciones `20260711000003/000004`); las vistas se recrearon después sin
  el flag `security_invoker` y el ERROR reapareció. El fix es restaurar el flag — no cambia filas.
- **41 funciones SECURITY DEFINER expuestas por REST**: es el patrón deliberado del CRM
  (RPC definer con guardia interna, porque clientes del portal y staff del CRM son TODOS
  `authenticated` del mismo proyecto). Se verificaron las 41: solo `contrato_tiene_pagos`
  no tenía guardia.
- **`crm.lead_asignaciones` con RLS sin policies**: intencional. Deny-all; el ledger solo se
  toca vía RPCs definer.

## Lo que el linter subestimaba

- **`pg_net`**: `anon`, `authenticated` y PUBLIC tienen USAGE sobre el esquema `net` y EXECUTE
  sobre `net.http_get/http_post` (SSRF latente). ⚠️ **Lección dura: el REVOKE es NO-OP en
  Supabase gestionado** — los grants los concedió `supabase_admin` y el rol `postgres` no puede
  revocarlos (verificado: ACL intacto tras el revoke en el branch). Mitigación real: `net` fuera
  de los Exposed schemas de la API (config de plataforma, no consultable por SQL — check visual
  en dashboard) y los 2 jobs de pg_cron que sí usan `net.http_post` corren como `postgres`.
  ⚠️ Trampa doble descubierta por el auditor-rls: escanear `pg_proc` NO detecta usos de
  `net.http_*` en `cron.job` (los jobs de pg_cron son texto SQL, no funciones).
- **`public.contrato_tiene_pagos(uuid)`**: sin guardia, cualquier authenticated podía sondear
  si un contrato ajeno tiene pagos (booleano, requiere UUID). Ahora exige `puede_ver_contrato`
  y devuelve `false` sin excepción (el llamador único es la pantalla admin del portal).
  Decisión clavada en el gate: **service_role sin JWT también recibe `false`** — la RPC es
  para humanos logueados; los procesos leen las tablas directo.

## Diferido a propósito (no tocar sin motivo nuevo)

- **5 políticas RLS permisivas múltiples** (contratos, perfiles, cronograma_pagos, audit_log):
  micro-optimización; a esta escala tocar RLS estable arriesga más de lo que gana.
- **15 índices "sin uso"**: 10 están en `crm.lead_asignaciones` y `crm.tareas` — features
  recién estrenadas; "sin uso" = estadísticas jóvenes, no peso muerto. **Re-mirar ~octubre 2026.**
- **Conexiones Auth con límite absoluto (10)**: solo importa al subir de instancia.
- **Extensiones en `public`** (`pg_trgm`, `pg_net`): moverlas de esquema es cosmético y con
  riesgo de romper índices/triggers; el riesgo real de pg_net ya se cerró con el REVOKE.

## Pendiente del lado de Miguel

- **HaveIBeenPwned** (protección de contraseñas filtradas): toggle del dashboard de Supabase
  (Authentication → passwords). No se puede activar por MCP.

Relacionadas: [[Distribución de leads por capital y trazabilidad CRM]], [[Bienvenido]].
