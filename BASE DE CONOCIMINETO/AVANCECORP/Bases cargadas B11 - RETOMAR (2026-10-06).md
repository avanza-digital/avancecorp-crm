# Bases cargadas · B11 (conversión) — RETOMAR · serial `AVC-BASES-CARGADAS-20261006-R1`

Sigue a [[Bases cargadas - RETOMAR (2026-10-05)]]. B11 = E10 de Miguel: el cierre de un contacto de **base cargada por
archivo** pesa **1** para el analista que lo consigue y **no entra al divisor**. Plan aprobado el 05/10, con dos respuestas
de Miguel: (1) los armados desde el CRM conservan su origen y su regla; (2) «Resultados por origen» sin fila de base. El
«sigue» del 05/10 aprobó además la **columna «Base» en el Divisor de coordinación** (pantalla primero, servidor después).

## Estado al 06/10 ~01:00 Lima — construido y probado en banco, NADA en producción, sin push

- **Rama** `crm/bases-cargadas-b11` en el worktree `AVANCECORP-desktop-worktrees/bases-cargadas-b11-20261005` (sale de
  `avancecorp/main` `b286b2bf`). Commit **`256780ec`** (lint + typecheck del pre-commit en verde). Sin push, sin PR.
- **Migración** `supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql` (generada por
  `supabase/scripts/base-gestion/b11/generar.py` desde los textos vivos de `b11/vivo/`; huellas nuevas en
  `b11/huellas-nuevas.json`). Ayudante único `private.conversion_origen_con_cierre(text)` en las 8 piezas que copiaban la
  lista; `cierres_base_cargada` al final del divisor de empresa y de su total (drop + create, misma ACL; **NULL en mes
  sellado**); clave `base_cargada` en `crm.conversion_divisor_coordinacion_fn`; 4 huellas del censo analítico movidas en su
  fila + resello. Freno: se niega si ya existe un cierre de base.
- **Pantalla:** `lib/conversion-coordinacion.ts` (clave opcional; `sumaDePartes` la suma; null solo vale en mes sellado) y
  `components/app/conversion-coordinacion.tsx` (columna «Base», cifra «Base cargada», parte de la fórmula, texto al pie).
- **Reversa** `supabase/scripts/base-gestion/reversa-b11.sql` (generada por `b11/generar_reversa.py`).

## Verificación hecha (06/10)

| Prueba | Resultado |
|---|---|
| Banco Docker `avancecorp-b10-20261004` a paridad con prod | ✅ 922/922 funciones idénticas (huella agregada = prod) antes de B11 |
| Migración en un mensaje | ✅ preflight + postflight verdes (0,35 s) |
| Paridad A/B `b11-paridad.sql` (32 salidas, como Gerencia) | ✅ idénticas; solo aparece `base_cargada` = 0 |
| Trinquetes antes/después | ✅ idénticos |
| Suite `b11-conversion.sql` (como `supabase_admin`) | ✅ 23/23 |
| Mutantes `b11-mutantes.mjs --puerto 58222` | ✅ 16/16 caen |
| Frenos (migración y reversa con un cierre de base) | ✅ se niegan y sueltan el candado |
| Reversa | ✅ banco vuelve a = prod (funciones y censo) |
| `npm run check` | ✅ 6134 tests |
| e2e Docker `repartir.spec.ts` | ✅ 26 pasan + 5 flaky ajenos (pasan al reintentar) |
| revisor-a11y | ✅ PASS (3 P3, abajo) |
| auditor-rls | ⚠️ CHANGES_REQUESTED (sin P0/P1): migración OK en ACL, DEFINER, gates, ayudante y censo; arreglos abajo |
| Codex r1 | ⏳ encargo listo, **NO enviado**: `docs/encargos/2026-10-06-b11-conversion-base-encargo-r1.md` |

## Pendientes, en orden

1. **Arreglos del auditor-rls (06/10):**
   - P2-1: fila de B11 en `MIGRACIONES.md` (ya era el paso 4).
   - P2-2: la reversa borra el ayudante sin mirar si otra función lo llama (pg_depend no lo ve) → en su preflight,
     P0409 si algún `prosrc` fuera de los 10 conocidos menciona `conversion_origen_con_cierre`; en su postflight, cero
     menciones.
   - P2-3: la reversa resella el censo sin comprobar que el sello estaba al día → copiar las líneas 95-103 del preflight
     de la migración (4 declaraciones vigentes + sello al día).
   - P3-1: la reversa no comprueba el candado de migraciones ni `prosecdef` en su postflight → copiar de la migración.
   - P3-2: `test-rls.mjs:9973` suma las partes sin `cierres.base_cargada` (añadir `?? 0`); barrido de EXECUTE denegado
     para anon/authenticated/service_role en el ayudante y las dos privadas del divisor (patrón de 16916/17005); caso
     positivo de `empresa.cierres.base_cargada` numérico en mes abierto.
   - P3-3: guarda en el preflight contra llamadores nuevos de las dos privadas que se recrean.
   - Medir en el banco el tiempo de `metricas_conversiones_implementacion` con 366 días antes/después (el ayudante no se
     inlinea).
   Tras los arreglos: regenerar (`b11/generar.py`, `b11/generar_reversa.py`), repetir suite, mutantes, paridad y reversa, y
   regenerar el encargo de Codex con `b11/encargo.py`.
2. **Codex r1**: `scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/2026-10-06-b11-conversion-base-encargo-r1.md`
   (desde la raíz del worktree). Si cambia la migración: regenerar con `b11/generar.py` (2 pasadas: medir huellas en el
   banco), `b11/generar_reversa.py` y `b11/encargo.py`, y repetir suite + mutantes + paridad.
3. **P3 de a11y (opcionales):** test del resumen «Base cargada» en mes sellado; el resumen pasa de 8 a 9 cifras (queda una
   sola en la última fila: ¿`lg:grid-cols-5`?); el «—» dice «Base», el resumen «Base cargada» (sr-only « cargada» en el
   `Th`, ajustando el test).
4. **Ledger** `MIGRACIONES.md` + **registrador** `supabase/scripts/base-gestion/registrar/20261006042144.sql` (formato del de
   B10: el archivo entero en `statements`, md5 del archivo) + sección B11 en `supabase/scripts/base-gestion/README.md`.
5. **Rama con datos** (ver [[rama-con-datos-sin-contrasena]] en la memoria): paridad `b11-paridad.sql` antes/después con
   datos reales de ago/sep/oct.
6. **PR** a `avanza-digital/avancecorp-crm` (CI `preflight` obligatorio).
7. **Publicar la pantalla PRIMERO** (`/release-crm`, lo invoca Miguel; el VIVO a contener es `27e6f248` o el que diga
   `version.json`). Luego la migración con `!` de Miguel (`supabase db query --linked --file …`) + registrador → verificar
   md5 de los 11 cuerpos (`b11/huellas-nuevas.json`) → `b11-paridad.sql` en prod antes/después (solo lectura) → `main`.

## Riesgos que quedan (decirle a Miguel)

- **Mes sellado:** la foto del cierre (`crm.cierre_mes_vendedor`) no guarda los cierres de base: el Divisor de
  coordinación de un mes sellado con cierres de base enseñará «—» en Base y sus partes no sumarán el numerador sellado.
  Arreglo de verdad (guardar la base en la foto al sellar) es otro paso; hoy no hay meses sellados y el ciclo está en pausa.
- **Inteligencia comercial, tabla por origen:** `fuera_del_divisor_del_nucleo` solo mira Referido ⇒ Base cargada saldrá
  como «dentro del divisor» (Oficina ya tiene el mismo desfase hoy). No se tocó en B11.
- El rojo del censo `private.gestion_diaria_cola_hechos` (sin declarar) es ajeno y previo; B11 exige que los rojos sean los
  mismos antes y después.

## Cómo levantar el banco

Volúmenes `supabase_*_avancecorp-b10-20261004` (PARADO, con B11 APLICADA). `config.toml` propio con
`project_id = "avancecorp-b10-20261004"`, `[api] port = 58221`, `[db] port = 58222`, `shadow_port = 58220`,
`[db.migrations] enabled = false`, realtime/studio/smtp/analytics apagados → `supabase start --ignore-health-check`. Antes de
usarlo, comparar con prod (y con el banco) esta huella agregada de las funciones `crm`+`private`:
`select count(*), md5(string_agg(fn||'|'||h, E'\n' order by fn)) from (select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' fn, md5(p.prosrc||coalesce(array_to_string(p.proconfig,','),'')||p.prosecdef::text) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('crm','private')) x`
(05/10, antes de B11: `922 | 42d476bb…`). La suite y los mutantes van como `supabase_admin` (superusuario del stack local).

## Lecciones

- Antes de prometer «sin cambios de pantalla» en algo de conversión, buscar los **candados de paridad del front**
  (`sumaDePartes`, `v.check` de sumas): un peso nuevo rompe la pantalla que reconcilia partes = total.
- Las salidas de métricas traen `now()` en varios campos (`generado_en`, `madura_hasta`, `seguimiento_hasta`): una foto A/B
  estable reemplaza la hora de la consulta antes de la huella.
- Clonar `node_modules` desde la carpeta de iCloud se colgó 1 h 23 (`clonefile failed: Operation timed out`); `npm ci` en
  el worktree tardó 5 s. La copia a medias quedó apartada en
  `AVANCECORP-desktop-worktrees/_apartado-b11-node_modules-parcial` (borrar con OK).
