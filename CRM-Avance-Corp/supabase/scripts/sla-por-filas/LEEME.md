# SLA · ventana por filas: paso 3a (`20261017054425` · `054426` · `054427`), migraciones v2 · kit v4

Paso 3a del plan «foto del SLA» (Fase 3). El objetivo es dejar de armar en memoria **un solo jsonb con todas las filas visibles**:
para gerencia son 3.869 leads y 15,3 MB, y `jsonb_agg` necesita varias veces ese tamaño sin que `work_mem` lo limite. Esa es la
causa acreditada de la caída del 13/10. Con esta serie, el resumen de avisos y la cola cuentan, ordenan y paginan sobre FILAS.

**No cambia ninguna salida.** Se mantienen igual:
- el jsonb, byte a byte, incluido el orden de los empates sin desempate («pendiente sin acción»);
- los errores, y el orden en que salen;
- las huellas de los cursores.

Tampoco cambian las pantallas, las tablas, las policies, los datos ni la ACL de las puertas.

Miguel autorizó tocar los 3 guardianes del SLA el 16/10/2026 a las 23:55 (excepción a su decisión 4).

La **v2** (17/10) incorpora las tres revisiones: Codex, auditor-rls y el verificador independiente. El detalle está en
`scripts/foto-sla/fase3/ensayo-3a/RESULTADO-MIGRACIONES-v2.md` de la copia aislada.

El **kit v3** (17/10, tras el Codex de cierre) cambia solo los scripts de este directorio: reversas y registradores.
**M1–M3 no cambian**: son los mismos bytes con los que se hizo la prueba de carga. `verificar.sql` tampoco cambia. El detalle
está en `ensayo-3a/RESULTADO-KIT-v3.md`. En corto:
- los registradores validan la **transición** del historial, no solo el estado vivo;
- las reversas conocen su versión y la comprueban **antes de cualquier DDL**, junto con «registrar antes de revertir»;
- la reversa M1 se niega ante identificadores Unicode escapados.

El **kit v4** (17/10, tras el Codex de verificación) cambia otra vez solo este directorio. M1–M3 siguen byte a byte iguales.
El detalle está en `ensayo-3a/RESULTADO-KIT-v4.md`.
- **Cada reversa se REGISTRA A SÍ MISMA** en la misma transacción que su DDL. Con eso:
  - no puede quedar una reversa ejecutada sin registrar, ni registrada con otra versión;
  - los `registrar-reversa-mN.sql` quedan **retirados**: solo se detienen con un mensaje claro y no escriben nada.
- **La versión de una reversa** tiene que ser mayor que el máximo de TODO el índice, no solo de la serie. Una versión NULL o
  vacía se rechaza. Las dos cosas se comprueban antes del DDL.
- **`verificar.sql`** informa del historial de la serie en el índice y de cuántas versiones posteriores a 054425 no son de la
  serie. `registrar-indice.sql` también lo informa, sin bloquear.

## Qué cambia, migración por migración

### M1 · `20261017054425_crm_sla_ventana_por_filas`

**Piezas.**
- Dos funciones NUEVAS:
  - `private.sla_operacion_ambito(uuid[],boolean)`: la autorización de siempre, en un solo sitio para los dos modos. Es INVOKER.
  - `private.sla_operacion_autorizada_filas(uuid[])`: una fila por lead, más una fila de cabecera que existe siempre. Es DEFINER.
- `private.sla_operacion_autorizada` pasa a ser **envoltorio** del mismo jsonb:
  - con `false` o `NULL` conserva la salida temprana;
  - con `true` arma el objeto final en UN solo `jsonb_build_object`.

**Guardianes.**
- `assert_sla_nucleo`:
  - cadena autorizada → {ámbito, `_filas`} → núcleo;
  - **exige que EXISTA** cada firma obligatoria y **prohíbe sobrecargas** de la autoridad y del núcleo;
  - `auth.` solo en el ámbito, y lo busca **sin distinguir mayúsculas**;
  - DEFINER = {autorizada, `_filas`};
  - dueño postgres;
  - **sella por md5** el ámbito, `_filas` y el envoltorio.
- `assert_sla_avisos`: la autorizada consume `_filas`.

### M2 · `20261017054426_crm_sla_avisos_por_filas`

**Piezas.** `crm.avisos_sla_resumen_v2_fn()` cuenta sobre `_filas(private.sla_leads_operativos())`. Lleva `COMMENT ON` nuevo.

**Guardián `assert_sla_avisos`.**
- El resumen consume `_filas`, siempre acotada por el ayudante.
- Solo puede llamar a su **lista permitida** de piezas privadas.
- **Sella por md5** el resumen.

### M3 · `20261017054427_crm_sla_cola_por_filas`

**Piezas.** `crm.cola_accion_v3_fn(...)`:
- llama a `_filas(null::uuid[])` con la **firma tipada**;
- usa **identidad por fila** (`WITH ORDINALITY`) y el núcleo se evalúa **una vez**;
- solo arma jsonb para la página;
- si alguna candidata de lead tiene clave NULL, arma la página con el **algoritmo anterior sobre la misma secuencia de entrada**;
- lleva `COMMENT ON` nuevo.

**Guardián `assert_cola_v3`.**
- Depende de `_filas`.
- La puerta solo puede llamar a su **lista permitida** de piezas privadas.
- **Re-sello** de la puerta: `6096aa63…`.

### Lo común a las tres

- Están en cadena: M2 exige M1, y M3 exige M2.
- Los tres guardianes fijan `quote_all_identifiers = off`, además de `search_path = ''`. Así sus sellos no dependen de quien los
  llama.

Cada migración corre en UNA transacción. Hace, en este orden:
1. Fija `lock_timeout`, `search_path = ''` y `quote_all_identifiers = off`, y toma un candado consultivo.
2. **Comprueba el historial antes de cualquier DDL.** Si su versión ya está en `supabase_migrations.schema_migrations`, se niega.
3. Exige, de todo lo que toca o necesita: las huellas vivas exactas (`md5(pg_get_functiondef)` y `md5(prosrc)`), los metadatos
   (dueño, ACL, configuración, DEFINER, volatilidad, paralelismo, tipo y comentario) y el resto de atributos.
   - Entre lo exigido están el **productor** `private.sla_operacion_leads`, el helper de clientes y `sla_leads_operativos`. Las
     tres migraciones los exigen, también M2.
   - Exige además el md5 de cada DDL ensayado.
4. Deja dueño postgres y `revoke all` explícito a `public`, `anon`, `authenticated` y `service_role` en las tres piezas privadas.
5. Comprueba después las huellas nuevas, TODOS los atributos y la ACL efectiva. La ACL la mira para todos los roles no
   superusuario que no son postgres ni lo heredan.
6. Corre `assert_sla_nucleo`, `assert_cola_v3` y `assert_sla_avisos`, y falla si alguno no da `OK: …` (también si da NULL).
7. **Se niega a aplicarse dos veces o fuera de orden.**

### Huellas v2 (`md5(pg_get_functiondef)` / `md5(prosrc)`, con `search_path` vacío)

| Pieza | ANTES (producción tras la opt1) | Después |
|---|---|---|
| `private.sla_operacion_ambito` | no existe | M1: `e843f6cd…` / `b75fb4c8…` |
| `private.sla_operacion_autorizada_filas` | no existe | M1: `5aa19153…` / `25086396…` |
| `private.sla_operacion_autorizada` | `a5bd718f…` / `a5fd870b…` | M1: `4cdaa81a…` / `7d8c8793…` |
| `crm.avisos_sla_resumen_v2_fn` | `e9ce617a…` / `576b1aa6…` | M2: `82a7cabd…` / `3387f3af…` |
| `crm.cola_accion_v3_fn` | `1ec76074…` / `828989da…` | M3: `6096aa63…` / `34b5abf0…` |
| `private.assert_sla_nucleo` | `6bc541b2…` / `dfdbedf7…` | M1: `a938047d…` / `7f5a08dd…` |
| `private.assert_sla_avisos` | `9b9edc86…` / `0eeb9efe…` | M1: `fb433efc…` / `7c600760…` · M2: `1cbce7c3…` / `d307e5ac…` |
| `private.assert_cola_v3` | `162fe9e0…` / `97d9d1b9…` | M3: `5b000de8…` / `862b765b…` |
| Familia SLA (`verificar.sql`) | `62 · 1adaf6c5…` | M1 `64 · 1a632cfd…` · M2 `64 · 5e4e27c4…` · M3 `64 · f9ea9038…` |

- **Exigidas sin cambios:**
  - productor `private.sla_operacion_leads`: `0abdf640…` / `e47f610f…`;
  - helper de clientes: `234ee27f…` / `8d02b260…`;
  - `private.sla_leads_operativos`: `8d478d78…` / `fd8f5800…`.
- **SHA-256 de los archivos:**
  - M1: `e9c491d6…`
  - M2: `468624e2…`
  - M3: `94f695cb…`
- **Censo analítico** (`private.contadores_crudos_leads_citas()`, sin el esquema `bench` del banco): igual antes y después de la
  serie. Es informativo y su valor depende del esquema:
  - `45 · ff12620b…` en el banco del 15/10;
  - `48 · 083aeae5…` en el volcado de producción del 17/10, 10:52, tras #317 y #318 (gate RLS, `foto-sla/fase3/gate-rls-3a/`).
  - En producción se compara el valor de ANTES con el de cada paso: tiene que ser IGUAL, sea cual sea.

**Unicidad de las filas.** Una fila por lead se demuestra con las restricciones del esquema:
- `leads_pkey`;
- `lead_sla_ciclos_unico (lead_id, ciclo_n)`;
- `lead_sla_etapas_un_abierto_idx (lead_id) WHERE finalizado_en IS NULL`;
- `lead_asignacion_sla_hitos (lead_asignacion_id)`;
- `sla_politica_etapas (politica_id, etapa)`;
- `sla_politica_etapas_operacion` PK `(politica_id, etapa)`;
- el resto de los joins son `limit 1` o agregados.

Aun así, la cola reconstruye la página **por identidad de fila**, no por `lead_id`.

## Evidencia (banco Docker con el esquema de producción, 3.869 leads sintéticos)

Equivalencia, mutantes, memoria y temporales de la v2: ver `RESULTADO-MIGRACIONES-v2.md`. Las cifras de memoria son las de
esa medición, y son las mismas en este LEEME, en las cabeceras de las migraciones (que remiten aquí) y en el RESULTADO:

Medición del 17/10, 12:05–12:08, con la serie v2 aplicada. Gerencia, `work_mem` 7 MB. Se compara la versión anterior
(copia exacta en `bench`) con la nueva, en conexión nueva y en conexión reutilizada, en los dos órdenes.

| Caso | Pico de RssAnon antes → después | Temporales escritos (bloques) | Ejecución (ms) |
|---|---|---|---|
| Avisos (`avisos_sla_resumen_v2_fn`) | 104–123 → **35–48 MiB** | 4.947 → 2.413 | 311–375 → 218–245 |
| Cola v3 (50, `pendientes`/`todas`) | 210–235 → **41–55 MiB** | 15.334–15.492 → 5.409 | 736–775 → 379–442 |
| Envoltorio con operativos (Gestión Diaria) | 105–116 → 106–116 MiB | — | — |
| Envoltorio con todas las filas | 151–168 → 152–162 MiB | — | — |
| Gestión Diaria (`gestion_diaria_equipo_pendientes`) | 104–109 → 99–111 MiB | 3.740 → **5.041** (+1.301 ≈ +10 MiB por llamada) | 312–326 → 313–332 |

- **Los consumidores del envoltorio no suben de memoria.** Sí escriben más temporales: es el tuplestore de `_filas`. Pasarlos a
  filas es la Fase 4.
- **Pendiente antes del «!»:** el ensayo de carga concurrente.

## Aplicación en producción (con el «!» de Miguel; nunca `db push` ni `apply_migration`)

**Antes de aplicar M1, el `verificar.sql` de partida tiene que dar las dos líneas siguientes:**
- `Versiones del índice posteriores a 20261017054425 que no son de la serie: 0`;
- `Historial de la serie en el índice: ANTES · coincide con la serie viva: SÍ`.

Si la primera NO da 0, **no se aplica nada y se avisa**. Hay migraciones ajenas registradas con versión posterior a M1, y una
reproducción del historial por versión ejecutaría M1–M3 antes que ellas. Re-versionar M1–M3 es una decisión aparte: cambia sus
bytes y obliga a re-ensayarlas.

Desde el commit fusionado en `avancecorp/main`, de una en una, **siempre entre dos `verificar.sql`**:

```bash
npx supabase db query --linked --file supabase/scripts/sla-por-filas/verificar.sql        # SERIE=ANTES · 62 · 1adaf6c5…
npx supabase db query --linked --file supabase/migrations/20261017054425_crm_sla_ventana_por_filas.sql
npx supabase db query --linked --file supabase/scripts/sla-por-filas/verificar.sql        # SERIE=M1 · 64 · 1a632cfd…
npx supabase db query --linked --file supabase/scripts/sla-por-filas/registrar-indice.sql # registra M1
# … ídem con 20261017054426 (SERIE=M2 · 5e4e27c4…) y 20261017054427 (SERIE=M3 · f9ea9038…; «GATE SERIE COMPLETA: OK»),
#     registrando tras cada una
```

- **`verificar.sql` es un INFORME de solo lectura.** Corre en `BEGIN READ ONLY` y termina siempre en `raise P0001`: el informe sale
  en el mensaje del error. **No es un gate por código de salida.** Hay que LEER el informe y detenerse ante cualquier otro error.
  - **El transporte ya está probado en producción.** Miguel lo corrió con «!» el 17/10/2026, después de las 01:44 Lima, con
    `npx supabase db query --linked --file supabase/scripts/sla-por-filas/verificar.sql`, y el informe volvió completo:
    `SERIE=ANTES · familia SLA=62 · 1adaf6c5… (la esperada)`. Es la versión v1 del informe, por la misma vía. Evidencia en
    `scripts/foto-sla/fase3/produccion/verificar-ANTES-20261017.txt` de la copia aislada.
  - **Una petición POSTERIOR por la misma vía funciona** (no queda una conexión abortada; `25P02` no apareció). Hay dos casos:
    - El 17/10, después de ese `verificar.sql` que terminó en P0001, Miguel corrió por la misma vía (`db query --linked`) el
      conteo H1, que devolvió `count = 0`.
    - El 16/10, la serie de la opt1 corrió `verificar.sql` → migración → `verificar.sql` → registro, una petición tras otra, sin
      `25P02`. Ver `scripts/foto-sla/CONTINUACION.md` (15:24:37–15:27:05 Lima) y `fase2/plan-opt1/produccion/`.

    Es la vía del Management API: una petición por conexión. Por eso el transporte NO se cambia.
  - **«GATE SERIE COMPLETA (exige M3): OK» identifica el estado de la serie; NO es una aprobación.** Solo comprueba que la serie
    viva es M3 y que las tres piezas exigidas siguen iguales. Puede salir OK con un guardián fallando (por ejemplo, con la RLS
    desactivada en una tabla vigilada). El veredicto exige ADEMÁS `assert_sla_nucleo`, `assert_cola_v3` y `assert_sla_avisos` en
    OK, y el resto del informe leído.

  Muestra:
  - la serie (`ANTES`, `M1`, `M2`, `M3` o `MIXTO`) y la línea **«GATE SERIE COMPLETA (exige M3)»**;
  - que el productor, el helper y los operativos siguen iguales;
  - la familia SLA;
  - la ACL efectiva de las piezas privadas para TODOS los roles relevantes, más su ACL guardada (`aclexplode`);
  - la ACL de las puertas;
  - el censo analítico;
  - 7 guardianes. Los 3 del SLA tienen que dar OK. Los otros 4 se comparan antes y después: en el banco, igual que en producción
    el 16/10, ya fallan `assert_gestion_diaria`, `assert_analitica_leads_citas` y `assert_analista_vigencia`, por cambios ajenos
    (FAIL preexistentes);
  - **v4:** «Historial de la serie en el índice». Da el estado al que lleva el historial y sus eventos, y si coincide con la
    serie viva. Entre una migración y su registro sale «NO»; después de registrar, «SÍ». Sin índice, sale «AUSENTE»;
  - **v4:** «Versiones del índice posteriores a 20261017054425 que no son de la serie: N».
- **`registrar-indice.sql`:**
  - vuelve a comprobar las piezas vivas, el productor, el helper y la ACL;
  - registra SOLO las versiones de la serie viva (M1, M1+M2 o las tres), con el texto literal de cada archivo;
  - **nunca borra ni cambia filas**, y falla si una versión ya existe con otro contenido;
  - **v3: valida la transición del historial.** Reproduce las filas de la serie en orden de versión, que tienen que ser una
    secuencia válida (aplicar M1 → M2 → M3 y revertir M3 → M2 → M1). Se niega si:
    - el historial va por delante de la serie viva. Con el kit v3 era una reversa ejecutada sin registrar; con el v4 no puede
      pasar, porque la reversa se registra sola. Si aparece, alguien cambió el esquema por fuera del kit: no se registra nada y
      se investiga;
    - la aplicación vigente de una mN registrada es de **otra generación** (otra versión): hay que usar el registrador de esa
      generación;
    - una versión por registrar ya está ocupada, o no es posterior a todo evento de la serie;
  - es idempotente solo para el MISMO evento: misma versión, mismo texto y vigente en el historial;
  - deja su informe en la **última fila** de la salida, porque `db query` no muestra los avisos;
  - **v4:** el informe dice también cuántas versiones del índice posteriores a la M1 de su generación no son de la serie, con un
    AVISO si no es 0. No bloquea, porque el DDL ya está hecho.
  - **Qué evento registra.** Las aplicaciones M1–M3 no dejan constancia de su versión en el catálogo, y sus bytes no se tocan.
    El registrador las identifica por exclusión:
    - cada mN se niega a correr si su versión ya está en el índice;
    - el registrador solo acepta su generación y la transición válida siguiente;
    - como las reversas se registran solas, ya no puede haber una reversa pendiente que lo confunda (contraejemplo (b) del
      Codex de verificación).
  - **Generación parcial.** Para reaplicar solo M3 (o M2 y M3) tras su reversa, se genera con las versiones vigentes de las que
    siguen aplicadas y versiones nuevas para las demás, por ejemplo `generar.py escribir 20261017054425 20261017054426
    <nueva>`. Se aplica y se registra con el kit de esa carpeta.
- **«Commit hecho, registro pendiente».** Si una migración se confirmó pero no se registró (corte, error de red, olvido), NO hay
  que volver a ejecutarla. Sí hay que:
  1. correr `verificar.sql`, que debe dar la serie correspondiente;
  2. correr `registrar-indice.sql`, que registra sin volver a ejecutar el DDL.
- **Advisors** de seguridad y rendimiento antes y después: no se esperan alertas nuevas.
- **Orden de despliegue:** solo servidor. No hace falta regenerar tipos: las piezas nuevas están en `private`.

## Si hay que revertir

El índice de migraciones solo crece: **nunca se borran sus filas**. Se revierte en orden inverso, M3 → M2 → M1.

**Antes de empezar: registrar antes de revertir.** La aplicación de mN tiene que ser el ÚLTIMO evento registrado de la serie.
Si mN se confirmó pero no se registró (corte, error de red), primero `verificar.sql` y `registrar-indice.sql`. Con el índice
presente, la reversa se niega a correr hasta entonces. Así se cierra el callejón «M3 confirmó, se cortó, se revierte sin
registrar».

**Orden de versiones (v4: orden GLOBAL).** Cada reversa lleva una versión NUEVA, libre en el índice y **mayor que el máximo de
TODO el índice**, contando las migraciones ajenas además de las de la serie. Así `054427 < R3 < R2 < R1`, y cada reversa queda
también después de cualquier migración ajena ya registrada. Una reproducción del historial por versión ascendente aplica
entonces los eventos en el mismo orden en que ocurrieron. La reversa lo comprueba antes del DDL.

Para cada reversa:
1. **Migración nueva.** Crear `AAAAMMDDHHMMSS_crm_sla_<pieza>_por_filas_revertir.sql` con el contenido EXACTO de
   `reversa-mN.sql`, cambiando SOLO la línea `v_esta_version text := 'AAAAMMDDHHMMSS';` por su versión (14 dígitos, nunca NULL).
2. **Aplicarla** con `db query --linked --file`, entre dos `verificar.sql`. **No hay paso de registro.**
   - **Antes de cualquier DDL**, con el índice presente, la reversa se niega si:
     - `v_esta_version` está sin rellenar, vacía o es NULL;
     - la versión está ocupada (por la serie o por otra migración), o no es mayor que el máximo de todo el índice;
     - el historial de la serie no es una secuencia válida;
     - la aplicación de mN no es el último evento registrado;
     - esa aplicación es de otra generación: entonces hay que usar el kit de esa generación.
   - **v4: se registra a sí misma.** Tras sus comprobaciones, su DDL y sus poscondiciones, en la MISMA transacción, inserta su
     fila:
     - versión: `v_esta_version`;
     - nombre: `crm_sla_<pieza>_por_filas_revertir`;
     - `statements`: el texto exacto del bloque que ejecutó.

     Ese bloque es autosuficiente: fija su entorno, vuelve a comprobarlo todo y reproduce el efecto. Si algo falla, incluida la
     inserción, no queda ni el DDL ni la fila.
   - **Sin índice** (banco de pruebas, arnés), se comporta como antes y no registra nada.
3. **`registrar-reversa-mN.sql`: RETIRADOS.** Solo se detienen con «RETIRADO (kit v4)…». El historial se comprueba con
   `verificar.sql`, en la línea «Historial de la serie en el índice». Tiene que dar el estado que deja la reversa, con
   «coincide: SÍ».
   - **Las piezas exigidas** (productor, helper, operativos) tampoco bloquean la reversa: para poder volver atrás pese a
     cambios ajenos. `verificar.sql` informa si cambiaron.
4. **Ledger.** Marcar la migración original como REVERTIDA en `MIGRACIONES.md`, con el motivo.

**Si se cortó durante una reversa**, no hay estado intermedio: o se confirmaron el DDL y su fila, o ninguno. `verificar.sql`
dice cuál de los dos pasó.

| Reversa | Solo actúa si… | Repone (byte a byte) |
|---|---|---|
| `reversa-m3.sql` | la serie viva es exactamente M3 | la cola, su comentario y `assert_cola_v3` de antes de M3 |
| `reversa-m2.sql` | la serie viva es exactamente M2 (M3 ya revertida) | el resumen y su comentario de antes de M2, y `assert_sla_avisos` de M1 |
| `reversa-m1.sql` | la serie viva es exactamente M1, y **nadie más usa `_filas` ni el ámbito** (ver abajo) | la autorizada, `assert_sla_nucleo` y `assert_sla_avisos` de antes de M1, y **borra solo las 2 funciones que creó M1** |

**Cómo comprueba la reversa M1 que nadie más usa `_filas` ni el ámbito.** Mira tres cosas:
- el texto de cualquier función, **sin distinguir mayúsculas**;
- las dependencias registradas en `pg_depend` (vistas, funciones SQL estándar…);
- **v3:** si algún cuerpo de función, fuera de `pg_catalog` e `information_schema`, contiene un identificador Unicode
  escapado (`U&"…"`, sin distinguir mayúsculas), se niega, de forma conservadora. Por ejemplo,
  `private.U&"sla_operacion_autorizada_\0066ilas"(NULL::uuid[])` resuelve a `_filas` sin contener su nombre. En el esquema de
  producción no hay ningún cuerpo así (0 en el banco). Si aparece uno, hay que revisarlo a mano antes de revertir.

**Límite.** Esta búsqueda no puede descartar dos cosas:
- una llamada dinámica construida por partes (`execute` con texto armado, `U&'…'` incluidos);
- un identificador escapado de otra forma que el texto no muestre.

**Reaplicar tras reversas registradas.** Las versiones originales ya están en el índice, y cada migración comprueba el
historial antes del DDL, así que **se niegan**. Una reaplicación va con **versiones nuevas**, mayores que todo el historial de la
serie. Para generarlas: `generar.py escribir <TS1> <TS2> <TS3> <carpeta>`. Esto solo cambia la versión, y deja las mismas
funciones y huellas.
- Cada **generación** (juego de versiones) se aplica, se registra y se revierte con **su propio kit**, el de esa carpeta.
- Los registradores y las reversas de otra generación se niegan.

Las reversas no corren los guardianes, como en la opt1, para que nada ajeno bloquee una vuelta atrás. Se comprueba después con
`verificar.sql`, que tras la de M1 debe dar `SERIE=ANTES · 62 · 1adaf6c5…`.

## Pruebas

`supabase/scripts/test-rls.mjs` → `testSlaPorFilas(sessions, seed)`.

**A, B y F** (exigen `CRM_BANCO_PSQL_URL` y M1 instalada):
- ACL efectiva para todos los roles y ACL guardada;
- forma de las tres piezas;
- solo el ámbito lee `auth.`;
- los 3 guardianes en OK;
- con `CRM_RLS_EXIGE_SLA_FILAS=1`, el **gate exige M3**.

**C, D y E** (solo API, sin `CRM_BANCO_PSQL_URL`):
- la API no alcanza `_filas` ni el ámbito, con `PGRST106`/`PGRST202`/`42501`;
- las puertas responden por rol con su contrato;
- ámbito ABSOLUTO:
  - en la cola v3 de vend1, todo lead es suyo;
  - sup1 no recibe nada del equipo de sup2;
  - `total_oportunidades` cumple vend1 ≤ sup1 ≤ gerencia;
  - `estado_sla_leads_v2_fn` de vend1 con un lead de vend3 devuelve `filas` vacío, y gerencia sí lo ve;
- `anon`, `vendInactive` y `clientBank` reciben 42501.
