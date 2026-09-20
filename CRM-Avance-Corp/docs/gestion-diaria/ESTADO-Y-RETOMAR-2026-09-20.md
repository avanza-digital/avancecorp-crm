# Gestión Diaria — dónde estamos y cómo retomar (20/09/2026)

Este archivo es el punto de entrada para seguir el módulo en otra sesión. El plan aprobado
completo está al lado: `PLAN-POR-FASES-2026-09-19.md` (con el PLAN.md original del handoff,
los 6 mockups y el playbook UI/UX en `mockups/` y `UI-UX-playbook.pdf`). Para retomar, di:
**«retomemos gestión diaria F4»**.

## Estado por fase

| Fase | Qué entrega | Estado | Evidencia |
|---|---|---|---|
| F0 · Cimientos | Plus Jakarta Sans, primitivas `Tabs` / `RadioGroup` / `exportar-csv`, docs y nota del vault | ✅ en prod | PR #29 |
| F1 · Módulo + registro crudo | Vista `gestion-diaria` en el menú (Operación) para los 3 roles; registro del día por analista/tipo/etapa con paginación; CSV para gerencia | ✅ en prod (SQL `20260919211958` instalada y registrada el 20/09) | PR #34; puerta `crm.registro_actividad_fn` |
| F2 · Resultado tipificado | Toda llamada del CRM se cierra con 1 de 7 resultados; tarea siguiente, descarte con submotivo hacia el Centro de rescate, «No insistir»; Deshacer 24 h | ✅ en prod (SQL `20260920005000` instalada y registrada el 20/09; front `crm-20260920T034405Z-afc391974382`, build `build-20260920T034404914Z`) | PR #38; acta PR #41; puertas `crm.registrar_llamada_v3`, `crm.deshacer_resultado_llamada` |
| F3 · Analista «Mi día» | Cola del día (lead nuevo primero → vencidas → hoy → sin conversación), marcador, compromisos, descartados de hoy con Deshacer; núcleo `private.gestion_diaria_llamadas` (llamadas por hora) | ✅ **EN PROD** el 20/09 (SQL `20260920041500` instalada y registrada; front `crm-20260920T062207Z-12230ee2ea0f`) | PR #42; puerta `crm.gestion_diaria_analista_fn` |
| F4 · Supervisor «Mi equipo hoy» | Tabla del equipo con tasa (chip solo con ≥ 5 llamadas útiles), llamadas por hora por analista, alertas del día | ⏭️ SIGUIENTE (su núcleo ya existe: `private.gestion_diaria_llamadas` acepta varios analistas) | plan §F4 |
| F5 · Gerencia «Toda la operación» | Pulso del día vs ayer y 7 días, por equipo, drill-down hasta el registro | pendiente | plan §F5 |
| F6 · Absorber Seguimiento | `#/seguimiento` → alias de `gestion-diaria`; retirar la vista vieja (cerrar → observar → derribar) | pendiente (tras ≥ 1 semana de F3–F5 en prod) | plan §F6 |

## Decisiones de Miguel que gobiernan (no re-preguntar)

1. «Hoy» se queda igual; Gestión Diaria es un módulo distinto (grupo Operación).
2. Cola del analista: lead nuevo sin primer intento primero, luego vencidas, luego las de hoy.
3. Plus Jakarta Sans sí; verde no (navy sobre fondo tenue para «Bien»).
4. «Contestó · no le interesa» descarta en la misma operación, con submotivo y Deshacer 24 h.
5. «Pide otro producto» también descarta (motivo `pide_credito`). Ambos caen en el Centro de rescate, reabribles por el supervisor.
6. Número errado / no es la persona: el analista decide (2.º número hoy · descartar por datos inválidos · reintento a 7 días · solo registrar). No entran en la tasa.
7. Tasa: el % siempre con el conteo al lado; chip y alerta solo con ≥ 5 llamadas útiles.
8. Supervisor y gerencia ven llamadas por rango de horas (08–20 Lima) por analista (F3/F4).
- Submotivos: sin fondos ahora → `sin_fondos` · ya invirtió con otro → `competencia` · desconfianza / no le interesa invertir / otro → `sin_interes` · préstamo / crédito / otro → `pide_credito`.
- Umbrales: Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 %; «sin llamadas» desde las 11:00; «parado» = 2 h sin llamar entre 09:00 y 18:00; «tasa muy baja» = 15 pp bajo el equipo.

## Lo que F2 dejó escrito (importa para F3)

- Quién registra: vendedor, supervisor y gerencia. El supervisor registra «volver a llamar» / «agendó cita» sin agendar; al dueño se le exige la tarea.
- Deshacer es una REAPERTURA (compone sobre `crm.reabrir_lead_fn`): ciclo nuevo, SLA reiniciado, el descarte queda en el ledger. `reunion_agendada` se restaura como `contactado`. «No insistir» no se deshace. La tarea que la llamada cerró no se reabre.
- Llamada útil (para la tasa) = resultado ∉ (`numero_errado`, `no_es_la_persona`); el histórico sin resultado cuenta como útil. Una llamada deshecha sigue contando; su descarte no.
- **Deudas para F3:** la lista blanca de `private.registro_actividad_core` (F1) no expone `deshecho_en` / `descartado` / `no_insista` → el registro muestra un resultado deshecho como vigente hasta que F3 amplíe la lista (exige re-sellar el md5 en `assert_gestion_diaria_registro`); el Centro de rescate no marca los descartes deshechos; el «Deshacer» solo vive 15 s en el toast (el servidor admite 24 h) → F3 lo ofrece en «Descartados hoy».
- Gate paraguas `private.assert_gestion_diaria()` = `_registro()` (F1) + `_resultado()` (F2); cada fase añade el suyo. Sella por md5 lo que compone: si otra sesión reescribe `reabrir_lead_fn`, `marcar_no_contactar`, `cerrar_tarea`, `sla_ejecutar_comando` o los triggers de leads, el gate se pone en rojo y hay que re-sellar a conciencia.

## Cómo retomar (receta)

1. **Tronco:** `avancecorp/main` (espejo del `main` local del taller). Fusionar siempre con merge commit; el preflight de deploy lee la ancestría. Antes de construir, fusionar; antes de publicar, `node _DEV_NO_SUBIR/deploy-hostinger-mcp.mjs preflight crm.miavance.com <zip>`.
2. **Worktree aparte** (el taller lo comparten varias sesiones): `git worktree add --detach /private/tmp/avancecorp-gd-f3 avancecorp/main`, enlazar `node_modules` (`ln -s` desde el taller para la raíz y `CRM-Avance-Corp/app`), y rama `gestion-diaria/f3-analista`. El release exige `VITE_SUPABASE_URL` y la clave pública anon en el entorno (públicas; el taller las tiene en su archivo de entorno).
3. **Banco local:** contenedor `supabase_db_avancecorp-f5-bank` (Docker Desktop tiene que estar reanudado). Plantilla a paridad: `conversion_inversion_base_20260919` + instalar en la copia `20260919185718`, `20260919211958`, `20260920005000` y `20260920014500` (todas ya en prod). Patrón de scripts: `supabase/scripts/gestion-diaria-resultado/` (banco.mjs, ensayar.mjs con sellado de md5 en dos pasadas, reversa.sql, oráculo por actor con leads creados por `crm.crear_lead_si_disponible`, generar-registrador.mjs).
4. **Servidor:** una migración por fase (`AAAAMMDDHHMMSS_crm_gestion_diaria_<tema>.sql`), preflight con md5 de lo vivo, postflight que llama solo a los 4 gates SLA verdes + el paraguas, censo analítico idéntico (sin `count(` ni `sum(1)`: usar `cardinality(array_agg())`). Instalación SOLO por Miguel con `!npx supabase db query --linked --file …` y luego el registrador generado.
5. **Front:** RPC nueva a mano en `app/src/lib/database.types.ts` (gen:types roto); SQL primero, front después; `npm run check:all` antes de la PR; `/release-crm` lo invoca Miguel.
6. **Revisiones (nivel 3):** Codex ×2 (arquitectura antes, diff después) + `auditor-rls` + `revisor-a11y` + refutadores. El MCP de Codex necesita `codex-cli 0.153.4` (la 0.155 quitó `mcp-server`); alternativa: `codex exec -s read-only … < /dev/null`.
7. **Trampas conocidas:** el hook de Bash bloquea comandos con `.env` o `*_KEY=` literales; los radios del panel llevan su descripción en el nombre accesible (Playwright: regex); un `div` envoltorio dentro de `Dialog` rompe el scroll del cuerpo (`flex min-h-0 flex-1 flex-col`); con un Sheet modal abierto los toasts no reciben clic sin la regla `[data-sonner-toaster]`.

## Pendiente de Miguel ahora

- **F3 COMPLETA EN PRODUCCIÓN el 20/09.** PR #42 fusionada por squash (`12230ee2`); el contenido llegó entero y
  `afc39197` —lo que estaba vivo— seguía siendo ancestro, así que el preflight no se rompió. SQL instalada y
  registrada (~01:19 Lima) y front publicado (`crm-20260920T062207Z-12230ee2ea0f`).
- **Prueba de negocio pendiente:** como analista, que el primer ítem de «Mi día» coincida con «Ahora» de Hoy.
- **Fusionar la PR #44** (saca del tronco el symlink `node_modules` que coló la rama de F3) y solo entonces integrar
  `avancecorp/main` en el `main` local: hasta que eso pase, el checkout intentaría escribir el symlink encima de la
  carpeta `node_modules` real del taller.
- Prueba de negocio de F2 en el CRM: una llamada real con «volver a llamar» crea la tarea en Agenda; «no le interesa» manda el lead al Centro de rescate con su motivo; «Deshacer» dentro de 24 h lo devuelve a su etapa.
- Prueba de negocio de F3: como analista, que el primer ítem de «Mi día» coincida con «Ahora» de Hoy.
- Fusionar la PR de acta #41.

## Lo que F3 dejó escrito (importa para F4)

- `private.gestion_diaria_llamadas(p_ini, p_fin, p_vendedor_ids)` ya acepta VARIOS analistas y devuelve una fila por cada uno: es el núcleo de la tabla del equipo. Los umbrales viven en `private.gestion_diaria_umbrales()` (F4 añadirá ahí «sin llamadas desde las 11:00», «parado 2 h» y «15 pp bajo el equipo», re-sellando su md5).
- `crm.equipo_visible_fn` NO filtra activos salvo en la rama «yo mismo», y para el lector global trae coordinación y directorio: quien lo use como autorización exige `ev.activo` y `ev.rol_crm`. Su cuerpo está sellado por md5 en el gate de F3.
- El nivel de la tasa se juzga con el valor SIN redondear; el % que se muestra sí va redondeado.
- `puede_deshacer` es falso cuando el actor no es el autor: el deshacer de F2 exige serlo. F4 no debe ofrecerlo por el analista.
- El marcador depende de quién mira tras una reasignación (la RLS acota por dueño actual del lead). F4 lo verá al correr como supervisor.
- El Sheet de la ficha es MODAL: deja inerte lo de atrás, así que un panel «global» no es alcanzable mientras está abierta (por eso `GuardadosSlaPendientes` conserva su copia dentro).

## Referencias

PRs: #29 (F0), #34 (F1), #38 (F2), #41 (acta F1+F2), #42 (F3). Migraciones: `20260919211958`, `20260920005000`, `20260920041500` (ledger `supabase/migrations/MIGRACIONES.md`). Vault: «Gestion Diaria - modulo nuevo y absorcion de Seguimiento 2026-09-19», «Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)» y «Gestion Diaria F3 - el dia del analista (2026-09-20)». Memoria de sesión: `gestion-diaria-plan-por-fases.md`, `gestion-diaria-f2-resultado-llamada.md` y `gestion-diaria-f3-analista.md`.
