---
tags: [auditoria, seguridad, finanzas, historial]
actualizado: 2026-06-13
---

# Auditoría exhaustiva 2026-06-13

Auditoría completa multi-agente (62 agentes: 7 dimensiones → verificación adversarial doble → síntesis) + verificación directa en producción por SQL. **Veredicto: lanzar-con-reservas.** 27 candidatos → **17 confirmados**, 10 descartados.

## Lo que se verificó SANO (sin acción)
- **RLS** correcto en las 9 tablas operativas: cliente aislado (`cliente_id=auth.uid()`), analista acotado (`creado_por=auth.uid()` + ventana 5 h), auto-update de perfil con `with_check rol=mi_rol()` → **no permite auto-escalar rol**. DELETE de perfiles/contratos/novedades solo superadmin.
- **Matemática de interés compuesto exacta al céntimo** en los 2 contratos reales (1000@15%×5a → 1011.36; 5000@17%×2a → 1844.50; capital a vencimiento+7d).
- Las **14 funciones `SECURITY DEFINER`** revalidan rol internamente → por diseño, no vulnerabilidad. `notificar-pagos` (sin JWT, cron) usa `verificar_cron_secret` contra `vault`.

## Hallazgos RESUELTOS en esta sesión (aplicados a prod)
1. **🔴 CRÍTICO — `respaldo_nombres_2026_06_10` con RLS OFF + GRANTs a `anon`.** PII de 25 clientes leíble/borrable por cualquier anónimo con la anon key pública. → `DROP TABLE` (migración `drop_respaldo_nombres_pii_2026_06_13`). **Regla nueva:** ninguna tabla `respaldo_*`/temporal se crea en `public` sin RLS+REVOKE.
2. **🟠 ALTO — pagos sin auditar desde el 2026-06-01.** Se había quitado el trigger de `cronograma_pagos`. → nuevo trigger `trg_audit_cronograma_pago` (migración `audit_cronograma_pagos_updates_2026_06_13`): audita solo `UPDATE` de `estado/monto_pagado/fecha_pago_real/registrado_por`, NO la regeneración masiva (DELETE+INSERT).
3. **🟡 Datos de prueba en prod.** Eliminadas `CLIENTE PRUEBA` y `CLIENTEPRUEBA2` (+ contratos S/50k c/u). AUM PEN limpio: ~S/100k ficticios fuera. 33→31 contratos/clientes.
4. **🟡 Backfill de asesores.** 5 clientes con `asesor_id` legacy (MIGUEL BRICEÑO) → `asesor_perfil_id` del perfil analista `d731f284`. **DELZO COLLADO** (cliente real sin asesor) asignado a MIGUEL BRICEÑO **por defecto — reasignable si su analista era otro**.
5. **Efecto:** clientes sin asesor 8→0; el ranking del directorio reconcilia 100% con el AUM (S/0 fuera de ranking). El fix de código de `directorio_ranking_analistas` (COALESCE/LEFT JOIN) queda opcional/defensivo.

## Resueltos también en la continuación (2026-06-13b — desplegado y verificado)
- **🟡 `proteger_campos_inmutables` endurecido (BD):** en `perfiles`, el auto-update de un no-admin restaura desde OLD `activo/rol/asesor_id/asesor_perfil_id/cargo` (ya no puede reactivarse ni reasignarse de analista). `debe_cambiar_password` **se dejó editable** a propósito (el cliente lo baja en el primer ingreso vía `reset-password.js`). Migración `proteger_perfil_autoupdate_cliente_2026_06_13`.
- **🟡 Redondeo half-up (frontend):** helper `redondear2` (notación exponencial, igual que `round()` de Postgres) reemplaza `.toFixed(2)` en `montoFijo`/`interesTotal` de `contratos.js`/`analista.js`. Verificado: 6667@18%/12 → 100.01 (antes 100.00); compuesto idéntico (1011.36/1844.50). Solo afecta contratos NUEVOS. Bumps `contratos v29`/`analista v14`, SW v91. **Desplegado a Hostinger vía MCP y verificado en prod.**
- **🟢 Drift + infra:** `diagnostico-push` (tombstone 410) versionada en `_supabase_functions/functions/diagnostico-push/index.ts`; `.htaccess` ahora bloquea `graphify-out/` (`/graphify-out`→403); §14 del `public_html/CLAUDE.md` lista `graphify-out/` y `_*` como NO subir.

## Pendientes (acción aparte)
- **🟡 HIBP + política de contraseña mínima** en Supabase Auth → **Miguel (toggle del dashboard; no hay tool MCP para esto).**
- **🟡 Ciclo de vida de contratos** (vencido/renovado/retirado) — diseño nuevo; **muerde en oct-2026** (primer vencimiento). Acción admin + job diario.
- **🟢 Mensajes de error genéricos** en edge functions (hoy devuelven `.message` crudo a staff autenticado; sin fuga de secretos).
- **🟢 Gating de páginas de cliente por rol** en `auth.js` (bajo; RLS ya protege). Evita la cascada de 19 importadores → agendar junto al próximo cambio de `auth.js`.
- **🟢 Mover `pg_trgm`/`pg_net`** fuera de `public` (usados por el buscador; baja prioridad). Función muerta `rentabilidadAcumulada` en `inversion.js` (bug UTC latente, sin caller).

## No re-alertado (cerrado)
[[Clave temporal = DNI]] (Miguel: no es riesgo) · XSS analista→admin (resuelto 2026-06-03, ver [[Auditoría prelanzamiento 2026-06-03]]).

## Notas relacionadas
[[Auditorías del portal]] · [[Arquitectura del portal]] · [[Interés compuesto]] · [[Fusión asesor-analista]] · [[Rol Directorio]] · [[Inicio]]
