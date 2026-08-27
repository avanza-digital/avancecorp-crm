---
tags: [crm, conversion, plan, en-ejecucion]
actualizado: 2026-08-27
estado: TODO EN PRODUCCION 27/08 - F0..F2.6 servidor + F3 front PUBLICADO (39.º release, verificado por hash) - queda SOLO F3.5 (retirada de claves viejas)
---

# Conversión única en todo el CRM — plan de migraciones

Plan para que **todas** las conversiones del CRM (vendedor, supervisor,
gerencia) salgan de **un solo núcleo** en el servidor, como pidió Miguel el
2026-08-26. **F0, F1 y F2 (incluida 2.3b) están EN PRODUCCIÓN al 27/08**;
queda F3 (front).
Verificado adversarialmente contra el repo antes de presentarse (4 lentes,
16 correcciones aplicadas — run `wf_4a2c07a4-480`).

Insumos ya cerrados (no re-derivar):
[[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]] (causa raíz y
motores) · [[Auditoria conversion CRM - informe final gerencia (2026-08-26)]]
(22 inconsistencias confirmadas adversarialmente) ·
[[Auditoria conversion CRM - inventario y diseno de unificacion (2026-08-26)]]
(41 funciones SQL, 55 cálculos en el front, borrador técnico). Continúa el
patrón de [[Conversion mensual - plan de implementacion]] (su Migración B ya
unificó metas con el núcleo; este plan replica ese movimiento en el resto).

## El problema, en 3 líneas

1. Hoy hay **6 fórmulas distintas** respondiendo a la palabra "conversión" en
   pantallas diferentes, más un séptimo conteo de "Convertidos". Por eso HOY
   puede decir 100 % y Conversiones 0 % el mismo día.
2. El 0 % de Conversiones es **estructural**: mide una columna
   (`crm.leads.contrato_id`) que nadie escribe (371 contratos, 0 enlazados).
3. El navegador además **divide por su cuenta** en 55 sitios, con redondeos y
   ventanas propias — cada uno puede contradecir al servidor.

## El principio del plan

**La aritmética de conversión se escribe UNA vez, en el servidor.** Se crea
una tabla-base interna (una fila por lead y por operación de cartera, con sus
banderas: referido, cerrado, anulado, mes de origen, origen, monto, semana).
Todas las pantallas — héroe de HOY, embudo, orígenes, distribución, 45 días,
reuniones, tendencia semanal — pasan a ser **solo agrupaciones** encima de esa
base. Ninguna pantalla puede volver a contar cierres por su cuenta: un vigía
automático lo impide. El front **nunca divide**: recibe el % ya calculado, y
si algo no cuadra pinta un aviso, jamás un número inventado.

## Estado del plan — 2026-08-26

| Fase | Estado |
|---|---|
| **F0** · anclar el texto vivo de Conversiones | ✅ **EN PROD** (2026-08-26, `20260826211500`; banco + auditor RLS + Codex; md5 `906afdec…` intacto) |
| **F1** · la tabla-base (`conversion_episodios`) + núcleo encima, con paridad byte a byte | ✅ **EN PROD** (2026-08-26/27, `20260826233000`; banco 6 llamadas + oráculo + 4 mutantes · auditor RLS · Codex 2 refutaciones cerradas · paridad EN PROD idéntica) |
| **F2** · los 5 motores paralelos pasan a consumir el núcleo | ✅ **COMPLETA EN PROD** (2026-08-27): 2.1 Conversiones · 2.2 Ranking · 2.3a Distribución · 2.4+2.4b cartera/equipo/series · 2.5 Reuniones. Vigía en prod: **los 7 motores consumen la tabla-base** |
| **F3** · front: consumir % servidos, borrar divisiones, rótulos; retirar lo viejo | ⛔ **bloqueada por la integración de ramas** ([[ramas-paralelas-crm]]): publicar front desde esta rama borraría «Hoy del supervisor» |

**Cero código escrito.** Reglas no negociables: ninguna migración se escribe
sin el OK explícito de Miguel a este plan. Cada migración se **ensaya antes
fuera de producción** (branch de Supabase con la receta de replay manual de
[[banco-branch-replay-manual]], o Postgres local con stubs del catálogo y
anclas `md5(prosrc)` local↔prod — patrón del ledger, `MIGRACIONES.md:1460`),
pasa `auditor-rls` → `test-rls.mjs`, se aplica con `aplicar-*-prod.sh` con OK
explícito (el merge de branches de Supabase sigue roto desde el 13/08), se
re-verifican los advisors tras aplicar, y **queda registrada en
`MIGRACIONES.md`** con hash y verificación en vivo (el ledger ya mintió una
vez — [[llave-mundo-leads-abierta]] — por eso es gate, no cortesía).

## El plan en tablas (lectura rápida)

### Tabla 1 — Las cuatro fases, en orden

| Fase | Qué hace, en idioma de negocio | Riesgo |
|---|---|---|
| **F0** | La función de la pantalla Conversiones fue parcheada "en caliente" el 24/08: su fuente completo **no existe en ningún fichero del repo**. F0 es una migración **NUEVA** que congela ese texto vivo con verificación de huella antes/después (la migración del 24/08, `20260824170630`, **no se edita jamás**). Así, lo que se reescriba en F2 será exactamente lo que corre en producción. | bajo |
| **F1** | Nace la tabla-base `private.conversion_episodios` (interna, sin acceso directo de nadie) y el núcleo actual se **redefine como una agrupación encima de ella**. El resultado debe ser idéntico byte a byte al actual — hay prueba de paridad. Si la paridad falla, no se avanza. Metas, cierre de mes y alertas individuales **heredan** el cambio sin tocarse (ya consumen el núcleo). | medio (toca la función del cierre de mes; la paridad lo contiene) |
| **F2** | Los 5 motores que hoy calculan por su cuenta pasan a agrupar la tabla-base: Conversiones (deja de medir la columna muerta → por fin muestra números reales), equipo, distribución, vendedores/cartera/series (la ventana 45 días), reuniones. No se renombra ninguna clave (la app publicada dejaría de funcionar) y, en la pantalla Distribución, **tampoco se puede añadir ninguna**: su parte visible va en dos tiempos (ver F2.3). | **alto en cifras**: los números CAMBIAN a la definición buena y **se verán bajo los rótulos viejos hasta F3** (decisiones D1–D3, D6, D7) |
| **F3** | El front consume los % servidos, se borran las divisiones locales, se corrigen los rótulos (cada cifra dice su base y su ventana), y al final se retiran las claves viejas del payload. | bloqueada hasta integrar ramas |

### Tabla 2 — Qué inconsistencia del informe arregla cada fase

| Hallazgo ([[Auditoria conversion CRM - informe final gerencia (2026-08-26)\|informe]]) | Se arregla en | Cómo |
|---|---|---|
| H3 · Conversiones da 0 % siempre | F2 | numerador pasa de `contrato_id` (muerto) al ledger de cierres (D2) |
| H8, H17, H18 · Distribución contradice a Rendimiento | F2 **+ F3** | mismo núcleo y sin anulados (F2); pero si D3 conserva la segunda lectura, los dos % siguen siendo distintos POR DISEÑO y solo el rótulo de F3 los reconcilia |
| H9, H19, H20 · la ventana «45 días» mide otra población | F2 | pasa al mes calendario del núcleo (D1 decidida): mismo número que HOY/Ranking; el rótulo «45 días» se corrige en F3 |
| H10, H11 · las alertas se contradicen entre sí y con el ranking | F2 **+ F3** | ambas leen el núcleo (F2); la ventana distinta y el "no se refresca desde el arranque" son del front (F3) |
| H12 · tendencia semanal vs meta | F2 **+ F3** | los insumos salen de la tabla-base (F2), pero la división local del navegador (`conversion-vendedores.ts:162`) sigue viva hasta F3 |
| H13, H16 · «por origen» y reuniones al 100 % vs referidos al 15 % | F2 + F3 | mismos episodios ponderados + rótulo; la fila «Referido» necesita la decisión D6 |
| H2, H4, H5, H7 · ventanas/cohortes mezcladas sin rótulo | F2 + F3 | una sola cohorte; el mes se nombra en pantalla |
| H1, H15 · «N cierres de M» no cuadra con el % | F3 | desglose legible bajo el %: cierres + referidos×0,15 + renovaciones − anuladas |
| H6 · dos gráficas homónimas | F2 | tras F2 son la misma fórmula |
| H14 · «Clientes» vs «Capital» | F3 | son universos legítimamente distintos → rótulo, no recálculo |
| H21 · umbral de la alerta invisible | F3 | el corte «≥10 recibidos» se dice en el texto de la alerta |
| H23 · tile vs chip de Pipeline | F3 | el chip deja de contar en el navegador |
| N1 · ruta «Capital» muerta | F3 | limpieza de menú/componente |

> ⚠️ Las filas con F3 **siguen visibles para el equipo hasta integrar las
> ramas** (sin fecha). Es el costo del orden servidor-primero que decide D4.

### Tabla 3 — Qué se prueba antes de dar nada por bueno

| Garantía, en idioma de negocio | Qué asegura |
|---|---|
| **La misma foto, antes y después** (prueba de paridad) | F1 no cambia NI UN número de lo que ya está en producción (metas, cierre de mes, héroe) |
| **Vigía automático** | ninguna pantalla puede volver a calcular la conversión por su cuenta; si alguien lo intenta en una migración futura, la prueba falla (mecánica en «Detalle por fase») |
| **Las cuentas cuadran solas** (sondas) | la suma por vendedor debe cuadrar con el total; si no cuadra, la pantalla avisa «cifras en revisión» — nunca muestra un número inventado |
| **Ensayo fuera de producción** | cada migración corre antes en un banco de pruebas (branch de Supabase o Postgres local anclado por huella a prod) |
| **Revisión de seguridad** (`auditor-rls` + `test-rls.mjs` + advisors) | permisos y visibilidad por rol intactos en cada migración; advisors re-verificados tras aplicar |
| **Se reescribe solo lo que corre vivo** (huellas md5 en F0 y en cada función que se pisa) | no se toca a ciegas nada distinto de producción ([[Un parche que solo vive en el artefacto no existe\|lección del 19/08]]) |
| **Cuaderno de bitácora** (`MIGRACIONES.md`) | cada migración aplicada queda registrada con su huella y su verificación en vivo |
| **`gate:realidad`** | todo probado contra el estado real de producción (base casi vacía) |

### Tabla 4 — Las decisiones de Miguel (las 8, todas resueltas)

| # | Decisión | Recomendación |
|---|---|---|
| **D1** | ¿Qué mide la columna de conversión de Gestión de equipo? | ✅ **DECIDIDA (Miguel, 26/08): MES CALENDARIO con la aritmética del núcleo** — el mismo número que HOY/Ranking/Metas; la ventana de 45 días desaparece de la MÉTRICA (era herencia de la regla de limpieza de cartera del 08/08, que sigue intacta para la VISTA). El rótulo «· 45 días» queda mintiendo hasta F3 |
| **D2** | Pantalla Conversiones: numerador muerto → ledger, y ¿qué pregunta responde? | ✅ **DECIDIDA (Miguel, 26/08): NÚCLEO + foto por cosecha rotulada** — cifra principal = flujo del mes del núcleo (mismo número que HOY/Ranking/Metas); segunda cifra «por cosecha» (de los que entraron en el rango, cuántos cerraron — para juzgar lotes de leads al madurar), servida de la MISMA tabla-base. La cosecha viaja como clave aditiva en F2 (schema tolerante) pero solo se VE en F3 |
| **D3** | ¿Se conserva «cierra el X % de lo que resuelve» (puntería: cerrados ÷ resueltos) como segunda lectura de Rendimiento? | ✅ **DECIDIDA (Miguel, 26/08): SE CONSERVA** — corregida en F2 (misma tabla-base, sin anulados) y con rótulo claro en F3 («de los leads que terminó de trabajar, ganó el X%»). Detecta el descarte a la ligera |
| **D4** | Secuencia: ¿servidor ahora (F0–F2) y front al integrar las ramas, o congelar todo hasta la integración? **Ojo: servidor-ahora NO es invisible** — el equipo verá números nuevos bajo rótulos viejos (Conversiones pasará de 0 % a cifras reales diciendo todavía «clientes»; el 45 días cambiará de población) durante un periodo sin fecha de cierre. | ✅ **DECIDIDA (Miguel, 26/08): servidor ahora, transición aceptada** — números nuevos bajo rótulos viejos hasta integrar ramas; comunicarlo al equipo el día del corte |
| **D5** | ¿F0 (congelar el texto vivo de Conversiones) como primera migración del paquete? | ✅ **DECIDIDA (Miguel, 26/08): SÍ, F0 primero** — migración nueva con verificación de huella, cero efecto en pantallas |
| **D6** | La barra «Referido» de «Conversión por origen»: en el núcleo los referidos no tienen divisor, su % por origen es indefinido. | ✅ **DECIDIDA (Miguel, 26/08): opción (c), % propio rotulado** — «de los referidos recibidos, cerró el X%» (cierres de referidos ÷ referidos recibidos), rótulo propio en F3 para no confundirlo con la conversión general |
| **D7** | Con renovaciones y arrastre, un mes normal puede superar el 100 %. ¿Se capa, y dónde? | ✅ **DECIDIDA (Miguel, 26/08): SIN TOPE** — número Y barra se muestran tal cual (120 % = barra de 120), igual en TODAS las pantallas; HOY deja de capar su barra. Nada se esconde |
| **D8** | El total de HOY excluye la parte fuera de roster (7,03 %) mientras los motores F2 la incluyen (7,22 %). ¿Quién cede? | ✅ **DECIDIDA (Miguel, 27/08): SE INCLUYE** — y **F2.6 EN PROD el mismo día** (`20260827154448`, registro fiel byte a byte): el `total` del mes abierto suma el agregado fuera de roster y HOY == núcleo, **medido: 39,75/569 = 6,99 % en ambos** (el 7,22 % era la foto del 26/08). `cobertura.fuera_de_roster` sigue declarándose; responsables byte-idénticos; ex-roster sin identidad. Detalle y verificación en el ledger `MIGRACIONES.md` |

## Detalle por fase (técnico, para ejecutar tras el OK)

### F0 — Anclar `private.metricas_conversiones_implementacion`

**Migración NUEVA** (fichero nuevo `AAAAMMDDHHMMSS_crm_*.sql`;
`20260824170630` no se edita jamás — regla de la casa). Contenido: (1)
preflight que verifica por md5 (`pg_get_functiondef`) que el texto vivo es el
esperado, (2) `create or replace` con ese texto íntegro ya materializado (el
resultado del `replace()` dinámico de `20260824170630:231-273`, leído de
producción), (3) re-verificación md5. Sin cambio funcional. A partir de ahí
el repo vuelve a ser la verdad del fuente.

### F1 — `private.conversion_episodios` + núcleo por agrupación

Nueva `private.conversion_episodios(p_ini timestamptz, p_fin timestamptz,
p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)`,
set-returning: una fila por lead-episodio del ledger
(`crm.lead_asignaciones`) y por operación de cartera elegible
(`crm.operaciones_cartera`, máx. 1 por cliente/mes), con
`analista_id, lead_id|operacion_id, fue_referido, cerrado, anulado
(private.cierre_anulado — ambos canales), mes_origen, origen, categoria,
monto, moneda, fecha_divisor = asignado_en, fecha_numerador = resultado_en,
aporte_divisor 0|1, aporte_numerador` (ya ponderado con `p_factor`, ya 0 si
anulado). `p_periodo` explícito desancla el mes del rango (hoy el núcleo
deriva el mes con `date_trunc('month', p_ini ...)` para arrastre —
`20260824231133:781`, vía `mes_origen < mes_periodo` en `:805` — y para la
pierna de cartera — `:814` — por eso no sirve rangos de 45 d ni semanas):
rangos libres pasan su `p_periodo` o NULL para omitir esa pierna.
`security definer, search_path=''`, EXECUTE revocado a todos (patrón del
núcleo actual, `20260824231133:880`).

`private.conversion_mensual_por_vendedor` se redefine como `GROUP BY
analista_id` sobre esa relación. **Test de paridad byte a byte del payload de
`crm.conversion_mensual_fn` y `crm.cumplimiento_metas_fn` antes/después** en
`test-conversion-mensual.sql`; la anulación post-sello sigue descontándose en
la lectura (`conversion_con_ajuste`), no en el núcleo (doble descuento).

**Vigía automático (mecánica)**: en el mismo script, (a) sobre `pg_proc`,
toda función de `crm.*` con `conversion` en su payload debe tener
`strpos(prosrc, 'conversion_mensual_por_vendedor') > 0` o
`strpos(prosrc, 'conversion_episodios') > 0` — nunca `LIKE`
([[En LIKE el guion bajo es COMODÍN\|el guion bajo es comodín]]); (b) grep de
migraciones nuevas que rechace `etapa = 'convertido'` o
`resultado = 'convertido'` junto a una división fuera de los ficheros del
núcleo.

### F2 — Los cinco motores, uno por migración, en este orden

| # | Función | Qué CTE muere | Qué la sustituye | Nota |
|---|---|---|---|---|
| 2.1 | `private.metricas_conversiones_implementacion` (pantalla Conversiones + KPIs/gráficas de HOY) | cohorte por `creado_en` + numerador `contrato_id` | GROUP BY episodios (cohorte asignación, cierres del ledger — D2) | payload aditivo (su schema del front tolera claves nuevas); `conversion_contratos_pct` pasa a valer algo real (H3). Las ventanas de CONTRATOS/capital (`fecha_cierre_comercial`, H14) NO se tocan: miden contratos, no conversión. La fila «Referido» de orígenes según D6 |
| 2.2 | `crm.metricas_conversiones_equipo_fn` (Ranking) | ídem (`20260810024404:287-306`) | GROUP BY episodios recortado al subárbol | conserva `responsables{...}`; aditivo tolerado por su schema |
| 2.3a | `crm.metricas_distribucion_leads_v2_fn` (+v1) — **solo reemplazo interno** | cohortes de `metricas_distribucion_leads_core` (`20260717224252:204-244`, con anulados) | GROUP BY episodios por rango, **payload idéntico byte a byte** (paridad como F1) | ⛔ **el bundle vivo (`b3f6e98`) valida este payload a cierre hermético** (`v.strictObject` en todos los niveles, `metricas-distribucion.ts:225`): una clave NUEVA también lo rompe, no solo renombrar. Lección [[crm-orden-deploy-front-primero]]: clave nueva en RESPUESTA → front primero. Aquí sí se excluyen los anulados (H17): cambio de VALOR, no de forma |
| 2.3b | ✅ **EN PROD** (`20260827090000`): RPC **v3** (`crm.metricas_distribucion_leads_v3_fn`) que el bundle vivo jamás llama | — | v2 + `conversion{pen,usd}` (puntería 6 decimales, pct NULL sin resueltos) + `nucleo_*` + `sondas` por analista/rango/resumen | v1/v2 byte-idénticas (foto antes/después); mes real: núcleo 7,22 % con paridad 0; `nucleo_sin_ficha:1` ya caza un caso real. Rollback ensayado (`rollback-f2-3b-distribucion-v3.sql`) |
| 2.4 | `crm.metricas_vendedores_fn` + `crm.resumen_cartera_fn` + `crm.series_comerciales_fn` | conteos `etapa='convertido'` por dueño actual (`20260809144920:558-568`) | episodios del MES CALENDARIO (D1 decidida: sin ventana 45d en la métrica) / por mes | los números cambian; añade `numerador`/`divisor` (schemas tolerantes) |
| 2.5 | `private.metricas_reuniones_implementacion` | `metrica_conversion_cliente/contrato` (`20260805180000:1026-1038`) | join reuniones × episodios | «Terminan en cliente» pasa a medir cierres del ledger |

No migran: `crm.metricas_agenda_fn`, `crm.resumen_reparto_fn` (no calculan
conversión de ventas) ni `crm.cumplimiento_metas_fn` /
`crm.conversion_mensual_fn` / `crm.cerrar_periodo` (ya consumen el núcleo —
heredan F1 sin tocarse).

Cada payload de F2 viaja con el bloque `sondas` — `sum(por vendedor) ==
total` (numerador y divisor), `episodios_sin_origen`, `paridad_nucleo`
(diferencia entre el % mensual y el recomputado desde episodios; debe ser 0)
y la cobertura del ledger que ya existe como `lecturaCobertura` — **salvo
Distribución**, cuyas sondas llegan en 2.3b.

### F3.1–F3.4 — ESCRITAS Y COMMITEADAS el 27/08 (sin publicar)

Cuatro commits en `wip/workspace-20260823-completo`, suite completa verde
(2249 tests) y `npm run check` entero (lint, typecheck, cobertura, build,
verify:bundle, dup):

- `4bfc168` — **Distribución sobre la v3**: schema `strictObject` V3 escrito
  desde el payload real (154 caminos medidos por la cadena viva), fetcher y
  hook en `data/metricas-distribucion-v3.ts` (fichero propio: `crm-api`/
  `crm-queries` son zona de conflicto), puntería servida en fichas/rangos/
  resumen/candidatos, orden «cierres» por el pct servido (con mutante), suma
  USD al servidor, carta del núcleo con la red de sondas (cuadra=false →
  banner ámbar y cifra oculta; cuadra=null → nota neutra «elige Este mes»;
  `nucleo_sin_ficha`>0 → aviso sin ocultar, que HOY caza en prod). Demo V3.
- `76d54cd` — **las otras divisiones**: tendencia semanal del equipo pasa a
  enteros servidos (recibidos y cierres, sin % fabricado ni meta mensual
  cruzada — H12); cabecera por supervisor en Gestión de equipo sin división
  (cierres · recibidos servidos); tasa de descarte del directorio retirada;
  schemas ganan `ventana_metrica`/`mes_metrica`/`operaciones_cartera`.
- `091f05e` — **F3.3**: fuera `embudo()`, `conversionPorOrigen()` y
  `conversionGlobal()` (huérfanos; `estancados()` se quedó — lo usa
  cola-accion); `agregarCumplimientos` ya no recalcula conversión (tipo nuevo
  `CumplimientoAgregado`, mutante vigilado); entrada «Capital» fuera del
  sidebar (N1 parcial: App.tsx/topbar/router tras integrar).
- `87a6dd1` — **Conversiones al núcleo (D2) + F3.4**: héroe con la cifra del
  núcleo y desglose H1, cosecha como segunda lectura, banner por sondas, D6
  rotulado en Conversiones y Resumen, H23 (chips de Pipeline leen el resumen
  servido), schema de Conversiones con nucleo/cosecha/sondas/claves D6.

**Hallazgos del gate de realidad (cadena viva, 27/08 de noche):**
1. 🔴 **HOY y los motores F2 ya NO dicen el mismo número**: el total de
   `conversion_mensual_fn` EXCLUYE la parte fuera de roster y lo declara
   (`cobertura.fuera_de_roster`: 37,75/537 = **7,03 %**), mientras el bloque
   `nucleo` de Conversiones y la v3 de Distribución la INCLUYEN (38,75/537 =
   **7,22 %**). Es el mismo analista de `nucleo_sin_ficha: 1`. Los rótulos que
   afirmaban «la misma cifra que HOY» se corrigieron ANTES de publicarse
   («cifra única del núcleo»). ✅ **RESUELTO como D8 (Miguel, 27/08): se
   INCLUYE** — ver Tabla 4; la migración F2.6 alinea el total de HOY con el
   núcleo (7,22 %). Al publicarse el front, los rótulos podrán volver a
   afirmar identidad con HOY.
2. `resumen_cartera_fn.conversion` es una TERCERA aritmética (cierres crudos
   15/541, redondeo entero) pese a declarar `ventana_metrica: mes_calendario`
   → la tarjeta del directorio pinta los CIERRES servidos, no un % que
   contradiga al héroe. Si se quiere el % del núcleo ahí, es una clave F2.x
   nueva, no una división del front.
3. Coste v3 medido: **~75–110 ms** por llamada, ~64 KB (mes en curso, 18
   analistas). Aceptable para una pantalla solo-gerencia con caché por
   período (TanStack; la clave incluye las fechas). Deuda de medición saldada.

**Esperan a la integración de ramas** (⛔ publicar sigue prohibido):
`alertas.ts` (H10/H11 y el umbral H21), `vendedor.tsx:1353` (rótulo «45
días» del héroe), el resto de N1 (App.tsx, topbar.tsx, router), el schema
del ranking del supervisor (`metricas-conversiones-equipo.ts` — su única
pantalla, supervisor.tsx, está en conflicto), mudar el fetcher v3 a
`crm-api.ts` + `gen:types`, publicar (`/release-crm` humano) y F3.5.

### F3 — Front (plan afinado el 27/08 tras cerrar F2.3b)

> **Hallazgo que cambia la estrategia:** de los 13 ficheros que F3 toca,
> **11 NO los tocó ninguna de las dos ramas** en disputa
> ([[ramas-paralelas-crm]]). La integración pelea por Hoy/alertas/capa de
> datos, no por las pantallas de métricas. Por tanto **F3.1–F3.4 se pueden
> ESCRIBIR y probar ya** sobre esta rama; lo único que espera a la
> integración es (a) publicar y (b) los 4 ficheros de la zona de conflicto:
> `alertas.ts` (las dos alertas de conversión, H10/H11), `crm-api.ts`,
> `tipos.ts`, `database.types.ts`.

**Orden ejecutable:**
1. **F3.1 rótulos** (bajo): cada % dice base y ventana; fuera el «45 días»;
   Conversiones deja de rotular «contratos»; mes nombrado (H4/H5); umbral de
   la alerta dicho (H21); desglose del héroe (H1: cierres + referidos×0,15 +
   renovaciones − anuladas); fila «Referido» con rótulo propio (D6); sin tope
   visual (D7).
2. **F3.2 el navegador deja de dividir** (alto): los 5 sitios vivos —
   `distribucion-lecturas.ts:206-211,254-256` (además ORDENA el ranking
   «cierres» con ese número), `conversion-vendedores.ts:133-165`,
   `equipo-gerencia.tsx:132-142`, `distribucion-leads-gerencia.tsx:341-345`
   (suma USD en cliente) y `directorio.tsx:131,154`. Distribución cambia a
   la RPC **v3** con schema `strictObject` NUEVO (las claves ya están en
   prod, medidas: `conversion{pen,usd,nucleo_*}` por analista/rango/resumen
   + `sondas`).
3. **F3.3 retirar lo muerto** (medio): huérfanos REALES en `inteligencia.ts`:
   `embudo()`, `conversionPorOrigen()`, `conversionGlobal()` — ⚠️ el plan
   original listaba también `estancados()` y **NO es huérfano**:
   `cola-accion.ts:11,253` lo usa vivo para el espejo demo de la campana de
   alertas; borrarlo rompería alertas. En `objetivos.ts` solo la aritmética
   de conversión (`:405-407`, `:423-430`); el resto de `agregarCumplimientos`
   se queda (alimenta las barras de capital de 5 pantallas). Ruta «Capital»
   (N1) fuera.
4. **F3.4 la red** (bajo): si una sonda falla (`cuadra !== true`,
   `paridad_nucleo !== 0`, `nucleo_sin_ficha > 0` como aviso), banner ámbar
   «cifras en revisión» y el número SE OCULTA. El front no fabrica ceros.
   Las sondas ya viajan en los 6 payloads (2.1, 2.2, v3, 2.4, 2.4b, 2.5).
5. ⛔ **Integración de ramas** — la puerta para todo lo que sigue.
6. `alertas.ts` + capa de datos (`crm-api.ts` gana `metricasDistribucionV3`,
   `tipos.ts`, `gen:types`) sobre el árbol integrado.
7. **Publicar** (solo humano: `/release-crm`) y verificar el bundle vivo por
   hash ([[sesiones-paralelas-deploy]]).
8. **F3.5 retirada** de claves viejas del servidor — SOLO tras verificar el
   front nuevo vivo por hash.

**Trampas para quien escriba F3** (todas mordieron en F2):
- El schema nuevo de Distribución v3 es `strictObject`: escribirlo DESDE el
  payload real de prod (está medido en el ledger de `20260827090000`), no
  desde la imaginación.
- `gate-realidad` antes de dar por buena una pantalla: los tests del fixture
  lleno no prueban el mundo vacío de prod.
- `pct` puede venir **NULL** («aún no se sabe») y NO es 0 — pintarlo distinto.
- El orden «cierres» de Distribución debe ordenar por el pct SERVIDO
  (`conversion.pen.pct`), no recalcular.
- Los números de puntería servidos vienen con 6 decimales a propósito: el
  front formatea a 1 decimal con Intl y da el mismo carácter que hoy.

#### Detalle original de F3 (sigue vigente donde no contradiga lo de arriba)

- Se borran los cálculos locales **con pintor vivo**:
  `distribucion-lecturas.ts:206-211,254-256` (`conversionLegible`,
  `pctNumerico`), `conversion-vendedores.ts:133-165`
  (`agregarTendenciaSemanal`), `equipo-gerencia.tsx:132-142`
  (`conversionGrupo`), `distribucion-leads-gerencia.tsx:341-345` (suma USD en
  cliente), `directorio.tsx:131,:154` (`tasaDescarte`, pintada en `:245-247`).
- En `objetivos.ts` se borra **solo la aritmética de conversión** del
  agregado: `:405-407` (reduces de convertidos/resueltos/numerador), `:423-427`
  (`conversionReal` — sin pintor desde el 13/08) y esos campos del return
  (`:428-430`). El resto de `agregarCumplimientos` (metas, `reales` de
  capital/contratos) **se queda**: alimenta las barras de capital de cinco
  pantallas (`objetivos.ts:494-495`).
- Huérfanos reales que se borran en `inteligencia.ts`: `embudo` (`:709-716`),
  `conversionPorOrigen` (`:723-733`), `estancados` (`:742-760`),
  `conversionGlobal` (`:769-777`) — sin importador vivo fuera de tests.
  **Se quedan** `metricasPorVendedor` (`:663-700`) y `comparativaEquipos`
  (`:788-814`): los usa el espejo demo (`metricas-vendedores.ts:137-138` vía
  `use-metricas-vendedores-operativas.ts:43`).
- `resumen-cartera.ts` es **solo-demo vivo** (espejo de
  `use-resumen-cartera-operativo.ts:37`): lo específico de conversión son
  `:146-149` y `:170-176`, y solo migrarían a % servido si se decide tocar la
  demo — cosa que este plan excluye (deuda consciente N4–N6).
- **Se quedan**: `pctMeta` (`inteligencia.ts:98-99`, avance vs meta, no es
  conversión) y los anchos de barras (presentación).
- Rótulos: cada % dice base y ventana («cohorte por asignación · 45 días»);
  el desglose legible del héroe (H1); el mes nombrado (H4/H5); el umbral de
  la alerta (H21); Conversiones deja de rotular contratos; la fila «Referido»
  según D6; el chip de Pipeline deja de contar del store (H23); limpieza de
  la ruta «Capital» (N1); el cap visual según D7.
- Si una sonda falla: banner ámbar «cifras en revisión» y el número se
  oculta. El front no fabrica ceros.
- Al final, migración de retirada de claves viejas — solo con el front nuevo
  verificado vivo por hash.

## Orden de despliegue y vuelta atrás

1. **Servidor** (F0 → F1 → F2.1, 2.2, 2.3a, 2.4, 2.5): cada migración con su
   ciclo completo (ensayo en banco → auditor-rls → test-rls → aplicar con OK
   → advisors → ledger). El front viejo sigue funcionando: los schemas
   tolerantes ignoran las claves nuevas y Distribución no recibe ninguna
   (2.3a es paridad de forma).
2. **Front** (F3 + 2.3b): bloqueado hasta resolver [[ramas-paralelas-crm]].
   No negociable: publicar antes borra «Hoy del supervisor».
3. **Retirada** de claves y helpers viejos: solo tras verificar el front
   nuevo vivo por hash (lección de [[sesiones-paralelas-deploy]]).

Vuelta atrás: F1 tiene la paridad como red (si falla, se revierte la
redefinición y el núcleo anterior sigue intacto en su migración); cada F2.x
lleva su script de rollback escrito ANTES de aplicar (patrón Migración C del
plan original). F0 es su propia vuelta atrás (no cambia comportamiento).

## Riesgos aceptados

- Los números de «45 días» y de Conversiones **cambiarán** al unificar, y se
  verán **bajo rótulos viejos hasta F3** (sin fecha): no es regresión, es la
  definición buena — pero hay que comunicarlo el día del corte (D1/D2/D4).
- **El >100 % será normal, no excepcional**: renovaciones y arrastre suman
  cierres sin sumar leads recibidos (regla explícita del núcleo,
  `20260824231133:879`) — un mes con pocas asignaciones y renovaciones
  activas lo supera con naturalidad, y tras F2 aparecerá en pantallas que hoy
  nunca lo muestran. D7 decide el tratamiento. (Con divisor 0 el núcleo
  devuelve NULL y la pantalla pinta «—», no un % — `20260824231133:860`.)
- La demo enseña otro negocio (N4–N6 del informe): coherencia de la demo
  queda fuera de este plan; se anota como deuda consciente.

### F3 paquete post-integración — COMPLETO el 27/08 (6 commits, check verde)

Con las ramas integradas, el paquete congelado se ejecutó entero
(`881c56d`…`2fdccfc`, uno por ítem, árbol verde en cada uno; `npm run check`
completo al cierre):

1. **Alertas (H10/H11/H21)** — la caída global lee el bloque `nucleo` servido
   (la MISMA aritmética que la individual y que HOY; un payload sin núcleo no
   se interpreta: sin fuente no hay alerta), los textos dicen ventana y
   umbral («se avisa desde 10» / «se compara desde 30» — borde exacto ENTRA,
   testeado), y «Actualizar» de gerencia recarga también metas/cumplimiento.
2. **Tile Convertidos del vendedor** — el rótulo lee `ventana_convertidos_dias`
   del payload y dice que es la VISTA de cartera, no la conversión del mes.
3. **N1 cerrado** — `capital-cierres` fuera de VISTAS/App/topbar/sidebar/
   gerencia; bookmark viejo cae en Hoy vía `ALIAS_HEREDADO`; ruta inexistente
   sigue en null.
4. **Schema del ranking del supervisor** — claves F2.2 (`nucleo_*` por
   responsable + bloques `nucleo`/`sondas`) escritas desde el payload REAL
   medido con supervisor impersonado; aditivas (servidor viejo y demo
   degradan); caso vacío = indisponible, jamás 0 %.
5. **Fetcher v3 mudado** a `crm-api.ts`/`crm-queries.ts` (la RPC ya está
   tipada por `gen:types`, adiós el workaround `RpcCrmSinTipos`);
   `data/metricas-distribucion-v3.ts` borrado.
6. **Identidad afirmada** — el rótulo de Distribución vuelve a decir «la misma
   cifra que HOY, Metas, Conversiones y el Ranking» tras verificarla MEDIDA
   en el mismo snapshot (v3 6,99 == HOY 6,99 == Conversiones 6,99,
   `cuadra: true`).

Queda del plan: **publicar** (`/release-crm`, humano, verificar bundle por
hash) y **F3.5** (retirada de claves viejas del servidor, solo con el front
nuevo vivo). Los previews (mi-cartera, ficha 360) siguen esperando la
revisión comercial de Miguel.

### 39.º release — PUBLICADO el 27/08 (F3 completa en producción)

`crm-20260827T163659Z-5acfbcbe3cb1` (commit `5acfbcb`, SHA-256
`4eca754a…7af6a9`) publicado a crm.miavance.com vía `/release-crm` invocado
por Miguel. Smoke: index 200 · `index-B_dyKVZr.js` vivo 200 · **byte a byte
contra el dist** (index.html, index.js y `crm-api-DZHQ4wXV.js` — el chunk de
las llaves — md5 idénticos). Contiene: la integración del 38.º release
(supervisor F1–F4.4, jornada, Derivar, tel. alternativo) + F3 completa de
«Conversión única» + los dos números del lead (F4/F5) + Beneficios.
**Rollback inmediato**: el ZIP del 38.º en `releases/` (mismo paso 5).
Antes de publicar hubo que borrar duplicados «* 2.*» de Finder dentro de
`app/src` (verificados byte a byte idénticos a sus originales) y usar
`--allow-dirty` por mugre EXTERNA al CRM (public_html, notas «2» del vault).
Queda: **F3.5** (retirada de claves viejas del servidor — el front nuevo ya
está vivo y verificado por hash, la condición se cumplió).
