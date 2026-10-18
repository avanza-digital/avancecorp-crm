# Paso 3a · experimento 2×2 de `estado` y Gestión Diaria bajo concurrencia

17/10/2026. Comprobaciones previas a las 14:50; tanda de medida de 15:00:22 a 15:59:36 (hora de Lima, `date`).
- **Banco:** `foto-sla-f2-db` (4 GiB sin swap, 2 CPU, `work_mem` 7 MB, `statement_timeout` 8 s).
- **Serie:** los archivos FINALES:
  - md5: M1 `6aa3cb8b…`, M2 `671e3690…`, M3 `e6b4e533…`, reversas `041ab08c…`/`e1258629…`/`5a581d44…`, verificar `0be75304…`;
  - familia de M3: `64 · f9ea9038…`.
- **Estado final:** serie en M3 (`64 · f9ea903841b9186ac985e103e050e6d5`), comprobada con `verificar.sql` al cerrar cada
  corrida. Banco libre: ningún `arnes.py` ni contenedor `foto-sla-f2-arnes-*` vivos, y 0 conexiones del arnés (16:00).
- **Arnés:** `fase2/arnes/arnes.py` con las opciones nuevas (LEEME, «Sonda dedicada, esperas y Gestión Diaria»). Copia previa:
  `arnes.py.antes-2x2`.
- **Las reglas del veredicto no se cambiaron.** Todas las cifras de este informe salen de los archivos de abajo.

## Lo esencial

1. **El 2×2 no encuentra que la `estado` nueva haga más trabajo, ni sola ni bajo contención.**
   - **Sonda dedicada** (una conexión fuera del pool, que alterna vieja y nueva dentro de la MISMA tormenta):
     - la nueva gasta la misma CPU por llamada que la vieja: +0,08 ms con la carga nueva (IC 95 % [−0,27, +0,43]) y +0,05 ms
       con la vieja ([−0,11, +0,22]), sobre ~3,3 ms;
     - su transcurrido mediano difiere +0,08 ms ([0,03, 0,13]) y −0,01 ms ([−0,06, 0,04]);
     - el p95 por tormenta, nueva/vieja: mediana +4,1 % y +3,4 %. El control, con las dos sondas viejas (variante A), da +1,3 % y
       +4,0 %.
   - **Por qué se alarga bajo contención:** la sonda espera CPU. Su p95 (~95 ms) es casi todo cola de CPU del kernel (p95 89–97
     ms), y el tiempo bloqueado es ≈ 0. El pool tiene de media 18–20 conexiones activas en CPU, y solo 0,1–0,5 en LWLock y ~0,1
     en E/S, **igual en A que en B**. No se sostiene la hipótesis de que en A las pesadas esperan E/S de temporales.
2. **El p95 de `estado` del pool (el del criterio) es más ruido que señal con 3–4 réplicas por variante.**
   - La misma comparación normal ANTES frente a M3, repetida, dio +13,9 % a las 12:57 (NO PASA) y −17,1 % a las 15:10 (PASA).
   - Comparaciones en las que la llamada `estado` del pool es el mismo código viejo en A y en B dan de −12,5 % a +4,5 %.
   - Los IC 95 % (bootstrap por réplica) del p95 agregado miden de 58 a 148 puntos de ancho, y más por rol; todos contienen el
     0.
   - La tolerancia del 10 % está por debajo de ese ruido. En «produccion», el p95 por réplica se mueve entre 210 y 1.204 ms, y en
     parte va con la CPU de otras sesiones en la VM (ρ de Spearman = 0,45; n 42).
3. **Gestión Diaria «equipo» bajo concurrencia (mismo criterio): NO PASA (con reservas), otra vez SOLO por el p95 de `estado`**
   (897 → 1.002 ms, +11,6 %).
   - Memoria: pico 2,188 → 1,810 GiB (las 3 de B por debajo de las 3 de A).
   - Temporales por ronda: −27,0 %.
   - p95: avisos −29,9 %, cola −30,4 % y Gestión Diaria −19,9 %.
   - Lo que señaló Codex: los temporales de Gestión Diaria **sí suben**, +36,8 % por llamada en la tormenta (14,12 → 19,32 MiB)
     y +34,7 % la de gerencia sola (29,36 → 39,56 MiB, ≈ +1.306 bloques; la v2 midió +1.301). Aun así, el total de temporales
     baja.

**Lectura (para revisar; no cambia el veredicto):**
- El NO PASA se reproduce en 2 de 4 comparaciones normales de hoy en «produccion» (12:57 y la de Gestión Diaria). En las otras
  dos sale PASA: la de 15:10, y la prueba corta AB de la mañana, que tiene una sola réplica por variante.
- La única diferencia de coste que mide la sonda en `estado` cabe en ±0,4 ms de CPU por llamada.
- Si se quiere un veredicto estable con este criterio de p95, hace falta mucho más que 3 réplicas por variante (ver «Qué falta»).
  Decidirlo es cosa del PRIMARY; yo no cambio la regla.

## 1. Comprobaciones previas (14:50, solo lectura)

`estado-2x2/comprobar.py`: transacción READ ONLY más llamadas en transacciones que se deshacen, por la misma vía del arnés.
Salida en `estado-2x2/comprobar-salida-20261017-1450.txt`.

- **Las copias viejas son las de producción.** Se compara `md5(prosrc)` tras deshacer el único cambio de la copia (el nombre
  del envoltorio):

  | Copia | md5 deshecho | Esperado |
  |---|---|---|
  | `bench.v0_sla_operacion_autorizada` | `a5fd870b…` | ANTES (opt1) |
  | `bench.v0_avisos_sla_resumen_v2_fn` | `576b1aa6…` | ANTES |
  | `bench.v0_cola_accion_v3_fn` | `828989da…` | ANTES |
  | `bench.v0_estado_sla_leads_v2_fn` | `2eb2e3fa…` | el de `crm.estado_sla_leads_v2_fn` vivo (la serie no lo toca) |

  - Las cuatro: DEFINER, `search_path=""`, dueño `postgres` y la misma ACL que su original.
  - Llaman a `bench.v0_sla_operacion_autorizada`, el envoltorio viejo. En `v0_cola`, la otra mención de
    `sla_operacion_autorizada` está en un comentario (`estado-2x2/residuo-cola.sql`).
- **Se pueden llamar como `authenticated`:** EXECUTE y USAGE en `bench` concedidos.
  - Como vendedor, `v0_estado = crm.estado`, `v0_avisos = crm.avisos` y `v0_cola = crm.cola`, todas `true`, con la serie en M3.
  - Como gerencia, `v0_avisos = crm.avisos`, `true`.
- **Gestión Diaria «equipo»** se puede llamar como supervisor (10.970 caracteres) y como gerencia (25.617). La cadena es:
  - `crm.gestion_diaria_equipo_fn(date,uuid)` (INVOKER, `2a74a228…`);
  - → `private.gestion_diaria_equipo_core` (INVOKER);
  - → `private.gestion_diaria_equipo_pendientes()` (DEFINER, `f59c18f7…`);
  - → el envoltorio `private.sla_operacion_autorizada`.
- **`pg_read_file` NO está permitido** al dueño (`permission denied`): `postgres` no es superusuario en Supabase. Por eso la
  sonda lee `/proc/<pid>/schedstat` y `/proc/<pid>/stat` de su backend con un bash persistente DENTRO del contenedor, que solo
  usa *builtins* y no crea un proceso por lectura (~1 ms por lectura).
  - Comprobado: `schedstat` en ns cuadra con `utime`+`stime`.
  - Mientras el backend espera al cliente no gasta CPU ni cola, así que el delta entre las dos lecturas es el de la llamada.

## 2. Diseño

| Celda (sonda, carga) | Dónde |
|---|---|
| (vieja, vieja) | A de cualquier corrida; con la sonda dedicada, B vieja de `resultados-serie-sonda-carga-vieja` |
| (nueva, nueva) | B de `resultados-serie` (12:57 / 13:05); B nueva de `resultados-serie-sonda` |
| (vieja, nueva) | B de `resultados-serie-estado-viejo` (coordinador, 14:27 / 14:35); B vieja de `resultados-serie-sonda` |
| (nueva, vieja) | **B de `resultados-serie-carga-vieja`** (15:00 «produccion», 15:47 «peor»): serie en M3, con `ARNES_SQL_AVISOS=select bench.v0_avisos_sla_resumen_v2_fn()` y `ARNES_SQL_COLA=select bench.v0_cola_accion_v3_fn(50,'pendientes',null,null,null)`; B nueva de `resultados-serie-sonda-carga-vieja` |

- **Mismos actores, argumentos y patrón de llegada** que las corridas de la mañana: misma semilla y mismas sesiones; solo
  cambia el SQL. Cada corrida alterna A y B. Así, su cociente B/A aísla un efecto con la deriva controlada:
  - normal = sonda + carga;
  - sonda vieja en las dos = solo carga;
  - carga vieja en las dos = solo sonda.
- **Más réplicas:** ABABABAB (4+4) en las tres corridas «produccion» nuevas sin Gestión Diaria. Con 4 réplicas por variante, el
  arnés fija 2 rondas medidas por réplica. Sigue habiendo ≥ 200 llamadas por consulta.
- **Sonda dedicada** (`--sonda vieja=… --sonda nueva=…`): el vendedor n 9 llama en bucle cerrado durante cada tormenta,
  alternando `bench.v0_estado_sla_leads_v2_fn('{}')` y `crm.estado_sla_leads_v2_fn('{}')`.
  - Cada ronda empieza por una distinta. La identidad se fija una vez; cada llamada es UNA sentencia.
  - Por llamada: transcurrido, CPU y cola de CPU del backend, y «resto» = transcurrido − CPU − cola (bloqueado: candados,
    LWLock, E/S, y la ida y vuelta local de psql).
  - Muestreo de `wait_event` cada 50 ms: la sonda y las conexiones activas del pool por clase de espera.
- **Otras sesiones:** CPU de los OTROS contenedores en cada réplica, de `docker stats` (todo menos la base y los auxiliares del
  arnés), y `loadavg` del Mac cada 10 s (`estado-2x2/host-carga-20261017.txt`).
- **Intervalos:**
  - p95 agregado del pool: bootstrap JERÁRQUICO por réplica (se remuestrean réplicas y, dentro de cada una, llamadas; 4.000
    iteraciones);
  - sonda: bootstrap de la media de las diferencias emparejadas por tormenta.

## 3. Resultados del 2×2

### 3.1 `estado` del pool (lo que mide el criterio): todas las comparaciones de hoy

`estado-2x2/resumen-repeticiones-20261017-1600.md` (ms, p95 de ejecución; los cortes valen 8.000):

| Escenario | Corrida | De A a B cambia | Réplicas | p95 por réplica A | p95 por réplica B | p95 agregado | Cambio | IC 95 % |
|---|---|---|---|---|---|---|---|---|
| produccion | `resultados-serie`, 12:57 | sonda + carga | 3/3 | 652 · 705 · 692 | 477 · 938 · 806 | 704 → 802 | **+13,9 %** | [−31,8 %, +53,9 %] |
| produccion | `resultados-serie-sonda`, 15:10 (con sonda dedicada) | sonda + carga | 4/4 | 996 · 999 · 976 · 793 | 780 · 991 · 701 · 290 | 913 → 757 | **−17,1 %** | [−59,7 %, +21,1 %] |
| produccion | `resultados-serie-gestion`, 15:29 (con Gestión Diaria) | sonda + carga | 3/3 | 813 · 967 · 897 | 1.202 · 1.093 · 573 | 897 → 1.002 | **+11,6 %** | [−32,4 %, +42,4 %] |
| produccion | `resultados-serie-estado-viejo`, 14:27 | solo carga | 3/3 | 210 · 443 · 448 | 232 · 484 · 355 | 396 → 414 | **+4,5 %** | [−46,0 %, +102,2 %] |
| produccion | `resultados-serie-carga-vieja`, 15:00 | solo sonda | 4/4 | 1.022 · 1.204 · 946 · 595 | 621 · 898 · 865 · 711 | 1.004 → 811 | **−19,2 %** | [−35,5 %, +34,8 %] |
| produccion | `resultados-serie-sonda-carga-vieja`, 15:19 (con sonda dedicada) | solo sonda | 4/4 | 569 · 609 · 777 · 1.005 | 485 · 882 · 891 · 947 | 780 → 860 | **+10,1 %** | [−29,5 %, +48,8 %] |
| peor | `resultados-serie`, 13:05 | sonda + carga | 3/3 | 798 · 703 · 568 | 1.094 · 800 · 283 | 703 → 915 | **+30,2 %** | [−58,5 %, +66,9 %] |
| peor | `resultados-serie-estado-viejo`, 14:35 | solo carga | 3/3 | 733 · 1.303 · 1.290 | 1.001 · 1.155 · 1.005 | 1.199 → 1.049 | **−12,5 %** | [−30,2 %, +31,6 %] |
| peor | `resultados-serie-carga-vieja`, 15:47 | solo sonda | 3/3 | 794 · 765 · 843 | 802 · 832 · 875 | 804 → 836 | **+3,9 %** | [−21,3 %, +36,4 %] |

- **Por rol** (`estado-2x2/analisis-20261017-1600.md`, IC bootstrap por réplica):
  - normal 12:57: vendedor +12,4 % [−33,1 %, +46,1 %] y supervisor +33,5 % [−32,4 %, +160,8 %];
  - sonda vieja: vendedor +12,0 % y supervisor +38,0 % (n 36 por variante);
  - carga vieja: vendedor −19,1 % [−36,1 %, +38,3 %] y supervisor −11,6 % [−58,6 %, +68,5 %].
  - En Gestión Diaria, el comparador da `estado` por rol: vendedor 863 → 959 ms (+11,1 %) y supervisor 1.005 → 1.229 ms
    (+22,3 %).
  - La subida «por rol» no se repite cuando solo cambia la sonda.
- **Control de ruido** con código idéntico: en `resultados-serie-carga-vieja` «produccion», avisos y cola son la MISMA copia
  vieja en A y en B. Aun así, su p95 cambia +7,31 % y +13,53 %, y el comparador da NO PASA por la cola.
- **Veredicto de cada corrida** con el criterio de siempre (`comparacion-*.md` de cada carpeta):
  - `resultados-serie-sonda`: **PASA (con reservas)**. Memoria 36,3 % → 26,6 %, temporales −55,4 %; p95 avisos −20,4 %, cola
    −21,7 % y estado −17,1 %;
  - `resultados-serie-carga-vieja` «produccion»: NO PASA (con reservas), por la cola (+13,5 %), que es el mismo código en las
    dos;
  - `resultados-serie-sonda-carga-vieja`: NO PASA, por `estado` +10,14 %, con la carga idéntica;
  - `resultados-serie-carga-vieja` «peor»: NO PASA (con reservas). Avisos y cola salen censurados en el corte, y los temporales
    por llamada completada, +14,4 %, con el mismo código.
  - Estas tres corridas con carga vieja no juzgan la serie: sirven para medir el ruido.

### 3.2 Sonda dedicada: las cuatro celdas («produccion», 4 réplicas por celda; `estado-2x2/celdas-sonda-20261017-1600.md`)

| Celda (sonda, carga) | Dónde | Llamadas | Transcurrido p50 / p95 / p99 ms | CPU media / p50 / p95 ms | Cola de CPU media / p95 ms |
|---|---|---|---|---|---|
| (vieja, vieja) | sonda-carga-vieja B | 535 | 3,1 / 95 / 202 | 3,35 / 3,00 / 5,55 | 16,7 / 91 |
| (nueva, vieja) | sonda-carga-vieja B | 536 | 3,1 / 95 / 202 | 3,40 / 3,06 / 5,80 | 17,3 / 91 |
| (vieja, nueva) | sonda B | 332 | 3,0 / 100 / 294 | 3,31 / 2,88 / 5,75 | 20,0 / 95 |
| (nueva, nueva) | sonda B | 330 | 3,0 / 99 / 202 | 3,41 / 2,97 / 5,68 | 20,8 / 97 |
| control A: vieja | sonda A | 538 | 3,0 / 93 / 200 | 3,17 / 2,93 / 4,71 | 15,8 / 90 |
| control A: `crm.estado` en ANTES (camino viejo) | sonda A | 537 | 3,0 / 96 / 293 | 3,21 / 2,97 / 5,02 | 18,8 / 92 |

**Emparejado por tormenta** (8 tormentas por fila; media de las diferencias e IC 95 % bootstrap):

| Corrida | Variante | Diferencia de medianas del transcurrido (ms) | CPU media por llamada (ms) | p95 nueva/vieja por tormenta: mediana (mín.–máx.) |
|---|---|---|---|---|
| carga nueva | B | +0,08 [0,03, 0,13] | +0,08 [−0,27, +0,43] | +4,1 % (−11,5 % … +86,4 %) |
| carga vieja | B | −0,01 [−0,06, 0,04] | +0,05 [−0,11, +0,22] | +3,4 % (−8,7 % … +22,5 %) |
| carga nueva | A (control: viejo frente a viejo) | +0,04 [−0,00, 0,09] | +0,04 [−0,16, +0,24] | +1,3 % (−4,2 % … +15,4 %) |
| carga vieja | A (control: viejo frente a viejo) | +0,03 [−0,07, 0,12] | −0,02 [−0,23, +0,18] | +4,0 % (−13,1 % … +15,6 %) |

- **Efecto de la sonda** (nueva − vieja con la misma carga): ≤ +0,1 ms de CPU por llamada, dentro de lo que da el control
  viejo-frente-a-viejo. No hay **interacción** visible: lo mismo con carga vieja y con nueva.
- **Efecto de la carga** sobre la sonda vieja: p95 95 → 100 ms y p99 202 → 294 ms con la carga nueva; la CPU por llamada no
  cambia (3,35 → 3,31 ms).
- **Dónde se va el tiempo:** el p50 (~3 ms) es la propia CPU. La cola del p95 (~95 ms) es espera en la cola de CPU, que cuadra
  con el estrangulamiento del cgroup de 2 CPU (periodos de 100 ms; 60–80 s estrangulados por réplica en «produccion»). El
  «resto» medio queda entre −0,34 y +0,82 ms.

### 3.3 Esperas del pool (`wait_event` cada 50 ms, rondas medidas)

| Corrida | Var. | Muestras | Activas en CPU | LWLock | IO | Lock |
|---|---|---|---|---|---|---|
| sonda (carga nueva en B) | A | 516 | 19,26 | 0,12 | 0,12 | 0,00 |
| sonda (carga nueva en B) | B | 355 | 20,28 | 0,20 | 0,10 | 0,00 |
| sonda-carga-vieja | A | 508 | 18,27 | 0,46 | 0,13 | 0,00 |
| sonda-carga-vieja | B | 520 | 18,84 | 0,19 | 0,13 | 0,00 |
| gestión (6 réplicas) | A | — | 19,6–20,6 | 0,1–0,3 | 0,2–0,3 | — |
| gestión (6 réplicas) | B | — | 19,9–21,7 | 0,2–0,3 | 0,2 | — |

- **La contención es de CPU.** Los temporales de A no se notan como espera de E/S: viven en la caché de páginas.
- El `LWLock:LockManager` que asomó en el primer humo es del **calentamiento**, justo tras el reinicio y con la caché fría: allí
  hay 4,3–5,0 conexiones de media en LWLock, en A y en B por igual. En las rondas medidas baja a 0,06–0,30.

### 3.4 Deriva y otras sesiones

- **El mismo trabajo cambia mucho a lo largo de la tarde.** Por ejemplo, la A de «produccion» con `estado` viejo dio un p95 de
  210–448 ms a las 14:27–14:32 y de 595–1.204 ms a las 15:00–15:07.
- **Va en parte con las otras sesiones:**
  - Spearman entre el p95 de `estado` por réplica y la CPU media de los otros contenedores: ρ = 0,45 en «produccion» (n 42) y
    0,42 en «peor» (n 18);
  - con la carga del Mac, ρ = 0,04 (n 29).
- **Réplicas con más de 1 núcleo de pico de otros contenedores:**
  - `resultados-serie`: B-1301 (54 % / 106 %);
  - `resultados-serie-estado-viejo`: A-1430 (37 % / 125 %);
  - `resultados-serie-carga-vieja`: A-1500 (112 % / 125 %) y A-1502 (40 % / 111 %);
  - `resultados-serie-gestion`: A-1529 (46 % / 134 %). La comparación de Gestión Diaria lo marca como reserva.
  - Ver las columnas de `analisis-20261017-1600.md`.

## 4. Gestión Diaria «equipo» bajo concurrencia

**Qué llamada y quién la pide:** `crm.gestion_diaria_equipo_fn(p_dia, p_supervisor_id)`, la que sube los temporales
(`fase3/ensayo-3a/RESULTADO-MIGRACIONES-v2.md`).
- El **supervisor** la pide con su propio id, desde la pantalla de Gestión Diaria (`useDiaEquipo`).
- **Gerencia** la pide con `null`, desde el detalle del pulso (`useDetallePulso`, solo con el panel abierto).
- Las dos usan `refetchInterval` y `refetchOnWindowFocus: 'always'`.

**Frecuencia:** no tengo su conteo por rol en los logs de la API del 14/10. Lo único que hay es `pg_stat_statements` de 43 h
(14 y 15/10, `fase1/ensayo-2026-10-14.medias.txt`): **18 llamadas** (media 2.356 ms), frente a 10.279 de estado, 9.549 de
avisos y 4.185 de cola. Es el 0,075 % de las tres del SLA.
- **Proporción usada, decidida antes de medir:** peor caso plausible. Los 4 supervisores y las 3 personas de gerencia la piden
  una vez en cada recarga. Son 7 de 99 llamadas por tormenta (7,1 %), unas 95 veces lo observado.
- **Regla:** la del arnés, sin cambios. Gestión Diaria entra como una consulta más: en el p95 por consulta, en los temporales y
  en las ≥ 200 llamadas (por eso salen 10 rondas por réplica). La concurrencia mínima sigue contando solo las 3 del SLA.

**Resultado** (`resultados-serie-gestion/comparacion-produccion-20261017-1547.md`, ABABAB, 15:29–15:47): **NO PASA (con
reservas)**.

| | A (ANTES) | B (M3) |
|---|---|---|
| Llamadas (avisos / cola / estado / gestion) | 900 / 930 / 930 / 210 | 900 / 930 / 930 / 210 |
| Cortes de 8 s | 0 | 0 |
| **Pico del contenedor** (por réplica, MiB) | **2,188 GiB = 54,71 %** (2.129,3 · 2.116,6 · 2.241,0) | **1,810 GiB = 45,25 %** (1.853,3 · 1.842,3 · 1.815,2) |
| anon pico − reposo (mediana) | 397,8 MiB | 167,8 MiB (−57,8 %) |
| Swap · OOM · eventos max | 0 · 0 · 0 | 0 · 0 · 0 |
| Temporales por ronda · total | 320,9 MiB · 9.627,3 MiB | 234,2 MiB · 7.025,9 MiB (**−27,02 %**) |
| p95 avisos | 4.915 ms | 3.447 ms (−29,86 %) |
| p95 cola | 4.717 ms | 3.281 ms (−30,45 %) |
| **p95 estado** | **897 ms** | **1.002 ms (+11,65 %)** |
| p95 gestion | 6.188 ms | 4.959 ms (−19,86 %) |
| Temporales de gestion por llamada (tormenta) | 14,12 MiB | 19,32 MiB (**+36,76 %**) |
| Gestion sola, gerencia · supervisor | 29,36 · 3,57 MiB | 39,56 · 5,48 MiB (+34,72 % · +53,53 %) |
| CPU estrangulada (suma) | 1.898,6 s | 1.493,8 s |
| Pesadas a la vez (pico mín. / mediana) | 34 / 11,25 | 33 / 18,0 |

- **Criterios:**
  - memoria PASA;
  - temporales PASA (−27,0 % por ronda; ponderado con producción, −55,3 %);
  - p95 NO PASA, solo por `estado`: por réplica A 813 · 967 · 897 y B 1.202 · 1.093 · 573 (IC del agregado [−32,4 %, +42,4 %]).
- **Reserva:** otros contenedores con 134 % de CPU de pico en A-20261017-1529.
- Con Gestión Diaria en la mezcla, la memoria y los temporales totales siguen bajando en M3. Su subida propia de temporales
  (+5,2 MiB por llamada en la tormenta) no llega a compensar la bajada de avisos y cola.

## 5. Qué falta y límites

- **No se intenta un veredicto «estable».** Con este ruido, para detectar un +10 % en el p95 de `estado` haría falta del
  orden de decenas de réplicas por variante, o un criterio sobre la sonda dedicada. Lo decide el PRIMARY o Codex; aquí no se
  cambió nada.
- **La sonda solo se corrió en «produccion».** En «peor», solo está la celda (nueva, vieja) del pool.
- **«Resto» de la sonda:** tras devolver el resultado, el backend hace su contabilidad. Si no hay CPU, esa espera cae en la
  ventana, y por eso la media del «resto» sale ±0,8 ms. Afecta igual a las dos sondas.
- **Lo que la sonda añade:** una conexión más en bucle (≈ 1 backend más en CPU). Sus llamadas cuentan en
  `pg_stat_statements` como `estado`, pero sin temporales. Las corridas con sonda se comparan solo entre sí: firma de trabajo
  propia.
- **Gestión Diaria:** la proporción de llamadas es supuesta (peor caso), no medida por rol. No se corrió en «peor».

## Archivos

**Resultados:**
- `fase2/arnes/resultados-serie-carga-vieja/`: celda (nueva, vieja), «produccion» y «peor»;
- `resultados-serie-sonda/` y `resultados-serie-sonda-carga-vieja/`: sonda dedicada, con `sonda.csv` y `esperas.csv` en cada
  réplica;
- `resultados-serie-gestion/`: con `esperas.csv`;
- cada carpeta trae sus `comparacion-*.md/.json` y sus `serie-dejar-*.log`.

**Logs de cada corrida:** `fase2/arnes/resultados-serie-{carga-vieja-produccion,sonda-produccion,sonda-carga-vieja-produccion,gestion-produccion,carga-vieja-peor}.log`.

**Guiones y análisis** (en `fase2/arnes/estado-2x2/`):
- comprobaciones: `comprobar.py`, `comprobar.sql`, `llamar.sql` y `residuo-cola.sql`, con su salida
  `comprobar-salida-20261017-1450.txt`;
- la tanda: `correr-tanda.sh` (log `tanda-20261017.log`) y la carga del Mac en `host-carga-20261017.txt`;
- análisis: `analizar.py` → `analisis-20261017-1600.md` y `analisis.json`, `celdas-sonda.py` →
  `celdas-sonda-20261017-1600.md`, y `resumen-repeticiones.py` → `resumen-repeticiones-20261017-1600.md`.
