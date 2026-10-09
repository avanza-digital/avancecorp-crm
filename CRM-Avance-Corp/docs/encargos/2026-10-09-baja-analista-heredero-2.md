# Encargo 2 a Codex (IMPLEMENTADOR) — Baja de analista: cooperativas, exención analítica, rótulo y pruebas por rol

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Mismas reglas que el encargo 1
(`docs/encargos/2026-10-09-baja-analista-heredero.md`): escribes SOLO en este worktree, sin commit/push, sin red,
sin Docker, sin producción, sin invocar a otros agentes. Todo en español. Informe breve al terminar.

## Estado actual (léelo, ha cambiado desde tu primera entrega)

Claude rehízo la migración tras medir en producción (el SQL anidado llevaba el capital de setiembre de 15 a 171 ms):
- 4 ayudantes: `private.analista_dado_de_baja` (SQL), `heredero_de_baja`, `analista_efectivo_contrato`,
  `analista_efectivo_cierre` (los tres PL/pgSQL, con camino rápido).
- `private.contratos_afectados_por_anulacion` se quedó INTACTA (tu duda era correcta: rompía la exclusión de anulados).
- `capital_episodios` calcula el efectivo UNA vez por fila con `cross join lateral … as ef(analista_id)`.
- `cartera_f5_fuentes` usa un mapa `bajas_map` (una vez por llamada).
- Producción (ensayos deshechos): movimientos correctos; tiempos capital oct 6,4→5,4 ms, set 14,5→15,3 ms, cartera
  12,4→16,1 ms. Banco: ciclo completo PASS, ensayo 68/68, dos mutantes cazados.
- `generar-cuerpos.py` es la fuente de los cuerpos: TODO cambio de cuerpo se hace AHÍ y se regenera
  (`python3 -I supabase/scripts/baja-analista-heredero/generar-cuerpos.py`, luego `--verificar`).

## Hallazgos de la auditoría (auditor-rls) que este encargo cierra

### 1. [P2] `crm.cierres_externos_fn(date)` — debe seguir la regla (decisión: opción «toda vía»)
Cuerpo VIVO de producción: `supabase/scripts/baja-analista-heredero/vivo/crm.cierres_externos_fn.sql`
(md5 de `pg_get_functiondef` = `d44dec0ba4b92ecd1991a7ff204dc57e`; dueño postgres; ACL
`{postgres=X/postgres,authenticated=X/postgres}`; SECURITY DEFINER; STABLE; plpgsql; search_path vacío).
Hoy reparte por `ce.vendedor_id` mientras `cumplimiento`/`capital_real` ya hereda → el panel «Por empresa» resta
cifras de dueños distintos (Avance de Noelia 0, el de Elizabeth inflado S/ 88.000). Cambios (generados en
`generar-cuerpos.py`, contando ocurrencias con `sustituir`):
- Ámbito: TODO `ce.vendedor_id = any(v_visibles)` / `ce0.vendedor_id = any(v_visibles)` pasa a usar el efectivo
  (`private.analista_efectivo_cierre(…)`). En las dos listas con tope 200 (`cierres`, `cierres_mes`) y en
  `por_empresa`, calcúlalo UNA vez por fila con `cross join lateral private.analista_efectivo_cierre(ce0.id) as
  ef(analista_id)` y expónlo como columna (`vendedor_efectivo_id`) del subselect; en los conteos/totales
  (`cierres_total`, `cierres_mes_total`, `totales`) basta la llamada en el `where` (con `v_global or …` cortocircuita).
- Salida: `'vendedor_id'` y `'vendedor_nombre'` de las filas y de `por_empresa` = el efectivo (join a perfiles por el
  efectivo; `group by` por el efectivo).
- El `'telefono'` NO cambia (ya sigue a la relación actual). Nada más cambia: firma, payload, claves, tope 200,
  exclusión de la demo por id.

### 2. Exención analítica de `crm.cierres_externos_fn(date)` — re-declararla en la misma migración
Patrón: `supabase/migrations/20260915170017_crm_analitica_exencion_cierres_externos_f8.sql`. Hoy en producción:
`private.analitica_leads_citas_exenciones.huella` de ese objeto = `06bafcce0f005d95914bd2339d064bed` (= md5 del
`prosrc` normalizado vivo; clase `analitica`), 43 exenciones, y `analitica_lc_sello.sello =
private.huella_exenciones_analitica_lc()` (sello vigente).
- PREFLIGHT: exigir esa huella de exención y el sello vigente (`is not true` → abortar).
- Tras reemplazar la función: `update` de `huella` (misma fórmula de normalización que 20260915170017) y `razon`
  (añadir una frase: baja de analista, 09/10/2026, ámbito y nombres por el analista efectivo); resellar
  `private.analitica_lc_sello` como en 20260915170017 (`lock table … in share row exclusive mode` antes).
- POSTFLIGHT: huella de exención = la normalizada del cuerpo nuevo; sello = `private.huella_exenciones_analitica_lc()`.
- **NO** llamar a `private.assert_analitica_leads_citas()`: en producción YA falla por tres funciones ajenas sin
  declarar (`crm.gestiones_resumen_fn`, `private.citas_clientes_core`, `private.gestion_diaria_cola_hechos`);
  llamarla abortaría esta migración por trabajo de otros. Documentarlo en la cabecera.
- Reversa: restaurar el cuerpo vivo, devolver la fila de exención a su estado vivo EXACTO y resellar. El estado
  vivo (leído de producción el 09/10) está en `supabase/scripts/baja-analista-heredero/vivo/exencion-cierres-externos.json`
  (`huella`, `clase`, `razon` literal y su `md5_razon`). La migración exige en su PREFLIGHT `md5(razon)` = ese
  `md5_razon`; la reversa repone `razon` desde el literal (dólar-citado) y comprueba su md5.

### 3. [P3] Revocar también a `service_role` en los 4 ayudantes (ACL esperada sigue `{postgres=X/postgres}`).

### 4. [P3] Rótulo de `crm.atribucion_contrato_fn`
Hoy `adoptada` = cadena distinta de `analista_cierre_id`. En 2026-01-001570 (cadena Pierina, procesado y heredado
por Betzabeth) el front mostraría «Cuenta a Betzabeth — adoptada de la cadena del upgrade». Nuevo significado:
`adoptada` = la cadena manda de verdad: `cadena is not null and cadena <> analista_cierre_id and efectivo = cadena`.
`heredada` igual que ahora (efectivo distinto de `coalesce(cadena, analista_cierre_id)`). `cadena` sin cambio.

### 5. [P2] Pruebas por ROL en `ensayo-sintetico.sql`
Hoy todo se llama como `postgres` con claims de gerencia. Añadir (sin romper los 68 casos; ajusta la expectativa de
`adoptada` de `v_renovacion` a false por el punto 4):
- Dos supervisores: S1 supervisa a A y H; S2 a P e I (siembra antes de desactivar a P e I).
- Llamar a las puertas como `authenticated` (`set_config('role','authenticated',true)` + claims `sub`/`role` en
  `request.jwt.claims` y `request.jwt.claim.sub`) y VOLVER a `postgres` antes de registrar el caso (el rol
  authenticated no puede escribir en las temporales).
- Casos: H ve en `crm.altas_nuevas_por_analista_fn(60)` las altas heredadas de P y ninguna fila con P; S1 también;
  S2 no ve las heredadas (sí las de I, que no tiene heredero); A no ve las de H.
  `crm.atribucion_contrato_fn(v_nuevo)` como H → `heredada` true y nombre de H; como A (otro vendedor, no asesor) →
  NULL. `crm.cierres_externos_fn(mes)` como H → la cooperativa heredada (`v_cierre`) sale en `cierres_mes` y en
  `por_empresa` con `vendedor_id` = H; como S2 → no sale `v_cierre`, sí `v_cierre_precedencia` (se queda en P);
  como gerencia → `por_empresa` suma bajo H lo heredado. Permisos: `anon` sin EXECUTE en las dos puertas y nadie
  salvo postgres con EXECUTE en los 4 ayudantes (`has_function_privilege`).
- `cierres_externos_fn` exige rol CRM y periodo = primer día del mes no futuro.

## Entregables
- `generar-cuerpos.py` (cierres_externos_fn + rótulo), migración regenerada (lista de huellas con
  `cierres_externos_fn` anterior `d44dec0b…` y nueva `PENDIENTE_MEDIR_EN_BANCO`; las ya medidas que cambien también a
  PENDIENTE), `reversa.sql`, `ensayo-sintetico.sql`, y que `ensayo-produccion.sql` y `medir-produccion.sql` sigan
  conteniendo la migración AL BYTE (hay un bloque en el encargo 1 de cómo se generan: cabecera + migración sin
  `commit` + bloque final; consérvalos).
- NO toques `MIGRACIONES.md` ni `LEEME.md` (los rehace Claude al final). NO toques `registrar.sql` (se regenera).
