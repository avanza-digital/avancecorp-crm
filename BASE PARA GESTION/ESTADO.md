# ESTADO del módulo «Base para gestión del analista»

**Última sesión:** 02/10/2026 (madrugada) · **Fase en curso:** B1 (esquema) — lista en local, falta la rama y el merge.
**Bloqueo:** el conector «claude.ai Supabase» no estaba cargado; Miguel lo conecta con `/mcp` o lanza el ciclo con `!`.
**Nada en producción. Último commit del módulo:** `4cbd3806` (02/10, main local, sin push). Siguientes: `git log --oneline -- "BASE PARA GESTION"`.

| Fase | Estado | Evidencia / siguiente paso |
|---|---|---|
| F0 Reconocimiento | ☑ 01/10, re-verificado 02/10 | Nota del vault; 2 choques nuevos (D9 `origen` inmutable, D10 puerta v4 rechaza descartados) |
| D1–D10 Decisiones | ☑ 02/10 | Tabla en `README.md`; marcadas en FigJam |
| **B1 Esquema** | **◉ local listo** | Migración `20261002054402`, banco PASS (aplicar + 5 negativos, test 12/12, reversa-y-reaplicar), `auditor-rls` con P1/P2 corregidos, typecheck/check:scripts/rls-preflight PASS. **Siguiente:** rama → aplicar → `test-rls.mjs` (`CRM_RLS_EXIGE_BASE_GESTION=1`) → advisors (y EXPLAIN con datos reales: ¿hace falta índice parcial `where etapa='descartado'`?) → merge |
| B2 RLS / ámbito | ☐ | Plan corto para Miguel. Previsto: RLS sin cambios para el analista; acceso a la base por RPC DEFINER con gate por rol (vendedor/supervisor/gerencia) y `vendedor_ids_visibles`; ampliar `levantar_no_contactar` al supervisor (D5; no está sellada). Codex B1+B2 |
| B3 Puertas | ☐ | `crm.obtener_base_gestion()`, `crm.registrar_intento_base(...)` + núcleo nuevo (2 GUC), `crm.reactivar_lead_base(...)` sobre `reabrir_lead_fn` + avance a `contactado` (D1), reuso de `marcar_no_contactar`/`levantar_no_contactar`. Probar con analista y supervisor en la rama |
| B4 Triggers | ☐ | Trigger AFTER INSERT en `actividades` (evento `intento_base`): 3.º intento sin cita/reactivación → `enfriado_hasta = hoy Lima + 30` (GUC del sello). SLA ya se reinicia al reabrir: verificar simulando fechas. Codex B3+B4 |
| merge de Miguel | ☐ | Tras B4 |
| F1 Vista analista | ☐ | `#/rescate` despacha por rol (como `gestion-diaria`); analista → lista plana por `obtener_base_gestion()` |
| F2 Ficha | ☐ | Historial completo legible + buscador; formulario de intento (7 resultados; fecha en volver a llamar); Reactivar (confirmación, idempotente); No contactar con motivo |
| F3 Organización | ☐ | «Llamar hoy» arriba; filtros motivo/etapa máxima/último resultado; contador de intentos |
| F4 Supervisor | ☐ | Columnas Intentos · Último resultado · Gestiona; quitar «no contactar» (D5); indicador de reactivaciones por analista |
| QA final | ☐ | 9 puntos del encargo + `npm run check` + `test:rls` + E2E Docker |

## Cómo actualizar este archivo
Al cerrar cada paso: cambia el estado (☐ → ◉ → ☑), escribe la evidencia (qué se corrió y resultado PASS/FAIL/NOT RUN) y el
siguiente paso concreto. Actualiza también la línea «Última sesión» y la nota del vault. No marques ☑ sin evidencia.
