# F2.b — herramientas de generación (E1 = b1+b2, E2 = b3+b4)

Las cuatro migraciones de F2.b (`20260904120000`, `20260904130000`, `20260905100000`,
`20260905110000`) NO se teclearon: se **generaron** desde el texto VIVO de producción.

- `vivas/*.sql` — `pg_get_functiondef` de cada función tal como estaba en producción el
  04/09/2026 (paridad con banco-f7). Es el punto de partida de cada transformación.
- `gen-b1.py` … `gen-b4.py` — generadores: `rep()` anclado (aborta si el ancla no aparece
  EXACTAMENTE una vez) sobre el texto vivo, y escriben la migración con sus guardas md5,
  postflights y la reversa byte a byte. La constante de ruta apunta al scratchpad de la
  sesión `3cb2f982…`; para re-ejecutarlos apúntala a esta carpeta.
- `huellas14-prod.txt` — md5 de PRODUCCIÓN de las 14 funciones que las guardas comprueban.
  🔴 `pg_get_functiondef` termina en UN salto de línea: el md5 se toma del archivo menos
  ese único salto (con `rstrip()` de todos los saltos las huellas salen mal).
- `baja-historica.sql` — se corre en el banco tras `seed:demo` y antes de `test:rls`
  (la suite espera la baja histórica que producción ya tiene).

Ciclo de la suite en banco-f7: `reset-gate-banco.sql` → `npm run seed:demo` →
`baja-historica.sql` → `npm run test:rls` con `CRM_DEMO_PASSWORD='Banco-P055-2026!'`.
Estado al 05/09: 1272/1273 (el rojo conocido «tercer estado», en `banco/HALLAZGOS-SUITE.md`).

Retomar: nota del vault **RETOMAR-59** y `DISEÑO-F2B-COLA-CATALOGO.md` (§b5 = E3, lo que sigue).
