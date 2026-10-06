# Base para gestión del analista — banco sintético (B1)

Destino fijo: Docker `supabase_db_crm-avance-corp-local`, base `base_gestion_20261002`, creada desde el
banco sintético `conversion_tipos_v3_20260927` y sellada con el comentario
`BANCO SINTETICO base gestion 20261002 / sin produccion`. `banco.mjs` exige nombre y comentario exactos
antes de operar; no acepta URL ni credenciales. Nada toca producción.

```sh
node supabase/scripts/base-gestion/banco.mjs crear                 # una vez
node supabase/scripts/base-gestion/banco.mjs paridad-acl           # ANTES de aplicar: copia la ACL (esquema, tablas, columnas,
                                                                   # funciones) del stack local = producción; el banco nace sin ACL.
                                                                   # Si se corre después, el revoke de tabla arrastra los grants por
                                                                   # columna de B1 (semántica medida en 20260919211105): reaplicar B1.
node supabase/scripts/base-gestion/banco.mjs aplicar               # 20261002054402_crm_base_gestion_esquema.sql
node supabase/scripts/base-gestion/banco.mjs test                  # test.sql: contrato, CHECK, sello, EXPLAIN
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar   # reversa-esquema.sql + preflight otra vez (solo si B1b NO está aplicada)
node supabase/scripts/base-gestion/banco.mjs aplicar-b1b           # 20261002224851_crm_base_gestion_proxima_llamada.sql (rellamada en el lead)
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b1b
node supabase/scripts/base-gestion/banco.mjs fixtures-b2           # actores (sup2, analistas B y C), 5 descartados, 2 vetados
node supabase/scripts/base-gestion/banco.mjs aplicar-b2            # 20261002061500_crm_base_gestion_no_contactar_supervisor.sql
node supabase/scripts/base-gestion/banco.mjs test-b2               # b2-rls.sql: 20 casos bajo rol (impersonación), termina en ROLLBACK
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b2
node supabase/scripts/base-gestion/banco.mjs aplicar-b3            # 20261002231436_crm_base_gestion_puertas.sql
node supabase/scripts/base-gestion/banco.mjs test-b3               # b3-puertas.sql: 40 casos de comportamiento bajo rol, termina en ROLLBACK
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b3
node supabase/scripts/base-gestion/banco.mjs aplicar-b4            # 20261002233851_crm_base_gestion_enfriamiento.sql (trigger de descanso)
node supabase/scripts/base-gestion/banco.mjs test-b4               # b4-enfriamiento.sql: 15 casos con fechas simuladas, ROLLBACK
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b4
node supabase/scripts/base-gestion/banco.mjs aplicar-b4b           # 20261002235342 (D13: ventana de intentos desde el fin del último descanso)
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b4b
node supabase/scripts/base-gestion/banco.mjs aplicar-b3b           # 20261003001014 (enmiendas de Codex: idempotencia, hija con uuid nuevo, orden)
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar-b3b
```

**B6b (20261004045038, «Ver no contactar» + detalle de las cifras).** No usa este banco sintético: corre en un banco con los
actores de `seed:demo` (el del gate de RLS en un stack Docker propio, a paridad con producción; en la construcción del 04/10,
`avancecorp-b6b-20261003`, puerto 58122, clon del volumen del gate del 03/10). Aplicar la migración en UN mensaje
(`psql -c "$(cat <archivo>)"`, como `db query --file`) y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b6b-vetados.sql      # 92 casos, ROLLBACK al final
node supabase/scripts/base-gestion/b6b-mutantes.mjs --puerto <puerto>                          # 20 mutantes: todos deben CAER
psql … -f supabase/scripts/base-gestion/reversa-b6b.sql                                         # vuelve a B5 exacto (antes que la de B5)
psql … -f supabase/scripts/base-gestion/registrar/20261004045038.sql                            # tras aplicar; idempotente
```

**B6c (20261004123611, la nota del veto reservada a sus puertas e inmutable).** La migración solo comprueba catálogo (sin DML con
el candado del `CREATE TRIGGER`: Codex r1); el comportamiento se comprueba DESPUÉS con `b6c-comprobar-tras-aplicar.sql`. Mismo banco que B6b (actores de `seed:demo`, B6b aplicada).
Las dos suites (`b6b-vetados.sql` y `b6c-nota-veto.sql`) se niegan a correr fuera de un banco LOCAL de Docker (secreto JWT de
desarrollo del CLI y conexión sin SSL). Aplicar en UN mensaje y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b6c-nota-veto.sql    # 76 casos, ROLLBACK al final
node supabase/scripts/base-gestion/b6c-mutantes.mjs --puerto <puerto>                          # 16 mutantes: todos deben CAER
psql … -f supabase/scripts/base-gestion/b6c-comprobar-tras-aplicar.sql                          # TRAS el commit (banco, rama y, si Miguel quiere, producción): comportamiento, ROLLBACK, veredicto en una fila
node supabase/scripts/base-gestion/b6b-mutantes.mjs --puerto <puerto> --solo-suite             # B6b sigue 92/92 con B6c
psql … -f supabase/scripts/base-gestion/reversa-b6c.sql                                         # vuelve a B6b exacto (antes que la de B6b)
psql … -f supabase/scripts/base-gestion/registrar/20261004123611.sql                            # tras aplicar; idempotente
```

**B7 · Bases cargadas, esquema (20261004160034).** Mismo banco (actores de `seed:demo`, B6b y B6c aplicadas). Aplicar en UN mensaje y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b7-esquema.sql                 # 177 casos, ROLLBACK al final
node supabase/scripts/base-gestion/b7-mutantes.mjs --puerto <puerto>                                     # 47 mutantes deben CAER + la reversa niega 21 derivas (control OK)
psql … -f supabase/scripts/base-gestion/b7-comprobar-tras-aplicar.sql                                     # TRAS el commit (banco, rama, producción): veredicto en una fila
psql … -f supabase/scripts/base-gestion/reversa-b7.sql                                                    # vuelve a B6c exacto (antes que la de B6c)
psql … -f supabase/scripts/base-gestion/registrar/20261004160034.sql                                      # tras aplicar; idempotente
```

**B8 · Bases cargadas, cargar y armar (20261004184501).** Mismo banco (actores de `seed:demo`, B6b, B6c y B7 aplicadas). Aplicar en UN mensaje y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b8-cargar.sql                  # 124 casos (identidad encendida y apagada), ROLLBACK al final
node supabase/scripts/base-gestion/b8-mutantes.mjs --puerto <puerto>                                     # 68 mutantes deben CAER + la reversa revierte en 4 controles y niega 16 derivas; banco SIN bases
node supabase/scripts/base-gestion/b8-mutantes.mjs --puerto <puerto> --concurrencia                      # 3 mutantes que solo ve la concurrencia (confirma datos: luego limpiar)
bash supabase/scripts/base-gestion/b8-concurrencia.sh --puerto <puerto>                                  # dos sesiones reales (13 escenarios: NOWAIT, armado con SKIP LOCKED e intercalaciones); CONFIRMA datos: luego limpiar-entre-corridas.sql
psql … -f supabase/scripts/base-gestion/b8-telefonos-sin-normalizar.sql                                   # solo lectura: teléfonos/DNI fuera de forma (para la rama y producción)
psql … -f supabase/scripts/base-gestion/b8-comprobar-tras-aplicar.sql                                     # TRAS el commit (banco, rama, producción): veredicto en una fila
psql … -f supabase/scripts/base-gestion/reversa-b8.sql                                                    # vuelve a B7 exacto (antes que la de B7)
psql … -f supabase/scripts/base-gestion/registrar/20261004184501.sql                                      # tras aplicar; idempotente
```

El gate (`test-rls.mjs`, bloque «Bases cargadas B8») deja una base y una armada de sup1 (sin DELETE por diseño):
`supabase/scripts/banco/limpiar-entre-corridas.sql` vacía las tablas de bases entre corridas del banco.

**B9 · Bases cargadas, repartir y recoger (20261004222602), r1.** Mismo banco (actores de `seed:demo`, B7 y B8 aplicadas). Cambia además la regla de B6
(`private.base_gestion_en_gestion_hasta`: el seguimiento activo cuenta desde que el dueño actual recibió el lead; Miguel, 04/10). Aplicar en UN mensaje y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b9-repartir.sql               # 155 casos, ROLLBACK al final (no exige un banco sin bases)
node supabase/scripts/base-gestion/b9-mutantes.mjs --puerto <puerto>                                     # 66 mutantes deben CAER + la reversa revierte en 4 controles (también con datos) y niega 8 derivas + el preflight niega 5 derivas de disparadores/B6
node supabase/scripts/base-gestion/b9-mutantes.mjs --puerto <puerto> --concurrencia                      # 8 mutantes que solo ve la concurrencia (confirma datos: luego limpiar)
bash supabase/scripts/base-gestion/b9-concurrencia.sh --puerto <puerto>                                  # dos sesiones reales (17 escenarios: NOWAIT de la base, SKIP LOCKED y candado SOLO de lo necesario, presupuesto de candados con la carrera foto/candado instrumentada, intento/reactivar/vetar/recoger cruzados, doble clic, REPEATABLE READ); CONFIRMA datos
psql … -f supabase/scripts/base-gestion/b9-consultas-rama.sql                                            # SOLO LECTURA, antes de aplicar (rama/producción): leads con vendedor y bandeja, reasignaciones sin cambio, impacto de la regla de B6, huellas del preflight
psql … -f supabase/scripts/base-gestion/b9-comprobar-tras-aplicar.sql                                     # TRAS el commit (banco, rama, producción): veredicto en una fila
psql … -f supabase/scripts/base-gestion/reversa-b9.sql                                                    # vuelve a B8 exacto y repone la ayudante de B6 (antes que la de B8 y la de B6); NO toca filas: se puede correr con datos
psql … -f supabase/scripts/base-gestion/registrar/20261004222602.sql                                      # tras aplicar; idempotente
```

El gate (`test-rls.mjs`, bloque «Bases cargadas B9») deja otra base de sup1 con sus recibos (sin DELETE): la misma limpieza.

**B10 · Bases cargadas: seguimiento, la base en la lista y el capital al reactivar (20261004223253), r4.** Mismo banco (actores
de `seed:demo`, B7, B8 y **B9 r2** aplicadas, SIN bases: limpiar antes). r2: UNA definición del estado del contacto
(`private.bases_carga_estado_contacto`) para las puertas de B9 y de B10: B10 reemplaza tres piezas del núcleo de B9 y borra su
clasificador (la reversa los repone byte a byte). r3 (E1): un armado desde el CRM que conserva su analista anterior es «sin
repartir» y el bloque lo elige; la lista de la base para gestión oculta solo a los dormidos del archivo. Aplicar en UN mensaje (`psql -c "$(cat <archivo>)"`; la migración toma el
candado de migraciones a nivel de SESIÓN antes de fijar la instantánea y lo suelta al final; si falla, se suelta al cerrar la
sesión) y luego:

```sh
psql -h 127.0.0.1 -p <puerto> -U postgres -f supabase/scripts/base-gestion/b10-seguimiento.sql            # 200 casos (reparto y recogida REALES de B9, estado único B9 = B10, fila anónima, cifras, roles, capital), ROLLBACK
node supabase/scripts/base-gestion/b10-mutantes.mjs --puerto <puerto>                                    # 76 mutantes deben CAER + la reversa revierte en 2 controles y niega 16 derivas
psql … -f supabase/scripts/base-gestion/b9-repartir.sql                                                   # la suite de B9 (155) con B10: solo D10 y Q2 condicionales
bash supabase/scripts/base-gestion/b9-concurrencia.sh --puerto <puerto>                                  # la concurrencia de B9 (62) con B10, sin cambios
psql … -f supabase/scripts/base-gestion/b10-comprobar-tras-aplicar.sql                                    # TRAS el commit (banco, rama, producción): veredicto en una fila (23 casos)
psql … -f supabase/scripts/base-gestion/reversa-b10.sql                                                   # vuelve a B9 r2 exacto (antes que la de B9)
psql … -f supabase/scripts/base-gestion/registrar/20261004223253.sql                                      # tras aplicar; idempotente
```

Las suites de B6c, B7, B8 y B9 tienen casos condicionales a B10 (cuerpo de la lista, 22023 al reactivar sin capital, los
dormidos del archivo sin repartir fuera de la lista —D10 de B9—, el núcleo de intentos con capital —Q2 de B9—): pasan con y
sin B10. La concurrencia de B9 no cambia. Con B10 aplicada, `b9-mutantes.mjs` no aplica (cambia piezas de B9 que B10 reemplaza): se corre con B10
revertida; y `reversa-b9.sql` se niega mientras B10 esté aplicada.

**B11 · Bases cargadas: la conversión de un contacto de base (20261006042144).** El cierre de un contacto de origen
`base_cargada` pesa 1 para el analista que lo consigue y no entra al divisor (E10). No toca tablas, policies ni grants: un
ayudante único (`private.conversion_origen_con_cierre`) reemplaza la lista copiada en siete funciones de conversión, y el
Divisor de coordinación gana la columna de base cargada (drop + create de sus dos privadas, misma ACL; clave `base_cargada` en
la puerta). La migración y la reversa se GENERAN desde los textos vivos de producción (`b11/vivo/`): no se editan a mano.
Banco: Docker a paridad con producción (con B7 y con datos de `seed:demo`: la suite clona un cierre real del mes). Migración y
reversa van como `postgres` (el postflight rechaza otro dueño); suite y mutantes, como el superusuario del stack local.

```sh
python3 supabase/scripts/base-gestion/b11/generar.py supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql   # 2 pasadas si cambia un cuerpo: medir huellas en el banco → b11/huellas-nuevas.json
python3 supabase/scripts/base-gestion/b11/generar_reversa.py supabase/scripts/base-gestion/reversa-b11.sql
python3 supabase/scripts/base-gestion/b11/generar_registrador.py                                                           # tras fijar el archivo final (lleva su md5)
psql … -X -At -F' | ' -f supabase/scripts/base-gestion/b11-paridad.sql > antes.txt                                          # solo lectura; ANTES de aplicar
psql … -U postgres -X -v ON_ERROR_STOP=1 -c "$(cat supabase/migrations/20261006042144_crm_bases_cargadas_conversion.sql)"  # UN mensaje
psql … -X -At -F' | ' -f supabase/scripts/base-gestion/b11-paridad.sql > despues.txt                                        # las huellas deben ser idénticas; solo aparece base_cargada = 0
psql … -U supabase_admin -X -f supabase/scripts/base-gestion/b11-conversion.sql                                             # 23 casos (base +1 al numerador y +0 al divisor, «otro» +0, mes sellado con NULL, ajuste), ROLLBACK
node supabase/scripts/base-gestion/b11-mutantes.mjs --puerto <puerto>                                                       # 16 mutantes deben CAER
bash supabase/scripts/base-gestion/b11-carrera.sh --puerto <puerto>                                                         # dos sesiones: sin el candado la carrera existe; con él, el freno vale hasta el commit
psql … -U postgres -X -v ON_ERROR_STOP=1 -c "$(cat supabase/scripts/base-gestion/reversa-b11.sql)"                          # vuelve al estado de antes, byte a byte
psql … -U postgres -X -v ON_ERROR_STOP=1 -c "$(cat supabase/scripts/base-gestion/registrar/20261006042144.sql)"             # tras aplicar; idempotente
```

Migración y reversa bloquean antes de su primera lectura las dos tablas donde nace un cierre (`crm.lead_asignaciones` y
`crm.conversion_acreditaciones`, SHARE ROW EXCLUSIVE NOWAIT): si alguien escribe en ese instante se niegan con «could not
obtain lock» y se repiten. Frenos (todos P0409, sin dejar nada ni retener el candado): la migración se niega si ya hay un cierre de un contacto de base,
si cambió alguno de los diez cuerpos, su dueño o su ACL, si aparece un llamador nuevo del divisor de empresa o si el censo
analítico no está vigente y sellado; la reversa, además, si otra función ya usa el ayudante. El gate (`test-rls.mjs`, bloque
«Bases cargadas B11») es de solo lectura: catálogo del núcleo y la clave nueva en un mes abierto.

Reversas, en este orden: B11 (`reversa-b11.sql`: solo funciones de conversión, no depende de las demás) · B10 (`reversa-b10.sql`, antes que todas las de bases) · B9 (`reversa-b9.sql`, antes que la de B8; no toca filas) · B8 (`reversa-b8.sql`, antes que la de B7) · B7 (`reversa-b7.sql`, antes que la de B6c) · B6c (`reversa-b6c.sql`, antes que todas; la de B2 se niega mientras levantar tenga el cuerpo de B6c) · B6b (`reversa-b6b.sql`) · B3b (`reversa-idempotencia-y-orden.sql`) · B4b (`reversa-ventana-descanso.sql`) · B4 (`reversa-enfriamiento.sql`) · B3 (`reversa-puertas.sql`, se niega si queda el trigger de B4) · B2 (`reversa-no-contactar-supervisor.sql`, independiente) · B1b (`reversa-proxima-llamada.sql`, se niega si quedan núcleos de B3) · B1 (`reversa-esquema.sql`, se niega si B1b sigue aplicada). Rama de Supabase con datos: `rama.mjs estado | aplicar | explain | gate` (la URL del pooler la aporta Miguel por archivo; ver `BASE PARA GESTION/ESTADO.md`).
