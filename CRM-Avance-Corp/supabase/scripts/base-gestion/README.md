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

Reversas, en este orden: B8 (`reversa-b8.sql`, antes que todas) · B7 (`reversa-b7.sql`, antes que la de B6c) · B6c (`reversa-b6c.sql`, antes que todas; la de B2 se niega mientras levantar tenga el cuerpo de B6c) · B6b (`reversa-b6b.sql`) · B3b (`reversa-idempotencia-y-orden.sql`) · B4b (`reversa-ventana-descanso.sql`) · B4 (`reversa-enfriamiento.sql`) · B3 (`reversa-puertas.sql`, se niega si queda el trigger de B4) · B2 (`reversa-no-contactar-supervisor.sql`, independiente) · B1b (`reversa-proxima-llamada.sql`, se niega si quedan núcleos de B3) · B1 (`reversa-esquema.sql`, se niega si B1b sigue aplicada). Rama de Supabase con datos: `rama.mjs estado | aplicar | explain | gate` (la URL del pooler la aporta Miguel por archivo; ver `BASE PARA GESTION/ESTADO.md`).
