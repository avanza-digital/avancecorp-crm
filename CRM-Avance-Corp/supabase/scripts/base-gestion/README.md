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
```

Reversas, en este orden: B3 (`reversa-puertas.sql`) · B2 (`reversa-no-contactar-supervisor.sql`, independiente) · B1b (`reversa-proxima-llamada.sql`, se niega si quedan núcleos de B3) · B1 (`reversa-esquema.sql`, se niega si B1b sigue aplicada). Rama de Supabase con datos: `rama.mjs estado | aplicar | explain | gate` (la URL del pooler la aporta Miguel por archivo; ver `BASE PARA GESTION/ESTADO.md`).
