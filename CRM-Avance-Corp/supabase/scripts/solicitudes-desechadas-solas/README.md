# Ensayo de «el CRM cancela solo las solicitudes de inversión que ya no corresponden»

Verifica la migración `20261022171001_crm_solicitudes_desechadas_solas.sql` (bloque 2.15 del plan del backend; orden de Miguel
D-58, decisiones D-59 y D-63, plan corto aprobado D-66) **en el banco Docker local (el laboratorio) y sin escribir nada**. Este
ensayo **no se corre contra producción**: siembra solicitudes de inversión con los actores reales del banco, hace un alta REAL de
contrato por la puerta viva del CRM (`crm.crear_contrato_con_cuenta_pdf_v2`) como un vendedor, corre la tarea nocturna y consulta
la solicitud como su asesor, siempre dentro de una transacción que termina en `rollback`.

**Estado (10/10/2026):** verificada por el escritor en el laboratorio (rondas 1, 2 y 3; la ronda 2 aplica las decisiones de Miguel
D-74, D-75, D-76 y D-77 sin cambiar ningún cuerpo de función; la ronda 3 atiende al auditor de permisos r1 —P2: la pieza escritora
relee también el MOTIVO bajo el candado; P3: el postflight vigila `service_role` en las dos puertas— y anota D-79 y D-80; la ronda 4
atiende los seis P2 de Codex r1: el contrato releído bajo candado, presupuesto único de 200 por corrida, recorrido que no se atasca
en omitidas/rechazadas, auditor habilitado y continuidad de postventa fijadas, reversa que fija piezas/tabla/columnas/job y detecta
lectores directos, cron obligatorio salvo marca de laboratorio, respuesta pública sin `contrato_id`). Pendiente de la verificación del
Director y de la revisión de Codex. No aplicada en ninguna base real.

**Reselle C2** (22/10/2026; plan AVANCE-BACKEND-1310-C2, encargo C2-a): `crm.confirmar_inversion_revisada_fn` se fija por su huella de producción del 22/10 (cuerpo `ef53419d…`, definición `33af606a…`; antes `5a4693a2…`/`68828d0a…`): `20261019001700` «recorrido» le añadió `private.recorrido_exigir(…, 'confirmar_inversion')` antes de los hechos financieros; la clave de idempotencia (= id de la solicitud), lo único que esta regla da por sabido de ella, sigue igual (el preflight lo comprueba aparte). Cambia en el preflight, el postflight y el caso K5 del oráculo. Nada más cambia.

## Qué prueba

La regla (D-58, D-59, D-63):

- **Caso 1, al instante:** cuando nace un contrato por el alta del CRM, las solicitudes de inversión PREPARADAS de Avance que
  llevan ese mismo número en `datos.contrato.numero_contrato` y **no son la que lo creó** (su id viaja como clave de idempotencia
  del alta) pasan a `cancelada` con motivo `numero_contrato_usado` y el detalle de **con cuál** contrato (id y número), por la
  vía `alta`. Nunca tumba el alta: si un disparador de la tabla se niega a cancelar una, el alta entra igual y la pieza lo informa.
- **Caso 2, cada noche** (`private.solicitudes_desechar_ciclo`, pg_cron `crm-solicitudes-desechar` 07:17 UTC = 02:17 Lima):
  primero las preparadas de Avance cuyo número ya lo usa un contrato que no crearon ellas (red para los contratos nacidos fuera
  del CRM: el Portal; D-75 y D-77), después las preparadas de **cualquier** empresa con **30 días** sin confirmarse ni corregirse
  (`actualizado_en`), motivo `sin_movimiento`; la preparada SIN número de contrato no es un caso aparte (D-74: D-63 manda sobre
  D-56). **Presupuesto ÚNICO de 200 cancelaciones por corrida** compartido por las dos pasadas (ronda 4, P2-2); las omitidas y las
  rechazadas no lo consumen y las exclusiones permanentes (acceso pendiente, con inversión, ya creó su contrato) se descartan antes
  del recorrido, así que una cola de rechazadas no tapa a una candidata válida (P2-3). Deja una fila por corrida en
  `crm.solicitudes_desechadas_corridas` con cuántas canceló, omitió y rechazó. Idempotente (sin efectos duplicados sobre la misma
  solicitud). El reloj es obligatorio: sin pg_cron la migración se niega, salvo la marca de laboratorio que pone el armador (`--sin-cron`).
  La marca `crm.laboratorio_sin_cron` es una **excepción operativa explícita, no una frontera de permisos** (cualquier sesión puede ponerla):
  con pg_cron presente y la marca puesta la migración se niega, y el ejecutor real comprueba antes de aplicar que no hay marca y sí reloj.
- **Nunca:** una con acceso Avance pendiente (`auth_claim_id`; D-76: ni a los 30 días), con inversión, que ya creó su contrato
  (fila en `private.contrato_altas_idempotentes` con su id como clave), confirmada o ya cancelada, la creadora, ni una de otra
  empresa por el número. Nunca se borra nada. Son las mismas guardas de `crm.cancelar_solicitud_inversion_fn` (D-19, D-58),
  releídas bajo el candado de la fila (`FOR UPDATE SKIP LOCKED`: nunca espera), **y el motivo también se relee bajo el candado**
  (P2 del auditor r1, ronda 3): para `numero_contrato_usado`, el número actual de la solicitud tiene que seguir siendo el del
  detalle; para `sin_movimiento`, `actualizado_en` tiene que seguir siendo el último movimiento observado y ≤ corte − días. Si la
  solicitud fue corregida entre la consulta de candidatas y el candado (otro número; `actualizado_en` movido), se omite y la
  fila no se toca; sin esos datos en el detalle, también se omite (fail-closed). Si un disparador de la tabla (la continuidad de
  postventa de una reinversión) se niega, la solicitud queda preparada y la corrida la informa como «rechazada» (D-77). La pasada
  nocturna «número usado» cancela TODAS las preparadas con un número que ya es de otro contrato, también si el contrato es anterior
  a la solicitud (tipeo corregible): D-79, como las 6 de D-58. Para `numero_contrato_usado` la pieza relee además EL CONTRATO del
  detalle bajo `FOR KEY SHARE SKIP LOCKED` (ronda 4, P2-1): si ya no existe, si lo está cambiando otra sesión o si ya no lleva ese
  número, omite y no toca la fila. La pieza no espera por la solicitud ni por el contrato; los disparadores de la tabla pueden esperar
  con sus propios candados (acotado por `lock_timeout`).
- **El motivo a la vista:** `crm.solicitud_inversion_fn` añade `cancelacion_motivo`, `cancelacion_detalle` (sin `contrato_id`: el
  UUID de un contrato ajeno no sale a la API; queda en la fila y en `public.audit_log`; ronda 4) y `cancelacion_texto` (nulos si el
  CRM no la canceló solo); la app los muestra en «Solicitud cancelada».

Escenario (`antes.sql`; V1 = un vendedor activo del banco con un cliente activo C1 con documento en su cartera cuya ficha de
inversionista I1 existe; N1…N7 números libres de la serie 2026-01-99NNNN; EX1 y EX2 números de contratos existentes).
**Todos los actores y datos de siembra son obligatorios**: si faltan, el ensayo aborta.

| Solicitud | Cómo se siembra | Qué se espera |
|---|---|---|
| S1, S2 | preparadas, Avance, número N1 | las cancela el alta con N1 (`numero_contrato_usado`, vía `alta`, contrato X) |
| S3 | preparada, Avance, número N2 | intacta; después la cancela V1 a mano (motivo nulo) |
| S4 | preparada, N1, acceso Avance reservado | nunca |
| S5 | preparada, N1, con inversión | nunca |
| S6 | preparada, **Prodelco**, con N1 en sus datos | otra empresa: nunca por el número |
| S7 | preparada, N1, con fila idempotente (ya creó su contrato) | nunca |
| S8 | preparada, N1, con un disparador de ensayo que rechaza su cancelación | sigue preparada; el alta entra; se informa «rechazada» |
| S9 | ya cancelada (hoy, sin motivo), N1 | intacta |
| S10 | preparada, N3, 31 días | la tarea (`sin_movimiento`, 30 días, último movimiento) |
| S11 | preparada, Prodelco, sin número, 45 días | la tarea (cualquier empresa) |
| S12 | preparada, N4, 29 días 23 h | todavía no |
| S13 | preparada, N5, 31 días, acceso reservado | nunca |
| S14 | preparada, EX1 (contrato existente), 1 día | la tarea (`numero_contrato_usado`, contrato EX1, vía `tarea`) |
| S15 | preparada, EX2, con fila idempotente que apunta a EX2 (el reintento de D-57) | nunca |
| S16 | preparada, N1: **la creadora** (el alta manda `clave_idempotencia` = S16) | nunca |
| S17 | preparada, N7, 31 días, con origen de **reinversión** cuyo cierre es de OTRA cooperativa (o anulado) | DEBE rechazarla la continuidad de postventa (P0409 «La inversión de origen no está disponible»): queda preparada e informada como rechazada; la tarea nunca aborta (expectativa independiente, ronda 4) |
| S18 | preparada, N6, 31 días, con origen de **upgrade** | la tarea (`sin_movimiento`): la continuidad deja pasar upgrade preparada → cancelada |
| S19 | preparada, sin número, 31 días, con fila idempotente (ya creó su contrato) | ni candidata: la pasada de 30 días la descarta antes del recorrido |

| Caso | Qué exige |
|---|---|
| R1 | El alta v2 con N1 entra (pese al rechazo forzado de S8), nace el contrato X con N1 y la memoria de idempotencia apunta a S16. |
| R2 | S1 y S2 canceladas con motivo, detalle (vía `alta`, X, N1, `cancelada_en`) y `actualizado_en` movido. |
| R3 | S16, S3, S4, S5, S6, S7, S9, S12, S13, S14 y S15 exactamente como se sembraron. |
| R4 | S8 sigue preparada; la pieza del alta, llamada otra vez con X, informa 0 canceladas y 1 rechazada (P0409 del disparador). |
| R5 | `public.audit_log` tiene el UPDATE de S1 y S2 (estado y motivo) a nombre de V1. |
| R6 | Un segundo alta con N1 muere con «El N de contrato N1 ya existe» (P0001) y no cambia nada. |
| R7 | La consulta como V1: S1 trae motivo, detalle y texto con N1; S3 trae las tres claves nulas y, quitadas, es byte a byte lo de antes de la migración. |
| R8 | La tarea: S14 cancelada (EX1, vía `tarea`), S8 rechazada, S10, S11 y S18 canceladas (`sin_movimiento`, 30, último movimiento, corrida), S17 rechazada e intacta, S19 ni candidata, S12/S13/S15 y el resto intactas; la corrida con sus contadores (3 canceladas sin movimiento, 1 rechazada) y el detalle. |
| R9 | La tarea otra vez: 0 canceladas (S8 otra vez rechazada), segunda corrida, nada más se mueve; **filas completas**: ninguna fila sembrada cambia ni gana auditoría (idempotencia = sin efectos duplicados sobre la misma solicitud). |
| R10 | La consulta de S10 dice «llevaba 30 días sin confirmarse ni corregirse». |
| R12 | (ronda 3, P2) El motivo se relee bajo el candado, en UNA sesión: S3 (lleva N2) llamada con el detalle de N1 → `omitida: el numero cambio bajo el candado`, intacta; S12 (29 días 23 h) como «sin movimiento» con corte = now() → `omitida: ya no cumple el corte`, intacta; S12 con un último movimiento observado que no es el suyo → `omitida: se movio bajo el candado`, intacta; control positivo (corte + 10 días y su último movimiento exacto) → `cancelada`, deshecho en una subtransacción (S12 vuelve a preparada). Va antes de R11. |
| R13 | (ronda 4, P2-1) El CONTRATO se relee bajo candado: S3 (N2) con un detalle cuyo contrato X lleva N1 → `omitida: el contrato ya no lleva ese numero`; con un contrato inexistente → `omitida: el contrato ya no existe`; S3 intacta. |
| R14 | (ronda 4, P2-2) Presupuesto único: 3 preparadas con el número de EX1 + 250 de 31 días (253 candidatas nuevas, en una subtransacción que se deshace) → corrida A cancela 200 (= el máximo: 3 + 197), B 53, C 0; nada queda sembrado. La regla garantiza **como máximo** 200 cancelaciones por corrida, no 200 exactas. |
| R15 | (ronda 4, P2-3) Progreso: 205 preparadas antiguas que el disparador de ensayo rechaza + 1 válida detrás → la válida se cancela en la PRIMERA corrida; la segunda no cancela nada; nada queda sembrado. |
| R11 | La cancelación de la pantalla de S3 como V1 sigue funcionando y deja el motivo nulo. |
| K1–K6 | Catálogo: las piezas con su ficha y sin EXECUTE para la API; las dos puertas (llamada única a la pieza, vista en la consulta, ficha, comentario); columnas y CHECK (un motivo sobre una preparada muere con 23514); la tabla de corridas con RLS, sin grants y con auditor completo (`private.tablas_sin_rastro()` no la lista; `private.assert_auditoria()` da lo mismo que antes); el job; lo que no se toca intacto; `private.assert_f7_piezas_cerradas()` pasa; lo diferido sobrevive. |
| K7 | (ronda 3, D-80) La consulta de runbook con la que el Director lee la última corrida (texto idéntico al del registro) funciona: trae los contadores y las «rechazadas» (S8 entre ellas). |

## Por qué así

El ensayo no prueba una copia: pega la **migración real** (preflight, columnas, tabla, piezas, puertas re-emitidas por ancla,
reloj, postflight y comentarios) dentro de la transacción. «Lo de antes» se mide en el montaje con la consulta vigente y «lo de
después» en el oráculo, en la misma transacción (`now()` es fijo). El alta es real (crea contrato, cronograma, cuenta, inversión y
memoria de idempotencia): se mide el camino de escritura de verdad, no una simulación. El rechazo de un disparador se fuerza con un
disparador de ensayo sobre S8 (determinista) y además se mide el real de postventa con S17.

## Cómo se corre

Desde `CRM-Avance-Corp/`. `EJECUTAR_SQL` es el comando que manda un archivo `.sql` al banco local (la herramienta del laboratorio
`fase-2/bloque-2.1/herramientas/lab_sql.py`, que compara una huella de la base antes y después y sale con 9 si algo quedó escrito).
**Una sola corrida a la vez en el laboratorio**: dos ensayos simultáneos se bloquean entre sí (la migración añade columnas con
`ACCESS EXCLUSIVE` y los trinquetes hacen DDL) y pueden dar un `deadlock` espurio.

```bash
# 1. ROJO: el oráculo SIN la migración. Es la medición del defecto.
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --sin-migracion > "$SALIDAS/rojo.sql"
$EJECUTAR_SQL "$SALIDAS/rojo.sql"
# 2. VERDE: la migración real + el oráculo. Termina SIEMPRE en excepción: eso es el veredicto.
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs > "$SALIDAS/verde.sql"
$EJECUTAR_SQL "$SALIDAS/verde.sql"
# 3. Mutantes (después de la migración) y 4. derivas (antes): cada uno con su veredicto de máquina. DIR_ENSAYO es obligatoria:
#    ahí quedan los SQL generados y sus salidas (la evidencia); los guiones no borran nada (ronda 2: ya no usan carpeta temporal).
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/mutantes" bash supabase/scripts/solicitudes-desechadas-solas/mutantes.sh
EJECUTAR_SQL="…" DIR_ENSAYO="$SALIDAS/derivas" bash supabase/scripts/solicitudes-desechadas-solas/derivas.sh
# 5. La reversa; la reversa con un SET añadido después de migrar (tiene que ABORTAR sin dejar rastro); y la reversa con
#    cancelaciones y corridas reales (ronda 4). Las derivas de la reversa (SET en una pieza, columna añadida, CHECK quitado,
#    lector directo, job cambiado) van dentro de derivas.sh.
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --reversa > "$SALIDAS/reversa.sql"
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --reversa-con-set > "$SALIDAS/reversa-con-set.sql"
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --reversa-poblada > "$SALIDAS/reversa-poblada.sql"
# 6. Trinquetes: la foto de todos los private.assert_*() (mutantes incluidos) y del censo, con y sin la migración.
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --trinquetes > "$SALIDAS/trinquetes-con.sql"
node supabase/scripts/solicitudes-desechadas-solas/armar-ensayo.mjs --trinquetes --sin-migracion > "$SALIDAS/trinquetes-sin.sql"
```

Resultados medidos: ver la sección del bloque en `supabase/migrations/MIGRACIONES.md` (`20261022171001`).

El ensayo se arma para una base que **todavía no tiene** esta migración: el preflight exige las dos puertas con su huella auditada
(alta v2 `505598d6…`/`d0b33d8f…`; consulta `0427b888…`/`1c5867ea…`) y nada de lo nuevo presente.

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `armar-ensayo.mjs` | Pega montaje + migración + oráculo en una transacción con `rollback`. Modos: `--sin-migracion`, `--mutante <archivo>`, `--reversa`, `--reversa-con-set`, `--reversa-deriva <archivo> --espera "<texto>"` (ronda 4: algo instalado tras migrar, la reversa debe negarse), `--reversa-poblada` (ronda 4: montaje + migración + `poblar.sql` + reversa + `reversa-poblada-oraculo.sql`), `--deriva <archivo> [--espera "<texto>"]` (la línea `-- @@MIGRACION@@` se sustituye por la migración), `--trinquetes [--sin-migracion]`; modificadores `--migracion <ruta>`, `--reversa-archivo <ruta>` y `--sin-cron` (pone la marca `crm.laboratorio_sin_cron`, la ÚNICA forma de que la migración siga sin pg_cron). Se niega si queda un `commit` suelto. |
| `poblar.sql` · `reversa-poblada-oraculo.sql` | (ronda 4) Un alta real con N1 y una corrida antes de revertir; después de la reversa: las canceladas siguen canceladas, las preparadas preparadas, cada motivo se recupera desde `public.audit_log` (el UPDATE auditado) y la corrida desde su INSERT auditado; nada de lo nuevo queda. |
| `antes.sql` | El montaje, DELANTE de la migración: auxiliares, actores obligatorios, números, la siembra, el disparador de rechazo de S8 y las mediciones de ANTES. |
| `pruebas.sql` | El oráculo (casos de arriba). |
| `mutantes.sh` | Un mutante por defensa: las guardas de la pieza escritora (acceso pendiente, con inversión, ya creó su contrato), la relectura del motivo bajo el candado (ronda 3: el número, el corte y el último movimiento, uno por rama), la subtransacción (sin ella el rechazo tumba el alta), el rechazo informado como cancelada, la empresa, el número, la vía del detalle, el umbral de 30 días, la exclusión del «mismo contrato», la empresa en la tarea, «sin movimiento» solo Avance, la corrida, la llamada desde el alta, la vista en la consulta, los dos textos; once de catálogo (EXECUTE, DEFINER, lock_timeout, volatilidad, comentario, anon, job, comando, auditor de la tabla, grant de la tabla, CHECK); y cuatro equivalentes (la guarda de estado duplicada por el filtro y el UPDATE; SKIP LOCKED, inobservable en una sesión; la exclusión de la creadora en la pieza del alta, duplicada por la guarda «ya creó su contrato»: su clave ya está en la memoria de idempotencia cuando corre la pieza, así que sin la exclusión solo cambia el contador de omitidas, que el oráculo no fija; y, desde la ronda 3, la comparación del número en el filtro de la pieza del alta, duplicada por la relectura del número bajo el candado —sin el filtro S3 llega a la pieza y se omite—). El mutante del umbral de 30 días muere desde la ronda 3 por los contadores (la pieza omite S12 por el corte), no por S12 intacta. Ronda 4: #11 (sin releer el número del contrato) y #12 (sin comprobar que el contrato exista), #19 y #20 (presupuesto: la pasada 1 no descuenta / la pasada 2 lo ignora), #21 (LIMIT antes de las guardas) y #22 (sin descartar la memoria idempotente en la pasada 2). Nota de método (Codex r2): #12 prueba la RESPUESTA «omitida: el contrato ya no existe», no que quitar esa comprobación permita cancelar (sin la rama, el número `NULL` también omite, con otro texto); #11 sí prueba que sin releer el número del contrato se cancela. 36 muertos + 4 equivalentes = 40. |
| `derivas.sh` | Veintiséis derivas ANTES de la migración (las dos puertas: cuerpo, SET, comentario, ACL de anon; lo que la regla da por sabido: cancelar, confirmar —la clave de idempotencia—, el resultado público; la forma de las tablas: columna ya presente, CHECK de estado, auditor, disparador de postventa apagado, PK de la memoria idempotente, UNIQUE del número, bandera de la empresa; lo nuevo ya existente: pieza ajena, tabla, job; ya aplicada; la ACL por `service_role`; la ACL con opción de concesión, que solo la ficha ve; y, desde la ronda 4, el auditor DESHABILITADO, la guarda de postventa sustituida por una que permite todo y la continuidad sustituida; desde la ronda 5, la guarda de postventa con otro `search_path` —mismo cuerpo: la huella no lo ve, la ficha sí— y la marca `crm.laboratorio_sin_cron` puesta con pg_cron presente) + «sin pg_cron y sin marca ⇒ aborta» con su control «sin pg_cron con la marca ⇒ entra avisando» (las dos como `supabase_admin`, dueño del stub del reloj: `EJECUTAR_SQL_ADMIN`), un control sin deriva, dos mutantes de la migración (sin comparar la ficha, el EXECUTE con opción de concesión se cuela —ni `anon` ni, desde la ronda 3, `service_role` sirven como mutante: los para además el postflight—; sin comparar el comentario, un comentario ajeno se cuela) y once derivas de la REVERSA (ronda 4: un SET en una pieza, una columna añadida a la tabla, un CHECK quitado a las columnas nuevas, un lector directo de la tabla, el job cambiado; ronda 5, lo que la «forma» de la ronda 4 no veía y la ficha completa sí: un CHECK añadido a la tabla de corridas, un índice, un valor por defecto, el comentario de una columna, una política, y un valor por defecto en una de las dos columnas nuevas: la reversa se niega sin rastro; con la reversa de la ronda 4 esas seis se COLABAN —`salidas/ronda5/ensayos/rojo-reversa/`—). |
| `reversa.sql` | Repone las dos puertas byte a byte y sus comentarios, desprograma el job, borra las piezas, la tabla y las columnas. Falla cerrada; lo que fija EXACTAMENTE antes de borrar (ni más ni menos): las dos puertas (huella de cuerpo y de definición, ficha —dueño, DEFINER, volatilidad, paralelo, configuración, ACL con opción de concesión— y comentario); las cuatro piezas (md5 de `pg_get_functiondef` y ficha); la tabla de corridas con su ficha completa (dueño, RLS y FORCE RLS, ACL, columnas con tipo/nulabilidad/default, todas las restricciones, índices, disparadores y si están habilitados, políticas, comentario de la tabla y de cada columna); las dos columnas nuevas (tipo, nulabilidad, default, comentario) y sus dos CHECK; la configuración del job (horario, comando, activo) si existe; y que ninguna otra función ni vista nombre a las piezas ni lea la tabla o las columnas nuevas. Lo que NO fija: nada fuera de esos objetos (p. ej. un objeto nuevo que no los nombre). No deshace cancelaciones (los motivos, los detalles y la fila de la corrida quedan en `public.audit_log` iguales a lo que había: `--reversa-poblada` lo exige con igualdad exacta). |

## Límites conocidos (lo que este ensayo NO garantiza)

1. **Concurrencia real (dos sesiones):** «dos altas con el mismo número» se prueba en serie (la segunda muere con el UNIQUE y no
   cambia nada); `SKIP LOCKED` no se puede observar en una sola sesión (el laboratorio no tiene `dblink` y abrir una segunda
   conexión está fuera del alcance del escritor). Queda para la integración (branch: `test-crear-contrato-concurrencia-local.mjs`
   como modelo).
2. **La vía del Portal** (`public.crear_contrato` directo): no la cubre el caso 1 (nada de `public` se toca: decisión de Miguel
   D-75); solo la tarea nocturna (S14 la representa), con un día de retraso como máximo. Es un límite aceptado, no un hueco.
3. **No llama como `authenticated` por la API** ni prueba el texto en la pantalla real: eso lo cubren las pruebas de vitest de la
   app (`inversion-nueva-venta-cruzada.test.tsx`, `inversion-solicitud.test.ts`) y, en la integración, `test-rls.mjs`.
4. **La saga del acceso Avance** (`crm.multiempresa_idempotencia`) está vacía en el banco: S4 y S13 prueban la guarda por
   `auth_claim_id`, no un acceso ya enlazado (que la regla tampoco toca: D-76).
