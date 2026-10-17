# Paso 3a «SLA por filas»: migraciones v2 y re-ensayo · RESULTADO

17/10/2026, 11:07 → 12:53 (hora de Lima, tomada con `date`).

- **Dónde:** copia aislada `/Users/usuario/dev/avancecorp-crm-foto-sla`, rama `crm/sla-por-filas-20261017`. Banco Docker
  `foto-sla-f2-db`: PostgreSQL 17.6, esquema de producción con la opt1 y 3.869 leads sintéticos.
- **Cómo se corrió:**
  - Migraciones, `verificar`, reversas y registradores: como **postgres**.
  - Arneses y sonda: como supabase_admin. Las puertas se llaman como `authenticated`; las piezas privadas, como su dueño.
- **Qué no se tocó:** producción, git, Codex y otros agentes.
- **El banco queda con M1–M3 APLICADAS**, como pediste, para el ensayo de carga. Ver «Estado final del banco».

## En corto

- **M1–M3 corregidas** con todo lo que pidieron las tres revisiones (Codex, auditor-rls y el verificador independiente), y
  **regeneradas**: huellas, reversas, `verificar`, registrador del índice y registradores nuevos de las reversas.
  - Mismos nombres de versión que la v1: no se confirmaron ni se aplicaron fuera del banco.
- **Re-ensayo completo sobre las versiones finales**, con este resultado:
  - **48 pasos como se esperaba, 0 inesperados** (más 9 corridas de `verificar`), de 11:55:32 a 12:52:10. Cubren: aplicar,
    negativas (repetir, fuera de orden, historial, productor cambiado, guardián en rojo), reversas con su ciclo de registro y
    reaplicación.
  - **Equivalencia, mi arnés:** 2.021 comparaciones, 0 diferencias.
  - **Equivalencia, arnés del verificador:** 7.172 comparaciones, 0 diferencias.
    - Las cadenas de un solo reloj quedaron **PARCIALES**: 168 de 239 terminadas (4.811 páginas) y 71 **NOT RUN**. Se
      cortaron a las 12:51:37 a pedido del coordinador, para liberar el banco.
  - **Empates «pendiente sin acción» (H1):** ahora salen en el MISMO orden. `12-repro-empates.sql` da igualdad en jsonb y texto,
    y las posiciones de los empates NULL coinciden.
  - **Mutantes:** 26 de 26 detectados. Son los 11 del escritor, los 8 del verificador (de esos 8, la v1 no detectaba 6) y 7
    nuevos. El `14-mutantes.sql` original del verificador da 8 de 8.
  - **Mutantes de la migración:** con su versión ya en el índice, con el productor cambiado y con un guardián en rojo, M1, M2
    y M3 se niegan y no dejan nada.
  - **Reversa M1:** se niega con un consumidor en MAYÚSCULAS y con una vista que depende de `_filas`.
  - **Memoria de gerencia:** avisos de 104–123 a 35–48 MiB; cola de 210–235 a 41–55 MiB. El envoltorio y Gestión Diaria no
    suben.
  - **Censo analítico:** igual antes y después (`45 · ff12620b…`).
  - **Checks locales:** `test:rls:preflight`, `seed:preflight` y `check:scripts` PASS. `test:rls` completo: NOT RUN.

## Qué cambió frente a la v1 (cada punto de las revisiones → cambio → prueba)

| Origen | Punto | Cambio en la v2 | Prueba en el banco |
|---|---|---|---|
| Codex P1 | Historial | Cada migración comprueba, **antes de cualquier DDL**, si su versión ya está en `supabase_migrations.schema_migrations` (`to_regclass` + `execute`). LEEME: «commit hecho, registro pendiente» y la reaplicación con versiones nuevas. **Registradores nuevos** de las 3 reversas: `registrar-reversa-m1/m2/m3.sql`, pedidos también por el auditor (P3). | En ROLLBACK, M1, M2 y M3 con su versión ya en el índice se niegan. Ciclo completo con índice de prueba (abajo): la M1 original se niega tras las reversas registradas; se reaplica con versiones nuevas. |
| Codex P2 | Firma de `_filas` | La cola llama a `_filas(null::uuid[])`. | Mutante con la sobrecarga `_filas(text)` (dueño, ACL y forma permitidos): detectado por el guardián nuevo de sobrecargas. |
| Codex P2 | Reversa M1 y sus consumidores | Busca usos con `~*` (sin distinguir mayúsculas) y **además** en `pg_depend`. | En ROLLBACK: un consumidor con `PRIVATE.SLA_OPERACION_AUTORIZADA_FILAS(` y una vista sobre `_filas` hacen que la reversa M1 se niegue. |
| Codex P2 | Existencia de las firmas | `assert_sla_nucleo` exige que EXISTAN las 6 firmas obligatorias y prohíbe sobrecargas de autorizada, `_filas`, ámbito y núcleo. | Mutantes «borrar solo el ámbito» y «sobrecarga del ámbito (text, boolean)»: detectados. |
| Codex P2 | Productor en M2 | Los manifiestos de M2 (y de M1 y M3) exigen el productor, el helper y `sla_leads_operativos`. | En ROLLBACK: «productor cambiado» (una línea de comentario más) hace que M2 y M3 se nieguen con PREFLIGHT. |
| Codex P2 | Unicidad en M3 | Identidad por fila con `WITH ORDINALITY`: la página se reconstruye por `fila`, nunca por `lead_id`. Unicidad demostrada además por el esquema (LEEME). | Arnés completo, 0 diferencias. |
| Verificador H1 | Orden con «pendiente sin acción» | Si alguna candidata de lead tiene clave NULL, la cola arma la secuencia completa de candidatas como antes y pagina con el **algoritmo anterior, con el mismo texto SQL**. En el caso normal, el camino por filas. | `12-repro-empates.sql`: igual en jsonb y en texto; posiciones `56:0e9c3bf6 57:0e1738f1 58:07b3292f 59:068d7b55 60:03b09730` iguales en las dos. Batería E1 del verificador (N = 2…70): ver abajo. Prueba propia en ROLLBACK: 42 de 42. |
| Verificador H2 | Sellos de la autoridad | `assert_sla_nucleo` sella por md5 (`pg_get_functiondef`) el ámbito, `_filas` y el envoltorio; `assert_sla_avisos` sella el resumen. Los 3 guardianes fijan `quote_all_identifiers = off` (y `search_path = ''`). | Los 6 mutantes de autoridad del verificador que la v1 no veía (V1, V2, V3, V6, V7, V8) ahora se detectan, en mi lote y en su `14-mutantes.sql` original. |
| Auditor P2 | `test-rls` | `testSlaPorFilas(sessions, seed)` añade: <br>· `vendInactive` y `clientBank` → 42501 en avisos y en `estado_sla_leads_v2_fn`;<br>· `estado_sla_leads_v2_fn` de vend1 con el lead de vend3 → `filas` vacío, y gerencia sí lo ve;<br>· en la cola v3 de vend1, todo lead es suyo;<br>· sup1 sin leads del equipo de sup2;<br>· vend1 ≤ sup1 ≤ gerencia;<br>· C, D y E sin `CRM_BANCO_PSQL_URL`. | `node --check` y preflight PASS. `test:rls` completo NOT RUN (sin pila con fixtures). |
| Auditor P3 | Lista permitida y códigos de la API | Lista PERMITIDA de llamadas privadas en el resumen (`assert_sla_avisos`) y en la cola (`assert_cola_v3`). El check de la API exige `PGRST106`/`PGRST202`/`42501`. | Mutantes «resumen llama a `sla_hechos_actuales`» y «cola llama a `sla_tareas_hechos`»: detectados. |
| Verificador P3 | Comentarios, ACL de `verificar` y cifras | `COMMENT ON` nuevo de la cola y del resumen (las reversas reponen el viejo), y comentario de `_filas` que vale en cualquier estado. La ACL de `verificar` mira TODOS los roles no superusuario ajenos a postgres, más `aclexplode`. Las cifras de memoria están en el LEEME y en este informe, y las cabeceras remiten al LEEME. | `verificar` en ANTES, M1, M2 y M3: «ninguna» en las dos líneas de ACL. |
| Codex (gate) | Gate de la serie completa | `verificar` informa «GATE SERIE COMPLETA (exige M3)», y `test-rls` con `CRM_RLS_EXIGE_SLA_FILAS=1` exige que el resumen y la cola lean `_filas`. | ANTES, M1 y M2: «NO»; M3: «OK». |
| Codex / auditor | Censo analítico | `verificar` informa el censo (`private.contadores_crudos_leads_citas()`, sin `bench`). | `45 · ff12620b…` en ANTES, M1, M2 y M3. |
| Codex (heredado) | `AUTH.` en mayúsculas | `assert_sla_nucleo` busca `auth.` con `~*`. | Mutante «`_filas` lee `AUTH.uid()`»: detectado. |
| Hallazgo propio v1 | Memoria del envoltorio | (ya en la v1 final) un solo `jsonb_build_object`. | Sonda v2: el envoltorio y Gestión Diaria no suben. |

## Huellas v2 (`md5(pg_get_functiondef)` / `md5(prosrc)`, con `search_path` vacío)

| Pieza | ANTES (= producción) | v1 | **v2** |
|---|---|---|---|
| `private.sla_operacion_ambito` | — | `e843f6cd` / `b75fb4c8` | `e843f6cd039b92a5fcd1e629d6ad4138` / `b75fb4c86471cba36687c15986bd60dc` (igual) |
| `private.sla_operacion_autorizada_filas` | — | `5aa19153` / `25086396` | `5aa191534358b819d8b8f0254f91c471` / `250863962d4a0a5adb564d2e7c8a39cb` (igual; cambia su comentario) |
| `private.sla_operacion_autorizada` | `a5bd718f` / `a5fd870b` | `4cdaa81a` / `7d8c8793` | `4cdaa81a538473ea322ca5e4835652d4` / `7d8c87935730be5f3b43559dc05e977a` (igual) |
| `crm.avisos_sla_resumen_v2_fn` | `e9ce617a` / `576b1aa6` | `82a7cabd` / `3387f3af` | `82a7cabdae761ea7b3707db9f9c62452` / `3387f3aff90b1e47e05bcddea14a91e3` (igual; cambia su comentario) |
| `crm.cola_accion_v3_fn` | `1ec76074` / `828989da` | `42995384` / `4216ba0c` | **`6096aa636688f01677327c5504ffaa8b` / `34b5abf032aac26cf5453f6e85f3d370`** |
| `private.assert_sla_nucleo` | `6bc541b2` / `dfdbedf7` | `02aee10e` / `f987b411` | **`a938047d5c98aa009984a9e836b2fc9d` / `7f5a08dde907b343b8562b6024eba110`** |
| `private.assert_sla_avisos` M1 | `9b9edc86` / `0eeb9efe` | `fb433efc` / `7c600760` | `fb433efc037f09647481744a5f36380c` / `7c6007603919f41406649edffa63429d` (igual) |
| `private.assert_sla_avisos` M2 | | `3be6ffa6` / `d04b0b71` | **`1cbce7c3cdd9d39e61e9c26af29a9f7e` / `d307e5acaa84517072d8f65db882c1f3`** |
| `private.assert_cola_v3` | `162fe9e0` / `97d9d1b9` | `32306af3` / `edd6bb2c` | **`5b000de8271604d1c6780dcc2425e90f` / `862b765b58b1cb7725b375b587733b81`** |

- **Familia SLA:**
  - ANTES `62 · 1adaf6c5708637fd916705cc090a4218`;
  - M1 `64 · 1a632cfd48a2cc1602646a8fb0fb5285`;
  - M2 `64 · 5e4e27c4548576663fa65b801a839f0e`;
  - M3 `64 · f9ea903841b9186ac985e103e050e6d5`.
- **Sellos de los guardianes:**
  - ámbito `e843f6cd…`, `_filas` `5aa19153…` y envoltorio `4cdaa81a…`, en `assert_sla_nucleo`;
  - resumen `82a7cabd…`, en `assert_sla_avisos`;
  - cola `6096aa63…`, en `assert_cola_v3`.
- **SHA-256 de los archivos:**
  - M1 `e9c491d6c1167b8e88bf7ee13771ef729bf1b3b20c0f5cf4ff8c4a98034d1a28`
  - M2 `468624e2631271bcbbf1e8f2937dbf816d3b6b2a30964b702c29f1134dc8191f`
  - M3 `94f695cbcfcb70b8259a69500279a586eae6eee6135978ca9ddb0e89fdd372cf`
- **Generador:** `ensayo-3a/migraciones/generar.py` (v2; el de la v1 queda en `generar.v1.py`).
  - Mide en una transacción con ROLLBACK (`medir.sql` → `medido.json`).
  - Comprueba sus propias predicciones contra lo medido antes de escribir.
  - La v1 completa queda en `real/gen2-v1/`.

## Salidas de `verificar.sql` (re-ensayo v2, como postgres)

`real2/resultados-pasos.txt` tiene el informe completo de cada paso. Extracto de los cuatro estados:

```
ANTES  SERIE=ANTES · familia SLA=62 · 1adaf6c5… (la esperada) · GATE SERIE COMPLETA (exige M3): NO · exigidas: IGUALES
       ámbito y _filas AUSENTES; autorizada, resumen, cola y guardianes ANTES
M1     SERIE=M1 · 64 · 1a632cfd… (la esperada) · GATE: NO · exigidas: IGUALES
M2     SERIE=M2 · 64 · 5e4e27c4… (la esperada) · GATE: NO · exigidas: IGUALES
M3     SERIE=M3 · 64 · f9ea9038… (la esperada) · GATE SERIE COMPLETA (exige M3): OK · exigidas: IGUALES
En los cuatro:
  ACL efectiva de las piezas privadas, todos los roles: ninguna
  ACL guardada fuera del dueño: ninguna
  ACL de las puertas: authenticated y crm_gestion_diaria_lector (por herencia, igual que antes)
  Censo analítico: 45 · ff12620be8b56014308627a3ef249a16
  assert_sla_nucleo, assert_cola_v3, assert_sla_avisos y assert_f7_piezas_cerradas: OK
  assert_gestion_diaria, assert_analitica_leads_citas y assert_analista_vigencia: FALLA PREEXISTENTE (igual antes y después; causas ajenas)
```

## Equivalencia

**Mi arnés** (real nueva contra copia `bench.v0_*` de la versión anterior; una sentencia por comparación; igualdad jsonb Y de
texto, o el mismo SQLSTATE, mensaje, detalle y pista), 17/10 de 11:55 a 12:05:

| Corrida | Comparaciones | Iguales | Diferencias |
|---|---|---|---|
| RV2 bloques A–G (envoltorio, avisos, cola: señales, etapas, analistas, límites, 16 cadenas hasta el final, 40 cursores alterados, actores alternados, modos E1–E6 en ROLLBACK y los 5 consumidores) | 1.984 | 1.984 | 0 |
| Casos sueltos: «solo clientes», cero candidatas, analista inactivo (23); página posterior al final (6); tarea de cliente anómala 22000 (8) | 37 | 37 | 0 |
| **Total** | **2.021** | **2.021** | **0** |

- 416 de las comparaciones son de los 5 consumidores del envoltorio.
- Errores iguales en las dos versiones: 0A000, 22009, 22023 (5 mensajes), 23514, 42501 (3 mensajes), P0002 y 22000.

**Arnés del verificador** (sus scripts, sin cambios, copiados a `real2/verificador/` para no pisar sus salidas; sus copias
`bench.vi_*`). Corrida del 17/10 de 12:08:08 a 12:51:37 (`real2/verificador/correr.sh`); resumen con `resumen-v2.sql`,
solo con filas nuevas (`id > 13467`), en `real2/verificador/salida-resumen-v2.txt`:

| Bloque | Comparaciones | Diferencias | Con el mismo error en las dos | Usuarios |
|---|---|---|---|---|
| A · envoltorio y sus consumidores | 980 | 0 | 96 | 35 |
| B · avisos e identidades | 200 | 0 | 100 | 35 |
| D · cambios de datos (ROLLBACK) | 678 | 0 | 25 | 7 |
| D6 · modos y directorio (ROLLBACK) | 203 | 0 | 9 | 5 |
| E · cursores alterados y precedencia | 198 | 0 | 152 | 3 |
| E1 · empates NULL, N = 2…70 (ROLLBACK) | 102 | 0 | 0 | 2 |
| C · un reloj por cadena, hasta el final (**PARCIAL**) | 4.811 | 0 | 0 | 9 |
| **Total** | **7.172** | **0** | 382 | |

- **`12-repro-empates.sql`:** `jsonb_igual = t` y `texto_igual = t`, total 62, `hay_mas = true`. Las posiciones de los empates
  NULL son las mismas en las dos: `56:0e9c3bf6 57:0e1738f1 58:07b3292f 59:068d7b55 60:03b09730`.
- **Cadenas de un solo reloj, PARCIAL.** Se cortaron a las 12:51:37, a pedido del coordinador, para liberar el banco para la
  prueba de carga. Cómo se cortó:
  - kill del psql y de sus scripts;
  - no quedó ningún backend vivo;
  - sin DROP ni TRUNCATE.

  | Bloque | Cadenas | Terminadas (`fin`) | NOT RUN | Páginas comparadas | Diferencias |
  |---|---|---|---|---|---|
  | RC1g | 13 | 13 | 0 | 1.475 | 0 |
  | RC1n | 41 | 41 | 0 | 1.987 | 0 |
  | RC2g | 118 | 49 | **69** | 419 | 0 |
  | RC2n | 56 | 56 | 0 | 709 | 0 |
  | RC3g | 2 | 0 | **2** | 0 | 0 |
  | RC3n | 9 | 9 | 0 | 221 | 0 |
  | **Total** | **239** | **168** | **71** | **4.811** | **0** |

  - La tanda `n` terminó entera a las 12:39:15. De la tanda `g` terminaron 62 de 133.
  - Las 71 NOT RUN siguen en `pagina = 0`, sin resultados. La que estaba en curso al cortar se deshizo con su sentencia.
  - En `salida-10-un-reloj-g.txt` faltan 1 de las 62 líneas «fin». El psql murió antes de escribirla, pero la base la da por
    terminada; cuenta la base.
  - Ninguna cadena se cortó por «Cursor incompatible» ni por error: todas las 168 llegaron a `hay_mas = false`.

## Memoria y tiempo (sonda RSS y EXPLAIN ANALYZE BUFFERS; gerencia, `work_mem` 7 MB; banco en reposo; 17/10 12:05–12:08)

| Caso | Viejo (`bench.v0_*`): pico MiB · ms | Real v2: pico MiB · ms | Temporales escritos (bloques) |
|---|---|---|---|
| Avisos | 104,0 · 122,4 · 105,8 (379 / 347 / 343) | **35,0 · 42,2 · 42,5** (270 / 255 / 252) | 4.947 → 2.413 |
| Cola (50, `pendientes`) | 223,2 · 221,4 · 212,8 (814 / 784 / 778) | **41,3 · 50,8 · 50,9** (431 / 417 / 413) | 15.334 → 5.409 |
| Cola (50, `todas`) | 226,3 · 209,9 · 226,3 (812 / 837 / 778) | **41,3 · 50,7 · 50,8** (493 / 445 / 402) | 15.492 → 5.409 |
| Envoltorio, operativos | 105,0 · 114,4 · 115,8 | 116,1 · 106,4 · 107,5 | — |
| Envoltorio, todas | 150,8 · 168,0 · 168,0 | 153,7 · 162,0 · 151,6 | — |
| Gestión Diaria (equipo) | 103,9 · 107,3 · 108,7 (364 / 397 / 383) | 104,8 · 98,8 · 110,7 (385 / 334 / 346) | 3.740 → **5.041** |

- **Misma conexión, alternando viejo y nuevo (AB y BA):**
  - la versión nueva no pasa de 48 MiB (avisos) ni de 55 MiB (cola);
  - la vieja vuelve a 105–123 MiB (avisos) y a 213–235 MiB (cola).
- **Tiempo de ejecución** (EXPLAIN ANALYZE BUFFERS):
  - avisos: 311–375 → 218–245 ms;
  - cola: 736–775 → 379–442 ms;
  - Gestión Diaria: 312–326 → 313–332 ms.
- Son las mismas cifras que el LEEME.

## Mutantes

**Lote v2 sobre las piezas reales con M3** (`real2/mutantes-v2.sql`, en ROLLBACK, cada uno en su savepoint): **26 de 26
detectados**. Tras el ROLLBACK, los 3 guardianes en OK.

| Origen | Mutantes | Detectados |
|---|---|---|
| Escritor (v1) | resumen sin acotar · `_filas` acotada + envoltorio sin acotar · resumen vuelve al bloque · `_filas` con EXECUTE para authenticated · ámbito con EXECUTE para PUBLIC · `_filas` sin DEFINER · `_filas` lee `auth.` · la cola vuelve a llamar al envoltorio · la cola con un byte cambiado · dueño de `_filas` cambiado · el envoltorio deja de usar el ámbito | 11/11 |
| Verificador (V1–V8) | `_filas` global · ámbito `es_global = true` · ámbito sin 42501 · EXECUTE a `crm_metricas_bridge` · ámbito DEFINER · `_filas` sin filtro de supervisión · el resumen cuenta todas las filas · el envoltorio `false` con hechos globales | **8/8** (v1: 2/8) |
| Nuevos (revisiones) | sobrecarga `_filas(text)` · borrar solo el ámbito · `AUTH.uid()` en mayúsculas · el resumen llama a `sla_hechos_actuales` · la cola llama a `sla_tareas_hechos` · `_filas` cambia solo un comentario de su cuerpo · sobrecarga `ambito(text, boolean)` | 7/7 |

**Otras pruebas de mutantes:**
- **El `14-mutantes.sql` original del verificador**, sin cambios: 8 de 8 detectados (en la v1, 2 de 8). El efecto observable vuelve
  a la base tras el ROLLBACK: el vendedor 9 tiene 319 filas, 0 ajenas, y la cola sin sesión da 42501.
- **Mutantes de la migración** (`real2/envuelto.sh`): el cuerpo de la migración corre dentro de una transacción externa con
  ROLLBACK.

  | Migración | Mutante | Resultado |
  |---|---|---|
  | M1, M2 y M3 | Su versión ya está en el índice | Se niegan |
  | M2 y M3 | Productor cambiado | Se niegan con PREFLIGHT |
  | M1, M2 y M3 | Guardián en rojo | Se niegan con «SLA: falta RLS en sla_operacion_control» |
  | Reversa M1 | Consumidor en MAYÚSCULAS | Se niega |
  | Reversa M1 | Vista que depende de `_filas` | Se niega |

## Reversas, ciclo de historial y reaplicación

`real2/ciclo-historial.sh`, 17/10 de 12:52:06 a 12:52:10, como postgres. Salida completa en
`real2/resultados/ciclo-historial-salida.txt` y en `resultados-pasos.txt`. **24 de 24 pasos como se esperaba, 0
inesperados.**

El índice `supabase_migrations.schema_migrations` es de PRUEBA, con la misma forma que el de Supabase. Se creó vacío y se
quitó al final, porque el banco no lo trae.

| Paso | Resultado |
|---|---|
| Registrar M1–M3 en M3 · otra vez (idempotente) | ok · ok (3 filas: `054425/26/27`) |
| `registrar-reversa-m3` sin haber revertido | se niega: «la serie viva es M3 y esta reversa deja M2» |
| M1 original con su versión ya registrada | se niega: «la versión 20261017054425 ya está en … schema_migrations» |
| Reversa M3 → `verificar` | ok → **SERIE=M2 · 64 · 5e4e27c4…**, gate NO, ACL «ninguna», censo `45 · ff12620b…` |
| `registrar-reversa-m3` del kit SIN poner la versión | se niega: «falta poner en v_version la versión NUEVA» |
| Registrar la reversa M3 (990003) · otra vez | ok · ok (idempotente) |
| Reversa M3 por segunda vez | se niega (PREFLIGHT: `assert_cola_v3` ya no es la de M3) |
| Reversa M2 → `verificar` → registrar (990002) | ok → **SERIE=M1 · 64 · 1a632cfd…** → ok |
| Reversa M1 con un consumidor en MAYÚSCULAS | se niega: «todavía usan … `bench.mut_consumidor_mayusculas()`» |
| Reversa M1 con una vista sobre `_filas` | se niega: «todavía usan … `rule _RETURN on view bench.mut_vista_filas`» |
| Reversa M1 → `verificar` → registrar (990001) | ok → **SERIE=ANTES · 62 · 1adaf6c5…** → ok |
| Reversa M1 por segunda vez | se niega (PREFLIGHT) |
| REAPLICAR M1 ORIGINAL tras las reversas registradas | se niega: «la versión 20261017054425 ya está en … schema_migrations» |
| Registrar en ANTES | se niega: «la serie viva no es M1, M2 ni M3» |
| Aplicar M1, M2 y M3 con versiones NUEVAS (990011/12/13) → `verificar` | ok, ok, ok → **SERIE=M3 · 64 · f9ea9038…**, gate OK |
| Registrar las versiones nuevas · M3 nueva por segunda vez | ok · se niega («la versión 20261017990013 ya está…») |
| Registrar con una fila ajena (990012 alterada a mano) | se niega: «ya existe con otro contenido; no se toca» |
| `verificar` FINAL | **SERIE=M3 · 64 · f9ea903841b9186ac985e103e050e6d5 (la esperada)** |

- **Las copias con versiones nuevas** salen de `generar.py escribir 20261017990011 20261017990012 20261017990013` (en
  `real2/nuevas/`). Son idénticas a las originales salvo los números de versión: 0 líneas distintas al igualarlos.
  - Las huellas de las funciones son las mismas, porque la familia da `f9ea9038…` igual que con las originales.
- **Índice al final** (antes de quitarlo): 9 filas. Son las 3 originales, las 3 reversas `99000n` y las 3 nuevas `99001n`.
  - La 990012 tiene el contenido alterado a propósito; el registrador no la pisó.
- **Registradores de reversa de prueba** (`real2/prueba/`): copias del kit con UNA sola línea cambiada, `v_version`. El
  script lo comprueba con un diff de 2 líneas.

## Estado final del banco (anotado)

Comprobado a las 12:52:27–12:52:28 (`verificar.sql` independiente, como postgres, y `pg_stat_activity`):

- **M1–M3 APLICADAS**: `SERIE=M3 · familia SLA=64 · f9ea903841b9186ac985e103e050e6d5 (la esperada)` y
  `GATE SERIE COMPLETA (exige M3): OK`.
  - Piezas exigidas: IGUALES.
  - ACL efectiva y guardada de las piezas privadas: «ninguna».
  - Puertas: `authenticated` y `crm_gestion_diaria_lector`.
  - Censo `45 · ff12620be8b56014308627a3ef249a16`.
  - Guardianes del SLA y F7: OK. Los tres guardianes ajenos siguen en la FALLA PREEXISTENTE de siempre.
- **Se aplicaron con las copias de versiones NUEVAS** (`20261017990011/12/13`) del ciclo de historial. Las funciones son byte
  a byte las de M1–M3 v2 (misma familia, mismas huellas). Para el ensayo de carga no hay diferencia.
- **Sin `supabase_migrations`**: el índice de prueba se quitó; el banco no lo traía.
- **Banco LIBRE**: 0 backends de cliente conectados. Las cadenas y los vigías locales están parados.
- **Andamiaje en `bench`** (no existe en producción, y no estorba al ensayo de carga):
  - mis copias `bench.v0_*` y `bench.sla_aut_*`;
  - las `vi_*` del verificador, más 7.207 filas suyas nuevas en `bench.vi_resultados` (`id > 13467`);
  - `bench.vi_cadenas` con 71 cadenas R% sin terminar (`pagina = 0`).

## Lo que queda abierto

0. **71 cadenas de un solo reloj del verificador: NOT RUN**, cortadas para liberar el banco: 69 de RC2g y 2 de RC3g.
   - Para completarlas: `bash correr-un-reloj-pat.sh <salida> 'RC_g'` en `real2/verificador/`. Retoma solo las `not terminada`.
   - Lo que sí corrió no tiene diferencias: 168 cadenas, 4.811 páginas.
1. **`test:rls` completo con fixtures: NOT RUN.** Necesita una pila Supabase con fixtures. Con `CRM_RLS_EXIGE_SLA_FILAS=1` exige M3.
2. **Ensayo de carga concurrente: pendiente antes del «!».** Debe cubrir 30+ consultas a la vez, Gestión Diaria y llamadas
   mezcladas, con la configuración de producción. Es el siguiente paso: el banco queda con M1–M3 aplicadas para eso.
   Gestión Diaria escribe +1.301 bloques (≈ +10 MiB) de temporales por llamada de «equipo».
3. **Codex de cierre** sobre la v2.
4. **Traer el tronco** (`avancecorp/main` avanzó a `6f176603`) antes de la PR.
5. **Fase 4:**
   - los consumidores que siguen sobre el envoltorio: Gestión Diaria, `cola_accion_v2_fn` y `estado_sla_leads_v2_fn`;
   - la parte de clientes de la cola, que vuelve a calcular rol, global y visibles aparte del ámbito (igual que antes; lo anotó el
     auditor).
6. **Heredado, no lo introduce el 3a:**
   - con ítems «sin acción» al final de una página, el cursor sale con `prioridad` null y la página siguiente se rechaza en las
     dos versiones (verificador H6);
   - paginar con el tiempo puede dar «Cursor incompatible».
7. **Límite de la búsqueda de consumidores** de la reversa M1: no puede probar la ausencia de llamadas dinámicas construidas por
   partes.
8. **Andamiaje en `bench`,** que no existe en producción:
   - mis copias `bench.v0_*` y las del ensayo anterior;
   - las `vi_*` del verificador;
   - más filas suyas en `bench.vi_resultados` (`id > 13467`).

