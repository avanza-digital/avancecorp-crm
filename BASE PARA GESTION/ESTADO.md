# ESTADO del módulo «Base para gestión del analista»

**Última sesión:** 02/10/2026, noche (sesión `119d2a01`) · **Fase en curso:** FRONTEND — F1 ☑ (en la rama); sigue F2 (ficha) con el OK de Miguel.
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
| F1 Vista analista | ☑ 02/10 (en la rama, sin publicar) | Rama `crm/base-gestion-front` (nace del vivo `44985828`): `c11a8840` tipos · `7231672e` F1 · `becbd7ea` a11y. `#/rescate` despacha por rol; analista → resumen + tabla (escritorio) o tarjetas `role=list` (celular), «Llamar» con `enlaceTel()` (tel: en celular, copiar en laptop), refresco fallido conserva los datos. `revisor-a11y` CHANGES_REQUESTED (2 P2 + 3 P3) → aplicado. `npm run check` PASS (5619). Capturas demo 1440/390/320 px sin desborde ni errores |
| F2 Ficha | ☐ | Historial completo y legible con buscador; formulario de intento (7 resultados, fecha en «volver a llamar»); Reactivar (confirmación, idempotente); No contactar con motivo |
| F3 Organización | ☐ | «Llamar hoy» arriba; filtros por motivo, etapa máxima y último resultado; contador de intentos |
| F4 Supervisor | ☐ (plan en `FRONTEND.md`; B5 «ver vetados» pendiente de OK) | Columnas Intentos · Último resultado · Gestiona; quitar «no contactar» (D5); reactivaciones por analista. Gerencia recibe 1069 filas: filtrar por analista o paginar |
| QA final | ☐ | Los 9 puntos del encargo + `npm run check` + `test:rls` + E2E Docker |

## Cómo actualizar este archivo
Al cerrar cada paso: cambia el estado (☐ → ◉ → ☑), escribe la evidencia (qué se corrió y si dio PASS, FAIL o NOT RUN) y el
siguiente paso concreto. Actualiza también la línea «Última sesión» y la nota del vault. No marques ☑ sin evidencia.

## Cómo continuar — en este orden

0. Lee `README.md` de esta carpeta, `FRONTEND.md` y la nota del vault. El código se toca en un worktree propio, nunca en
   la carpeta compartida (regla de Miguel). A `main` solo llegan commits parciales, con `git commit -- <rutas>` o con
   índice temporal si el archivo tiene líneas ajenas.
1. Frontend F1 → F4 según `FRONTEND.md`. En cada fase: ejecutar, verificar (vitest, `revisor-a11y`, typecheck/lint y E2E
   Docker cuando toque) y reportar. Pedir OK para la B5 «ver vetados» al llegar a F4.
2. Publicar el front con preflight (`/release-crm`, lo invoca Miguel). Después, la PR de integración con GitHub sin lo de
   Gloria, si Miguel la pide.
3. Al cerrar la QA: borrar esta carpeta (el conocimiento vive en el vault) y actualizar el tablero FigJam.
