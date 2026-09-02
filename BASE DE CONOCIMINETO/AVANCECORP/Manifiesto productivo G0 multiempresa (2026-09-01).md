---
tags: [crm, multiempresa, g0, manifiesto, capital, supabase, solo-lectura]
fecha: 2026-09-01
estado: r3-oraculo-de-borde-observacion-clasificada-requiere-correccion-no-firmado
serial_origen: AVC-MULTIEMPRESA-G0-20260902-R3
serial_anterior: AVC-MULTIEMPRESA-G0-20260901-R2
proyecto_supabase: dctqcbznekcyxhjujuci
capturado_en_utc: 2026-09-02T04:32:13Z
r3_ejecutado_en_utc: 2026-09-02T05:00:00Z
---

# Manifiesto productivo G0 — cliente multiempresa

## Historial de capturas

| Serial | Migraciones | Capturado (UTC) | Resultado |
|---|---:|---|---|
| R1 | 196 | 2026-09-02T01:36:25Z | Núcleo y oráculos en paridad; quedó obsoleta al publicarse 197–198 |
| R2 | 198 | 2026-09-02T04:32:13Z | Recaptura completa contra 197–198: cero deriva respecto a R1 |
| **R3 (esta)** | **198** (verificado: misma huella `fc46855522…`) | 2026-09-02T05:00Z | **Oráculo de borde UTC/Lima: la observación temporal queda CLASIFICADA — no es aceptable sin corrección** |

R2 repite toda la batería de R1 (migraciones, núcleo, resolutor, consumidores,
fuentes, ACL, guardianes, Capital mensual, AUM, núcleo completo y ATR-4) en
transacciones `READ ONLY` contra producción, ya con los registros 197 y 198
aplicados. Todas las huellas funcionales de R1 se reproducen al byte.

## Qué cambió entre R1 y R2 (registros 197–198)

- `20260902040000` — `crm_lector_global_no_ve_borrados`
- `20260902050000` — `crm_lector_global_definers`

Objetos que tocan, medidos en producción:

| Objeto | Tipo | `md5` |
|---|---|---|
| `crm.leads :: leads_select` | policy SELECT (qual\|with_check) | `f5ed5c4cba969c38a4dc1d5439043225` |
| `crm.actividades :: actividades_select` | policy SELECT | `d90886ec53fe55e6f4465effae656233` |
| `crm.tareas :: tareas_select` | policy SELECT | `f5ed5c4cba969c38a4dc1d5439043225` |
| `crm.actividades_del_ambito_fn()` | función DEFINER | `c2f9a322da2cfced6eb1b8818caa25d3` (prosrc) |
| `crm.cierres_estado_fn(uuid[])` | función DEFINER | `bcaf7f545ac80f302008d629ea13f8af` (prosrc) |

**Ninguno pertenece al núcleo de Capital ni a sus 17 consumidores.** Son
políticas de lectura y dos puertas DEFINER del lector global (Directorio); no
alteran columnas, constraints ni índices de las seis fuentes. El núcleo se
recapturó igualmente porque la regla es medir, no suponer.

## Veredicto

El núcleo de Capital y su resolutor de atribución coinciden exactamente con las
huellas de referencia de [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]]
y con la captura R1:

- `private.capital_episodios`: sin deriva de firma, cuerpo, ACL ni atributos;
- `private.analista_atribuido_cadena`: una sola sobrecarga, cuerpo y ACL intactos;
- 17 consumidores: `md5(prosrc)` idéntico a R1, sin consumidores nuevos ni vistas;
- Capital mensual: paridad exacta (41 filas, cero diferencias, misma huella que R1);
- AUM: paridad JSON exacta por moneda;
- núcleo completo: 513 episodios, misma huella que R1;
- guardianes de analítica y vigencia: verdes;
- ATR-4: la única anulación externa sigue siendo la demo declarada y no reaparece
  como dinero.

**G0 queda capturado contra el estado 198, pero todavía no firmado.** Sigue
abierta la observación temporal (ver más abajo): `crm.metricas_capital_mes_fn`
y `crm.metricas_vencimientos_fn` derivan su ventana de `current_date` en UTC.
R2 añade un oráculo con reloj de Lima que hoy tampoco difiere, pero esa
igualdad no demuestra el borde de fin de mes. **R3 (más abajo) sí lo demuestra:
la salida 1 queda refutada y se necesita la salida 2 (corrección autorizada).**

Esta nota no autoriza F1, migraciones, backfill, escritura en Supabase, despliegue
ni piloto.

## Seguridad de la captura

- Proyecto consultado: `PortalAvanceCorp`, ref `dctqcbznekcyxhjujuci`, región
  `us-east-2`, estado `ACTIVE_HEALTHY`.
- Motor informado por Supabase: PostgreSQL `17.6.1.105`; el servidor respondió
  `PostgreSQL 17.6 on aarch64-unknown-linux-gnu`.
- Base `postgres`, rol de catálogo `postgres`, vía MCP `execute_sql`.
- Cada lote se ejecutó como `begin read only; …; commit;` y devolvió
  `current_setting('transaction_read_only') = 'on'` en la propia fila de resultado.
- No se ejecutó DDL, DML, migración, backfill, función de escritura ni prueba
  destructiva. No se cambió de rol de sesión (regla del taller: `select fn()` sin EXECUTE segfaultea el backend,
  así que jamás `set role authenticated` contra funciones sin EXECUTE).
- Para las lentes autorizadas se instalaron claims locales
  (`set_config('request.jwt.claims', …, true)`) de una cuenta activa que reúne
  Gerencia CRM y Superadmin Portal; la transacción verificó
  `es_gerencia_crm_activa() = true` y `es_superadmin_portal_activo() = true`.
  El ajuste vivió únicamente dentro de la transacción de solo lectura.

## Migraciones aplicadas

Normalización: `version|name`, una fila por línea, orden ascendente por `version`;
huella `md5` sobre el texto completo.

| Dato | R1 | **R2** |
|---|---|---|
| Cantidad | `196` | **`198`** |
| Primera | `20260708000000` | `20260708000000` |
| Última | `20260901200000` | **`20260902050000`** |
| Huella versión + nombre | `dff571b380d41ecc3707857c6283ce1a` | **`fc46855522d1d114deda4a27a222f046`** |
| ATR-2 `20260830233000` | presente | presente |
| ATR-4 `20260901180000` | presente | presente |
| 197 `20260902040000` | — | presente |
| 198 `20260902050000` | — | presente |

Cola productiva desde ATR-1:

1. `20260830223000` — `crm_atr_1_upgrade_cuenta_a_quien_lo_hace`
2. `20260830233000` — `crm_atr_2_capital_por_cadena_de_upgrade`
3. `20260831010000` — `crm_atr_3a_lentes_y_ficha_al_analista`
4. `20260831020000` — `crm_f7_0_el_gate_que_vigila_las_puertas`
5. `20260831055000` — `crm_ola_r_las_doce_actas_mudas`
6. `20260831060000` — `crm_f7_1_cerrar_lo_que_quedo_suelto`
7. `20260901180000` — `crm_atr_4_sancion_de_anular_solo_conversion`
8. `20260901185600` — `habilitar_landing_formulario_alta_manual`
9. `20260901191947` — `crm_contrato_pdf_plantilla_v7_plazo_fin_mes`
10. `20260901200000` — `crm_f7_2_cerrar_el_interruptor_legacy`
11. `20260902040000` — `crm_lector_global_no_ve_borrados` *(nuevo en R2)*
12. `20260902050000` — `crm_lector_global_definers` *(nuevo en R2)*

## Núcleo protegido

Normalización de funciones: ninguna. Se calcularon por separado
`md5(pg_get_functiondef(oid))` y `md5(pg_proc.prosrc)` directamente en producción.

### `private.capital_episodios`

- Firma única:
  `private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])`.
- Argumentos observados:
  `p_ini timestamptz, p_fin timestamptz, p_global boolean, p_visibles uuid[]`.
- Resultado observado: 17 columnas:
  `tipo`, `medida`, `contrato_id`, `cierre_externo_id`, `lead_id`, `cliente_id`,
  `analista_id`, `registrado_por`, `en_roster`, `moneda`, `monto`, `categoria`,
  `mes_comercial`, `fecha`, `fecha_vencimiento`, `estado`, `anulado`.
- Lenguaje/atributos: SQL, `STABLE`, `SECURITY DEFINER`, `search_path=""`.
- Propietario: `postgres`. ACL: `{postgres=X/postgres}`.
- `md5(pg_get_functiondef)`: `b8f375fbb377582835f4cfe222240c5b`.
- `md5(prosrc)`: `38c99b1bd6e8ae0bc8bb0f93d5487ce8`.
- Comparación con el plan y con R1: **coincidencia exacta**.

El cuerpo fue recapturado directamente. Lee únicamente las fuentes ya declaradas:
`public.contratos`, `crm.operaciones_cartera`, `crm.cierres_externos`,
`crm.leads`, `crm.metas_vendedor` y `crm.meta_periodos`, y aplica
`private.analista_atribuido_cadena` a contratos y desgloses. Conserva la
excepción declarada de ATR-4: la fila demo `a112aead-…` es la única con
medida `nula` y monto `0`.

### `private.analista_atribuido_cadena`

- Firma única: `private.analista_atribuido_cadena(uuid)`. Resultado: `uuid`.
- Lenguaje/atributos: SQL, `STABLE`, invocador, `search_path=""`.
- Propietario: `postgres`. ACL: `{postgres=X/postgres}`.
- `md5(pg_get_functiondef)`: `3c9cec305b014ad8c933df25057d3e8b`.
- `md5(prosrc)`: `e39016e2913cce47faabee29c2c38fe2`.
- Comparación con el pin de ATR-2/ATR-4 y con R1: **coincidencia exacta**.

## Consumidores observados

Censo reproducible: `strpos(pg_proc.prosrc, …) > 0` sobre los esquemas `crm`,
`public` y `private` (nunca `LIKE`: el guion bajo es comodín y casa prosa),
más el mismo barrido sobre `pg_views.definition`. Resultado: **17 funciones,
0 vistas**, exactamente el mismo conjunto y las mismas huellas que R1.

| Consumidor | Referencia | `md5(prosrc)` |
|---|---|---|
| `crm.atribucion_contrato_fn(uuid)` | atribución | `1eccb3a1ff8b73e91f2f7870d08f83e8` |
| `crm.contratos_por_periodo_comercial_fn(date)` | Capital | `f7a322f9c41bf66675f4979868747b04` |
| `crm.metricas_capital_mes_fn(integer)` | Capital | `b21f9a7a134f76f9f2eabfe75578cbca` |
| `crm.metricas_vencimientos_fn(integer)` | Capital | `4e7751a6c644a9c120ae155035e70561` |
| `crm.resumen_cartera_clientes_fn()` | Capital | `541c486b442011cd4a4a367ea8a0dd7a` |
| `public.dashboard_admin_metricas()` | Capital | `a08433337d53728bbf295cb292dd8794` |
| `public.directorio_ranking_analistas()` | Capital | `2f41fe29d1c5fa991fa7855336edefa2` |
| `public.directorio_top_clientes()` | Capital | `86bd131166db45e71ffc39b704c135cc` |
| `public.metricas_directorio()` | Capital | `048fb9e9c3f6163c768028f23e82ec91` |
| `private.assert_analitica_leads_citas()` | Capital | `6e21c8649b2cfb62dc24b5708a84a34a` |
| `private.capital_autorizada(date,date,text)` | Capital | `dc499b1f12693e6e724ef93848dda1ac` |
| `private.contratos_afectados_por_anulacion(uuid)` | atribución | `f65428e6aa50b7a68a2082dea52a6cb8` |
| `private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)` | atribución | `d825a0f89a0beb20a579d7f3de08f552` |
| `private.metricas_cartera_por_vendedor(date)` | ambos | `f968879ae7f354a4165f1aebedc685b9` |
| `private.metricas_conversiones_implementacion(date,date,text)` | Capital | `4642129507df5a0effe69c94e51b10bf` |
| `private.metricas_reuniones_implementacion(date,date)` | Capital | `ecc02c4e86a3f2d7ec2ad70bd8efafed` |
| `private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)` | Capital | `6d5ccff20d28d767ebd6efdf851806ac` |

## Fuentes — huellas de esquema

R1 no dejó escritos los separadores literales de su normalización, así que sus
`md5` de esquema **no son reproducibles** y no se comparan. R2 fija la
normalización de forma explícita para que R3 sí pueda comparar:

1. columnas: `ordinal_position|column_name|data_type|udt_schema|udt_name|is_nullable|coalesce(column_default,'')`, una por línea (`\n`), orden por `ordinal_position`;
2. constraints: `conname|contype|pg_get_constraintdef`, orden por `conname`;
3. índices: `indexname|indexdef`, orden por `indexname`;
4. texto final: `cols || '\n--constraints--\n' || cons || '\n--indexes--\n' || idx`;
5. `md5` del texto resultante.

| Fuente | Columnas | Constraints | Índices | RLS | ACL de tabla | `md5` esquema (R2) |
|---|---:|---:|---:|---|---|---|
| `public.contratos` | 26 | 18 | 14 | sí | `postgres=arwdDxtm, anon=arwd, authenticated=arwd, service_role=arwdDxtm` | `1ff13639738b323191e5b174fafa302f` |
| `crm.cierres_externos` | 18 | 15 | 7 | sí | `postgres=arwdDxtm` | `dc5abe49838bcc7e6a45b0c3310749e1` |
| `crm.operaciones_cartera` | 16 | 14 | 5 | sí | `postgres=arwdDxtm, authenticated=r` | `ad80cfe2620d2c382ae943e2a27ea942` |
| `crm.leads` | 37 | 24 | 22 | sí | `postgres=arwdDxtm, authenticated=rw, service_role=arwd` | `f24b05fc8e5a0e9c5ec6b01f4e55fb4f` |
| `crm.metas_vendedor` | 6 | 7 | 4 | sí | `postgres=arwdDxtm, authenticated=r, service_role=r` | `3f74006a41d7e32ed9d3417317ff9d30` |
| `crm.meta_periodos` | 6 | 6 | 5 | sí | `postgres=arwdDxtm, authenticated=r, service_role=r` | `6375050997c76f3f34e5b4b32a8430cf` |

Los conteos de columnas, constraints e índices son **idénticos a R1 en las seis
fuentes**. Los registros 197–198 no cambiaron ninguna estructura.

La restricción `crm.cierres_externos_un_cierre_por_lead UNIQUE (lead_id)` sigue
presente. Es el bloqueo conocido que F1 deberá reemplazar de forma aditiva y
controlada; su presencia en G0 es esperada, no una deriva.

Nota sobre `crm.leads`: su ACL de tabla concede `rw` a `authenticated`, pero
la tabla tiene además **GRANT POR COLUMNA**; este
manifiesto no sustituye una auditoría completa de políticas RLS, solo confirma
RLS habilitado en las seis fuentes.

## Oráculos funcionales

### Capital mensual

Se comparó `crm.metricas_capital_mes_fn(60)` (con claims de Gerencia) contra
una agregación directa de `private.capital_episodios` con la misma ventana y
la misma clasificación contractual (`medida='stock'`, `tipo like 'contrato_%'`
o `cooperativa`, categoría `cooperativa` para las coops). R2 calculó **dos**
valores esperados: uno con la expresión del consumidor (`current_date`, reloj
UTC) y otro derivando la ventana de `(now() at time zone 'America/Lima')::date`.

| Evidencia | R1 | **R2** |
|---|---:|---:|
| Filas de salida RPC | 41 | 41 |
| Meses cubiertos | — | 2025-09 → 2026-09 |
| Huella RPC | `b5713699a6e93a39303a5dc39dd7fcd9` | `b5713699a6e93a39303a5dc39dd7fcd9` |
| Huella esperada (reloj UTC) | `b5713699…` | `b5713699a6e93a39303a5dc39dd7fcd9` |
| Huella esperada (reloj Lima) | — | `b5713699a6e93a39303a5dc39dd7fcd9` |
| `EXCEPT ALL` RPC↔UTC, ambos sentidos | 0 | 0 |
| `EXCEPT ALL` RPC↔Lima, ambos sentidos | — | 0 |

Normalización de la huella: `md5(fila::text)` por fila, orden por esa huella,
concatenación con `|`, `md5` exterior.

### AUM

Se comparó `public.metricas_directorio()->'aum'` con la suma directa de episodios
`medida='stock'`, conservando contratos activos y cooperativas conforme a ATR-4,
con `captado_mes` medido desde el inicio de mes en Lima.

| Moneda | AUM | Captado en septiembre | Variación informada |
|---|---:|---:|---:|
| PEN | 19,534,113.12 | 311,000.00 | 1.6 % |
| USD | 1,038,943.33 | 0.00 | 0 % |

Resultado: **coincidencia JSON exacta**, idéntica a R1.

### Núcleo completo y ATR-4

Ventana: `2000-01-01` → `2100-01-01`, `p_global = true`, `p_visibles = null`.
Normalización: `md5(row::text)` por fila, orden por esa huella, concatenación
con `|`, `md5` exterior.

| Evidencia | R1 | **R2** |
|---|---:|---:|
| Episodios totales | 513 | 513 |
| Huella del conjunto | `f02c25c9f7d24169e8deb80e59701364` | `f02c25c9f7d24169e8deb80e59701364` |
| Episodios `stock` | 512 | 512 |
| Episodios `desglose` | 0 | 0 |
| Episodios `nula` | 1 | 1 (la demo `a112aead-…`, monto 0) |
| Episodios sin analista | 13 | 13 (todos contratos; 0 coops) |
| Anulaciones Avance (contratos `estado='anulado'`) | 0 | 0 |
| Ajustes de mes cerrado | 0 | no recapturado: R1 no dejó su definición |
| Anulaciones externas | 1 | 1 (coincide con `cierres_externos.anulado_en`) |
| Violaciones «demo vuelve a ser dinero» (`nula` con monto ≠ 0) | 0 | 0 |
| Violaciones «anulación real pierde Capital» (coop anulada no demo sin `stock` > 0) | 0 | 0 |

Desglose por tipo (R2): `contrato_nuevo` 314 (21 sin categoría), `contrato_renovacion` 24,
`contrato_upgrade` 160, `cooperativa` 15 (14 `stock` + 1 `nula`). Estados:
activo 497, vencido 1, vigente 14, anulado 1. Stock por moneda:
PEN 19,544,713.12 · USD 1,038,943.33 (incluye el contrato vencido, por eso
supera el AUM en 10,600 PEN). Contratos en tabla: 498 reales + 2 demo.

Las 13 filas sin analista son el histórico ya declarado durante ATR-3a; no se
observó una deriva nueva en el núcleo. G0 las congela como baseline, no las
declara deseables para las escrituras nuevas.

### Guardianes

- `private.assert_analitica_leads_citas()` →
  `OK: 30 contadores declarados y con su huella intacta, tope 30, 0 sin declarar`.
- `private.assert_analista_vigencia()` →
  `OK: 6 puertas declaradas y con su huella intacta, tope 6, 0 sin declarar`.

## Guardas operativas recibidas después de la captura R1

Miguel comunicó estas condiciones el 2026-09-01 después de la primera pasada de
G0. Son autoridad operativa para cualquier continuación. R2 las respetó todas;
las cifras del banco siguen sin recapturarse independientemente (R2 no lo usó).

### 1. Capital tiene una sola calculadora

- `private.capital_episodios` es la única calculadora de Capital.
- El trinquete vigente admite **0 calculadoras crudas** fuera del núcleo en
  `crm`, `public` y `private`; ese tope solo puede bajar.
- Una pantalla o arreglo puede agregar la salida del núcleo, pero no volver a
  sumar `contratos.capital`, `operaciones_cartera.capital_renovado`,
  `operaciones_cartera.capital_adicional` ni `cierres_externos.monto` por su
  cuenta.
- Cualquier SQL nuevo que calcule directamente desde esas fuentes debe ser
  rechazado por el gate.

R2 respetó esta guarda: los oráculos sumaron `e.monto` únicamente sobre la
salida de `private.capital_episodios`; no se creó ni persistió otra calculadora.

### 2. El banco no está virgen

Estado informado por Miguel después de ejecutar la prueba de carga de F4:

- `10 408` leads sembrados y posteriormente desactivados;
- `10 346` episodios conservados por el ledger `INSERT-only`;
- `7` leads vivos;
- reset del gate aplicado.

Toda medición futura en ese banco debe declarar ese residuo como parte del
baseline. No se puede interpretar el conteo histórico como fixture limpio ni
intentar borrar el ledger para "limpiarlo". Ni R1 ni R2 usaron ese banco:
consultaron producción en `READ ONLY`.

### 3. Carpeta compartida por sesiones paralelas

Existen varias sesiones sobre la misma carpeta. La regla operativa vigente es:

- trabajar directamente sobre `main`;
- no cambiar de rama, porque movería el suelo de las otras sesiones;
- hacer cambios aislados y commits pequeños cuando se autorice commitear;
- revisar el estado compartido antes y después de cada cambio.

R2 no cambió de rama ni creó worktree; `main` local estaba en `75c03d0` (el
commit que publicó 197–198). Solo reescribió este archivo Markdown, todavía sin
commit, preservando los demás cambios existentes.

### 4. Piezas cerradas durante la observación F7

Hasta el 13–14/09 permanecen cerradas y vigiladas:

- `metricas_altas_analista_fn`;
- `metricas_cartera_fn`.

No deben reabrirse ni reemplazarse para resolver una visualización. Un vigía
diario y el gate detectan cambios, y tocar esas piezas reiniciaría o rompería la
ventana de observación de la Fase 7. R2 no las modificó ni las invocó.

### 5. Rendimiento ya medido

Medición informada por Miguel con `10 000` leads:

| Lectura | Tiempo observado |
|---|---:|
| Capital del mes | `8 ms` |
| Vencimientos | `7,5 ms` |

Los tiempos son equivalentes a los observados con `208` leads y el Capital no
cambió. Por tanto, si una pantalla muestra un número incorrecto, la hipótesis
inicial debe ser semántica o frontend, no rendimiento. La observación UTC/Lima
de este manifiesto pertenece precisamente a la categoría semántica.

## Observación temporal pendiente

Durante la ejecución de R2:

- timezone de sesión: `UTC`;
- `current_date` de sesión: `2026-09-02`;
- fecha civil en `America/Lima`: `2026-09-01`.

Es decir, R2 corrió **dentro** de la franja de divergencia (19:00–23:59 de
Lima). El cuerpo productivo de `crm.metricas_capital_mes_fn` usa:

```sql
date_trunc('month', current_date)
current_date + 1
```

y solo después convierte esos `date` a medianoches de Lima. En el último día
del mes, la ventana puede saltar al mes siguiente cinco horas antes del cierre
civil de Lima. `crm.metricas_vencimientos_fn` conserva el mismo patrón con
`current_date` (límite superior y filtro de `fecha_vencimiento`) y debe
revisarse en el mismo análisis.

`public.metricas_directorio`, en cambio, deriva correctamente su fecha con
`now() AT TIME ZONE 'America/Lima'`; su AUM pasó el oráculo.

Lo que R2 añade: el oráculo con reloj de Lima coincidió con el RPC. Eso demuestra
que **hoy, 1/09 en Lima**, ambas ventanas caen en el mismo mes y ningún contrato
lleva fecha comercial 2026-09-02, así que la salida es la misma. **No demuestra
el borde de fin de mes** (30/09 entre 19:00 y 23:59 de Lima, cuando el reloj
UTC ya vive en octubre y la ventana de 60 meses se desplaza un mes). Antes de
firmar G0 se necesita una de estas salidas explícitas:

1. demostrar con un oráculo de borde (simulando el instante 30/09 23:00 Lima)
   que el comportamiento vigente satisface el contrato comercial de Lima; o
2. autorizar por separado una corrección SQL de la ventana y volver a recapturar
   huellas y oráculos (afecta al menos a `metricas_capital_mes_fn` y
   `metricas_vencimientos_fn`).

No se corregirá ni se aceptará silenciosamente dentro de G0.

## R3 — Oráculo de borde UTC/Lima (2026-09-02): la observación queda clasificada

Serial `AVC-MULTIEMPRESA-G0-20260902-R3`. Ejecutado ~05:00Z (00:00 Lima) en
`begin read only; …; commit;` con `transaction_read_only = on` en cada fila.
Antes de medir se verificó que producción sigue en **198 migraciones** con la
misma huella de R2 (`fc46855522d1d114deda4a27a222f046`) y que las dos funciones
observadas conservan su `md5(prosrc)` de R2 (`b21f9a7a…` y `4e7751a6…`).

### Método

`current_date` no se puede falsear en producción, así que el oráculo evalúa la
**misma lógica** de cada función con la fecha como parámetro: para cada día
civil `D` de Lima entre 2026-09-01 y 2027-08-31 se calcula la salida con
`cd = D` (lo que debe ver Lima) y con `cd = D + 1` (lo que el servidor usa
entre 19:00 y 23:59 de Lima, cuando su reloj UTC ya vive en mañana), y se
comparan con `EXCEPT ALL` en ambos sentidos. La ventana de
`private.capital_episodios` se replica filtrando su salida completa por
`e.fecha` con las expresiones literales de cada función (el núcleo devuelve
`fecha` como medianoche de Lima para contratos y desgloses, e instante para
cooperativas, así que el filtro es equivalente a pasarle la ventana).

Tres controles de fidelidad, todos con **0 filas distintas**:

1. réplica vs. **llamar al núcleo con la ventana real** en el borde (cd
   2026-09-30 y 2026-10-01, p_meses 12 y 60);
2. RPC real `crm.metricas_capital_mes_fn(12)` con claims de Gerencia vs.
   réplica en `cd = current_date` (40 filas);
3. RPC real `crm.metricas_vencimientos_fn(90)` con claims de Gerencia vs.
   réplica en `cd = current_date` (4 filas).

Parámetros que manda el front (`CRM-Avance-Corp/app/src/screens/hoy/graficas-gerencia.tsx`):
Capital `p_meses = 12`; Vencimientos `p_dias = 365` (`DIAS_VENCIMIENTOS`). La
pantalla no calcula fechas en el navegador: pinta lo que devuelve el servidor.
El SQL íntegro del oráculo queda en el scratchpad de la sesión
(`g0-reloj/oraculo-borde.sql`) y se reproduce con este método.

### Resultado 1 — `crm.metricas_capital_mes_fn`

| Evidencia | p_meses = 12 (front) | p_meses = 60 |
|---|---:|---:|
| Días con diferencia (365 evaluados) | **9** | 0 |
| Cuáles | último día de cada mes desde 2026-12-31 | — |
| Filas `solo_utc` (dinero que aparecería de más) | 0 | 0 |
| Filas `solo_lima` (dinero que desaparece antes) | 40 | 0 |
| **30/09/2026** | **0 diferencias** | 0 |

Lectura: el dinero **nunca cambia de mes** (`mes_comercial` se calcula en Lima
dentro del núcleo). Lo que se mueve es el **borde inicial** de la ventana de 12
meses: el último día del mes, de 19:00 a 23:59 de Lima, el servidor ya cuenta
el mes siguiente y el mes más antiguo desaparece cinco horas antes. El 30/09 no
se nota porque el mes que saldría (2025-10) no tiene datos; el primer caso
visible es el **31/12/2026** (enero 2026: 3 contratos, 120 000 PEN) y luego cada
fin de mes (el 31/05/2027 desaparece junio 2026 entero: 64 contratos nuevos PEN
por 4 391 660,40, etc.).

### Resultado 2 — `crm.metricas_vencimientos_fn`

| p_dias | Días con diferencia (365 evaluados) |
|---:|---:|
| 30 | 254 |
| 90 | 282 |
| 180 | 224 |
| **365 (front)** | **178** (424 filas) |
| 366 | 176 |

Lectura: la divergencia es **DIARIA**, no de fin de mes. Cada día `D`, entre
19:00 y 23:59 de Lima, el servidor evalúa «hoy» como `D + 1`, así que (a) los
contratos que vencen **hoy** desaparecen de «por vencer» cinco horas antes y
(b) los que vencen en `D + p_dias` entran un día antes. Casos reales con los
datos vivos:

- **23/09/2026 a las 19:00**: el contrato de 150 000 PEN que vence ese día (el
  primer vencimiento real del CRM) deja de aparecer como «por vencer»; el ciclo
  diario que lo marcará `vencido` corre a las 09:10 de Lima del día siguiente,
  así que durante cinco horas no está ni en «por vencer» ni en «vencidos».
- 01/09/2026 (hoy, ya pasado el borde): con `p_dias = 365` entraron un día antes
  4 contratos PEN (205 600) y 1 USD (1 500) que vencen en septiembre 2027; con
  `p_dias = 90`, el contrato de 70 000 PEN que vence el 30/11.
- 30/09/2026 en concreto: sin filas (ningún contrato vence ese día), pero el
  patrón se repite 178 de los 365 días siguientes.

### Resultado 3 — un tercer afectado fuera del CRM

`public.dashboard_admin_metricas()` (tablero del gestor de cartera en el
Portal; consumidor nº 6 del núcleo) clasifica `vencido` con
`fecha_vencimiento < current_date` y `por_vencer` con
`fecha_vencimiento <= current_date + 30`: mismo patrón diario. No se barrió
porque devuelve un JSON agregado, pero el cuerpo lo muestra. Censo completo
(`strpos`, no `LIKE`) sobre `crm`, `public` y `private`: de los 17 consumidores
del núcleo, **solo estos tres** usan `current_date`; `public.metricas_directorio`
ya deriva su fecha con `now() at time zone 'America/Lima'`. Fuera del núcleo,
`crm.metricas_pagos_mes_fn` (cuotas) usa `current_date` para el borde inicial
de su ventana y además lleva `search_path` `private, public, crm` en vez del
vacío; no afecta a Capital, se anota para el mismo paquete.

Cron relevante (UTC): `ciclo-contratos-diario` 14:10, `crm-cierre-mes-diario`
14:20, `recordatorio-cuotas-3d` 14:00; vigías 06:17–06:59. Ninguno corre dentro
de la franja 00:00–04:59 UTC, así que los jobs no ven la divergencia; solo la
ven las pantallas.

### Veredicto de R3

- **Salida 1 (demostrar que el comportamiento vigente cumple el contrato de
  Lima): REFUTADA.** Para Vencimientos el contrato se incumple 178 días al año
  durante cinco horas; para Capital mensual se incumple cada fin de mes desde el
  31/12/2026. El borde del 30/09/2026 en particular está limpio con los datos de
  hoy, pero eso es casualidad de los datos, no una propiedad de las funciones.
- **Salida 2 (corrección SQL autorizada aparte): es la única vía para firmar
  G0.** Alcance propuesto, pendiente del `!` de Miguel: sustituir
  `current_date` por `(now() at time zone 'America/Lima')::date` en
  `crm.metricas_capital_mes_fn`, `crm.metricas_vencimientos_fn` y
  `public.dashboard_admin_metricas` y `crm.metricas_pagos_mes_fn` (Codex
  demostró que no es opcional). No añade calculadoras (el trinquete sigue en
  0), no toca las piezas cerradas de F7 ni el núcleo, y cambia 3 de las 17
  huellas de consumidores: tras publicar hay que recapturar esas huellas,
  repetir los oráculos de Capital mensual, AUM y este de borde, y solo entonces
  firmar G0 (R4). Debe entrar **antes del freeze del sello (08–10/09)** o
  esperar a después.
- Nada de esto se corrige dentro de G0 ni sin autorización. Esta nota sigue sin
  autorizar F1, migraciones, backfill, escritura en Supabase, despliegue ni piloto.

### Refutación de Codex (sesión `01a06082-29a9-7552-832d-cf75f2e232c3`, 23 min, solo lectura)

Se le pidió REFUTAR las cinco conclusiones. Veredicto, ya contrastado en el
repo por esta sesión antes de aceptarlo:

| Conclusión | Veredicto | Evidencia verificada |
|---|---|---|
| 1. La réplica equivale a pasar la ventana al núcleo | **No refutada** | Contratos/desgloses comparan fecha civil y devuelven `fecha` = medianoche Lima; coops por instante con borde exclusivo. `zdump America/Lima 2025–2028`: sin DST. Solo un límite fuera de medianoche rompería la identidad, y ninguna RPC lo genera |
| 2. Capital: el dinero no cambia de mes | **No refutada** | `mes_comercial` sale del episodio, no del reloj. Matiz: es conclusión del *snapshot*; una alta tardía con fecha histórica (2025-10/11/12) adelantaría la primera diferencia. Las altas normales no admiten fechas futuras (`20260824170630`, líneas 152 y 427) |
| 3. Vencimientos: divergencia diaria | **No refutada** | Intervalo semiabierto `[cd, cd + p_dias)`; con `cd = D + 1` salen las filas de `D` y entran las de `D + p`. Codex señaló que la pantalla manda 365, no 90: ya medido arriba (178 días) |
| 4. Censo completo | **Refutada en parte** | El censo SQL es correcto, pero hay relojes de **navegador** fuera de él: «Mi cartera» calcula «por vencer ≤ 30 d» con el día local del navegador (`lib/cartera-vista.ts`, `diasHasta`, comentario «= Lima en prod») y el tablero antiguo del Portal (`public_html/js/admin/dashboard.js`) arma su tabla de vencimientos/pagos con hora local a propósito (comentario: así arregló que «un contrato que cae HOY desaparecía toda la tarde») mientras sus KPI vienen de `dashboard_admin_metricas` (reloj UTC). Para un usuario en Lima el navegador acierta; la inconsistencia es servidor↔navegador entre 19:00 y 23:59. Sin consumidores en edge functions |
| 5. Corrección propuesta | **Refutada en alcance** | La expresión `(now() at time zone 'America/Lima')::date` es correcta (`now()` = `transaction_timestamp()`, STABLE; `pg_catalog` resuelve con `search_path=''`). Pero `crm.metricas_pagos_mes_fn` **no es opcional**: la pantalla Hoy la llama siempre junto a las otras dos (`graficas-gerencia.tsx:272-274`). El paquete son **cuatro funciones** |

Efectos colaterales que Codex verificó y esta sesión confirmó:

- el trinquete de «0 calculadoras crudas» solo caza sumas directas de columnas
  (`supabase/scripts/trinquete-capital.sql`); una expresión temporal no lo dispara;
- no toca `metricas_cartera_fn` ni `metricas_altas_analista_fn` (piezas cerradas de F7);
- `private.assert_f7_piezas_cerradas()` tiene el **mismo defecto por separado**
  (`current_date` en `20260831020000`, línea 288: puede dar por cumplido el 13/09
  desde las 19:00 del 12/09 Lima); las Olas 2/2b lo compensan con hora de Lima.
  Se deja anotado, fuera de este paquete;
- `crm.ciclo_cierre_mes()` ya calcula el mes en Lima (09:20 Lima); el único
  conflicto con el sello es de calendario (no publicar en el freeze 08–10/09);
- la migración de origen (`20260829191000_crm_f4_a_pantallas_gerencia.sql`)
  dice que `current_date` se COPIÓ del cuerpo vivo y que el único cambio
  deliberado fue la fuente de datos: fue herencia, no una decisión temporal.

**Alcance corregido tras Codex:** migración de **cuatro** funciones
(`crm.metricas_capital_mes_fn`, `crm.metricas_vencimientos_fn`,
`crm.metricas_pagos_mes_fn`, `public.dashboard_admin_metricas`), pendiente del
`!` de Miguel. Los dos relojes de navegador (Mi cartera y tablero antiguo del
Portal) quedan como paquete de front aparte; no bloquean la firma de G0 porque
no son consumidores del núcleo.

## Estado de ramas

- Árbol local en `main` = `75c03d0` con notas multiempresa sin commit; no se
  cambió de rama ni se mezcló una implementación.
- Supabase Branching sigue informando `banco-f7` (ref `cwkiejoaqadcnaieghnf`,
  creado 2026-09-01T21:28Z) con estado `MIGRATIONS_FAILED`; no se reutilizó
  (todo branch nuevo cae en `MIGRATIONS_FAILED` por diseño y se replay-a a mano).
- La metadata de Branching también muestra `MIGRATIONS_FAILED` para `main`,
  aunque el proyecto productivo está `ACTIVE_HEALTHY` y las 198 migraciones
  están registradas. Esa discrepancia de plataforma debe aclararse antes de
  preparar el branch aislado de F1.
- No se creó un branch nuevo: hacerlo requiere autorización y confirmación de
  costo; además F1 continúa sin autorización.

## Próximo gate

1. ~~Clasificar la observación temporal~~ **Hecho en R3**: requiere corrección.
2. Obtener el `!` de Miguel para la migración del reloj (4 funciones, incluida
   `metricas_pagos_mes_fn` por veredicto de Codex), ensayarla en el banco (`banco-f7` sirve para
   ensayar SQL aunque su estado de Branching sea ambiguo) y publicarla antes del
   freeze del 08/09 o después del sello.
3. Recapturar las huellas de los consumidores tocados, repetir los oráculos
   (Capital mensual, AUM, borde) y firmar G0 como R4, siempre que la cuenta de
   migraciones sea la esperada.
4. En paralelo: seis decisiones de F0 y aclaración del `MIGRATIONS_FAILED` de
   Branching. Después, autorización expresa para F1.

Relacionado: [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]] ·
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]] ·
[[Contrato de la capa semantica - Capital (F4, 2026-08-29)]] ·
[[Contrato de la atribucion por cadena de upgrade (2026-08-30)]] ·
[[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
