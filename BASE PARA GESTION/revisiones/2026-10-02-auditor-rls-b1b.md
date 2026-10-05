# auditor-rls · B1b (20261002224851_crm_base_gestion_proxima_llamada.sql) — 02/10/2026 (noche)

**VERDICT: CHANGES_REQUESTED** (la migración es sólida; lo accionable estaba en la matriz y en la reversa hermana de B1).
**APLICADO el 02/10 (noche):** P2 matriz → el bloque `testBaseGestionB1` de `test-rls.mjs` cubre B1b (PATCH 42501 de
`proxima_llamada_en` para dueño/supervisor/gerencia, no-op NULL, SELECT con las 3 columnas, ACL exacta 6, `tgattr` = 3 con
el attnum de la columna, constantes 3/30/10, índice válido; detección «aplicada» por las 3 columnas). P2 reversa B1 →
guarda: se niega si `proxima_llamada_en` existe («aplicar antes reversa-proxima-llamada.sql»), verificado en banco.
P3 postflight → contrato de constantes y sello reverificado, `anon` sin EXECUTE, positivos con offset+microsegundos y con
`.000Z` capturando `check_violation`, aserción «el ensayo se deshizo». P3 reversa B1b → reemite los tres `comment on` de B1
y comprueba `tgattr` = 2 y que el CHECK vuelve a exigir `tarea_id`. P3 regex → documentado en el comentario del CHECK
(«el núcleo construye la clave con `to_jsonb(timestamptz)`, nunca `::text`, y castea antes de escribir»). README del
banco con comandos B1b y orden de reversas.

## Lo que el auditor verificó sin hallazgo
Sello cerrado para las tres columnas (INSERT/UPDATE, GUC, exención `auth.uid()` null), sin ventana en `drop/create
trigger` (misma transacción, mismo nombre → mismo orden `zz`). CHECK: trampa NULL cerrada; la regex acepta la salida de JS/
PostgREST (`.000Z`) y de `to_jsonb` (offset `±hh:mm`), rechaza fecha sin zona; la clave `proxima_llamada_en` de metadata no
está reservada por «solo núcleo» (ruido inocuo: la agenda se lee de `crm.leads`). `drop function` de constantes sin
dependientes. Índice con convención, predicado alineado y comentario. Grants: 6 ACL exactas. Postflight sin rastro.
Preflight «sin intento_base» correcto (algo estricto, mejora el mensaje). Riesgo heredado: la exención `auth.uid()` null
cubre a `service_role` sin `sub`, igual que en B1 y «solo núcleo» (aceptado antes).

## Nota para B3
Construir `metadata.proxima_llamada_en` con `to_jsonb(v_ts)`; castear a `timestamptz` antes de escribir la columna; leer la
agenda de `crm.leads.proxima_llamada_en`, nunca de la metadata.
