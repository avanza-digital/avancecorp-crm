# ESTADO del módulo «Base para gestión del analista»

**Última sesión:** 03/10/2026 (sesión `93fde734`) · **Fase en curso:** servidor B1–B6 y front F1 (hoja + «Mes» + gris del supervisor) **EN PRODUCCIÓN desde el 03/10**; PR #177 para el tronco de GitHub. Sigue F2. F1 terminada en la rama del front (falta publicar). **Pedido nuevo de Miguel (03/10): «Bases cargadas»** — plan en `BASES-CARGADAS.md` (decisiones E1–E4 cerradas), fases B7–B10 + F5–F6 después de F2–F4.
**La base de datos está EN PRODUCCIÓN desde el 02/10, 20:15 Lima.** Miguel aplicó con `!` las 7 migraciones, cada una con
su registrador. Comprobado después, en solo lectura:
- las 7 en true y las 7 registradas con el md5 de su archivo;
- 0 intentos, reactivados, enfriados o rellamadas (los postflights deshicieron sus ensayos);
- las huellas de producción son idénticas a las de la rama;
- los advisors son iguales a los de la rama; nuevas solo las 4 WARN de las puertas.
Tipos regenerados desde producción en `9c1d7296` (typecheck PASS). Rama de Supabase borrada. Evidencia de la rama y el
gate en `revisiones/2026-10-02-rama-y-gate.md`.
**GitHub:** `main` local y `avancecorp/main` divergen (285 commits solo en local, entre ellos lo de Gloria, que NO sube;
28 solo en GitHub). No se hizo push: la integración va por una PR que decide Miguel.
**Frontend:** la rama `crm/base-gestion-front` nace del VIVO `44985828` (que NO está en `main` local: el tronco está partido, 52 commits del vivo faltan en `main`). Se publica desde esa rama con preflight y después se integra a `main` (decisión de Miguel sobre la carpeta sucia).
**Bloqueos:** ninguno.

| Fase | Estado | Evidencia / siguiente paso |
|---|---|---|
| F0 Reconocimiento | ☑ 01/10, re-verificado 02/10 | Nota del vault; 2 choques nuevos (D9 `origen` inmutable, D10 puerta v4 rechaza descartados) |
| D1–D13 Decisiones | ☑ 02/10 | Tabla en `README.md`; marcadas en FigJam |
| B1 Esquema `20261002054402` | ☑ EN PRODUCCIÓN 02/10 | Banco, auditor-rls, Codex, rama, gate, merge y registro (ledger) |
| B1b Rellamada `20261002224851` | ☑ EN PRODUCCIÓN 02/10 | «Llamar hoy» usa `idx_leads_base_rellamada` (0,05 ms con datos reales) |
| B2 Permisos `20261002061500` | ☑ EN PRODUCCIÓN 02/10 | `#5 B2` en verde en el gate |
| B3 Puertas `20261002231436` | ☑ EN PRODUCCIÓN 02/10 | Con datos reales: analista 73 ms, gerencia 78 ms (1069 filas), supervisores ≤ 137 ms |
| B4 Enfriamiento `20261002233851` | ☑ EN PRODUCCIÓN 02/10 | Aplicado fuera de horario; ensayo deshecho (0 enfriados) |
| B4b Ventana (D13) `20261002235342` | ☑ EN PRODUCCIÓN 02/10 | |
| B3b Codex `20261003001014` | ☑ EN PRODUCCIÓN 02/10 | Punto (a) de Codex r2 acreditado: «intentos previos 0» antes de aplicar |
| Merge de Miguel | ☑ 02/10 20:15 | 7/7 `OK`; huellas de producción = rama; tipos `9c1d7296`; rama borrada |
| F1 Vista analista | ☑ EN PRODUCCIÓN 03/10 (17:10 Lima) | Rama `crm/base-gestion-front` (nace del vivo `44985828`): `c11a8840` tipos · `7231672e` F1 · `becbd7ea` a11y · `8570cdfb` hoja + helpers del mes · **`c9e772fd` columna «Mes» (3.ª, tras Lead) + selector «Mes: Todos (N) · Agosto 2026 (n)…»**; el # de fila, las pastillas y el título de la tabla cuentan lo filtrado; sin `recibido_en` (antes de B5) no hay ni columna ni selector (prueba «ESTADO DE PRODUCCIÓN»). `revisor-a11y`: APPROVE con 5 P3, aplicados. `npm run check` PASS (5623) |
| **B3c Fuera del censo** `20261003162300` | ☑ EN PRODUCCIÓN 03/10 (~14:30) | 🔴 Producción abre una alerta diaria desde el 02/10: el censo analítico marca 4 funciones del módulo sin declarar (leído en prod el 03/10). Sus conteos de intentos pasan a `private.base_gestion_intentos_ciclo` (una sola definición) y el resumen cuenta la lista de `obtener_base_gestion`; nueva `private.base_gestion_leads_de` (solo predicado). Postflight: el censo pierde EXACTAMENTE las 4. Banco: B2 25/25 · B3 48/48 · B4 17/17; mutante → FALLA. OK de Miguel 03/10 |
| **B5 Mes del lead** `20261003162400` | ☑ EN PRODUCCIÓN 03/10 (~14:30) | `recibido_en = coalesce(tenencia_desde, creado_en)` al final de `obtener_base_gestion` (drop + create sobre B3c). Fuera del censo |
| **B6 Seguimiento activo** `20261003162500` | ☑ EN PRODUCCIÓN 03/10 (~14:30) · pantalla lista sin publicar | Decisiones de Miguel (03/10): rellamada vigente cuenta · EN GRIS en el rescate · **candado en el LEAD para toda vía** (rescate, ficha, «tomar lead libre»; el auditor y el banco probaron que la ficha lo saltaba). Trigger `trg_leads_00_seguimiento_activo` + regla única `private.base_gestion_en_gestion_hasta` (una baja libera; rellamada de otro ciclo no cuenta). `rescatar_descartes` NO se toca (huella en el censo). Límite aceptado: devolverlo a su MISMO analista pasa. Mutantes → FALLAN. Pantalla del supervisor `5475be81` |
| Paquete B3c → B5 → B6 | ☑ EN PRODUCCIÓN 03/10 (~14:30) | Miguel con `!`: las 3 migraciones y sus 3 registradores, en orden. Comprobado en solo lectura tras cada una: huellas = las del gate, ACL exacta, trigger habilitado, censo en rojo SOLO por `gestion_diaria_cola_hechos` (otra sesión; 42 → 38), 0 leads en gestión (aún no hay intentos), 3 registradas con el md5 de su archivo. Tipos regenerados desde producción: rama del front `390e21bc` y `main` `083b0c57` (check PASS). Evidencia de la revisión, la rama y el gate: `revisiones/2026-10-03-*.md`. **Front publicado 03/10 17:10 Lima** (`/release-crm` de Miguel): `build-20261003T221026768Z`, commit `c489d487` (rama `crm/base-gestion-front-sobre-vivo-20261003` = vivo `8db0d4f1` + nuestras pantallas + tipos; respaldo en GitHub `rescue/base-gestion-front-20261003`). Preflight OK, smoke OK (index-*.js idéntico). E2E 322/2/26: los 2 rojos fallan también en `8db0d4f1` (previos). **PR #177** contra `avancecorp/main` (rearmada sobre `00a482a3`): la fusiona Miguel por squash. **Sigue:** F2 |
| F2 Ficha | ☐ | Historial completo y legible con buscador; formulario de intento (7 resultados, fecha en «volver a llamar»); Reactivar (confirmación, idempotente); No contactar con motivo |
| F3 Organización | ☐ | «Llamar hoy» arriba; filtros por motivo, etapa máxima y último resultado; contador de intentos |
| F4 Supervisor | ☐ (plan en `FRONTEND.md`; la migración «ver vetados» —en `FRONTEND.md` se llamaba «B5», NO es la B5 del mes— pendiente de OK) | Columnas Intentos · Último resultado · Gestiona; quitar «no contactar» (D5); reactivaciones por analista. Gerencia recibe 1069 filas: filtrar por analista o paginar |
| **B7–B10 Bases cargadas** (servidor) | ☐ plan 03/10, decisiones E1–E4 cerradas | Esquema de bases + carga desde archivo o desde el CRM (duplicados se saltan y se informan) + reparto por cantidades o individual + seguimiento por analista. Detalle en `BASES-CARGADAS.md` |
| **F5–F6 Bases cargadas** (pantalla) | ☐ plan 03/10 | F5 pantalla «Bases» del supervisor (cargar, repartir «Ana 40 · Luis 30», seguimiento, recoger); F6 columna y selector «Base» del analista. Bocetos en FigJam (sección `28:2`) |
| QA final | ☐ | Los 9 puntos del encargo + `npm run check` + `test:rls` + E2E Docker |

## Cómo actualizar este archivo
Al cerrar cada paso: cambia el estado (☐ → ◉ → ☑), escribe la evidencia (qué se corrió y si dio PASS, FAIL o NOT RUN) y el
siguiente paso concreto. Actualiza también la línea «Última sesión» y la nota del vault. No marques ☑ sin evidencia.

## Cómo continuar — en este orden

**Ahora:** (a) que Miguel fusione la PR #177; (b) F2 (la ficha). 🔴 El VIVO del CRM es `c489d487` (03/10 17:10): la próxima publicación debe contenerlo. El scratchpad del stack del gate del 02/10 ya no existe: quedan sus volúmenes Docker (`supabase_db_avancecorp-base-gestion-20261002`), hay que recrear su `config.toml` con el mismo `project_id` y puertos 569xx. (b) F2. (c) Después de F2–F4: Bases cargadas (B7–B10 + F5–F6), plan en `BASES-CARGADAS.md`.

0. Lee `README.md` de esta carpeta, `FRONTEND.md` y la nota del vault. El código se toca en un worktree propio, nunca en
   la carpeta compartida (regla de Miguel). A `main` solo llegan commits parciales, con `git commit -- <rutas>` o con
   índice temporal si el archivo tiene líneas ajenas.
1. Frontend F1 → F4 según `FRONTEND.md`. En cada fase: ejecutar, verificar (vitest, `revisor-a11y`, typecheck/lint y E2E
   Docker cuando toque) y reportar. Pedir OK para la B5 «ver vetados» al llegar a F4.
2. Publicar el front con preflight (`/release-crm`, lo invoca Miguel). Después, la PR de integración con GitHub sin lo de
   Gloria, si Miguel la pide.
3. Al cerrar la QA: borrar esta carpeta (el conocimiento vive en el vault) y actualizar el tablero FigJam.
