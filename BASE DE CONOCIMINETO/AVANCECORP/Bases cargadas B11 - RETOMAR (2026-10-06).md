# Bases cargadas · B11 (conversión) — RETOMAR · serial `AVC-BASES-CARGADAS-20261006-R1`

Sigue a [[Bases cargadas - RETOMAR (2026-10-05)]]. B11 = E10 de Miguel: el cierre de un contacto de **base cargada por
archivo** pesa **1** para el analista que lo consigue y **no entra al divisor**. Plan aprobado el 05/10, con dos respuestas
de Miguel: (1) los armados desde el CRM conservan su origen y su regla; (2) «Resultados por origen» sin fila de base. El
«sigue» del 05/10 aprobó además la **columna «Base» en el Divisor de coordinación** (pantalla primero, servidor después).

## ✅ CERRADO el 06/10 ~12:05 Lima — B11 EN PRODUCCIÓN (pantalla + migración), verificada

> **06/10 ~12:30 — PR #205 fusionada (`avancecorp/main` = `4e7c55bb`) y limpieza hecha por orden de Miguel.** Ya NO
> existen el banco `avancecorp-b10-20261004`, los worktrees de bases (`base-gestion-*`, `bases-cargadas-b10/b11`) ni
> `bancos-20261006-NO-VERSIONAR/b11/`. Quedan las ramas locales `crm/bases-cargadas-*`, los veredictos de Codex en
> `bancos-20261006-NO-VERSIONAR/b11-evidencia/` y las dos lecturas de producción (`leer-prod.sql`,
> `verificar-b11-prod.sql`). Las rutas a ese banco y a esos worktrees que aparecen más abajo son HISTORIA. Para ensayar el
> sellado de un mes con cierres de base hay que montar un banco nuevo.

- **Migración `20261006042144` aplicada y registrada** por Miguel con `!` (el mismo día que la pantalla: su decisión).
  Antes: producción `933 | 2c2f2612…`, 0 contactos y 0 cierres de base. Después (solo lectura,
  `bancos-20261006-NO-VERSIONAR/verificar-b11-prod.sql`): `934 | 2f359f3e…` = banco con B11, 11/11 huellas, núcleo solo de
  `postgres` 3/3, ACL de la puerta intacta, censo sellado, versión registrada (md5 `33ec12dc…`), 0 candados, 0 cierres de base.
- **PR #205** (`crm/bases-cargadas-b11-aplicada`, `ab740e15`): solo el ledger, marca «APLICADA». Falta el squash de Miguel.
- Con esto el módulo **Bases cargadas (B7–B11) está completo en producción**.
- **Queda pendiente (no bloquea):** (1) ensayar el sellado de un mes con cierres de base antes de reactivar el cierre
  mensual; (2) adelantar el `main` local cuando la otra sesión guarde `MIGRACIONES.md` (hoy va 1–2 commits detrás);
  (3) «Inteligencia comercial» por origen muestra Base cargada como «dentro del divisor»; (4) limpieza de bancos y
  worktrees de bases (`avancecorp-b10-20261004`, `bases-cargadas-b10/b11`, ramas ya fusionadas) con el OK de Miguel;
  (5) producción está en SLA `activo / rev 1`: el banco quedó en `legado`.

## Estado al 06/10 ~12:00 Lima — PANTALLA PUBLICADA; faltaba aplicar la migración

- **PR #204 fusionada** (squash `afae7b59`, 11:45 Lima). **Pantalla publicada** con `/release-crm`: artefacto
  `crm-20261006T165240Z-afae7b59412a.zip` (commit `afae7b59`, worktree limpio), preflight
  `live=build-20261006T152938176Z/33694da6 candidate=afae7b59`, deploy aceptado. Smoke: home 200, `version.json` =
  **`build-20261006T165239841Z`** (= VIVO del CRM), `index-cjpjOXVD.js` y el trozo `repartir-8f6ayUzx.js` (el que trae
  la columna «Base») servidos byte a byte iguales al artefacto. ZIP y manifiesto copiados a `CRM-Avance-Corp/releases/`
  de la carpeta principal.
- El release se construyó en el worktree `bases-cargadas-b11-20261005` (ahora en `afae7b59` suelto, con el archivo de
  entorno que copió Miguel con `!`): la carpeta principal tiene 254 archivos ajenos sin guardar y su `main` local quedó
  un commit detrás (`33694da6`; no se pudo adelantar porque otra sesión tiene `MIGRACIONES.md` modificado).
- **Falta (servidor):** con `!`, desde `CRM-Avance-Corp/`: `leer-prod.sql` → la migración `20261006042144` → su
  registrador → verificar 11 huellas y paridad → marcar APLICADA en el ledger (PR aparte) → adelantar `main` local.
  Recomendado: al día siguiente de la pantalla (o, si es hoy, al menos una hora después). «could not obtain lock» = repetir.

## Estado al 06/10 ~11:40 Lima — PR #204 abierta, checks en verde

- **PR #204** (`crm/bases-cargadas-b11` → `main`, cabeza `a5aa2ad2`): `app-check`, `cambios`, `preflight` y `verify` PASS;
  fusionable, espera el squash de Miguel. https://github.com/avanza-digital/avancecorp-crm/pull/204
- **Codex r2 (última ronda): APPROVE_WITH_NITS**, sin P0/P1 (P1 cerrado; el P2 de las pestañas viejas queda como residual
  reconocido). Anotado en el ledger.
- Miguel ya entendió B11 («le cuenta como conversión, pero solo para el numerador») y quiere hacerlo ya.
- **Orden que falta:** (1) Miguel fusiona la #204; (2) `/release-crm` (pantalla primero); (3) con `!`, desde
  `CRM-Avance-Corp/` de la carpeta principal: `leer-prod.sql` (esperado `933 | 2c2f2612…`, 0 contactos y 0 cierres de base),
  la migración y el registrador (rutas del worktree `bases-cargadas-b11-20261005`, md5 `33ec12dc…`); (4) verificar las 11
  huellas y la paridad en solo lectura; (5) marcar «APLICADA» en el ledger, `main` local al día, memoria y esta nota.
  Si la migración responde «could not obtain lock», alguien escribía en ese instante: repetirla.

## Estado al 06/10 ~12:30 Lima — r2: candado del freno + ledger; Codex r2 enviado (última ronda)

**Sigue sin aplicar y sin push.** Rama `crm/bases-cargadas-b11` asentada sobre `avancecorp/main` `33694da6`:
`ffcdc1d8` (base) · `d3f262d5` (r1) · **`e03d888b`** (r2). md5: migración **`33ec12dc…`**, reversa `2dbf3436…`,
registrador `58761b03…`.

- **Respuesta a Codex r1:** [P1] ACEPTADO → migración y reversa toman `lock table crm.lead_asignaciones,
  crm.conversion_acreditaciones in share row exclusive mode nowait` antes de su primera lectura (suelto, no en un DO: un
  DO toma la instantánea antes). Ensayo de dos sesiones en el repo: `supabase/scripts/base-gestion/b11-carrera.sh
  --puerto 58222` (17 PASS: sin candado la carrera existe; con él el freno ve el cierre; NOWAIT se niega al instante; el
  escritor que llega en medio espera). [P2] pestañas con el bundle anterior → riesgo operativo declarado: pantalla
  primero, el CRM avisa «hay versión nueva» cada 60 s, y la migración se aplica después (propuesta a Miguel: al día
  siguiente; **aún no respondió**, pidió que se le explicara qué es B11 y se le explicó).
- **Banco arreglado** (las dos filas de control cargadas) y todo repetido con los archivos finales: paridad 41/41, censo
  igual, 11 huellas, suite 23/23, mutantes 16/16, frenos 10/10, registrador, carrera 17/17, **gate 8 de 2817 → 8 de 2825
  (mismos 8 rojos de fondo), bloque B11 8/8**, `npm run check` 6201.
- **Hecho además:** fila del ledger (`MIGRACIONES.md`, estado PENDIENTE), línea de `schema_migrations` en la reversa,
  `assert '$chk$'` en el generador del registrador, README con el candado y la carrera.
- **Encargo r2:** `docs/encargos/2026-10-06-b11-conversion-base-encargo-r2.md` (enviado; el r1 quedó como se envió).
- Banco `avancecorp-b10-20261004`: config y guiones en `AVANCECORP-desktop-worktrees/bancos-20261006-NO-VERSIONAR/b11/`
  (arranque: `supabase start --workdir <esa carpeta> --ignore-health-check -x realtime,studio,inbucket,logflare,vector,
  edge-runtime,imgproxy,supavisor,postgres-meta`; API 58221, DB 58222). Queda CON B11 aplicada.

**Lo que sigue:** (1) leer Codex r2 y cerrar lo que traiga; (2) preguntas a Miguel: espera entre pantalla y migración,
rama de Supabase con datos (¿se crea?) y abrir la PR; (3) lectura de producción con `!`
(`bancos-20261006-NO-VERSIONAR/leer-prod.sql`: esperado `933 | 2c2f2612…` y 0 contactos/cierres de base); (4) PR →
`/release-crm` de la pantalla → migración con `!` + registrador → md5 de los 11 cuerpos → `main`.

## Estado al 06/10 ~11:00 Lima — r1: arreglos del auditor hechos y probados; Codex r1 = BLOCK (respondido en r2, arriba)

**Sigue sin aplicar y sin push.** Rama `crm/bases-cargadas-b11`, commits `c69a5c07` (el de antes, asentado sobre
`avancecorp/main` `ea3b6ed2`) + **`44e1bf91`** (r1). `main` ya avanzó a `33694da6` (#203): volver a asentar antes de la PR.

- **Hecho en r1:** los seis arreglos del auditor-rls (reversa: se niega si otra función usa el ayudante, si hay un llamador
  nuevo del divisor de empresa o si el censo no está vigente y sellado; candado y `prosecdef`; migración: guarda de
  llamadores nuevos), bloque `testBasesCargadasB11` en `test-rls.mjs` y `(f.cierres.base_cargada ?? 0)` en la paridad,
  registrador generado (`b11/generar_registrador.py` → `registrar/20261006042144.sql`), sección B11 en
  `base-gestion/README.md`, y los tres P3 de pantalla (cabecera «Base» se oye «Base cargada», resumen en 3 columnas, test
  del resumen en mes sellado).
- **md5 finales:** migración `2f5f2ea9…`, reversa `04cd0f1b…`, registrador `a945ccf0…`.
- **Banco (06/10):** el banco ahora = producción con «eliminar inversión» (`933 | 2c2f2612…`; con B11 `934 | 2f359f3e…`).
  Migración y reversa van como **`postgres`** (como `supabase_admin` el postflight las rechaza: otro dueño). Paridad 41
  salidas idénticas · censo igual · 11 huellas = `huellas-nuevas.json` · suite 23/23 · mutantes 16/16 · frenos en negativo
  10/10 · registrador (se niega sin la migración, idempotente) · tiempo de `metricas_conversiones_implementacion` 366 días
  ≈ 90 ms antes y después · gate RLS antes/después: **los mismos 71 rojos de fondo**, bloque B11 8/8 · `npm run check`
  6201 · e2e Docker `repartir.spec.ts` 31/31.
- **auditor-rls r2: PASS.** P3 que quedan: falta la **fila del ledger** (obligatoria antes de la PR); la cabecera de la
  reversa no dice que la fila de `schema_migrations` se conserva; opcionales: `proconfig` en los postflights,
  `assert '$chk$' not in mig` en el generador del registrador, regex `~*` con comillas.
- **Codex r1: BLOCK** (salida en el encargo `docs/encargos/2026-10-06-b11-conversion-base-encargo-r1.md`, respuesta por escribir):
  1. **[P1] El freno no excluye escritores:** la migración (y la reversa) miran «no hay cierres de base» dentro de una
     instantánea; un cierre de base que se confirme en ese instante no se ve. Arreglo propuesto: `lock table
     crm.lead_asignaciones, crm.conversion_acreditaciones in share row exclusive mode` ANTES de la primera lectura
     (con `lock_timeout`), en migración y reversa, + ensayo de dos sesiones. Cambia el archivo ⇒ regenerar y repetir banco.
  2. **[P2] Pestaña abierta con el bundle anterior + servidor nuevo:** cuando aparezca el primer cierre de base, la
     pantalla vieja suma las partes sin la base y rechaza el desglose. «Pantalla primero» no cubre las pestañas ya
     abiertas. Por decidir: ver si el CRM ya obliga a recargar al cambiar de versión; si no, decirlo a Miguel como riesgo.
  3. Riesgos: recorrido real cierre de base → sellar el mes → foto → anulación (no ensayado con `crm.cerrar_periodo`).
- 🔴 **El banco tenía un defecto que tapaba 63 rojos del gate:** faltaban las filas únicas de
  `crm.sla_operacion_control` y `crm.piloto_f8_control` (las siembran sus migraciones; el volcado solo-esquema no las
  trae). Con ellas el gate baja de 71 a **8 rojos de fondo**. En el banco de B11 (`avancecorp-b10-20261004`) todavía
  faltan: cargarlas (`insert … values (true)` en `replica`) y **repetir el gate antes/después de B11** antes de la PR.
- **No pude leer producción** (el clasificador lo deniega): falta que Miguel confirme con `!` que producción da
  `933 | 2c2f2612b14e772cf705c8ce2dece1da` con la consulta de «Cómo levantar el banco».

**Lo que sigue:** (1) arreglar el banco y repetir el gate; (2) responder a Codex: candado del P1 + decisión del P2;
(3) fila del ledger y línea de la reversa; (4) asentar sobre `main`, rama con datos, PR; (5) pantalla primero, luego `!`.

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
