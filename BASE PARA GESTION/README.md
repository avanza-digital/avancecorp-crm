# BASE PARA GESTION — carpeta de trabajo del módulo (TEMPORAL: se borra al cerrar)

Módulo: **Base de gestión para analistas con seguimiento y reactivación de leads** (encargo P-0XX, Miguel, 01/10/2026).
Esta carpeta existe para que **cualquier sesión** retome el plan en la fase en que esté. Cuando el módulo quede
publicado y con QA cerrada, se borra entera; el conocimiento duradero vive en el vault, no aquí.

## Cómo retomar (en este orden)
1. Lee `ESTADO.md` (fase en curso, qué está hecho, qué sigue, bloqueos).
2. Lee la nota del vault `BASE DE CONOCIMINETO/AVANCECORP/Base para gestion del analista - F0 y decisiones (2026-10-01).md`
   (F0, decisiones D1–D10, evidencia por agentes, estado de cada fase).
3. Abre el tablero del plan en FigJam (conector «claude.ai Figma», nunca la app a mano):
   https://www.figma.com/board/zbgq3gjYGsaaMCo6e140bU — nodos en la nota del vault.
4. `git status`: estás en `main`; otras sesiones comparten ESTA carpeta. **Una sola sesión escribe por fase.**
   Commitea solo tus rutas (`git add <ruta>`); si un archivo compartido tiene cambios ajenos, stagea solo tus hunks.
5. Ejecuta la fase según `ENCARGO.md` + el plan ajustado: fases B (base de datos) → plan corto y confirmación de
   Miguel ANTES de escribir SQL; fases F (frontend) → ejecutar y reportar decisiones. Al terminar: reporta y detente.
6. Actualiza `ESTADO.md`, la nota del vault y el tablero (☐ → ◉ → ☑, línea «Actualizado»).

## Mapa de lo construido
- Migración B1: `CRM-Avance-Corp/supabase/migrations/20261002054402_crm_base_gestion_esquema.sql`
- Migración B1b (rellamada en el lead): `…/20261002224851_crm_base_gestion_proxima_llamada.sql`
- Migración B3 (puertas y núcleos): `…/20261002231436_crm_base_gestion_puertas.sql` · B4 (trigger de enfriamiento): `…/20261002233851_crm_base_gestion_enfriamiento.sql` · B4b (D13): `…/20261002235342_crm_base_gestion_ventana_descanso.sql` · B3b (Codex): `…/20261003001014_crm_base_gestion_idempotencia_y_orden.sql`
- Migración B2 (D5, Supervisión levanta «no contactar»): `…/20261002061500_crm_base_gestion_no_contactar_supervisor.sql`
- Revisiones (auditor-rls, Codex): `BASE PARA GESTION/revisiones/`
- Banco Docker + pruebas + reversa: `CRM-Avance-Corp/supabase/scripts/base-gestion/` (`banco.mjs crear|aplicar|test|reversa-y-reaplicar`)
- Matriz RLS: bloque `testBaseGestionB1` en `CRM-Avance-Corp/supabase/scripts/test-rls.mjs`
- Ledger: entrada `20261002054402` en `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`
- Tipos: `reactivado_en` / `enfriado_hasta` añadidos a mano en `app/src/lib/database.types.ts` (regenerar tras la rama)
- Encargo original: `ENCARGO.md` (texto íntegro de Miguel) · Plan técnico del frontend: `FRONTEND.md` (F1–F4, hechos del front que mandan)

## Decisiones de Miguel (02/10/2026) — mandan sobre el encargo
| # | Decisión |
|---|---|
| D1 | Reactivar lleva el lead **directo a `contactado`** (reabrir a `nuevo` + avanzar en la misma transacción; el guard lo permite) |
| D2 | **Mismo analista** conserva el lead; el supervisor sigue repartiendo desde el Centro de rescate |
| D3 | **Botón «Reactivar» explícito**; «agendó cita» reactiva sola. No se crea el resultado «interesado» |
| D4 | **3 intentos sin cita ni reactivación → 30 días** de enfriamiento, por ciclo (`private.base_gestion_constantes()`) |
| D5 | **El supervisor también** puede quitar «no contactar» (su equipo, con motivo) → ampliar `crm.levantar_no_contactar` |
| D6 | Etapa máxima alcanzada **deducida del historial** (`cambio_etapa`) en la RPC, sin columna |
| D7 | Rellamada en **`crm.tareas`** (tipo `llamada`, `vence_en`) |
| D8 | **Columna `enfriado_hasta` + trigger** (B4) |
| D9 | Marca de reactivación = **`reactivado_en` + línea en el historial**; `origen` es inmutable y no se toca |
| D10 | **Puerta y núcleo propios** para el intento (`crm.registrar_intento_base` → `private.intento_base_registrar`) |
| D7-bis | **Agenda propia de la base** (02/10 noche): la rellamada vive en `crm.leads.proxima_llamada_en` (sellada), NO en `crm.tareas` (el CRM rechaza tareas en leads cerrados). Pantallas: bloque «Llamar hoy», contador en el menú, línea «Base: N rellamadas para hoy» en «Hoy». Migración B1b `20261002224851` |
| D11 | La rellamada se agenda **como máximo 10 días adelante** (`dias_max_rellamada = 10`) |
| D12 | **Gana la rellamada:** el enfriamiento de 30 días arranca solo cuando el 3.º intento termina sin cita y sin rellamada agendada |
| D13 | **Tres intentos nuevos tras cada descanso** (02/10 noche): la ventana de intentos empieza en el descarte o al vencer el último descanso. Migración B4b `20261002235342` |

## Reglas que no se negocian en este módulo
- Arquitectura en 4 capas: puertas `crm.*` → núcleos `private.*` → tablas con RLS; la pantalla solo llama RPC.
- **No reemplazar funciones selladas por huella** (`assert_gestion_diaria_resultado` fija `llamada_registrar`,
  `reabrir_lead_fn`, `marcar_no_contactar`, `trg_leads_cambio_etapa`, `trg_leads_zz_sello_descarte`,
  `trg_leads_sync_tareas`, `trg_actividades_resultado_solo_nucleo`, `actividades_de_lead_core`). Llamarlas sí.
- La rellamada de la base NO es una tarea (D7-bis): el núcleo escribe `proxima_llamada_en` bajo el sello; máximo 10 días (D11); gana al enfriamiento (D12).
- El núcleo del intento enciende **dos GUC** de transacción: `crm.op_base_gestion` (sello de leads) y
  `crm.op_resultado_llamada` (claves `resultado`/`intento_n` reservadas), restaurando el valor previo.
- Fechas: `(col at time zone 'America/Lima')::date`. Idempotencia: recibos `crm.sla_operacion_recibos`.
- Riesgo LEVEL 3: 1 review de Codex (`scripts/codex-review-mcp`, encargo por stdin) por bloque B1+B2 y otro por
  B3+B4; `auditor-rls` sobre cada migración antes de `test-rls`. E2E solo con Docker local.
- Base de datos: rama de Supabase (conector «claude.ai Supabase») → aplicar → `test-rls.mjs` → advisors → merge
  de Miguel. **Nunca directo a producción.** Frontend solo después del merge.
- Cada fase termina con un informe: IMPLEMENTED · MODIFIED · REVIEW · VERIFICATION · REMAINING RISKS · MANUAL ACTION.
