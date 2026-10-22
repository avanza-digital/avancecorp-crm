# Ensayo de «el analista dado de baja o suspendido sigue con su marca, y la fila «Otros» hace que el desglose de reuniones sume el total»

Verifica la migración `20261022170900_crm_reuniones_desglose_con_bajas.sql` (bloque 2.12 del plan del backend; decisiones D-43,
D-46, D-47, D-48, D-53 y D-54 de Miguel, 09/10/2026) **en el banco Docker local (el laboratorio) y sin escribir nada**. Este ensayo
**no se corre contra producción**: siembra citas y tareas con los actores reales del banco, da de baja a unos y suspende a otro
dentro de la transacción y pide las dos métricas por sus puertas (`crm.metricas_reuniones_fn` y `crm.metricas_agenda_fn`) como
cada rol, siempre dentro de una transacción que termina en `rollback`. La migración va **encima del bloque 2.2** (su preflight
exige la implementación del 2.2 y su registro analítico).

**Estado (09/10/2026):** verificada por el escritor y por el Director en el laboratorio (rondas 2 y 3); el auditor de permisos (r1)
pidió cambios, atendidos en la ronda 3; Codex (r1) pidió cambios (sin defectos de permisos ni de cálculo), atendidos en la ronda 4.
Las revisiones del bloque están agotadas: lo cierra la verificación del Director de la ronda 4. No aplicada en ninguna base real.

## ⚠️ Orden de despliegue: PRIMERO LA APP, DESPUÉS LA MIGRACIÓN (con una ventana de convivencia)

La app publicada valida la agenda con un objeto ESTRICTO (`app/src/lib/metricas-agenda.ts`, `v.strictObject`): una clave nueva
(`de_baja`, `suspendido`) tumba el panel «Agenda del equipo» entero (medido: con la respuesta nueva, la app anterior lanza «Las
métricas de agenda no tienen el formato esperado»). La app nueva (`app/src/data/crm-api.ts`) acepta las marcas como opcionales y
funciona con la respuesta de antes y con la nueva (probado en vitest con las dos). Decisión del Director (09/10/2026): expandir →
cambiar; nada de puerta nueva.

- **Ventana de convivencia:** la app NO se recarga sola al publicar (`app/src/components/app/version-publicada.tsx` solo avisa y
  consulta cada 60 s): una pestaña abierta conserva el código viejo y, tras la migración, su agenda caería en cuanto hubiera un
  marcado con actividad. Por eso: publicar la app, avisar «recargar», y aplicar la migración después, p. ej. a primera hora del día
  siguiente.
- **Revertir la app exige revertir ANTES la migración** (una app anterior al 2.12 con la migración aplicada tumba la agenda).
  Revertir la migración con la app nueva publicada es seguro (las marcas son opcionales).
- Reuniones no tiene ese problema (`v.object`): una app anterior ignora las marcas y pinta «Otros» como una fila más.

## Quién consume estas puertas hoy (D-53)

- **`crm.metricas_reuniones_fn`**: solo el Resumen de Gerencia (`app/src/screens/hoy/resumen-gerencia.tsx:231-232`), que lee
  `resumen` y `conversion`. El panel que pinta el desglose por responsable (`ReunionesGerenciaPanel`, de
  `HoyGerencia seccion="reuniones"`) **no se monta en ninguna ruta** (`screens/gerencia.tsx:15-18`, `lib/vistas.ts:98`,
  `lib/roles.ts:89,101`): Gerencia y Supervisión ven «Citas del equipo» (`TableroCitas`), que lee `crm.citas_gerencia_consulta_fn`.
  Por eso **el desglose con marcas y «Otros» queda como coherencia de la API** (el desglose suma el total) y no se ve hoy en
  ninguna pantalla. La marca llega a «Citas del equipo» en un bloque aparte, el **2.14** (D-53; allí se mide primero si hace falta
  «Otros»).
- **`crm.metricas_agenda_fn`**: el panel «Agenda del equipo» del puesto de mando del supervisor (`screens/hoy.tsx:16-17` →
  `supervisor-mando.tsx:977`). Ahí sí se ven «de baja» y «suspendido».

## Qué prueba

Las reglas:

- **D-43** — en el desglose por responsable de `crm.metricas_reuniones_fn`, quien **fue** analista o supervisor (su ficha) y **hoy
  está dado de baja** (ficha de `crm.equipo` inactiva: la regla de producción `private.analista_dado_de_baja`) sigue, con **sus**
  citas y `"de_baja": true`.
- **D-46** — el **suspendido en el Portal** (ficha ACTIVA, perfil `activo is not true`: la definición del propio CRM en
  `crm.fijar_membresia_activa_fn` y `crm.usuarios_administrables_fn`) también, con `"suspendido": true`. Si la ficha está inactiva,
  gana «de baja» (confirmado por el Director).
- **D-47** — lo que el desglose deja fuera (citas sin responsable, de Gerencia o Coordinación —también de un ex Gerencia de baja—, de
  un perfil sin rol efectivo) va a una fila **«Otros»** al final, con las mismas columnas, `supervisor_nombre` «—» y
  `"otros": true`: el desglose suma SIEMPRE el total **en los diez contadores** (pactadas, debieron_ocurrir, realizadas, no_show,
  canceladas, reprogramadas, pendientes_cierre, programadas_futuras, canceladas_sistema_vencidas, reprogramadas_vencidas) y **NO
  en el divisor de realización**: cada fila descuenta las canceladas por otro asesor y el resumen no (diferencia deliberada y
  previa de la implementación). En D2: divisor del resumen 10 − 1 = 9; filas P + B + «Otros» = 2 + 1 + 5 = 8; la diferencia es
  la cancelada ajena de X (Codex r1). El caso R5 fija las dos cosas.
- **D-48** — la agenda conserva al de baja, con su marca, **solo si tiene actividad registrada en el período o tareas pendientes
  actuales**, con la misma definición que la app (`app/src/lib/agenda-equipo-vista.ts:138-150`: toques, citas realizadas,
  completadas, no asistió, canceladas, tareas creadas, citas agendadas y reprogramaciones —del período— o pendientes —una foto de
  hoy, no del período—; el rezago —vencidas, leads sin acción— no cuenta). La pantalla lo explica así (Codex r1, P3-3).
- **D-54** — y también al **suspendido** con actividad, con «suspendido»: lo ven el **supervisor (solo su subárbol) y Directorio**,
  como Gerencia. Es un estado del Portal que hasta ahora solo veían Gerencia y Superadmin; Miguel decidió que lo vean, para saber
  por qué se le quedan tareas paradas y repartirlas.
- **Nombre de reserva** (auditor r1, P3-5) — un marcado con el `nombre` vacío o en blanco sale como «(sin nombre)»: la agenda de la
  app exige texto no vacío y `public.perfiles.nombre_completo` no lo impide.

**A QUIÉN ve cada rol no cambia** (quién consulta y su ámbito los decide la implementación; en la agenda,
`private.vendedor_ids_visibles`, que la migración fija con su huella); **cambia QUÉ ve de su ámbito**: el supervisor y Directorio
pasan a ver a los de baja y suspendidos con actividad, con su marca. Tampoco cambian los totales ni las otras tres métricas que
usan el filtro común. Sin bajas, suspendidos ni «Otros», la respuesta es **idéntica byte a byte** a la de antes.

Escenario (`antes.sql`; D1 = hoy − 40 días, D2 = hoy − 39 días y D3 = hoy − 38 días, ventanas de reuniones enteramente del
ensayo). **Todos los actores son obligatorios, también el lector global (Directorio)**, que D-54 nombra: si falta, el ensayo aborta
(«falta un lector global (Directorio)»); no hay modo parcial que se presente como completo (Codex r1, P3-2).

| Día | Quién | Citas | Qué se espera |
|---|---|---|---|
| D1 | A, analista **→ de baja** | 3 realizadas, 1 no asistió, 1 cancelada por él, 1 reprogramada | en el desglose, «de baja», con las cifras de la implementación (6 pactadas, divisor 5, 60,0 %) |
| D1 | S, supervisor con cartera **→ de baja** | 2 realizadas, 1 cancelada por el sistema | en el desglose, «de baja» (3 pactadas, divisor 2) |
| D1 | B, analista activo | 1 realizada, 1 no asistió | tal cual, sin marca |
| D2 | P, **suspendido en el Portal** | 1 realizada, 1 no asistió | en el desglose, «suspendido» (2 pactadas, divisor 2, 50,0 %) |
| D2 | B | 1 realizada | tal cual |
| D2 | X, otra Gerencia **→ de baja** | 1 realizada, 1 cancelada por la Gerencia G (ajena) | en «Otros» |
| D2 | C, Coordinación activa | 1 no asistió | en «Otros» |
| D2 | N, sin responsable (`vendedor_id` nulo) | 1 realizada, 1 cancelada por el sistema | en «Otros» |
| D2 | Z, un perfil que **nunca tuvo ficha** (sembrado saltándose la FK) | 1 realizada | en «Otros» |
| D2 | M, analista **desalineado** (ficha y perfil activos; su perfil del Portal pasa a Directorio: sin rol efectivo) | 1 realizada | en «Otros» |
| D3 | C, Coordinación | 1 cancelada por el sistema | «Otros» es la ÚNICA fila; su divisor es 0 (porcentaje nulo) |

«Otros» de D2 = 7 pactadas, 7 que debieron ocurrir, 4 realizadas, 1 no asistió, 1 cancelada (por otro asesor), 1 cancelada por el
sistema; divisor 5 (= 7 − 1 − 1), 80,0 %. Agenda (cuenta por `creado_en`/`actualizado_en`, que en la siembra es AHORA, y la foto de
pendientes): A, S y P tienen actividad hoy; **Q1** (de baja del banco) solo una tarea PENDIENTE antigua → aparece «de baja»; **Q2**
(de baja del banco) no tiene nada y **R** (suspendido del banco) solo un lead sin próxima acción (rezago) → siguen fuera; M
(desalineado) → fuera. A y P pasan al equipo de SUPV, el supervisor que consulta la agenda.

Estados: **«sin»** = A, S, X y Q1 con la ficha activa y P con el perfil activo (nadie de baja ni suspendido CON actividad: Q2 y R lo
están, sin actividad); **«con»** = A, S, X y Q1 de baja y P suspendido.

| Caso | Qué exige |
|---|---|
| R1 | D1 con: A y S «de baja» con sus cifras (su elemento, quitada la marca, es el de la implementación); B tal cual; sin «Otros»; orden A, S, B. |
| R2 | D2 con: P «suspendido» con sus cifras; B tal cual; X, C, N, Z y M fuera por nombre y dentro de «Otros» (cifras a mano, 19 claves); orden P, B, «Otros». |
| R3 | Seis ventanas (D1, D2, D3, hoy, el mes, el último año): la respuesta es EXACTAMENTE la esperada, calculada por el oráculo desde la implementación con su propia clasificación (`pg_temp.clase`). |
| R4 | Seis ventanas: quitando los marcados y «Otros», byte a byte la de antes. |
| R5 | Seis ventanas: el desglose suma el total en los diez contadores que comparten fila y resumen; y el divisor de realización NO: la suma de los divisores de las filas + sus canceladas por otro asesor = el divisor del resumen. |
| R6 | Las marcas de cada ventana son exactamente las del escenario. |
| R7 | El contrato de la pantalla (`metricas-reuniones.ts` + las marcas de `crm-api.ts`), con y sin. |
| R8 | Lo que ve cada rol en reuniones (Gerencia, lector global, Coordinación, supervisor, analista, el propio A, el propio P, anónimo), en D1 y D2: Gerencia y lector, lo de antes + lo nuevo; los demás, el mismo 42501. |
| R9 | D3: «Otros» es la ÚNICA fila (1 pactada, 1 cancelada por el sistema), con divisor 0 y porcentaje nulo, igual que el resumen. |
| G1–G3 | Agenda de Gerencia, lector, supervisor y analista en cuatro ventanas (hoy, semana, mes, D1–D2): la esperada desde su implementación; quitando los marcados, la de antes; las marcas, las del escenario (Gerencia y lector: A, S, P, Q1; el supervisor: A y P; el analista: ninguna). |
| G4 | Agenda: Q2 (de baja sin nada), R (suspendido con solo rezago) y M (desalineado) siguen fuera aunque la implementación los trae. |
| G5 | Agenda: «de baja» ⇒ `activo: false`; «suspendido» y sin marca ⇒ `activo: true`; ningún nombre vacío; ninguna clave fuera del contrato estricto de la app. |
| G6 | Agenda: Coordinación, el propio A, el propio P y anónimo reciben lo de antes (42501). |
| O1 | Las otras tres métricas del filtro común (conversiones, conversiones del equipo, conversión mensual): byte a byte. |
| S1–S3 | «Sin»: reuniones, la esperada (sin «Otros», byte a byte; con «Otros», la de antes + «Otros»); agenda, byte a byte en cada rol y ventana; visibilidad, byte a byte. |
| P1 | P con el perfil `activo` NULO sigue «suspendido» (la definición del CRM es `is not true`). |
| P2 | Un marcado con el nombre vacío (Q1) o en blanco (P) sale como «(sin nombre)», en la agenda y en reuniones, y la agenda pasa el contrato de la app. |
| P3 | Ficha INACTIVA y perfil inactivo (A) o NULO (S), con actividad: en reuniones y en la agenda, SOLO «de baja» (la ficha manda). Sin este caso, el mutante que da prioridad a la suspensión sobrevivía (medido en la ronda 4). |
| P4 | Actividad por UNA sola clave: R (suspendido) con solo un toque y Q2 (de baja) con solo una reprogramación aparecen marcados. |
| K1–K8 | Catálogo y evidencia: fichas de las dos puertas y de las dos piezas; las nueve claves de actividad en la puerta de la agenda; lo que no se toca, con su huella (también `private.vendedor_ids_visibles`); registro analítico y censos; FK de la ficha; la regla de baja de producción; la definición de suspendido. |

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, piezas, puertas re-emitidas, postflight y comentarios) dentro de
la transacción. «Lo de antes» se mide en el montaje con las puertas vigentes y «lo de después» en el oráculo, en la misma
transacción: `now()` es fijo, también `generado_en`, así la comparación es byte a byte. El oráculo no se fía de la migración:
clasifica él mismo cada elemento y construye la respuesta esperada.

Las citas se siembran **ya en su estado final** con los triggers apagados (`set local session_replication_role = replica`), como el
ensayo del bloque 2.2: se mide cómo las métricas **leen** las tablas, no el camino de escritura. La baja se siembra como el **estado**
que deja la baja real (`crm.equipo.activo = false`) y la suspensión como el del Portal (`public.perfiles.activo = false`). Los actores
salen del banco y son **obligatorios**: si faltan, el ensayo aborta (`ENSAYO ABORTADO`). La identidad se fija en las DOS formas de los
claims; no se usa `set role`: los permisos se leen del catálogo.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito).

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
# 3. Mutantes (después de la migración) y 4. derivas (antes): cada uno con su veredicto de máquina.
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/reuniones-desglose-con-bajas/mutantes.sh
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/reuniones-desglose-con-bajas/derivas.sh
# 5. La reversa, y la reversa con un SET añadido después de migrar (tiene que ABORTAR sin dejar rastro).
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
# 6. Trinquetes: la foto de todos los private.assert_*() (mutantes incluidos) y del censo, con y sin la migración.
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes.sql"
node supabase/scripts/reuniones-desglose-con-bajas/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/trinquetes-sin.sql"
# 7. El oráculo del bloque 2.2 ENCIMA de esta migración (su armador acepta otra migración con --migracion).
node supabase/scripts/metricas-reuniones-realizacion/armar-ensayo.mjs \
  --migracion supabase/migrations/20261022170900_crm_reuniones_desglose_con_bajas.sql > "$SALIDAS/oraculo22-encima.sql"
```

Resultados medidos: ver la sección del bloque en `supabase/migrations/MIGRACIONES.md` (`20261022170900`).

El ensayo se arma para una base que **todavía no tiene** esta migración y **sí** tiene la del 2.2: el preflight exige las dos
puertas con sus huellas (`ca480bc7…` / `de328143…` y `104d863b…` / `1a5f2938…`) y la implementación del 2.2 (`ca6fe61e…` /
`ce852e37…`).

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega montaje + migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--reversa-con-deriva <archivo> --espera "<texto>"`, `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` se sustituye por la migración), `--trinquetes [--sin-migracion]`; modificadores `--migracion <ruta>` y `--reversa-archivo <ruta>`. Se niega si queda un `commit` suelto. |
| `antes.sql` | El montaje, DELANTE de la migración: auxiliares, actores obligatorios, A y P al equipo de SUPV, M desalineado, neutralización, la siembra y las mediciones de ANTES («sin» y «con»). |
| `pruebas.sql` | El oráculo (casos de arriba). Primero «con», después «sin», y al final P con el perfil nulo, los nombres vacíos, la baja con el perfil inactivo o nulo, la actividad de una sola clave y el catálogo. |
| `mutantes.sh` | Un mutante por regla: cada puerta vuelve al filtro común; sin cada marca; el suspendido como «de baja»; sin la rama del suspendido; `is false` en vez de `is not true`; la suspensión antes que la baja; sin mirar el rol; sin la condición de actividad; la actividad solo con toques o sin pendientes; la actividad también para los activos; `de_baja: false` a los activos; una clave nueva; los de baja al final; sin el nombre de reserva; sin «Otros», «Otros» siempre, al principio, sin su marca, sin porcentaje, con el divisor mal; reuniones con condición de actividad; Coordinación consultando cada puerta con las dos cerraduras abiertas; seis de catálogo; y tres equivalentes. |
| `derivas.sh` | Derivas ANTES de la migración (las dos puertas: cuerpo, `SET`, INVOKER, ACL y comentario; piezas ajenas; filtro común, `rol_crm`, `es_lector_global`, las dos implementaciones y `private.vendedor_ids_visibles` alterados; implementación anterior al 2.2; registro analítico; `crm.equipo` con `activo` nulable o sin la FK a `public.perfiles`; ya aplicada; un gate sembrado para el postflight), los mutantes de la migración que las dejan pasar, y la reversa con el gate sembrado y su mutante. |
| `reversa.sql` | Repone los cuerpos anteriores de las dos puertas (byte a byte), les quita el comentario y borra las dos piezas. Falla cerrada. |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **La siembra apaga los triggers.** Las citas nacen en su estado final y la baja o la suspensión son el estado que dejan, no las
   RPC: nada de aquí prueba el camino de escritura de la baja (`crm.fijar_membresia_activa_fn`) ni del Portal, que no cambian.
2. **Z es un caso imposible en producción** (la FK lo impide) y **M es raro** (una pareja ficha/perfil desalineada): se siembran para
   fijar que van a «Otros».
3. **La lista de claves de actividad** de la puerta de la agenda es la de la app hoy; si la app cambia `tieneActividad`, hay que
   cambiar las dos (el caso K3 fija la lista de la puerta; la app la fija `agenda-equipo-vista.ts`).
4. **Las otras tres métricas** se comparan en una ventana con datos del banco; para ellas el ensayo prueba que no cambian, no cómo
   tratarían a una baja (lo declaran en su agregado de «fuera del roster»).
5. **El oráculo del 2.2 encima** cae en su caso 6b por diseño: fija la huella de `crm.metricas_reuniones_fn` (`ca480bc7…`), que
   esta migración re-emite; es evidencia histórica del 2.2 (decisión del Director: no se toca).
6. **Agenda agrupada** (más de un supervisor en la respuesta, `agenda-equipo-vista.ts:206-224`): el marcado cae en «Sin equipo
   asignado», porque el grupo sale del roster de la app (`crm.equipo_visible_fn`), que no incluye a quien no tiene rol efectivo; un
   supervisor de baja con actividad forma su propio grupo. Es de presentación; arreglarlo exige que la respuesta traiga el
   `supervisor_id` (otro cambio; puede ir al 2.14 si Miguel lo pide).
7. **Excepción delimitada** a la invariante «un analista dado de baja no reaparece con nombre propio» ([[crm-p04-revocado-vs-ajeno]],
   `test-rls.mjs:13150-13162`): el 2.12 lo hace a propósito SOLO en reuniones y agenda; `crm.conversion_mensual_fn` y las demás
   métricas siguen sin él.
8. **El ensayo no llama como `authenticated` por la API**: eso lo cubrirán las pruebas de `test-rls.mjs` en la integración (abajo).

## Pruebas para la integración (grupo C) — `test-rls.mjs` (lista del auditor de permisos r1 y de Codex r1; no se tocan aquí)

Hoy `test-rls.mjs` solo cubre `7881-7915` (reuniones: Gerencia y Directorio con forma; vend1, sup1 y coordinador denegados) y
`9893-9900` (agenda: Coordinación denegado).

- **Fixture:** `vendInactive` (de baja) con cita y actividad; un suspendido (patrón P04, `test-rls.mjs:4354-4369`, sobre vend2,
  restaurándolo); una baja sin actividad; una cita de Gerencia o con `vendedor_id` nulo.
- **Reuniones.** 1) Gerencia: vendInactive `de_baja:true`, el suspendido `suspendido:true`, una sola fila `otros:true` (la última,
  `responsable_id:null`), la suma del desglose = resumen en los diez contadores, ninguna otra fila con marca. 2) Directorio = Gerencia.
  3) 42501: vend1, sup1, sup2, coordinador, vendInactive y el suspendido (con su token vigente); anónimo 401/42501. 4) Las piezas,
  inalcanzables por `schema('private').rpc` y `has_function_privilege` falso para `anon`, `authenticated` y `service_role`.
- **Agenda.** 5) sup2 ve a vendInactive `de_baja:true`, `activo:false`, con actividad; no sin actividad. 6) sup1 ve a su suspendido
  `suspendido:true`, `activo:true`; no a vendInactive. 7) sup2 no ve al suspendido de sup1. 8) sup1Nested no ve hacia arriba.
  9) vend1: solo su fila, sin marcas. 10) Gerencia y Directorio: el mismo conjunto con los dos marcados. 11) Solo rezago ⇒ no
  aparece. 12) Contrato: claves del `strictObject` + `de_baja`/`suspendido`; como mucho una marca; la marca cuadra con `activo`.
  13) 42501: coordinador, anónimo, vendInactive y el suspendido. 14) No regresión: `testConversionMensual` (13150-13162) sigue
  excluyendo a vendInactive.
- **Divisor (Codex r1).** 15) En reuniones, el desglose suma el total en los diez contadores y NO en `divisor_realizacion`: la
  suma de los divisores de las filas + sus `canceladas_ajenas_vencidas` = el divisor del resumen (comprobarlo con una cita
  cancelada por otro asesor).
- **E2E del grupo C (local, con Docker).** 16) El recorrido real RPC → datos del supervisor (`datos-supervisor.ts`) → panel «Agenda
  del equipo»: un de baja y un suspendido con actividad salen marcados; con varios supervisores (agrupada), el marcado cae en «Sin
  equipo asignado» (efecto conocido) y un supervisor marcado forma su propio grupo; y la app anterior con la migración aplicada
  falla cerrada (para fijar el orden de despliegue).
