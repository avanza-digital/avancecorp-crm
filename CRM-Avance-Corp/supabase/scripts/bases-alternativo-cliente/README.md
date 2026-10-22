# Ensayo de «La carga de bases también mira el teléfono alternativo de los clientes» (bloque 2.9)

Verifica la migración `20261022170500_crm_bases_alternativo_cliente.sql` (la fecha definitiva se pone al integrar) **en el banco
Docker local (el laboratorio) y sin escribir nada**. Este ensayo **no se corre contra producción**: convierte clientes de verdad por la
puerta del formulario compartido, registra altas por la puerta real, crea bases y carga lotes por la puerta real
(`crm.crear_base`, `crm.cargar_base_lote`), reactiva un contacto de base e importa un lead sin sesión, siempre dentro de una
transacción que termina en `rollback`. La base de partida es el laboratorio **igual a producción con los siete bloques de la fase 2
aplicados** (2.1, 2.6, 2.3, 2.2, 2.4, 2.7 y 2.8 r4): la migración cambia el envoltorio de identidad de la carga de bases B8
(`20261004184501`), que ninguno de ellos toca, y exige el candado de contacto del 2.8 r4.

**Ronda 2** (09/10/2026; auditor de permisos r1 —PASS con cuatro P3— y Codex r1 —sin defectos del predicado—; conciliación en
`fase-2/bloque-2.9/revision/CONCILIACION.md`; el predicado NO cambia): el comentario del cuerpo ya no nombra la pieza del 2.8 (su
reversa se habría negado con el 2.9 aplicado: medido); la migración y la reversa fijan el verificador de 3 argumentos, la cadena del
ámbito y la función del candado, y buscan consumidores del envoltorio, de la regla del ámbito y del núcleo; la migración exige el
candado de contacto del 2.8 r4; casos D2, E1, F3/F3b y F4; mutantes MD, MA1, MA2, M9 y MC5–MC7; derivas y mutantes nuevos; el ensayo
«reversa del 2.8 con el 2.9 aplicado».

## Qué prueba

La regla de Miguel (decisión **D-37**, 09/10/2026; alcance «Solo si es cliente»: solo el alternativo de los leads **convertidos**;
plan AVANCE-BACKEND-0810-F2, fase 2, bloque 2.9): una fila de una base cuyo teléfono es el **teléfono alternativo de un cliente ya
convertido** (activo o retirado) no entra como contacto dormido: sale `ya_existia`. El cliente entra en el MISMO conjunto que
cualquier otra coincidencia del envoltorio, así que:
- si el alternativo es la **única** coincidencia, la fila responde **exactamente lo mismo que con su teléfono principal** (mismo motivo
  —`convertido`, o `retirado` si la ficha del cliente está retirada: D-E1, aceptada— y el mismo id si quien carga lo ve y sigue activo);
- si hay **varias**, **gana la más relevante** (vivo → descartado → convertido → retirado; a igual categoría, la creada más
  recientemente; después el id), así que el motivo o el id pueden cambiar respecto de hoy (R1, E1);
- la **regla del ámbito** mira TODAS: si alguna coincidencia es de otro equipo, la fila solo dice `ya_existia`, sin motivo ni id, aunque
  otra sea un lead propio vivo o en No contactar (F3/F3b: decisión del Director; cuenta en `ya_existian`, no en `no_contactar`).
Hoy (medido en ROJO) la fila con el alternativo de un cliente se carga.

| Caso | Qué exige |
|---|---|
| A | **El alternativo de un cliente** ⇒ la fila responde EXACTAMENTE lo mismo que con su teléfono principal (Ap, que ya se detecta hoy), el lote cuenta 1 `ya_existia` y 0 cargadas, no nace ningún lead con ese teléfono, la base no gana pertenencias, el cliente queda intacto y la respuesta no lleva su nombre, sus teléfonos ni su DNI: **A1** con persona y activo (`convertido` + su id) · **A2** con persona y **retirado** (`retirado`, sin id) · **A3** sin persona y activo · **A4** sin persona y retirado · **A5** la carga Gerencia (ve a todos). |
| F | **La misma regla del ámbito:** **F1** SUP1 carga el alternativo de un cliente de VEND3 (equipo de SUP2) ⇒ solo `ya_existia` (como su principal, F1p) · **F2** Gerencia, otro cliente de VEND3 ⇒ motivo e id · **F3** (ronda 2) el teléfono es el principal de un lead PROPIO vivo y el alternativo de un cliente de otro equipo ⇒ solo `ya_existia` (hoy `con_dueno` con el id del propio) · **F3b** igual con el lead propio en No contactar ⇒ solo `ya_existia` y cuenta en `ya_existian` (hoy `no_contactar`), comprobados el lote, el acumulado de la base en la respuesta y la fila de `crm.bases_carga` (base nueva) · **F4p/F4** el cliente RETIRADO de otro equipo ⇒ solo `ya_existia`. |
| N | **No cambia (D-37):** el alternativo de un lead que NO es cliente ⇒ `cargada` y nace su contacto dormido, como hoy: **N1** vivo · **N2** descartado (sembrado) · **N3** retirado · **N4** un teléfono libre · **N5** el alternativo **internacional de 9 dígitos** de un cliente (`+924090315`) no es el móvil peruano `+51 924 090 315` de la fila (comparación literal de formas canónicas, como el 2.8). |
| R | **El orden de relevancia y el verificador:** **R1** el principal de una ficha **retirada** (no cliente) y el alternativo de un cliente **activo** ⇒ manda el cliente: `convertido` con su id (hoy, `retirado`) · **R2** el principal de un lead **vivo** y el alternativo de un cliente ⇒ el verificador dice «tomado» y manda: `con_dueno` con el id del lead vivo (como hoy). |
| E | **E1** (ronda 2) EMPATE de categoría con fechas distintas: el principal de un cliente A (más antiguo, id menor) y el alternativo de otro cliente B (más reciente, id mayor) ⇒ gana B (hoy, A). Sembrado declarado: ids fijos y `creado_en` (dentro del ensayo todas las altas comparten `statement_timestamp()`). |
| Z | **La misma normalización:** el alternativo del cliente escrito **Z1** con espacios · **Z2** con `+51` y guiones · **Z3** con `51` delante · **Z4** en nueve dígitos ⇒ `ya_existia`. |
| D | **D1** el alternativo de un cliente con un DNI libre ⇒ `ya_existia` · **D2** (ronda 2) un teléfono libre con el DNI de un cliente **retirado sin persona** (el verificador dice «libre» antes) ⇒ el resultado de B8, que no cambia: `ya_existia`, `retirado`, sin id. |
| L | **L1** un lote mixto (la tanda del INSERT): libre · alternativo de un cliente · alternativo de un no cliente ⇒ `cargada` · `ya_existia` (convertido, su id) · `cargada`; conteos 2 y 1; nacen exactamente los dos dormidos. |
| S | **S1** el importador sin sesión (`crm.importar_lead_fn`) con el alternativo de un cliente ⇒ `importado`, como hoy (H-3 del 2.8, por diseño). |
| C | Catálogo: **C1** el envoltorio sigue INVOKER de postgres, STABLE, `search_path` vacío, EXECUTE solo postgres · **C2** las doce funciones que fija la migración (sus dos llamadores, la puerta, los dos verificadores, la normalización, la cadena del ámbito —`base_gestion_lead_visible`, `vendedor_ids_visibles`, `es_lector_global`, `rol_crm`—, `bases_carga_lead_ref` y `bloquear_contactos_lead`), intactas · **C3** los consumidores: del envoltorio solo el núcleo y el ámbito; del ámbito solo el núcleo; del núcleo solo la puerta · **C4** el CHECK `leads_telefono_alternativo_formato` intacto · **C5** el candado de contacto del 2.8 r4 (el disparador lo toma con el alternativo en la UPDATE y en el INSERT; sus dos disparadores de tabla habilitados, el de la edición con el alternativo en su lista). |
| H | **Medida (hallazgo, no caso):** **H1** un contacto de base cargado cuando su teléfono era libre, que después resulta ser el alternativo de un cliente, se **reactiva** por `crm.reactivar_lead_base_v2` y vuelve activo con el teléfono del cliente (otra puerta: D-55, bloque 2.11). |

**Decisiones:** **D-E1** (aceptada por el Director): el alternativo de un cliente **retirado** responde `retirado`, igual que su
principal. **D-E2**: no se reutiliza la pieza del 2.8 (devuelve un veredicto de alta, no los leads que necesitan el ámbito y el id). **F3**
(decisión del Director): con alguna coincidencia de otro equipo manda la respuesta opaca. **D-E3** (a la integración): el caso B1 del
oráculo del 2.8 afirma la carga vieja; al integrar el grupo C se cambia su esperado y el oráculo completo corre sobre el estado FINAL.

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, postflight y comentario incluidos) dentro de la transacción. Los
clientes con persona nacen por la **conversión real** del formulario compartido (como en los oráculos del 2.7 y del 2.8); los sin
persona, por el alta real (con su alternativo) y una conversión sembrada; el descarte de N2, el No contactar de F3b y las fechas de E1
se siembran y se declaran. Los actores del banco (`PASO08 …`) son **obligatorios** con su rol y su equipo exactos, y cada caso exige su
precondición (p. ej. que hoy el verificador diga «libre», «tomado» o «no_contactar»: si no, el caso no mediría lo que dice y el ensayo
aborta). La identidad se fija en las DOS formas de los claims; no se usa `set role` (llamar bajo `set role` a una función sin EXECUTE
tumba el Postgres de esta imagen), así que la RLS no se ensaya aquí; la puerta de la carga es DEFINER y resuelve rol y ámbito con
`auth.uid()`.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito);
`EJECUTAR_SQL_ADMIN`, el mismo como `supabase_admin` (solo lo usan las derivas «cambio de dueño»). Los SQL generados van a una carpeta
de trabajo (`$SALIDAS`), no al repo.

```bash
# 1. ROJO: el oráculo SIN la migración (la medición del defecto).
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"; $EJECUTAR_SQL "$SALIDAS/rojo.sql"
#    → ENSAYO ROJO — 18 fallo(s) de 38: «la fila ENTRÓ como contacto dormido (cargada) → nació un lead con el teléfono …, que es de un
#      cliente ya convertido» (A1–A5, F1, F2, F4, Z1–Z4, D1, L1) y los cambios de selección o de ámbito (R1, E1, F3, F3b); los 20
#      controles, negativos y de catálogo ya pasan.
# 2. VERDE: la migración real + el oráculo.
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs > "$SALIDAS/verde.sql"; $EJECUTAR_SQL "$SALIDAS/verde.sql"
#    → ENSAYO VERDE — 0 fallos (38 comprobaciones)
# 3. Mutantes (catálogo en mutantes.py; cada uno debe morir nombrando sus casos):
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/bases-alternativo-cliente/mutantes.sh
# 4. Derivas de la migración y de la reversa (y sus mutantes):
EJECUTAR_SQL="…" EJECUTAR_SQL_ADMIN="… --usuario supabase_admin" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/bases-alternativo-cliente/derivas.sh
# 5. Reversa: aplicar → revertir → el envoltorio de B8 (cuerpo, definición, comentario) y la foto idéntica.
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"; $EJECUTAR_SQL "$SALIDAS/reversa.sql"
# 6. La reversa del 2.8 con el 2.9 aplicado (compatibilidad mecánica, no concurrencia): tiene que ENTRAR.
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --reversa-28 > "$SALIDAS/r28.sql"; $EJECUTAR_SQL "$SALIDAS/r28.sql"
# 7. Trinquetes: los private.assert_*() (los 36) y el censo, sin y con la migración (tienen que ser idénticos).
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/t0.sql"
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --trinquetes > "$SALIDAS/t1.sql"
# 8. Los oráculos del 2.4 (modo 2.7 «con», sin el fixture B7), del 2.7 y del 2.8, sin y con esta migración:
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --oraculo 24|27|28 [--sin-migracion] > "$SALIDAS/oNN-….sql"
#    → 2.4 (67) y 2.7 (54) VERDE sin y con, mismas respuestas; 2.8 VERDE sin (124) y con 1 fallo: su B1 (D-E3).
# 9. Rendimiento (medida): volumen sintético, el envoltorio de B8 y el nuevo cronometrados, su plan y un lote real de 100 filas.
node supabase/scripts/bases-alternativo-cliente/armar-ensayo.mjs --rendimiento > "$SALIDAS/rendimiento.sql"; $EJECUTAR_SQL "$SALIDAS/rendimiento.sql"
```

El ensayo se arma para una base que **todavía no tiene** esta migración y **sí** tiene el 2.8 r4: su preflight exige el envoltorio de
B8 exacto (`cf6489ee…`/`563274f8…`, comentario `1e1052db…`) y el candado de contacto del 2.8 r4. En una base que ya la tiene, el oráculo
se corre solo (`--sin-migracion`) y entonces tiene que salir VERDE.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--oraculo 24\|27\|28 [--sin-migracion] [--mutante <archivo>]`, `--reversa`, `--reversa-deriva <archivo> [--espera "<texto>"]`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` de la deriva se sustituye por la migración: deriva «ya aplicada»), `--trinquetes [--sin-migracion]`, `--rendimiento`, `--reversa-28`; modificadores `--migracion`, `--pruebas`, `--reversa-archivo`. Se niega si queda un `commit` suelto. |
| `pruebas.sql` | El oráculo (casos de arriba; 38 comprobaciones y la medida H1). |
| `mutantes.py` / `mutantes.sh` | 21 mutantes: los del encargo —**M1** sin la comparación nueva, **M2** cualquier lead, **M3** al revés (el principal del cliente en vez de su alternativo), **M3b** al revés (el filtro), **M4a** sin normalizar la fila, **M4b** normalizando el alternativo guardado—; **M5** la regla del ámbito ciega al alternativo, **M6** solo clientes activos, **M7** otro orden de relevancia, **M8** categoría propia del alternativo; ronda 2: **MD** sin la coincidencia por DNI, **MA1** el ámbito con `bool_and`, **MA2** el ámbito que solo mira al ganador, **M9** el desempate por fecha al revés; **MC1–MC7** catálogo (DEFINER, GRANT, `search_path`, consumidores del envoltorio, del ámbito y del núcleo, el disparador sin el candado del alternativo). Cada uno solo cuenta como muerto si el ensayo sale ROJO **y nombra sus fallos**. M1 y M3 son equivalentes en lo que buscan: los mutantes no son defensas independientes una a una. `DIR_ENSAYO` obligatoria. |
| `derivas.sh` | 35 derivas instaladas ANTES de la migración (el envoltorio: cuerpo, `SET`, DEFINER, GRANT, dueño —como superusuario—, comentario, ya aplicada; las doce funciones fijadas; consumidores nuevos —PL/pgSQL, en MAYÚSCULAS, una vista, una función `BEGIN ATOMIC`, de la regla del ámbito, del núcleo, un `cron.job`—; el candado del 2.8 r4 —sin el alternativo en la UPDATE o en el INSERT, un disparador de tabla deshabilitado o sin el alternativo—; el CHECK quitado o cambiado; un trinquete cambiado o de más), el control y cuatro **mutantes del preflight** (MP1 sin el inventario de trinquetes, MP3 sin la búsqueda de consumidores y MP4 sin la comprobación del candado: mueren; MP2 sin la búsqueda del preflight: aborta en el postflight). Al final, las **derivas de la reversa** (control y 10 rechazos: `SET`, otro cuerpo, GRANT, dueño, comentario, el núcleo cambiado y, ronda 2, un consumidor NUEVO del envoltorio, del ámbito, del núcleo y un `cron.job`) y tres **mutantes de la reversa** (RM1 aborta en el postflight; RM2 deja colar el GRANT; RM3, sin la búsqueda de consumidores, deja al consumidor sin el alternativo: mueren). `DIR_ENSAYO` y `EJECUTAR_SQL_ADMIN` obligatorias. |
| `reversa.sql` | GENERADA desde la migración (su ancla, su bloque y su frase, byte a byte; sus huellas y sus dependencias; generador en `fase-2/bloque-2.9/salidas/ronda2/trabajo/generadores/`). **Falla cerrada:** exige el envoltorio EXACTAMENTE como lo deja la migración, las doce funciones intactas y que nadie más consuma el envoltorio, el ámbito ni el núcleo (revertir le quitaría el alternativo a ese consumidor en silencio); repone el cuerpo y el comentario de B8; su postflight exige las huellas de B8. No deshace datos (la regla no escribe). |
| `rendimiento.sql` | La medida de rendimiento (lo arma `--rendimiento`): 50 000 leads sintéticos (5 000 convertidos), sin ANALYZE. Su función de cronometraje construye el nombre del envoltorio en tiempo de ejecución: la búsqueda de consumidores no la ve (límite 3). |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La RLS no se ensaya** (todo corre como `postgres`, sin `set role`); la puerta de la carga es DEFINER y resuelve el rol y el
   ámbito en el servidor. La parte HTTP es del banco (lista de pruebas de integración en `MIGRACIONES.md`).
2. **Concurrencia.** El núcleo toma los candados de contacto de sus filas antes de juzgar y, desde el 2.8 r4, el disparador toma la
   MISMA clave para el alternativo (C5 y el preflight lo exigen): una carga de X y quien pone X como alternativo de un cliente (o convierte
   un lead que lo tiene) no se juzgan a la vez sobre fotos viejas; el resultado es uno de los dos órdenes. El orden «carga primero» es
   legítimo (X aún no era de un cliente) y lo cubren después D-55 y D-62. No ensayado aquí con dos sesiones: la carrera con COMMIT en los
   dos órdenes es de la branch. La «reversa del 2.8 con el 2.9» prueba compatibilidad mecánica, no concurrencia (sin el 2.8 el
   alternativo deja de tomar candado).
3. **La búsqueda de consumidores** (migración, reversa, C3) ve referencias LITERALES en los cuerpos de función (sin distinguir
   mayúsculas), dependencias registradas en `pg_depend` y los comandos de `cron.job` que ve quien migra; es conservadora (un comentario o
   una cadena con el nombre también bloquea) y **no ve el SQL dinámico** (un nombre armado en tiempo de ejecución, como el de
   `rendimiento.sql`): no prueba ausencia. Inventario revisado en el laboratorio (09/10): envoltorio ← núcleo y ámbito; ámbito ← núcleo;
   núcleo ← puerta; `pg_depend` vacío; ningún `cron.job`. En la branch hay que comprobar que `cron.job` se ve ÍNTEGRO (con RLS podría
   devolver menos filas sin error).
4. **Los contactos ya cargados** no se tocan (fuera del plan) y la **reactivación** de uno cuyo teléfono es el alternativo de un
   cliente entra (medida H1: D-55, bloque 2.11); las demás puertas que devuelven un lead a la cartera: D-62 (bloque 2.16).
5. **Rendimiento:** la comparación nueva recorre el índice parcial de los convertidos (`idx_leads_convertido_en`) y filtra; crece con
   el número de convertidos (medido: +~2 ms por llamada con 5 000; producción tenía 213 el 08/10). Medido como `postgres`, sin
   estadísticas al día: no acredita el límite HTTP de 8 s (prueba de integración con datos representativos). Un índice por
   `telefono_alternativo` de los convertidos lo evitaría (DDL sobre `crm.leads`: fuera de este bloque).
6. **El oráculo B8 de la carga** (`supabase/scripts/base-gestion/b8-cargar.sql`) no corre en este laboratorio: exige un banco de la
   CLI de Supabase con los actores de `seed:demo` (su guarda inicial).
7. **La medida de rendimiento** inserta y deshace 50 000 filas: deja tuplas muertas en `crm.leads` hasta el autovacuum del laboratorio.
8. **Las huellas y los trinquetes** prueban igualdad de lo observado (también de los errores que ya había: 7 trinquetes caen igual sin y
   con); la `FOTO` de las derivas cubre el envoltorio, sus dos llamadores, la puerta y el disparador con sus disparadores de tabla.
