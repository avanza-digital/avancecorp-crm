---
tags: [crm, conversion, auditoria, arquitectura, borrador]
actualizado: 2026-08-26
estado: borrador técnico — insumo del paso 3; NO es el plan aprobado, no se escribe SQL sin OK de Miguel
---

> Salida del paso 2 del handoff [[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]].
> Inventario completo: **41 funciones SQL** que producen conversión (23 por nombre + 18 por fórmula, con solapes) y **55 cálculos de conversión hechos en el front**.
> Detalle crudo por función/cálculo (archivo:línea de todo): journal `wf_7ebabc4e-a85` en
> `~/.claude/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/5a9b6045-f2a0-4d21-8aa3-cb4f6797cad0/subagents/workflows/wf_7ebabc4e-a85/journal.jsonl`.
> Complementa a [[Auditoria conversion CRM - informe final gerencia (2026-08-26)]] (los 22 hallazgos confirmados).

# Plan: núcleo único de conversión en todo el CRM

## 1. Principio arquitectónico

El núcleo es `private.conversion_mensual_por_vendedor` (20260824231133:738) más su futura base set-returning `private.conversion_episodios`. Solo ahí viven cohorte por `asignado_en`, ponderación de referidos, arrastre, dedupe cliente/mes de cartera y anulados (`private.cierre_externo_anulado`). Una RPC de pantalla puede: llamar al núcleo, recortar por ámbito, agrupar columnas ya calculadas y formatear payload. No puede: contar `resultado='convertido'`, `etapa='convertido'` ni `contrato_id is not null` y dividirlo. Se hace cumplir con un gate doble en `test-conversion-mensual.sql`: (a) sobre `pg_proc`, toda función de esquema `crm` cuyo `prosrc` contenga la clave `conversion` en su payload debe tener `strpos(prosrc, 'conversion_mensual_por_vendedor') > 0` o `strpos(prosrc, 'conversion_episodios') > 0` (nunca `LIKE`: el guion bajo es comodín); (b) grep de migraciones nuevas que rechace `etapa = 'convertido'` o `resultado = 'convertido'` junto a una división fuera de ficheros del núcleo.

## 2. Evolución del núcleo

Nueva función **`private.conversion_episodios(p_ini timestamptz, p_fin timestamptz, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)`**, set-returning, una fila por lead-episodio y por operación de cartera elegible: `(analista_id, lead_id|operacion_id, fue_referido, cerrado, anulado, mes_origen, origen, categoria, monto, moneda, fecha_divisor=asignado_en, fecha_numerador=resultado_en, aporte_divisor 0|1, aporte_numerador ya ponderado con p_factor y ya en 0 si anulado)`. `p_periodo` explícito desancla el mes de `p_ini` (limitación (a) de la ficha): rango de 45 días, semana o trimestre pasan `p_periodo` para arrastre/cartera o NULL para omitir esa pierna.

`private.conversion_mensual_por_vendedor` se **redefine como `GROUP BY analista_id` sobre esa relación**, con test de paridad byte a byte del payload antes/después (test-conversion-mensual.sql + gate:realidad). Embudo, orígenes, montos, tendencia semanal y la ventana 45 d son `GROUP BY origen|categoria|width_bucket(monto)|date_trunc('week', fecha_divisor)` encima. No puede divergir porque los consumidores solo **suman columnas ya calculadas**: el factor, el filtro de anulados y el dedupe cliente/mes se computan una sola vez en la relación base; nadie vuelve a escribir esa aritmética.

## 3. Migraciones (orden de despliegue)

| # | RPC | CTE que se borra | Sustituto | Payload | Riesgo | Test |
|---|-----|------------------|-----------|---------|--------|------|
| 1 | (nueva) `private.conversion_episodios` | — | — | interno, sin grants | bajo | test-conversion-mensual.sql (paridad) |
| 2 | `private.conversion_mensual_por_vendedor` | sus CTE `recibidos`/`cierres`/`agg_ops` | agregación de episodios | idéntico byte a byte | medio (toca cierre de mes) | paridad + gate:realidad |
| 3 | `private.metricas_conversiones_implementacion` | cohorte por `l.creado_en` + `h_contrato` (numerador muerto: contrato_id=0) | GROUP BY episodios (cohorte por asignación; cerrado del ledger) | aditivo: mismas claves, `conversion_contratos_pct` pasa a valer algo real | **alto**: el texto vigente solo existe en caliente (parche 20260824170630) → migración previa que fije el prosrc con preflight md5 | test-rls.mjs + gate:realidad |
| 4 | `crm.metricas_conversiones_equipo_fn` | cohorte `creado_en`+`contrato_id` (20260810024404:287-306) | GROUP BY episodios recortado a subárbol | conserva `responsables{vendedor_id, leads, clientes, conversion_pct}` | medio: cifras cambian (hoy 0%) | test-rls.mjs |
| 5 | `crm.metricas_distribucion_leads_v2_fn` (y v1) | cohortes convertidos/descartados de `metricas_distribucion_leads_core` (20260717224252:204-244) | GROUP BY episodios por rango; **añade** pct servidos (`conversion_pen_pct`…) | pares convertidos/descartados se conservan (strictObject) | bajo: ya va por ledger | test-rls.mjs |
| 6 | `crm.metricas_vendedores_fn` + `crm.resumen_cartera_fn` + `crm.series_comerciales_fn` | conteos `etapa='convertido'` por dueño actual (20260809144920:558-568, 171-183, 741-760) | episodios con `p_ini = now()-45d` / por mes de asignación | `conversion_pct` conserva nombre; añade `numerador`/`divisor` | **alto semántico**: stock→cohorte, los números cambian (decisión 1) | test-rls.mjs + gate:realidad |
| 7 | `private.metricas_reuniones_implementacion` | `metrica_conversion_cliente/contrato` sobre perfil_id/contrato_id (20260805180000:1026-1038) | join reuniones × episodios: `cerrado and fecha_numerador >= vence_en` | claves iguales | medio | test-rls.mjs |
| 8 | `crm.cumplimiento_metas_fn` / `crm.conversion_mensual_fn` / `crm.cerrar_periodo` | ninguna (ya consumen núcleo — patrón Migración B) | heredan la redefinición del paso 2 | sin cambio | bajo | paridad |

`crm.metricas_agenda_fn` y `crm.resumen_reparto_fn` no migran: no calculan conversión de ventas.

## 4. contrato_id

**Recomendación: abandonarlo como numerador y medir por ledger (`resultado='convertido'`) + `perfil_id` como señal de cliente, como ya hace el núcleo.** Pros: el ledger ya cubre cooperativas (que jamás tendrán contrato Avance), integra anulaciones y está probado en prod. Contras de rellenarlo: backfill de 371 contratos + escribirlo en dos flujos (edge `crm-convertir-lead` y alta de contrato) para seguir midiendo peor. La columna se declara obsoleta para métricas en una nota del vault.

## 5. Front

Se eliminan (o quedan solo-demo/borrados): `lib/distribucion-lecturas.ts:206-211` `conversionLegible` y `:254-256` `pctNumerico` (el pct llega servido; `porcentajeLegible` queda como formateador), `lib/conversion-vendedores.ts:133-165` `agregarTendenciaSemanal`, `lib/objetivos.ts:398-427` `agregarCumplimientos.conversionReal` (sin pintor desde 2026-08-13), `screens/hoy/equipo-gerencia.tsx:132-142` `conversionGrupo` (el servidor añade agregado por supervisor), `distribucion-leads-gerencia.tsx:341-345` suma USD en cliente, `directorio.tsx:131` `tasaDescarte`, y los huérfanos `cierres-del-mes.ts:88-105`, `series-comerciales.ts:96-98`, `inteligencia.ts:686-815`, `resumen-cartera.ts:146-176`. **Se quedan**: `pctMeta` (`inteligencia.ts:99-100`, avance vs meta, no conversión) y los anchos relativos de barras (presentación). El front nunca divide porque ya divergió dos veces (comentario `resumen-gerencia.tsx:175`: «dos fórmulas distintas»; redondeo `Math.round` vs half-up de Postgres; 0% fabricado vs null). Rótulos: «Conversión · 45 días» pasa a decir «cohorte por asignación · 45 días»; la pantalla Conversiones deja de rotular contratos.

## 6. Sondas de coherencia

Bloque `sondas` en cada payload: (a) `sum(responsables.numerador) == total.numerador` y lo mismo para divisor; (b) `episodios_sin_origen` (filas con origen null); (c) `paridad_nucleo`: diferencia entre el pct mensual y el recomputado desde episodios (debe ser 0); (d) cobertura del ledger (min `asignado_en` no aproximado, ya existe como `lecturaCobertura`). El front, si una sonda falla, pinta banner ámbar «cifras en revisión» y oculta el número — jamás lo fabrica ni promedia.

## 7. Orden de despliegue

1. **Servidor aditivo**: migraciones 1-2 (episodios + redefinición con paridad), luego 3-7 añadiendo claves sin renombrar ninguna (strictObject). Puede ir ya, vía `aplicar-*-prod.sh` con OK de Miguel.
2. **Front**: consumir pct servidos, borrar divisiones, rótulos. **Bloqueado hasta integrar las dos ramas** (`b3f6e98` no es antepasado de `wip/workspace-20260823-completo`): publicar antes borra «Hoy del supervisor».
3. **Retirar lo viejo**: claves obsoletas y helpers muertos, solo con el front nuevo verificado vivo por hash. No paralelizable: 3 con front viejo rompe strictObject; 2 no puede adelantarse a 1 porque las claves nuevas no existirían.

## 8. Decisiones de Miguel (máx. 5)

1. **¿Cambia la «Conversión · 45 días» de stock a cohorte del ledger?** Los números del equipo cambiarán. *Recomendado: sí — un solo idioma; avisar al equipo el día del corte.*
2. **Numerador de la pantalla Conversiones**: ¿cierres del ledger (recomendado) o rellenar `contrato_id`? *Recomendado: ledger (sección 4).*
3. **Denominador «resueltos» de Distribución** (convertidos+descartados): ¿se conserva como segunda lectura rotulada, servida del mismo núcleo? *Recomendado: sí — son preguntas distintas, misma fuente.*
4. **Secuencia**: ¿servidor ahora y front tras integrar ramas, o congelar todo hasta la integración? *Recomendado: servidor ahora (es aditivo e invisible).*
5. **Fijar `metricas_conversiones_implementacion`**: migración que congele el texto vivo (hoy solo existe en caliente) antes de reescribirla, con preflight md5. *Recomendado: sí, primera migración del paquete.*
---

# Anexo: ficha del núcleo actual

## Núcleo vigente

**`private.conversion_mensual_por_vendedor`** — última redefinición: `supabase/migrations/20260824231133_crm_gestion_clientes_renovaciones_conversion.sql:738` (pisa la de `20260812000259:1728`).

- **Firma** (l.738–758): `(p_ini timestamptz, p_fin timestamptz, p_global boolean, p_visibles uuid[], p_factor numeric)` → `TABLE(analista_id uuid, divisor int, divisor_aproximado int, divisor_por_motivo jsonb, cierres_no_referidos int, cierres_referidos int, cierres_de_arrastre int, numerador numeric, conversion_pct numeric, procedencia jsonb, referidos_recibidos int, referidos_aporta_pct numeric)`. plpgsql `stable security definer, search_path=''`; EXECUTE revocado a TODOS (l.879) — solo llamable desde otras DEFINER.
- **Aritmética**: divisor = leads no-referidos de `crm.lead_asignaciones.asignado_en` en `[p_ini,p_fin)`; numerador = `cierres_no_referidos + p_factor·cierres_referidos + conversiones_clientes` (l.858–864). Desde el 24-08 suma `agg_ops`: máx. 1 fila de `crm.operaciones_cartera` con `elegible_conversion` por cliente/mes (l.807–819); el divisor sigue saliendo solo del ledger de leads.
- **Anulaciones**: filtra cierres con `not private.cierre_externo_anulado(la.lead_id)` (l.787), delegado de una línea a `private.cierre_anulado` (`20260813235119:185–224`), que cubre AMBOS canales: coop (`crm.cierres_externos.anulado_en`) y Avance (`crm.cierres_avance_anulados`). Los cierres en cooperativas cuentan porque escriben episodio `resultado='convertido'` en `lead_asignaciones` (`20260812000259`). Anulación post-sello se descuenta en la LECTURA (`ajuste_pendiente_por_vendedor` + `conversion_con_ajuste`, `20260815003742:349–376`), no en el núcleo (doble descuento).

## Caller público

**`crm.conversion_mensual_fn(p_periodo date) returns jsonb`** — vigente en `20260824231133:890`: envoltorio que llama a `crm.conversion_mensual_sin_cartera_fn` (la definición de `20260815003742:103`, renombrada en l.884) y le injerta bloque `cartera` por responsable + estado `solo_arrastre`. El caller real (`20260815003742:283–291`) fabrica los parámetros:

- `v_ini/v_fin`: bordes del mes en Lima — `p_periodo::timestamp at time zone 'America/Lima'` (l.288–289); valida primer día de mes y no-futuro (l.143–151).
- `v_global` = gerencia (`private.rol_crm`, vigente `20260807203740:74`) o `es_lector_global()`; `v_visibles` = `'{}'` si global, si no `private.vendedor_ids_visibles(v_uid)` (vigente `20260803164348:38`) — supervisor→equipo, vendedor→él mismo.
- `v_factor` = `private.peso_referido_conversion(p_periodo)` (`20260811154434:438–471`), que lee `crm.conversion_pesos` (mayor `vigente_desde<=mes`, fallback al más antiguo, error 55000 si vacía; semilla 0.150).
- Las filas se cuelgan del roster `private.roster_metas_vendedores()` (`20260810163458:41`); lo producido fuera va a `fuera_de_roster`. Mes sellado: sirve la foto de `crm.periodos_cerrados`, no calcula.

## Limitaciones para otras pantallas

**(a)** Paramétricamente acepta rango libre, pero semánticamente está anclado al mes: deriva `mes_periodo`, arrastre, procedencia y el `periodo` de cartera con `date_trunc('month', p_ini)` (l.782–783, 812) — un rango de 45 d o semanal daría cartera y arrastre incoherentes. El wrapper público es estrictamente mensual.

**(b)** Solo por vendedor. Desgloses existentes: `divisor_por_motivo` (motivo_apertura) y `procedencia` (mes de origen). Nada por origen (solo binario referido/no), categoría, monto ni semana; no devuelve filas por lead.

**(c)** Haría falta una variante set-returning **por lead/operación**: `(lead_id|operacion_id, analista_id, aporte_divisor, aporte_numerador ya ponderado y ya filtrado de anulados, fue_referido, origen, motivo, monto/moneda, fecha_divisor, fecha_numerador)`, más desanclar el mes (pasar `p_periodo date` explícito en vez de derivarlo de `p_ini`). Embudo, orígenes, distribución por monto, tendencia semanal y la ventana 45 d agregarían esa relación por cualquier dimensión reutilizando factor, anulaciones y regla cliente/mes sin duplicar la aritmética.