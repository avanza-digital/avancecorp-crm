---
tags: [facturacion, plan, datos, crm]
fecha: 2026-10-08
estado: propuesta — Miguel eligió la opción B; falta OK para tocar `public` y 4 decisiones
---

> Plan de la decisión 1 de [[Facturacion - fase 0 decisiones de datos (2026-10-08)]] (opción B: corregir los 12 + prevenir, antes de sellar septiembre). Sin código. Toca `public.contratos` (puerta + trigger): necesita el OK explícito de Miguel. La consulta de medición del anexo NO se ha ejecutado: pasarla primero por el banco Docker.

## Medición en producción (08/10 19:11 Lima, solo lectura) y estado

- 🔴 **Plazo real:** agosto está SELLADO y el cron `crm-cierre-mes-diario` está ACTIVO (09:20 Lima). Septiembre se puede
  sellar desde el 11/10 00:00 → el cron lo sellará el **11/10 ~09:20 Lima**. La corrección debe estar aplicada antes.
- Los 12: PDF congelado (sellado, revisión 1), producto legacy, ninguno fuera de lo esperado, **0 cambian de dueño en la
  conversión** (la decisión 3 del plan desaparece).
- **Nacieron como «nuevo» y nadie los corrigió**: la operación de upgrade (`fuente = flujo_cartera`) se creó DESPUÉS sobre
  el contrato ya existente. Corrige la hipótesis del plan: la prevención va también donde se CREA la operación.
- 106 contratos legacy (mar–jul) con upgrade/renovación SIN operación: no se tocan ni se restringen.
- **Efecto en metas de septiembre (% de la meta de capital nuevo):** Merlys Garcia 90,6 → 13,6 · Lisseth Nuñez 114,6 →
  95,0 (baja de 100 %) · Astrid Centenaro 43,5 → 25,3 · Linda Condori 70,1 → 60,1 · Betzabeth Fuenmayor 351,6 → 251,6.
  Total por moneda igual: PEN «nuevo» 6,46 M → 4,37 M y «upgrade» 0,73 M → 2,82 M.
- 08/10 ~19:25: implementación y ensayo en banco Docker propio en curso (rama `crm/categoria-por-operacion`).
- ✅ **08/10 ~19:45 — Miguel APRUEBA corregir septiembre** («ok sí está de acuerdo»), tras la explicación comercial. Su condición: «no vas a quitarle capital a ningún analista» → confirmado: los 12 siguen con el mismo analista, monto, moneda y día (0 cambian de analista; el total de cada uno cuadra). Solo cambia la casilla «Capital nuevo» → «Upgrade», y con ella el % de la meta de capital nuevo de 5 analistas. (Pagos y compensaciones: fuera de nuestro alcance —«solo construimos sistemas», Miguel 08/10—; no se listan como pendiente.)
- **08/10 noche — banco:** migración `20261009120000_crm_categoria_contrato_por_operacion.sql` + guiones en la rama `crm/categoria-por-operacion` (worktree `categoria-por-operacion-20261008`, banco Docker `avancecorp-categoria-20261008`, puertos 5600x). Gate A/B sin rojos nuevos (44 de fondo), prueba 76/76, mutantes 13/13, ensayo/real/reversa OK, auditor-rls APPROVE_WITH_CHANGES aplicado. **Causa confirmada:** 11 de los 12 los creó el backfill B del 23/09 (inserta operaciones sin tocar contratos), no los analistas. Efecto: el «cedido» de la tarjeta de rentabilidad baja (banco: S/ 217.361 → 6.190); hueco inverso (contrato sin operación → upgrade por «Corregir») queda abierto a propósito.
- **Codex r1: BLOCK** → aceptados F1 (carrera sincronización/edición: bloquear la fila), F2 (solo READ COMMITTED en el núcleo), F3 (orden periodo → fila), transporte (los guiones van como UN mensaje: sin candados de sesión, READ COMMITTED + candado de transacción + `lock table … in share mode`), guarda AFTER UPDATE WHEN, y menores. **Rechazados con evidencia:** Q3 (ningún trigger actual reescribe la categoría: el de producto solo toca `producto_condicion_id`, el de inmutables id/fechas/cierre) y la «foto de pago» (se genera al sellar; septiembre sigue abierto). En curso los arreglos; luego Codex r2 (última).
- **08/10 ~21:40 — arreglos r1 en el banco:** gate sin rojos nuevos, prueba 81/81, dos conexiones 4/4, mutantes 19/19, transporte de un solo mensaje OK y 0 candados tras cada corrida.
- **Codex r2 (última ronda del protocolo): BLOCK** con N1 (P1: la guarda no rechazaba REPEATABLE READ → con foto vieja se podía dejar nuevo/upgrade), N2 (P1: los guiones heredaban el aislamiento de la sesión) y N3 (P2: «mes → share» invertía el orden de un alta en curso). **Aceptados los tres**; se cierran con pruebas en el banco (guarda y sincronización solo en READ COMMITTED; guiones con `begin isolation level read committed`; candados de tabla NOWAIT antes del mes y abortar para reintentar). Sin tercera ronda: decide el PRIMARY con la evidencia del banco.
- ✅ **08/10 ~23:00 — r2 cerrado en el banco y PR abierta:** prueba 81/81 + 6/6 en REPEATABLE READ (todo responde 25001), dos conexiones 9/9 (el intercalado exacto de N1 deja upgrade/upgrade; frente a un alta detenida o a un sello en curso los guiones salen al instante sin escribir), mutantes 23/23, transporte de un solo mensaje 12/12, gate 44/3043 → 44/3056 (mismos 44 de fondo, bloque nuevo 13/13). `check:scripts` PASS. Revisé la migración y los guiones yo mismo: acepto. Commit `be95cffd`, **PR #230** (`crm/categoria-por-operacion`), migración md5 `f054d9fe…`. Nada aplicado en producción todavía.
  - Consecuencia de N1: la migración va en READ COMMITTED (no REPEATABLE READ como la casa), y **todo SQL futuro que cambie una categoría o registre una renovación/upgrade tiene que ir en READ COMMITTED**.
  - Queda abierto (aceptado): corregir a la vez la fecha y la categoría del mismo contrato puede abortar una con 40P01 (nada a medias); 25001 en vez del 0A000 de la casa; los guiones bloquean las escrituras en 22 tablas unos segundos (correrlos de noche).
  - 🟢 **08/10 22:55 — MIGRACIÓN APLICADA EN PRODUCCIÓN** por Miguel con `!` (corrió entera: última fila `pg_advisory_unlock = true`, preflight y postflight OK). Desde aquí la guarda y la sincronización están VIVAS. Falta: registrador, ENSAYO, REAL, oráculo, tipos y fusionar #230.
  - 🟢 **08/10 23:47 — 2-REAL APLICADO EN PRODUCCIÓN: «OK: 12 contratos de nuevo a upgrade»**, firmado por ADMINISTRADOR AVANCE CORP (`bf1c562e`, elegida por Miguel: el 1.er ensayo abortó sin escribir porque hay 3 cuentas de Gerencia —ADMINISTRADOR AVANCE CORP, CARLOS VALLES, KIRK SANCHEZ— y la regla «mismo nombre que el perfil de pruebas» no casaba; los guiones ahora fijan el prefijo, commit `6003d7b8`). Registrador OK (md5 `f054d9fe…`). Movido S/ 2.092.254 y US$ 54.971 de nuevo → upgrade; total por moneda igual (S/ 7.803.152,21 · US$ 440.135,63); conversión igual (129,35/1.655); Ranking por origen sin cambios; 12 filas de motivo y 12 del libro. Tarjeta de rentabilidad: cedido S/ 366.805 → 260.920 y US$ 8.335 → 8.057, ceden 156 → 147, sin_regla 4 → 16, contratos 261 → 263 (2 vuelven a la ventana de 30 días). Falta: oráculo, tipos, ledger «aplicada» y fusionar #230.
  - 🔑 Lección (gate de realidad): el banco tenía UNA Gerencia con el mismo nombre que el perfil de pruebas; producción tiene 3 y ninguna con ese nombre. La identidad de un guion se fija con Miguel, no se adivina por nombre.
  - ✅ **08/10 23:49 — oráculo PASS** (los 12 upgrade/upgrade, PDF intacto, capital por moneda y por analista como lo esperado, conversión igual, deriva vacía, septiembre abierto). Tipos regenerados (solo la puerta nueva) y ledger «aplicada» → **PR #230 fusionada por Miguel el 09/10 (`a3b89cc4`)**; `main` local al día. ⏳ Queda: decidir si se cierra el contrato SIN ficha de cartera → upgrade/renovación por «Corregir».
  - ✅ **09/10 12:17 — Miguel decide CERRAR el hueco inverso** («ok sí claro hay que cerrarlo», tras la explicación comercial): un contrato SIN operación de cartera solo puede quedar como nuevo (toda vía); pasar a nuevo/NULL sí. Medido en prod: los 106 sin operación con upgrade/renovación son de mar–jul y no cambian; huella de la guarda `8fdd5f1a…`. Migración `20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql` en construcción en el banco (rama `crm/categoria-sin-operacion-solo-nuevo`).
  - 🔨 **09/10 13:59 — «sin operación → solo nuevo» construida y probada en el banco** (migración `20261009180000`, md5 `9ac4dc87…`, PR #236, commit `3f110c5f`): prueba nueva 64/64 + 3/3, prueba de #230 83/83 + 6/6, concurrencia 9/9, mutantes 9/9 y 23/23, transporte 8/8, gate sin rojos nuevos. Codex r1 en curso. 🔑 Lección: una defensa DUPLICADA con el mismo texto (la guarda nueva rechaza lo mismo que el núcleo) deja ciega la prueba de la capa vieja — el mutante «núcleo sin respaldo» sobrevivía; se arregló probando que la puerta rechaza ANTES del UPDATE (R6/R7). Pendiente aparte: el CRM muestra este 23514 como «No se pudo guardar el cambio.» (traducirlo en `crm-api.ts`).
  - **09/10 14:01 — Codex r1 (sin operación → solo nuevo): BLOCK sin P0/P1.** Q3 correcta (NULL/nuevo pasan, upgrade/renovación rechazan; 25001 primero), Q2 sin vía que esquive la guarda, Q6 aceptable (3b NOT RUN con el puente legacy cerrado). Q1 pedía 3 cuerpos: los revisé en el volcado — `trg_restaurar_operacion_antes_borrar_contrato` solo toca estado/renovado_a_id/cerrado_* del origen, `definir_periodo_comercial_contrato` fecha/fuente del cierre, `proteger_campos_inmutables` no toca la categoría ⇒ cerrado. Aceptados: P2 (el candado de SESIÓN no se suelta si la aplicación falla dentro del mensaje: pasar a `pg_advisory_xact_lock` porque la migración es READ COMMITTED) y P3 (prueba b: bloquear y revalidar el candidato antes de medir). En curso en el banco.
  - ✅ **09/10 15:18 — «sin operación → solo nuevo» APLICADA EN PRODUCCIÓN y registrada** (`20261009180000`, md5 `04d57954…`, tras Codex r1: candado de TRANSACCIÓN `pg_advisory_xact_lock` —el de sesión quedaba tomado si la aplicación fallaba a mitad— y prueba b con `for update skip locked` + revalidación). Verificado: guarda nueva `b8f9c14e…`, ACL y trigger intactos, 0 candados. PR #236 (`71de1100`) al día con main, falta que Miguel la fusione. 🔑 Para migraciones en READ COMMITTED, el candado de exclusión va como `pg_advisory_xact_lock` dentro de la transacción.
  - Orden para Miguel (`!`, desde el worktree): migración → registrador → 1-ENSAYO (mirar tarjeta de rentabilidad y Ranking) → 2-REAL → oráculo PASS → `gen:types` y fusionar #230. Antes del 11/10 09:20.

# Facturación · Fase 0 — Categoría de 12 contratos: corregir y prevenir (PLAN CORTO)

Solo lectura; nada tocado. El worktree `facturacion-fase1-20261008` se borró a mitad (PR #229 fusionada): leí `main`
`faa65d1c`, cuyas migraciones son idénticas (`git diff 0d9f8f3b faa65d1c -- CRM-Avance-Corp/supabase` vacío).
Rutas `AAAAMMDD…:línea` = `supabase/migrations/`. **LEVEL 3** (datos de `public.contratos` y dinero de Metas).
Medición previa: `sql-fase0/medir-categoria.sql` (R0–R7).

## 1. Qué se cambia
- **Datos:** los 12 pasan de `categoria='nuevo'` a `'upgrade'` (8 en soles, S/ 2.092.254; 4 en dólares, US$ 54.971),
  con una puerta auditada, **antes de sellar septiembre**.
- **Prevención:** la categoría de un contrato no podrá quedar distinta de su operación de cartera, venga de donde venga.

## 2. Por qué pasó
- **El alta está bien:** `public.crear_contrato` escribe la misma `v_categoria` en el contrato y en la operación
  (`20260908211349:3287, :3475, :3519`); todos los escritores de `crm.operaciones_cartera` son versiones de esa función.
- **El error entra al CORREGIR:** `public.actualizar_contrato` (`20260821222348:521`) y `public.actualizar_numero_contrato`
  (`:647`) cambian la categoría sin mirar la operación. Llegan desde «Corregir» del CRM (`contrato-corregir.tsx:268`:
  elegir una condición de producto **pisa** la categoría; `:523-536`) y desde el portal (`public_html/js/admin/contratos.js:1403-1414, :1489-1490`).
- **El cinturón solo mira el alta:** `trg_contratos_operacion_cartera_commit` es `after insert` (`20260824231133:447-450`).
  Por eso la guarda va en el UPDATE de `public.contratos`: un trigger en `crm.operaciones_cartera` no vería nada.
- Hipótesis: nacieron 'upgrade' y alguien los corrigió a 'nuevo'. **R6** lo confirma (con qué nacieron, quién, cuándo).

## 3. Riesgos
| Tema | Respuesta | Evidencia |
|---|---|---|
| PDF | **No cambia el documento.** La categoría solo se valida en el snapshot; no llega a la plantilla ni al anexo. La integridad compara trabajo↔archivo, no el contrato vivo: no se rompe ningún sello. | `renderer.ts:263`, `:454-483`, `:576-607`; `template-v2.ts` y `anexo-v1.ts` no la nombran; `20260831055000:1420-1440` |
| Congelación | **Sí bloquea (55000)** si el contrato ya tiene PDF (R1 `congelado`): `categoria` está en los términos congelados. Las dos puertas que hoy la cambian abren con un GUC y **crean revisión** (PDF nuevo de un contrato firmado, sin cambio visible). | `20260818200741:133-153`, `:577-592`; revisión `:499`, `:541` |
| Tasas | **No aborta**, ni en observación ni en enforcement: al cambiar la categoría re-resuelve; el upgrade no guarda origen (CHECK) → `sin_regla` con base = su tasa → la tasa no entra en juego. Deja 1 fila más en `crm.ledger_rentabilidad`. P0411 solo en INSERT. La puerta **no** debe declarar origen (con origen: P0410 si la tasa difiere). | `20260918210543:386, :426-440, :459-466, :478-498`; `20261007180108:48-51`; `20260908165706:84`; `20260824231133:120-125` |
| Producto | Snapshot legacy: crea otro (exige `permite_altas_legacy`). Condición de catálogo: **falla 23514**. | `20260807203751:1451, :1490-1498`; `20260807235933:596-600` → R1 |
| Conversión | El cierre del lead no cambia (ya excluido por tener operación) y `elegible_conversion` no se recalcula. La operación sigue sumando, pero **cambia de dueño** donde el analista del contrato ≠ dueño del cliente: con 'upgrade' la cadena devuelve el analista (regla ATR-1, 30/08). | `20260927073637:158-170`; `20260908211349:3504-3512`; `20261007160937:263-286`; `20260830223000:150-178, :383-392` → R4 |
| Metas sep. | El capital pasa de «nuevo» a «upgrade» del **mismo** analista y moneda. Estimado (lista fase 0): Marzano S/1.116.900 · Merlys García S/577.554 · Fuenmayor S/150.000 (3) · Centenaro S/100.000 + US$1.400 · Núñez S/97.800 + US$53.571 (3) · Condori S/50.000. Facturación, Ranking, Gráficas y Resumen se mueven igual. | `20260908211349:899`; `20260901180000:254-259`; objetivos `20260807203757:51-61`; sello `20261007203000:2293-2327` → R2, R3 |
| Sellado | Septiembre abierto. Se puede sellar desde **11/10 00:00 Lima**, en orden (agosto antes) y el cron estaba pausado (vault 26/09). Sellado ⇒ no se reescribe. | `20260927073637:25-38, :1029-1035`; `20261007203000:1891, :1943, :1954` → R0 |
| Renovado / adicional | **Quedan vacíos:** el CHECK los exige NULL en upgrade y el alta solo los llena en renovación. El capital del upgrade es el contrato entero; no hay nada que rellenar. | `20260824231133:120-125`; `20260908211349:3521-3522` |
| Auditoría | `trg_audit_contratos` ya guarda el UPDATE con antes/después; el motivo va en fila hermana. | `20260829180000:34-36`; `20260927073637:769-786` |

## 4. Diseño
**Puerta** `crm.corregir_categoria_contrato_fn(p_contrato_id uuid, p_categoria text, p_motivo text) returns jsonb`. Molde:
`crm.corregir_fecha_cierre_comercial` (`20260927073637:670-795`); no se reutilizan las v3 (sin motivo, sin sello, sin respaldo, con revisión PDF).
1. Solo Gerencia CRM vigente (`:688`), membresía no revocada; motivo de 5 a 300 caracteres (`:700`).
2. Contrato `for update` (`:707`); si ya tiene esa categoría → `{cambio:false}` y no escribe nada.
3. Candado con las llaves del sello (`:729-735`); mes sellado → P0409 (`:744`).
4. **Respaldo:** con operación, `p_categoria` = `o.tipo`; sin operación, solo 'nuevo'; si no → 23514.
5. Vacía `crm.rentabilidad_origen_upgrade`; abre la congelación solo para ese id (GUC de `20260818200741:529-539`);
   **UPDATE solo de `categoria`**; cierra el GUC (también si falla). **Sin revisión de PDF.**
6. Fila hermana en `public.audit_log` (`tabla='contratos.categoria'`: antes, después, motivo, id de la operación).
`security definer` justificado (escribe `public.contratos` y la auditoría, que el rol no puede), `search_path=''`, nombres
calificados, rol verificado dentro; `revoke` a public/anon, `grant` a authenticated; `COMMENT ON`.

**Prevención (toda vía):** `private.trg_contrato_categoria_por_operacion()` + `trg_contratos_01_categoria_por_operacion`
**BEFORE UPDATE OF categoria ON public.contratos**: solo si la categoría CAMBIA, exige que case con su operación (o 'nuevo'
sin operación) y que el mes no esté sellado; si no, 23514 «La categoría la decide la operación de cartera». No toca el alta
ni el cinturón de INSERT; corregir otra cosa sigue pasando; lo que hoy cambia la categoría en silencio (p. ej. elegir una
condición de catálogo en «Corregir») recibirá ese error. **Pantalla (después, no bloquea):** en «Corregir» del CRM
(`contrato-corregir.tsx:268, :523-536`) y del portal, la categoría queda de solo lectura con ese texto.

## 5. Migración, orden y reversa
- `AAAAMMDDHHMMSS_crm_categoria_contrato_por_operacion.sql`: puerta + trigger + grants + comentarios, preflight con las
  huellas md5 de R7 y postflight; `MIGRACIONES.md`; `npm run gen:types`.
- **Orden:** 1) Miguel corre `medir-categoria.sql` (`!`). 2) Banco Docker a paridad con fixtures en el estado de producción
  (contrato 'nuevo' + operación upgrade + PDF sellado + snapshot legacy) → gate A/B → advisors → `auditor-rls` → Codex
  (`scripts/codex-review-mcp`) → Miguel aplica con `!`. 3) Los 12 por guion con la identidad de Miguel: ENSAYO (`DO` que
  termina en `raise`) y REAL (una transacción + postflight). 4) Pantalla.
- **Reversa** (solo con septiembre abierto): esquema = `drop trigger` + `drop function` ×2; datos = guion inverso
  (12 → 'nuevo', motivo «reversa») tras retirar el trigger. Libro y auditoría no se borran.

## 6. Pruebas
- **Gate `test-rls.mjs`** antes y después, más: anon/vendedor/supervisor/coordinador → 42501 y Gerencia sí; motivo; mes
  sellado → P0409; sin respaldo → 23514; idempotencia; PDF sigue `sellado` con 0 trabajos nuevos; sin P0410 en observación
  **y** en enforcement; dos filas de auditoría. Prevención: «Corregir» 'upgrade'→'nuevo' con operación y 'nuevo'→'upgrade'
  sin ella → 23514; corregir otra cosa → pasa; alta de upgrade y de renovación → pasan.
- **Oráculo SQL** (septiembre, por analista y moneda): Δnuevo = −Δupgrade = los 12; total por moneda igual; número de
  operaciones de conversión igual (solo cambia el dueño que diga R4).
- **Mutantes** (cada uno debe tumbar una prueba): sin rechazo de sellado · sin respaldo · sin rol · trigger sin efecto ·
  GUC sin cerrar · sin fila de motivo.

## 7. Qué decide Miguel
1. **OK para tocar `public`:** 12 UPDATE en `public.contratos`, 1 trigger en esa tabla y filas en `public.audit_log`.
2. ¿Quién usa la puerta: solo Gerencia (recomendado) o también admin/superadmin?
3. **Conversión:** que cada upgrade cuente al analista del contrato (ATR-1) donde hoy cuenta al dueño (lista de R4).
4. Si R1 muestra condiciones de catálogo o el legacy cerrado: esos contratos quedan fuera y se deciden aparte.
5. Aplicar antes del **11/10** y no sellar agosto ni septiembre hasta verificar con el oráculo.


## Anexo — medir-categoria.sql (solo lectura, sin probar todavía)

```sql
-- medir-categoria.sql — Facturación fase 0 · los 12 contratos «nuevo» que son upgrade. SOLO LECTURA.
--
-- PARA QUÉ: antes de escribir la puerta y la prevención, medir en PRODUCCIÓN qué
-- se mueve si los 12 pasan de 'nuevo' a 'upgrade'. Lo principal es R2: Metas de
-- septiembre por analista y moneda. No escribe nada: lee y SIMULA el «después».
--
-- CÓMO LO CORRE MIGUEL (con `!`, desde CRM-Avance-Corp):
--   supabase db query --linked -f <ruta>/medir-categoria.sql --output-format json > medir-categoria.json
--
-- POR QUÉ ES SEGURO
--   · Transacción READ ONLY: cualquier escritura fallaría (25006). Termina en ROLLBACK.
--   · Solo llama funciones STABLE/IMMUTABLE: private.capital_episodios,
--     private.produccion_mes_por_vendedor, private.analista_atribuido_cadena,
--     private.contrato_documental_regimen/_congelado, private.cierre_mes_ventana_desde.
--   · El resultado viaja en un GUC LOCAL (set_config(..., true)): `db query --linked`
--     solo devuelve la última sentencia con filas y no trae NOTICE.
--   · Cada sección va en su propio subbloque: si una falla deja {"error": ...} y las demás siguen.
--   · OJO: la sintaxis NO se probó contra Postgres (quien la escribió no podía conectarse a
--     ninguna base). Pasarla primero por el banco Docker; en el banco los 12 no existen y
--     las secciones salen vacías, lo que solo prueba que compila.
--   · Las huellas md5 de R7 dependen del search_path de la sesión: correrla con el de siempre.
--
-- SECCIONES
--   R0_resumen        los 12 (encontrados, movibles, fuera de lo esperado), metas sep/ago,
--                     meses sellados, desde cuándo se puede sellar septiembre, política de
--                     rentabilidad (modo), si el producto legacy deja cambiar términos
--   R0_cron_sello     estado del job crm-cierre-mes-diario
--   R1_contratos      por contrato: operación, analista hoy / tras upgrade, PDF, producto
--   R2_metas_sep      ★ analista × moneda: «nuevo» y «upgrade» antes → después, objetivo y %
--   R3_capital_sep    núcleo de Facturación/Resumen/Gráficas por moneda, antes → después
--   R4_conversion     la operación de upgrade: ¿suma en el numerador? ¿a quién hoy y después?
--   R5_incoherencias  TODO el histórico: categoría distinta de su operación, por mes
--   R6_historia       con qué categoría nació cada uno, quién la cambió, libro de rentabilidad
--   R7_anclas         huellas md5 para el preflight + triggers vivos de public.contratos
--
-- Columnas y firmas verificadas contra las migraciones del repo (main faa65d1c):
--   public.contratos(id, numero_contrato, cliente_id, capital, moneda, tasa_anual, categoria, estado,
--     es_demo, creado_en, creado_por, analista_cierre_id, fecha_cierre_comercial date, producto_condicion_id)
--   crm.operaciones_cartera(id, cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
--     fecha_operacion, periodo, elegible_conversion, fuente, creado_en)          20260824231133:80-127
--   crm.meta_periodos / crm.metas_vendedor / crm.metas_vendedor_detalle           20260807203757:12-61
--   private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid) → vendedor_id, categoria, moneda,
--     contratos_real, capital_real                                               20260901180000:232
--   private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])             20260908211349:887 (tipo :899)
--   public.audit_log(tabla, operacion, fila_id TEXT, usuario_id, ts, data_antes, data_despues)
--   crm.ledger_rentabilidad(contrato_id, secuencia, categoria, regla, origen, contrato_origen_id,
--     tasa_base, tasa_final, registrado_en, detalle)                             20260906170000:778-797
--   crm.politica_rentabilidad(version, modo, vigente_desde)                       20260906170000:121-136

begin transaction read only;
set local statement_timeout = '180s';
set local lock_timeout = '5s';

do $medir$
declare
  v_res            jsonb := '{}'::jsonb;
  v_tmp            jsonb;
  v_periodo        constant date := date '2026-09-01';
  v_ini            constant timestamptz := timestamp '2026-09-01 00:00:00' at time zone 'America/Lima';
  v_fin            constant timestamptz := timestamp '2026-10-01 00:00:00' at time zone 'America/Lima';
  v_numeros        constant text[] := array[
    '2026-01-001362', '2026-01-001369', '2026-01-001401', '2026-01-001408',
    '2026-01-001400', '2026-01-001439', '2026-01-001440', '2026-01-001441',
    '2026-01-001424', '2026-01-001425', '2026-01-001445', '2026-01-001447'];
  v_ids            uuid[] := '{}'::uuid[];
  v_periodo_id     uuid;
  v_revision       integer;
  v_legacy_abierto boolean;
begin
  -- ── Base: los MOVIBLES = siguen en 'nuevo', son el contrato nuevo de una operación
  --    'upgrade', no son demo y su día comercial es de septiembre. ──────────────────
  begin
    select coalesce(array_agg(c.id order by c.numero_contrato), '{}'::uuid[])
      into v_ids
      from public.contratos c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
     where c.numero_contrato = any(v_numeros)
       and coalesce(c.categoria, 'nuevo') = 'nuevo'
       and o.tipo = 'upgrade'
       and not c.es_demo
       and c.fecha_cierre_comercial >= v_periodo
       and c.fecha_cierre_comercial < date '2026-10-01';

    select mp.id, mp.revision into v_periodo_id, v_revision
      from crm.meta_periodos mp
     where mp.periodo = v_periodo
     order by mp.revision desc
     limit 1;

    select p.permite_altas_legacy into v_legacy_abierto
      from crm.productos_inversion p
     where p.codigo = 'HISTORICO-SIN-CATALOGO' and p.es_legacy;
  exception when others then
    v_res := v_res || jsonb_build_object('error_base', sqlstate || ': ' || sqlerrm);
  end;

  -- ── R0. Resumen ───────────────────────────────────────────────────────────────
  begin
    v_tmp := jsonb_build_object(
      'generado_en_lima', (now() at time zone 'America/Lima')::text,
      'numeros_pedidos', cardinality(v_numeros),
      'numeros_encontrados', (select count(*) from public.contratos c
                               where c.numero_contrato = any(v_numeros)),
      'movibles', cardinality(v_ids),
      'movibles_por_moneda', (
        select coalesce(jsonb_object_agg(t.moneda, jsonb_build_object('contratos', t.n, 'capital', t.cap)), '{}'::jsonb)
          from (select c.moneda, count(*) as n, sum(c.capital) as cap
                  from public.contratos c where c.id = any(v_ids) group by c.moneda) t),
      'fuera_de_lo_esperado', (
        select coalesce(jsonb_agg(c.numero_contrato order by c.numero_contrato), '[]'::jsonb)
          from public.contratos c
         where c.numero_contrato = any(v_numeros) and not (c.id = any(v_ids))),
      'metas_septiembre', case when v_periodo_id is null then null else jsonb_build_object(
          'revision', v_revision,
          'analistas', (select count(*) from crm.metas_vendedor mv where mv.meta_periodo_id = v_periodo_id)) end,
      'metas_agosto_publicadas', exists (select 1 from crm.meta_periodos mp where mp.periodo = date '2026-08-01'),
      'meses_sellados', (select coalesce(jsonb_agg(pc.periodo order by pc.periodo), '[]'::jsonb)
                           from crm.periodos_cerrados pc),
      'septiembre_se_puede_sellar_desde_lima',
        (private.cierre_mes_ventana_desde(v_periodo) at time zone 'America/Lima')::text,
      'politica_rentabilidad', (select jsonb_build_object('version', p.version, 'modo', p.modo)
                                  from crm.politica_rentabilidad p
                                 where p.vigente_desde <= now()
                                 order by p.vigente_desde desc
                                 limit 1),
      'legacy_permite_cambiar_terminos', v_legacy_abierto
    );
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R0_resumen', v_tmp);

  begin
    select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'horario_utc', j.schedule, 'activo', j.active)), '[]'::jsonb)
      into v_tmp
      from cron.job j
     where j.jobname = 'crm-cierre-mes-diario';
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R0_cron_sello', v_tmp);

  -- ── R1. Contrato por contrato ─────────────────────────────────────────────────
  --    analista_tras_upgrade: con categoria 'upgrade' la cadena adopta el PROPIO
  --    contrato (nivel 0) y devuelve su analista_cierre_id (20260830223000:150-178).
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'numero', c.numero_contrato,
             'dia', c.fecha_cierre_comercial,
             'moneda', c.moneda, 'capital', c.capital, 'tasa', c.tasa_anual,
             'categoria', c.categoria, 'estado', c.estado,
             'operacion', jsonb_build_object(
                 'tipo', o.tipo, 'fuente', o.fuente,
                 'con_contrato_origen', o.contrato_origen_id is not null,
                 'elegible_conversion', o.elegible_conversion,
                 'nacio_con_el_contrato', o.creado_en = c.creado_en,
                 'dueno_del_cliente', pv.nombre_completo),
             'analista_hoy', ph.nombre_completo,
             'analista_tras_upgrade', pa.nombre_completo,
             'capital_cambia_de_analista',
                 coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
                   is distinct from c.analista_cierre_id,
             'pdf', jsonb_build_object(
                 'regimen', private.contrato_documental_regimen(c.id),
                 'congelado', private.contrato_documental_congelado(c.id),
                 'ultimo_trabajo', (select jsonb_build_object('revision', j.revision, 'estado', j.estado)
                                      from private.contrato_pdf_jobs j
                                     where j.contrato_id = c.id
                                     order by j.revision desc
                                     limit 1),
                 'archivos', (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id)),
             'producto', jsonb_build_object(
                 'legacy', pc.es_legacy,
                 'categoria_condicion', pc.categoria,
                 -- Legacy: el trigger crea otro snapshot y exige permite_altas_legacy.
                 -- Catálogo: la condición es 'nuevo' y el trigger rechaza 'upgrade' (23514).
                 'pasaria_trigger_producto', case when pc.es_legacy then coalesce(v_legacy_abierto, false)
                                                  else false end)
           ) order by c.fecha_cierre_comercial, c.numero_contrato), '[]'::jsonb)
      into v_tmp
      from public.contratos c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
      left join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
      left join public.perfiles pv on pv.id = o.vendedor_id
      left join public.perfiles pa on pa.id = c.analista_cierre_id
      left join public.perfiles ph
        on ph.id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
     where c.id = any(v_ids);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R1_contratos', v_tmp);

  -- ── R2. ★ Metas de septiembre por analista y moneda ───────────────────────────
  --    «antes» = el núcleo de producción tal cual (el mismo que usa cerrar_periodo).
  --    «después» = antes − los 12 en «nuevo» + los 12 en «upgrade».
  --    Atribución: con analista, la producción usa coalesce(meta, analista) = el
  --    analista (20260902202247:131-132). Sin ajustes saldados (si R0 muestra meses sellados, revisar).
  --    'cuadra' = false si «nuevo después» saldría negativo: entonces la atribución
  --    no es la supuesta y la cifra NO se usa.
  begin
    with delta as (
      select coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as v_antes,
             c.analista_cierre_id as v_despues,
             c.moneda, c.capital
        from public.contratos c
       where c.id = any(v_ids)
    ), mov as (
      select d.v_antes as vendedor_id, d.moneda,
             -sum(d.capital) as d_nuevo, -(count(*)::int) as n_nuevo,
             0::numeric as d_upgrade, 0 as n_upgrade
        from delta d group by d.v_antes, d.moneda
      union all
      select d.v_despues, d.moneda, 0::numeric, 0, sum(d.capital), count(*)::int
        from delta d group by d.v_despues, d.moneda
    ), d2 as (
      select m.vendedor_id, m.moneda,
             sum(m.d_nuevo) as d_nuevo, sum(m.n_nuevo)::int as n_nuevo,
             sum(m.d_upgrade) as d_upgrade, sum(m.n_upgrade)::int as n_upgrade
        from mov m group by m.vendedor_id, m.moneda
    ), prod as (
      select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
        from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
    ), obj as (
      select mv.vendedor_id, dt.categoria, dt.moneda, dt.capital_objetivo, dt.contratos_objetivo
        from crm.metas_vendedor mv
        join crm.metas_vendedor_detalle dt on dt.meta_vendedor_id = mv.id
       where mv.meta_periodo_id = v_periodo_id
    )
    select jsonb_build_object(
      'meta_revision', v_revision,
      'por_analista', coalesce(jsonb_agg(jsonb_build_object(
          'analista', coalesce(pf.nombre_completo, '(sin analista)'),
          'en_metas_sep', exists (select 1 from crm.metas_vendedor mv
                                   where mv.meta_periodo_id = v_periodo_id
                                     and mv.vendedor_id = d2.vendedor_id),
          'moneda', d2.moneda,
          'nuevo', jsonb_build_object(
              'objetivo', obn.capital_objetivo,
              'antes', coalesce(pn.capital_real, 0),
              'despues', coalesce(pn.capital_real, 0) + d2.d_nuevo,
              'contratos_antes', coalesce(pn.contratos_real, 0),
              'contratos_despues', coalesce(pn.contratos_real, 0) + d2.n_nuevo,
              'pct_antes', case when obn.capital_objetivo > 0
                 then round(100.0 * coalesce(pn.capital_real, 0) / obn.capital_objetivo, 2) end,
              'pct_despues', case when obn.capital_objetivo > 0
                 then round(100.0 * (coalesce(pn.capital_real, 0) + d2.d_nuevo) / obn.capital_objetivo, 2) end),
          'upgrade', jsonb_build_object(
              'objetivo', obu.capital_objetivo,
              'antes', coalesce(pu.capital_real, 0),
              'despues', coalesce(pu.capital_real, 0) + d2.d_upgrade,
              'contratos_antes', coalesce(pu.contratos_real, 0),
              'contratos_despues', coalesce(pu.contratos_real, 0) + d2.n_upgrade,
              'pct_antes', case when obu.capital_objetivo > 0
                 then round(100.0 * coalesce(pu.capital_real, 0) / obu.capital_objetivo, 2) end,
              'pct_despues', case when obu.capital_objetivo > 0
                 then round(100.0 * (coalesce(pu.capital_real, 0) + d2.d_upgrade) / obu.capital_objetivo, 2) end),
          'cuadra', coalesce(pn.capital_real, 0) + d2.d_nuevo >= 0
        ) order by d2.moneda, pf.nombre_completo), '[]'::jsonb))
      into v_tmp
      from d2
      left join public.perfiles pf on pf.id = d2.vendedor_id
      left join prod pn on pn.vendedor_id is not distinct from d2.vendedor_id
                       and pn.moneda = d2.moneda and pn.categoria = 'nuevo'
      left join prod pu on pu.vendedor_id is not distinct from d2.vendedor_id
                       and pu.moneda = d2.moneda and pu.categoria = 'upgrade'
      left join obj obn on obn.vendedor_id = d2.vendedor_id
                       and obn.moneda = d2.moneda and obn.categoria = 'nuevo'
      left join obj obu on obu.vendedor_id = d2.vendedor_id
                       and obu.moneda = d2.moneda and obu.categoria = 'upgrade';
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R2_metas_sep', v_tmp);

  -- ── R3. Capital de septiembre en el núcleo (Facturación, Resumen, Gráficas) ───
  begin
    select coalesce(jsonb_object_agg(t.moneda, jsonb_build_object(
             'contrato_nuevo_antes', t.nuevo,
             'contrato_nuevo_despues', t.nuevo - t.mov,
             'contrato_upgrade_antes', t.up,
             'contrato_upgrade_despues', t.up + t.mov,
             'total_stock_no_cambia', t.total)), '{}'::jsonb)
      into v_tmp
      from (select e.moneda,
                   coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'), 0) as nuevo,
                   coalesce(sum(e.monto) filter (where e.tipo = 'contrato_upgrade'), 0) as up,
                   coalesce(sum(e.monto) filter (where e.tipo = 'contrato_nuevo'
                                                   and e.contrato_id = any(v_ids)), 0) as mov,
                   coalesce(sum(e.monto), 0) as total
              from private.capital_episodios(v_ini, v_fin, true, '{}'::uuid[]) e
             where e.medida = 'stock'
             group by e.moneda) t;
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R3_capital_sep', v_tmp);

  -- ── R4. Conversión: la operación de upgrade ───────────────────────────────────
  --    Suma en el numerador si es elegible y es la PRIMERA elegible del cliente en
  --    el mes (20261007160937:263-286). Hoy cuenta a coalesce(cadena, dueño); con
  --    'upgrade' la cadena devuelve el analista del contrato (ATR-1).
  begin
    with ops as (
      select o.id,
             row_number() over (partition by o.cliente_id, o.periodo
                                order by o.fecha_operacion, o.creado_en, o.id) as orden
        from crm.operaciones_cartera o
       where o.elegible_conversion and o.periodo = v_periodo
    ), filas as (
      select c.numero_contrato, o.elegible_conversion,
             coalesce(oo.orden = 1, false) as cuenta,
             coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) as hoy,
             coalesce(c.analista_cierre_id, o.vendedor_id) as despues
        from crm.operaciones_cartera o
        join public.contratos c on c.id = o.contrato_nuevo_id
        left join ops oo on oo.id = o.id
       where o.contrato_nuevo_id = any(v_ids)
    )
    select jsonb_build_object(
      'filas', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'numero', f.numero_contrato,
                 'elegible', f.elegible_conversion,
                 'suma_en_numerador', f.cuenta,
                 'hoy_cuenta_a', p1.nombre_completo,
                 'despues_contaria_a', p2.nombre_completo,
                 'cambia_de_persona', f.hoy is distinct from f.despues) order by f.numero_contrato)
          from filas f
          left join public.perfiles p1 on p1.id = f.hoy
          left join public.perfiles p2 on p2.id = f.despues), '[]'::jsonb),
      'movimientos_por_persona', coalesce((
        select jsonb_agg(jsonb_build_object('persona', x.nombre, 'conversiones', x.delta) order by x.nombre)
          from (select coalesce(p.nombre_completo, '(sin nombre)') as nombre, sum(m.delta) as delta
                  from (select f.hoy as persona, -1 as delta from filas f
                         where f.cuenta and f.hoy is distinct from f.despues
                        union all
                        select f.despues, 1 from filas f
                         where f.cuenta and f.hoy is distinct from f.despues) m
                  left join public.perfiles p on p.id = m.persona
                 group by coalesce(p.nombre_completo, '(sin nombre)')) x), '[]'::jsonb)
    ) into v_tmp;
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R4_conversion', v_tmp);

  -- ── R5. Incoherencias en TODO el histórico (dimensiona la prevención) ─────────
  begin
    select jsonb_build_object(
      'categoria_distinta_de_su_operacion', coalesce((
        select jsonb_agg(jsonb_build_object('mes', t.mes, 'categoria', t.cat, 'operacion', t.tipo,
                                            'moneda', t.moneda, 'contratos', t.n, 'capital', t.cap)
                         order by t.mes, t.cat, t.tipo, t.moneda)
          from (select to_char(date_trunc('month', c.fecha_cierre_comercial), 'YYYY-MM') as mes,
                       coalesce(c.categoria, '(nula)') as cat, o.tipo, c.moneda,
                       count(*) as n, sum(c.capital) as cap
                  from public.contratos c
                  join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
                 where coalesce(c.categoria, 'nuevo') <> o.tipo and not c.es_demo
                 group by 1, 2, 3, 4) t), '[]'::jsonb),
      'renovacion_o_upgrade_sin_operacion', coalesce((
        select jsonb_agg(jsonb_build_object('mes', t.mes, 'categoria', t.cat, 'contratos', t.n)
                         order by t.mes, t.cat)
          from (select to_char(date_trunc('month', c.fecha_cierre_comercial), 'YYYY-MM') as mes,
                       c.categoria as cat, count(*) as n
                  from public.contratos c
                 where c.categoria in ('renovacion', 'upgrade') and not c.es_demo
                   and not exists (select 1 from crm.operaciones_cartera o
                                    where o.contrato_nuevo_id = c.id)
                 group by 1, 2) t), '[]'::jsonb)
    ) into v_tmp;
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R5_incoherencias', v_tmp);

  -- ── R6. Historia: con qué nació, quién cambió la categoría, libro de rentabilidad ─
  --    fila_id es TEXT en producción (la medida del 08/10 falló con 42883 al compararlo con uuid).
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'numero', c.numero_contrato,
             'nacio_como', (select al.data_despues ->> 'categoria'
                              from public.audit_log al
                             where al.tabla in ('contratos', 'public.contratos')
                               and al.fila_id = c.id::text and al.operacion = 'INSERT'
                             order by al.ts limit 1),
             'cambios_de_categoria', coalesce((
                select jsonb_agg(jsonb_build_object(
                         'cuando_lima', (al.ts at time zone 'America/Lima')::text,
                         'quien', pq.nombre_completo,
                         'de', al.data_antes ->> 'categoria',
                         'a', al.data_despues ->> 'categoria') order by al.ts)
                  from public.audit_log al
                  left join public.perfiles pq on pq.id = al.usuario_id
                 where al.tabla in ('contratos', 'public.contratos')
                   and al.fila_id = c.id::text and al.operacion = 'UPDATE'
                   and (al.data_antes ->> 'categoria') is distinct from (al.data_despues ->> 'categoria')),
                '[]'::jsonb),
             'libro_rentabilidad', coalesce((
                select jsonb_agg(jsonb_build_object(
                         'secuencia', l.secuencia,
                         'cuando_lima', (l.registrado_en at time zone 'America/Lima')::text,
                         'categoria', l.categoria, 'regla', l.regla, 'origen', l.origen,
                         'con_contrato_origen', l.contrato_origen_id is not null,
                         'tasa_base', l.tasa_base, 'tasa_final', l.tasa_final,
                         'motivo', l.detalle ->> 'motivo') order by l.secuencia)
                  from crm.ledger_rentabilidad l
                 where l.contrato_id = c.id), '[]'::jsonb)
           ) order by c.numero_contrato), '[]'::jsonb)
      into v_tmp
      from public.contratos c
     where c.numero_contrato = any(v_numeros);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R6_historia', v_tmp);

  -- ── R7. Anclas para el preflight de la migración ──────────────────────────────
  begin
    select jsonb_build_object(
      'huellas_md5', (
        select jsonb_object_agg(f.firma,
                 case when to_regprocedure(f.firma) is null then null
                      else md5(pg_get_functiondef(to_regprocedure(f.firma))) end)
          from unnest(array[
                 'private.trg_contratos_observar_rentabilidad()',
                 'private.proteger_contrato_documental()',
                 'private.mutacion_documental_autorizada(uuid)',
                 'private.trg_contratos_producto_snapshot()',
                 'private.trg_contrato_exige_operacion_cartera()',
                 'private.rentabilidad_origen_declarado(public.contratos)',
                 'private.analista_atribuido_cadena(uuid)',
                 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])',
                 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)',
                 'crm.corregir_fecha_cierre_comercial(uuid,date,text)',
                 'public.actualizar_contrato(uuid,jsonb,jsonb)',
                 'public.actualizar_numero_contrato(uuid,text,text,text)']) as f(firma)),
      'observador_con_upgrade_flexible', position($t$v_c.categoria in ('nuevo','upgrade')$t$ in
          pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure)) > 0,
      'observador_con_correccion_admin_tasa', position('crm.tasa_admin_contrato_id' in
          pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure)) > 0,
      'nombre_libre_puerta', to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is null,
      'triggers_public_contratos', (
        select jsonb_agg(jsonb_build_object('nombre', t.tgname, 'activo', t.tgenabled <> 'D',
                                            'def', pg_get_triggerdef(t.oid)) order by t.tgname)
          from pg_trigger t
         where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
    ) into v_tmp;
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R7_anclas', v_tmp);

  perform set_config('medir.categoria', v_res::text, true);
end
$medir$;

select current_setting('medir.categoria', true)::jsonb as resultado;

rollback;
```
