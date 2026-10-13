# Ensayo de «"Realización" cuenta la cita realizada desde que se marca»

Verifica la migración `20261013145852_crm_realizacion_cuenta_anticipada.sql` **en el banco Docker local (el laboratorio) y sin
escribir nada**. Este ensayo **no se corre contra producción**: siembra leads y citas con los actores reales del banco y pide la
métrica por la puerta `crm.metricas_reuniones_fn` como la Gerencia, siempre dentro de una transacción que termina en `rollback`.

Fase 4, F4.2 (09/10/2026): **reselle contra el código de producción** (laboratorio igual a producción: B5+B6, 32 migraciones de
`main` y `20261009120000`). La migración entraba en su preflight y se negaba en su postflight porque `main` cambió
`private.metricas_conversiones_implementacion` (bases cargadas `20261006042144` y tope de referidos `20261007203000`: `1a0e7f7f…` →
`14f45688…`); su «cita real» (`ce.realizada and ce.debio_ocurrir`) es la misma línea, y la función, el núcleo, la exención y la puerta
de la métrica son los auditados: «Realización» es la verificada. Cambian: esa huella (postflight y caso 6b, que fija además
`private.conversion_episodios` `9c606dd4…` → `e3d278a1…`, tope de referidos); los dos barridos de `private.assert_*()` de la migración
y los dos de la reversa **excluyen los `*_mutantes`** (requisito F4.2 del plan, como el bloque 2.7; el ensayo `--trinquetes` sigue
barriendo los 36); y el montaje (`antes.sql`) completa los tres vendedores con los de menos reuniones y **neutraliza** dentro de la
transacción las que ya tuvieran (ver «Límites», 9). El cuerpo de la función, sin cambio. Cadena repetida: ROJO 8 (los mismos fallos,
con las mismas cifras, que la ronda 2), VERDE 25, mutantes, derivas, reversas y trinquetes. Evidencia: `fase-4/F4.2-reselle/salidas/`
del plan.

Fase 4, F4.2-bis (09/10/2026, tarde): **producción aplicó `20261009200000`** (baja de analista). De lo que fija la migración no
cambió nada: entra igual (postflight con las mismas huellas y 30 trinquetes idénticos). Cambiaron `private.conversion_episodios`
(`e3d278a1…` → `125b4046…`) y `private.capital_episodios` (`214c6bad…` → `b4ee7e56…`), que fija el caso 6b: solo el analista de las
operaciones y del capital, que esta pantalla no lee. «Realización» sale de `private.citas_episodios` (sin cambio): es la verificada;
medido además con un ensayo de equivalencia aparte (la respuesta de la pantalla con las funciones de producción y con las auditadas,
sin y con analistas dados de baja con heredero: idéntica, 8 de 8, con una reunión convertida sembrada para que conversión y capital
no salgan en cero). Cambian esas dos huellas del caso 6b y el **montaje** (`antes.sql`): el banco deja reuniones de hoy con la hora
unas tres horas por delante y el ensayo abortaba («ya tiene reuniones con hora futura») hasta que pasaban; ahora se neutralizan
dentro de la transacción, como las de los actores (ver «Límites», 3 y 9). Cadena: ROJO 8 (mismos fallos y cifras), VERDE 25, 11
mutantes + 1 equivalente, 14 derivas, reversas y trinquetes idénticos. Evidencia: `fase-4/F4.2b-reselle/salidas/` del plan.

## Qué prueba

La regla de Miguel (decisiones D-11/Q2 y D-13, 2026-10-06): una cita marcada como realizada **antes de su hora pactada** entra al
numerador **y** al divisor del indicador «Realización» de Gerencia desde que se marca («1 de 3» pasa a «1 de 4»). La cita
pertenece al mes de su hora pactada; los periodos ya pasados no cambian; las canceladas por el asesor ya vencidas siguen en el
divisor; las reprogramadas y las canceladas por el sistema vencidas siguen restándose; las futuras no realizadas siguen fuera. El
núcleo `private.citas_episodios` y los informes de conversiones («cita real» = realizada y hora vencida) **no cambian**.

| Caso | Qué exige |
|---|---|
| 1 | Tres citas vencidas sin realizar (dos «no asistió» y una pendiente) + una **realizada antes de su hora**, del vendedor A, en la ventana de hoy: la fila del analista pasa de «1 de 3 · 33,3 %» a **«1 de 4 · 25,0 %»**; el resumen suma 9 al «debieron ocurrir» y 7 al divisor (7 vencidas + 2 anticipadas − 1 del sistema − 1 reprogramada); la modalidad virtual (A2, A3, A4, B1) suma 4 y 4; el origen `web` (solo la anticipada A4) pasa de `pct_realizacion = null` a 100,0 %. Coherencia servida (`divisor = debieron − sistema vencidas − reprogramadas vencidas`, `realizadas <= divisor`, `pct = round(100·realizadas/divisor, 1)`) en el resumen y en cada modalidad. |
| 2 | Un analista (B) con **una sola** cita, realizada antes de su hora (hoy `realizadas=1, divisor=0`): queda «1 de 1 · 100,0 %». |
| 3 | **Periodo ya pasado** (el mes anterior, una cita de cada estado, todas vencidas, sembradas ANTES de la migración): la respuesta de la puerta es **idéntica** antes y después de aplicarla, dentro de la misma transacción; y es exactamente la siembra (6 pactadas, 6 vencidas, 1 realizada, divisor 4, 25,0 %). |
| 4 | Vendedor C: canceladas por el asesor ya vencidas (propia y ajena) **siguen en el divisor** (4 vencidas → divisor del analista 4−1−1−1 = 1, con `canceladas_ajenas_vencidas = 1`); cancelada por el sistema y reprogramada vencidas se restan; pendiente, cancelada (asesor y sistema) y reprogramada **futuras** quedan fuera del divisor y de las exclusiones. |
| 4b | **Frontera exacta de la hora**, sin mover el reloj: una cita realizada con `vence_en = now()` **exacto** (el mismo `now()` fijo de la transacción que la función usa como «ahora») ya «debió ocurrir» (`<=`): el núcleo la da por `debio_ocurrir = t` y `realizada = t` («cita real» para los informes) y la fila de B suma 1 a pactadas, debieron, realizadas y divisor, **igual antes y después** de la migración (la migración solo añade las que aún no llegaron a su hora). Se siembra al final, después de las demás mediciones, para no mover sus deltas. |
| 5 | Una realizada anticipada con hora en el **mes siguiente** no aparece ni en la ventana de hoy ni en la del mes en curso; la ventana del mes cuenta la anticipada de hoy igual que la de hoy. |
| 6 | El núcleo sigue diciendo que la anticipada **no** debió ocurrir aunque está realizada (así la leen los informes: 0 «citas reales» entre las anticipadas; 7 vencidas con `debio_ocurrir`), y conserva su huella (`md5(prosrc)` de 3 y 4 argumentos); `private.metricas_conversiones_implementacion`, `crm.metricas_reuniones_fn`, `private.filtrar_desglose_sujetos_crm`, `conversion_episodios`, `capital_episodios` y `peso_referido_conversion` con su huella; el bloque `conversion` de la pantalla solo suma los 2 leads reunidos. |
| 7 | La **huella analítica re-sellada para el cuerpo vivo**: la exención de `private.analitica_leads_citas_exenciones` lleva la huella normalizada del cuerpo, el censo `private.contadores_crudos_leads_citas()` la da por `declarada` y `huella_ok`, y `private.analitica_lc_sello` coincide con `private.huella_exenciones_analitica_lc()`. |
| 8 | Ficha: dueño `postgres`, `security definer`, `STABLE`, `search_path` vacío, EXECUTE **solo** para el dueño (ni `anon`, ni `authenticated`, ni `service_role`). |
| 9 | **El contrato de la pantalla** (`app/src/lib/metricas-reuniones.ts:106-116,135-138`): toda fila servida (resumen, modalidades, responsables) pasa la validación de la app. Hoy, con una anticipada y nada más, la app rechaza el payload entero (`realizadas 1 > divisor 0`). |

## Por qué así

El ensayo no prueba una copia de la función: pega la **migración real** (preflight, re-sellado, postflight y comentario incluidos)
dentro de la transacción. Si alguien toca la migración, el oráculo prueba lo tocado.

Las citas se siembran **ya en su estado final** con los triggers de `crm.tareas` y `crm.leads` apagados
(`set local session_replication_role = replica`): el candado BEFORE UPDATE exige que todo cierre venga por una RPC de agenda y el
BEFORE INSERT vuelve «sistema» toda cancelación. Lo que se mide es cómo la métrica **lee** la tabla (`private.citas_episodios` sobre
`crm.tareas`), no el camino de escritura, que ya cubre el ensayo del bloque 2.1 (`no-asistio-espera-hora/`). Los CHECK de la tabla
siguen activos (motivo, modalidad, ubicación, quién canceló). Los actores (una Gerencia y tres vendedores sin citas desde el mes
pasado) salen del banco y son **obligatorios**: si faltan, o si tras neutralizar las reuniones con hora futura (contaminarían los
deltas; ver «Límites», 3) quedara alguna, o si faltan menos de 10 minutos para la medianoche de Lima, el ensayo aborta (`ENSAYO
ABORTADO`), no pasa en verde. La
identidad se fija en las DOS formas de los claims; no se usa `set role` (llamar bajo `set role` a una función sin EXECUTE tumba el
Postgres del banco): los permisos se leen del catálogo (caso 8).

Las cifras del resumen, de las modalidades y de los orígenes se comprueban por **deltas** contra la línea base (el laboratorio ya
tiene citas de hoy, todas vencidas); las filas de los tres vendedores, en **absoluto** (son enteramente del ensayo).

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó
escrito). Los SQL generados van a una carpeta de trabajo, no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 8 fallo(s): «la realizada anticipada no entra al divisor» del resumen, del analista A, de la modalidad
#      virtual, de los orígenes web y whatsapp y de la ventana del mes; el analista B queda «1 de 0»; la pantalla rechazaría
#      el payload (realizadas 1 > divisor 0). Nunca un error de montaje. Los demás 17 casos, en «ok» (la frontera exacta
#      pasa también sin la migración: no depende de ella).

# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (25 comprobaciones «ok» y las medidas de huellas, reloj, actores, cifras y frontera)

# 3. Los mutantes: rompen una defensa DESPUÉS de la migración y exigen que el oráculo lo grite nombrando su fallo.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/metricas-reuniones-realizacion/mutantes.sh
#    → MUTANTES: los 11 mutantes de verdad murieron, cada uno por su fallo; 1 equivalente confirmado.

# 4. Las derivas previas: rompen el catálogo o el registro analítico ANTES de la migración y exigen que se niegue (13 en su
#    preflight; la 14.ª —un gate sembrado cuyo primer error cambia solo después del carácter 160— en su postflight, por la
#    foto íntegra de los assert_*). Después, los mutantes de la migración y la reversa con la misma deriva.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/metricas-reuniones-realizacion/derivas.sh
#    → DERIVAS: las 14 abortan (13 en el preflight, 1 en el postflight) y no dejan rastro; el control entra; los 3 mutantes de
#      la migración mueren; la reversa aborta con el gate sembrado y su mutante de la foto truncada muere.

# 5. La reversa: aplicar → revertir → la función, la exención y el sello vuelven a ser los de antes.
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
$EJECUTAR_SQL "$SALIDAS/reversa.sql"
#    → REVERSA VERDE: prosrc 6880150b…, definición cec7ee9e…, exención 4b28cc41…, sello consistente, censo ok, ficha idéntica.

# 6. La reversa con un SET añadido después de migrar: tiene que ABORTAR y no dejar rastro (falla cerrada).
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
$EJECUTAR_SQL "$SALIDAS/reversa-con-set.sql"
#    → REVERSA CON SET VERDE: la reversa ABORTÓ («no tiene exactamente la definición que dejó la migración»); foto IGUAL, SET conservado.

# 7. Los trinquetes: la foto de los 36 private.assert_*() y del censo analítico, con la migración puesta, para compararla con la de antes.
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes.sql"
$EJECUTAR_SQL "$SALIDAS/trinquetes.sql"
```

El ensayo se arma para una base que **todavía no tiene** la migración: su preflight exige las huellas anteriores de la función
(`md5(prosrc)` `6880150b…`, `md5(pg_get_functiondef)` `cec7ee9e…`) y la huella `4b28cc41…` en la exención. En una base que ya la
tiene, el oráculo se corre solo (`--sin-migracion`) y entonces tiene que salir VERDE.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega montaje + migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--reversa-con-deriva <archivo> --espera "<texto>"` (aplicar → instalar la deriva → la reversa tiene que abortar con ese texto y sin rastro), `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` del archivo se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`; modificadores `--migracion <ruta>` (otra migración, para mutar el preflight, el re-sellado o la foto) y `--reversa-archivo <ruta>` (otra reversa, para mutar su foto). Se niega si queda un `commit` suelto. |
| `antes.sql` | El montaje, DELANTE de la migración: auxiliares temporales, actores obligatorios, precondiciones del laboratorio y la siembra del periodo pasado con su respuesta guardada. |
| `pruebas.sql` | El oráculo (casos de arriba). Línea base → siembra de hoy → medición por deltas y absolutos → veredicto. |
| `mutantes.sh` | 12 mutantes: 6 de cuerpo (cambio revertido; `or` aplicado también a canceladas, a reprogramadas y a pendientes futuras; la bandera del núcleo cambiada en vez de la de la métrica —la métrica sale igual y muere por el núcleo—; solo el divisor del resumen y no los cortes), 1 de la **migración** (sin re-sellar la huella ni controlarlo), 4 de catálogo (INVOKER, `search_path`, VOLATILE, EXECUTE a `authenticated`) y 1 **equivalente** (el orden de las dos banderas en el `or`). Los de cuerpo re-sellan la huella para el cuerpo mutado: mueren por su comportamiento, no por el sello. |
| `derivas.sh` | Catorce derivas instaladas ANTES de la migración: trece la hacen abortar en su **preflight** (cuerpo, `SET`, INVOKER, VOLATILE, EXECUTE a `authenticated`, comentario, núcleo `citas_episodios` alterado, `contadores_crudos_leads_citas` alterada, exención con otra huella sin y con re-sellado, exención con otra razón re-sellada, sello distinto, migración ya aplicada) y la 14.ª en su **postflight**: un gate `private.assert_zz_…` sembrado solo en el ensayo cuyo primer error es fijo hasta pasado el carácter 160 y después lleva la huella de la exención (la migración la cambia); la foto íntegra lo ve. Un control sin deriva. Tres **mutantes de la migración**: sin comparar el sello previo, el sello distinto se cuela y se sobrescribe; sin comparar las fuentes en pre y postflight, el núcleo alterado se cuela; con la foto de los `assert_*` **truncada a 160** (la de la ronda 1), el gate sembrado se cuela. Y la **reversa** con el mismo gate sembrado: aborta en su postflight sin rastro; una reversa con la foto truncada lo deja pasar (su mutante muere). Ningún `assert_*` real se toca. |
| `reversa.sql` | Repone el cuerpo anterior (byte a byte el de `20260907194622…:27-354`), la huella `4b28cc41…` de la exención, el sello y el comentario. **Falla cerrada:** exige `md5(prosrc)` `ca6fe61e…`, `md5(pg_get_functiondef)` `ce852e37…` y la exención con `d54d4f87…` (los que deja la migración). Su postflight exige la foto íntegra de los `assert_*` idéntica a la de antes de revertir. No deshace datos. |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La siembra apaga los triggers.** Las citas nacen en su estado final sin pasar por las RPC de agenda ni por el ledger de
   asignaciones; la métrica lee `crm.tareas`, así que mide lo mismo, pero nada de aquí prueba el camino de escritura (bloque 2.1)
   ni los informes de conversiones con cohortes reales (los leads sembrados no tienen llegada en el ledger).
2. **Los informes de conversiones no se ejecutan:** se comprueba que su cuerpo tiene la huella del laboratorio y que el núcleo
   sigue dando `debio_ocurrir = false` para la anticipada (lo que esos informes leen). Ejecutarlos con una cohorte real es trabajo
   del banco (fila 5).
3. **Los deltas suponen que ninguna cita preexistente tiene la hora en el futuro.** Desde F4.2-bis `antes.sql` las neutraliza dentro
   de la transacción (`activo = false`, triggers apagados, rollback) antes de sembrar y de medir —el banco corrido sobre el laboratorio
   igual a producción deja reuniones de hoy con la hora unas tres horas por delante (9 el 09/10)— y, si aun así quedara alguna, aborta
   en vez de medir mal. Lo que no prueba: nada sobre esas reuniones neutralizadas.
4. **La ventana «de hoy» necesita 10 minutos de margen con la medianoche de Lima.** Las citas vencidas van hasta 8 minutos atrás y
   las anticipadas hasta 7 adelante (sobre el `now()` fijo de la transacción). Cerca de medianoche el ensayo aborta y se repite.
5. **Borrar la exención no se puede ensayar como deriva:** la propia tabla lo rechaza con su candado («Una exencion no se borra por
   fuera…»), medido el 07/10/2026. Es una defensa más, no un hueco.
6. **Los gates del banco no están todos verdes, y la foto de los `assert_*` garantiza exactamente esto:** por cada uno de los
   `private.assert_*()` sin argumentos **que no son `*_mutantes`** (30 de 36 en el laboratorio igual a producción; F4.2: varios
   `*_mutantes` aplican sin guarda DDL de permisos sobre tablas calientes y en la base real tomarían candados ACCESS EXCLUSIVE; se
   siguen barriendo los 36 en `--trinquetes`), su **estado** (`pasa`) o, si cae, el **SQLSTATE y el texto íntegro de su primer error** (sin
   truncar), **idénticos antes y después** de la migración (postflight, con igualdad exacta) y antes y después de revertir (reversa).
   **No acredita PASS de los gates que ya caían:** en el laboratorio 7 caen desde antes por trabajos ajenos —entre ellos
   `assert_analitica_leads_citas` por `private.gestion_diaria_cola_hechos` sin declarar, que aborta ANTES de llegar a su control
   «cuerpo CAMBIO»—, así que aquí la foto no puede demostrar que la migración lo deje en «pasa», ni vería una segunda regresión
   del mismo gate que no cambie su primer error. La garantía fuerte sobre lo que la migración toca son **las huellas de la función,
   el sello de la lista de exenciones y el censo analítico**, exigidos aparte en el postflight y en el caso 7 del oráculo (y es por
   ahí por donde muere el mutante «migración sin re-sellar»). En producción, donde `assert_analitica_leads_citas` pasa, un `create
   or replace` sin re-sellar lo tumbaría, y el postflight lo vería como «pasa → cae». La foto externa (`--trinquetes`, con
   `potencial-lead/banco/trinquetes.sql`) sigue truncada a 160 caracteres: es la del banco y se compara con la del 2.6 tal cual.
7. **La huella viva de producción:** el preflight la exige igual a la del laboratorio (corte `20261003162500`); si difiere, aborta
   sin tocar nada. F4.2 (09/10/2026): en el laboratorio igual a producción del 08/10 la función, la exención y las fuentes son las
   auditadas, y la única huella que cambió (`metricas_conversiones_implementacion`) está re-auditada. F4.2-bis (09/10/2026, tarde): con
   la baja de analista de producción (`20261009200000`) la migración sigue entrando (no fija nada de lo que cambió); el oráculo fija
   además `conversion_episodios` y `capital_episodios`, que cambiaron solo en el analista (que esta pantalla no lee), re-auditadas.
   Vuelve a valer si `main` o producción cambian antes de la branch.
8. **La frontera exacta se ensaya con el `now()` fijo de la transacción** (caso 4b), que es el mismo «ahora» de la función: no
   se mueve el reloj del servidor. La cita del mes siguiente se prueba *fuera* del mes actual; su inclusión cuando ese mes sea
   consultable se deduce del filtro por `vence_en` y no se ejecutó.
9. **Los tres vendedores pueden traer reuniones del banco** (F4.2): `antes.sql` prefiere los que no tienen ninguna desde el inicio
   del mes pasado y, si no hay tres, completa con los de menos y pone `activo = false` a esas reuniones (solo las de los tres
   actores, triggers apagados, dentro del rollback) antes de sembrar y de medir; el núcleo solo cuenta tareas activas, así que sus
   filas siguen siendo enteramente del ensayo. En el laboratorio igual a producción del 09/10 neutraliza 1 (de `PASO08 VEND3`, que el
   banco dejó hoy); los actores son los mismos que en la fase 2. Lo que no prueba: nada sobre esas reuniones neutralizadas.

## La reversa, con exactitud

- **Falla cerrada.** Exige que la función tenga EXACTAMENTE la definición que dejó la migración (`md5(prosrc)` y
  `md5(pg_get_functiondef)`), que la exención lleve la huella `d54d4f87…` y que el sello coincida con la lista. Si alguien cambió el
  cuerpo **o un atributo** después (p. ej. `ALTER FUNCTION … SET lock_timeout`), **se niega** y no toca nada. Ensayado con
  `--reversa-con-set`.
- **Qué restaura:** el cuerpo anterior (`6880150b…` / `cec7ee9e…`), la huella `4b28cc41…` de la exención (calculada sobre el cuerpo
  restaurado y comparada con la revisada), el **valor** del sello con `private.huella_exenciones_analitica_lc()` y el comentario
  anterior. El postflight lo exige, más el censo reconociendo la exención y la foto íntegra de los trinquetes sin los `*_mutantes`
  (estado o SQLSTATE + texto completo del primer error; 30 de 36 en el laboratorio igual a producción) idéntica a la de antes de revertir.
- **Qué no vuelve:** `sellado_en` queda en `now()` (la reversa re-sella como la plantilla del repo, `20260908020020`); el timestamp
  anterior del sello no se restaura. Lo que el vigía compara es el valor del sello, y ese sí vuelve.
- **Qué conserva:** firma, dueño, `security definer`, `STABLE`, `search_path` vacío y ACL.
- **No deshace datos:** la métrica se calcula al leer. Tras revertir, la anticipada vuelve a contar solo arriba hasta su hora: es
  el defecto que la migración cerraba.

## Trampas encontradas al escribirlo

- **`trg_tareas_before_insert` vuelve «sistema» toda cancelación y exige `crm.op_tarea = on` para nacer cerrada;**
  `trg_tareas_before_update` exige la RPC para cerrar: por eso la siembra apaga los triggers con `session_replication_role`.
- **Cada comparación del preflight tiene su eco en el postflight** (las fuentes, la exención, el sello): un mutante del preflight que
  quite solo la del preflight muere por el postflight, no por la deriva. Para demostrar qué comparación protege hay que quitar las dos.
- **`pct_realizacion` de un origen con 1 realizada y divisor 0 sale `null`** (no 100 ni error): en el ROJO es lo que delata al
  origen `web`.
- **La Gerencia que elige el banco es `GER_ADMIN` (admin del Portal + Gerencia del CRM)**, por orden alfabético; la métrica no
  depende del usuario (D-17 no aplica), pero se anota en las medidas.
- **La foto de los `assert_*` truncada a 160 caracteres (ronda 1) perdía texto de verdad:** en el laboratorio dos gates que caen
  tienen mensajes íntegros de 412 y 611 caracteres (`assert_analista_vigencia`, `assert_auditoria`). Con los 36 gates de hoy la foto
  truncada y la íntegra dan el mismo veredicto; para demostrar que la íntegra compara el texto entero hizo falta sembrar un gate
  cuyo error cambie solo después del carácter 160 (deriva D14): la migración íntegra lo rechaza y la truncada lo deja pasar.
