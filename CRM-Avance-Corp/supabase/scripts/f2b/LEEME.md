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

- `gen-d13.py` (v4.4) + `vivas/d13/*.sql` (9 funciones vivas: verificador 3-args, trigger de nacimiento, `tomar_lead_libre`,
  `convertir_lead`, `convertir_lead_externo`, `marcar_efectos_conversion` 3-args, `rescatar_descartes`, `deshacer_descarte_implementacion`
  y `reservar_conversion_lead` 4-args TAL COMO LA DEJA D-10 —requisito—) + `huellas-d13-prod.txt`; 9 helpers privados (`bloquear_personas_de_leads` devuelve `{personas, claves}` y `lead_dentro_de_bloqueo` exige que el lead siga dentro de lo bloqueado —Codex v4.2, ABA—), la puerta `crm.fijar_dni_lead_fn` y el trigger `trg_leads_zz_reapertura_solo_rpc` → migración `20260905160000`, `scripts/rollback-f2b-d13.sql`
  y `scripts/registrar-f2b-d13.sql`. `python3 gen-d13.py <esta carpeta> <dir supabase>`.
- Oráculo: `scripts/oraculo-f2b-d13.sh` (81 asertos; sin D-13 debe salir ROJO; fixtures de descartado viejo con el trigger del sello apagado un instante). Diseño: `DISEÑO-F2B-COLA-CATALOGO.md` § [D-13].


## Bloque 2 de activación: [D-9] + [D-3] + [D-2] (05/09 noche → 06/09)

Tres migraciones independientes, una por ítem, generadas desde el texto VIVO (`vivas/bloque2/*.sql`, md5 = producción en
`huellas-bloque2-prod.txt`): `python3 gen-d9.py <esta carpeta> <dir supabase>` (ídem `gen-d3.py`, `gen-d2.py`). Cada una escribe la
migración, `scripts/rollback-f2b-dN.sql` (byte a byte + desregistro) y `scripts/registrar-f2b-dN.sql`.

- `gen-d9.py` → `20260906100000`: los auditores de `crm.leads` y `crm.cierres_externos` pasan a `private.log_audit_sin_secretos('dni')` /
  `('documento')`. NO va detrás de la bandera (privacidad). Oráculo `scripts/oraculo-f2b-d9.sh` (18; sin D-9, 5 rojos).
- `gen-d3.py` → `20260906110000`: veto coherente (tareas de perfil, ficha del cliente, sueltos/puente). Transforma 4 vivas
  (`marcar/levantar_no_contactar`, `trg_gestion_lead_serializada`, `leads_vetados_persona`) + 3 helpers privados + 1 trigger.
  Oráculo `scripts/oraculo-f2b-d3.sh` (36; sin D-3, 13 rojos). 🔴 Forma: `uq_leads_dni_vivo` admite UN lead vivo por DNI; las
  identidades nacidas de un lead NO quedan verificadas (la persona del fixture nace en la coop).
- `gen-d2.py` → `20260906120000`: offboarding atómico sobre los tramos + capacidad operativa del nuevo responsable. Transforma 3 vivas
  (`impacto_desactivacion_usuario_fn`, `fijar_membresia_activa_fn`, `reasignar_responsable_relacion_fn`). Oráculo
  `scripts/oraculo-f2b-d2.sh` (51; sin D-2, 24 rojos; crea V2/V3 bajo S y devuelve sus personas a Gerencia al final).
- Diseño: `DISEÑO-F2B-COLA-CATALOGO.md` § «Bloque 2 de activación». Bloques de la suite: `testIdentidadF2bD9/D3/D2` en `test-rls.mjs`.

## Bloque 3 de activación: [D-4] el importador por la puerta SQL (06/09)

- `gen-d4.py` → `20260906130000` (`crm.importar_lead_fn(jsonb)`, solo service_role: los mismos candados y el MISMO INSERT del edge, con
  `23505`/`P0481`/`P0429` convertidos en veredicto y el reingreso en la misma transacción), `scripts/rollback-f2b-d4.sql` (DROP) y
  `scripts/registrar-f2b-d4.sql`. Sin funciones vivas transformadas. Oráculo `scripts/oraculo-f2b-d4.sh` (49 en v6; sin la puerta, 39 rojos).
- v3 (auditor-rls 06/09): guardas de los triggers 000/00/zz e índices únicos (son el contrato del importador), veredicto de duplicado
  sin PII (nombre del índice), transitorios del reingreso suben, `op_privilegiada` off, dueño `postgres` en postflight/registro; en el
  edge, la puerta ausente (`PGRST202`/`42883`/`42501`/404) es temporal, no rechazo. Espejo `_supabase_functions/…/crm-importar-leads` sincronizado.
- v4 (Codex 06/09): sin dedup previo en el edge (decide la puerta); contactos los toma el trigger 00 tras el veto (una persona vetada no espera);
  casts tras el gate; categorías cerradas en el edge; el Apps Script conoce «YA ES CLIENTE» (🔴 reinstalarlo en Google antes del ON).
- v5 (Codex 2ª ronda): reingreso idempotente 24 h (`repetido`); suben las clases 08/40/53/55/57/58/XX; la puerta no valida formato
  (decide la fila al nacer, misma prioridad que el INSERT directo); panel de la hoja cuenta «ya clientes»; candados del oráculo confirmados.
- v6 (Codex 3ª ronda): idempotencia sin el número de fila y a 7 días (+ ensayo simultáneo); solo 22/23/P0 son definitivos en el reingreso;
  `catalogo.ts` (claves propias); contador del panel por nombre/teléfono/estado; contención hasta señal y ms.
- 🔴 Regla aprendida: el importador NO usa el veredicto comercial (enfriamiento, ficha, veto de un lead viejo): el trigger de disponibilidad
  exime al escritor sin sesión; la puerta debe hacer el mismo INSERT y traducir, no juzgar.
- Fase 2 = el edge `functions/crm-importar-leads` (`rpc importar_lead_fn`; tests Deno `deno test` en esa carpeta). Deploy aparte.

## Bloque 4 (06/09): `[D-5]` y `[D-15]`
- `gen-d5.py` + `huellas-d5-prod.txt` + `vivas/d5/` (reserva 1 arg, sellado 1 arg, sellado 3 args: textos vivos de prod = banco) → `20260906140000` (las firmas de un argumento se cierran con ON; el sellado por persona marca su paso con el GUC `crm.sellado_por_persona`; `crm.abandonar_conversion_gerencia_fn`), `rollback-f2b-d5.sql`, `registrar-f2b-d5.sql`. Oráculo `../oraculo-f2b-d5.sh` (28/28; mutante 20 rojos).
- `gen-d15.py` + `huellas-d15-prod.txt` → `20260906150000` (`crm.reabrir_lead_fn`, la puerta del botón «Reabrir»), `rollback-f2b-d15.sql`, `registrar-f2b-d15.sql`. Oráculo `../oraculo-f2b-d15.sh` (37/37; mutante 28 rojos).
- Lección: antes de cerrar una firma vieja, buscar quién DELEGA en ella (`strpos(prosrc, 'nombre(')` en pg_proc): el sellado por persona delegaba en la de un argumento.
