# Ledger de migraciones — esquema `crm`

Proyecto: `dctqcbznekcyxhjujuci` (el MISMO del portal — ver condiciones §5 del plan).
Ciclo obligatorio: **branch de Supabase → aplicar → `scripts/test-rls.mjs` → advisors → merge**.
Prohibido `apply_migration` directo a producción. Ninguna migración altera objetos de `public`.

| # | Version | Nombre | Qué hace | Estado |
|---|---------|--------|----------|--------|
| 1 | 20260709000001 | cimientos_crm | Esquemas `crm`+`private`; `crm.equipo` (jerarquía 3 roles + directorio externo); helpers `private.{rol_crm, vendedor_ids_visibles (CTE recursivo), puede_ver_cartera, es_lector_global}`; `crm.leads` (etapas nuevo→contactado→reunion_agendada→propuesta_enviada / convertido·descartado, dedup vivo por teléfono E.164 y DNI, FKs a perfiles/contratos); `crm.actividades` (log inmutable); triggers (inmutabilidad+guard de conversión, touch, normalizar teléfono +51, cambio de etapa→timeline, bloquear reasignación por vendedor, auditoría→public.audit_log); RLS jerárquica deny-by-default sin DELETE; vista `crm.clientes_basicos` (sin columnas bancarias, security_invoker); `crm.existe_cliente_por_dni` (gate interno); grants (authenticated + service_role) + hardening (revokes) | ✍️ escrita + **revisada adversarialmente (3 lentes)** y endurecida con 11 fixes, **NO aplicada** — pendiente de OK de Miguel |

## Revisión adversarial (2026-07-09)

3 agentes independientes intentaron refutar la seguridad del SQL (lentes: escalada/RLS ·
impacto en el portal en producción · corrección SQL). Veredicto de los 3: **apto con fixes**.
Todos los hallazgos se incorporaron a la migración (ver bloque de comentarios al final del .sql
y `docs/recon/11-revision-adversarial-f0.md`). Los 2 críticos que habrían tocado producción:
oráculo de DNI abierto a los 127 clientes del portal, y CHECK de conversión que rompía el
hard-delete de clientes existente. Ambos cerrados.

## Pasos manuales asociados (una vez, tras aplicar la #1)

1. Dashboard → Settings → API → **Exposed schemas**: añadir `crm` (queda `public, crm`).
2. Verificar con `get_advisors` (security + performance) que no aparece nada nuevo.

## Deuda/decisiones anotadas

- El alta/edición de `crm.equipo` no tiene policies a propósito: va por RPC/edge gerencia-gated (F1). Mientras no exista, se administra por SQL de superadmin.
- La conversión lead→cliente (edge `crm-convertir-lead`) llega en F3; el CHECK `convertido_requiere_perfil` ya la protege.
- Realtime/notificaciones del CRM: F2 (no se añadió nada a la publicación `supabase_realtime`).
