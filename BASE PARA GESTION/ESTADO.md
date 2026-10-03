# ESTADO del módulo «Base para gestión del analista»

**TRASPASO (03/10/2026):** Miguel pasa el módulo a una sesión que tiene la contraseña de BD de la rama/producción. Esta sesión (id `251c677b-7a2b-4135-bb20-db2eff4659c2`) deja todo commiteado en `main` local; la siguiente retoma por la sección «Cómo continuar» de abajo.

**Última sesión:** 03/10/2026 · **Fase en curso:** B3 (puertas) escrita y ensayada en banco (40/40); B3 auditada y corregida; B4 auditada; B4b (D13: tres intentos nuevos tras cada descanso) escrita y verde (17/17). Codex B3+B4 BLOCK → enmiendas en B3b `20261003001014` (48/48). **Codex r2 (03/10) BLOCK con 2 P2, RESUELTOS sin código (ledger):** (a) replays de operaciones anteriores a B3b no llevarían `solicitud_proxima`/`nota_md5` → 23505: NO aplica fuera del banco (B3/B4b nunca se aplicaron en rama ni prod; acreditarlo en el ledger al retomar); (b) #6 sigue parcial (empates de instante solo sintéticos; aceptado como limitación o acotar el ciclo por `lead_asignaciones.ciclo_n`). Informe en `revisiones/2026-10-03-codex-b3b.md`. **Sigue:** rama (URL de Miguel) → `rama.mjs estado | aplicar | explain | gate` → advisors → merge (B4 fuera de horario). Rama con datos `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`) creándose (RESTORING). Sigue: auditor-rls B1b → aplicar B1/B1b/B2 en la rama → test-rls → advisors → merge.
**Bloqueos:** (1) **Rama con datos `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`, `--with-data`, ACTIVE_HEALTHY):** hereda la contraseña de BD de producción y la CLI la enmascara; `supabase db query --project-ref` solo sirve para el proyecto enlazado (no se cambia el link de la carpeta compartida). **Miguel debe dejar la URL del pooler en modo sesión** (`postgresql://postgres.dpjojnpfcwkeikyagtxj:<contraseña>@aws-0-us-east-2.pooler.supabase.com:5432/postgres`) en `~/.config/avancecorp/rama-base-gestion.pgurl` (chmod 600) o exportar `CRM_RAMA_DB_URL`; luego `node supabase/scripts/base-gestion/rama.mjs estado | aplicar | explain | gate` (el `gate` TRUNCA leads/actividades/tareas del clon: correr `explain` antes). La rama vacía `base-gestion-20261002` se borró (replay 86/400). Borrar la rama con datos al terminar; (2) D7-bis RESUELTA (agenda propia de la base, B1b `20261002224851`); D11 = rellamada máx. 10 días; D12 = gana la rellamada al enfriamiento.
**Nada en producción. Último commit del módulo:** `4cbd3806` (02/10, main local, sin push). Siguientes: `git log --oneline -- "BASE PARA GESTION"`.

| Fase | Estado | Evidencia / siguiente paso |
|---|---|---|
| F0 Reconocimiento | ☑ 01/10, re-verificado 02/10 | Nota del vault; 2 choques nuevos (D9 `origen` inmutable, D10 puerta v4 rechaza descartados) |
| D1–D10 Decisiones | ☑ 02/10 | Tabla en `README.md`; marcadas en FigJam |
| **B1 Esquema** | **◉ local listo** | Migración `20261002054402`, banco PASS (aplicar + 5 negativos, test 12/12, reversa-y-reaplicar), `auditor-rls` con P1/P2 corregidos, typecheck/check:scripts/rls-preflight PASS. **Siguiente:** rama → aplicar → `test-rls.mjs` (`CRM_RLS_EXIGE_BASE_GESTION=1`) → advisors (y EXPLAIN con datos reales: ¿hace falta índice parcial `where etapa='descartado'`?) → merge |
| **B1b Rellamada en el lead** | ◉ local listo | Migración `20261002224851`: `proxima_llamada_en` sellada (sello de 3 columnas), CHECK con fecha ISO en `volver_a_llamar`, constantes (3, 30, 10), índice parcial. Banco: aplicar + postflight, `test`, `reversa-y-reaplicar-b1b` PASS; typecheck PASS. **Pendiente:** auditor-rls B1b, rama |
| B2 Permisos | ◉ local listo + revisado | **Sin migración de RLS**: la RLS vigente ya limita al analista a sus leads/actividades/tareas (demostrado con `b2-rls.sql`, 20/20 PASS bajo rol con impersonación). **Migración `20261002061500`** (D5): `levantar_no_contactar` para Gerencia o Supervisión en su ámbito (todos los leads de la persona en su equipo; si no, 42501 «pídelo a Gerencia»); historial con rol. Banco: `fixtures-b2`, `aplicar-b2`, `reversa-y-reaplicar-b2` PASS; `paridad-acl` copia la ACL del stack local (correr ANTES de aplicar). `test-rls.mjs`: 7 casos nuevos (#5 B2). check:scripts y rls-preflight PASS. auditor-rls (CHANGES_REQUESTED) y Codex (BLOCK, P1 real de semántica NULL) → corregidos: `is not true`, `activo`, reversa con guarda, fixtures de persona real, `b2-rls.sql` estricto 25/25, negativos de roles en test-rls. Informes en `revisiones/`. **Pendiente:** rama usable → aplicar B1+B2 → `test-rls.mjs` → advisors → merge |
| B3 Puertas | ◉ local listo + revisado | Migración `20261002231436` (auditor-rls aplicado: sello de actividades, candados persona→lead, replay tras candado, resumen por dueño): `obtener_base_gestion(p_vendedor_id)`, `registrar_intento_base`, `reactivar_lead_base`, `base_gestion_resumen` + núcleos y ayudantes. Banco: aplicar + postflight, `b3-puertas.sql` 43/43, `reversa-y-reaplicar-b3` PASS; test-rls con bloque API. **Pendiente:** Codex B3+B4, rama. Diseño previsto: `crm.obtener_base_gestion()`, `crm.registrar_intento_base(...)` + núcleo nuevo (2 GUC; escribe `proxima_llamada_en` ≤ 10 días en `volver_a_llamar`, la consume el siguiente intento, la limpian reactivar/vetar; D12: la rellamada gana al enfriamiento), `crm.reactivar_lead_base(...)` sobre `reabrir_lead_fn` + avance a `contactado` (D1), reuso de `marcar_no_contactar`/`levantar_no_contactar`. Probar con analista y supervisor en la rama |
| B4 Trigger de enfriamiento | ◉ local listo + revisado | Migración `20261002233851`: AFTER INSERT (WHEN `intento_base`); 3.º intento sin rellamada ni cita → `enfriado_hasta = hoy Lima + 30` bajo el sello; D12 respetada. Banco: postflight con ensayo deshecho, `b4-enfriamiento.sql` 15/15 con fechas simuladas, `reversa-y-reaplicar-b4` PASS; b3 ajustado 44/44; test-rls con casos B4 y D12. auditor-rls aplicado (gate por GUC). **B4b `20261002235342` (D13):** ventana de intentos desde el fin del último descanso; 17/17; `reversa-y-reaplicar-b4b` PASS. **B3b `20261003001014` (Codex):** replay antes de lo temporal, identidad con fecha y nota, hija con uuid nuevo, orden del contrato, desempates; b3 48/48. **Pendiente:** Codex r2, rama |
| merge de Miguel | ☐ | Tras B4 |
| F1 Vista analista | ☐ (plan en `FRONTEND.md`) | `#/rescate` despacha por rol (como `gestion-diaria`); analista → lista plana por `obtener_base_gestion()` |
| F2 Ficha | ☐ | Historial completo legible + buscador; formulario de intento (7 resultados; fecha en volver a llamar); Reactivar (confirmación, idempotente); No contactar con motivo |
| F3 Organización | ☐ | «Llamar hoy» arriba; filtros motivo/etapa máxima/último resultado; contador de intentos |
| F4 Supervisor | ☐ (plan en `FRONTEND.md`; B5 pendiente de OK: ver vetados para quitar la marca) | Columnas Intentos · Último resultado · Gestiona; quitar «no contactar» (D5); indicador de reactivaciones por analista |
| QA final | ☐ | 9 puntos del encargo + `npm run check` + `test:rls` + E2E Docker |

## Cómo actualizar este archivo
Al cerrar cada paso: cambia el estado (☐ → ◉ → ☑), escribe la evidencia (qué se corrió y resultado PASS/FAIL/NOT RUN) y el
siguiente paso concreto. Actualiza también la línea «Última sesión» y la nota del vault. No marques ☑ sin evidencia.

## Cómo continuar (para la sesión que tiene la clave) — en este orden

0. Lee `README.md` de esta carpeta, `FRONTEND.md` y la nota del vault. Comprueba `git log --oneline -12` (último commit del
   módulo: ver abajo) y que estás en `main`. Docker encendido si quieres repetir el banco (`banco.mjs …`, opcional).
1. **Credencial de la rama** `base-gestion-datos-20261002` (ref `dpjojnpfcwkeikyagtxj`, copia de producción con datos):
   crea `~/.config/avancecorp/rama-base-gestion.pgurl` (chmod 600) con
   `postgresql://postgres.dpjojnpfcwkeikyagtxj:<CONTRASEÑA>@aws-0-us-east-2.pooler.supabase.com:5432/postgres`
   (o exporta `CRM_RAMA_DB_URL`). Nunca inline en un comando (el hook lo bloquea). Si la rama no existe ya
   (`supabase branches list --project-ref dctqcbznekcyxhjujuci`), créala: `supabase branches create base-gestion-datos-<fecha>
   --project-ref dctqcbznekcyxhjujuci --region us-east-2 --size micro --with-data` y actualiza `RAMA` en `rama.mjs`.
2. `node supabase/scripts/base-gestion/rama.mjs estado` (desde `CRM-Avance-Corp`) → debe decir B1..B3b false e
   «intentos previos: 0» (acredita el punto (a) de Codex r2).
3. `node supabase/scripts/base-gestion/rama.mjs aplicar` → aplica en orden B1, B1b, B2, B3, B4, B4b, B3b (un mensaje cada
   una, como `supabase db query --file`). Si una falla, el NOTICE/ERROR dice cuál; las reversas están en
   `supabase/scripts/base-gestion/reversa-*.sql` (orden: B3b, B4b, B4, B3, B2, B1b, B1).
4. `node supabase/scripts/base-gestion/rama.mjs explain` → con datos reales: si «base por analista» o «llamar hoy» salen
   SEQ SCAN, añadir índice parcial `where etapa = 'descartado'` en una migración B5 y anotarlo.
5. `CRM_RAMA_LOG=/ruta/log node supabase/scripts/base-gestion/rama.mjs gate` → gate completo de RLS (`test-rls.mjs` con
   `CRM_RLS_EXIGE_BASE_GESTION=1`). ⚠️ TRUNCA leads/actividades/tareas del clon (siembra sus fixtures): por eso va después
   del EXPLAIN. Los bloques nuevos: `testBaseGestionB1` (sello, B1b), `testBaseGestionB3` (puertas, B4, D12) y los casos
   `#5 B2` (Supervisión levanta «no contactar»).
6. Advisors de Supabase (seguridad y rendimiento) en la rama: sin alertas nuevas respecto a producción. Anotar en el ledger.
7. **Merge de Miguel** (producción, con `!`): `supabase db query --linked --file <migración>` en el orden del punto 3; B4
   fuera del horario de gestión (su postflight toma un candado breve sobre un lead real). Después, los registradores del
   historial si el proyecto los exige (ver precedentes en `MIGRACIONES.md`), `npm run gen:types` en `app/` (quitar las
   líneas a mano de `database.types.ts` si difieren), commit, `git push avancecorp main`. Borrar la rama con datos
   (`supabase branches delete …`).
8. Actualizar `MIGRACIONES.md` («APLICADA Y REGISTRADA EN PRODUCCIÓN …»), esta carpeta, la nota del vault y el tablero
   FigJam (B1..B3b → ☑).
9. Frontend: F1 → F4 según `FRONTEND.md` (cada fase: ejecutar, verificar, reportar). Pedir OK para B5 al llegar a F4.
