VERDICT:
CHANGES_REQUESTED

SUMMARY:
Los dos SQL de producto fallan de forma cerrada y no encontré defectos nuevos de corrección en ellos dentro de lo adjuntado. `premerge.mjs` verifica bien la paridad catálogo/ledger/Edge entre padre y banco. Sin embargo, no verifica lo que efectivamente se fusiona, que es el contenido git de la rama. Tampoco ata los resultados de los gates al commit ni a las migraciones que aprueban. Además, una de sus referencias de producción no tiene control de frescura. Ninguno de estos puntos es P0. Algunos sí permiten que se fusionen cambios ajenos o que se haga un merge con evidencia caducada. No declaro el gate HTTP: sigue corriendo.

FINDINGS:

[P1] El premerge no comprueba qué contiene la rama que se fusiona
File: `supabase/scripts/incidencias-20261013/remoto/premerge.mjs`
Lines: todo el script (no hay ninguna lectura de git)
Problem: todas las aserciones comparan padre contra banco (catálogo, extra, F7, Edge). Ninguna compara `main...HEAD`.
Evidence:
- El historial reciente incluye merges de otras ramas (`6cffe735`, `df328cde` "Merge branch 'main' into rescate/...").
- La rama `crm/corregir-f7-sesion-rendimiento-20261013` parte de `bd59d35d`.
- `git status` muestra `?? .../remoto/` sin trackear, así que un `git add` de la carpeta la incorpora entera.
- `assert.equal(p.nuevas,null)` solo detecta migraciones nuevas ya aplicadas en producción. No detecta migraciones de otro agente presentes en `main` o en la rama y aún no aplicadas.
Impact: el merge podría transportar archivos de otro trabajo, como migraciones, Edge en `supabase/functions/**`, `config.toml` o frontend. Todo el aparato de paridad pasaría igualmente en verde. Es exactamente el riesgo que pediste detectar.
Recommendation: añadir al premerge, o como paso obligatorio previo, estas comprobaciones:
- `git fetch` seguido de exigir `merge-base HEAD origin/main == origin/main`, o que el rebase esté reciente.
- `git diff --name-only origin/main...HEAD` contra una allowlist explícita: las dos migraciones, `remoto/*.mjs|.sql|LEEME.md`, el informe y los archivos de app/tests ya revisados.
- `git ls-files supabase/migrations` comparado con `main` más exactamente esas dos.
- Si CI despliega Edge al fusionar, ningún cambio bajo `supabase/functions/`.

[P2] Los resultados de gate no están atados al commit ni a las huellas de migración
File: `premerge.mjs`
Lines: `for(const f of ['gate-http-estado.json','sql-resultados.json'])assert.equal(json(f).estado,'PASS',f);`
Problem: solo se exige `estado:'PASS'`. No se controla frescura (a diferencia de las capturas `*-premerge.json`), ni el SHA de HEAD, ni las huellas `c9385202…`/`1766dbb1…` con que corrió el gate.
Evidence:
- El primer gate HTTP falló (`Bucket not found`) y se repitió tras restaurar el fixture.
- Si cualquier corrida previa o parcial dejó `PASS` en ese archivo, o si la rama recibe otro commit después del gate, el premerge lo aceptaría.
Impact: un merge con evidencia de un estado anterior de código o de banco.
Recommendation: que `gate-http.mjs` y `probar-sql.mjs` escriban en su JSON `git rev-parse HEAD`, el hash de los dos archivos de migración y `b.nuevas[].huella`. Que `premerge.mjs` los compare con el HEAD actual y con `b.nuevas`. Rechazar si HEAD cambió después del gate.

[P2] La referencia F7 de producción no tiene control de frescura
File: `premerge.mjs`
Lines: `const f7base=json('produccion-controles.json')...`
Problem: `produccion-controles.json` no está en la lista de capturas de menos de 60 s. El catálogo (`estructura`) cubre la estructura, pero según lo mostrado no incluye las filas de `private.f7_piezas_en_observacion`.
Evidence: la lista de frescura cubre solo `produccion-catalogo-premerge.json`, `produccion-extra-premerge.json` y `edge-premerge.json`.
Impact: si producción añade o redeclara una pieza F7 entre la captura y el merge, el premerge compara el banco contra una foto vieja y pasa. Producción sí está protegida en el momento de aplicar, porque el preflight de la migración F7 exige la huella vieja exacta y ninguna otra deriva. El problema es que el merge quedaría hecho con una afirmación de paridad falsa.
Recommendation: capturar `produccion-controles-premerge.json` en la misma ventana y añadirlo al bucle de frescura. O incluir las filas F7 en `produccion-extra-premerge`.

[P2] Las versiones del ledger del banco difieren de los nombres de archivo del repo (hipótesis sobre el despliegue)
File: `supabase/migrations/20261014001044_…sql`, `supabase/migrations/20261014001346_…sql`; `premerge.mjs` (`b.nuevas` con `20261014013757` / `20261014013830`); `LEEME.md` ("no se renombran ni editan")
Problem: el banco registró versiones distintas de los nombres de archivo. Si producción se aplica por MCP, recibirá una tercera pareja de versiones.
Evidence: las versiones del bloque `b.nuevas` frente a los prefijos de archivo.
Impact: `supabase migration list` o `db push` contra cualquiera de los proyectos verá las migraciones del repo como pendientes, con riesgo de reaplicación. La F7 fallaría cerrada en su preflight. La SLA también fallaría cerrada, porque la definición previa ya no coincide. Por tanto no hay daño de datos, pero sí deriva de ledger y ruido operativo. Desconozco si los 473 registros ya siguen esa convención (MCP con versión distinta del archivo).
Recommendation: documentar en el informe el mapeo archivo→versión del banco y fijar cómo se registrará en producción. Si la convención del repo exige igualdad, aplicar en producción con la versión del nombre de archivo.

[P2] Riesgo de commitear capturas privadas (hipótesis)
File: `remoto/` (sin trackear), `banco.mjs` (`carpeta`)
Problem: el valor de `carpeta` no se adjuntó. El script escribe `premerge.json` en `carpeta` y lee `produccion-*.json`, que contienen ACL, catálogo y ledger de producción.
Evidence: el `LEEME.md` afirma que estos archivos están "fuera del repositorio", pero `remoto/` aparece completo como `??`.
Impact: si `carpeta` resuelve dentro del árbol, un `git add` de la carpeta publica capturas productivas.
Recommendation: que el premerge, o el script de captura, haga `assert` de que `carpeta` está fuera de `git rev-parse --show-toplevel`. Añadir los patrones a `.gitignore` y revisar `git status` antes de commitear.

[P3] La lista de normalizaciones no tiene cota
File: `premerge.mjs`
Lines: bucle `normalizaciones`
Problem: se acepta cualquier entrada de `paridad-esquema.json`. El LEEME habla de exactamente 3 CHECK.
Recommendation: `assert.equal(normalizaciones.length,3)` y fijar los nombres esperados de tabla y restricción. Así, una normalización añadida por error no oculta una diferencia real.

[P3] La ventana entre el PASS del premerge y el merge no tiene límite
File: `premerge.mjs`
Problem: la frescura de 60 s se exige a las capturas, pero `premerge.json` (con su `fecha`) no la tiene en el momento del merge.
Recommendation: en el procedimiento de merge, exigir que `premerge.json` tenga menos de N minutos y que corresponda al HEAD fusionado (ver el segundo hallazgo).

[P3] El paso posterior a la aplicación F7 es manual y no está en ningún checklist mostrado
File: `20261014001044_…sql`, cabecera ("Tras aplicar: ejecutar private.vigia_f7_piezas()")
Recommendation: incluirlo explícitamente en el runbook de aplicación productiva, junto con la verificación del resultado.

TEST GAPS:
- No hay un test o check que falle si la rama contiene archivos fuera de la allowlist.
- No hay un check de que `gate-http-estado.json` y `sql-resultados.json` correspondan al HEAD y a las huellas actuales.
- La comparación F7 entre producción y banco no se hace con una captura fresca.
- Lo adjuntado no muestra una prueba de que un `db push` o `migration list` contra el banco no reintente las dos migraciones.

ARCHITECTURE RISKS:
- La paridad se demuestra entre entornos desplegados, no entre repo y entornos. Es el hueco por el que entra trabajo ajeno.
- La deriva entre versión de ledger y nombre de archivo se acumula entre banco, producción y repo.

SECURITY RISKS:
- Posible publicación de capturas productivas si `carpeta` está dentro del repo (hipótesis).
- No veo cambios de ACL ni de owner: ambas migraciones los verifican pre y post. pg_net está acotado con aserción exacta.

REGRESSION RISKS:
- SLA: sin regresión visible en lo adjuntado. Los resultados con NULL cuando no hay tareas o la agregación no tiene filas se preservan (`jsonb_agg … filter`→NULL, `->0`→NULL, `cardinality(NULL) is null`). Los asserts de núcleo, avisos, cola y gestión diaria corren en el postflight.
- F7: `disable trigger` toma AccessExclusive sobre la tabla F7. Con `lock_timeout` de 5 s, si el cron de vigía está activo en producción, la migración fallará de forma cerrada y habrá que reintentar.

RECOMMENDED NEXT ACTIONS:
1. Añadir el check git (base actualizada más allowlist de `diff --name-only` y del conjunto de migraciones) antes del merge.
2. Atar los JSON de gate a HEAD y a las huellas de migración, y comprobarlos en el premerge.
3. Capturar los controles F7 de producción en la ventana de 60 s, acotar las normalizaciones a las 3 esperadas y confirmar que `carpeta` está fuera del repo.
4. Documentar el mapeo de versiones del ledger y la forma de registrarlas en producción, y añadir `vigia_f7_piezas()` al runbook.

CONFIDENCE:
MEDIUM. Alta sobre lo que el premerge no comprueba. Baja sobre `carpeta`, CI y la convención del ledger, porque no se adjuntaron.
