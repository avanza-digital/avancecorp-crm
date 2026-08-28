# Auditoría del servidor Supabase — duplicación y deuda (P-053, 2026-08-28)

Auditoría de **solo lectura** sobre producción (`dctqcbznekcyxhjujuci`), esquemas `crm` / `private` / `public`. Cero escrituras: todo salió del catálogo (`pg_proc`, `pg_policies`, `pg_trigger`, `pg_index`, `pg_constraint`, `information_schema`), de conteos agregados, de los logs (solo lectura) y del repo local. Cada hallazgo lleva su consulta pegada, reproducible copiando y pegando. Los hallazgos que aspiraban a ROTO pasaron por refutación adversarial independiente (3 lentes: reproducción, diseño deliberado, impacto); el resultado de esa refutación está dicho donde aplica.

Relacionadas: [[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]] · [[Conversion unica en todo el CRM - plan de migraciones 2]] · [[Fundamentos UX del CRM]]

## Resumen ejecutivo

- **Nada se comporta mal hoy ante un usuario, salvo una cosa**: `public.contrato_titulares` (co-titulares de cuentas mancomunadas, dato con peso legal) **muta sin dejar rastro en `audit_log`** — 0 entradas contra 1 083 de `contratos`, y 0 de los 9 co-titulares actuales están protegidos por el congelamiento documental. Es el único ROTO.
- **2 de los 3 "rotos" de la auditoría de superficie se refutaron con evidencia**: el desacuerdo `es_admin`/políticas no bloquea a nadie (las políticas permisivas se OR-ean), y `crm.operaciones_cartera` es un ledger append-only con autoría en la propia fila — su "falta de auditoría" era un falso positivo del método.
- La cifra que más importa: **la matriz de autorización está copiada a mano en ~114 funciones** (roles literales; 140 resuelven el actor con `auth.uid()` inline; 20 llevan el gate completo `rol_crm in (...)` copiado) y **el proyecto no usa ni un solo enum/dominio**: toda lista fija vive en CHECKs de texto repetidos entre 2 y 7 tablas.
- La duplicación de métricas es mayor que la estimada (capital en **16** funciones, no 6; leads en **21**, no 4) — ya resuelta por diseño en P-050/051/052, **sin ejecutar** (`private.capital_episodios` no existe aún).
- Seguridad: **limpia en lo que importa** — 283/283 `SECURITY DEFINER` con `search_path` fijado, 57/57 tablas con RLS, cero funciones de escritura alcanzables por `anon`, cero políticas para `anon`. Queda deuda cosmética de grants heredados de Supabase (incl. `TRUNCATE`, que la RLS no gobierna).
- Ventana barata que se cierra: `crm.cierre_mes_vendedor` y `cronograma_pagos` no tienen malla anti-NaN y el **primer sellado real es el 10/09** — hoy están con 0 filas / 0 violaciones: es el momento gratis de cerrar la regla.

---

## ROTO

### R1 · `public.contrato_titulares`: se agregan y eliminan co-titulares sin rastro de auditoría

- **Objetos:** `public.contrato_titulares` · `public._sync_contrato_titulares` (hace el `DELETE FROM` + re-`INSERT`) · `public.crear_contrato` y `public.actualizar_contrato` (EXECUTE a `authenticated`, delegan en `_sync`) · ausencia de trigger `log_audit_change` en la tabla.
- **Evidencia (9 filas · 0 en audit_log · 1 083 de contratos):**
```sql
select count(*) filter (where tabla='contrato_titulares') as titulares_en_audit,
       count(*) filter (where tabla='contratos')          as contratos_en_audit
from public.audit_log;                                   -- => 0 · 1083
select count(*) from public.contrato_titulares;          -- => 9
select t.tgname, p.proname from pg_trigger t
join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
join pg_proc p on p.oid=t.tgfoid
where n.nspname='public' and c.relname='contrato_titulares' and not t.tgisinternal;
-- => único trigger: trg_contrato_titulares_00_documental_congelado (candado documental, no audita)
select count(*) as titulares,
       count(*) filter (where private.contrato_documental_congelado(ct.contrato_id)) as congelados
from public.contrato_titulares ct;                       -- => 9 · 0
```
- **Manifestación hoy:** el registro de auditoría ya está incompleto: las altas de los 9 co-titulares no existen en `audit_log` mientras las de sus contratos sí. Cualquier gestor de cartera que llame `actualizar_contrato` con la lista de titulares recortada elimina un co-titular sin quién/cuándo/qué-había-antes (el `_sync` borra TODOS y reinserta desde el JSON). La única defensa (congelamiento documental post-19/08) hoy no cubre a ninguno de los 9.
- **Mecanismo verificado:** la escritura directa por API está bloqueada (RLS activa, 1 sola política y es de SELECT); el único camino de mutación son las RPC, y esa vía no audita (`strpos(prosrc,'audit_log')=0` en las tres funciones). Precisión sobre la auditoría previa: `crear/actualizar_contrato` no hacen DML directo sobre la tabla — todo pasa por `_sync_contrato_titulares`.
- **Consecuencia de no arreglar:** dato contractual con peso probatorio, mutable sin historial, justo en la tabla satélite de la entidad mejor auditada del sistema. Ante un reclamo de cuenta mancomunada, la reconstrucción forense sale incompleta.
- **Nota de honestidad (contraste 2/3):** de las 3 refutaciones adversariales, dos lo confirmaron como ROTO y una lo bajaría a deuda forense ("no consta que jamás se haya eliminado un co-titular; solo se manifiesta si hay reclamo"). Se queda en ROTO porque el registro de auditoría ya está incompleto hoy, no solo en un escenario futuro; queda dicho el disenso.
- **Esfuerzo:** bajo (colgar `public.log_audit_change` — `id` es uuid, aplica tal cual; requiere migración = rama). **Dependencias:** decidir antes la convención de D3 (a cuál de las dos funciones de auditoría se suma).

---

## DUPLICADO

### D1 · Trío `*_contrato_producto` duplicado crm/public: 6 funciones dormidas sin ningún llamador — y el criterio "seleccionable" escrito 3 veces

- **Objetos:** `crear_contrato_producto`, `actualizar_contrato_producto`, `actualizar_contrato_con_cuenta_producto` (cada una en `crm` y `public`, las 6 con EXECUTE a `authenticated`) + `productos_inversion_seleccion_fn` (crm/public, fork real) + `crm.cerrar_altas_legacy_productos`.
- **Corrección al hallazgo previo:** NO son forks activos. Los 6 cuerpos delegan en el MISMO núcleo (`public.crear_contrato` / `public.actualizar_contrato` / `crm.actualizar_contrato_con_cuenta`); difieren solo en el gate por superficie (patrón wrapper del sistema) y en la coreografía del GUC `crm.producto_condicion_id`, que **ya divergió levemente** (public guarda/restaura el valor anterior; crm lo resetea a `''`). Y **nadie los llama hoy**: cero llamadores en CRM app, portal, edges y base — el único que los menciona es `cerrar_altas_legacy_productos`, solo como guard de existencia (`to_regprocedure`). Los flujos vivos son `crm.crear_contrato_con_cuenta_pdf_v2` y `crm.actualizar_contrato_con_cuenta_pdf_v3` (CRM) y `public.crear_contrato` (portal).
- `productos_inversion_seleccion_fn` sí es fork real (firmas y columnas distintas, cada front llama la suya — CRM `crm-config-api.ts:306`, portal `productos-contrato-ui.js:141`): la diferencia de filas es de diseño, pero el predicado "condición seleccionable" (activo + no legacy + versión publicada + vigencia + condición activa) está escrito literal **3 veces** (WHERE del selector crm, `seleccionable_nuevo` del selector public, EXISTS de `cerrar_altas_legacy_productos`).
```sql
select n.nspname, p.proname, md5(p.prosrc), length(p.prosrc),
       (select string_agg(a.grantee::regrole::text||'='||a.privilege_type,',')
        from aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) a) as grants
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where p.proname in ('crear_contrato_producto','actualizar_contrato_producto',
                    'actualizar_contrato_con_cuenta_producto','productos_inversion_seleccion_fn')
  and n.nspname in ('crm','public') order by p.proname, n.nspname;   -- => 8 filas, todas authenticated=EXECUTE
```
- **Consecuencia:** cuando se encienda la "frontera catalogada", CRM y Portal podrían comportarse distinto en el mismo caso borde (GUC anidado), y un ajuste del criterio "seleccionable" en una sola copia haría que CRM y Portal ofrezcan catálogos distintos en silencio. **Esfuerzo:** medio. **Dependencias:** borrarlas rompería `cerrar_altas_legacy_productos` (guard de existencia); regla de Miguel: no borrar nada de prod sin su OK.

### D2 · `metricas_distribucion_leads`: 3 versiones vivas y expuestas — deuda de retiro programado consciente; v1 sin tráfico ni llamadores

- **Objetos:** `crm.metricas_distribucion_leads_fn` (v1) / `_v2_fn` / `_v3_fn` — las tres SECURITY DEFINER, owner `crm_metricas_bridge`, grants `authenticated`+bridge; las tres delegan en el despachador único `private.metricas_distribucion_leads_autorizada` (la autorización NO está triplicada, solo el shape del payload).
- v3 vigente (`crm-api.ts:3526`), v2 aún llamada (`crm-api.ts:3479` — el aviso de versión del front no recarga solo), **v1 sin llamadores estáticos** (solo `database.types.ts`) **y sin tráfico**: en los logs de 24 h hubo 10 716 requests `/rpc/` y **cero** mencionan `metricas_distribucion_leads` (ninguna versión):
```sql
-- query_logs (ClickHouse, ventana 24h):
select source, count() as hits from logs
 where event_message like '%metricas_distribucion_leads%' group by source;  -- => 0 filas
select source, count() from logs where event_message like '%/rpc/%' group by source; -- => edge_logs 10716 (control)
```
- **Consecuencia:** cada cambio al despachador debe sostener 3 contratos de salida. **Esfuerzo:** bajo. **Dependencias:** retiro bloqueado por bundles cacheados por la CDN (7 días) y por el consumidor externo del rol `crm_metricas_bridge` (conexión directa, no pasa por PostgREST — confirmar con Miguel qué lo usa). La ventana de logs es de solo 24 h: repetir la medición unos días antes de revocar.

### D3 · Dos funciones de auditoría escriben al MISMO `public.audit_log` con convenciones incompatibles

- **Objetos:** `private.log_audit_crm` (33 tablas crm) vs `public.log_audit_change` (6 tablas public); y `private.set_actualizado_en_crm` (4) vs `public.set_actualizado_en` (4) — este segundo par es idéntico en lo funcional, solo divergen envolturas.
```sql
select n.nspname||'.'||p.proname fn, count(distinct t.tgrelid) tablas
from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
where not t.tgisinternal
  and p.proname in ('log_audit_crm','log_audit_change','set_actualizado_en_crm','set_actualizado_en')
group by 1;                                              -- => 33 · 6 · 4 · 4
select tabla, count(*) from public.audit_log group by tabla order by 2 desc; -- formato partido visible en datos
```
- **Consecuencia (ya visible en los 22 356+ registros):** columna `tabla` CON esquema en la variante crm (`crm.leads`) y SIN esquema en la public (`contratos`) — todo reporte que agrupe por tabla debe conocer ambas convenciones o pierde la mitad del log; `fila_id` castea a uuid con fallback (6 tablas crm sin `id` → `fila_id` NULL) mientras `log_audit_change` exige `NEW.id` (revienta en runtime si la tabla no tiene `id`); la función equivocada en una tabla nueva no falla al crear el trigger sino al ESCRIBIR. **Esfuerzo:** medio. **Dependencias:** bloquea la forma final de R1 y C1 (a qué convención se suman las tablas nuevas).

### D4 · 3 políticas RLS re-implementan inline el chequeo que ya existe como helper

- **Objetos:** `public.audit_log · audit_log_superadmin_select` · `public.novedades · novedades_superadmin_elimina` · `public.suscripciones_push · suscripciones_push_select`.
```sql
select schemaname, tablename, policyname, cmd from pg_policies
where schemaname in ('crm','private','public')
  and (coalesce(qual,'')||coalesce(with_check,'')) like '%''superadmin''%'
order by tablename, policyname;                          -- => exactamente estas 3
```
- Hoy las 3 copias son lógicamente idénticas a `es_superadmin()`/`es_admin()`; si mañana el helper cambia, divergen en silencio y nadie las encuentra buscando el helper. Además `audit_log_superadmin_select` es 100 % redundante (superadmin ya pasa por `audit_log_admin_select`, ambas PERMISSIVE): se puede borrar sin cambio de comportamiento. **Esfuerzo:** bajo. **Dependencias:** ninguna.

### D5 · Gate de autorización disperso: 140 funciones con `auth.uid()` inline; matriz de roles copiada en 114

- **Conteos verificados** (base 330 funciones: crm 128 · private 163 · public 39, extensiones excluidas vía `pg_depend deptype='e'`): `auth.uid()` en **140** (88 crm, 37 private, 15 public) · literal `'gerencia'` en **94** · `'supervisor'` en **60** · algún rol literal en **114** · gate completo `rol_crm in (...)` inline en **20** · convención partida para la misma variable: `v_actor uuid` en 40, `v_uid uuid` en 35.
```sql
WITH fns AS (SELECT p.oid, n.nspname, p.prosrc FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('crm','private','public')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
                    AND d.objid=p.oid AND d.deptype='e'))
SELECT count(*) FILTER (WHERE strpos(prosrc,'auth.uid()')>0)      AS con_auth_uid,
       count(*) FILTER (WHERE strpos(prosrc,'''gerencia''')>0)    AS lit_gerencia,
       count(*) FILTER (WHERE strpos(prosrc,'''supervisor''')>0)  AS lit_supervisor,
       count(*) FILTER (WHERE strpos(lower(prosrc),'rol_crm in (')>0) AS rol_crm_in,
       count(*) FILTER (WHERE strpos(prosrc,'''gerencia''')>0 OR strpos(prosrc,'''supervisor''')>0
                        OR strpos(prosrc,'''vendedor''')>0)       AS algun_rol_literal
FROM fns;                                                -- => 140 · 94 · 60 · 20 · 114
```
- **Consecuencia:** agregar un rol, renombrar uno o cambiar qué rol puede qué exige editar ~114 cuerpos a mano; basta olvidar uno para que dos pantallas apliquen matrices distintas. **Esfuerzo:** alto (es EL refactor grande del servidor, junto con las métricas). **Dependencias:** el mismo refactor absorbe la convención `v_actor`/`v_uid`.

### D6 · Textos de error copiados sin catálogo: 70 ocurrencias en 4 familias (contexto: 713 `raise exception` en 199 funciones)

- **Conteos verificados** (la auditoría previa subcontaba): bloque exacto `raise exception 'No autorizado' using errcode='42501'` **40** veces (+7 variantes «No autorizado para …», todas con 42501) · `Contrato no encontrado` **12** como mensaje exacto (25 apariciones por substring) · `El contrato está en proceso de eliminación` **10** · `Selecciona un producto de inversión` **7**. Total del sistema: **713** `raise exception` en 199 funciones (el 713 es dispersión, no duplicación: los duplicados reales son las ~70 de las 4 familias).
```sql
-- desglose por mensaje exacto (los >=4 son las familias duplicadas):
WITH fns AS (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('crm','private','public')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
                    AND d.objid=p.oid AND d.deptype='e')),
msgs AS (SELECT (regexp_matches(prosrc,'raise\s+exception\s+''([^'']*)''','gi'))[1] AS msg FROM fns)
SELECT msg, count(*) FROM msgs GROUP BY msg HAVING count(*)>=4 ORDER BY 2 DESC;
```
- **Consecuencia:** los textos que el usuario ve (y que el front matchea por string) viven copiados N veces; ya divergieron variantes. **Esfuerzo:** medio. **Dependencias:** ninguna.

### D7 · `'America/Lima'` hardcodeada en 47 funciones (139 apariciones)

```sql
WITH fns AS (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('crm','private','public')
    AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass
                    AND d.objid=p.oid AND d.deptype='e'))
SELECT count(*) FILTER (WHERE strpos(prosrc,'America/Lima')>0)                                        AS fns,
       sum((length(prosrc)-length(replace(prosrc,'America/Lima','')))/length('America/Lima'))          AS occ
FROM fns;                                                -- => 47 · 139
```
- No es que el literal exista (`private.conversion_episodios` lo trae y ES la arquitectura objetivo): es que la zona horaria del negocio no tiene punto único de verdad — un typo en una copia produce cortes de día/mes distintos entre pantallas sin que nada lo detecte. **Esfuerzo:** medio. **Dependencias:** ninguna.

### D8 · Métricas: capital en 16 funciones, leads en 21, citas en 6 — inventario para P-050/051/052 (ya diseñado, sin ejecutar)

- `private.capital_episodios` **NO existe** (0 filas en `pg_proc`): el rediseño está diseñado, no ejecutado; la duplicación sigue viva.
- **Capital (16, predicado `sum(` sobre columna capital):** `crm.cerrar_periodo`, `crm.contratos_por_periodo_comercial_fn`, `crm.metricas_capital_mes_fn`, `crm.metricas_cartera_fn`, `crm.metricas_vencimientos_fn`, `crm.metricas_vendedores_fn`, `crm.resumen_cartera_clientes_fn`, `private.metricas_cartera_por_vendedor`, `private.metricas_conversiones_implementacion`, `private.metricas_reuniones_implementacion`, `private.produccion_mes_por_vendedor`, `private.registrar_ajuste_si_mes_cerrado`, `public.dashboard_admin_metricas`, `public.directorio_ranking_analistas`, `public.directorio_top_clientes` (+1). Incluye 2 **escritoras** del ledger que sellan capital con su propia copia de la fórmula. Consumidores adicionales vía vistas intermedias sin `sum(` directo: `crm.resumen_cartera_fn`, `crm.series_comerciales_fn` (mencionan capital), `crm.cronograma_contrato_fn`/`titulares_contrato_fn`/`resumen_cartera_clientes_fn` (vía `contratos_cartera`/`clientes_basicos`).
- **Leads (21, `from crm.leads` + `count(`):** incluye contadores incidentales dentro de funciones de acción; el subconjunto de superficie de métricas es ~12. Ya produjo el episodio de los dos contadores divergentes que Miguel vetó el 28/08.
- **Citas (6, `from crm.tareas` + `reunion` + `count(`):** no existe tabla `citas`; las citas son filas de `crm.tareas` con columnas `*_reunion`.
```sql
select n.nspname||'.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('crm','private','public')
  and p.prosrc ~* 'sum\s*\(\s*(coalesce\s*\(\s*)?([a-z_]+\.)?"?capital' order by 1;  -- => 16
```
- **Esfuerzo:** alto. **Dependencias:** resuelto por diseño en P-050/051/052; este inventario (más completo que el previo: 16/21/6 vs 6/4/3) alimenta esa ejecución.

### D9 · La regla anti-NaN del dinero vive completa en UNA columna; en el resto está degradada o ausente

- **Regla canónica del proyecto** (`check (x <> 'NaN'::numeric and x > 0)`, lección PG17: `NaN > 0` es TRUE): completa solo en `crm.cierres_externos.monto`. Degradada (solo `>= 0`: NaN pasa) en `crm.lead_asignaciones.monto_estimado` y los 6 campos de `crm.ajustes_mes_cerrado`. **Ausente** en `public.cronograma_pagos.monto_programado/monto_pagado` (4 219 filas) y en TODOS los campos de `crm.cierre_mes_vendedor` (0 filas — **primer sellado real: 10/09**) y `crm.periodos_cerrados.ponderacion_referido`. Las columnas con tope superior (`x <= tope`) sí rechazan NaN de rebote (NaN es mayor que todo): protegidas con texto distinto.
```sql
select n.nspname, c.relname, a.attname, format_type(a.atttypid,a.atttypmod) tipo,
       (select string_agg(pg_get_constraintdef(con.oid),' | ') from pg_constraint con
         where con.conrelid=c.oid and con.contype='c' and a.attnum=any(con.conkey)) checks
from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
where n.nspname in ('crm','public') and c.relkind='r' and a.attnum>0 and not a.attisdropped
  and format_type(a.atttypid,a.atttypmod) like 'numeric%' order by 1,2,3;
-- datos hoy: 0 filas fuera de regla en cronograma_pagos; cierre_mes_vendedor/periodos_cerrados/ajustes vacías
```
- **Consecuencia:** un NaN en `cronograma_pagos` o en el sellado mensual contamina toda suma del portal o del cierre. Hoy 0 violaciones y las tablas del sellado vacías: **es el momento barato de cerrarla, antes del 10/09**. **Esfuerzo:** bajo. **Dependencias:** ninguna (migración en rama).

### D10 · Formato de documento según tipo: regla completa en `cierres_externos`, ausente en `perfiles` — y ya hay 3 filas divergentes

- `crm.cierres_externos` valida por tipo (DNI `^[0-9]{8}$` / CE / pasaporte); `public.perfiles` tiene la lista de tipos pero **ningún CHECK de formato** sobre `dni`; `public.contrato_titulares` solo exige no-vacío (hoy 9/9 cumplen el formato estricto por disciplina, no por esquema).
```sql
select count(*) filter (where tipo_documento='DNI' and dni is null)                       as dni_nulo,
       count(*) filter (where tipo_documento='DNI' and dni is not null
                        and dni !~ '^[0-9]{8}$')                                          as dni_malformado,
       count(*) filter (where tipo_documento='DNI')                                       as total_dni
from public.perfiles;                                     -- => 2 · 1 · 402
```
- **La divergencia ya se materializó:** 3 perfiles con documento que la regla estricta rechazaría, fuera de todo cruce por DNI (matching colaborador↔cliente y lead↔perfil usan DNI de 8 dígitos). **Esfuerzo:** medio. **Dependencias:** corregir las 3 filas antes de poder añadir el CHECK.

### D11 · Cero enums/dominios en todo el sistema: 6 listas fijas idénticas copiadas en 2–7 tablas (+ motivos de descarte por triplicado)

- `pg_type` con `typtype in ('e','d')` en crm/public/private: **0 filas**. Toda lista fija es CHECK de texto: `moneda IN (PEN,USD)` ×7 tablas · `categoria (nuevo,renovacion,upgrade)` ×4 · `tipo_documento` ×3 · etapas gestionables ×2 (+superset en leads) · `modalidad` ×2 · `tipo_interes` ×2. Y los 7 motivos de descarte viven por triplicado: CHECK en `crm.leads`, CHECK idéntico en `crm.enfriamiento_politica` y 7 filas de configuración en esa misma tabla (consumidas por el circuito de disponibilidad).
```sql
select tn.nspname, t.typname, t.typtype from pg_type t
join pg_namespace tn on tn.oid=t.typnamespace
where t.typtype in ('e','d') and tn.nspname in ('crm','public','private');   -- => 0 filas
```
- **Consecuencia:** una moneda/categoría/motivo nuevo exige tocar 2–7 CHECKs y nada avisa si uno queda atrás — el valor entra en una tabla y rebota en otra a mitad de flujo. Hoy todas las copias coinciden byte a byte. **Esfuerzo:** medio. **Dependencias:** decidir junto motivos de descarte y listas ×4+ (moneda, categoria).

### D12 · 8 pares de índices redundantes (el candidato a soltar es siempre el no-UNIQUE; verificado contra `pg_constraint`)

- **Duplicado exacto:** `crm.producto_condiciones_version_activas_idx` ≡ `producto_condiciones_orden_activo_uk` (mismas columnas, mismo predicado; sobra el no-unique).
- **Prefijo de un UNIQUE:** `metas_vendedor_detalle_meta_idx` · `sla_politica_etapas_politica_idx` · `idx_novedades_leidas_novedad` · `idx_suscripciones_push_cliente`.
- **No-unique prefijo de no-unique:** `idx_perfiles_rol` (251 466 scans — lo usan los helpers de rol; el planner lo elige, pero `idx_perfiles_listado_admin` lo cubre 100 %).
- **DESC redundante frente al UNIQUE ascendente (backward scan):** `meta_periodos_vigente_idx` · `sla_politicas_vigencia_idx`.
```sql
-- pares prefijo (la consulta completa, con indclass/indoption/indpred/indexprs iguales):
select n.nspname||'.'||t.relname tabla, ci1.relname menor, ci2.relname mayor
from pg_index i1 join pg_index i2 on i1.indrelid=i2.indrelid and i1.indexrelid<>i2.indexrelid
join pg_class ci1 on ci1.oid=i1.indexrelid join pg_class ci2 on ci2.oid=i2.indexrelid
join pg_class t on t.oid=i1.indrelid join pg_namespace n on n.oid=t.relnamespace
where n.nspname in ('crm','private','public') and ci1.relam=ci2.relam
  and i1.indpred is null and i2.indpred is null and i1.indexprs is null and i2.indexprs is null
  and i1.indisvalid and i2.indisvalid and i1.indnkeyatts<=i2.indnkeyatts
  and (i1.indkey::int2[])[0:i1.indnkeyatts-1]=(i2.indkey::int2[])[0:i1.indnkeyatts-1]
  and (i1.indclass::oid[])[0:i1.indnkeyatts-1]=(i2.indclass::oid[])[0:i1.indnkeyatts-1]
  and (i1.indexrelid<i2.indexrelid or i1.indnkeyatts<i2.indnkeyatts);
```
- **Consecuencia:** doble mantenimiento por escritura a cambio de nada; tablas chicas, costo hoy de catálogo, no de latencia. Ningún UNIQUE quedó marcado como redundante (verificado `conindid`). **Esfuerzo:** bajo (drops en rama, midiendo planes antes/después — en especial `idx_perfiles_rol`). **Dependencias:** ninguna.

---

## COSMÉTICO

### C1 · Cobertura de auditoría asimétrica: faltan 8 tablas (no 3) — y `operaciones_cartera` NO es el problema que parecía

- Universo real: **47** tablas en crm+public (no 42); **39 con trigger de auditoría** (33 `log_audit_crm` + 6 `log_audit_change` — conteo previo confirmado exacto); **8 sin él**: `crm.operaciones_cartera`, `public.contrato_titulares` (→ R1), `public.suscripciones_push`, `public.novedades_leidas`, `crm.agenda_ics`, `crm.usuario_eventos`, `crm.actividades_cliente`, `public.audit_log` (esta última por diseño, obvio).
- **`operaciones_cartera` REFUTADA como roto (3/3 lentes):** es un **ledger append-only deliberado** — su trigger `trg_operaciones_cartera_00_append_only` aborta todo UPDATE y todo DELETE directo (P0409); ninguna de las 330 funciones hace `UPDATE crm.operaciones_cartera` (el "hace INSERT y UPDATE" de la auditoría previa era un artefacto de `strpos` sobre todo el cuerpo); cada fila lleva `creado_por`+`creado_en` (60/60 pobladas; solo 12 de las 60 las escribió `crear_contrato`, las otras 48 son `backfill_agosto_2026`); el único borrado posible viaja con el DELETE del contrato, que SÍ queda en `audit_log` (94 DELETE de contratos registrados), y está vetado en meses de `periodos_cerrados`. Residuo real: al borrarse una operación no queda foto de sus montos (`capital_renovado`/`capital_adicional`) — cinturón-y-tirantes, no roto.
- Del resto: `usuario_eventos` es en sí una bitácora (ojo al cablear: `id` es **bigint** — colgarle `log_audit_crm` tal cual ABORTARÍA toda escritura por el cast `::uuid`); `actividades_cliente` está en 0 filas pero su camino de escritura ya está expuesto (`crm.cerrar_tarea`): conviene cablearla ANTES de que estrene datos, junto con R1; `agenda_ics` rota tokens sin rastro (1 fila); `suscripciones_push`/`novedades_leidas` son dato técnico sin valor probatorio.

### C2 · Grants heredados de Supabase en `public`: `anon`+`authenticated` con los 8 privilegios (incl. TRUNCATE, que NO pasa por RLS) sobre las 10 tablas core

- Las 10 tablas de `public` (incl. `audit_log`, `contratos`, `perfiles`) conservan los grants por defecto; el gating real lo hacen solo las políticas. Hoy inerte (RLS activa, cero políticas para `anon`, PostgREST no emite TRUNCATE), pero `TRUNCATE` ignora la RLS por diseño de Postgres: cualquier vía SQL futura con esos roles sería borrado masivo sin candado. **El log de auditoría tiene GRANT DELETE/TRUNCATE/UPDATE/INSERT a `anon`.** Contrasta con `crm`, donde los grants van comando a comando y calzan 1:1 con las políticas (matriz verificada: cero huecos).
- En la misma familia: 5 RPCs `admin_*` del portal ejecutables por `anon`/PUBLIC (SECURITY INVOKER de solo SELECT — hoy devuelven agregados en cero por RLS, pero son contrato de API no intencional; 2 de ellas sin ningún front que las llame) · 6 funciones de trigger de `public` con EXECUTE a `anon`/PUBLIC (no invocables: letra muerta) · 5 funciones de trigger de `private` con `proacl` NULL (heredan el default EXECUTE a PUBLIC; las otras 158 de private tienen ACL explícita) — no hay `pg_default_acl` para crm/private: la próxima función nace abierta.
```sql
select c.relname, coalesce(gr.rolname,'PUBLIC') grantee, a.privilege_type
from pg_class c join pg_namespace n on n.oid=c.relnamespace
cross join lateral aclexplode(c.relacl) a left join pg_roles gr on gr.oid=a.grantee
where n.nspname='public' and c.relkind='r' and (a.grantee=0 or gr.rolname='anon')
order by c.relname, a.privilege_type;
```
- Arreglo: REVOKE en tanda (rama) + `ALTER DEFAULT PRIVILEGES` en crm/private. Esfuerzo bajo.

### C3 · Cascadas y puertas de DELETE: la historia se puede borrar por arrastre y dos políticas dejan puertas abiertas sin auditoría

- **10 FKs `ON DELETE CASCADE` hacia tablas de negocio; en 4 hijas el DELETE no se audita** (`crm.actividades` — historial de gestión del lead, audita solo INSERT; `crm.actividades_cliente`; `public.cronograma_pagos` — cuotas incluidas pagadas, audita solo UPDATE; `public.contrato_titulares`). `equipo_perfil_id_fkey` codifica en el esquema lo contrario de P04 (borrar el perfil borra el asiento de membresía). Mitigación real presente: el ledger (operaciones_cartera, cierres, lead_asignaciones…) referencia perfiles con RESTRICT — un perfil con historia comercial no se puede borrar.
- **La edge `eliminar-cliente` borra físico el perfil y su cascada arrastra datos del CRM que su propio código no contempla** (el comentario dice "cascada: novedades_leidas, suscripciones_push"; también cascada `crm.cuentas_bancarias` — el ledger de cuentas, fuente de verdad — y `crm.actividades_cliente`). Hoy **5 clientes** sin contrato tienen cuentas bancarias registradas: si un admin los elimina, ese ledger se borra en la misma transacción.
- **2 políticas-puerta:** `superadmin_elimina_perfiles` no restringe el rol del perfil objetivo (un superadmin puede borrar por PostgREST el perfil de un vendedor; la cascada arrastra `crm.equipo` = violación directa de P04 — en la práctica los RESTRICT del ledger frenan a quien tenga historia) y `cronograma_admin_elimina` permite a un admin borrar cuotas —incluidas pagadas— **sin que ningún trigger audite ese DELETE**. Ningún frontend usa hoy esos caminos: puertas abiertas, no flujos vivos. El patrón correcto ya existe en `contratos_delete_solo_servidor (USING false)`.
- **Único DELETE físico de entidad:** `crm.contrato_eliminacion_finalizar` (flujo deliberado de dos fases, EXECUTE solo service_role, contrato cabecera auditado; sus hijos caen en el punto anterior).
```sql
select con.conname, conrel.relname hija, confrel.relname padre
from pg_constraint con join pg_class conrel on conrel.oid=con.conrelid
join pg_class confrel on confrel.oid=con.confrelid
where con.contype='f' and con.confdeltype='c'
  and confrel.relnamespace::regnamespace::text in ('crm','private','public') order by padre, hija;
```

### C4 · Estilo initplan partido: 13 políticas invocan helpers desnudos (8 son gratis; el costo por fila real hoy: ~11 ms en `novedades`)

- `es_admin()` desnudo en **10** políticas vs 8 envueltas en `(SELECT es_admin())`; +3 con otros helpers desnudos (`superadmin_elimina_perfiles`, `cronograma_admin_actualiza`, `documentos_admin_inserta`). **Impacto medido, no estimado:** cuando el helper es el único término del qual, el planner lo saca como One-Time Filter (audit_log, 22 356 filas: 1,9 ms, scan "never executed") — el costo por fila existe solo donde está OR-eado con columnas: `novedades_select`/`novedades_update` (810 filas → 810 llamadas ≈ 11 ms por scan; crece lineal). La consecuencia principal es que el patrón desnudo se sigue copiando. Nota: `private.rol_crm` NO tiene el problema (no invoca `auth.uid()`: el uid viaja por parámetro — la premisa previa era imprecisa); `es_admin/es_superadmin/es_operaciones/mi_rol` sí lo llaman desnudo adentro, sin consecuencia propia medible. *(Los EXPLAIN corrieron con el rol del MCP, que bypassa RLS: magnitudes indicativas.)*
```sql
select schemaname, tablename, policyname, cmd,
       case when strpos(coalesce(qual,'')||' '||coalesce(with_check,''),'SELECT es_admin()')>0
            then 'envuelto' else 'desnudo' end estilo
from pg_policies
where schemaname in ('crm','private','public')
  and strpos(coalesce(qual,'')||coalesce(with_check,''),'es_admin()')>0 order by estilo, tablename;
```

### C5 · Funciones muertas y candidatas a retiro: 1 muerta confirmada + 8 con grant que nadie llama

- **Muerta confirmada (base + repo + bundles desplegados):** `crm.contrato_pdf_snapshot_v2(uuid)` — ACL `{postgres=X}` (nadie puede ejecutarla), 0 referencias en las 7 capas del catálogo, 0 en el repo, 0 en el bundle vivo de la edge. Superada por `private.contrato_pdf_snapshot_v2_base`.
- **3 superadas por el flujo vigente** (grant a `authenticated`, 0 llamadores en repo NI en bundles desplegados NI en logs de 24 h): `crm.contrato_pdf_archivo_fn`, `crm.registrar_candidato_usuario_fn`, `crm.crear_contrato_con_cuenta_producto`.
- **4 esperando su pantalla** (NO retirar sin decidir el trabajo pendiente): `crm.resumen_tareas_fn` y `crm.resumen_cartera_clientes_fn` (previews mi-cartera/ficha-360, fuera a propósito) · `crm.contratos_por_periodo_comercial_fn` y `crm.corregir_fecha_cierre_comercial` (período comercial del supervisor, sin UI).
- **1 cubierta por D2:** `metricas_distribucion_leads_fn` v1.
- El esquema `private` entero (163 funciones): **cero muertas** — 66 de trigger cableadas, 6 en políticas, el resto callees, y las 2 sin referencia las llama `pg_cron` (jobs 4 y 5, activos, 0 fallos históricos).
- Límite que impide decir "muertas" a las 8 con grant: la hoja de Apps Script del puente (vive en Drive; este entorno no lista proyectos .gs) y el consumidor externo del rol `crm_metricas_bridge`.

### C6 · 24 FKs genuinamente sin índice de respaldo (de 126; 31 más están cubiertas por parciales `IS NOT NULL`, patrón deliberado)

- **5 en tablas que crecen** (las primeras que dolerán con el plan de escalabilidad): `lead_sla_etapas.politica_id` (1 372 filas), `tareas.asignado_supervisor_id` (1 127), `lead_sla_ciclos.politica_id` (665), `leads.asignado_supervisor_id` (660), `producto_condiciones.version_id` (534 — los índices existentes son `WHERE activa`). Hoy no duele: sus padres no reciben DELETE.
- **12 hacia `public.perfiles`** (el padre con MÁS deletes reales: 1 594) en hijas de 0–60 filas · **7** en tablas mini/legacy. Consulta completa en D12/N5 (pares por `conkey` prefijo de `indkey`, parciales evaluados aparte).

### C7 · NOT NULL faltantes: 10 columnas de timestamps/autoría del portal, 100 % pobladas y usadas sin guard

- `perfiles/contratos/cronograma_pagos/novedades/asesores/documentos · creado_en/actualizado_en` + `contratos.creado_por` — todas con DEFAULT `now()`, todas `total = no_nulos` (463/463, 415/415, 4 219/4 219…), y consumidas sin `coalesce` (p.ej. `metricas_directorio` cuenta `WHERE creado_en >= inicio_mes`: un INSERT con NULL explícito bypassa el default y la fila desaparece del conteo en silencio). La mitad "NOT NULL sobrante" del barrido: el probe de defaults centinela dio **0** y no se halló ninguna función insertando `''`/dummy en columnas NOT NULL (barrido dirigido, no exhaustivo — declarado en límites).

### C8 · 167 de 330 funciones (50,6 %) sin `COMMENT ON`

- crm 37/128 (28,9 %) · private 100/163 (61,3 %) · public 30/39 (76,9 %). Deuda documental pura; `private` — el corazón de los helpers — tiene 100 funciones mudas.
```sql
select n.nspname, count(*) total, count(*) filter (where d.objoid is null) sin_comment
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
left join pg_description d on d.objoid=p.oid and d.classoid='pg_proc'::regclass and d.objsubid=0
where n.nspname in ('crm','private','public') group by 1;
```

---

## Cruce con las edge functions desplegadas (las 16, código vivo — no el repo)

Se bajó el código **desplegado** de las 16 edges (todas ACTIVE: crear-cliente v31, crear-admin v18, enviar-comunicado v15, enviar-push v7, diagnostico-push v7, resetear-password v7, eliminar-cliente v7, notificar-pagos v9, importar-clientes v14, ciclo-contratos v6, crm-convertir-lead v12, crm-tipo-cambio v7, crm-agenda-ics v7, crm-importar-leads v18, crm-usuarios v7, crm-contrato-pdf-v2 v10) y se grepeó entero:

- **Candidatas a retiro (C5/D2): CERO hits en las 16.** Ninguna edge viva llama `contrato_pdf_archivo_fn`, `registrar_candidato_usuario_fn`, `crear_contrato_con_cuenta_producto`, `resumen_tareas_fn`, `resumen_cartera_clientes_fn`, `contratos_por_periodo_comercial_fn`, `corregir_fecha_cierre_comercial`, ninguna versión de `metricas_distribucion_leads`, `contrato_pdf_snapshot_v2` ni los 6 `*_contrato_producto` / `productos_inversion_seleccion_fn`. Las RPC que sí llaman: `verificar_cron_secret`, `marcar_contratos_vencidos`, `reservar_conversion_lead`, `marcar_efectos_conversion`, `convertir_lead_con_domicilio`, `agenda_ics_feed_fn`, `destinos_importacion_por_correo_fn`, `buscar_candidato_por_correo_fn`, `registrar_vendedor_usuario_fn` y las 6 `contrato_pdf_*` del ciclo PDF.
- **Escrituras a tablas sin trigger de auditoría: solo `suscripciones_push`**, y es técnico: enviar-push, notificar-pagos y ciclo-contratos hacen el mismo `UPDATE {activo:false}` sobre suscripciones expiradas (webpush 404/410). Cero escrituras desde edges a `operaciones_cartera`, `contrato_titulares`, `actividades_cliente`, `agenda_ics`, `usuario_eventos`, `novedades_leidas` — el límite "escrituras con service_role invisibles al catálogo" de C1 queda cerrado.
- **Hallazgos colaterales del cruce:** `diagnostico-push` v7 es un stub muerto (`respuesta 410 'gone'` en todo el código) desplegado y ACTIVE — candidata obvia a retirar (con OK de Miguel). En `crm-usuarios`, el password inicial es `input.documento` sin relleno: un PASAPORTE válido de 6–7 caracteres pasaría la validación pero moriría en el mínimo de 8 de Supabase Auth (`auth_create_failed`) — DNI/CE no afectados; es bug del edge, no de la base (anotado aquí porque apareció de paso). `notificar-pagos`, `ciclo-contratos` y `crm-agenda-ics` corren con `verify_jwt=false`: deliberado y documentado (x-cron-secret / token ICS).

---

## Tabla de priorización

| # | Hallazgo | Cubeta | Esfuerzo | Por qué en este orden | Depende de |
|---|----------|--------|----------|----------------------|------------|
| 1 | R1 auditoría de `contrato_titulares` (+ `actividades_cliente` y `agenda_ics` en la misma migración) | ROTO | bajo | dato legal mutable sin rastro, arreglo de una línea por tabla | decidir convención (D3) |
| 2 | D9 malla anti-NaN en `cronograma_pagos` + `cierre_mes_vendedor` | DUPLICADO | bajo | **antes del 10/09**: las tablas del sellado están vacías — hoy es gratis | — |
| 3 | C2 REVOKE de grants heredados (anon/TRUNCATE) + default privileges | COSMÉTICO | bajo | cierra el riesgo latente más feo (TRUNCATE sin RLS) de una vez | rama |
| 4 | C3 auditar DELETE en `cronograma_pagos` + acotar `superadmin_elimina_perfiles` + aviso en `eliminar-cliente` | COSMÉTICO | bajo | puertas de destrucción de historial sin rastro | comparte migración con 1 |
| 5 | D4 + C4: reescribir las 3 políticas inline y envolver las 13 desnudas | DUP/COS | bajo | mecánico, un solo pase de políticas | — |
| 6 | D10 corregir 3 documentos + CHECK de formato en `perfiles` | DUPLICADO | medio | la divergencia ya se materializó (3 filas fuera de cruce) | limpiar datos primero |
| 7 | D2/C5 retiro programado: v1 métricas + 3 superadas + muerta confirmada | DUPLICADO | bajo | logs 24 h en cero; repetir medición y pedir OK a Miguel | CDN 7 días · bridge externo · OK Miguel |
| 8 | D12 drop de 8 índices redundantes + C6 índices FK (tanda única) | DUP/COS | bajo | en rama, midiendo planes antes/después | rama |
| 9 | D8 ejecutar P-050/051/052 (capital 16 → núcleo único) | DUPLICADO | alto | ya diseñado; este inventario (16/21/6) alimenta la ejecución | P-050/051/052 |
| 10 | D3 unificar convención de auditoría (tabla con/sin esquema, fila_id) | DUPLICADO | medio | ordena el log partido; decidirlo ANTES de cablear tablas nuevas idealmente | decisión de datos históricos |
| 11 | D5/D6/D7/D11 el refactor grande: matriz de roles, catálogo de errores, zona horaria, enums | DUPLICADO | alto | el mayor volumen de deuda; hacerlo por capas tras las métricas | 9 |
| 12 | C5 (4 en espera de pantalla) · C7 · C8 | COSMÉTICO | bajo | decisiones de producto / oportunistas | decisión Miguel |

## Veredicto de los 11 hallazgos previos (uno a uno)

| # | Hallazgo previo | Veredicto |
|---|----------------|-----------|
| 1 | Dos definiciones de admin en desacuerdo; admin bloqueado de audit_log/novedades | **REFUTADO como roto.** Las políticas SELECT son PERMISSIVE y se OR-ean: los 2 admins activos VEN audit_log (`audit_log_admin_select` con `es_admin()`); el veto de DELETE en novedades al admin es diseño confirmado por el front del portal (gating `ES_SUPERADMIN`). Sobrevive como duplicación inline → D4. |
| 2 | 4 funciones dos veces con código distinto, ambas expuestas | **CORREGIDO.** Existen y están expuestas, pero 3 pares son wrappers dormidos sin ningún llamador que delegan al mismo núcleo (no forks activos); el 4.º (`productos_inversion_seleccion_fn`) es fork real de diseño con el criterio "seleccionable" triplicado → D1. |
| 3 | 3 tablas sin trigger de auditoría; otras 39 sí | **CORREGIDO.** El 39 es exacto, pero el universo es 47: faltan **8**, no 3. `operaciones_cartera` refutada 3/3 (ledger append-only con autoría propia); `contrato_titulares` se sostiene y es el único ROTO → R1; `suscripciones_push` sin valor probatorio → C1. |
| 4 | `auth.uid()` en 140; v_actor 37, v_uid 35 | **140 exacto.** Declaraciones estrictas: v_actor **40** (no 37), v_uid 35 ✓. |
| 5 | gerencia 94, supervisor 60, listas inline 20 | **Exactos los tres** (reproducidos 2 veces con consultas independientes). Añadido: 114 con algún rol literal. |
| 6 | 199 raise; 'No autorizado'+42501 28+6; textos 10/10/7 | **CORREGIDO.** 199 son las FUNCIONES; las ocurrencias son **713**. El bloque 'No autorizado'+42501 exacto es **40** (+7 variantes), no 28+6; 'Contrato no encontrado' 12 como raise exacto (25 por substring); los otros dos exactos ✓. |
| 7 | 'America/Lima' en 47 | **Exacto** (+dato: 139 apariciones). |
| 8 | log_audit_crm 33 / log_audit_change 6 / set_actualizado 4+4 | **Exactos los cuatro.** La consecuencia es real y visible: formato partido dentro del mismo audit_log → D3. |
| 9 | 3 versiones de metricas_distribucion_leads | **Confirmado**, con matiz: decisión consciente reciente, autorización NO triplicada (despachador único), v1 sin llamadores estáticos ni tráfico en 24 h → D2. |
| 10 | 6 capital / 4 leads / 3 citas | **Subcontado.** Con predicado estricto: **16 / 21 / 6**. `private.capital_episodios` no existe → P-050/051/052 sin ejecutar → D8. |
| 11 | initplan: rol_crm y es_lector_global; es_admin desnudo; 8/4 políticas | **PARCIALMENTE CORREGIDO.** `rol_crm` NO invoca `auth.uid()` (el uid viaja por parámetro — sin problema initplan); `es_lector_global` ya está bien; `es_admin()` desnudo confirmado. Políticas: **10 desnudas / 8 envueltas** (no 8/4) + 3 de otros helpers; impacto medido: solo `novedades` paga por fila (~11 ms) → C4. |

## Verificado y descartado (para no re-auditar)

**Seguridad (limpio):**
- **SECURITY DEFINER sin `search_path`: CERO.** 283/283 lo tienen fijado (public 27/27, crm 126/126, private 130/130). `select ... from pg_proc where prosecdef and (proconfig is null or not exists (select 1 from unnest(proconfig) c where c like 'search\_path=%' escape '\'))` → 0 filas.
- **SEC-URGENTE: no existe.** `anon` solo ejecuta 13 funciones, todas en public: 5 agregadoras SECURITY INVOKER de solo-SELECT (RLS frena → agregados en cero), 6 de trigger (no invocables) y 2 helpers booleanos que con `auth.uid()` NULL devuelven false. Cero funciones de crm/private ejecutables por anon; cero políticas para anon; cero tablas sin RLS.
- **Tablas sin RLS: NINGUNA** (57/57 con RLS; 6 de private además con FORCE). Las **26 con RLS y cero políticas** son deny-all deliberado: sin ningún grant a la API, operadas solo por SECURITY DEFINER — y el front no consulta ninguna directo (grep del data-layer). Ninguna pantalla recibe 0 filas por esto.
- **Matriz grant×política de `crm`: cobertura perfecta** (cero grants sin su política permisiva para ese comando). Único grant por columna del sistema: `crm.leads` (9 columnas, coincide con la memoria del proyecto).
- Las 24 funciones crm DEFINER+authenticated sin helper visible en el primer barrido **TODAS autorizan** (leídas una a una: `puede_operar_reparto_crm`, `puede_gestionar_contratos_crm`, `puede_leer_contrato_pdf`, gates delegados, etc.).
- `private.conversion_episodios` cerrada como manda la arquitectura (`proacl={postgres=X}`); `crm_metricas_bridge` es privilegio mínimo (NOLOGIN, sin BYPASSRLS, un solo EXECUTE en private). USAGE de `private` para authenticated es REQUISITO del patrón helpers-en-políticas (29 políticas llaman `private.rol_crm`), no una fuga; `anon` no tiene USAGE ni en crm ni en private.
- Los 7 helpers de private con EXECUTE a authenticated: justificados (los usan 29+ políticas evaluadas con los privilegios del caller). Riesgo residual mínimo aceptado: `rol_crm(uuid)`/`vendedor_ids_visibles(uuid)` aceptan uuid arbitrario → sondeo de rol/visibilidad, sin PII.

**Autorización y helpers:**
- `private.rol_crm`, `private.es_lector_global`, `private.vendedor_ids_visibles`: conformes a la arquitectura objetivo (deny-by-default, `(select auth.uid())`, `search_path=''`). No existe sobrecarga `rol_crm()` sin argumentos.
- Políticas de `perfiles`: todos los helpers envueltos — es el patrón al que migrar C4.

**Datos y modelo:**
- Teléfono principal: los 4 espejos en BD son **idénticos** (`^\+519[0-9]{8}$`); 660/660 leads cumplen. El regex más amplio del alternativo (con `(?!51)`) es diseño documentado, no divergencia. `crm.leads.telefono` cubierta por trigger BEFORE (no CHECK, pero la tabla no queda abierta).
- Dinero con tope superior: rechaza NaN de rebote (texto distinto, regla efectiva equivalente) — no se reporta.
- Regla "periodo = primer día de mes": 6 tablas con `date_trunc`, 1 tabla de archivo congelada con `EXTRACT(day)=1` — equivalentes, sin consecuencia.
- Listas de estados de contratos/cronograma/productos/tareas y roles CRM vs portal: dominios distintos por diseño, no copias.
- Enums/dominios huérfanos: no hay ninguno (no existe ninguno, punto → la mitad "sin uso" de la categoría queda vacía).
- 0 filas violando la regla canónica de dinero en las 4 219 de `cronograma_pagos`; tablas del sellado vacías.

**DELETEs legítimos (clase b, no se reportan):** `caducar_alertas_reconocimientos` (retención 90 días, audit en DELETE presente) · `caducar_recordatorios_disponibilidad` (PII caduca, 7 días) · `registrar_consulta_ayuda` (purga por `retener_hasta`) · `_sync_contrato_titulares` (delete+reinsert transaccional — su falta de AUDIT es R1, el patrón en sí es legítimo) · `actualizar_contrato` (reemplaza solo cuotas NO pagadas) · `trg_restaurar_operacion_antes_borrar_contrato` (hijo técnico del flujo de eliminación + guard de mes cerrado) · 6 CASCADE técnicos (tokens, marcas de lectura, push, ayuda) · FKs del ledger hacia perfiles: RESTRICT (contiene la mayor parte del riesgo de C3) · `contratos_delete_solo_servidor USING false` = patrón correcto.
- Los 59 triggers ON DELETE revisados: todos audit o guards que BLOQUEAN; ninguno borra colateralmente salvo el analizado.

**Índices:** 71/126 FKs con índice total; 31 cubiertas por parciales `IS NOT NULL` (el planner prueba la implicación con `=` estricto: cobertura real); los pares con predicados DISTINTOS (leads/tareas: cartera, parkeo, bandeja…) tienen cada uno su propósito — no redundantes; barrido extra de pares parciales con MISMO predicado: solo el duplicado exacto ya reportado.

**Funciones vivas que un grep ingenuo daría por muertas:** `ciclo_cierre_mes` + 2 `caducar_*` (pg_cron, jobs activos, 0 fallos, última corrida hoy) · familia legacy de contratos (callees de los wrappers vigentes) · `clientes_basicos_fn`/`contratos_cartera_fn` (vía vistas que el front consulta) · `metricas_cartera_fn` (callee de `conversion_mensual_fn`) · 4 sin grant que son callees internos (patrón wrapper del proyecto).

**Pasada de completitud (verificaciones extra, todas limpias):** (a) las 3 vistas de crm son `security_invoker=true` con solo SELECT a authenticated — sin fuga por vista DEFINER; no hay materialized views; (b) cero triggers deshabilitados (`tgenabled<>'O'` = 0); (c) las 7 secuencias de crm/private sin ningún grant a la API; (d) la publicación `supabase_realtime` contiene EXACTAMENTE `audit_log`, `novedades`, `novedades_leidas` — ninguna tabla de crm/private con PII publicada; (e) `private.log_audit_crm` SÍ registra `to_jsonb(old)` en DELETE (verificado leyendo la fuente); (f) los 5 cron jobs activos con 0 fallos en todo su historial.

## Límites y zonas sin auditar

- **Apps Script del puente de leads:** vive en Drive como script contenido en la hoja; la búsqueda de proyectos `.gs` en el Drive conectado devolvió vacío (los scripts contenidos no se listan como archivos). Las 8 "candidatas a retiro" de C5 no pueden confirmarse muertas sin abrir ese script a mano.
- **Consumidor externo de `crm_metricas_bridge`:** conexión directa (no pasa por PostgREST ni por estos logs); preguntar a Miguel qué lo consume antes de retirar v1/v2.
- **Ventana de logs: 24 h** (tope del API). El cero tráfico de D2/C5 es fuerte pero corto; repetir la medición unos días antes de revocar cualquier grant.
- **Config de PostgREST (`db-schemas`)** no es auditable por SQL: la no-exposición de `private` al Data API se gobierna ahí (la premisa "private sin USAGE" era imprecisa: authenticated SÍ tiene USAGE, y es requisito del patrón).
- **Realtime con RLS por suscriptor** sobre audit_log/novedades: asumido correcto (documentado), probarlo en vivo exige un JWT real.
- **EXPLAIN de C4** medidos con el rol del MCP (bypassa RLS, `auth.uid()` NULL): magnitudes indicativas; la medición exacta requiere rama.
- Redundancia entre índices GIN/GiST no auditada (solo btree, como pedía la tarea). "NOT NULL sobrante" cubierta solo con probe de centinelas (0) + barrido dirigido.
- Escrituras vía SQL dinámico (`format`/`execute`) no las caza `strpos`: un chequeo dirigido sobre las funciones con DELETE no arrojó candidatos.

## Método (reproducibilidad)

Auditoría orquestada en 21 pasadas independientes (11 de búsqueda + refutación adversarial de 3 lentes sobre cada candidato a ROTO + reproducción de muestra + pasada de completitud), todas contra producción en solo lectura. Pruebas de cierre: 3 hallazgos re-ejecutados al azar por un verificador independiente (2/3 al byte; el 3.º destapó que la consulta original de D4 sobre-contaba con ILIKE — quedó corregida aquí y re-verificada: 3 filas exactas) + 3 re-ejecutados de nuevo al ensamblar este informe (D4 corregida, D12 par exacto, D5 conteos 94/60/20/114): todos exactos. Cero sentencias fuera de SELECT/introspección en todo el ciclo.
