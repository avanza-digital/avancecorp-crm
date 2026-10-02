# Base para gestión del analista — banco sintético (B1)

Destino fijo: Docker `supabase_db_crm-avance-corp-local`, base `base_gestion_20261002`, creada desde el
banco sintético `conversion_tipos_v3_20260927` y sellada con el comentario
`BANCO SINTETICO base gestion 20261002 / sin produccion`. `banco.mjs` exige nombre y comentario exactos
antes de operar; no acepta URL ni credenciales. Nada toca producción.

```sh
node supabase/scripts/base-gestion/banco.mjs crear                 # una vez
node supabase/scripts/base-gestion/banco.mjs aplicar               # 20261002054402_crm_base_gestion_esquema.sql
node supabase/scripts/base-gestion/banco.mjs test                  # test.sql: contrato, CHECK, sello, EXPLAIN
node supabase/scripts/base-gestion/banco.mjs reversa-y-reaplicar   # reversa-esquema.sql + preflight otra vez
```

Fases siguientes (B2–B4) añaden aquí sus propios `.sql` de prueba. Reversa de B1: `reversa-esquema.sql`.
