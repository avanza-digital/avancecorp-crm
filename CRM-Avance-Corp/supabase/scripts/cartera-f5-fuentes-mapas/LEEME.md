# 20260930172255_crm_cartera_f5_fuentes_mapas — scripts de acompañamiento

Todos terminan en `raise` o son idempotentes. Orden en producción (lo lanza Miguel con `!`, desde `CRM-Avance-Corp/`):

1. `supabase db query --linked --file supabase/scripts/cartera-f5-fuentes-mapas/ensayo-oraculo.sql` — aceptación previa, deshecha: 33/33 iguales y tiempos.
2. `supabase db query --linked --file supabase/migrations/20260930172255_crm_cartera_f5_fuentes_mapas.sql` — aplica (preflight huella viva `94fa33cf…`, oráculo de filas dentro de la transacción, postflight huella `fa15f776…`).
3. `supabase db query --linked --file supabase/scripts/cartera-f5-fuentes-mapas/registrar.sql` — fila en `schema_migrations` (2 sentencias: función + comentario).
4. `supabase db query --linked --file supabase/scripts/cartera-f5-fuentes-mapas/verificar.sql` — termina en raise: huella y tiempos (fuentes ≤ 15 ms, ficha < 350, agenda < 130, cartera < 160).
5. `supabase db advisors --type all` (o el MCP) — ninguna clase nueva.

Reversa: `reversa.sql` (restaura el cuerpo vivo del 30/09 byte a byte; conserva la fila de `schema_migrations`: anotarlo en `MIGRACIONES.md`).

Banco Docker propio (`avancecorp-f5-fuentes-20260930`, imagen `supabase/postgres:17.6.1.105`, esquema `public,crm,private`
volcado de producción; paridad de cuerpos `crm` 278 / `private` 536 con el MISMO md5 que prod): migración → repetida (ya
aplicada) → reversa → repetida → migración → registrar → repetido; negativos: cuerpo ajeno (migración y reversa lo rechazan)
e `inversionista_canonica` alterada (migración y registro lo rechazan).
`prueba-sintetica.sql` (como `supabase_admin`, todo deshecho): 15 fuentes idénticas entre cuerpo vivo y nuevo, con expectativas
explícitas por caso: hijo y nieto fusionados, cadena de 17 (supera el tope 16), ciclo A↔B, padre inexistente, perfil sin persona,
identidad incoherente, cierres enlazados solo por inversión y solo por lead, upgrades encadenados, renovación tras upgrade,
ciclo de operaciones y analista nulo. El empate de dos
ancestros «upgrade» no puede darse (`contrato_nuevo_id` UNIQUE). `contexto-seguridad.sql`: solo lectura.
Medición y prototipos: `supabase/scripts/ensayo-cartera-f5-fuentes-mapas/`.
