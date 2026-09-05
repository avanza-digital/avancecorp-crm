# F2.b — herramientas de generación (E1 = b1+b2, E2 = b3+b4, E3 = b5)

Las cinco migraciones de F2.b (`20260904120000`, `20260904130000`, `20260905100000`,
`20260905110000`, `20260905120000`) NO se teclearon: se **generaron** desde el texto VIVO de producción.

- `vivas/*.sql` — `pg_get_functiondef` de cada función tal como estaba en producción el
  04/09/2026 (paridad con banco-f7). Es el punto de partida de cada transformación.
- `gen-b1.py` … `gen-b5.py` — generadores: `rep()` anclado (aborta si el ancla no aparece
  EXACTAMENTE una vez) sobre el texto vivo, y escriben la migración con sus guardas md5,
  postflights y la reversa byte a byte. La constante de ruta apunta al scratchpad de la
  sesión `3cb2f982…`; para re-ejecutarlos apúntala a esta carpeta.
- `vivas/e3/*.sql` + `huellas-e3-prod.txt` — texto VIVO (05/09, = prod por md5) de las 7 funciones que b5 transforma
  (`convertir_lead`, `convertir_lead_externo`, `saga_conversion_fn`, `marcar_efectos_conversion` ×2 —el archivo `.3.sql`
  es la sobrecarga de 3 argumentos—, `alta_cliente_identidad_fn`, `trg_leads_disponibilidad_atomica`).
- `b5-nuevos.sql` — los objetos NUEVOS de b5 (tabla `crm.inversionista_operaciones`, helpers privados, 5 RPC de Gerencia);
  `gen-b5.py` lo incrusta tal cual: `python3 gen-b5.py <esta carpeta> <dir supabase>` escribe la migración, la reversa
  (`scripts/rollback-f2b-b5.sql`) y el registro (`scripts/registrar-f2b-e3.sql`).
- `huellas14-prod.txt` — md5 de PRODUCCIÓN de las 14 funciones que las guardas comprueban.
  🔴 `pg_get_functiondef` termina en UN salto de línea: el md5 se toma del archivo menos
  ese único salto (con `rstrip()` de todos los saltos las huellas salen mal).
- `baja-historica.sql` — se corre en el banco tras `seed:demo` y antes de `test:rls`
  (la suite espera la baja histórica que producción ya tiene).

Ciclo de la suite en banco-f7: `reset-gate-banco.sql` → `npm run seed:demo` →
`baja-historica.sql` → `npm run test:rls` con `CRM_DEMO_PASSWORD='Banco-P055-2026!'`.
Estado al 05/09 (E2): 1272/1273 (el rojo conocido «tercer estado», en `banco/HALLAZGOS-SUITE.md`). E3: ver el ledger.

Oráculo de E3: `scripts/oraculo-f2b-b5.sh` (dos sesiones psql; `run_as` cambia el ROL SQL a `authenticated` además
de las claims, así que prueba también los grants). Retomar: nota del vault **RETOMAR-59** y `DISEÑO-F2B-COLA-CATALOGO.md`.

## Bloque 1 de activación: [D-10] + [D-11] (05/09)

- `gen-d10.py` + `vivas/d10/crm.reservar_conversion_lead.4.sql` + `huellas-d10-prod.txt` → migración `20260905150000`
  (la reserva por persona cuenta el PUENTE en «un solo lead»), `scripts/rollback-f2b-d10.sql` y `scripts/registrar-f2b-d10.sql`.
  `python3 gen-d10.py <esta carpeta> <dir supabase>`. El texto vivo se sacó del banco (md5 = producción, `6242dfc9…`).
- Oráculo: `scripts/oraculo-f2b-d10-d11.sh` (D-10 + el ensayo D-11 del replay de un claim terminal tras una fusión).
  Corrido ANTES de aplicar D-10, la sección D-10 debe salir ROJA (mutante); después, 41/41 (v3: espejo de b5 —auditor M1— y el puente del propio lead manda —Codex #2—; el preflight del oráculo reconoce los md5 de v1/v2 y dice qué debe salir rojo).

## Bloque 2 de activación: [D-13] (05/09)

- `gen-d13.py` + `vivas/d13/*.sql` (5 funciones vivas: verificador 3-args, trigger de nacimiento, `tomar_lead_libre`,
  `convertir_lead`, `convertir_lead_externo`) + `huellas-d13-prod.txt` → migración `20260905160000`, `scripts/rollback-f2b-d13.sql`
  y `scripts/registrar-f2b-d13.sql`. `python3 gen-d13.py <esta carpeta> <dir supabase>`.
- Oráculo: `scripts/oraculo-f2b-d13.sh` (28 asertos; sin D-13 debe salir ROJO). Diseño: `DISEÑO-F2B-COLA-CATALOGO.md` § [D-13].

