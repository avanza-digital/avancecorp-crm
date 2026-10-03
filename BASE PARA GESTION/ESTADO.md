# ESTADO del módulo «Base para gestión del analista»

**Última sesión:** 02/10/2026, noche (sesión `119d2a01`) · **Fase en curso:** MERGE DE MIGUEL en producción. La rama con
datos tiene las 7 migraciones aplicadas. El EXPLAIN con datos reales no da SEQ SCAN, así que **la B5 de índice NO hace
falta**. Los advisors no dan alertas nuevas, salvo las 4 WARN del patrón por diseño. El gate de RLS completo corrió en un
banco Docker propio, a paridad total con producción: base para gestión 74/74 y A/B sin rojos nuevos. El gate cazó 2
expectativas viejas del test; quedan corregidas en `72189f04`. Los registradores del historial están listos y probados.
Evidencia completa: `revisiones/2026-10-02-rama-y-gate.md`. Producción, leída el 02/10 a las 20:10: ninguna de las 7
aplicada ni registrada, última versión `20261002163158` (la misma de la rama).
**Sin contraseña de BD:** todo fue por la Management API: `supabase db query | db advisors | db dump --linked --project-ref
dpjojnpfcwkeikyagtxj --workdir <carpeta aparte cuyo supabase/.temp/project-ref es la rama>`. La carpeta compartida sigue
enlazada a producción y no se toca. `rama.mjs` (psql) solo hace falta para correr el gate EN la rama; por decisión de Miguel
(02/10) el gate se corre en Docker.
**Bloqueos:** ninguno técnico. El merge lo lanza Miguel con `!`: el clasificador no deja a Claude aplicar en producción ni
preparar scripts que lo hagan.
**Nada en producción.** Siguientes commits: `git log --oneline -- "BASE PARA GESTION" CRM-Avance-Corp/supabase/scripts/base-gestion`.

| Fase | Estado | Evidencia / siguiente paso |
|---|---|---|
| F0 Reconocimiento | ☑ 01/10, re-verificado 02/10 | Nota del vault; 2 choques nuevos (D9 `origen` inmutable, D10 puerta v4 rechaza descartados) |
| D1–D13 Decisiones | ☑ 02/10 | Tabla en `README.md`; marcadas en FigJam |
| **B1 Esquema** `20261002054402` | ◉ rama ✓ · gate ✓ | Banco sintético, auditor-rls y Codex (ledger). Rama 02/10: aplicada; EXPLAIN con índices. **Siguiente:** merge |
| **B1b Rellamada** `20261002224851` | ◉ rama ✓ · gate ✓ | `idx_leads_base_rellamada` usado en «llamar hoy» (0,05 ms). **Siguiente:** merge |
| **B2 Permisos** `20261002061500` | ◉ rama ✓ · gate ✓ | `#5 B2` en verde en el gate. Sin B2 da 9 rojos, como se esperaba. **Siguiente:** merge |
| **B3 Puertas** `20261002231436` | ◉ rama ✓ · gate ✓ | Puertas con datos reales: analista 73 ms, gerencia 78 ms (1069 filas), supervisores ≤ 137 ms. **Siguiente:** merge |
| **B4 Enfriamiento** `20261002233851` | ◉ rama ✓ · gate ✓ | Postflight con ensayo deshecho (0 enfriados tras aplicar). **Siguiente:** merge FUERA de horario de gestión |
| **B4b Ventana (D13)** `20261002235342` | ◉ rama ✓ · gate ✓ | **Siguiente:** merge |
| **B3b Codex** `20261003001014` | ◉ rama ✓ · gate ✓ | Punto (a) de Codex r2 acreditado: «intentos previos: 0» en la rama antes de aplicar. **Siguiente:** merge |
| merge de Miguel | ☐ **siguiente** | Pasos 1–2 de «Cómo continuar» |
| F1 Vista analista | ☐ (plan en `FRONTEND.md`) | `#/rescate` despacha por rol (como `gestion-diaria`); el analista ve una lista plana por `obtener_base_gestion()` |
| F2 Ficha | ☐ | Historial completo y legible con buscador; formulario de intento (7 resultados, fecha en «volver a llamar»); Reactivar (confirmación, idempotente); No contactar con motivo |
| F3 Organización | ☐ | «Llamar hoy» arriba; filtros por motivo, etapa máxima y último resultado; contador de intentos |
| F4 Supervisor | ☐ (plan en `FRONTEND.md`; B5 «ver vetados» pendiente de OK) | Columnas Intentos · Último resultado · Gestiona; quitar «no contactar» (D5); reactivaciones por analista. Gerencia recibe 1069 filas: filtrar por analista o paginar |
| QA final | ☐ | Los 9 puntos del encargo + `npm run check` + `test:rls` + E2E Docker |

## Cómo actualizar este archivo
Al cerrar cada paso: cambia el estado (☐ → ◉ → ☑), escribe la evidencia (qué se corrió y si dio PASS, FAIL o NOT RUN) y el
siguiente paso concreto. Actualiza también la línea «Última sesión» y la nota del vault. No marques ☑ sin evidencia.

## Cómo continuar — en este orden

0. Lee `README.md` de esta carpeta, `FRONTEND.md`, la nota del vault y `revisiones/2026-10-02-rama-y-gate.md`. Trabaja desde `main`.
1. **Merge de Miguel** (producción, con `!`, fuera del horario de gestión). Se lanza desde `CRM-Avance-Corp/`, enlazada a
   producción. Orden: B1 `20261002054402` → B1b `20261002224851` → B2 `20261002061500` → B3 `20261002231436` →
   B4 `20261002233851` → B4b `20261002235342` → B3b `20261003001014`. Por cada una:
   `supabase db query --linked --file supabase/migrations/<archivo>.sql`, y justo después su registrador:
   `supabase db query --linked --file supabase/scripts/base-gestion/registrar/<version>.sql`.
   Hay que parar en el primer fallo: la migración que falla se deshace sola, porque cada archivo es su propia transacción.
   Antes de lanzar, Claude relee el estado de producción (solo lectura): no debe haber ninguna de las 7 aplicada ni
   registrada, y el md5 de cada archivo debe ser el ensayado (están en la cabecera de cada registrador).
2. Después del merge, Claude:
   - relee el estado de producción: las 7 en true y 7 registradas;
   - corre los advisors de producción;
   - corre `gen:types` en un worktree (en la carpeta compartida `database.types.ts` tiene cambios ajenos) y hace el commit;
   - `git push avancecorp main`;
   - borra la rama: `supabase branches delete base-gestion-datos-20261002 --project-ref dctqcbznekcyxhjujuci`;
   - para el stack Docker propio (`avancecorp-base-gestion-20261002`) y retira el worktree
     `AVANCECORP-desktop-worktrees/base-gestion-gate-20261002`.
3. Ledger («APLICADA Y REGISTRADA EN PRODUCCIÓN …»), esta carpeta, la nota del vault y el tablero FigJam (B1..B3b → ☑).
4. Frontend F1 → F4 según `FRONTEND.md`; en cada fase: ejecutar, verificar y reportar. Pedir OK para la B5 «ver vetados» al
   llegar a F4.
